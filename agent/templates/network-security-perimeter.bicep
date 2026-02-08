targetScope = 'resourceGroup'

param location string
param nspName string
param createDefaultProfile bool = true

resource networkSecurityPerimeter 'Microsoft.Network/networkSecurityPerimeters@2024-07-01' = {
  name: nspName
  location: location
  properties: {}
}

resource defaultProfile 'Microsoft.Network/networkSecurityPerimeters/profiles@2024-07-01' = if (createDefaultProfile) {
  parent: networkSecurityPerimeter
  name: 'defaultProfile'
  properties: {}
}

output nspId string = networkSecurityPerimeter.id
output nspName string = networkSecurityPerimeter.name
output defaultProfileId string = createDefaultProfile ? defaultProfile.id : ''
