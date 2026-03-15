targetScope = 'resourceGroup'

// ============================================================================
// DATA COLLECTION ENDPOINT (DCE)
// ============================================================================
// Creates a Data Collection Endpoint for Azure Monitor.
// Required for:
// - Logs Ingestion API (custom logs)
// - Azure Monitor Private Link Scope (AMPLS)
// - VNet-isolated data ingestion
// ============================================================================

@description('Name of the Data Collection Endpoint.')
@minLength(3)
@maxLength(44)
param dceName string

@description('Azure region for the DCE. Must match the region of resources using it.')
param location string = resourceGroup().location

@description('Public network access for the endpoint.')
@allowed([
  'Enabled'
  'Disabled'
  'SecuredByPerimeter'
])
param publicNetworkAccess string = 'Enabled'

@description('Description for the DCE.')
param dceDescription string = ''

@description('Tags to apply to the resource.')
param tags object = {}

// ============================================================================
// DATA COLLECTION ENDPOINT RESOURCE
// ============================================================================

resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: dceName
  location: location
  tags: tags
  properties: {
    description: empty(dceDescription) ? null : dceDescription
    networkAcls: {
      publicNetworkAccess: publicNetworkAccess
    }
    configurationAccess: {}
    logsIngestion: {}
    metricsIngestion: {}
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output dceId string = dataCollectionEndpoint.id
output dceName string = dataCollectionEndpoint.name
output dceImmutableId string = dataCollectionEndpoint.properties.immutableId
output logsIngestionEndpoint string = dataCollectionEndpoint.properties.logsIngestion.endpoint
output metricsIngestionEndpoint string = dataCollectionEndpoint.properties.metricsIngestion.endpoint
output configurationAccessEndpoint string = dataCollectionEndpoint.properties.configurationAccess.endpoint
output location string = dataCollectionEndpoint.location
