extension microsoftGraphV1

@description('Unique name of the existing Server App - must match the uniqueName used in server-app.bicep.')
param appUniqueName string

@description('Application (client) ID returned from the server app creation.')
param appId string

resource app 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: appUniqueName
  displayName: appUniqueName
  identifierUris: [
    'api://${appId}'
  ]
}
