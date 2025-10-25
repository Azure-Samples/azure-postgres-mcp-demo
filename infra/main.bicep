@description('Location for all resources')
param location string = resourceGroup().location

@description('Name for the Azure Container App')
param acaName string

@description('Display name for the Entra App')
param entraAppDisplayName string

@description('Azure RBAC role definition ID for Container App (Reader role)')
param acaRoleId string = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'

@description('Full resource ID of the Postgres resource to assign the role on')
param postgresResourceId string

@description('AI Foundry project resource ID (optional - only needed if assigning Entra App role to AIF project MI)')
param aifProjectResourceId string

var entraAppUniqueName = '${replace(toLower(entraAppDisplayName), ' ', '-')}-${uniqueString(deployment().name, resourceGroup().id)}'

// Deploy Entra App
module entraApp 'modules/entra-app.bicep' = {
  name: 'entra-app-deployment'
  params: {
    entraAppDisplayName: entraAppDisplayName
    entraAppUniqueName: entraAppUniqueName
  }
}

// Deploy ACA Infrastructure
module acaInfrastructure 'modules/aca-infrastructure.bicep' = {
  name: 'aca-infrastructure-deployment'
  params: {
    name: acaName
    location: location
  }
}

// Deploy role assignment for ACA to access Postgres resource
module acaRoleAssignment './modules/aca-role-assignment-resource.bicep' = {
  name: 'aca-role-assignment'
  params: {
    postgresResourceId: postgresResourceId
    acaPrincipalId: acaInfrastructure.outputs.containerAppPrincipalId
    roleDefinitionId: acaRoleId
  }
}

// Deploy Entra App role assignment for AIF project MI to access ACA
module aifRoleAssignment './modules/aif-role-assignment-entraapp.bicep' = {
  name: 'aif-role-assignment'
  params: {
    aifProjectResourceId: aifProjectResourceId
    entraAppServicePrincipalObjectId: entraApp.outputs.entraAppServicePrincipalObjectId
    entraAppRoleId: entraApp.outputs.entraAppRoleId
  }
}

// Outputs for azd and other consumers
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId

// Entra App outputs
output ENTRA_APP_CLIENT_ID string = entraApp.outputs.entraAppClientId
output ENTRA_APP_OBJECT_ID string = entraApp.outputs.entraAppObjectId
output ENTRA_APP_SERVICE_PRINCIPAL_ID string = entraApp.outputs.entraAppServicePrincipalObjectId
output ENTRA_APP_ROLE_ID string = entraApp.outputs.entraAppRoleId
output ENTRA_APP_IDENTIFIER_URI string = entraApp.outputs.entraAppIdentifierUri

// ACA Infrastructure outputs
output RESOURCE_GROUP_NAME string = acaInfrastructure.outputs.resourceGroupName
output CONTAINER_REGISTRY_LOGIN_SERVER string = acaInfrastructure.outputs.containerRegistryLoginServer
output CONTAINER_REGISTRY_NAME string = acaInfrastructure.outputs.containerRegistryName
output CONTAINER_APP_NAME string = acaInfrastructure.outputs.containerAppName
output CONTAINER_APP_URL string = acaInfrastructure.outputs.containerAppUrl
output CONTAINER_APP_PRINCIPAL_ID string = acaInfrastructure.outputs.containerAppPrincipalId
output AZURE_CONTAINER_APP_ENVIRONMENT_ID string = acaInfrastructure.outputs.containerAppEnvironmentId
