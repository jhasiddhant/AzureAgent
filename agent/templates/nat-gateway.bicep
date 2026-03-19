targetScope = 'resourceGroup'

@description('Name of the NAT Gateway.')
param natGatewayName string

@description('Azure region for the NAT Gateway.')
param location string

@description('Resource ID of an existing Standard SKU Public IP to associate with the NAT Gateway.')
param publicIpId string

@description('SKU name for the NAT Gateway.')
@allowed([
  'Standard'
])
param skuName string = 'Standard'

@description('Idle timeout in minutes (4-120).')
@minValue(4)
@maxValue(120)
param idleTimeoutInMinutes int = 4

@description('Availability zones for the NAT Gateway (e.g., ["1"] or ["1", "2", "3"]).')
param zones array = []

@description('Optional tags for the resources.')
param tags object = {}

// Create NAT Gateway
resource natGateway 'Microsoft.Network/natGateways@2024-07-01' = {
  name: natGatewayName
  location: location
  sku: {
    name: skuName
  }
  zones: !empty(zones) ? zones : null
  tags: tags
  properties: {
    idleTimeoutInMinutes: idleTimeoutInMinutes
    publicIpAddresses: [
      {
        id: publicIpId
      }
    ]
  }
}

// Outputs
output natGatewayId string = natGateway.id
output natGatewayName string = natGateway.name
