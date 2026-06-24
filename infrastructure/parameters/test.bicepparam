using '../main.bicep'

param environment          = 'test'
param location             = 'eastus'
param namePrefix           = 'contoso'
param hubAddressPrefix     = '10.0.0.0/16'
param spokeAddressPrefix   = '10.2.0.0/16'
param tags = {
  environment: 'test'
  project: 'hub-spoke'
  costCenter: 'engineering'
  managedBy: 'bicep'
}
