targetScope = 'resourceGroup'

@description('Globally unique Function App name.')
@minLength(2)
@maxLength(60)
param functionAppName string

@description('Region for the Function App.')
param location string

@description('Hosting plan type for the Function App.')
@allowed([
  'Consumption'
  'FlexConsumption'
  'Premium'
  'AppServicePlan'
])
param hostingPlanType string

@description('App Service Plan name (required for Premium and AppServicePlan hosting types).')
param appServicePlanName string = ''

@description('App Service Plan SKU (required for Premium and AppServicePlan hosting types).')
@allowed([
  'Y1'              // Consumption
  'FC1'             // Flex Consumption
  'EP1'             // Premium V3 P1V3 - 122.64 USD/Month (8 GB, 2 vCPU)
  'EP2'             // Premium V3 P2V3 - 245.28 USD/Month (16 GB, 4 vCPU)
  'EP3'             // Premium V3 P3V3 - 490.56 USD/Month (32 GB, 8 vCPU)
  'P0v3'            // Premium V3 P0V3 - 61.32 USD/Month (4 GB, 1 vCPU)
  'P1v3'            // Premium V3 P1V3 - 122.64 USD/Month (8 GB, 2 vCPU)
  'P1mv3'           // Premium V3 P1MV3 - 147.17 USD/Month (16 GB, 2 vCPU)
  'P2v3'            // Premium V3 P2V3 - 245.28 USD/Month (16 GB, 4 vCPU)
  'P3v3'            // Premium V3 P3V3 - 490.56 USD/Month (32 GB, 8 vCPU)
  'B1'              // Basic B1 - 13.14 USD/Month (100 ACU, 1.75 GB, 1 vCPU)
  'B2'              // Basic B2 - 26.28 USD/Month (200 ACU, 3.5 GB, 2 vCPU)
  'B3'              // Basic B3 - 52.56 USD/Month (400 ACU, 7 GB, 4 vCPU)
  'S1'              // Standard S1 - 69.35 USD/Month (100 ACU, 1.75 GB, 1 vCPU)
  'S2'              // Standard S2 - 138.70 USD/Month (200 ACU, 3.5 GB, 2 vCPU)
  'S3'              // Standard S3 - 277.40 USD/Month (400 ACU, 7 GB, 4 vCPU)
  'P1v2'            // Premium V2 P1v2 - 146.00 USD/Month (210 ACU, 3.5 GB, 1 vCPU)
  'P2v2'            // Premium V2 P2v2 - 292.00 USD/Month (420 ACU, 7 GB, 2 vCPU)
  'P3v2'            // Premium V2 P3v2 - 584.00 USD/Month (840 ACU, 14 GB, 4 vCPU)
])
param appServicePlanSku string = 'EP1'

@description('Runtime stack for the Function App.')
@allowed([
  'dotnet'
  'dotnet-isolated'
  'node'
  'python'
  'java'
  'powershell'
  'custom'
])
param runtimeStack string

@description('Runtime version (e.g., ~4 for Functions runtime, 3.11 for Python, 20 for Node).')
param runtimeVersion string = '~4'

@description('Existing Storage Account name (ADLS Gen2) for Function App content.')
param storageAccountName string

@description('Enable public network access.')
param publicNetworkAccess bool = true

// Storage account reference (must exist)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: functionAppName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: null
  }
}

// App Service Plan (for all hosting types except ContainerApps)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = if (hostingPlanType != 'ContainerApps') {
  name: (hostingPlanType == 'Premium' || hostingPlanType == 'AppServicePlan') ? appServicePlanName : '${functionAppName}-plan'
  location: location
  kind: hostingPlanType == 'Premium' ? 'elastic' : (hostingPlanType == 'FlexConsumption' ? 'functionapp' : 'app')
  sku: {
    name: appServicePlanSku
    tier: appServicePlanSku == 'Y1' ? 'Dynamic' : (contains(appServicePlanSku, 'EP') || contains(appServicePlanSku, 'P') ? 'ElasticPremium' : (contains(appServicePlanSku, 'B') ? 'Basic' : (appServicePlanSku == 'FC1' ? 'FlexConsumption' : 'Standard')))
  }
  properties: {
    reserved: contains(runtimeStack, 'dotnet') ? false : true // Linux for non-Windows runtimes
    maximumElasticWorkerCount: hostingPlanType == 'Premium' ? 20 : null
  }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  kind: hostingPlanType == 'FlexConsumption' ? 'functionapp' : (hostingPlanType == 'Premium' || hostingPlanType == 'AppServicePlan' ? 'functionapp' : 'functionapp,linux,container')
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlanType != 'ContainerApps' ? appServicePlan.id : null
    httpsOnly: true
    publicNetworkAccess: publicNetworkAccess ? 'Enabled' : 'Disabled'
    functionAppConfig: hostingPlanType == 'FlexConsumption' ? {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}deployments'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: runtimeStack
        version: runtimeStack == 'python' ? '3.11' : (runtimeStack == 'node' ? '20' : '8.0')
      }
    } : null
    
    siteConfig: {
      linuxFxVersion: hostingPlanType != 'FlexConsumption' && runtimeStack == 'python' ? 'Python|3.11' : (hostingPlanType != 'FlexConsumption' && runtimeStack == 'node' ? 'Node|20' : (hostingPlanType != 'FlexConsumption' && runtimeStack == 'dotnet-isolated' ? 'DOTNET-ISOLATED|8.0' : ''))
      appSettings: concat([
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: runtimeVersion
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
      ], hostingPlanType != 'FlexConsumption' ? [
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: runtimeStack
        }
      ] : [])

      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      use32BitWorkerProcess: false
      cors: {
        allowedOrigins: []
        supportCredentials: false
      }
    }
  }
}

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output systemAssignedIdentityPrincipalId string = functionApp.identity.principalId
output storageAccountId string = storageAccount.id
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
output appInsightsConnectionString string = appInsights.properties.ConnectionString
