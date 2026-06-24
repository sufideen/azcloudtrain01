/*
  Application Gateway v2 with WAF (OWASP 3.2)
  Phase 1: HTTP(80) only — routes to backend pool with WAF inspection.
  Phase 2: Add SSL cert from Key Vault and enable HTTPS(443) + HTTP→HTTPS redirect.
  WAF in Prevention mode for prod, Detection for dev/test.
*/
param location string
param environment string
param namePrefix string
param tags object
param appGatewaySubnetId string

var appGwName     = 'agw-${namePrefix}-${environment}'
var pipName       = 'pip-agw-${namePrefix}-${environment}'
var wafPolicyName = 'waf-${namePrefix}-${environment}'

var wafMode  = environment == 'prod' ? 'Prevention' : 'Detection'
var capacity = environment == 'prod' ? 2 : 1

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

resource appGateway 'Microsoft.Network/applicationGateways@2023-09-01' = {
  name: appGwName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: capacity
    }
    firewallPolicy: { id: wafPolicy.id }
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
    frontendPorts: [
      { name: 'port-80', properties: { port: 80 } }
    ]
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
    httpListeners: [
      {
        name: 'httpListener'
        properties: {
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, 'appGwFrontendIp') }
          frontendPort: { id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, 'port-80') }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'httpRoutingRule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: { id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, 'httpListener') }
          backendAddressPool: { id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, 'webBackendPool') }
          backendHttpSettings: { id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, 'httpSettings') }
        }
      }
    ]
  }
}

output appGatewayId string = appGateway.id
output appGatewayName string = appGateway.name
output publicIpAddress string = publicIp.properties.ipAddress
