targetScope = 'resourceGroup'

// ============================================================================
// AZURE FRONT DOOR (CDN Profile)
// ============================================================================
// Deploys an Azure Front Door Premium profile with:
// - Premium_AzureFrontDoor SKU by default
// - AFD Endpoint (enabled by default)
// - Origin Group with health probing
// - Origin pointing to backend host
// - Default route with HTTPS redirect
// - Security policy attaching a WAF policy (mandatory)
// ============================================================================

@description('Name of the Front Door profile.')
@minLength(1)
@maxLength(260)
param frontDoorName string

@description('Azure region. Front Door is a global resource.')
param location string = 'Global'

@description('Front Door SKU.')
@allowed([
  'Premium_AzureFrontDoor'
  'Standard_AzureFrontDoor'
])
param skuName string = 'Premium_AzureFrontDoor'

@description('Name of the AFD endpoint.')
param endpointName string = ''

@description('Resource ID of the WAF policy to attach.')
param wafPolicyId string

@description('Origin host name (e.g., myapp.azurewebsites.net or mysa.z5.web.core.windows.net).')
param originHostName string

@description('Origin host header (defaults to originHostName).')
param originHostHeader string = ''

@description('Name of the origin group.')
param originGroupName string = 'default-origin-group'

@description('Name of the origin.')
param originName string = 'default-origin'

@description('Origin HTTP port.')
param httpPort int = 80

@description('Origin HTTPS port.')
param httpsPort int = 443

@description('Origin priority.')
@minValue(1)
@maxValue(5)
param originPriority int = 1

@description('Origin weight.')
@minValue(1)
@maxValue(1000)
param originWeight int = 1000

@description('Health probe path.')
param healthProbePath string = '/'

@description('Health probe request type.')
@allowed([
  'HEAD'
  'GET'
])
param healthProbeRequestType string = 'HEAD'

@description('Health probe protocol.')
@allowed([
  'Http'
  'Https'
])
param healthProbeProtocol string = 'Http'

@description('Health probe interval in seconds.')
@minValue(5)
@maxValue(120)
param healthProbeIntervalInSeconds int = 100

@description('Load balancing sample size.')
@minValue(1)
param loadBalancingSampleSize int = 4

@description('Successful samples required for healthy origin.')
@minValue(1)
param loadBalancingSuccessfulSamplesRequired int = 3

@description('Additional latency in milliseconds for load balancing.')
param loadBalancingAdditionalLatencyMs int = 50

@description('Session affinity state.')
@allowed([
  'Enabled'
  'Disabled'
])
param sessionAffinityState string = 'Disabled'

@description('Origin response timeout in seconds.')
@minValue(16)
@maxValue(240)
param originResponseTimeoutSeconds int = 60

@description('Forwarding protocol for the default route.')
@allowed([
  'MatchRequest'
  'HttpOnly'
  'HttpsOnly'
])
param forwardingProtocol string = 'MatchRequest'

@description('Enable HTTPS redirect on the default route.')
@allowed([
  'Enabled'
  'Disabled'
])
param httpsRedirect string = 'Enabled'

@description('Enable caching on the default route.')
param enableCaching bool = false

@description('Query string caching behavior.')
@allowed([
  'IgnoreQueryString'
  'UseQueryString'
  'IgnoreSpecifiedQueryStrings'
  'IncludeSpecifiedQueryStrings'
])
param queryStringCachingBehavior string = 'IgnoreQueryString'

@description('Resource tags.')
param tags object = {}

// ============================================================================
// VARIABLES
// ============================================================================

var resolvedEndpointName = !empty(endpointName) ? endpointName : frontDoorName
var resolvedOriginHostHeader = !empty(originHostHeader) ? originHostHeader : originHostName

var cacheConfig = enableCaching ? {
  compressionSettings: {
    isCompressionEnabled: false
    contentTypesToCompress: []
  }
  queryStringCachingBehavior: queryStringCachingBehavior
} : null

// ============================================================================
// FRONT DOOR PROFILE
// ============================================================================
resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-09-01' = {
  name: frontDoorName
  location: location
  tags: tags
  sku: {
    name: skuName
  }
  properties: {
    originResponseTimeoutSeconds: originResponseTimeoutSeconds
  }
}

// ============================================================================
// AFD ENDPOINT
// ============================================================================
resource afdEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-09-01' = {
  parent: frontDoorProfile
  name: resolvedEndpointName
  location: location
  properties: {
    enabledState: 'Enabled'
  }
}

// ============================================================================
// ORIGIN GROUP
// ============================================================================
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-09-01' = {
  parent: frontDoorProfile
  name: originGroupName
  properties: {
    loadBalancingSettings: {
      sampleSize: loadBalancingSampleSize
      successfulSamplesRequired: loadBalancingSuccessfulSamplesRequired
      additionalLatencyInMilliseconds: loadBalancingAdditionalLatencyMs
    }
    healthProbeSettings: {
      probePath: healthProbePath
      probeRequestType: healthProbeRequestType
      probeProtocol: healthProbeProtocol
      probeIntervalInSeconds: healthProbeIntervalInSeconds
    }
    sessionAffinityState: sessionAffinityState
  }
}

// ============================================================================
// ORIGIN
// ============================================================================
resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-09-01' = {
  parent: originGroup
  name: originName
  properties: {
    hostName: originHostName
    httpPort: httpPort
    httpsPort: httpsPort
    originHostHeader: resolvedOriginHostHeader
    priority: originPriority
    weight: originWeight
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// ============================================================================
// SECURITY POLICY (WAF ATTACHMENT)
// ============================================================================
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-09-01' = {
  parent: frontDoorProfile
  name: '${resolvedEndpointName}-waf'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicyId
      }
      associations: [
        {
          domains: [
            {
              id: afdEndpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

// ============================================================================
// DEFAULT ROUTE
// ============================================================================
resource defaultRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-09-01' = {
  parent: afdEndpoint
  name: 'default-route'
  properties: {
    cacheConfiguration: cacheConfig
    customDomains: []
    originGroup: {
      id: originGroup.id
    }
    ruleSets: []
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: forwardingProtocol
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: httpsRedirect
    enabledState: 'Enabled'
  }
  dependsOn: [
    origin
  ]
}

// ============================================================================
// OUTPUTS
// ============================================================================
output frontDoorId string = frontDoorProfile.id
output frontDoorName string = frontDoorProfile.name
output endpointHostName string = afdEndpoint.properties.hostName
output endpointId string = afdEndpoint.id
output originGroupId string = originGroup.id
