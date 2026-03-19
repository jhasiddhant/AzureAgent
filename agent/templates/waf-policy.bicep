targetScope = 'resourceGroup'

// ============================================================================
// AZURE FRONT DOOR WAF POLICY
// ============================================================================
// This template creates a Web Application Firewall (WAF) policy for Azure Front Door
// with Prevention mode and Premium SKU enabled by default for maximum security.
//
// Features:
// - Premium SKU by default for advanced protection
// - Prevention mode by default (blocks malicious requests)
// - Microsoft Default Rule Set 2.1 included
// - Bot Manager Rule Set 1.1 included
// - Configurable rate limiting rule
// ============================================================================

@description('Name of the WAF policy.')
@minLength(1)
@maxLength(128)
param wafPolicyName string

@description('SKU for the WAF policy.')
@allowed([
  'Premium_AzureFrontDoor'
  'Standard_AzureFrontDoor'
  'Classic_AzureFrontDoor'
])
param skuName string = 'Premium_AzureFrontDoor'

@description('WAF policy mode.')
@allowed([
  'Prevention'
  'Detection'
])
param mode string = 'Prevention'

@description('Enable or disable the WAF policy.')
@allowed([
  'Enabled'
  'Disabled'
])
param enabledState string = 'Enabled'

@description('Custom block response status code.')
@allowed([
  200
  403
  405
  406
  429
])
param customBlockResponseStatusCode int = 403

@description('Enable request body inspection.')
@allowed([
  'Enabled'
  'Disabled'
])
param requestBodyCheck string = 'Enabled'

@description('JavaScript challenge expiration in minutes.')
@minValue(5)
@maxValue(1440)
param javascriptChallengeExpirationInMinutes int = 30

@description('Enable rate limiting rule.')
param enableRateLimiting bool = true

@description('Rate limit threshold (requests per duration).')
@minValue(1)
param rateLimitThreshold int = 100

@description('Rate limit duration in minutes.')
@minValue(1)
@maxValue(5)
param rateLimitDurationInMinutes int = 5

@description('Enable Microsoft Default Rule Set.')
param enableDefaultRuleSet bool = true

@description('Microsoft Default Rule Set version.')
@allowed([
  '2.1'
  '2.0'
  '1.1'
])
param defaultRuleSetVersion string = '2.1'

@description('Enable Bot Manager Rule Set (Premium only).')
param enableBotManagerRuleSet bool = true

@description('Bot Manager Rule Set version.')
@allowed([
  '1.1'
  '1.0'
])
param botManagerRuleSetVersion string = '1.1'

@description('Resource tags.')
param tags object = {}

// ============================================================================
// VARIABLES
// ============================================================================

// Build managed rule sets array based on parameters
var defaultRuleSet = enableDefaultRuleSet ? [
  {
    ruleSetType: 'Microsoft_DefaultRuleSet'
    ruleSetVersion: defaultRuleSetVersion
    ruleSetAction: 'Block'
    ruleGroupOverrides: []
    exclusions: []
  }
] : []

var botManagerRuleSet = enableBotManagerRuleSet && skuName == 'Premium_AzureFrontDoor' ? [
  {
    ruleSetType: 'Microsoft_BotManagerRuleSet'
    ruleSetVersion: botManagerRuleSetVersion
    ruleGroupOverrides: []
    exclusions: []
  }
] : []

var managedRuleSets = concat(defaultRuleSet, botManagerRuleSet)

// Rate limiting rule configuration
var rateLimitRule = enableRateLimiting ? [
  {
    name: 'RateLimitRule'
    enabledState: 'Enabled'
    priority: 100
    ruleType: 'RateLimitRule'
    rateLimitDurationInMinutes: rateLimitDurationInMinutes
    rateLimitThreshold: rateLimitThreshold
    matchConditions: [
      {
        matchVariable: 'SocketAddr'
        operator: 'IPMatch'
        negateCondition: false
        matchValue: [
          '0.0.0.0/0'
          '::/0'
        ]
        transforms: []
      }
    ]
    action: 'Block'
    groupBy: [
      {
        variableName: 'SocketAddr'
      }
    ]
  }
] : []

// ============================================================================
// RESOURCES
// ============================================================================

resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: wafPolicyName
  location: 'Global'
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    policySettings: {
      enabledState: enabledState
      mode: mode
      customBlockResponseStatusCode: customBlockResponseStatusCode
      requestBodyCheck: requestBodyCheck
      javascriptChallengeExpirationInMinutes: javascriptChallengeExpirationInMinutes
    }
    customRules: {
      rules: rateLimitRule
    }
    managedRules: {
      managedRuleSets: managedRuleSets
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('The resource ID of the WAF policy.')
output wafPolicyId string = wafPolicy.id

@description('The name of the WAF policy.')
output wafPolicyName string = wafPolicy.name

@description('The SKU name of the WAF policy.')
output skuName string = wafPolicy.sku.name
