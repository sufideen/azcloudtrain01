using '../main.bicep'

param environment          = 'dev'
param location             = 'uksouth'
param namePrefix           = 'contoso'
param hubAddressPrefix     = '10.0.0.0/16'
param spokeAddressPrefix   = '10.1.0.0/16'
param alertEmail           = 'alerts@contoso.com'
param monthlyBudgetGbp     = 1200
// param keyVaultCertSecretUri = '' // run bootstrap-ssl.sh then uncomment with the output URI
param tags = {
  environment: 'dev'
  project: 'hub-spoke'
  costCenter: 'engineering'
  managedBy: 'bicep'
}
