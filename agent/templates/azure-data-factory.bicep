targetScope = 'resourceGroup'

// Parameters the user provides
@description('Azure region where the Data Factory will be deployed (must match the ADLS account region).')
param location string

@description('Name of the Azure Data Factory.')
param factoryName string


// Create Data Factory with system-assigned managed identity
resource factory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: factoryName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
}

// Managed Integration Runtime (auto-resolve)
resource ir 'Microsoft.DataFactory/factories/integrationRuntimes@2018-06-01' = {
  parent: factory
  name: 'AutoResolveIntegrationRuntime'
  properties: {
    type: 'Managed'
    typeProperties: {
      computeProperties: {
        location: 'AutoResolve'
      }
    }
  }
}

output factoryId string = factory.id
output factoryName string = factory.name
output principalId string = factory.identity.principalId
