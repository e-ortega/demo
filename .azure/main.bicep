// .azure/main.bicep (updated)
param location string = resourceGroup().location
param acrName string
param webAppName string
param skuName string = 'B1' // App Service Plan SKU
param appInsightsName string = '${webAppName}-ai'

// Optional: image tag to set on deployment. Leave empty to skip setting container.
param imageTag string = ''

// -- ACR
resource acr 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {}
}

// -- App Service Plan (Linux)
resource plan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: '${webAppName}-plan'
  location: location
  sku: {
    name: skuName
    tier: startsWith(skuName, 'P') ? 'PremiumV2' : (startsWith(skuName, 'B') ? 'Basic' : 'Standard')
    capacity: 1
  }
  kind: 'linux'
  properties: {}
}

// -- Web App for Containers (system-assigned identity)
// NOTE: We DO NOT set linuxFxVersion here to avoid validation errors when image is missing.
resource webApp 'Microsoft.Web/sites@2022-03-01' = {
  name: webAppName
  location: location
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    siteConfig: {
      // Leave linuxFxVersion out here on purpose.
      appSettings: [
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
        {
          name: 'DOCKER_REGISTRY_SERVER_URL'
          value: 'https://${acr.properties.loginServer}'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '0'
        }
      ]
    }
  }
  dependsOn: [
    acr
    plan
  ]
}

// -- Application Insights (optional)
resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (appInsightsName != '') {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

// -- Role assignment: give Web App MSI AcrPull on the registry
var acrPullRoleGuid = guid(acr.id, webApp.name, 'acrpull')

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: acrPullRoleGuid
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    )
    principalId: webApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    webApp
  ]
}

// -- Optional: set the container image only when an imageTag is provided
// This avoids validation failures when the image is not yet in ACR.
resource webAppConfig 'Microsoft.Web/sites/config@2022-03-01' = if (imageTag != '') {
  name: '${webApp.name}/web'
  properties: {
    linuxFxVersion: 'DOCKER|${acr.properties.loginServer}/${webAppName}:${imageTag}'
    appSettings: [
      {
        name: 'DOCKER_REGISTRY_SERVER_URL'
        value: 'https://${acr.properties.loginServer}'
      }
    ]
  }
  dependsOn: [
    acrPullRole
  ]
}

// Outputs
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output acrLoginServer string = acr.properties.loginServer
output webAppPrincipalId string = webApp.identity.principalId
