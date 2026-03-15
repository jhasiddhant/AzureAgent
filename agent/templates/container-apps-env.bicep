targetScope = 'resourceGroup'

// ============================================================================
// AZURE CONTAINER APPS ENVIRONMENT
// ============================================================================
// This template creates a Container Apps Environment with VNet integration.
// Requirements:
// - Must be deployed in the SAME REGION as the Resource Group
// - REQUIRES a VNet with a dedicated subnet for Container Apps
// - REQUIRES an existing Log Analytics workspace
// - Subnet size: minimum /23 for consumption, /27 for workload profiles
// ============================================================================

@description('Name of the Container Apps Environment.')
@minLength(2)
@maxLength(60)
param environmentName string

@description('Region for the Container Apps Environment. MUST match the Resource Group region.')
param location string

@description('Full resource ID of the subnet for Container Apps infrastructure. REQUIRED.')
@metadata({
  example: '/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}'
})
param infrastructureSubnetId string

@description('Full resource ID of existing Log Analytics workspace. REQUIRED.')
@metadata({
  example: '/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.OperationalInsights/workspaces/{workspaceName}'
})
param logAnalyticsWorkspaceId string

@description('Enable zone redundancy for high availability.')
param zoneRedundant bool = false

@description('Workload profile configuration. Use "Consumption" for serverless or specify dedicated profiles.')
@allowed([
  'Consumption'
  'D4'
  'D8'
  'D16'
  'D32'
  'E4'
  'E8'
  'E16'
  'E32'
])
param workloadProfileType string = 'Consumption'

@description('Enable internal-only environment (no public ingress).')
param internalOnly bool = false

// ============================================================================
// EXISTING RESOURCES
// ============================================================================

// Reference existing Log Analytics workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(logAnalyticsWorkspaceId, '/'))
  scope: resourceGroup(split(logAnalyticsWorkspaceId, '/')[2], split(logAnalyticsWorkspaceId, '/')[4])
}

// ============================================================================
// CONTAINER APPS ENVIRONMENT
// ============================================================================

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: environmentName
  location: location
  properties: {
    // VNet Configuration - REQUIRED
    vnetConfiguration: {
      infrastructureSubnetId: infrastructureSubnetId
      internal: internalOnly
    }
    
    // Zone Redundancy
    zoneRedundant: zoneRedundant
    
    // Logging Configuration - uses existing Log Analytics
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    
    // Workload Profiles
    workloadProfiles: workloadProfileType == 'Consumption' ? [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ] : [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
      {
        name: 'dedicated'
        workloadProfileType: workloadProfileType
        minimumCount: 1
        maximumCount: 10
      }
    ]
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output environmentId string = containerAppsEnvironment.id
output environmentName string = containerAppsEnvironment.name
output defaultDomain string = containerAppsEnvironment.properties.defaultDomain
output staticIp string = containerAppsEnvironment.properties.staticIp
output logAnalyticsWorkspaceId string = logAnalyticsWorkspaceId
output location string = containerAppsEnvironment.location
