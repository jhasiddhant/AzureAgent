targetScope = 'resourceGroup'

param location string
param aiFoundryName string
param aiProjectName string = ''
param disableLocalAuth bool = true
param disablePublicNetworkAccess bool = true
param restrictOutboundNetworkAccess bool = true
param allowedFqdnList array = []
param allowProjectManagement bool = true
param customSubDomainName string = ''
param applyNetworkAcls bool = false

var effectiveProjectName = empty(aiProjectName) ? '${aiFoundryName}-aip' : aiProjectName
var effectiveSubdomain   = empty(customSubDomainName) ? aiFoundryName : customSubDomainName

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: aiFoundryName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: allowProjectManagement
    customSubDomainName: effectiveSubdomain
    disableLocalAuth: disableLocalAuth
    publicNetworkAccess: disablePublicNetworkAccess ? 'Disabled' : 'Enabled'
    ...(applyNetworkAcls ? {
      networkAcls: {
        defaultAction: 'Deny'
        ipRules: []
        virtualNetworkRules: []
      }
    } : {})
  }
}

resource aiProject 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  name: effectiveProjectName
  parent: aiFoundry
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
  dependsOn: [
    aiFoundry
  ]
}

output aiFoundryId string = aiFoundry.id
output aiFoundryPrincipalId string = aiFoundry.identity.principalId
output aiProjectId string = aiProject.id
output aiProjectPrincipalId string = aiProject.identity.principalId
output aiFoundryEndpoint string = 'https://${effectiveSubdomain}.cognitiveservices.azure.com/'
output originalRestrictOutboundNetworkAccess bool = restrictOutboundNetworkAccess
output originalAllowedFqdns array = allowedFqdnList
