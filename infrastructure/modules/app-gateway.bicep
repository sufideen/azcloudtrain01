/*
  Application Gateway WAF v2 (OWASP 3.2 + BotManager)
  HTTP is always active.
  HTTPS activates when keyVaultCertSecretUri is provided (run bootstrap-ssl.sh first).
  WAF: Detection mode for dev/test, Prevention for prod.
*/
param location string
param environment string
param namePrefix string
param tags object
param appGatewaySubnetId string
param managedIdentityId string = ''        // user-assigned identity for KV cert access
@secure()
param keyVaultCertSecretUri string = ''

var appGwName     = 'agw-${namePrefix}-${environment}'
var pipName       = 'pip-agw-${namePrefix}-${environment}'
var wafPolicyName = 'waf-${namePrefix}-${environment}'
var wafMode       = environment == 'prod' ? 'Prevention' : 'Detection'
var capacity      = environment == 'prod' ? 2 : 1
var httpsEnabled  = !empty(keyVaultCertSecretUri) && !empty(managedIdentityId)

// ── Public IP ──────────────────────────────────────────────────────────────────
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: pipName
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: { domainNameLabel: '${namePrefix}-${environment}' }
  }
}

// ── WAF Policy (standalone — not the deprecated inline config) ──────────────────
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-09-01' = {
  name: wafPolicyName
  location: location
  tags: tags
  properties: {
    policySettings: {
      state: 'Enabled'
      mode: wafMode
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    }
    managedRules: {
      managedRuleSets: [
        { ruleSetType: 'OWASP',                      ruleSetVersion: '3.2' }
        { ruleSetType: 'Microsoft_BotManagerRuleSet', ruleSetVersion: '1.0' }
      ]
    }
    customRules: [
      {
        name: 'BlockSQLi'
        priority: 10
        ruleType: 'MatchRule'
        action: 'Block'
        matchConditions: [
          {
            matchVariables: [{ variableName: 'QueryString', selector: null }]
            operator: 'Contains'
            negationConditon: false
            matchValues: ['select ', 'union ', 'drop ', 'insert ', '--']
            transforms: ['Lowercase', 'UrlDecode']
          }
        ]
      }
    ]
  }
}

// ── Conditional HTTPS building blocks ─────────────────────────────────────────────
var extraFrontendPorts = httpsEnabled ? [
  { name: 'port-443', properties: { port: 443 } }
] : []

var sslCertificates = httpsEnabled ? [
  { name: 'kv-ssl-cert', properties: { keyVaultSecretId: keyVaultCertSecretUri } }
] : []

var httpsListeners = httpsEnabled ? [
  {
    name: 'httpsListener'
    properties: {
      frontendIPConfiguration: { id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, 'appGwFrontendIp') }
      frontendPort:            { id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, 'port-443') }
      protocol: 'Https'
      sslCertificate: { id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', appGwName, 'kv-ssl-cert') }
    }
  }
] : []

// HTTP redirects to HTTPS when cert is present; otherwise routes to backend directly
var httpRedirectConfigs = httpsEnabled ? [
  {
    name: 'httpToHttps'
    properties: {
      redirectType: 'Permanent'
      targetListener: { id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, 'httpsListener') }
      includePath: true
      includeQueryString: true
    }
  }
] : []

var httpRoutingRule = httpsEnabled ? {
  name: 'httpRedirectRule'
  properties: {
    ruleType: 'Basic'
    priority: 100
    httpListener:          { id: resourceId('Microsoft.Network/applicationGateways/httpListeners',         appGwName, 'httpListener') }
    redirectConfiguration: { id: resourceId('Microsoft.Network/applicationGateways/redirectConfigurations', appGwName, 'httpToHttps') }
  }
} : {
  name: 'httpRule'
  properties: {
    ruleType: 'Basic'
    priority: 100
    httpListener:       { id: resourceId('Microsoft.Network/applicationGateways/httpListeners',              appGwName, 'httpListener') }
    backendAddressPool: { id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools',        appGwName, 'webBackendPool') }
    backendHttpSettings:{ id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, 'httpSettings') }
  }
}

var httpsRoutingRules = httpsEnabled ? [
  {
    name: 'httpsRule'
    properties: {
      ruleType: 'Basic'
      priority: 200
      httpListener:       { id: resourceId('Microsoft.Network/applicationGateways/httpListeners',              appGwName, 'httpsListener') }
      backendAddressPool: { id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools',        appGwName, 'webBackendPool') }
      backendHttpSettings:{ id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, 'httpSettings') }
    }
  }
] : []

// ── App Gateway ───────────────────────────────────────────────────────────────────
resource appGateway 'Microsoft.Network/applicationGateways@2023-09-01' = {
  name: appGwName
  location: location
  tags: tags
  identity: empty(managedIdentityId) ? null : {
    type: 'UserAssigned'
    userAssignedIdentities: { '${managedIdentityId}': {} }
  }
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: capacity
    }
    firewallPolicy: { id: wafPolicy.id }
    sslCertificates: sslCertificates
    gatewayIPConfigurations: [
      {
        name: 'appGwIpConfig'
        properties: { subnet: { id: appGatewaySubnetId } }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwFrontendIp'
        properties: { publicIPAddress: { id: publicIp.id } }
      }
    ]
    frontendPorts: concat(
      [{ name: 'port-80', properties: { port: 80 } }],
      extraFrontendPorts
    )
    backendAddressPools: [
      { name: 'webBackendPool', properties: {} }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'httpSettings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 30
          probe: { id: resourceId('Microsoft.Network/applicationGateways/probes', appGwName, 'healthProbe') }
        }
      }
    ]
    probes: [
      {
        name: 'healthProbe'
        properties: {
          protocol: 'Http'
          host: '127.0.0.1'
          path: '/health'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: false
          minServers: 0
          match: { statusCodes: ['200-399'] }
        }
      }
    ]
    httpListeners: concat(
      [
        {
          name: 'httpListener'
          properties: {
            frontendIPConfiguration: { id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, 'appGwFrontendIp') }
            frontendPort:            { id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, 'port-80') }
            protocol: 'Http'
          }
        }
      ],
      httpsListeners
    )
    redirectConfigurations: httpRedirectConfigs
    requestRoutingRules: concat([httpRoutingRule], httpsRoutingRules)
  }
}

output appGatewayId string = appGateway.id
output appGatewayName string = appGateway.name
output publicIpAddress string = publicIp.properties.ipAddress
