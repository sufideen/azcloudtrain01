/*
  Storage account for:
  - Bicep artifact storage (CI/CD staging)
  - App data blobs
  Prod: GRS replication; dev/test: LRS
*/
param location string
param environment string
param namePrefix string
param tags object

// Storage account names must be globally unique, 3-24 chars, lowercase alphanumeric
var accountName = toLower(take('${replace(namePrefix, '-', '')}${environment}${uniqueString(resourceGroup().id)}', 24))

var replication = environment == 'prod' ? 'Standard_GRS' : 'Standard_LRS'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: accountName
  location: location
  tags: tags
  sku: { name: replication }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource bicepContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/bicep-artifacts'
  properties: { publicAccess: 'None' }
}

resource appDataContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/app-data'
  properties: { publicAccess: 'None' }
}

output accountName string = storageAccount.name
output accountId string = storageAccount.id
output primaryEndpoint string = storageAccount.properties.primaryEndpoints.blob
