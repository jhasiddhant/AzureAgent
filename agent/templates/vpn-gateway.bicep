targetScope = 'resourceGroup'

// ============================================================================
// AZURE VPN GATEWAY
// ============================================================================
// Deploys a VPN Gateway (VpnGw2AZ) with:
// - Active-Active configuration with 3 Public IPs
// - Route-based VPN type
// - BGP enabled
// - Generation 1
//
// Prerequisites (must exist before deployment):
// - Virtual Network with a GatewaySubnet
// - 3 Standard SKU Public IP addresses (zone-redundant)
// - NSG associated with the GatewaySubnet
//
// NOTE: VPN Gateway provisioning takes ~30-45 minutes.
// Point-to-Site configuration should be done manually after creation.
// ============================================================================

@description('Name of the VPN Gateway.')
@minLength(1)
@maxLength(80)
param vpnGatewayName string

@description('Azure region for the VPN Gateway.')
param location string

@description('Resource ID of the Virtual Network containing the GatewaySubnet.')
param vnetId string

@description('Resource ID of the NSG associated with the GatewaySubnet (collected for compliance tracking).')
#disable-next-line no-unused-params
param nsgId string

@description('Resource ID of the primary Public IP address.')
param publicIpId1 string

@description('Resource ID of the secondary Public IP address.')
param publicIpId2 string

@description('Resource ID of the third Public IP address (used for P2S configuration).')
param publicIpId3 string

@description('SKU name and tier for the VPN Gateway.')
@allowed([
  'VpnGw1AZ'
  'VpnGw2AZ'
  'VpnGw3AZ'
  'VpnGw4AZ'
  'VpnGw5AZ'
])
param skuName string = 'VpnGw2AZ'

@description('VPN type.')
@allowed([
  'RouteBased'
  'PolicyBased'
])
param vpnType string = 'RouteBased'

@description('Enable BGP for the VPN Gateway.')
param enableBgp bool = true

@description('Enable active-active configuration.')
param activeActive bool = true

@description('VPN Gateway generation.')
@allowed([
  'Generation1'
  'Generation2'
])
param vpnGatewayGeneration string = 'Generation1'

@description('Enable private IP address on the gateway.')
param enablePrivateIpAddress bool = false

@description('Optional tags for the resource.')
param tags object = {}

// ============================================================================
// VPN GATEWAY
// ============================================================================
resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-07-01' = {
  name: vpnGatewayName
  location: location
  tags: tags
  properties: {
    enablePrivateIpAddress: enablePrivateIpAddress
    ipConfigurations: [
      {
        name: 'ipconfig-primary'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIpId1
          }
          subnet: {
            id: '${vnetId}/subnets/GatewaySubnet'
          }
        }
      }
      {
        name: 'ipconfig-secondary'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIpId2
          }
          subnet: {
            id: '${vnetId}/subnets/GatewaySubnet'
          }
        }
      }
      {
        name: 'ipconfig-tertiary'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIpId3
          }
          subnet: {
            id: '${vnetId}/subnets/GatewaySubnet'
          }
        }
      }
    ]
    sku: {
      name: skuName
      tier: skuName
    }
    gatewayType: 'Vpn'
    vpnType: vpnType
    enableBgp: enableBgp
    activeActive: activeActive
    vpnGatewayGeneration: vpnGatewayGeneration
    enableBgpRouteTranslationForNat: false
    disableIPSecReplayProtection: false
    enableHighBandwidthVpnGateway: false
    allowRemoteVnetTraffic: false
    allowVirtualWanTraffic: false
    natRules: []
    virtualNetworkGatewayPolicyGroups: []
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================
output vpnGatewayId string = vpnGateway.id
output vpnGatewayName string = vpnGateway.name
