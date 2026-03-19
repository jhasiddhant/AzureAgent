targetScope = 'resourceGroup'

// ============================================================================
// AZURE SPEECH SERVICES
// ============================================================================
// Deploys a Cognitive Services Speech Services account with:
// - SystemAssigned managed identity
// - Local auth (API keys) disabled by default
// - Public network access disabled by default
// - Outbound network restrictions enabled
// - Network ACLs with deny-by-default
// ============================================================================

@description('Azure region for the Speech Services account.')
param location string

@description('Speech Services account name (globally unique).')
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
param allowedFqdnList array = [
  'microsoft.com'
]

@description('Optional tags for the resource.')
param tags object = {}

// ============================================================================
// SPEECH SERVICES ACCOUNT
// ============================================================================
resource speechService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: accountName
  location: location
  kind: 'SpeechServices'
  tags: tags
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

// ============================================================================
// OUTPUTS
// ============================================================================
output accountId string = speechService.id
output accountName string = speechService.name
output principalId string = speechService.identity.principalId
output endpoint string = 'https://${accountName}.cognitiveservices.azure.com/'
output allowedOutboundFqdns array = restrictOutboundNetworkAccess ? allowedFqdnList : []
