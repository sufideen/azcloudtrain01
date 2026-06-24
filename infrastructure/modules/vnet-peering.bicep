/*
  Bidirectional VNet peering between hub and spoke.
  Requires two separate deployments scoped to each resource group.
*/
targetScope = 'subscription'

param hubRgName string
param spokeRgName string
param hubVnetName string
param spokeVnetName string
param hubVnetId string
param spokeVnetId string
param environment string

// Hub → Spoke peering
module hubToSpoke 'vnet-peering-single.bicep' = {
  name: 'peering-hub-to-spoke'
  scope: resourceGroup(hubRgName)
  params: {
    localVnetName: hubVnetName
    remoteVnetId: spokeVnetId
    peeringName: 'peer-hub-to-spoke-${environment}'
    allowGatewayTransit: true
    useRemoteGateways: false
  }
}

// Spoke → Hub peering
module spokeToHub 'vnet-peering-single.bicep' = {
  name: 'peering-spoke-to-hub'
  scope: resourceGroup(spokeRgName)
  params: {
    localVnetName: spokeVnetName
    remoteVnetId: hubVnetId
    peeringName: 'peer-spoke-to-hub-${environment}'
    allowGatewayTransit: false
    useRemoteGateways: false
  }
  dependsOn: [hubToSpoke]
}
