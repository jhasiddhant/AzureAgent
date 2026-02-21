targetScope = 'resourceGroup'

@description('Name of the Private Endpoint.')
param privateEndpointName string

@description('Azure region for the Private Endpoint (should match VNet location).')
param location string

@description('Resource ID of the target Azure resource to connect to (e.g., Storage Account, Key Vault).')
param targetResourceId string

@description('''
The sub-resource (group ID) for the private endpoint connection. Use the appropriate value based on service type:

STORAGE ACCOUNT:
  - blob          : Blob storage
  - blob_secondary: Blob storage (secondary)
  - file          : Azure Files
  - file_secondary: Azure Files (secondary)
  - table         : Table storage
  - table_secondary: Table storage (secondary)
  - queue         : Queue storage
  - queue_secondary: Queue storage (secondary)
  - web           : Static website
  - dfs           : Data Lake Storage Gen2
  - dfs_secondary : Data Lake Storage Gen2 (secondary)

KEY VAULT:
  - vault         : Key Vault

COSMOS DB:
  - Sql           : SQL API
  - MongoDB       : MongoDB API
  - Cassandra     : Cassandra API
  - Gremlin       : Gremlin API
  - Table         : Table API
  - Analytical    : Analytical store

SQL DATABASE:
  - sqlServer     : SQL Server

SYNAPSE:
  - Sql           : SQL pools
  - SqlOnDemand   : Serverless SQL
  - Dev           : Development endpoint

APP SERVICE / FUNCTION APP:
  - sites         : Web app / Function app

COGNITIVE SERVICES / OPENAI:
  - account       : Cognitive Services account

CONTAINER REGISTRY:
  - registry      : Container Registry

SEARCH SERVICE:
  - searchService : Azure AI Search

EVENT HUB:
  - namespace     : Event Hub namespace

SERVICE BUS:
  - namespace     : Service Bus namespace

DATA FACTORY:
  - dataFactory   : Data Factory
  - portal        : Data Factory portal

MACHINE LEARNING:
  - amlworkspace  : ML workspace

REDIS CACHE:
  - redisCache    : Redis Cache

SIGNALR:
  - signalr       : SignalR Service
''')
param groupId string

@description('Resource ID of the subnet to deploy the Private Endpoint into.')
param subnetId string

@description('Optional: Resource ID of an existing Private DNS Zone for automatic DNS registration. Leave empty to skip DNS configuration.')
param privateDnsZoneId string = ''

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: privateEndpointName
  location: location
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${privateEndpointName}-connection'
        properties: {
          privateLinkServiceId: targetResourceId
          groupIds: [
            groupId
          ]
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = if (!empty(privateDnsZoneId)) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: privateDnsZoneId
        }
      }
    ]
  }
}

output privateEndpointId string = privateEndpoint.id
output privateEndpointName string = privateEndpoint.name
output networkInterfaceId string = privateEndpoint.properties.networkInterfaces[0].id
