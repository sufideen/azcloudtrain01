/*
  Hub-and-Spoke Network Architecture
  Deploys: Hub VNet, Spoke VNet, NSGs, App Gateway (WAF v2), Storage, VNet Peering
*/
targetScope = 'subscription'

@description('Environment name: dev | test | prod')
@allowed(['dev', 'test', 'prod'])
param environment string

@description('Azure region for all resources')
param location string = 'uksouth'

@description('Spoke VNet address space (e.g. 10.1.0.0/16 for dev)')
param spokeAddressPrefix string

@description('Hub VNet address space')
param hubAddressPrefix string = '10.0.0.0/16'

@description('Name prefix for all resources')
param namePrefix string = 'contoso'

@description('Tags applied to all resources')
param tags object = {
  environment: environment
  project: 'hub-spoke'
  managedBy: 'bicep'
}

// ── Resource Groups ─────────────────────────────────────────────────────────
resource hubRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-${namePrefix}-hub-${environment}'
  location: location
  tags: tags
}

resource spokeRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-${namePrefix}-spoke-${environment}'
  location: location
  tags: tags
}

resource storageRg 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-${namePrefix}-storage-${environment}'
  location: location
  tags: tags
}

// ── NSGs (deployed into spoke RG) ───────────────────────────────────────────
module nsgs 'modules/nsg.bicep' = {
  name: 'nsg-deployment'
  scope: spokeRg
  params: {
    location: location
    environment: environment
    namePrefix: namePrefix
    tags: tags
    appGatewaySubnetPrefix: cidrSubnet(hubAddressPrefix, 24, 2)  // 10.0.2.0/24
    bastionSubnetPrefix: cidrSubnet(hubAddressPrefix, 26, 12)    // 10.0.3.0/26
    spokeAddressPrefix: spokeAddressPrefix
  }
}

// ── Hub Network ─────────────────────────────────────────────────────────────
module hub 'modules/hub-network.bicep' = {
  name: 'hub-network-deployment'
  scope: hubRg
  params: {
    location: location
    environment: environment
    namePrefix: namePrefix
    hubAddressPrefix: hubAddressPrefix
    tags: tags
  }
}

// ── Spoke Network ───────────────────────────────────────────────────────────
module spoke 'modules/spoke-network.bicep' = {
  name: 'spoke-network-deployment'
  scope: spokeRg
  params: {
    location: location
    environment: environment
    namePrefix: namePrefix
    spokeAddressPrefix: spokeAddressPrefix
    tags: tags
    nsgWebId: nsgs.outputs.nsgWebId
    nsgAppId: nsgs.outputs.nsgAppId
    nsgDataId: nsgs.outputs.nsgDataId
    nsgAdminId: nsgs.outputs.nsgAdminId
  }
}

// ── VNet Peering ────────────────────────────────────────────────────────────
module peering 'modules/vnet-peering.bicep' = {
  name: 'vnet-peering-deployment'
  params: {
    hubRgName: hubRg.name
    spokeRgName: spokeRg.name
    hubVnetName: hub.outputs.vnetName
    spokeVnetName: spoke.outputs.vnetName
    hubVnetId: hub.outputs.vnetId
    spokeVnetId: spoke.outputs.vnetId
    environment: environment
  }
}

// ── App Gateway with WAF ─────────────────────────────────────────────────────
module appGateway 'modules/app-gateway.bicep' = {
  name: 'app-gateway-deployment'
  scope: hubRg
  params: {
    location: location
    environment: environment
    namePrefix: namePrefix
    tags: tags
    appGatewaySubnetId: hub.outputs.appGatewaySubnetId
  }
}

// ── Storage Account (Bicep artifacts + app data) ─────────────────────────────
module storage 'modules/storage.bicep' = {
  name: 'storage-deployment'
  scope: storageRg
  params: {
    location: location
    environment: environment
    namePrefix: namePrefix
    tags: tags
  }
}

// ── Outputs ──────────────────────────────────────────────────────────────────
output hubVnetId string = hub.outputs.vnetId
output spokeVnetId string = spoke.outputs.vnetId
output appGatewayPublicIp string = appGateway.outputs.publicIpAddress
output storageAccountName string = storage.outputs.accountName

// Instantiate the centralized environment Key Vault
module coreKeyVault './modules/key-vault.bicep' = {
  name: 'deploy-core-key-vault-${uniqueString(hubRg.id)}'
  scope: hubRg // Targets the Hub Resource Group declared on line 31
  params: {
    location: location
    vaultName: 'kv-alz-${environment}-${uniqueString(hubRg.id)}'
  }
}