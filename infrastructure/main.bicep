/*
  Hub-and-Spoke Network Architecture — Phase 2
  Deploys: Hub VNet, Spoke VNet, NSGs, Azure Firewall, Azure Bastion,
           App Gateway (WAF v2), Key Vault, Storage, VNet Peering,
           Log Analytics diagnostics, Cost Management budget alerts
*/
targetScope = 'subscription'

@description('Environment name: dev | test | prod')
@allowed(['dev', 'test', 'prod'])
param environment string

@description('Azure region for all resources')
param location string = 'uksouth'

@description('Spoke VNet address space')
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

@description('Email address for cost budget and monitoring alerts')
param alertEmail string

@description('Monthly budget threshold in GBP — alerts fire at 80%, 100%, and 110% forecast')
param monthlyBudgetGbp int = 1500

@description('Key Vault secret URI for the TLS certificate. Run bootstrap-ssl.sh then re-deploy to activate HTTPS.')
param keyVaultCertSecretUri string = ''

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

// ── User-assigned identity (App Gateway → Key Vault cert access) ────────────────
module appGwIdentity 'modules/identity.bicep' = {
  name: 'identity-deployment'
  scope: hubRg
  params: {
    location: location
    namePrefix: namePrefix
    environment: environment
    tags: tags
  }
}

// ── Key Vault (hub RG) ──────────────────────────────────────────────────────────
module kv 'modules/keyvault.bicep' = {
  name: 'keyvault-deployment'
  scope: hubRg
  params: {
    location: location
    environment: environment
    namePrefix: namePrefix
    tags: tags
    appGatewayPrincipalId: appGwIdentity.outputs.principalId
  }
}

// ── NSGs (spoke RG) ──────────────────────────────────────────────────────────────
module nsgs 'modules/nsg.bicep' = {
  name: 'nsg-deployment'
  scope: spokeRg
  params: {
    location: location
    environment: environment
    namePrefix: namePrefix
    tags: tags
    appGatewaySubnetPrefix: cidrSubnet(hubAddressPrefix, 24, 2)
    bastionSubnetPrefix: cidrSubnet(hubAddressPrefix, 26, 12)
    spokeAddressPrefix: spokeAddressPrefix
  }
}

// ── Hub Network (VNet + Firewall + Bastion) ────────────────────────────────────
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

// ── Spoke Network ─────────────────────────────────────────────────────────────
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

// ── VNet Peering ─────────────────────────────────────────────────────────────────
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

// ── App Gateway (WAF v2 + optional HTTPS via Key Vault) ────────────────────────
module appGateway 'modules/app-gateway.bicep' = {
  name: 'app-gateway-deployment'
  scope: hubRg
  params: {
    location: location
    environment: environment
    namePrefix: namePrefix
    tags: tags
    appGatewaySubnetId: hub.outputs.appGatewaySubnetId
    managedIdentityId: appGwIdentity.outputs.identityId
    keyVaultCertSecretUri: keyVaultCertSecretUri
  }
}

// ── Storage Account ──────────────────────────────────────────────────────────────
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

// ── Centralised Diagnostics (Log Analytics + diagnostic settings) ───────────────
module diagnostics 'modules/diagnostics.bicep' = {
  name: 'diagnostics-deployment'
  scope: hubRg
  params: {
    location: location
    environment: environment
    namePrefix: namePrefix
    tags: tags
    appGatewayName: appGateway.outputs.appGatewayName
    firewallName: hub.outputs.firewallName
  }
}

// ── Cost Management Budget (subscription scope) ───────────────────────────────
resource budget 'Microsoft.Consumption/budgets@2023-05-01' = {
  name: 'budget-hub-spoke-${environment}'
  properties: {
    category: 'Cost'
    amount: monthlyBudgetGbp
    timeGrain: 'Monthly'
    timePeriod: { startDate: '2026-06-01' }
    filter: {
      dimensions: {
        name: 'ResourceGroupName'
        operator: 'In'
        values: [
          hubRg.name
          spokeRg.name
          storageRg.name
        ]
      }
    }
    notifications: {
      Actual_80Pct: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 80
        contactEmails: [alertEmail]
        thresholdType: 'Actual'
      }
      Actual_100Pct: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 100
        contactEmails: [alertEmail]
        thresholdType: 'Actual'
      }
      Forecasted_110Pct: {
        enabled: true
        operator: 'GreaterThan'
        threshold: 110
        contactEmails: [alertEmail]
        thresholdType: 'Forecasted'
      }
    }
  }
}

// ── Outputs ──────────────────────────────────────────────────────────────────
output hubVnetId string = hub.outputs.vnetId
output spokeVnetId string = spoke.outputs.vnetId
output appGatewayPublicIp string = appGateway.outputs.publicIpAddress
output storageAccountName string = storage.outputs.accountName
output keyVaultName string = kv.outputs.keyVaultName
output keyVaultUri string = kv.outputs.keyVaultUri
output logAnalyticsName string = diagnostics.outputs.logAnalyticsName
output firewallPrivateIp string = hub.outputs.firewallPrivateIp
output bastionName string = hub.outputs.bastionName
