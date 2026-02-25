targetScope = 'resourceGroup'

@description('Azure region for the Language (Cognitive Services) account.')
param location string

@description('Language service account name (globally unique).')
@minLength(2)
@maxLength(64)
param accountName string

@description('SKU for Language service (commonly S).')
@allowed([
  'S'
])
param skuName string = 'S'

@description('Disable local authentication (API keys).')
param disableLocalAuth bool = true

@description('Disable public network access.')
param disablePublicNetworkAccess bool = true

@description('Restrict outbound network access (true => only domains in allowedFqdnList).')
param restrictOutboundNetworkAccess bool = true

@description('Allowed FQDNs for outbound when restriction is enabled.')
param allowedFqdnList array = []

// Azure AI Language account (Text Analytics)
resource language 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: accountName
  location: location
  kind: 'TextAnalytics'
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

output accountId string = language.id
output principalId string = language.identity.principalId
output allowedOutboundFqdns array = restrictOutboundNetworkAccess ? allowedFqdnList : []
