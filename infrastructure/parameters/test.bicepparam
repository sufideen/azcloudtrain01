using '../main.bicep'

param environment          = 'test'
param location             = 'uksouth'
param namePrefix           = 'contoso'
param hubAddressPrefix     = '10.0.0.0/16'
param spokeAddressPrefix   = '10.2.0.0/16'
param alertEmail           = 'alerts@contoso.com'
param monthlyBudgetGbp     = 1200
// param keyVaultCertSecretUri = '' // run bootstrap-ssl.sh then uncomment with the output URI
param tags = {
  environment: 'test'
  project: 'hub-spoke'
  costCenter: 'engineering'
  managedBy: 'bicep'
}
