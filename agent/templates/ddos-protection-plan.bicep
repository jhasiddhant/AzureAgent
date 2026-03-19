targetScope = 'resourceGroup'

// ============================================================================
// AZURE DDOS PROTECTION PLAN
// ============================================================================
// Deploys a DDoS Protection Plan to protect VNet resources from DDoS attacks.
// Associate this plan with VNets to enable DDoS Protection Standard.
// ============================================================================

@description('Name of the DDoS Protection Plan.')
@minLength(1)
@maxLength(80)
param ddosProtectionPlanName string

@description('Azure region for the DDoS Protection Plan.')
param location string

@description('Optional tags for the resource.')
param tags object = {}

// ============================================================================
// DDOS PROTECTION PLAN
// ============================================================================
resource ddosProtectionPlan 'Microsoft.Network/ddosProtectionPlans@2024-07-01' = {
  name: ddosProtectionPlanName
  location: location
  tags: tags
  properties: {}
}

// ============================================================================
// OUTPUTS
// ============================================================================
output ddosProtectionPlanId string = ddosProtectionPlan.id
output ddosProtectionPlanName string = ddosProtectionPlan.name
