# Azure MCP Server Docker

Azure MCP Server with OAuth2 On-Behalf-Of authentication running locally via Docker.

## Prerequisites

```bash
# Login to Azure CLI and azd (same tenant)
az login --tenant <tenant-id>
azd auth login --tenant-id <tenant-id>
```

## Configuration

Edit `infra/main.bicepparam` to customize:
- Host port 
- MCP namespaces

## Usage

```shell
# Deploy and start
azd up
```

```bash
# On bash/macOS/Linux:
# Grant admin consent for Azure service permissions
SERVER_APP_ID=$(azd env get-values | grep serverAppId | cut -d'=' -f2 | tr -d '"')
az ad app permission admin-consent --id $SERVER_APP_ID
```

```bash
# On PowerShell/Windows:
# Grant admin consent for Azure service permissions
$SERVER_APP_ID = (azd env get-values | Select-String serverAppId).ToString().Split('=')[1].Trim('"')
az ad app permission admin-consent --id $SERVER_APP_ID
```


```shell
# Stop and cleanup
azd down
```

## Test client

```pwsh
pwsh ./azmcp-client.ps1

# Run with full HTTP/JSON dumps
pwsh ./azmcp-client.ps1 -Detailed
```


