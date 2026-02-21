targetScope = 'resourceGroup'

@description('Name of the Logic App')
@minLength(3)
@maxLength(60)
param logicAppName string

@description('Region for the Logic App')
param location string

@description('Type of Logic App: consumption (serverless) or standard (workflow service plan)')
@allowed([
  'consumption'
  'Consumption'
  'standard'
  'Standard'
])
param logicAppType string

var normalizedLogicAppType = toLower(logicAppType)

@description('App Service Plan SKU (only for standard type)')
@allowed([
  'WS1'
  'WS2'
  'WS3'
])
param appServicePlanSku string = 'WS1'

// Generate storage account name from Logic App name (max 24 chars, lowercase alphanumeric)
var storageAccountBaseName = toLower(replace(replace(logicAppName, '-', ''), '_', ''))
var storageAccountNameFull = '${take(storageAccountBaseName, 15)}${uniqueString(resourceGroup().id, logicAppName)}'

// ============================================================================
// CONSUMPTION LOGIC APP
// ============================================================================
resource logicAppConsumption 'Microsoft.Logic/workflows@2019-05-01' = if (normalizedLogicAppType == 'consumption') {
  name: logicAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      triggers: {}
      actions: {}
      outputs: {}
    }
  }
}

// ============================================================================
// STANDARD LOGIC APP RESOURCES
// ============================================================================

// Storage Account for Logic App Standard
// NOTE: allowSharedKeyAccess=true is REQUIRED for Logic Apps - may need policy exemption
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = if (normalizedLogicAppType == 'standard') {
  name: take(storageAccountNameFull, 24)
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true // REQUIRED for Logic Apps - may need policy exemption
    isHnsEnabled: false // Must be false for Logic Apps
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (normalizedLogicAppType == 'standard') {
  name: logicAppName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: null
  }
}

// App Service Plan (Workflow Standard)
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = if (normalizedLogicAppType == 'standard') {
  name: '${logicAppName}-asp'
  location: location
  kind: 'elastic'
  sku: {
    name: appServicePlanSku
    tier: 'WorkflowStandard'
  }
  properties: {
    elasticScaleEnabled: true
    maximumElasticWorkerCount: 20
    reserved: false
  }
}

// File share for Logic App content
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = if (normalizedLogicAppType == 'standard') {
  name: '${storageAccount.name}/default/${toLower(take(logicAppName, 50))}-content'
  properties: {
    shareQuota: 5120
    enabledProtocols: 'SMB'
  }
}

// Logic App Standard
resource logicAppStandard 'Microsoft.Web/sites@2023-12-01' = if (normalizedLogicAppType == 'standard') {
  name: logicAppName
  location: location
  kind: 'functionapp,workflowapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      netFrameworkVersion: 'v6.0'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'node'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
        // Storage settings
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount!.name};AccountKey=${storageAccount!.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: '${toLower(logicAppName)}-content'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount!.name};AccountKey=${storageAccount!.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        // Application Insights
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights!.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights!.properties.ConnectionString
        }
        // Workflow settings
        {
          name: 'AzureFunctionsJobHost__extensionBundle__id'
          value: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
        }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__version'
          value: '[1.*, 2.0.0)'
        }
      ]
    }
  }
  dependsOn: [
    fileShare
  ]
}

// ============================================================================
// OUTPUTS
// ============================================================================
output logicAppId string = normalizedLogicAppType == 'consumption' ? logicAppConsumption!.id : logicAppStandard!.id
output systemAssignedIdentityPrincipalId string = normalizedLogicAppType == 'consumption' ? logicAppConsumption!.identity.principalId : logicAppStandard!.identity.principalId
output storageAccountName string = normalizedLogicAppType == 'standard' ? storageAccount!.name : ''
output storageAccountId string = normalizedLogicAppType == 'standard' ? storageAccount!.id : ''

// ============================================================================
// REQUIRED RBAC ROLES (for admin to assign - Standard type only)
// ============================================================================
// The Logic App System Assigned MI needs these roles on the Storage Account:
//
// Role Name                              | Role Definition ID
// ---------------------------------------|--------------------------------------
// Storage Blob Data Owner                | b7e6dc6d-f1e8-4753-8033-0f276bb0955b
// Storage Account Contributor            | 17d1049b-9a84-46fb-8f53-869881c3d3ab
// Storage Queue Data Contributor         | 974c5e8b-45b9-4653-ba55-5f855dd0fb88
// Storage Table Data Contributor         | 0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3
// Storage File Data SMB Share Contributor| 0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb
//
// Admin can assign using:
// az role assignment create --assignee <principalId> --role "<RoleName>" --scope <storageAccountId>
