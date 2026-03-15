param(
    [Parameter(Mandatory = $false)]
    [string]$PipelineName,
    
    [Parameter(Mandatory = $false)]
    [string]$Description = "",
    
    [Parameter(Mandatory = $false)]
    [string]$Stages = "UAT,Production"
)

# Prompt for missing parameters
if (-not $PipelineName) {
    $PipelineName = Read-Host "Enter Deployment Pipeline Name"
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Creating Fabric Deployment Pipeline" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Pipeline Name : $PipelineName" -ForegroundColor Yellow
Write-Host "Description   : $Description" -ForegroundColor Yellow
Write-Host "Stages        : $Stages" -ForegroundColor Yellow
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

# Parse stages and create stage objects
$stageList = $Stages -split ","
$stageObjects = @()
$order = 0

foreach ($stage in $stageList) {
    $stageObjects += @{
        order = $order
        displayName = $stage.Trim()
    }
    $order++
}

# Create the pipeline request body
$body = @{
    displayName = $PipelineName
    description = $Description
    stages = $stageObjects
} | ConvertTo-Json -Depth 3

Write-Host "`nCreating deployment pipeline with $($stageObjects.Count) stages..." -ForegroundColor Green

try {
    $response = Invoke-WebRequest -Uri "https://api.fabric.microsoft.com/v1/deploymentPipelines" `
        -Method Post `
        -Headers $headers `
        -Body $body `
        -UseBasicParsing
    
    $pipeline = $response.Content | ConvertFrom-Json
    
    Write-Host "`n==========================================" -ForegroundColor Green
    Write-Host "SUCCESS: Deployment Pipeline Created" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Pipeline ID   : $($pipeline.id)" -ForegroundColor Cyan
    Write-Host "Pipeline Name : $($pipeline.displayName)" -ForegroundColor Cyan
    Write-Host "Description   : $($pipeline.description)" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Green
    
    # Output stages information
    Write-Host "`nStages Created:" -ForegroundColor Yellow
    foreach ($stage in $stageObjects) {
        Write-Host "  [$($stage.order)] $($stage.displayName)" -ForegroundColor Yellow
    }
    
    # Output JSON for programmatic use
    Write-Host "`n--- Pipeline Details (JSON) ---" -ForegroundColor Gray
    $pipeline | ConvertTo-Json -Depth 5
    
} catch {
    Write-Host "`n==========================================" -ForegroundColor Red
    Write-Host "ERROR: Failed to create deployment pipeline" -ForegroundColor Red
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
