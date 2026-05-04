targetScope = 'resourceGroup'

@description('Base name for the app registrations. Server app: {appName}-server, Client app: {appName}-client.')
param appName string

@description('MCP tool namespaces to expose — drives the requiredResourceAccess on the server app.')
param namespaces string[]

@description('Public client redirect URIs for interactive login flows (VS Code, CLI, browser). http://localhost covers all localhost ports; the explicit 127.0.0.1 + vscode.dev entries are required by VS Code MCP auth.')
param publicClientRedirectUris array = [
  'http://localhost'
  'http://127.0.0.1:33418'
  'https://vscode.dev/redirect'
]

@description('Host port for the local MCP server container.')
param hostPort int = 8080

var scopeMap = loadJsonContent('azmcp_namespaces_required_resource_access.json')

var filteredAccess = filter(
  scopeMap,
  entry => !empty(intersection(entry.namespaces, namespaces)) && !empty(entry.resourceAccess)
)

var requiredResourceAccess = map(filteredAccess, entry => {
  resourceAppId: entry.resourceAppId
  resourceAccess: entry.resourceAccess
})

var entraAppUniqueId = uniqueString(resourceGroup().id)
var serverDisplayName = '${appName} Server'
var serverUniqueName = '${replace(toLower(serverDisplayName), ' ', '-')}-${entraAppUniqueId}'

var clientDisplayName = '${appName} Client'  
var clientUniqueName = '${replace(toLower(clientDisplayName), ' ', '-')}-${entraAppUniqueId}'

module serverApp 'modules/server-app.bicep' = {
  name: 'create-server-app'
  params: {
    displayName: serverDisplayName
    uniqueName: serverUniqueName
    requiredResourceAccess: requiredResourceAccess
  }
}

module serverAppSetUri 'modules/server-app-set-identifier-uri.bicep' = {
  name: 'set-server-app-identifier-uri'
  params: {
    appUniqueName: serverUniqueName
    appId: serverApp.outputs.appId
  }
}

module clientApp 'modules/client-app.bicep' = {
  name: 'create-client-app'
  params: {
    displayName: clientDisplayName
    uniqueName: clientUniqueName
    serverAppId: serverApp.outputs.appId
    serverAppScopeId: serverApp.outputs.mcpScopeId
    publicClientRedirectUris: publicClientRedirectUris
  }
}

module serverAppAddPreauth 'modules/server-app-add-preauth.bicep' = {
  name: 'server-app-add-preauth'
  dependsOn: [
    serverAppSetUri
  ]
  params: {
    appUniqueName: serverUniqueName
    displayName: serverDisplayName
    clientAppId: clientApp.outputs.appId
    mcpScopeId: serverApp.outputs.mcpScopeId
  }
}

@description('Server App application (client) ID.')
output serverAppId string = serverApp.outputs.appId

@description('Server App object ID.')
output serverAppObjectId string = serverApp.outputs.appObjectId

@description('Client App application (client) ID.')
output clientAppId string = clientApp.outputs.appId

@description('The Azure AD tenant ID.')
output tenantId string = tenant().tenantId

@description('The configured MCP namespaces.')
output mcpNamespaces string = join(namespaces, ' ')

@description('The configured host port for the MCP server.')
output hostPort int = hostPort

@description('Client App object ID.')
output clientAppObjectId string = clientApp.outputs.appObjectId

@description('The Mcp.Tools.ReadWrite scope URI for token requests.')
output mcpScope string = 'api://${serverApp.outputs.appId}/Mcp.Tools.ReadWrite'
