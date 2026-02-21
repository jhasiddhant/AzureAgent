targetScope = 'resourceGroup'

@description('Name of the subnet.')
param subnetName string

@description('Name of the existing Virtual Network.')
param vnetName string

@description('Starting IP address for the subnet (e.g., 10.0.0.32 for second /27 block).')
param subnetStartingAddress string

@description('Subnet prefix length (CIDR notation, /27 = 32 addresses, 27 usable).')
@minValue(24)
@maxValue(29)
param subnetSize int = 27

@description('Resource ID of the existing Network Security Group to associate with the subnet.')
param networkSecurityGroupId string

var addressPrefix = '${subnetStartingAddress}/${subnetSize}'

resource existingVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: vnetName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' = {
  parent: existingVnet
  name: subnetName
  properties: {
    addressPrefix: addressPrefix
    networkSecurityGroup: {
      id: networkSecurityGroupId
    }
    delegations: []
    privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
    defaultOutboundAccess: false
  }
}

output subnetId string = subnet.id
output subnetName string = subnet.name
output subnetAddressPrefix string = subnet.properties.addressPrefix
