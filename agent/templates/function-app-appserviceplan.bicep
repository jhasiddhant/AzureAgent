targetScope = 'resourceGroup'

// ============================================================================
// AZURE FUNCTION APP - APP SERVICE PLAN (Standard/Premium)
// ============================================================================
// This template creates a Function App with App Service Plan (Dedicated).
// Requirements:
// - Existing Storage Account for function content
// - Existing User Assigned Managed Identity (UAMI) with Storage Blob Data Contributor
// Configuration:
// - System Assigned MI: Enabled
// - UAMI: Used for storage access
// - App Service Plan with configurable SKU
// ============================================================================

@description('Globally unique Function App name.')
@minLength(2)
@maxLength(60)
param functionAppName string

@description('Region for the Function App.')
param location string

@description('Existing Storage Account name for Function App content.')
param storageAccountName string

@description('Existing User Assigned Managed Identity name.')
param uamiName string

@description('Runtime stack for the Function App.')
@allowed([
  'dotnet-isolated'
  'node'
  'python'
  'java'
  'powershell'
])
param runtimeStack string = 'python'

@description('Runtime version for the selected stack.')
param runtimeVersion string = '3.11'

@description('App Service Plan SKU name.')
@allowed([
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1v2'
  'P2v2'
  'P3v2'
  'P1v3'
  'P2v3'
  'P3v3'
])
param skuName string = 'S1'

@description('Number of instances for the App Service Plan.')
@minValue(1)
@maxValue(30)
param instanceCount int = 1

@description('Enable Always On for the Function App.')
param alwaysOn bool = true

// Reference existing Storage Account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// Reference blob services on the storage account
resource blobServices 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: storageAccount
  name: 'default'
}

// ============================================================================
// REQUIRED BLOB CONTAINERS
// ============================================================================
// These containers must exist before the Function App starts.
// Creating them in the template ensures they are available even when NSP
// restricts runtime auto-creation.

resource containerWebjobsHosts 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'azure-webjobs-hosts'
}

resource containerWebjobsSecrets 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'azure-webjobs-secrets'
}

resource containerDeployments 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'deployments'
}

resource containerScmReleases 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobServices
  name: 'scm-releases'
}

// Reference existing User Assigned Managed Identity
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: uamiName
}

// Get SKU tier from SKU name
var skuTier = startsWith(skuName, 'B') ? 'Basic' : startsWith(skuName, 'S') ? 'Standard' : 'PremiumV2'

// Determine linux fx version based on runtime stack
var linuxFxVersion = runtimeStack == 'python' ? 'PYTHON|${runtimeVersion}' : runtimeStack == 'node' ? 'NODE|${runtimeVersion}' : runtimeStack == 'dotnet-isolated' ? 'DOTNET-ISOLATED|${runtimeVersion}' : runtimeStack == 'java' ? 'JAVA|${runtimeVersion}' : 'POWERSHELL|${runtimeVersion}'

// ============================================================================
// APP SERVICE PLAN (Dedicated)
// ============================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${functionAppName}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: skuName
    tier: skuTier
    capacity: instanceCount
  }
  properties: {
    reserved: true // Linux
  }
}

// ============================================================================
// FUNCTION APP (App Service Plan)
// ============================================================================

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      alwaysOn: alwaysOn
      appSettings: [
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: storageAccount.properties.primaryEndpoints.blob
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: uami.properties.clientId
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: storageAccount.properties.primaryEndpoints.queue
        }
        {
          name: 'AzureWebJobsStorage__tableServiceUri'
          value: storageAccount.properties.primaryEndpoints.table
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: runtimeStack == 'dotnet-isolated' ? 'dotnet-isolated' : runtimeStack
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: ['https://portal.azure.com']
        supportCredentials: false
      }
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output systemAssignedPrincipalId string = functionApp.identity.principalId
output appServicePlanId string = appServicePlan.id
output appServicePlanSku string = '${skuName} (${skuTier})'
output uamiPrincipalId string = uami.properties.principalId
output uamiClientId string = uami.properties.clientId
output storageAccountId string = storageAccount.id
