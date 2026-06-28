@description('The Azure region where the Bastion Host will be provisioned.')
param location string = resourceGroup().location

@description('The resource ID of the target Hub Virtual Network.')
param hubVnetId string

resource bastionPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-alz-hub-bastion'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastionHost 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: 'bas-alz-hub-core'
  location: location
  sku: {
    name: 'Standard' // Standard SKU unlocks native client SSH/RDP support
  }
  properties: {
    ipConfigurations: [
      {
        name: 'bastion-ip-config'
        properties: {
          publicIPAddress: {
            id: bastionPip.id
          }
          subnet: {
            id: '${hubVnetId}/subnets/AzureBastionSubnet'
          }
        }
      }
    ]
  }
}