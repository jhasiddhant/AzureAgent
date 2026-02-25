param(
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceIdentifier,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("Admin", "Contributor", "Member", "Viewer")]
    [string]$RoleName,
    
    [Parameter(Mandatory = $true)]
    [string]$PrincipalId,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("User", "Group", "ServicePrincipal", "ServicePrincipalProfile")]
    [string]$PrincipalType
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Assigning Fabric Workspace Role" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Workspace    : $WorkspaceIdentifier" -ForegroundColor Yellow
Write-Host "Role         : $RoleName" -ForegroundColor Yellow
Write-Host "Principal ID : $PrincipalId" -ForegroundColor Yellow
Write-Host "Principal Type: $PrincipalType" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

# Get Azure AD token for Fabric API
Write-Host "Getting Azure AD token..." -ForegroundColor Green
$token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv

if (-not $token) {
    Write-Error "Failed to get Azure AD token. Please run 'az login' first."
    exit 1
}

# Prepare headers
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

# Resolve workspace ID - check if it's a GUID or a name
$workspaceId = $null

# Check if WorkspaceIdentifier is a valid GUID
$isGuid = $false
try {
    [System.Guid]::Parse($WorkspaceIdentifier) | Out-Null
    $isGuid = $true
    $workspaceId = $WorkspaceIdentifier
    Write-Host "Using workspace ID: $workspaceId" -ForegroundColor Green
}
catch {
    $isGuid = $false
}

# If not a GUID, treat as workspace name and resolve it
if (-not $isGuid) {
    Write-Host "Resolving workspace name to ID..." -ForegroundColor Yellow
    
    try {
        $workspacesResponse = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces" `
            -Method Get `
            -Headers $headers
        
        $matchedWorkspace = $workspacesResponse.value | Where-Object { 
            $_.displayName -eq $WorkspaceIdentifier 
        }
        
        if (-not $matchedWorkspace) {
            # Try case-insensitive partial match
            $matchedWorkspace = $workspacesResponse.value | Where-Object { 
                $_.displayName -like "*$WorkspaceIdentifier*" 
            } | Select-Object -First 1
        }
        
        if (-not $matchedWorkspace) {
            Write-Error "Workspace '$WorkspaceIdentifier' not found. Please verify the workspace name or use the workspace ID."
            exit 1
        }
        
        $workspaceId = $matchedWorkspace.id
        Write-Host "Resolved workspace '$($matchedWorkspace.displayName)' to ID: $workspaceId" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to resolve workspace name: $_"
        exit 1
    }
}

# Prepare the role assignment request body
$body = @{
    principal = @{
        id   = $PrincipalId
        type = $PrincipalType
    }
    role      = $RoleName
} | ConvertTo-Json -Depth 5

Write-Host "`nAssigning role..." -ForegroundColor Green

# Call Fabric API to assign role
try {
    $response = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/roleAssignments" `
        -Method Post `
        -Headers $headers `
        -Body $body
    
    Write-Host "`n==========================================`n" -ForegroundColor Green
    Write-Host "ROLE ASSIGNMENT SUCCESSFUL" -ForegroundColor Green
    Write-Host "==========================================`n" -ForegroundColor Green
    
    # Output result details
    $result = [PSCustomObject]@{
        Status        = "Success"
        WorkspaceId   = $workspaceId
        Role          = $RoleName
        PrincipalId   = $PrincipalId
        PrincipalType = $PrincipalType
        AssignmentId  = $response.id
    }
    
    $result | Format-List
    
    # Also output as JSON for programmatic use
    Write-Host "`nJSON Output:" -ForegroundColor Cyan
    $result | ConvertTo-Json
}
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $errorMessage = $_.ErrorDetails.Message
    
    # Try to parse error details
    $errorDetails = $null
    if ($errorMessage) {
        try {
            $errorDetails = $errorMessage | ConvertFrom-Json
        }
        catch {
            $errorDetails = @{ message = $errorMessage }
        }
    }
    
    Write-Host "`n==========================================`n" -ForegroundColor Red
    Write-Host "ROLE ASSIGNMENT FAILED" -ForegroundColor Red
    Write-Host "==========================================`n" -ForegroundColor Red
    
    Write-Host "Status Code: $statusCode" -ForegroundColor Red
    
    if ($errorDetails.errorCode) {
        Write-Host "Error Code: $($errorDetails.errorCode)" -ForegroundColor Red
    }
    
    if ($errorDetails.message) {
        Write-Host "Error Message: $($errorDetails.message)" -ForegroundColor Red
    }
    elseif ($errorDetails.error.message) {
        Write-Host "Error Message: $($errorDetails.error.message)" -ForegroundColor Red
    }
    else {
        Write-Host "Error: $_" -ForegroundColor Red
    }
    
    Write-Host "`nCommon causes:" -ForegroundColor Yellow
    Write-Host "  - Principal ID (Object ID) is incorrect" -ForegroundColor Yellow
    Write-Host "  - You don't have Admin access to the workspace" -ForegroundColor Yellow
    Write-Host "  - Role assignment already exists (use update instead)" -ForegroundColor Yellow
    Write-Host "  - Invalid principal type for the given ID" -ForegroundColor Yellow
    Write-Host "  - Workspace ID is incorrect" -ForegroundColor Yellow
    
    exit 1
}
