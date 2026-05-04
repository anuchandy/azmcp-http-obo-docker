extension microsoftGraphV1

@description('Unique name of the existing Server App - must match the uniqueName used in server-app.bicep.')
param appUniqueName string

@description('Display name for the Server App.')
param displayName string

@description('Client App application (client) ID to preauthorize.')
param clientAppId string

@description('GUID of the Mcp.Tools.ReadWrite scope to preauthorize the client for.')
param mcpScopeId string

resource app 'Microsoft.Graph/applications@v1.0' = {
  uniqueName: appUniqueName
  displayName: displayName

  api: {
    oauth2PermissionScopes: [
      {
        adminConsentDescription: 'Allow the MCP server to read and write tools on behalf of the user'
        adminConsentDisplayName: 'Read and write MCP tools'
        id: mcpScopeId
        isEnabled: true
        type: 'User'
        userConsentDescription: 'Allow the MCP server to read and write tools on your behalf'
        userConsentDisplayName: 'Read and write MCP tools'
        value: 'Mcp.Tools.ReadWrite'
      }
    ]
    preAuthorizedApplications: [
      {
        appId: clientAppId
        delegatedPermissionIds: [
          mcpScopeId
        ]
      }
      {
        // Azure CLI - allows `az account get-access-token` to work
        appId: '04b07795-8ddb-461a-bbee-02f9e1bf7b46'
        delegatedPermissionIds: [
          mcpScopeId
        ]
      }
      {
        // Visual Studio Code - allows the built-in MS auth provider / MCP client to acquire tokens
        appId: 'aebc6443-996d-45c2-90f0-388ff96faa56'
        delegatedPermissionIds: [
          mcpScopeId
        ]
      }
    ]
  }
}
