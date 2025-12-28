targetScope = 'resourceGroup'

@description('Azure region for the Log Analytics Workspace.')
param location string

@description('Log Analytics Workspace name.')
@minLength(4)
@maxLength(63)
param workspaceName string

@description('SKU for the Log Analytics Workspace.')
@allowed([
  'PerGB2018'
  'CapacityReservation'
  'Free'
  'Standard'
  'Premium'
])
param skuName string = 'PerGB2018'

@description('Data retention in days (30-730).')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

@description('Enable public network access.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccessForIngestion string = 'Enabled'

@description('Enable public network access for query.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccessForQuery string = 'Enabled'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: skuName
    }
    retentionInDays: retentionInDays
    publicNetworkAccessForIngestion: publicNetworkAccessForIngestion
    publicNetworkAccessForQuery: publicNetworkAccessForQuery
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
output customerId string = logAnalyticsWorkspace.properties.customerId
