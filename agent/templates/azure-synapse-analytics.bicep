targetScope = 'resourceGroup'

// Parameters the user provides
@description('Azure region where the Synapse workspace will be deployed.')
param location string

@description('Name of the Synapse workspace.')
param synapseName string

@description('ADLS Gen2 storage account name. Will be created if createStorageAccount is true, otherwise must exist.')
param storageAccountName string

@description('ADLS Gen2 filesystem (container) name. Will be created if createStorageAccount is true, otherwise must exist.')
param filesystemName string

@description('Object ID of the initial Entra ID workspace admin (user or group).')
param initialWorkspaceAdminObjectId string

@description('Set to true to create a new ADLS Gen2 storage account. Set to false to use existing storage account.')
param createStorageAccount bool = true

@description('Set to true to create a new container/filesystem. Set to false to use existing container.')
param createContainer bool = true

@description('Set to true to create a managed private endpoint to the default data lake storage. Requires additional networking setup.')
param createManagedPrivateEndpoint bool = false

// Managed resource group name for Synapse-managed resources
var managedResourceGroupName = '${synapseName}-managedrg'

// ============================================================================
// ADLS Gen2 Storage Account (created only if createStorageAccount is true)
// Security best practices aligned with storage-account.bicep template
// ============================================================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = if (createStorageAccount) {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true // Required for ADLS Gen2
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowSharedKeyAccess: false // Entra ID auth only - security best practice
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled' // Change to 'Disabled' after private networking established
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob: { enabled: true }
        file: { enabled: true }
        table: { enabled: true }
        queue: { enabled: true }
      }
    }
  }
}

// Reference existing storage account when not creating a new one but need to create container
resource existingStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = if (!createStorageAccount && createContainer) {
  name: storageAccountName
}

// Blob service for new storage account
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = if (createStorageAccount) {
  parent: storageAccount
  name: 'default'
}

// Blob service for existing storage account (when creating container only)
resource existingBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = if (!createStorageAccount && createContainer) {
  parent: existingStorageAccount
  name: 'default'
}

// Container/Filesystem for new storage account
resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = if (createStorageAccount && createContainer) {
  parent: blobService
  name: filesystemName
  properties: {
    publicAccess: 'None'
  }
}

// Container/Filesystem for existing storage account
resource containerOnExistingStorage 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = if (!createStorageAccount && createContainer) {
  parent: existingBlobService
  name: filesystemName
  properties: {
    publicAccess: 'None'
  }
}

// ============================================================================
// Synapse Workspace
// ============================================================================
resource workspace 'Microsoft.Synapse/workspaces@2021-06-01' = {
  name: synapseName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    defaultDataLakeStorage: {
      createManagedPrivateEndpoint: createManagedPrivateEndpoint
      accountUrl: 'https://${storageAccountName}.dfs.${environment().suffixes.storage}'
      filesystem: filesystemName
    }

    // Networking and managed RG
    managedVirtualNetwork: 'default'
    managedResourceGroupName: managedResourceGroupName

    // Security defaults
    publicNetworkAccess: 'Enabled'

    // Entra ID admin (required when using Entra-only auth)
    cspWorkspaceAdminProperties: {
      initialWorkspaceAdminObjectId: initialWorkspaceAdminObjectId
    }

    // Entra ID only authentication for SQL
    azureADOnlyAuthentication: true

    // Keep trusted service bypass disabled by default
    trustedServiceBypassEnabled: false
  }
  dependsOn: createStorageAccount ? [container] : (createContainer ? [containerOnExistingStorage] : [])
}

// ============================================================================
// NOTE: RBAC Assignment Required (Manual Step)
// An admin with Owner/User Access Administrator role must assign 
// 'Storage Blob Data Contributor' role to the Synapse managed identity
// on the storage account for Synapse to access the data lake.
// ============================================================================

// Explicitly enforce Entra-only auth via child resource (defense in depth with current API)
resource aadOnlyAuth 'Microsoft.Synapse/workspaces/azureADOnlyAuthentications@2021-06-01' = {
  parent: workspace
  name: 'default'
  properties: {
    azureADOnlyAuthentication: true
  }
}

// Minimum TLS settings for dedicated SQL (recommended security baseline)
resource minimalTls 'Microsoft.Synapse/workspaces/dedicatedSQLminimalTlsSettings@2021-06-01' = {
  parent: workspace
  name: 'default'
  properties: {
    minimalTlsVersion: '1.2'
  }
}

// Outputs
output workspaceId string = workspace.id
output workspaceName string = workspace.name
output principalId string = workspace.identity.principalId
output storageAccountId string = createStorageAccount ? storageAccount.id : (!createStorageAccount && createContainer ? existingStorageAccount.id : '')
output storageAccountCreated bool = createStorageAccount
output containerCreated bool = createContainer
