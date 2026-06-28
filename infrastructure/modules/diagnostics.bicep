/*
  Centralised observability: Log Analytics Workspace + Diagnostic Settings
  Attaches to App Gateway and Azure Firewall in the hub resource group.
  Retention: 30 days dev/test, 90 days prod.
*/
param location string
param environment string
param namePrefix string
param tags object
param appGatewayName string
param firewallName string

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${namePrefix}-${environment}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: environment == 'prod' ? 90 : 30
    features: { enableLogAccessUsingOnlyResourcePermissions: true }
  }
}

// ── App Gateway diagnostics ──────────────────────────────────────────────────
resource appGatewayExisting 'Microsoft.Network/applicationGateways@2023-09-01' existing = {
  name: appGatewayName
}

resource appGwDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-appgw-to-law'
  scope: appGatewayExisting
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      { category: 'ApplicationGatewayAccessLog',      enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'ApplicationGatewayPerformanceLog',  enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'ApplicationGatewayFirewallLog',     enabled: true, retentionPolicy: { enabled: false, days: 0 } }
    ]
    metrics: [{ category: 'AllMetrics', enabled: true, retentionPolicy: { enabled: false, days: 0 } }]
  }
}

// ── Azure Firewall diagnostics ───────────────────────────────────────────────
resource firewallExisting 'Microsoft.Network/azureFirewalls@2023-09-01' existing = {
  name: firewallName
}

resource firewallDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-fw-to-law'
  scope: firewallExisting
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      { category: 'AzureFirewallApplicationRule', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'AzureFirewallNetworkRule',     enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'AzureFirewallDnsProxy',        enabled: true, retentionPolicy: { enabled: false, days: 0 } }
    ]
    metrics: [{ category: 'AllMetrics', enabled: true, retentionPolicy: { enabled: false, days: 0 } }]
  }
}

output logAnalyticsId string = logAnalytics.id
output logAnalyticsName string = logAnalytics.name
