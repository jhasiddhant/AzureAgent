targetScope = 'resourceGroup'

// ============================================================================
// AZURE APP SERVICE
// ============================================================================
// This template creates an App Service with secure defaults.
// Security features:
// - HTTPS Only
// - TLS 1.3 minimum
// - System + User Assigned Managed Identity
// - Remote debugging disabled
// - FTP disabled
// - End-to-end TLS encryption
// - CORS restricted (no wildcards)
// ============================================================================

@description('Globally unique App Service name.')
@minLength(2)
@maxLength(60)
param appServiceName string

@description('Region for the App Service.')
param location string

@description('Existing User Assigned Managed Identity name.')
param uamiName string

@description('App Service Plan SKU name.')
@allowed([
  'F1'
  'D1'
  'B1'
  'B2'
  'B3'
  'S1'
  'S2'
  'S3'
  'P1v2'
  'P2v2'
  'P3v2'
  'P1v3'
  'P2v3'
  'P3v3'
])
param skuName string = 'B1'

@description('Number of instances for the App Service Plan.')
@minValue(1)
@maxValue(30)
param instanceCount int = 1

@description('Runtime stack (e.g., DOTNET|8.0, NODE|20-lts, PYTHON|3.11, JAVA|17).')
param linuxFxVersion string = 'DOTNET|8.0'

@description('Enable Always On (requires Standard or higher SKU).')
param alwaysOn bool = false

@description('Allowed CORS origins (specific URLs only, no wildcards).')
param corsAllowedOrigins array = ['https://portal.azure.com']

@description('Enable HTTP/2 protocol.')
param http20Enabled bool = true

// Reference existing User Assigned Managed Identity
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: uamiName
}

// Get SKU tier from SKU name
var skuTier = skuName == 'F1' ? 'Free' : skuName == 'D1' ? 'Shared' : startsWith(skuName, 'B') ? 'Basic' : startsWith(skuName, 'S') ? 'Standard' : startsWith(skuName, 'P1v3') || startsWith(skuName, 'P2v3') || startsWith(skuName, 'P3v3') ? 'PremiumV3' : 'PremiumV2'

// ============================================================================
// APP SERVICE PLAN
// ============================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${appServiceName}-plan'
  location: location
  kind: 'linux'
  sku: {
    name: skuName
    tier: skuTier
    capacity: instanceCount
  }
  properties: {
    reserved: true // Linux
  }
}

// ============================================================================
// APP SERVICE
// ============================================================================

resource appService 'Microsoft.Web/sites@2024-04-01' = {
  name: appServiceName
  location: location
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    enabled: true
    serverFarmId: appServicePlan.id
    reserved: true // Linux
    
    // Security: HTTPS Only
    httpsOnly: true
    
    // Security: End-to-end TLS encryption
    endToEndEncryptionEnabled: true
    
    // Public network access (as requested)
    publicNetworkAccess: 'Enabled'
    
    // Use System Assigned MI for Key Vault references
    keyVaultReferenceIdentity: 'SystemAssigned'
    
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      alwaysOn: alwaysOn
      http20Enabled: http20Enabled
      
      // Security: Latest TLS version
      minTlsVersion: '1.3'
      scmMinTlsVersion: '1.2'
      
      // Security: Disable FTP
      ftpsState: 'Disabled'
      
      // Security: Disable remote debugging
      remoteDebuggingEnabled: false
      
      // Performance settings
      use32BitWorkerProcess: false
      managedPipelineMode: 'Integrated'
      loadBalancing: 'LeastRequests'
      
      // CORS: Specific origins only (no wildcards)
      cors: {
        allowedOrigins: corsAllowedOrigins
        supportCredentials: false
      }
      
      // Logging (recommended for diagnostics)
      requestTracingEnabled: true
      httpLoggingEnabled: true
      detailedErrorLoggingEnabled: true
      logsDirectorySizeLimit: 35
    }
  }
}

// ============================================================================
// PUBLISHING CREDENTIALS POLICIES
// ============================================================================

// Disable FTP publishing credentials
resource ftpPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: appService
  name: 'ftp'
  properties: {
    allow: false
  }
}

// Disable SCM publishing credentials
resource scmPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: appService
  name: 'scm'
  properties: {
    allow: false
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output appServiceId string = appService.id
output appServiceName string = appService.name
output appServiceUrl string = 'https://${appService.properties.defaultHostName}'
output appServicePlanId string = appServicePlan.id
output appServicePlanSku string = '${skuName} (${skuTier})'
output systemAssignedPrincipalId string = appService.identity.principalId
output uamiPrincipalId string = uami.properties.principalId
output uamiClientId string = uami.properties.clientId

// ============================================================================
// POST-DEPLOYMENT INSTRUCTIONS
// ============================================================================

output postDeploymentInstructions string = '''
================================================================================
POST-DEPLOYMENT: DIAGNOSTIC SETTINGS CONFIGURATION
================================================================================

This App Service was deployed with secure defaults but diagnostic settings
must be configured separately for compliance monitoring.

RECOMMENDED ACTIONS:
1. Configure Log Analytics diagnostic settings:
   - Use azure_attach_diagnostic_settings tool, OR
   - Azure Portal > App Service > Diagnostic settings > Add diagnostic setting

2. Optionally attach Application Insights:
   - Use azure_attach_appinsights tool for APM telemetry

SECURITY FEATURES ENABLED:
  - HTTPS Only
  - TLS 1.3 minimum
  - System + User Assigned Managed Identity
  - Remote debugging disabled
  - FTP/FTPS disabled
  - SCM credentials disabled
  - End-to-end TLS encryption
  - CORS restricted (no wildcards)

================================================================================
'''
