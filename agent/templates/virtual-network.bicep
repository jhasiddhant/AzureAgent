targetScope = 'resourceGroup'

@description('Name of the Virtual Network.')
param vnetName string

@description('Azure region for the VNet (should match NSG location).')
param location string

@description('Resource ID of the existing Network Security Group to associate with subnets.')
param networkSecurityGroupId string

@description('Optional: Custom address space in CIDR notation. If not provided, creates 6 predefined enterprise subnets.')
param addressPrefix string = ''

// Determine mode based on user input
var useCustomMode = !empty(addressPrefix)

// Default address space for predefined subnets (/23 = 512 IPs)
var defaultAddressPrefix = '10.0.0.0/23'

// ============================================================================
// CUSTOM MODE: Single default subnet (when user provides addressPrefix)
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
          addressPrefix: cidrSubnet(addressPrefix, 28, 0)
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
// DEFAULT MODE: 6 predefined enterprise subnets (when no addressPrefix given)
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
        name: 'InboundPrivateLink'
        properties: {
          addressPrefix: '10.0.0.0/25'
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
          privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
      // OutboundWebApp - /28 (16 IPs) - App Service (Standard/Premium)
      {
        name: 'OutboundWebApp'
        properties: {
          addressPrefix: '10.0.0.128/28'
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
          delegations: [
            {
              name: 'webServerFarmsDelegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
      // OutboundFuncApp - /28 (16 IPs) - Function App (Flex/Consumption)
      {
        name: 'OutboundFuncApp'
        properties: {
          addressPrefix: '10.0.0.144/28'
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
          delegations: [
            {
              name: 'webServerFarmsDelegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
      // OutboundFuncAppPremium - /28 (16 IPs) - Function App (Premium/Dedicated)
      {
        name: 'OutboundFuncAppPremium'
        properties: {
          addressPrefix: '10.0.0.160/28'
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
          delegations: [
            {
              name: 'webServerFarmsDelegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
      // ContainerAppSubnet - /27 (32 IPs) - Container Apps Environment (workload profiles)
      {
        name: 'ContainerAppSubnet'
        properties: {
          addressPrefix: '10.0.1.128/27'
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
          delegations: [
            {
              name: 'containerAppDelegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
      // AzureFirewallSubnet - /26 (64 IPs) - No NSG allowed on firewall subnet
      {
        name: 'AzureFirewallSubnet'
        properties: {
          addressPrefix: '10.0.0.192/26'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
          defaultOutboundAccess: false
        }
      }
      // GatewaySubnet - /27 (32 IPs) - No NSG allowed on gateway subnet
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: '10.0.1.0/27'
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Disabled'
          defaultOutboundAccess: false
        }
      }
      // InboundDNSResolver - /27 (32 IPs) - Requires delegation
      {
        name: 'InboundDNSResolver'
        properties: {
          addressPrefix: '10.0.1.32/27'
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
        name: 'OutboundDNSResolver'
        properties: {
          addressPrefix: '10.0.1.64/27'
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
      // APIManagementSubnet - /27 (32 IPs) - API Management VNet injection
      {
        name: 'APIManagementSubnet'
        properties: {
          addressPrefix: '10.0.1.96/27'
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
          delegations: [
            {
              name: 'apimDelegation'
              properties: {
                serviceName: 'Microsoft.ApiManagement/service'
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
output mode string = useCustomMode ? 'custom (1 subnet)' : 'default (10 subnets)'

// Subnet outputs - default mode
output inboundPrivateLinkSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[0].id : ''
output outboundWebAppSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[1].id : ''
output outboundFuncAppSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[2].id : ''
output outboundFuncAppPremiumSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[3].id : ''
output containerAppSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[4].id : ''
output azureFirewallSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[5].id : ''
output gatewaySubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[6].id : ''
output inboundDnsResolverSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[7].id : ''
output outboundDnsResolverSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[8].id : ''
output apiManagementSubnetId string = !useCustomMode ? vnetDefault!.properties.subnets[9].id : ''

// Subnet output - custom mode
output defaultSubnetId string = useCustomMode ? vnetCustom!.properties.subnets[0].id : ''
