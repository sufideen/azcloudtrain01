@description('The Azure region where the Key Vault will be provisioned.')
param location string = resourceGroup().location

@description('The name of the Key Vault instance.')
param vaultName string = 'kv-alz-hub-core-${uniqueString(resourceGroup().id)}'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: vaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true // Enables modern Azure RBAC roles instead of legacy access policies
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    // Purge protection intentionally NOT enabled: the vault name is deterministic per RG and dev is
    // torn down nightly, so a purge-protected soft-deleted vault would block redeploy. See README security scope.
    publicNetworkAccess: 'Enabled' // Accepted risk in this showcase; RBAC-only auth. Prod should use Private Endpoint.
  }
}

output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri