param(
    [Parameter(Mandatory = $true)]
    [string]$PipelineId
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Getting Deployment Pipeline Stages" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Pipeline ID : $PipelineId" -ForegroundColor Yellow
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

Write-Host "`nRetrieving stages..." -ForegroundColor Green

try {
    $response = Invoke-RestMethod `
        -Uri "https://api.fabric.microsoft.com/v1/deploymentPipelines/$PipelineId/stages" `
        -Method Get `
        -Headers $headers
    
    Write-Host "`n==========================================" -ForegroundColor Green
    Write-Host "SUCCESS: Pipeline Stages Retrieved" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    
    if ($response.value -and $response.value.Count -gt 0) {
        Write-Host "`nStages:" -ForegroundColor Yellow
        Write-Host "==========================================`n" -ForegroundColor Yellow
        
        foreach ($stage in $response.value) {
            Write-Host "Stage Order  : $($stage.order)" -ForegroundColor Cyan
            Write-Host "Stage ID     : $($stage.id)" -ForegroundColor Cyan
            Write-Host "Display Name : $($stage.displayName)" -ForegroundColor Cyan
            
            if ($stage.workspaceId) {
                Write-Host "Workspace ID : $($stage.workspaceId)" -ForegroundColor Green
                Write-Host "Workspace    : $($stage.workspaceName)" -ForegroundColor Green
            } else {
                Write-Host "Workspace    : (Not Assigned)" -ForegroundColor Gray
            }
            
            Write-Host "------------------------------------------" -ForegroundColor Gray
        }
    } else {
        Write-Host "No stages found for this pipeline." -ForegroundColor Yellow
    }
    
    # Output JSON for programmatic use
    Write-Host "`n--- Stages Details (JSON) ---" -ForegroundColor Gray
    $response | ConvertTo-Json -Depth 5
    
} catch {
    Write-Host "`n==========================================" -ForegroundColor Red
    Write-Host "ERROR: Failed to retrieve pipeline stages" -ForegroundColor Red
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
    exit 1
}
