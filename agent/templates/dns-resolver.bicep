targetScope = 'resourceGroup'

// ============================================================================
// AZURE DNS PRIVATE RESOLVER
// ============================================================================
// Deploys a DNS Private Resolver with:
// - Inbound endpoint (Static IP) for DNS queries from on-premises/peered VNets
// - Outbound endpoint (Dynamic IP) for forwarding DNS queries to on-premises
//
// Prerequisites:
// - VNet with two dedicated subnets (one for inbound, one for outbound)
// - Subnets must be delegated to Microsoft.Network/dnsResolvers
// - Subnets must be in the same VNet as the resolver
// ============================================================================

@description('Name of the DNS Private Resolver.')
@minLength(1)
@maxLength(80)
param dnsResolverName string

@description('Azure region for the DNS Resolver.')
param location string

@description('Resource ID of the Virtual Network for the DNS Resolver.')
param vnetId string

@description('Resource ID of the subnet for the inbound endpoint (must be delegated to Microsoft.Network/dnsResolvers).')
param inboundSubnetId string

@description('Static private IP address for the inbound endpoint.')
param inboundPrivateIpAddress string

@description('Resource ID of the subnet for the outbound endpoint (must be delegated to Microsoft.Network/dnsResolvers).')
param outboundSubnetId string

@description('Name for the inbound endpoint.')
param inboundEndpointName string = 'DNSInbound'

@description('Name for the outbound endpoint.')
param outboundEndpointName string = 'DNSOutbound'

@description('Optional tags for the resource.')
param tags object = {}

// ============================================================================
// DNS PRIVATE RESOLVER
// ============================================================================
resource dnsResolver 'Microsoft.Network/dnsResolvers@2022-07-01' = {
  name: dnsResolverName
  location: location
  tags: tags
  properties: {
    virtualNetwork: {
      id: vnetId
    }
  }
}

// ============================================================================
// INBOUND ENDPOINT (Static IP - receives DNS queries)
// ============================================================================
resource inboundEndpoint 'Microsoft.Network/dnsResolvers/inboundEndpoints@2022-07-01' = {
  parent: dnsResolver
  name: inboundEndpointName
  location: location
  properties: {
    ipConfigurations: [
      {
        subnet: {
          id: inboundSubnetId
        }
        privateIpAddress: inboundPrivateIpAddress
        privateIpAllocationMethod: 'Static'
      }
    ]
  }
}

// ============================================================================
// OUTBOUND ENDPOINT (Dynamic IP - forwards DNS queries)
// ============================================================================
resource outboundEndpoint 'Microsoft.Network/dnsResolvers/outboundEndpoints@2022-07-01' = {
  parent: dnsResolver
  name: outboundEndpointName
  location: location
  properties: {
    subnet: {
      id: outboundSubnetId
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================
output dnsResolverId string = dnsResolver.id
output dnsResolverName string = dnsResolver.name
output inboundEndpointId string = inboundEndpoint.id
output inboundIpAddress string = inboundPrivateIpAddress
output outboundEndpointId string = outboundEndpoint.id
