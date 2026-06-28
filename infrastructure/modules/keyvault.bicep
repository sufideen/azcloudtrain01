/*
  Azure Key Vault — Standard SKU, RBAC-authorised
  Stores TLS certificates referenced by the App Gateway HTTPS listener.
  App Gateway's managed identity is granted Key Vault Secrets User role.
*/
param location string
param environment string
param namePrefix string
param tags object
param appGatewayPrincipalId string

// KV names: globally unique, max 24 chars
var kvName = take('kv-${namePrefix}-${environment}-${uniqueString(resourceGroup().id)}', 24)

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  tags: tags
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: tenant().tenantId
    enableSoftDelete: true
    softDeleteRetentionInDays: environment == 'prod' ? 90 : 7
    enableRbacAuthorization: true          // RBAC over legacy access policies
    enabledForTemplateDeployment: true
    publicNetworkAccess: 'Enabled'
  }
}

// Key Vault Secrets User — App Gateway reads the TLS cert as a versioned secret
resource appGwSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, appGatewayPrincipalId, '4633458b-17de-408a-b874-0445c86b69e0')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e0')
    principalId: appGatewayPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri string = keyVault.properties.vaultUri
