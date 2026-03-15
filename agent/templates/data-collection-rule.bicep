targetScope = 'resourceGroup'

// ============================================================================
// DATA COLLECTION RULE (DCR) - DIRECT KIND
// ============================================================================
// Creates a Data Collection Rule for Logs Ingestion API (custom logs).
// Optionally creates a custom Log Analytics table.
// 
// Prerequisites:
// 1. Log Analytics Workspace must exist
// 2. Data Collection Endpoint (DCE) must exist
// ============================================================================

@description('Name of the Data Collection Rule.')
@minLength(1)
@maxLength(64)
param dcrName string

@description('Azure region. Must match Log Analytics Workspace and DCE region.')
param location string = resourceGroup().location

@description('Name of the existing Log Analytics Workspace.')
param workspaceName string

@description('Name of the existing Data Collection Endpoint.')
param dceName string

@description('Base name of custom table (without _CL suffix). E.g., "MyCustomLogs" creates "MyCustomLogs_CL".')
@minLength(1)
@maxLength(60)
param customTableBaseName string

@description('Create the custom table (true) or skip if it already exists.')
param createTable bool = true

@description('Interactive retention in days.')
@allowed([30, 60, 90, 120, 180, 270, 365, 550, 730])
param retentionInDays int = 90

@description('Total retention in days including archive.')
@minValue(30)
param totalRetentionInDays int = 180

@description('Description for the Data Collection Rule.')
param dcrDescription string = 'Custom ingestion via Logs Ingestion API'

@description('Description for the custom table.')
param tableDescription string = 'Custom table for direct log ingestion'

@description('Tags to apply to the DCR.')
param tags object = {}

@description('Columns for the custom table schema. Must include TimeGenerated.')
param tableColumns array = [
  {
    name: 'TimeGenerated'
    type: 'dateTime'
  }
  {
    name: 'Message'
    type: 'string'
  }
]

// ============================================================================
// VARIABLES
// ============================================================================

var tableName = '${customTableBaseName}_CL'
var streamName = 'Custom-${tableName}'
var destinationAlias = 'lawDest'

// Convert table columns to stream declaration format (dateTime -> datetime)
var streamColumns = [for col in tableColumns: {
  name: col.name
  type: col.type == 'dateTime' ? 'datetime' : col.type
}]

// ============================================================================
// EXISTING RESOURCES
// ============================================================================

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' existing = {
  name: dceName
}

// ============================================================================
// CUSTOM TABLE (OPTIONAL)
// ============================================================================

resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2023-09-01' = if (createTable) {
  parent: workspace
  name: tableName
  properties: {
    schema: {
      name: tableName
      description: tableDescription
      columns: tableColumns
    }
    retentionInDays: retentionInDays
    totalRetentionInDays: totalRetentionInDays
  }
}

// ============================================================================
// DATA COLLECTION RULE
// ============================================================================

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dcrName
  location: location
  tags: tags
  kind: 'Direct'
  properties: {
    description: dcrDescription
    dataCollectionEndpointId: dce.id

    destinations: {
      logAnalytics: [
        {
          name: destinationAlias
          workspaceResourceId: workspace.id
        }
      ]
    }

    streamDeclarations: {
      '${streamName}': {
        columns: streamColumns
      }
    }

    dataFlows: [
      {
        streams: [streamName]
        destinations: [destinationAlias]
        outputStream: streamName
        // Optional transform KQL if incoming payload differs from table schema:
        // transformKql: 'source | extend TimeGenerated = todatetime(TimeGenerated)'
      }
    ]
  }
  dependsOn: createTable ? [customTable] : []
}

// ============================================================================
// OUTPUTS
// ============================================================================

output dcrId string = dataCollectionRule.id
output dcrName string = dataCollectionRule.name
output dcrImmutableId string = dataCollectionRule.properties.immutableId
output tableName string = tableName
output streamName string = streamName
output dceId string = dce.id
output workspaceId string = workspace.id
output location string = dataCollectionRule.location
