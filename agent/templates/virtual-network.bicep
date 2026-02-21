targetScope = 'resourceGroup'

@description('Name of the Virtual Network.')
param vnetName string

@description('Azure region for the VNet (should match NSG location).')
param location string

@description('Address space for the VNet (e.g., 10.0.0.0/24 = 256 IPs, fits 8 subnets of /27).')
param addressPrefix string = '10.0.0.0/24'

@description('Name of the default subnet.')
param subnetName string = 'subnet-1'

@description('Starting IP address for the subnet (e.g., 10.0.0.0).')
param subnetStartingAddress string = '10.0.0.0'

@description('Subnet prefix length (CIDR notation, /27 = 32 addresses, 27 usable).')
@minValue(24)
@maxValue(29)
param subnetSize int = 27

@description('Resource ID of the existing Network Security Group to associate with the subnet.')
param networkSecurityGroupId string

var subnetAddressPrefix = '${subnetStartingAddress}/${subnetSize}'

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
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
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          networkSecurityGroup: {
            id: networkSecurityGroupId
          }
          delegations: []
          privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output subnetId string = vnet.properties.subnets[0].id
output subnetName string = vnet.properties.subnets[0].name
