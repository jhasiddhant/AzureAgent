param(
    [Parameter(Mandatory = $true)]
    [string]$PipelineId,
    
    [Parameter(Mandatory = $true)]
    [string]$PrincipalId,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("User", "Group", "ServicePrincipal", "ServicePrincipalProfile")]
    [string]$PrincipalType = "User",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Admin")]
    [string]$Role = "Admin"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Adding Role Assignment to Deployment Pipeline" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Pipeline ID    : $PipelineId" -ForegroundColor Yellow
Write-Host "Principal ID   : $PrincipalId" -ForegroundColor Yellow
Write-Host "Principal Type : $PrincipalType" -ForegroundColor Yellow
Write-Host "Role           : $Role" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

# Get access token for Power BI/Fabric API
Write-Host "Getting access token..." -ForegroundColor Green
$tokenResponse = az account get-access-token --resource https://analysis.windows.net/powerbi/api | ConvertFrom-Json

if (-not $tokenResponse -or -not $tokenResponse.accessToken) {
    Write-Error "Failed to get access token. Please run 'az login' first."
    exit 1
}

$ACCESS_TOKEN = $tokenResponse.accessToken

# Setup headers for API calls
$headers = @{
    "Authorization" = "Bearer $ACCESS_TOKEN"
    "Content-Type" = "application/json"
}

# Create the request body
$body = @{
    principal = @{
        id = $PrincipalId
        type = $PrincipalType
    }
    role = $Role
} | ConvertTo-Json -Depth 3

Write-Host "`nAdding role assignment..." -ForegroundColor Green

try {
    $uri = "https://api.fabric.microsoft.com/v1/deploymentPipelines/$PipelineId/roleAssignments"
    
    $response = Invoke-RestMethod `
        -Uri $uri `
        -Method Post `
        -Headers $headers `
        -Body $body
    
    Write-Host "`n==========================================" -ForegroundColor Green
    Write-Host "SUCCESS: Role Assignment Added" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Pipeline ID    : $PipelineId" -ForegroundColor Cyan
    Write-Host "Principal ID   : $PrincipalId" -ForegroundColor Cyan
    Write-Host "Principal Type : $PrincipalType" -ForegroundColor Cyan
    Write-Host "Role           : $Role" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Green
    
    # Output result as JSON
    $result = @{
        success = $true
        pipelineId = $PipelineId
        principalId = $PrincipalId
        principalType = $PrincipalType
        role = $Role
        message = "Role assignment successfully added to deployment pipeline"
    }
    
    Write-Host "`n--- Result (JSON) ---" -ForegroundColor Gray
    $result | ConvertTo-Json
    
} catch {
    Write-Host "`n==========================================" -ForegroundColor Red
    Write-Host "ERROR: Failed to add role assignment" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Response) {
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Host "Response: $responseBody" -ForegroundColor Red
        } catch {
            # Ignore read errors
        }
    }
    
    Write-Host "`nCommon causes:" -ForegroundColor Yellow
    Write-Host "  - Principal ID must be the Entra ID Object ID (GUID), not the email" -ForegroundColor Yellow
    Write-Host "  - Use 'az ad user show --id <email>' to get the Object ID" -ForegroundColor Yellow
    Write-Host "  - Role assignment may already exist" -ForegroundColor Yellow
    Write-Host "  - Invalid pipeline ID or principal ID" -ForegroundColor Yellow
    Write-Host "  - Insufficient permissions on the pipeline" -ForegroundColor Yellow
    
    exit 1
}
