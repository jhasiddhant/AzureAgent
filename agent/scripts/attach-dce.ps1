<#
.SYNOPSIS
    Attaches a Data Collection Endpoint (DCE) to a Data Collection Rule (DCR).

.DESCRIPTION
    Updates an existing Data Collection Rule to reference a Data Collection Endpoint.
    This is required for:
    - Logs Ingestion API
    - Azure Monitor Private Link Scope (AMPLS)
    - VNet-isolated data ingestion

.PARAMETER DcrName
    Name of the Data Collection Rule.

.PARAMETER DcrResourceGroup
    Resource group containing the DCR.

.PARAMETER DceName
    Name of the Data Collection Endpoint to attach.

.PARAMETER DceResourceGroup
    Resource group containing the DCE. Defaults to DCR resource group.

.PARAMETER SubscriptionId
    Subscription ID. Uses current context if not specified.

.EXAMPLE
    .\attach-dce.ps1 -DcrName "my-dcr" -DcrResourceGroup "monitoring-rg" -DceName "my-dce"

.EXAMPLE
    .\attach-dce.ps1 -DcrName "my-dcr" -DcrResourceGroup "app-rg" -DceName "my-dce" -DceResourceGroup "shared-rg"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$DcrName,
    
    [Parameter(Mandatory=$true)]
    [string]$DcrResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$DceName,
    
    [Parameter(Mandatory=$false)]
    [string]$DceResourceGroup = $DcrResourceGroup,
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId
)

$ErrorActionPreference = "Stop"

# Set subscription if provided
if ($SubscriptionId) {
    Write-Host "Setting subscription to: $SubscriptionId" -ForegroundColor Cyan
    az account set --subscription $SubscriptionId
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to set subscription"
        exit 1
    }
}

# Get current subscription
$currentSub = az account show --query "id" -o tsv
Write-Host "Using subscription: $currentSub" -ForegroundColor Cyan

# Get DCE resource ID
Write-Host "`nLooking up DCE: $DceName in resource group: $DceResourceGroup" -ForegroundColor Cyan
$dceId = az monitor data-collection endpoint show `
    --name $DceName `
    --resource-group $DceResourceGroup `
    --query "id" -o tsv

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($dceId)) {
    Write-Error "Failed to find Data Collection Endpoint '$DceName' in resource group '$DceResourceGroup'"
    exit 1
}

Write-Host "  DCE ID: $dceId" -ForegroundColor Green

# Get current DCR configuration
Write-Host "`nLooking up DCR: $DcrName in resource group: $DcrResourceGroup" -ForegroundColor Cyan
$dcr = az monitor data-collection rule show `
    --name $DcrName `
    --resource-group $DcrResourceGroup `
    --query "{id:id, currentDce:dataCollectionEndpointResourceId, kind:kind}" -o json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0 -or $null -eq $dcr) {
    Write-Error "Failed to find Data Collection Rule '$DcrName' in resource group '$DcrResourceGroup'"
    exit 1
}

Write-Host "  DCR ID: $($dcr.id)" -ForegroundColor Green

# Check if DCE is already attached
if ($dcr.currentDce -eq $dceId) {
    Write-Host "`nDCE is already attached to this DCR." -ForegroundColor Yellow
    Write-Host "  Current DCE: $dceId" -ForegroundColor Yellow
    exit 0
}

if (![string]::IsNullOrEmpty($dcr.currentDce)) {
    Write-Host "`nNote: DCR currently has a different DCE attached:" -ForegroundColor Yellow
    Write-Host "  Current DCE: $($dcr.currentDce)" -ForegroundColor Yellow
    Write-Host "  Will be replaced with: $dceId" -ForegroundColor Yellow
}

# Update DCR to attach DCE
Write-Host "`nAttaching DCE to DCR..." -ForegroundColor Cyan
$result = az monitor data-collection rule update `
    --name $DcrName `
    --resource-group $DcrResourceGroup `
    --data-collection-endpoint-id $dceId `
    --query "{name:name, dce:dataCollectionEndpointResourceId, immutableId:immutableId}" -o json

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to attach DCE to DCR"
    exit 1
}

$resultObj = $result | ConvertFrom-Json

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "SUCCESS: DCE attached to DCR" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  DCR Name:        $($resultObj.name)"
Write-Host "  DCR Immutable ID: $($resultObj.immutableId)"
Write-Host "  Attached DCE:    $($resultObj.dce)"
Write-Host ""
