targetScope = 'resourceGroup'

// ============================================================================
// AZURE CONTAINER APP
// ============================================================================
// This template creates a Container App in an existing Container Apps Environment
// using the default Microsoft quickstart image.
//
// Requirements:
// - Existing Container Apps Environment in the same Resource Group
// ============================================================================

@description('Name of the Container App.')
@minLength(2)
@maxLength(32)
param containerAppName string

@description('Region for the Container App. Should match the Container Apps Environment region.')
param location string

@description('Name of the existing Container Apps Environment.')
param environmentName string

@description('Target port the container listens on.')
param targetPort int = 80

@description('Enable external ingress (publicly accessible).')
param externalIngress bool = true

@description('CPU cores allocated to the container (e.g., 0.25, 0.5, 1, 2).')
@allowed([
  '0.25'
  '0.5'
  '0.75'
  '1'
  '1.25'
  '1.5'
  '1.75'
  '2'
  '4'
])
param cpu string = '0.5'

@description('Memory allocated to the container (e.g., 0.5Gi, 1Gi, 2Gi).')
@allowed([
  '0.5Gi'
  '1Gi'
  '1.5Gi'
  '2Gi'
  '3Gi'
  '3.5Gi'
  '4Gi'
  '8Gi'
])
param memory string = '1Gi'

@description('Minimum number of replicas.')
@minValue(0)
@maxValue(30)
param minReplicas int = 0

@description('Maximum number of replicas.')
@minValue(1)
@maxValue(30)
param maxReplicas int = 10

@description('Environment variables as JSON array: [{"name":"VAR1","value":"val1"}]')
param envVars array = []

@description('Workload profile name to use. Use "Consumption" for serverless.')
param workloadProfileName string = 'Consumption'

// ============================================================================
// VARIABLES
// ============================================================================

var containerImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

// ============================================================================
// EXISTING RESOURCES
// ============================================================================

// Reference existing Container Apps Environment
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: environmentName
}

// ============================================================================
// CONTAINER APP
// ============================================================================

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    workloadProfileName: workloadProfileName
    
    configuration: {
      // Ingress Configuration
      ingress: {
        external: externalIngress
        targetPort: targetPort
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            weight: 100
            latestRevision: true
          }
        ]
      }
      
      // Secrets (if needed)
      secrets: []
    }
    
    template: {
      containers: [
        {
          name: containerAppName
          image: containerImage
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: envVars
        }
      ]
      
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output containerAppId string = containerApp.id
output containerAppName string = containerApp.name
output fqdn string = containerApp.properties.configuration.ingress.fqdn
output latestRevisionName string = containerApp.properties.latestRevisionName
output containerImage string = containerImage
output environmentId string = containerAppsEnvironment.id
