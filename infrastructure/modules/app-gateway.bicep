/*
  Application Gateway v2 with WAF (OWASP 3.2)
  Phase 1: HTTP(80) only — routes to backend pool with WAF inspection.
  Phase 2: Add SSL cert from Key Vault and enable HTTPS(443) + HTTP→HTTPS redirect.


  WAF in Prevention mode for prod, Detection for dev/test.
*/
/*
  Phase 2: Add SSL cert from Key Vault and enable HTTPS(443) + HTTP->HTTPS redirect.
  WAF in Prevention mode for prod, Detection for dev/test.
*/

param location string
param environment string
param namePrefix string
param tags object
param appGatewaySubnetId string

// Phase 2: New incoming configuration parameters
param appGwIdentityId string
param kvCertificateSecretId string

var appGwName         = 'agw-${namePrefix}-${environment}'
var pipName           = 'pip-agw-${namePrefix}-${environment}'
var wafPolicyName     = 'waf-${namePrefix}-${environment}'
var wafMode           = environment == 'prod' ? 'Prevention' : 'Detection'

// 1. WAF Policy Container Deployment Configuration
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-09-01' = {
  name: wafPolicyName
  location: location
  tags: tags
  properties: {
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: wafMode
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
      ]
    }
  }
}

// 2. Main Application Gateway Resource Container
resource appGateway 'Microsoft.Network/applicationGateways@2023-09-01' = {
  name: appGwName
  location: location
  tags: tags
  
  // Phase 2 Identity: Grant Gateway permissions to authenticate to Key Vault via OIDC
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appGwIdentityId}': {}
    }
  }

  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 1
    }

    gatewayIPConfigurations: [
      {
        name: 'appGwIpConfig'
        properties: {
          subnet: {
            id: appGatewaySubnetId
          }
        }
      }
    ]

    // Phase 2 SSL: Map the Key Vault Certificate Secret URI into the SSL engine
    sslCertificates: [
      {
        name: 'appgw-ssl-cert'
        properties: {
          keyVaultSecretId: kvCertificateSecretId
        }
      }
    ]

    frontendIPConfigurations: [
      {
        name: 'appgw-public-ip'
        properties: {
          publicIPAddress: {
            id: resourceId('Microsoft.Network/publicIPAddresses', pipName)
          }
        }
      }
    ]

    // Phase 2 Ports: Secure communication line shifted to Port 443
    frontendPorts: [
      {
        name: 'port_443'
        properties: {
          port: 443
        }
      }
    ]

    backendAddressPools: [
      {
        name: 'webBackendPool'
        properties: {}
      }
    ]

    backendHttpSettingsCollection: [
      {
        name: 'webBackendSettings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true
          requestTimeout: 20
        }
      }
    ]

    // Phase 2 Listener: Upgraded listener mode configuration to encrypted HTTPS protocol
    httpListeners: [
      {
        name: 'https-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGwName, 'appgw-public-ip')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGwName, 'port_443')
          }
          protocol: 'Https'
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', appGwName, 'appgw-ssl-cert')
          }
          firewallPolicy: {
            id: wafPolicy.id
          }
        }
      }
    ]

    // Phase 2 Routing: Re-bind operational rule metrics onto the HTTPS stream listener
    requestRoutingRules: [
      {
        name: 'rule-default'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGwName, 'https-listener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGwName, 'webBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGwName, 'webBackendSettings')
          }
        }
      }
    ]
  }
}

output appGatewayId string   = appGateway.id
output appGatewayName string = appGateway.name