param(
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceId
)

$ErrorActionPreference = "Stop"

# Get Fabric access token
try {
    $tokenResult = az account get-access-token --resource "https://api.fabric.microsoft.com" --query "accessToken" -o tsv 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        @{ error = "Failed to get Fabric access token. Run 'az login' to authenticate." } | ConvertTo-Json
        exit 1
    }
    
    $token = $tokenResult.Trim()
} catch {
    @{ error = "Failed to get access token: $_" } | ConvertTo-Json
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $token"
}

# Check if WorkspaceId is a GUID or a name - if not a GUID, look it up
$guidPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
$workspaceName = $null

if ($WorkspaceId -notmatch $guidPattern) {
    $workspaceName = $WorkspaceId
    
    try {
        $workspacesUrl = "https://api.fabric.microsoft.com/v1/workspaces"
        $workspacesResponse = Invoke-RestMethod -Uri $workspacesUrl -Method GET -Headers $headers -TimeoutSec 30
        
        $workspace = $workspacesResponse.value | Where-Object { $_.displayName -eq $WorkspaceId -or $_.displayName -like "*$WorkspaceId*" } | Select-Object -First 1
        
        if (-not $workspace) {
            @{ error = "Workspace not found: $WorkspaceId" } | ConvertTo-Json
            exit 0
        }
        
        $WorkspaceId = $workspace.id
        $workspaceName = $workspace.displayName
    } catch {
        @{ error = "Failed to lookup workspace: $($_.Exception.Message)" } | ConvertTo-Json
        exit 0
    }
}

# List managed private endpoints
try {
    $apiUrl = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/managedPrivateEndpoints"
    
    $response = Invoke-RestMethod -Uri $apiUrl -Method GET -Headers $headers -TimeoutSec 30
    
    $endpoints = $response.value
    
    if ($null -eq $endpoints -or $endpoints.Count -eq 0) {
        @{
            workspaceId = $WorkspaceId
            count = 0
            endpoints = @()
            message = "No managed private endpoints found"
        } | ConvertTo-Json -Depth 3
        exit 0
    }
    
    $formattedEndpoints = @()
    foreach ($ep in $endpoints) {
        $formattedEndpoints += @{
            name = $ep.name
            id = $ep.id
            targetResourceId = $ep.targetPrivateLinkResourceId
            groupId = $ep.targetSubresourceType
            provisioningState = $ep.provisioningState
            connectionStatus = $ep.connectionState.status
            connectionDescription = $ep.connectionState.description
        }
    }
    
    @{
        workspaceId = $WorkspaceId
        workspaceName = $workspaceName
        count = $endpoints.Count
        endpoints = $formattedEndpoints
    } | ConvertTo-Json -Depth 4
    
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $errorMessage = $_.Exception.Message
    
    @{
        error = "Failed to list endpoints"
        statusCode = $statusCode
        message = $errorMessage
        workspaceId = $WorkspaceId
    } | ConvertTo-Json
    exit 1
}
