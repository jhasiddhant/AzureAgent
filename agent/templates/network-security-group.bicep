targetScope = 'resourceGroup'

@description('Name of the Network Security Group.')
param nsgName string

@description('Azure region for the NSG.')
param location string

@description('Optional array of security rules to apply.')
param securityRules array = []

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-07-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: securityRules
  }
}

output nsgId string = nsg.id
output nsgName string = nsg.name
