targetScope = 'resourceGroup'

@description('Globally unique Storage Account name (3-24 lowercase letters and digits).')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Region for the Storage Account (should match the resource group location).')
param location string

@description('Blob access tier.')
@allowed([
  'Hot'
  'Cool'
  'Cold' // Cold may be preview/limited; use Hot or Cool if deployment fails.
])
param accessTier string
@description('Enable hierarchical namespace (ADLS Gen2). Set false for classic storage.')
param enableHierarchicalNamespace bool = true

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: accessTier
    isHnsEnabled: enableHierarchicalNamespace
    allowSharedKeyAccess: false
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled' // Change to 'Disabled' after private networking established
    minimumTlsVersion: 'TLS1_2'
    encryption: {
      keySource: 'Microsoft.Storage'
      services: {
        blob:  { enabled: true }
        file:  { enabled: true }
        table: { enabled: true }
        queue: { enabled: true }
      }
    }
  }
}

output storageAccountId string = storageAccount.id
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output dfsEndpoint string = storageAccount.properties.primaryEndpoints.dfs
output webEndpoint string = storageAccount.properties.primaryEndpoints.web
output appliedAccessTier string = storageAccount.properties.accessTier
