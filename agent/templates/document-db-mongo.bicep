targetScope = 'resourceGroup'

@description('Azure region for the MongoDB cluster.')
param location string = 'westus'

@description('Name of the MongoDB cluster (must be globally unique).')
param mongoClusterName string

@description('Administrator username for the MongoDB cluster.')
param administratorUserName string

@secure()
@description('Administrator password for the MongoDB cluster (required for NativeAuth).')
param administratorPassword string = ''

@description('MongoDB server version.')
@allowed([
  '5.0'
  '6.0'
  '7.0'
  '8.0'
])
param serverVersion string = '8.0'

@description('Compute tier for the MongoDB cluster.')
@allowed([
  'Free'
  'M25'
  'M30'
  'M40'
  'M50'
  'M60'
  'M80'
])
param computeTier string = 'Free'

@description('Storage size in GB.')
@minValue(32)
@maxValue(16384)
param storageSizeGb int = 32

@description('Storage type for the MongoDB cluster.')
@allowed([
  'PremiumSSD'
  'StandardSSD'
])
param storageType string = 'StandardSSD'

@description('Number of shards for the MongoDB cluster.')
@minValue(1)
@maxValue(32)
param shardCount int = 1

@description('High availability mode for the MongoDB cluster.')
@allowed([
  'Disabled'
  'SameZone'
  'ZoneRedundantPreferred'
])
param highAvailabilityMode string = 'Disabled'

@description('Enable public network access.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Data API mode.')
@allowed([
  'Enabled'
  'Disabled'
])
param dataApiMode string = 'Disabled'

@description('Authentication modes allowed for the cluster.')
@allowed([
  'NativeAuth'
  'EntraAuth'
])
param allowedAuthModes array = ['NativeAuth']

@description('Create mode for the MongoDB cluster.')
@allowed([
  'Default'
  'PointInTimeRestore'
  'GeoReplica'
  'Replica'
])
param createMode string = 'Default'

@description('Enable creation of default admin user.')
param createAdminUser bool = true

// MongoDB Cluster resource
resource mongoCluster 'Microsoft.DocumentDB/mongoClusters@2025-09-01' = {
  name: mongoClusterName
  location: location
  identity: {
    type: 'None'
  }
  properties: {
    administrator: {
      userName: administratorUserName
      password: !empty(administratorPassword) ? administratorPassword : null
    }
    serverVersion: serverVersion
    compute: {
      tier: computeTier
    }
    storage: {
      sizeGb: storageSizeGb
      type: storageType
    }
    sharding: {
      shardCount: shardCount
    }
    highAvailability: {
      targetMode: highAvailabilityMode
    }
    backup: {}
    publicNetworkAccess: publicNetworkAccess
    dataApi: {
      mode: dataApiMode
    }
    authConfig: {
      allowedModes: allowedAuthModes
    }
    createMode: createMode
  }
}

// Admin user resource (optional)
resource mongoClusterUser 'Microsoft.DocumentDB/mongoClusters/users@2025-09-01' = if (createAdminUser) {
  parent: mongoCluster
  name: administratorUserName
  properties: {}
}

@description('MongoDB cluster resource ID.')
output mongoClusterId string = mongoCluster.id

@description('MongoDB cluster name.')
output mongoClusterNameOutput string = mongoCluster.name

@description('MongoDB cluster connection string endpoint.')
output connectionStringEndpoint string = 'mongodb+srv://${mongoClusterName}.mongocluster.cosmos.azure.com'
