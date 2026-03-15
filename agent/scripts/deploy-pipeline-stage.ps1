param(
    [Parameter(Mandatory = $true)]
    [string]$PipelineId,
    
    [Parameter(Mandatory = $true)]
    [int]$SourceStageOrder,
    
    [Parameter(Mandatory = $false)]
    [string]$Note = "",
    
    [Parameter(Mandatory = $false)]
    [switch]$AllowOverwrite = $false,
    
    [Parameter(Mandatory = $false)]
    [switch]$AllowCreate = $true
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deploying Fabric Pipeline Stage" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Pipeline ID       : $PipelineId" -ForegroundColor Yellow
Write-Host "Source Stage Order: $SourceStageOrder (deploying TO next stage)" -ForegroundColor Yellow
Write-Host "Deployment Note   : $Note" -ForegroundColor Yellow
Write-Host "Allow Overwrite   : $AllowOverwrite" -ForegroundColor Yellow
Write-Host "Allow Create New  : $AllowCreate" -ForegroundColor Yellow
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

# First, get pipeline stages to display info
Write-Host "`nRetrieving pipeline stages..." -ForegroundColor Green

try {
    $stagesResponse = Invoke-RestMethod `
        -Uri "https://api.fabric.microsoft.com/v1/deploymentPipelines/$PipelineId/stages" `
        -Method Get `
        -Headers $headers
    
    $sourceStage = $stagesResponse.value | Where-Object { $_.order -eq $SourceStageOrder }
    $targetStage = $stagesResponse.value | Where-Object { $_.order -eq ($SourceStageOrder + 1) }
    
    if (-not $sourceStage) {
        Write-Error "Source stage with order $SourceStageOrder not found"
        exit 1
    }
    
    if (-not $targetStage) {
        Write-Error "Target stage (order $($SourceStageOrder + 1)) not found. Cannot deploy from the last stage."
        exit 1
    }
    
    Write-Host "`nDeployment Path:" -ForegroundColor Cyan
    Write-Host "  FROM: [$($sourceStage.order)] $($sourceStage.displayName)" -ForegroundColor Yellow
    if ($sourceStage.workspaceName) {
        Write-Host "        Workspace: $($sourceStage.workspaceName)" -ForegroundColor Gray
    }
    Write-Host "  TO:   [$($targetStage.order)] $($targetStage.displayName)" -ForegroundColor Green
    if ($targetStage.workspaceName) {
        Write-Host "        Workspace: $($targetStage.workspaceName)" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "Warning: Could not retrieve stage details: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Create the deploy request body
$body = @{
    sourceStageOrder = $SourceStageOrder
    isBackwardDeployment = $false
    newWorkspace = $null
    options = @{
        allowOverwriteArtifact = $AllowOverwrite.IsPresent
        allowCreateArtifact = $AllowCreate.IsPresent
        allowOverwriteTargetArtifactLabel = $AllowOverwrite.IsPresent
        allowPurgeData = $false
        allowTakeOver = $false
    }
}

if ($Note -and $Note.Trim() -ne "") {
    $body.note = $Note
}

$bodyJson = $body | ConvertTo-Json -Depth 5

Write-Host "`nInitiating deployment..." -ForegroundColor Green

try {
    $uri = "https://api.fabric.microsoft.com/v1/deploymentPipelines/$PipelineId/deploy"
    
    $response = Invoke-RestMethod `
        -Uri $uri `
        -Method Post `
        -Headers $headers `
        -Body $bodyJson
    
    Write-Host "`n==========================================" -ForegroundColor Green
    Write-Host "SUCCESS: Deployment Initiated" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    
    if ($response.id) {
        Write-Host "Operation ID: $($response.id)" -ForegroundColor Cyan
    }
    
    Write-Host "`nDeployment is running in the background." -ForegroundColor Yellow
    Write-Host "Check the Fabric portal for deployment status." -ForegroundColor Yellow
    
    # Output result as JSON
    $result = @{
        success = $true
        pipelineId = $PipelineId
        sourceStageOrder = $SourceStageOrder
        targetStageOrder = $SourceStageOrder + 1
        operationId = $response.id
        message = "Deployment initiated successfully"
    }
    
    Write-Host "`n--- Result (JSON) ---" -ForegroundColor Gray
    $result | ConvertTo-Json
    
} catch {
    Write-Host "`n==========================================" -ForegroundColor Red
    Write-Host "ERROR: Deployment failed" -ForegroundColor Red
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
    Write-Host "  - Source or target workspace not assigned to stages" -ForegroundColor Yellow
    Write-Host "  - No items in source workspace to deploy" -ForegroundColor Yellow
    Write-Host "  - Insufficient permissions on source or target workspace" -ForegroundColor Yellow
    Write-Host "  - Items with same name exist in target (use -AllowOverwrite)" -ForegroundColor Yellow
    Write-Host "  - Another deployment is in progress" -ForegroundColor Yellow
    
    exit 1
}
