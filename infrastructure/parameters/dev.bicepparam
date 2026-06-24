using '../main.bicep'

param environment          = 'dev'
param location             = 'eastus'
param namePrefix           = 'contoso'
param hubAddressPrefix     = '10.0.0.0/16'
param spokeAddressPrefix   = '10.1.0.0/16'
param tags = {
  environment: 'dev'
  project: 'hub-spoke'
  costCenter: 'engineering'
  managedBy: 'bicep'
}
