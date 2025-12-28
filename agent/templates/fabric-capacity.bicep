targetScope = 'resourceGroup'

@description('The name of the Fabric capacity')
param capacityName string

@description('The SKU of the Fabric capacity')
@allowed([
  'F2'
  'F4'
  'F8'
  'F16'
  'F32'
  'F64'
  'F128'
  'F256'
  'F512'
  'F1024'
  'F2048'
])
param sku string

@description('Admin member emails for the Fabric capacity (comma-separated for multiple emails)')
param adminMembers string

@description('Location for the Fabric capacity - Should be same as Tenant Region')
param location string

@description('Tags for the resource')
param tags object = {}

// Convert comma-separated string to array
var adminMembersArray = split(adminMembers, ',')

resource fabricCapacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: capacityName
  location: location
  sku: {
    name: sku
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: adminMembersArray
    }
  }
  tags: tags
}

output capacityId string = fabricCapacity.id
output capacityName string = fabricCapacity.name
output location string = fabricCapacity.location
output sku string = fabricCapacity.sku.name
