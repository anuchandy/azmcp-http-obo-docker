#!/usr/bin/env pwsh
[CmdletBinding()]
param(
    [switch]$Detailed
)

$ErrorActionPreference = "Stop"

function Get-AzdEnvironment {
    $envValues = azd env get-values --output json | ConvertFrom-Json
    $hostPort = if ($envValues.hostPort) { $envValues.hostPort } else { 8080 }
    return [pscustomobject]@{
        ClientAppId = $envValues.clientAppId
        ServerAppId = $envValues.serverAppId
        HostPort    = $hostPort
        McpUrl      = "http://localhost:$hostPort"
    }
}

function Get-AccessToken {
    param([string]$ServerAppId)

    Write-Host "Getting access token..."
    $token = az account get-access-token --resource "api://$ServerAppId" --query accessToken -o tsv

    if ([string]::IsNullOrEmpty($token)) {
        Write-Host "Failed to get access token using az account get-access-token" -ForegroundColor Red
        exit 1
    }

    Write-Host "Got access token" -ForegroundColor Green
    return $token
}

function New-McpHeaders {
    param(
        [string]$Token,
        [string]$SessionId
    )

    $headers = @{
        "Content-Type"  = "application/json"
        "Accept"        = "application/json, text/event-stream"
        "Authorization" = "Bearer $Token"
    }

    if ($SessionId) {
        $headers["Mcp-Session-Id"] = $SessionId
    }

    return $headers
}

function Invoke-McpRequest {
    param(
        [string]$Url,
        [hashtable]$Headers,
        [hashtable]$Body
    )

    $jsonBody = $Body | ConvertTo-Json -Depth 10 -Compress
    return Invoke-WebRequest -Uri $Url -Method POST -Headers $Headers -Body $jsonBody -UseBasicParsing
}

function ConvertFrom-McpResponse {
    param([string]$Raw)

    if ($Raw -match '^event:') {
        $line = ($Raw -split "`n" | Where-Object { $_ -match '^data: ' } | Select-Object -First 1) -replace '^data: ', ''
        try { return $line | ConvertFrom-Json } catch { return $null }
    }

    try { return $Raw | ConvertFrom-Json } catch { return $null }
}

function Get-SessionId {
    param(
        [Microsoft.PowerShell.Commands.WebResponseObject]$Response,
        [psobject]$JsonBody
    )

    if ($Response.Headers.ContainsKey("Mcp-Session-Id")) {
        $value = ($Response.Headers["Mcp-Session-Id"] | Select-Object -First 1).Trim()
        if ($value) { return $value }
    }

    if ($JsonBody -and $JsonBody.result.sessionId) {
        return $JsonBody.result.sessionId
    }

    $generated = [guid]::NewGuid().ToString()
    Write-Host "No session ID in headers or JSON body, generated: $generated"
    return $generated
}

function Initialize-McpSession {
    param(
        [string]$Url,
        [string]$Token,
        [switch]$Detailed
    )

    Write-Host "Initializing MCP session..."

    $headers = New-McpHeaders -Token $Token
    $body = @{
        jsonrpc = "2.0"
        id      = 1
        method  = "initialize"
        params  = @{
            protocolVersion = "2024-11-05"
            capabilities    = @{}
            clientInfo      = @{
                name    = "test-client"
                version = "1.0"
            }
        }
    }

    $response = Invoke-McpRequest -Url $Url -Headers $headers -Body $body

    if ($Detailed) {
        Write-Host ""
        Write-Host "HTTP Status Code: $($response.StatusCode)"
        Write-Host "Response body:"
        Write-Host $response.Content
    }

    $json = ConvertFrom-McpResponse -Raw $response.Content
    if ($Detailed) {
        Write-Host ""
        Write-Host "Parsed JSON response:"
        if ($json) { $json | ConvertTo-Json -Depth 10 | Write-Host }
        else { Write-Host "Failed to parse response" -ForegroundColor Yellow }
    }

    $sessionId = Get-SessionId -Response $response -JsonBody $json
    Write-Host "Session ID: $sessionId"

    Write-Host ""
    Write-Host "MCP Server initialized successfully!" -ForegroundColor Green
    if ($json) {
        $serverName = if ($json.result.serverInfo.name) { $json.result.serverInfo.name } else { "Unknown" }
        $serverVersion = $json.result.serverInfo.version
        $protocol = if ($json.result.protocolVersion) { $json.result.protocolVersion } else { "Unknown" }
        Write-Host "Server: $serverName $serverVersion"
        Write-Host "Protocol: $protocol"
    }

    return $sessionId
}

function Get-McpTools {
    param(
        [string]$Url,
        [string]$Token,
        [string]$SessionId,
        [switch]$Detailed
    )

    Write-Host ""
    Write-Host "Listing MCP tools..."
    Write-Host "Using session ID: $SessionId"

    $headers = New-McpHeaders -Token $Token -SessionId $SessionId
    $body = @{
        jsonrpc = "2.0"
        id      = 2
        method  = "tools/list"
        params  = @{}
    }

    $response = Invoke-McpRequest -Url $Url -Headers $headers -Body $body
    $json = ConvertFrom-McpResponse -Raw $response.Content

    if ($Detailed) {
        Write-Host "Tools response:"
        if ($json) { $json | ConvertTo-Json -Depth 10 | Write-Host }
        else { Write-Host $response.Content }
    }

    return [pscustomobject]@{
        Json = $json
        Raw  = $response.Content
    }
}

function Show-Tools {
    param([pscustomobject]$Result)

    Write-Host ""
    Write-Host "📋 Available Azure MCP Tools:" -ForegroundColor Cyan

    $count = 0
    if ($Result.Json -and $Result.Json.result -and $Result.Json.result.tools) {
        $count = @($Result.Json.result.tools).Count
    }
    Write-Host "Total tools: $count"

    if ($count -gt 0) {
        $Result.Json.result.tools | Select-Object -First 10 | ForEach-Object {
            Write-Host "- $($_.name): $($_.description)"
        }
        if ($count -gt 10) {
            Write-Host "... and $($count - 10) more tools"
        }
    }
    else {
        Write-Host "No tools available. Check server logs:" -ForegroundColor Yellow
        Write-Host "Raw response: $($Result.Raw)"
    }
}

function Invoke-McpTool {
    param(
        [string]$Url,
        [string]$Token,
        [string]$SessionId,
        [string]$ToolName,
        [hashtable]$Arguments = @{},
        [int]$RequestId = 100,
        [switch]$Detailed
    )

    $headers = New-McpHeaders -Token $Token -SessionId $SessionId
    $body = @{
        jsonrpc = "2.0"
        id      = $RequestId
        method  = "tools/call"
        params  = @{
            name      = $ToolName
            arguments = $Arguments
        }
    }

    $response = Invoke-McpRequest -Url $Url -Headers $headers -Body $body
    $json = ConvertFrom-McpResponse -Raw $response.Content

    if ($Detailed) {
        Write-Host "Raw response from $ToolName :"
        if ($json) { $json | ConvertTo-Json -Depth 10 | Write-Host }
        else { Write-Host $response.Content }
    }

    return [pscustomobject]@{
        Json = $json
        Raw  = $response.Content
    }
}

function Get-McpToolPayload {
    param([pscustomobject]$Result)

    if (-not $Result.Json -or -not $Result.Json.result) { return $null }

    $content = $Result.Json.result.content
    if (-not $content) { return $null }

    $textItem = @($content) | Where-Object { $_.type -eq "text" } | Select-Object -First 1
    if (-not $textItem) { return $null }

    try { return $textItem.text | ConvertFrom-Json } catch { return $textItem.text }
}

function Get-DefaultSubscription {
    $sub = az account show --query id -o tsv 2>$null
    if ([string]::IsNullOrWhiteSpace($sub)) { return $null }
    return $sub.Trim()
}

function Get-NameList {
    param($Items)

    if (-not $Items) { return @() }
    return @($Items | ForEach-Object {
        if ($_ -is [string]) { $_ } else { $_.name }
    })
}

function Test-StorageTools {
    param(
        [string]$Url,
        [string]$Token,
        [string]$SessionId,
        [switch]$Detailed
    )

    Write-Host ""
    Write-Host "Calling storage tools..." -ForegroundColor Cyan

    $subscription = Get-DefaultSubscription
    if (-not $subscription) {
        Write-Host "'az account show' returned nothing. Skipping." -ForegroundColor Yellow
        return
    }
    Write-Host "Subscription: $subscription"

    Write-Host ""
    Write-Host "azmcp_storage_account_list"
    $accountsResult = Invoke-McpTool -Url $Url -Token $Token -SessionId $SessionId `
        -ToolName "azmcp_storage_account_list" `
        -Arguments @{ subscription = $subscription } `
        -RequestId 100 -Detailed:$Detailed

    $accountsPayload = Get-McpToolPayload -Result $accountsResult
    $accountNames = Get-NameList -Items $accountsPayload.accounts
    Write-Host "Found $($accountNames.Count) storage account(s)"
    $accountNames | Select-Object -First 10 | ForEach-Object { Write-Host "  - $_" }
}

# --- Main ---

Write-Host "Testing Azure MCP Server..." -ForegroundColor Cyan

$azdEnv = Get-AzdEnvironment
Write-Host "Client App ID: $($azdEnv.ClientAppId)"
Write-Host "Server App ID: $($azdEnv.ServerAppId)"
Write-Host "MCP URL: $($azdEnv.McpUrl)"

$token = Get-AccessToken -ServerAppId $azdEnv.ServerAppId
$sessionId = Initialize-McpSession -Url $azdEnv.McpUrl -Token $token -Detailed:$Detailed
$tools = Get-McpTools -Url $azdEnv.McpUrl -Token $token -SessionId $sessionId -Detailed:$Detailed
Show-Tools -Result $tools

Test-StorageTools -Url $azdEnv.McpUrl -Token $token -SessionId $sessionId -Detailed:$Detailed
