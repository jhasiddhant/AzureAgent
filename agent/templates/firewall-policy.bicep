targetScope = 'resourceGroup'

// ============================================================================
// AZURE FIREWALL POLICY
// ============================================================================
// Deploys a reusable Firewall Policy that can be associated with one or more
// Azure Firewalls. Includes an initial empty rule collection group.
//
// After creation, associate this policy with a Firewall using its resource ID.
// ============================================================================

@description('Name of the Firewall Policy.')
@minLength(1)
@maxLength(80)
param firewallPolicyName string

@description('Azure region for the Firewall Policy.')
param location string

@description('SKU tier for the Firewall Policy.')
@allowed([
  'Standard'
  'Premium'
  'Basic'
])
param skuTier string = 'Standard'

@description('Threat intelligence mode.')
@allowed([
  'Alert'
  'Deny'
  'Off'
])
param threatIntelMode string = 'Alert'

@description('Enable DNS proxy.')
param enableDnsProxy bool = false

@description('Custom DNS servers (optional). Leave empty to use Azure default DNS.')
param dnsServers array = []

@description('Name of the initial rule collection group.')
param ruleCollectionGroupName string = ''

@description('Priority of the initial rule collection group.')
@minValue(100)
@maxValue(65000)
param ruleCollectionGroupPriority int = 100

@description('Optional tags for the resource.')
param tags object = {}

// ============================================================================
// VARIABLES
// ============================================================================

var dnsSettings = enableDnsProxy ? {
  enableProxy: true
  servers: !empty(dnsServers) ? dnsServers : null
} : null

// ============================================================================
// FIREWALL POLICY
// ============================================================================
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2024-07-01' = {
  name: firewallPolicyName
  location: location
  tags: tags
  properties: {
    sku: {
      tier: skuTier
    }
    threatIntelMode: threatIntelMode
    dnsSettings: dnsSettings
  }
}

// ============================================================================
// INITIAL RULE COLLECTION GROUP (optional)
// ============================================================================
resource ruleCollectionGroup 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2024-07-01' = if (!empty(ruleCollectionGroupName)) {
  parent: firewallPolicy
  name: !empty(ruleCollectionGroupName) ? ruleCollectionGroupName : 'placeholder'
  properties: {
    priority: ruleCollectionGroupPriority
    ruleCollections: []
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================
output firewallPolicyId string = firewallPolicy.id
output firewallPolicyName string = firewallPolicy.name
