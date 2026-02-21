param(
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceId,
    
    [Parameter(Mandatory=$true)]
    [string]$EndpointName,
    
    [Parameter(Mandatory=$true)]
    [string]$TargetResourceId,
    
    [Parameter(Mandatory=$true)]
    [string]$GroupId
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
    "Content-Type" = "application/json"
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

# Create the managed private endpoint
$apiUrl = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/managedPrivateEndpoints"

$body = @{
    name = $EndpointName
    targetPrivateLinkResourceId = $TargetResourceId
    targetSubresourceType = $GroupId
} | ConvertTo-Json -Depth 10

try {
    # Use -SkipHttpErrorCheck if available (PowerShell 7+), otherwise catch errors
    $webResponse = Invoke-WebRequest -Uri $apiUrl -Method POST -Headers $headers -Body $body -TimeoutSec 60 -UseBasicParsing -ErrorAction Stop
    $response = $webResponse.Content | ConvertFrom-Json
    
    @{
        success = $true
        message = "Managed Private Endpoint created successfully"
        workspaceId = $WorkspaceId
        workspaceName = $workspaceName
        endpoint = @{
            name = $response.name
            id = $response.id
            provisioningState = $response.provisioningState
            connectionState = $response.connectionState.status
            targetResourceId = $TargetResourceId
            groupId = $GroupId
        }
        nextSteps = @(
            "Go to the Azure resource in Azure Portal",
            "Navigate to: Networking > Private endpoint connections",
            "Find the pending connection from Fabric workspace",
            "Select the connection and click 'Approve'"
        )
    } | ConvertTo-Json -Depth 4
    
} catch [System.Net.WebException] {
    $statusCode = [int]$_.Exception.Response.StatusCode
    $errorBody = ""
    
    $responseStream = $_.Exception.Response.GetResponseStream()
    if ($responseStream) {
        $reader = New-Object System.IO.StreamReader($responseStream)
        $errorBody = $reader.ReadToEnd()
        $reader.Close()
    }
    
    $apiErrorObj = $null
    if ($errorBody) {
        try {
            $apiErrorObj = $errorBody | ConvertFrom-Json
        } catch {
            $apiErrorObj = @{ raw = $errorBody }
        }
    }
    
    @{
        error = "Failed to create endpoint"
        statusCode = $statusCode
        apiError = $apiErrorObj
        workspaceId = $WorkspaceId
        workspaceName = $workspaceName
        endpointName = $EndpointName
        targetResourceId = $TargetResourceId
        groupId = $GroupId
        hint = "Common groupIds: blob, dfs (storage), vault (keyvault), sqlServer, sites (webapp/function)"
    } | ConvertTo-Json -Depth 4
    exit 1
} catch {
    # PowerShell 7+ HttpRequestException or other errors
    $statusCode = 0
    $errorBody = ""
    
    if ($_.ErrorDetails.Message) {
        $errorBody = $_.ErrorDetails.Message
    }
    
    $apiErrorObj = $null
    if ($errorBody) {
        try {
            $apiErrorObj = $errorBody | ConvertFrom-Json
        } catch {
            $apiErrorObj = @{ raw = $errorBody }
        }
    }
    
    @{
        error = "Failed to create endpoint"
        statusCode = $statusCode
        apiError = $apiErrorObj
        exceptionMessage = $_.Exception.Message
        exceptionType = $_.Exception.GetType().FullName
        workspaceId = $WorkspaceId
        workspaceName = $workspaceName
        endpointName = $EndpointName
        targetResourceId = $TargetResourceId
        groupId = $GroupId
        hint = "Common groupIds: blob, dfs (storage), vault (keyvault), sqlServer, sites (webapp/function)"
    } | ConvertTo-Json -Depth 4
    exit 1
}
