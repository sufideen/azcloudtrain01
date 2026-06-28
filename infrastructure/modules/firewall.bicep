@description('The Azure region where the firewall will be provisioned.')
param location string = resourceGroup().location

@description('The resource ID of the existing Hub Virtual Network.')
param hubVnetId string

// 1. Centralised Firewall Policy
resource firewallPolicy 'Microsoft.Network/firewallPolicies@2023-11-01' = {
  name: 'fw-alz-hub-policy'
  location: location
  properties: {
    sku: { tier: 'Standard' }
    threatIntelMode: 'Alert'
  }
}

// 2. Public IP for SNAT egress
resource firewallPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-alz-hub-fw'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

// 3. Azure Firewall instance
resource azureFirewall 'Microsoft.Network/azureFirewalls@2023-11-01' = {
  name: 'fw-alz-hub-central'
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
    }
    firewallPolicy: { id: firewallPolicy.id }
    ipConfigurations: [
      {
        name: 'fw-ip-config'
        properties: {
          publicIPAddress: { id: firewallPip.id }
          subnet: { id: '${hubVnetId}/subnets/AzureFirewallSubnet' }
        }
      }
    ]
  }
}

output firewallPrivateIp string = azureFirewall.properties.ipConfigurations[0].properties.privateIPAddress
output firewallName string = azureFirewall.name
