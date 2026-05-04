# Azure MCP Server Docker

Azure MCP Server with OAuth2 On-Behalf-Of authentication running locally via Docker.

> [!NOTE]
> This setup is strictly for **local Docker runs**. For secure remote hosting, refer to the [these azd templates](https://github.com/microsoft/mcp/tree/main/servers/Azure.Mcp.Server/azd-templates).

## Prerequisites

```bash
# Login to Azure CLI and azd
az login --tenant <tenant-id>
azd auth login --tenant-id <tenant-id>
```

## Configuration

Edit `infra/main.bicepparam` to customize:
- MCP namespaces
- Host port 

## Usage

```shell
# Deploy and start
azd up
```

```bash
# On PowerShell:
# Grant admin consent for Azure service permissions
$SERVER_APP_ID = (azd env get-values |
    Select-String serverAppId).
    ToString().
    Split('=')[1].
    Trim('"')

az ad app permission admin-consent --id $SERVER_APP_ID
```

```bash
# Test client
pwsh ./client/azmcp-client.ps1
```

```shell
# Stop and cleanup
azd down
```


