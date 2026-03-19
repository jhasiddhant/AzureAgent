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

@description('Resource ID of the VNet (used for DNS zone link). If not provided, will be extracted from subnetId.')
param vnetId string = ''

@description('Name for the VNet link in DNS zone (will be auto-generated if not provided).')
param vnetLinkName string = ''

@description('Enable auto-registration of VM DNS records in the DNS zone')
param enableDnsAutoRegistration bool = false

@description('Resource ID of an EXISTING Private DNS Zone. If provided, skips DNS zone creation and uses this zone instead.')
param existingDnsZoneId string = ''

@description('Set to true if the VNet link already exists for this DNS zone. Skips VNet link creation.')
param skipVnetLink bool = false

// DNS Zone mapping based on groupId
// Reference: https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
var dnsZoneMapping = {
  // Storage Account
  blob: 'privatelink.blob.${environment().suffixes.storage}'
  blob_secondary: 'privatelink.blob.${environment().suffixes.storage}'
  file: 'privatelink.file.${environment().suffixes.storage}'
  file_secondary: 'privatelink.file.${environment().suffixes.storage}'
  table: 'privatelink.table.${environment().suffixes.storage}'
  table_secondary: 'privatelink.table.${environment().suffixes.storage}'
  queue: 'privatelink.queue.${environment().suffixes.storage}'
  queue_secondary: 'privatelink.queue.${environment().suffixes.storage}'
  web: 'privatelink.web.${environment().suffixes.storage}'
  dfs: 'privatelink.dfs.${environment().suffixes.storage}'
  dfs_secondary: 'privatelink.dfs.${environment().suffixes.storage}'
  
  // Key Vault
  vault: 'privatelink.vaultcore.azure.net'
  
  // Cosmos DB
  Sql: 'privatelink.documents.azure.com'
  MongoDB: 'privatelink.mongo.cosmos.azure.com'
  Cassandra: 'privatelink.cassandra.cosmos.azure.com'
  Gremlin: 'privatelink.gremlin.cosmos.azure.com'
  Table: 'privatelink.table.cosmos.azure.com'
  Analytical: 'privatelink.analytics.cosmos.azure.com'
  
  // SQL Database
  sqlServer: 'privatelink${environment().suffixes.sqlServerHostname}'
  
  // Synapse
  SqlOnDemand: 'privatelink.sql.azuresynapse.net'
  Dev: 'privatelink.dev.azuresynapse.net'
  
  // App Service / Function App
  sites: 'privatelink.azurewebsites.net'
  
  // Cognitive Services / OpenAI
  account: 'privatelink.cognitiveservices.azure.com'
  
  // Container Registry
  registry: 'privatelink.azurecr.io'
  
  // Azure AI Search
  searchService: 'privatelink.search.windows.net'
  
  // Event Hub / Service Bus
  namespace: 'privatelink.servicebus.windows.net'
  
  // Data Factory
  dataFactory: 'privatelink.datafactory.azure.net'
  portal: 'privatelink.adf.azure.com'
  
  // Machine Learning
  amlworkspace: 'privatelink.api.azureml.ms'
  
  // Redis Cache
  redisCache: 'privatelink.redis.cache.windows.net'
  
  // SignalR
  signalr: 'privatelink.service.signalr.net'
}

// Get DNS zone name from mapping
var privateDnsZoneName = dnsZoneMapping[?groupId] ?? ''

// Determine if we should create a new DNS zone or use existing
var shouldCreateDnsZone = !empty(privateDnsZoneName) && empty(existingDnsZoneId)
var shouldLinkNewZone = shouldCreateDnsZone && !skipVnetLink
var hasDnsConfig = !empty(privateDnsZoneName) || !empty(existingDnsZoneId)

// Extract VNet ID from subnet ID if not provided
// Subnet ID format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}
var subnetParts = split(subnetId, '/')
var extractedVnetId = vnetId != '' ? vnetId : '${join(take(subnetParts, 9), '/')}'
var vnetName = last(split(extractedVnetId, '/'))
var actualLinkName = vnetLinkName != '' ? vnetLinkName : '${vnetName}-link'

// Create Private Endpoint
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

// Create Private DNS Zone (only if we need to create new, not using existing)
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = if (shouldCreateDnsZone) {
  name: privateDnsZoneName
  location: 'global'
  properties: {}
}

// Create VNet Link to DNS Zone (for newly created DNS zones)
resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (shouldLinkNewZone) {
  parent: privateDnsZone
  name: actualLinkName
  location: 'global'
  properties: {
    registrationEnabled: enableDnsAutoRegistration
    virtualNetwork: {
      id: extractedVnetId
    }
  }
}

// NOTE: VNet links to existing DNS zones in different resource groups are now handled
// by the Python code deploying dns-zone-vnet-link.bicep to the DNS zone's RG.
// When skipVnetLink is true, we skip VNet link creation here and rely on Python handling it.

// Create DNS Zone Group to link PE with DNS Zone (use existing or new zone)
// This registers the A record in the DNS zone for DNS resolution
resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = if (hasDnsConfig) {
  parent: privateEndpoint
  name: 'default'
  dependsOn: [
    vnetLink
  ]
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(!empty(existingDnsZoneId) ? last(split(existingDnsZoneId, '/')) : privateDnsZoneName, '.', '-')
        properties: {
          privateDnsZoneId: !empty(existingDnsZoneId) ? existingDnsZoneId : privateDnsZone.id
        }
      }
    ]
  }
}

output privateEndpointId string = privateEndpoint.id
output privateEndpointName string = privateEndpoint.name
output networkInterfaceId string = privateEndpoint.properties.networkInterfaces[0].id
output privateDnsZoneId string = shouldCreateDnsZone ? privateDnsZone.id : existingDnsZoneId
output privateDnsZoneName string = shouldCreateDnsZone ? privateDnsZone.name : (!empty(existingDnsZoneId) ? last(split(existingDnsZoneId, '/')) : '')
output vnetLinkId string = shouldLinkNewZone ? vnetLink.id : ''

