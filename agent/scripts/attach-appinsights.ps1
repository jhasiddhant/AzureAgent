param(
    [Parameter(Mandatory=$true)]
    [string]$AppInsightsName,

    [Parameter(Mandatory=$true)]
    [string]$AppInsightsResourceGroup,

    [Parameter(Mandatory=$true)]
    [string]$TargetAppName,

    [Parameter(Mandatory=$true)]
    [string]$TargetResourceGroup,

    [Parameter(Mandatory=$true)]
    [ValidateSet("functionapp", "webapp")]
    [string]$TargetType
)

$ErrorActionPreference = "Stop"

# Get Application Insights details
Write-Host "Getting Application Insights '$AppInsightsName' details..."
$appInsights = az monitor app-insights component show `
    --app $AppInsightsName `
    --resource-group $AppInsightsResourceGroup `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to get Application Insights: $appInsights"
    exit 1
}

$appInsightsObj = $appInsights | ConvertFrom-Json
$connectionString = $appInsightsObj.connectionString
$instrumentationKey = $appInsightsObj.instrumentationKey
$appInsightsId = $appInsightsObj.id

if (-not $connectionString) {
    Write-Error "Application Insights connection string not found"
    exit 1
}

Write-Host "Application Insights ID: $appInsightsId"

# Verify target app exists
Write-Host "Verifying $TargetType '$TargetAppName' exists..."
if ($TargetType -eq "functionapp") {
    $targetApp = az functionapp show `
        --name $TargetAppName `
        --resource-group $TargetResourceGroup `
        --output json 2>&1
} else {
    $targetApp = az webapp show `
        --name $TargetAppName `
        --resource-group $TargetResourceGroup `
        --output json 2>&1
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to find $TargetType '$TargetAppName': $targetApp"
    exit 1
}

$targetAppObj = $targetApp | ConvertFrom-Json
Write-Host "$TargetType found: $($targetAppObj.name)"

# Update app settings with Application Insights
Write-Host "Attaching Application Insights to $TargetType..."

$settings = @(
    "APPLICATIONINSIGHTS_CONNECTION_STRING=$connectionString",
    "APPINSIGHTS_INSTRUMENTATIONKEY=$instrumentationKey",
    "ApplicationInsightsAgent_EXTENSION_VERSION=~3"
)

if ($TargetType -eq "functionapp") {
    $result = az functionapp config appsettings set `
        --name $TargetAppName `
        --resource-group $TargetResourceGroup `
        --settings $settings `
        --output json 2>&1
} else {
    $result = az webapp config appsettings set `
        --name $TargetAppName `
        --resource-group $TargetResourceGroup `
        --settings $settings `
        --output json 2>&1
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to update app settings: $result"
    exit 1
}

Write-Host "Successfully attached Application Insights '$AppInsightsName' to $TargetType '$TargetAppName'"

# Return result as JSON
$output = @{
    status = "success"
    appInsightsName = $AppInsightsName
    appInsightsId = $appInsightsId
    targetApp = $TargetAppName
    targetType = $TargetType
    settingsUpdated = @(
        "APPLICATIONINSIGHTS_CONNECTION_STRING",
        "APPINSIGHTS_INSTRUMENTATIONKEY",
        "ApplicationInsightsAgent_EXTENSION_VERSION"
    )
}

$output | ConvertTo-Json -Depth 10
