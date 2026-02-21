targetScope = 'resourceGroup'

@description('Public IP address name.')
param publicIPName string

@description('Azure region for the Public IP address.')
param location string

@description('SKU name for the Public IP address.')
@allowed([
  'Basic'
  'Standard'
])
param skuName string = 'Standard'

@description('SKU tier for the Public IP address.')
@allowed([
  'Regional'
  'Global'
])
param skuTier string = 'Regional'

@description('Public IP allocation method.')
@allowed([
  'Static'
  'Dynamic'
])
param allocationMethod string = 'Static'

@description('IP address version.')
@allowed([
  'IPv4'
  'IPv6'
])
param ipVersion string = 'IPv4'

@description('Availability zones for the Public IP (empty array for no zones).')
param zones array = [
  '1'
  '2'
  '3'
]

@description('Idle timeout in minutes (4-30).')
@minValue(4)
@maxValue(30)
param idleTimeoutInMinutes int = 4

@description('Optional DNS domain name label (must be unique within region).')
param domainNameLabel string = ''

@description('IP tags for routing and policy purposes.')
param ipTags array = [
  {
    ipTagType: 'FirstPartyUsage'
    tag: '/Unprivileged'
  }
]

resource publicIP 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: publicIPName
  location: location
  sku: {
    name: skuName
    tier: skuTier
  }
  zones: zones
  properties: {
    publicIPAddressVersion: ipVersion
    publicIPAllocationMethod: allocationMethod
    idleTimeoutInMinutes: idleTimeoutInMinutes
    ipTags: ipTags
    dnsSettings: domainNameLabel != '' ? {
      domainNameLabel: domainNameLabel
    } : null
  }
}

output publicIPId string = publicIP.id
output publicIPAddress string = publicIP.properties.ipAddress
output fqdn string = domainNameLabel != '' ? publicIP.properties.dnsSettings.fqdn : ''
