targetScope = 'resourceGroup'

@description('Name of the SQL Server.')
@minLength(1)
@maxLength(63)
param sqlServerName string

@description('Region for the SQL Server.')
param location string

@description('Entra ID admin login name (user/group display name).')
param entraAdminLogin string

@description('Entra ID admin Object ID (user or group).')
param entraAdminObjectId string

@description('Entra ID admin principal type.')
@allowed([
  'User'
  'Group'
  'Application'
])
param entraAdminPrincipalType string = 'User'

@description('Azure AD Tenant ID.')
param tenantId string = subscription().tenantId

@description('Minimum TLS version.')
@allowed([
  '1.0'
  '1.1'
  '1.2'
])
param minimumTlsVersion string = '1.2'

@description('Public network access setting.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Name of the existing Log Analytics workspace for SQL Auditing.')
param logAnalyticsWorkspaceName string

// SQL Server
resource sqlServer 'Microsoft.Sql/servers@2024-05-01-preview' = {
  name: sqlServerName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    version: '12.0'
    minimalTlsVersion: minimumTlsVersion
    publicNetworkAccess: publicNetworkAccess
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: entraAdminPrincipalType
      login: entraAdminLogin
      sid: entraAdminObjectId
      tenantId: tenantId
      azureADOnlyAuthentication: true
    }
    restrictOutboundNetworkAccess: 'Disabled'
  }
}

// Entra-only authentication enforcement
resource azureADOnlyAuth 'Microsoft.Sql/servers/azureADOnlyAuthentications@2024-05-01-preview' = {
  parent: sqlServer
  name: 'Default'
  properties: {
    azureADOnlyAuthentication: true
  }
}

// Allow Azure services firewall rule
resource allowAzureServicesRule 'Microsoft.Sql/servers/firewallRules@2024-05-01-preview' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Advanced Threat Protection
resource advancedThreatProtection 'Microsoft.Sql/servers/advancedThreatProtectionSettings@2024-05-01-preview' = {
  parent: sqlServer
  name: 'Default'
  properties: {
    state: 'Enabled'
  }
}

// Security Alert Policy
resource securityAlertPolicy 'Microsoft.Sql/servers/securityAlertPolicies@2024-05-01-preview' = {
  parent: sqlServer
  name: 'Default'
  properties: {
    state: 'Enabled'
    emailAccountAdmins: false
    retentionDays: 0
  }
}

// SQL Vulnerability Assessment
resource sqlVulnerabilityAssessment 'Microsoft.Sql/servers/sqlVulnerabilityAssessments@2024-05-01-preview' = {
  parent: sqlServer
  name: 'Default'
  properties: {
    state: 'Enabled'
  }
}

// Auditing Settings
resource auditingSettings 'Microsoft.Sql/servers/auditingSettings@2024-05-01-preview' = {
  parent: sqlServer
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
    retentionDays: 0
    auditActionsAndGroups: [
      'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
      'FAILED_DATABASE_AUTHENTICATION_GROUP'
      'BATCH_COMPLETED_GROUP'
    ]
  }
}

// ============================================================================
// LOG ANALYTICS DIAGNOSTIC SETTING FOR SQL AUDITING
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsWorkspaceName
}

resource sqlServerDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: sqlServer
  name: '${sqlServerName}-audit-logs'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'SQLSecurityAuditEvents'
        enabled: true
      }
      {
        category: 'DevOpsOperationsAudit'
        enabled: true
      }
    ]
    metrics: []
  }
}

// Connection Policy
resource connectionPolicy 'Microsoft.Sql/servers/connectionPolicies@2024-05-01-preview' = {
  parent: sqlServer
  name: 'default'
  properties: {
    connectionType: 'Default'
  }
}

// Service-managed encryption
resource encryptionProtector 'Microsoft.Sql/servers/encryptionProtector@2024-05-01-preview' = {
  parent: sqlServer
  name: 'current'
  properties: {
    serverKeyName: 'ServiceManaged'
    serverKeyType: 'ServiceManaged'
    autoRotationEnabled: false
  }
}

resource serviceKey 'Microsoft.Sql/servers/keys@2024-05-01-preview' = {
  parent: sqlServer
  name: 'ServiceManaged'
  properties: {
    serverKeyType: 'ServiceManaged'
  }
}

output sqlServerId string = sqlServer.id
output sqlServerName string = sqlServer.name
output fullyQualifiedDomainName string = sqlServer.properties.fullyQualifiedDomainName
output principalId string = sqlServer.identity.principalId
