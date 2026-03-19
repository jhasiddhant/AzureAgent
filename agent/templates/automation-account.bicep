targetScope = 'resourceGroup'

// ============================================================================
// AZURE AUTOMATION ACCOUNT
// ============================================================================
// This template creates an Azure Automation Account with Managed Identity enabled
// and local authentication (keys) disabled by default for enhanced security.
//
// Features:
// - System-assigned and/or User-assigned Managed Identity support
// - Local authentication disabled by default (keys disabled)
// - Public network access disabled by default
// - Microsoft-managed encryption by default
// ============================================================================

@description('Name of the Automation Account.')
@minLength(6)
@maxLength(50)
param automationAccountName string

@description('Azure region for the Automation Account.')
param location string

@description('SKU for the Automation Account. Basic is the default.')
@allowed([
  'Basic'
  'Free'
])
param skuName string = 'Basic'

@description('List of User-Assigned Managed Identity resource IDs to associate (optional). System-assigned MI is always enabled.')
param userAssignedIdentities array = []

@description('Disable local authentication (keys). Set to true for enhanced security.')
param disableLocalAuth bool = true

@description('Enable or disable public network access.')
param publicNetworkAccess bool = false

@description('Resource tags.')
param tags object = {}

// ============================================================================
// VARIABLES
// ============================================================================

// Build userAssignedIdentities object from array of resource IDs
var userAssignedIdentitiesObject = reduce(userAssignedIdentities, {}, (cur, next) => union(cur, { '${next}': {} }))

// Always enable System-assigned MI, optionally add User-assigned MIs
var identityType = length(userAssignedIdentities) > 0 ? 'SystemAssigned, UserAssigned' : 'SystemAssigned'

// Determine the identity configuration
var identityConfiguration = {
  type: identityType
  userAssignedIdentities: length(userAssignedIdentities) > 0 ? userAssignedIdentitiesObject : null
}

// ============================================================================
// RESOURCES
// ============================================================================

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  tags: tags
  identity: identityConfiguration
  properties: {
    publicNetworkAccess: publicNetworkAccess
    disableLocalAuth: disableLocalAuth
    sku: {
      name: skuName
    }
    encryption: {
      keySource: 'Microsoft.Automation'
      identity: {}
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('The resource ID of the Automation Account.')
output automationAccountId string = automationAccount.id

@description('The name of the Automation Account.')
output automationAccountName string = automationAccount.name

@description('The principal ID of the system-assigned managed identity.')
output principalId string = automationAccount.identity.principalId

@description('The tenant ID of the system-assigned managed identity.')
output tenantId string = automationAccount.identity.tenantId
