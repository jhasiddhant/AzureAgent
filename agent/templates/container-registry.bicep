targetScope = 'resourceGroup'

@description('Globally unique Container Registry name (5-50 alphanumeric characters).')
@minLength(5)
@maxLength(50)
param registryName string

@description('Region for the Container Registry (should match the resource group location).')
param location string

@description('SKU/Pricing tier for the Container Registry.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string = 'Standard'

@description('Enable zone redundancy (Premium SKU only).')
@allowed([
  'Enabled'
  'Disabled'
])
param zoneRedundancy string = 'Disabled'

@description('Retention policy days for images (Premium SKU only).')
@minValue(0)
@maxValue(365)
param retentionDays int = 7

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2021-09-01' = {
  name: registryName
  location: location
  sku: {
    name: sku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: sku == 'Premium' ? 'Disabled' : 'Enabled'
    networkRuleBypassOptions: sku == 'Premium' ? 'AzureServices' : 'None'
    networkRuleSet: sku == 'Premium' ? {
      defaultAction: 'Deny'
      ipRules: []
    } : null
    policies: sku == 'Premium' ? {
      quarantinePolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        type: 'Notary'
        status: 'disabled'
      }
      retentionPolicy: {
        days: retentionDays
        status: retentionDays > 0 ? 'enabled' : 'disabled'
      }
      exportPolicy: {
        status: 'enabled'
      }
    } : null
    zoneRedundancy: sku == 'Premium' ? zoneRedundancy : 'Disabled'
  }
}

// Default scope maps are automatically created by Azure
// No need to explicitly create them

output registryId string = containerRegistry.id
output registryName string = containerRegistry.name
output loginServer string = containerRegistry.properties.loginServer
output principalId string = containerRegistry.identity.principalId
