targetScope = 'resourceGroup'

@description('Azure region for the Cosmos DB account (must be valid for this resource group).')
param location string

@description('Cosmos DB account name (globally unique).')
param cosmosDbAccountName string

@description('Default consistency policy settings.')
param defaultConsistencyLevel string = 'Session'
@minValue(5)
param maxIntervalInSeconds int = 5
@minValue(1)
param maxStalenessPrefix int = 100

@description('Backup policy configuration.')
param backupIntervalInMinutes int = 240
param backupRetentionIntervalInHours int = 8
@allowed([
  'Geo'
  'Local'
  'Zone'
])
param backupStorageRedundancy string = 'Local'

// Cosmos DB account (SQL API by default via kind: GlobalDocumentDB)
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2025-05-01-preview' = {
  name: cosmosDbAccountName
  location: location
  kind: 'GlobalDocumentDB'
  identity: {
    // System-assigned identity by default; set UserAssigned via a separate template if needed.
    type: 'SystemAssigned'
  }
  properties: {
    // Required defaults
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'

    // Common secure defaults and minimal working config
    databaseAccountOfferType: 'Standard'
    minimalTlsVersion: 'Tls12'
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: defaultConsistencyLevel
      maxIntervalInSeconds: maxIntervalInSeconds
      maxStalenessPrefix: maxStalenessPrefix
    }

    // Backup (Periodic)
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: backupIntervalInMinutes
        backupRetentionIntervalInHours: backupRetentionIntervalInHours
        backupStorageRedundancy: backupStorageRedundancy
      }
    }

    // Sensible defaults: block CORS, no IP rules unless needed
    cors: []
    ipRules: []
    networkAclBypass: 'None'
    networkAclBypassResourceIds: []
  }
}

@description('Cosmos DB account resource ID.')
output cosmosAccountId string = cosmosAccount.id

@description('Managed identity principal ID of the Cosmos account (system-assigned).')
output cosmosAccountPrincipalId string = cosmosAccount.identity.principalId
