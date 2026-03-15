targetScope = 'resourceGroup'

@description('Name of the Private DNS Zone (e.g., privatelink.blob.core.windows.net)')
param privateDnsZoneName string

@description('Resource ID of the VNet to link to this DNS zone')
param vnetId string

@description('Name for the VNet link (will be auto-generated if not provided)')
param vnetLinkName string = ''

@description('Enable auto-registration of VM DNS records in this zone')
param enableAutoRegistration bool = false

// Extract VNet name from ID for link naming
var vnetName = last(split(vnetId, '/'))
var actualLinkName = empty(vnetLinkName) ? '${vnetName}-link' : vnetLinkName

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  properties: {}
}

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: actualLinkName
  location: 'global'
  properties: {
    registrationEnabled: enableAutoRegistration
    virtualNetwork: {
      id: vnetId
    }
  }
}

output privateDnsZoneId string = privateDnsZone.id
output privateDnsZoneName string = privateDnsZone.name
output vnetLinkId string = vnetLink.id
output vnetLinkName string = vnetLink.name
