targetScope = 'resourceGroup'

// ============================================================================
// AZURE API MANAGEMENT (APIM)
// ============================================================================
// Creates an API Management service instance.
// Standard tier is the default (production-ready with SLA).
// ============================================================================

@description('Name of the API Management service (globally unique).')
@minLength(1)
@maxLength(50)
param apimName string

@description('Azure region for the API Management service.')
param location string

@description('The email address of the publisher (required).')
param publisherEmail string

@description('The name of the publisher/organization (required).')
param publisherName string

@description('SKU of the API Management service.')
@allowed([
  'Consumption'
  'Developer'
  'Basic'
  'Standard'
  'Premium'
])
param skuName string = 'Standard'

@description('Number of scale units (capacity). Not applicable for Consumption tier.')
@minValue(0)
@maxValue(12)
param skuCapacity int = 1

@description('Enable system-assigned managed identity.')
param enableSystemAssignedIdentity bool = true

@description('Disable public network access to the APIM management plane.')
param disablePublicNetworkAccess bool = false

@description('Virtual network type for APIM.')
@allowed([
  'None'
  'External'
  'Internal'
])
param virtualNetworkType string = 'None'

@description('Subnet resource ID for VNet integration (required if virtualNetworkType is External or Internal).')
param subnetId string = ''

@description('Log Analytics workspace resource ID for monitoring and diagnostics (required).')
param logAnalyticsWorkspaceId string

@description('Minimum TLS version for client connections.')
@allowed([
  '1.0'
  '1.1'
  '1.2'
])
param minApiVersion string = '1.2'

@description('Enable triple DES ciphers (not recommended for security).')
param enableTripleDes bool = false

@description('Tags to apply to the APIM resource.')
param tags object = {}

// ============================================================================
// VARIABLES
// ============================================================================

var identityType = enableSystemAssignedIdentity ? 'SystemAssigned' : 'None'

// Consumption tier has fixed capacity of 0
var effectiveCapacity = skuName == 'Consumption' ? 0 : skuCapacity

// VNet configuration only if type is not None
var virtualNetworkConfiguration = virtualNetworkType != 'None' && !empty(subnetId) ? {
  subnetResourceId: subnetId
} : null

// ============================================================================
// API MANAGEMENT SERVICE
// ============================================================================

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: apimName
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: effectiveCapacity
  }
  identity: {
    type: identityType
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: virtualNetworkType
    virtualNetworkConfiguration: virtualNetworkConfiguration
    publicNetworkAccess: disablePublicNetworkAccess ? 'Disabled' : 'Enabled'
    customProperties: {
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': minApiVersion == '1.0' ? 'True' : 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': minApiVersion == '1.0' || minApiVersion == '1.1' ? 'True' : 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Ciphers.TripleDes168': enableTripleDes ? 'True' : 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'False'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'False'
    }
  }
}

// ============================================================================
// LOG ANALYTICS DIAGNOSTIC SETTINGS
// ============================================================================

resource apimDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${apimName}-diagnostics'
  scope: apim
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output apimId string = apim.id
output apimName string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output managementApiUrl string = apim.properties.managementApiUrl
output portalUrl string = apim.properties.portalUrl
output developerPortalUrl string = apim.properties.developerPortalUrl
output principalId string = enableSystemAssignedIdentity ? apim.identity.principalId : ''
output publicIpAddresses array = apim.properties.publicIPAddresses
output privateIpAddresses array = apim.properties.privateIPAddresses
