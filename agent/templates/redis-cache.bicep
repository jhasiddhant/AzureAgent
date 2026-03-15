targetScope = 'resourceGroup'

@description('Name of the Azure Cache for Redis instance.')
@minLength(1)
@maxLength(63)
param redisCacheName string

@description('Region for the Redis Cache.')
param location string

@description('SKU name for the Redis Cache.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param skuName string = 'Standard'

@description('SKU family (C for Basic/Standard, P for Premium).')
@allowed([
  'C'
  'P'
])
param skuFamily string = 'C'

@description('Cache capacity (0-6 for C family, 1-5 for P family).')
@minValue(0)
@maxValue(6)
param skuCapacity int = 0

@description('Redis version.')
@allowed([
  '6.0'
  '7.4'
])
param redisVersion string = '6.0'

@description('Minimum TLS version.')
@allowed([
  '1.0'
  '1.1'
  '1.2'
])
param minimumTlsVersion string = '1.2'

@description('Enable public network access.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

@description('Resource ID of User-Assigned Managed Identity (optional).')
param userAssignedIdentityId string = ''

// Redis Cache resource
resource redisCache 'Microsoft.Cache/Redis@2024-11-01' = {
  name: redisCacheName
  location: location
  identity: userAssignedIdentityId != '' ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  } : {
    type: 'SystemAssigned'
  }
  properties: {
    redisVersion: redisVersion
    sku: {
      name: skuName
      family: skuFamily
      capacity: skuCapacity
    }
    enableNonSslPort: false
    minimumTlsVersion: minimumTlsVersion
    publicNetworkAccess: publicNetworkAccess
    redisConfiguration: {
      'aad-enabled': 'True'
      'maxmemory-reserved': '30'
      'maxfragmentationmemory-reserved': '30'
      'maxmemory-delta': '30'
    }
    updateChannel: 'Stable'
    zonalAllocationPolicy: 'Automatic'
    disableAccessKeyAuthentication: true
  }
}

// Built-in access policies
resource dataContributorPolicy 'Microsoft.Cache/Redis/accessPolicies@2024-11-01' = {
  parent: redisCache
  name: 'Data Contributor'
  properties: {
    permissions: '+@all -@dangerous +cluster|info +cluster|nodes +cluster|slots allkeys'
  }
}

resource dataOwnerPolicy 'Microsoft.Cache/Redis/accessPolicies@2024-11-01' = {
  parent: redisCache
  name: 'Data Owner'
  properties: {
    permissions: '+@all allkeys'
  }
}

resource dataReaderPolicy 'Microsoft.Cache/Redis/accessPolicies@2024-11-01' = {
  parent: redisCache
  name: 'Data Reader'
  properties: {
    permissions: '+@read +@connection +cluster|info +cluster|nodes +cluster|slots allkeys'
  }
}

output redisCacheId string = redisCache.id
output redisCacheName string = redisCache.name
output hostName string = redisCache.properties.hostName
output sslPort int = redisCache.properties.sslPort
output principalId string = redisCache.identity.type == 'SystemAssigned' ? redisCache.identity.principalId : ''
