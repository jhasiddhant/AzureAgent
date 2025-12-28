targetScope = 'resourceGroup'

@description('Azure region for the User Assigned Managed Identity (must be valid for this resource group).')
param location string

@description('User Assigned Managed Identity name (must be unique within the resource group).')
param uamiName string

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
  name: uamiName
  location: location
}

@description('Resource ID of the User Assigned Managed Identity')
output uamiResourceId string = uami.id

@description('Principal (Object) ID of the User Assigned Managed Identity')
output uamiPrincipalId string = uami.properties.principalId

@description('Client (Application) ID of the User Assigned Managed Identity')
output uamiClientId string = uami.properties.clientId
