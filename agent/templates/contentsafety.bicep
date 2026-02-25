targetScope = 'resourceGroup'

@description('Azure region for the Content Safety (Cognitive Services) account.')
param location string

@description('Content Safety account name (globally unique).')
@minLength(2)
@maxLength(64)
param accountName string

@description('SKU for Content Safety (commonly kept at S0).')
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

// Azure AI Content Safety account
resource contentSafety 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: accountName
  location: location
  kind: 'ContentSafety'
  sku: {
    name: skuName
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // Using a custom subdomain is commonly required/expected for several Azure AI resources.
    customSubDomainName: accountName

    // No public ingress
    publicNetworkAccess: disablePublicNetworkAccess ? 'Disabled' : 'Enabled'

    // Default deny for inbound network rules
    networkAcls: {
      defaultAction: 'Deny'
      virtualNetworkRules: []
      ipRules: []
    }

    // Prefer Entra ID auth over keys
    disableLocalAuth: disableLocalAuth

    // Reduce egress exposure (where supported)
    restrictOutboundNetworkAccess: restrictOutboundNetworkAccess
    allowedFqdnList: restrictOutboundNetworkAccess ? allowedFqdnList : []
  }
}

output accountId string = contentSafety.id
output principalId string = contentSafety.identity.principalId
output allowedOutboundFqdns array = restrictOutboundNetworkAccess ? allowedFqdnList : []
