using '../main.bicep'

param environment          = 'prod'
param location             = 'uksouth'
param namePrefix           = 'contoso'
param hubAddressPrefix     = '10.0.0.0/16'
param spokeAddressPrefix   = '10.3.0.0/16'
param alertEmail           = 'alerts@contoso.com'
param monthlyBudgetGbp     = 1500
// param keyVaultCertSecretUri = '' // run bootstrap-ssl.sh then uncomment with the output URI
param tags = {
  environment: 'prod'
  project: 'hub-spoke'
  costCenter: 'production'
  managedBy: 'bicep'
}
