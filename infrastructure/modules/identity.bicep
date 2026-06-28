/*
  User-assigned managed identity
  Assigned to App Gateway so it can pull TLS certs from Key Vault without secrets
*/
param location string
param namePrefix string
param environment string
param tags object

resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${namePrefix}-appgw-${environment}'
  location: location
  tags: tags
}

output identityId string = managedIdentity.id
output principalId string = managedIdentity.properties.principalId
output clientId string = managedIdentity.properties.clientId
