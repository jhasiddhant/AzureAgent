param(
    [Parameter(Mandatory = $true)]
    [string]$PipelineId,
    
    [Parameter(Mandatory = $true)]
    [string]$StageId,
    
    [Parameter(Mandatory = $true)]
    [string]$WorkspaceId
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Assigning Workspace to Pipeline Stage" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Pipeline ID  : $PipelineId" -ForegroundColor Yellow
Write-Host "Stage ID     : $StageId" -ForegroundColor Yellow
Write-Host "Workspace ID : $WorkspaceId" -ForegroundColor Yellow
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
    workspaceId = $WorkspaceId
} | ConvertTo-Json

Write-Host "`nAssigning workspace to stage..." -ForegroundColor Green

try {
    $uri = "https://api.fabric.microsoft.com/v1/deploymentPipelines/$PipelineId/stages/$StageId/assignWorkspace"
    
    Invoke-RestMethod `
        -Uri $uri `
        -Method Post `
        -Headers $headers `
        -Body $body | Out-Null
    
    Write-Host "`n==========================================" -ForegroundColor Green
    Write-Host "SUCCESS: Workspace Assigned to Stage" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Pipeline ID  : $PipelineId" -ForegroundColor Cyan
    Write-Host "Stage ID     : $StageId" -ForegroundColor Cyan
    Write-Host "Workspace ID : $WorkspaceId" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Green
    
    # Output result as JSON
    $result = @{
        success = $true
        pipelineId = $PipelineId
        stageId = $StageId
        workspaceId = $WorkspaceId
        message = "Workspace successfully assigned to pipeline stage"
    }
    
    Write-Host "`n--- Result (JSON) ---" -ForegroundColor Gray
    $result | ConvertTo-Json
    
} catch {
    Write-Host "`n==========================================" -ForegroundColor Red
    Write-Host "ERROR: Failed to assign workspace to stage" -ForegroundColor Red
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
    Write-Host "  - Stage already has a workspace assigned" -ForegroundColor Yellow
    Write-Host "  - Workspace is already assigned to another stage in this pipeline" -ForegroundColor Yellow
    Write-Host "  - Invalid pipeline ID, stage ID, or workspace ID" -ForegroundColor Yellow
    Write-Host "  - Insufficient permissions on the workspace or pipeline" -ForegroundColor Yellow
    
    exit 1
}
