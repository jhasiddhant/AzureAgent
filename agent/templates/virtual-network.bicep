targetScope = 'resourceGroup'

@description('Name of the Virtual Network.')
param vnetName string

@description('Azure region for the VNet (should match NSG location).')
param location string

@description('Resource ID of the existing Network Security Group to associate with subnets.')
param networkSecurityGroupId string

@description('Optional: Custom address space in CIDR notation. If not provided, uses default /23 with predefined subnets.')
param addressPrefix string = ''

// Determine if using custom or default mode
var useCustomMode = !empty(addressPrefix)

// Default address space for predefined subnets (/23 = 512 IPs)
var defaultAddressPrefix = '10.0.0.0/23'

// Predefined subnet configuration (when no custom address provided)
// Total: 352 IPs, fits in /23 with 160 IPs to spare
var predefinedSubnets = [
  {
    name: 'InboundPrivateLink'
    addressPrefix: '10.0.0.0/25'      // 128 IPs
    delegation: ''
  }
  {
    name: 'OutboundPrivateLink'
    addressPrefix: '10.0.0.128/26'    // 64 IPs
    delegation: ''
  }
  {
    name: 'AzureFirewallSubnet'
    addressPrefix: '10.0.0.192/26'    // 64 IPs (Azure requires /26 minimum)
    delegation: ''
  }
  {
    name: 'GatewaySubnet'
    addressPrefix: '10.0.1.0/27'      // 32 IPs
    delegation: ''
  }
  {
    name: 'InboundDNSResolver'
    addressPrefix: '10.0.1.32/27'     // 32 IPs
    delegation: 'Microsoft.Network/dnsResolvers'
  }
  {
    name: 'OutboundDNSResolver'
    addressPrefix: '10.0.1.64/27'     // 32 IPs
    delegation: 'Microsoft.Network/dnsResolvers'
  }
]

// ============================================================================
// CUSTOM MODE: Single default subnet with /28 (16 IPs)
// ============================================================================
resource vnetCustom 'Microsoft.Network/virtualNetworks@2024-07-01' = if (useCustomMode) {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: cidrSubnet(addressPrefix, 28, 0)  // First /28 from provided range
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
          privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

// ============================================================================
// DEFAULT MODE: Predefined 6 subnets for enterprise setup
// ============================================================================
resource vnetDefault 'Microsoft.Network/virtualNetworks@2024-07-01' = if (!useCustomMode) {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        defaultAddressPrefix
      ]
    }
    subnets: [
      // InboundPrivateLink - /25 (128 IPs)
      {
        name: predefinedSubnets[0].name
        properties: {
          addressPrefix: predefinedSubnets[0].addressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
          privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
      // OutboundPrivateLink - /26 (64 IPs)
      {
        name: predefinedSubnets[1].name
        properties: {
          addressPrefix: predefinedSubnets[1].addressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
          privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
      // AzureFirewallSubnet - /26 (64 IPs) - No NSG allowed on firewall subnet
      {
        name: predefinedSubnets[2].name
        properties: {
          addressPrefix: predefinedSubnets[2].addressPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
          defaultOutboundAccess: false
        }
      }
      // GatewaySubnet - /27 (32 IPs) - No NSG allowed on gateway subnet
      {
        name: predefinedSubnets[3].name
        properties: {
          addressPrefix: predefinedSubnets[3].addressPrefix
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
          defaultOutboundAccess: false
        }
      }
      // InboundDNSResolver - /27 (32 IPs) - Requires delegation
      {
        name: predefinedSubnets[4].name
        properties: {
          addressPrefix: predefinedSubnets[4].addressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
          delegations: [
            {
              name: 'dnsResolverDelegation'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
      // OutboundDNSResolver - /27 (32 IPs) - Requires delegation
      {
        name: predefinedSubnets[5].name
        properties: {
          addressPrefix: predefinedSubnets[5].addressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
          delegations: [
            {
              name: 'dnsResolverDelegation'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================
output vnetId string = useCustomMode ? vnetCustom!.id : vnetDefault!.id
output vnetName string = useCustomMode ? vnetCustom!.name : vnetDefault!.name
output addressSpace string = useCustomMode ? addressPrefix : defaultAddressPrefix
output mode string = useCustomMode ? 'custom' : 'default'

// Subnet outputs for default mode
output inboundPrivateLinkSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[0].id : ''
output outboundPrivateLinkSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[1].id : ''
output azureFirewallSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[2].id : ''
output gatewaySubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[3].id : ''
output inboundDnsResolverSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[4].id : ''
output outboundDnsResolverSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[5].id : ''

// Subnet output for custom mode
output defaultSubnetId string = useCustomMode ? vnetCustom!.properties.subnets[0].id : ''
