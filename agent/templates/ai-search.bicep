targetScope = 'resourceGroup'

@description('Name of the Azure AI Search service (must be globally unique).')
@minLength(2)
@maxLength(60)
param name string

@description('Azure region for the AI Search resource.')
param location string

@description('Pricing tier/SKU for the AI Search service.')
@allowed([
  'free'        // F
  'basic'       // B
  'standard'    // S
  'standard2'   // S2
  'standard3'   // S3
  'standard3_high_density' // S3HD
  'storage_optimized_l1'   // L1
  'storage_optimized_l2'   // L2
])
param skuName string = 'standard'

resource search 'Microsoft.Search/searchServices@2023-11-01' = {
  name: name
  location: location
  sku: {
    name: skuName
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    publicNetworkAccess: 'disabled'
    hostingMode: 'default'
    disableLocalAuth: true
    networkRuleSet: {
      ipRules: []
      virtualNetworkRules: []
      bypass: 'AzureServices'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

output searchId string = search.id
output principalId string = search.identity.principalId