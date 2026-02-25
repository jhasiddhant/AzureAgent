targetScope = 'resourceGroup'

@description('Azure region for the Document Intelligence (Cognitive Services) account.')
param location string

@description('Document Intelligence (Cognitive Services) account name (globally unique).')
@minLength(2)
@maxLength(64)
param accountName string

@description('SKU for Document Intelligence (kept default Standard S0).')
@allowed([
  'S0'
])
param skuName string = 'S0'

@description('Disable local authentication (API keys).')
param disableLocalAuth bool = true

@description('Disable public network access.')
param disablePublicNetworkAccess bool = true

@description('Restrict outbound network access (true => only domains in allowedFqdnList).')
param restrictOutboundNetworkAccess bool = true

@description('Allowed FQDNs for outbound when restriction is enabled.')
param allowedFqdnList array = []

// Azure Document Intelligence account
resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: accountName
  location: location
  kind: 'FormRecognizer'
  sku: {
    name: skuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: disablePublicNetworkAccess ? 'Disabled' : 'Enabled'
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: []
      ipRules: []
    }
    disableLocalAuth: disableLocalAuth
    restrictOutboundNetworkAccess: restrictOutboundNetworkAccess
    allowedFqdnList: restrictOutboundNetworkAccess ? allowedFqdnList : []
  }
}

output accountId string = documentIntelligence.id
output principalId string = documentIntelligence.identity.principalId
output allowedOutboundFqdns array = restrictOutboundNetworkAccess ? allowedFqdnList : []
