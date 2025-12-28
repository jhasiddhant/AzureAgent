targetScope = 'resourceGroup'

@description('Azure region for the Key Vault.')
param location string

@description('Key Vault name (3-24 chars, globally unique).')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('SKU for the Key Vault.')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Soft delete retention in days (7-90).')
@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 90

// Key Vault using RBAC (no access policies) with public network disabled and explicit network ACL baseline.
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: tenant().tenantId
    sku: {
      name: skuName
      family: 'A'
    }
    enablePurgeProtection: true
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays

    enableRbacAuthorization: true
    publicNetworkAccess: 'Disabled'

    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

output keyVaultId string = kv.id
output keyVaultUri string = kv.properties.vaultUri