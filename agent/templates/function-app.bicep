targetScope = 'resourceGroup'

// ============================================================================
// AZURE FUNCTION APP - FLEX CONSUMPTION PLAN
// ============================================================================
// This template creates a Function App with Flex Consumption hosting plan.
// Requirements:
// - Existing ADLS Gen2 Storage Account (for function content and deployment)
// - Existing User Assigned Managed Identity (UAMI) with Storage Blob Data Owner
// Configuration:
// - System Assigned MI: Enabled but NOT used
// - UAMI: Used for deployment and runtime storage access
// - Public network access enabled for both Function App and ADLS
// ============================================================================

@description('Globally unique Function App name.')
@minLength(2)
@maxLength(60)
param functionAppName string

@description('Region for the Function App.')
param location string

@description('Existing Storage Account name (ADLS Gen2) for Function App content and deployment.')
param storageAccountName string

@description('Existing User Assigned Managed Identity name.')
param uamiName string

@description('Runtime stack for the Function App.')
@allowed([
  'dotnet-isolated'
  'node'
  'python'
  'java'
  'powershell'
])
param runtimeStack string = 'python'

@description('Runtime version for the selected stack.')
param runtimeVersion string = '3.11'

@description('Maximum instance count for scaling (1-1000).')
@minValue(1)
@maxValue(1000)
param maximumInstanceCount int = 100

@description('Instance memory in MB.')
@allowed([
  512
  2048
  4096
])
param instanceMemoryMB int = 2048

@description('HTTP concurrency per instance.')
@minValue(1)
@maxValue(1000)
param httpPerInstanceConcurrency int = 16

// Reference existing Storage Account (ADLS Gen2)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// Reference existing User Assigned Managed Identity
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: uamiName
}

// ============================================================================
// APP SERVICE PLAN (Flex Consumption)
// ============================================================================

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${functionAppName}-plan'
  location: location
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true // Linux
  }
}

// ============================================================================
// FUNCTION APP (Flex Consumption)
// ============================================================================

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    
    // Flex Consumption specific configuration
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}deployments'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: uami.id
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
        triggers: {
          http: {
            perInstanceConcurrency: httpPerInstanceConcurrency
          }
        }
      }
      runtime: {
        name: runtimeStack
        version: runtimeVersion
      }
    }
    
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage__blobServiceUri'
          value: storageAccount.properties.primaryEndpoints.blob
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: uami.properties.clientId
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__queueServiceUri'
          value: storageAccount.properties.primaryEndpoints.queue
        }
        {
          name: 'AzureWebJobsStorage__tableServiceUri'
          value: storageAccount.properties.primaryEndpoints.table
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
      ]
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: ['https://portal.azure.com']
        supportCredentials: false
      }
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output systemAssignedPrincipalId string = functionApp.identity.principalId
output uamiPrincipalId string = uami.properties.principalId
output uamiClientId string = uami.properties.clientId
output storageAccountId string = storageAccount.id
output storageAccountBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output storageAccountDfsEndpoint string = storageAccount.properties.primaryEndpoints.dfs

// ============================================================================
// POST-DEPLOYMENT INSTRUCTIONS (Output as message)
// ============================================================================

output postDeploymentInstructions string = '''
================================================================================
POST-DEPLOYMENT STEPS REQUIRED
================================================================================

1. CREATE REQUIRED CONTAINERS IN ADLS:
   Run the following Azure CLI commands to create required blob containers:
   
   az storage container create --name "azure-webjobs-hosts" --account-name <storageAccountName> --auth-mode login
   az storage container create --name "azure-webjobs-secrets" --account-name <storageAccountName> --auth-mode login
   az storage container create --name "deployments" --account-name <storageAccountName> --auth-mode login
   az storage container create --name "scm-releases" --account-name <storageAccountName> --auth-mode login

2. ROLE ASSIGNMENTS REQUIRED (Request Admin):
   The following roles must be assigned on the ADLS Storage Account:
   
   For User Assigned Managed Identity (UAMI):
   - Role: Storage Blob Data Contributor
   - Role: Storage Account Contributor
   - Scope: Storage Account

3. VERIFY PUBLIC ACCESS:
   - ADLS Storage Account: publicNetworkAccess should be 'Enabled'
   - Function App: publicNetworkAccess is 'Enabled'

================================================================================
'''
