targetScope = 'resourceGroup'

@description('Name of the Azure Firewall.')
param firewallName string

@description('Azure region for the Firewall.')
param location string

@description('SKU tier: Standard, Premium, or Basic.')
@allowed([
  'Standard'
  'Premium'
  'Basic'
])
param skuTier string = 'Standard'

@description('Threat intelligence mode: Alert, Deny, or Off.')
@allowed([
  'Alert'
  'Deny'
  'Off'
])
param threatIntelMode string = 'Alert'

@description('Resource ID of the VNet containing AzureFirewallSubnet.')
param vnetId string

@description('Resource ID of the Public IP for firewall.')
param publicIpId string

@description('Name for the IP configuration.')
param ipConfigName string = 'AzureFirewallIpConfig'

@description('Resource ID of the Public IP for firewall management (required for forced tunneling).')
param managementPublicIpId string = ''

@description('Name for the management IP configuration.')
param managementIpConfigName string = 'AzureFirewallManagementIpConfig'

@description('Availability zones for the firewall (e.g., ["1", "2", "3"]).')
param zones array = []

@description('Enable DNS proxy for the firewall.')
param enableDnsProxy bool = false

@description('Custom DNS servers (optional).')
param dnsServers array = []

@description('Resource ID of Firewall Policy to associate (optional).')
param firewallPolicyId string = ''

@description('Optional tags for the resource.')
param tags object = {}

// Determine if forced tunneling is enabled (requires management IP)
var useForcedTunneling = !empty(managementPublicIpId)

// SKU name is always AZFW_VNet for VNet-based firewall
var skuName = 'AZFW_VNet'

// Build DNS settings if enabled
var dnsSettings = enableDnsProxy ? {
  enableProxy: true
  servers: !empty(dnsServers) ? dnsServers : null
} : null

// ============================================================================
// AZURE FIREWALL - Standard/Premium (without forced tunneling)
// ============================================================================
resource firewallStandard 'Microsoft.Network/azureFirewalls@2024-07-01' = if (!useForcedTunneling) {
  name: firewallName
  location: location
  zones: !empty(zones) ? zones : null
  tags: tags
  properties: {
    sku: {
      name: skuName
      tier: skuTier
    }
    threatIntelMode: threatIntelMode
    ipConfigurations: [
      {
        name: ipConfigName
        properties: {
          publicIPAddress: {
            id: publicIpId
          }
          subnet: {
            id: '${vnetId}/subnets/AzureFirewallSubnet'
          }
        }
      }
    ]
    firewallPolicy: !empty(firewallPolicyId) ? {
      id: firewallPolicyId
    } : null
    additionalProperties: dnsSettings != null ? {
      'Network.DNS.EnableProxy': string(enableDnsProxy)
    } : {}
    networkRuleCollections: []
    applicationRuleCollections: []
    natRuleCollections: []
  }
}

// ============================================================================
// AZURE FIREWALL - With Forced Tunneling (requires management IP config)
// ============================================================================
resource firewallForcedTunnel 'Microsoft.Network/azureFirewalls@2024-07-01' = if (useForcedTunneling) {
  name: firewallName
  location: location
  zones: !empty(zones) ? zones : null
  tags: tags
  properties: {
    sku: {
      name: skuName
      tier: skuTier
    }
    threatIntelMode: threatIntelMode
    managementIpConfiguration: {
      name: managementIpConfigName
      properties: {
        publicIPAddress: {
          id: managementPublicIpId
        }
        subnet: {
          id: '${vnetId}/subnets/AzureFirewallManagementSubnet'
        }
      }
    }
    ipConfigurations: [
      {
        name: ipConfigName
        properties: {
          publicIPAddress: {
            id: publicIpId
          }
          subnet: {
            id: '${vnetId}/subnets/AzureFirewallSubnet'
          }
        }
      }
    ]
    firewallPolicy: !empty(firewallPolicyId) ? {
      id: firewallPolicyId
    } : null
    additionalProperties: dnsSettings != null ? {
      'Network.DNS.EnableProxy': string(enableDnsProxy)
    } : {}
    networkRuleCollections: []
    applicationRuleCollections: []
    natRuleCollections: []
  }
}

// Outputs
output firewallId string = useForcedTunneling ? firewallForcedTunnel.id : firewallStandard.id
output firewallName string = useForcedTunneling ? firewallForcedTunnel.name : firewallStandard.name
output privateIpAddress string = useForcedTunneling 
  ? firewallForcedTunnel!.properties.ipConfigurations[0].properties.privateIPAddress 
  : firewallStandard!.properties.ipConfigurations[0].properties.privateIPAddress
