/*
  Application Gateway v2 with WAF (OWASP 3.2)
  HTTP(80) listener redirects permanently to HTTPS(443) listener.
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
        { ruleSetType: 'OWASP',                    ruleSetVersion: '3.2' }
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
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: wafMode
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
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
      { name: 'port-80',  properties: { port: 80  } }
      { name: 'port-443', properties: { port: 443 } }
    ]
    backendAddressPools: [
      { name: 'webBackendPool', properties: {} }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'httpsSettings'
        properties: {
          port: 443
          protocol: 'Https'
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
          protocol: 'Https'
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
        // Port 80 listener — redirects to HTTPS
        name: 'httpListener'
        properties: {
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, 'appGwFrontendIp') }
          frontendPort: { id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, 'port-80') }
          protocol: 'Http'
        }
      }
      {
        // Port 443 listener — the redirect TARGET
        name: 'httpsListener'
        properties: {
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, 'appGwFrontendIp') }
          frontendPort: { id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, 'port-443') }
          protocol: 'Https'
          // sslCertificate must be provided before prod; omitted here for initial infra deploy
        }
      }
    ]
    redirectConfigurations: [
      {
        name: 'httpToHttps'
        properties: {
          redirectType: 'Permanent'
          // Target is the HTTPS listener, NOT the HTTP listener
          targetListener: { id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, 'httpsListener') }
          includePath: true
          includeQueryString: true
        }
      }
    ]
    requestRoutingRules: [
      {
        // HTTP traffic → redirect to HTTPS
        name: 'httpRedirectRule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: { id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, 'httpListener') }
          redirectConfiguration: { id: resourceId('Microsoft.Network/applicationGateways/redirectConfigurations', appGwName, 'httpToHttps') }
        }
      }
      {
        // HTTPS traffic → backend pool
        name: 'httpsRoutingRule'
        properties: {
          ruleType: 'Basic'
          priority: 200
          httpListener: { id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, 'httpsListener') }
          backendAddressPool: { id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, 'webBackendPool') }
          backendHttpSettings: { id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, 'httpsSettings') }
        }
      }
    ]
  }
}

output appGatewayId string = appGateway.id
output appGatewayName string = appGateway.name
output publicIpAddress string = publicIp.properties.ipAddress
