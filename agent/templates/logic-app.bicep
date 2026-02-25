targetScope = 'resourceGroup'

@description('Name of the Logic App')
@minLength(3)
@maxLength(60)
param logicAppName string

@description('Region for the Logic App')
param location string

// ============================================================================
// CONSUMPTION LOGIC APP (Serverless)
// ============================================================================
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {}
      actions: {}
      outputs: {}
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================
output logicAppId string = logicApp.id
output logicAppName string = logicApp.name
output systemAssignedIdentityPrincipalId string = logicApp.identity.principalId
