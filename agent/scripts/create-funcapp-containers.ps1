# ============================================================================
# CREATE FUNCTION APP ADLS CONTAINERS
# Creates required containers for Azure Function App Flex Consumption
# Skips containers that already exist
# ============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = ""
)

$ErrorActionPreference = "Stop"

# Required containers for Function App Flex Consumption
$requiredContainers = @(
    "azure-webjobs-hosts",
    "azure-webjobs-secrets", 
    "deployments",
    "scm-releases"
)

Write-Host ""
Write-Host "Creating ADLS containers for Function App..." -ForegroundColor Cyan
Write-Host "Storage Account: $StorageAccountName" -ForegroundColor Gray
Write-Host ""

$createdCount = 0
$skippedCount = 0
$failedCount = 0

foreach ($container in $requiredContainers) {
    try {
        # Check if container exists
        $existsCheck = az storage container exists `
            --name $container `
            --account-name $StorageAccountName `
            --auth-mode login `
            --only-show-errors `
            -o tsv `
            --query "exists" 2>$null
        
        if ($existsCheck -eq "true") {
            Write-Host "  [SKIP] $container (already exists)" -ForegroundColor Yellow
            $skippedCount++
        }
        else {
            # Create container
            az storage container create `
                --name $container `
                --account-name $StorageAccountName `
                --auth-mode login `
                --only-show-errors `
                --output none 2>$null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK]   $container" -ForegroundColor Green
                $createdCount++
            }
            else {
                Write-Host "  [FAIL] $container" -ForegroundColor Red
                $failedCount++
            }
        }
    }
    catch {
        Write-Host "  [FAIL] $container - $_" -ForegroundColor Red
        $failedCount++
    }
}

Write-Host ""
Write-Host "Container Summary:" -ForegroundColor Cyan
Write-Host "  Created: $createdCount" -ForegroundColor Green
Write-Host "  Skipped: $skippedCount (already existed)" -ForegroundColor Yellow
if ($failedCount -gt 0) {
    Write-Host "  Failed:  $failedCount" -ForegroundColor Red
    Write-Host ""
    Write-Host "Some containers failed to create. Ensure you have:" -ForegroundColor Red
    Write-Host "  - 'Storage Blob Data Contributor' role on the storage account" -ForegroundColor Red
    Write-Host "  - Or the storage account allows public access" -ForegroundColor Red
}
Write-Host ""

# Return success if no failures
if ($failedCount -eq 0) {
    exit 0
}
else {
    exit 1
}
