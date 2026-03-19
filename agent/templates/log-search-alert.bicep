targetScope = 'resourceGroup'

// ============================================================================
// LOG SEARCH ALERT RULE
// ============================================================================
// Deploys a Scheduled Query Rule (Log Search Alert) that:
// - Runs a KQL query against a Log Analytics Workspace
// - Triggers an Action Group when conditions are met
// - Supports configurable severity, frequency, and evaluation
// ============================================================================

@description('Name of the alert rule.')
@minLength(1)
@maxLength(260)
param alertRuleName string

@description('Azure region for the alert rule.')
param location string

@description('Resource ID of the Log Analytics Workspace to query.')
param workspaceId string

@description('KQL query to evaluate.')
param kqlQuery string

@description('Resource ID of the Action Group to notify.')
param actionGroupId string

@description('Display name for the alert rule (defaults to alertRuleName).')
param displayName string = ''

@description('Alert severity level.')
@allowed([
  0
  1
  2
  3
  4
])
param severity int = 1

@description('Enable the alert rule.')
param enabled bool = true

@description('Evaluation frequency in ISO 8601 duration format (e.g., PT5M for 5 minutes).')
param evaluationFrequency string = 'PT5M'

@description('Window size for evaluation in ISO 8601 duration format (e.g., PT5M for 5 minutes).')
param windowSize string = 'PT5M'

@description('Auto-mitigate (auto-resolve) the alert when condition is no longer met.')
param autoMitigate bool = false

@description('Number of consecutive evaluation failures before triggering alert.')
@minValue(1)
@maxValue(6)
param numberOfEvaluationFailures int = 1

@description('Number of evaluation periods for failing periods.')
@minValue(1)
@maxValue(6)
param numberOfEvaluationPeriods int = 1

@description('Optional tags for the resource.')
param tags object = {}

// ============================================================================
// VARIABLES
// ============================================================================

var resolvedDisplayName = !empty(displayName) ? displayName : alertRuleName

// ============================================================================
// LOG SEARCH ALERT RULE
// ============================================================================
resource alertRule 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: alertRuleName
  location: location
  tags: tags
  properties: {
    displayName: resolvedDisplayName
    severity: severity
    enabled: enabled
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    scopes: [
      workspaceId
    ]
    targetResourceTypes: [
      'Microsoft.OperationalInsights/workspaces'
    ]
    criteria: {
      allOf: [
        {
          query: kqlQuery
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: numberOfEvaluationPeriods
            minFailingPeriodsToAlert: numberOfEvaluationFailures
          }
        }
      ]
    }
    autoMitigate: autoMitigate
    actions: {
      actionGroups: [
        actionGroupId
      ]
      customProperties: {}
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================
output alertRuleId string = alertRule.id
output alertRuleName string = alertRule.name
