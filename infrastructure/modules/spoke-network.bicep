/*
  Spoke VNet per environment: web, app, data, admin subnets
*/
param location string
param environment string
param namePrefix string
param spokeAddressPrefix string
param tags object

// NSG resource IDs injected from nsg module
param nsgWebId string
param nsgAppId string
param nsgDataId string
param nsgAdminId string

var spokeName = 'vnet-${namePrefix}-spoke-${environment}'

// Carve 4 /24s from the spoke /16
var webSubnet   = cidrSubnet(spokeAddressPrefix, 24, 1)  // .1.0/24
var appSubnet   = cidrSubnet(spokeAddressPrefix, 24, 2)  // .2.0/24
var dataSubnet  = cidrSubnet(spokeAddressPrefix, 24, 3)  // .3.0/24
var adminSubnet = cidrSubnet(spokeAddressPrefix, 24, 4)  // .4.0/24

resource spokeVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: spokeName
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [spokeAddressPrefix] }
    subnets: [
      {
        name: 'WebSubnet'
        properties: {
          addressPrefix: webSubnet
          networkSecurityGroup: { id: nsgWebId }
        }
      }
      {
        name: 'AppSubnet'
        properties: {
          addressPrefix: appSubnet
          networkSecurityGroup: { id: nsgAppId }
        }
      }
      {
        name: 'DataSubnet'
        properties: {
          addressPrefix: dataSubnet
          networkSecurityGroup: { id: nsgDataId }
        }
      }
      {
        name: 'AdminSubnet'
        properties: {
          addressPrefix: adminSubnet
          networkSecurityGroup: { id: nsgAdminId }
        }
      }
    ]
  }
}

output vnetId string = spokeVnet.id
output vnetName string = spokeVnet.name
output webSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', spokeName, 'WebSubnet')
output appSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', spokeName, 'AppSubnet')
output dataSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', spokeName, 'DataSubnet')
output adminSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', spokeName, 'AdminSubnet')
