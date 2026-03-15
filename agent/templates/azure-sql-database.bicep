targetScope = 'resourceGroup'

@description('Name of the SQL Database.')
@minLength(1)
@maxLength(128)
param databaseName string

@description('Name of the existing SQL Server.')
param sqlServerName string

@description('Region for the database (should match SQL Server location).')
param location string

@description('SKU name for the database.')
@allowed([
  'GP_S_Gen5'
  'GP_Gen5'
  'BC_Gen5'
  'S0'
  'S1'
  'S2'
  'Basic'
])
param skuName string = 'GP_S_Gen5'

@description('SKU tier.')
@allowed([
  'GeneralPurpose'
  'BusinessCritical'
  'Standard'
  'Basic'
])
param skuTier string = 'GeneralPurpose'

@description('SKU family (for vCore SKUs).')
param skuFamily string = 'Gen5'

@description('Capacity (vCores for vCore SKU, DTUs for DTU SKU).')
@minValue(1)
@maxValue(128)
param skuCapacity int = 1

@description('Minimum vCore capacity for serverless (0.5 to skuCapacity).')
param minCapacity string = '0.5'

@description('Auto-pause delay in minutes (-1 to disable, 60 minimum).')
param autoPauseDelay int = 60

@description('Maximum database size in bytes (default 32GB).')
param maxSizeBytes int = 34359738368

@description('Database collation.')
param collation string = 'SQL_Latin1_General_CP1_CI_AS'

@description('Enable zone redundancy.')
param zoneRedundant bool = false

@description('Backup storage redundancy.')
@allowed([
  'Local'
  'Zone'
  'Geo'
  'GeoZone'
])
param backupStorageRedundancy string = 'Local'

// Reference existing SQL Server
resource sqlServer 'Microsoft.Sql/servers@2024-05-01-preview' existing = {
  name: sqlServerName
}

// SQL Database
resource sqlDatabase 'Microsoft.Sql/servers/databases@2024-05-01-preview' = {
  parent: sqlServer
  name: databaseName
  location: location
  sku: {
    name: skuName
    tier: skuTier
    family: skuTier == 'GeneralPurpose' || skuTier == 'BusinessCritical' ? skuFamily : null
    capacity: skuCapacity
  }
  properties: {
    collation: collation
    maxSizeBytes: maxSizeBytes
    catalogCollation: collation
    zoneRedundant: zoneRedundant
    readScale: 'Disabled'
    autoPauseDelay: skuName == 'GP_S_Gen5' ? autoPauseDelay : -1
    requestedBackupStorageRedundancy: backupStorageRedundancy
    minCapacity: skuName == 'GP_S_Gen5' ? json(minCapacity) : null
    isLedgerOn: false
    availabilityZone: 'NoPreference'
  }
}

// Short-term backup retention (depends on database being fully provisioned)
resource shortTermBackup 'Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2024-05-01-preview' = {
  parent: sqlDatabase
  name: 'default'
  properties: {
    retentionDays: 7
    diffBackupIntervalInHours: 12
  }
}

// Geo-backup policy (disabled for Local redundancy, sequenced after backup retention)
resource geoBackupPolicy 'Microsoft.Sql/servers/databases/geoBackupPolicies@2024-05-01-preview' = {
  parent: sqlDatabase
  name: 'Default'
  dependsOn: [shortTermBackup]
  properties: {
    state: backupStorageRedundancy == 'Local' ? 'Disabled' : 'Enabled'
  }
}

output databaseId string = sqlDatabase.id
output databaseName string = sqlDatabase.name
output serverName string = sqlServerName
