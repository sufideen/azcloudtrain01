using '../main.bicep'

param environment          = 'prod'
param location             = 'eastus'
param namePrefix           = 'contoso'
param hubAddressPrefix     = '10.0.0.0/16'
param spokeAddressPrefix   = '10.3.0.0/16'
param tags = {
  environment: 'prod'
  project: 'hub-spoke'
  costCenter: 'production'
  managedBy: 'bicep'
}
