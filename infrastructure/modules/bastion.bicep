/*
  Azure Bastion Standard SKU
  Enables native RDP/SSH tunneling to VMs without exposing public IPs
*/
param location string
param environment string
param namePrefix string
param tags object
param bastionSubnetId string

resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'pip-bas-${namePrefix}-${environment}'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-09-01' = {
  name: 'bas-${namePrefix}-${environment}'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    enableTunneling: true      // az network bastion ssh / rdp native client
    enableIpConnect: true      // connect via private IP without FQDN
    ipConfigurations: [
      {
        name: 'basIpConfig'
        properties: {
          publicIPAddress: { id: bastionPip.id }
          subnet: { id: bastionSubnetId }
        }
      }
    ]
  }
}

output bastionId string = bastion.id
output bastionName string = bastion.name
output bastionPublicIp string = bastionPip.properties.ipAddress
