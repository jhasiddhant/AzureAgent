targetScope = 'resourceGroup'

@description('Azure region for the Azure OpenAI account (must be valid for this resource group).')
param location string

@description('Azure OpenAI (Cognitive Services) account name (globally unique).')
@minLength(2)
@maxLength(64)
param accountName string

@description('SKU (kept default Standard S0).')
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
// disable-next-line no-hardcoded-env-urls
param allowedFqdnList array = []

// Azure OpenAI account
resource openAi 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: accountName
  location: location
  kind: 'OpenAI'
  sku: {
    name: skuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
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

output accountId string = openAi.id
output principalId string = openAi.identity.principalId
output allowedOutboundFqdns array = restrictOutboundNetworkAccess ? allowedFqdnList : []
