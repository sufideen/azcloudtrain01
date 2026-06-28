@description('The Azure region where the Route Table will be provisioned.')
param location string = resourceGroup().location

@description('The name of the Route Table.')
param routeTableName string = 'rt-alz-hub-egress'

@description('The internal private IP address of the central Azure Firewall to act as the Next Hop.')
param firewallPrivateIp string

resource routeTable 'Microsoft.Network/routeTables@2023-11-01' = {
  name: routeTableName
  location: location
  properties: {
    disableBgpRoutePropagation: false
    routes: [
      {
        name: 'udr-default-egress-to-fw'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: firewallPrivateIp
        }
      }
    ]
  }
}

output routeTableId string = routeTable.id
