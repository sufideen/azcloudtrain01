/*
  Hub VNet: App Gateway subnet, Firewall subnet, Bastion subnet, Gateway subnet
*/
param location string
param environment string
param namePrefix string
param hubAddressPrefix string
param tags object

var hubName = 'vnet-${namePrefix}-hub-${environment}'

// Subnets carved from hubAddressPrefix (default 10.0.0.0/16)
var gatewaySubnet   = cidrSubnet(hubAddressPrefix, 27, 0)   // /27 — VPN/ER gateway
var firewallSubnet  = cidrSubnet(hubAddressPrefix, 26, 4)   // /26 — Azure Firewall
var appGwSubnet     = cidrSubnet(hubAddressPrefix, 24, 2)   // /24 — App Gateway
var bastionSubnet   = cidrSubnet(hubAddressPrefix, 26, 12)  // /26 — Azure Bastion

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: hubName
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [hubAddressPrefix] }
    subnets: [
      {
        name: 'GatewaySubnet'
        properties: { addressPrefix: gatewaySubnet }
      }
      {
        name: 'AzureFirewallSubnet'
        properties: { addressPrefix: firewallSubnet }
      }
      {
        name: 'AppGatewaySubnet'
        properties: { addressPrefix: appGwSubnet }
      }
      {
        name: 'AzureBastionSubnet'
        properties: { addressPrefix: bastionSubnet }

      }


    ]
  }
}

output vnetId string = hubVnet.id
output vnetName string = hubVnet.name
output appGatewaySubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', hubName, 'AppGatewaySubnet')
output bastionSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', hubName, 'AzureBastionSubnet')
module hubFirewall './firewall.bicep' = {
  name: 'deploy-hub-firewall'
  params: {
    location: resourceGroup().location
    hubVnetId: hubVnet.id
  }
}
