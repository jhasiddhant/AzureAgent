targetScope = 'resourceGroup'

@description('Name of the Application Insights instance.')
@minLength(1)
@maxLength(255)
param appInsightsName string

@description('Region for the Application Insights instance.')
param location string

@description('Resource ID of the Log Analytics workspace to link to.')
param logAnalyticsWorkspaceId string

@description('Application type.')
@allowed([
  'web'
  'other'
  'java'
  'MobileCenter'
  'phone'
  'store'
  'ios'
  'Node.JS'
])
param applicationType string = 'web'

@description('Disable IP masking for client IP collection.')
param disableIpMasking bool = false

@description('Disable local authentication (API key/instrumentation key).')
param disableLocalAuth bool = true

@description('Retention period in days.')
@allowed([
  30
  60
  90
  120
  180
  270
  365
  550
  730
])
param retentionInDays int = 90

// Application Insights resource
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: applicationType
  properties: {
    Application_Type: applicationType
    WorkspaceResourceId: logAnalyticsWorkspaceId
    DisableIpMasking: disableIpMasking
    DisableLocalAuth: disableLocalAuth
    RetentionInDays: retentionInDays
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output appInsightsId string = appInsights.id
output appInsightsName string = appInsights.name
output instrumentationKey string = appInsights.properties.InstrumentationKey
output connectionString string = appInsights.properties.ConnectionString
