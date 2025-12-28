Param(
    [Parameter(Mandatory=$true)] [string]$ResourceGroupName,
    [Parameter(Mandatory=$true)] [string]$WorkspaceId,
    [Parameter(Mandatory=$true)] [string]$ResourceId
)
$ErrorActionPreference = "Stop"

$diagName = "diag-" + ($ResourceId -split '/')[-1]

Write-Output "Configuring diagnostic setting: $diagName"
Write-Output "Resource: $ResourceId"
Write-Output "Workspace: $WorkspaceId"

# Fetch all available log categories
Write-Output "`nFetching available log categories..."
$logCategories = az monitor diagnostic-settings categories list --resource $ResourceId --query "value[?categoryType=='Logs'].name" -o tsv 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to fetch log categories. Error: $logCategories"
    exit 1
}

# Fetch all available metric categories
Write-Output "Fetching available metric categories..."
$metricCategories = az monitor diagnostic-settings categories list --resource $ResourceId --query "value[?categoryType=='Metrics'].name" -o tsv 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to fetch metric categories. Error: $metricCategories"
    exit 1
}

# Build logs array
$logsArray = @()
foreach ($category in $logCategories) {
    if ($category -and $category.Trim()) {
        $logsArray += @{category=$category.Trim(); enabled=$true}
    }
}

# Build metrics array
$metricsArray = @()
foreach ($category in $metricCategories) {
    if ($category -and $category.Trim()) {
        $metricsArray += @{category=$category.Trim(); enabled=$true}
    }
}

Write-Output "`nEnabling $($logsArray.Count) log categories and $($metricsArray.Count) metric categories..."

# Convert to JSON - ensure it's an array even if single item
$logsJson = if ($logsArray.Count -eq 1) { 
    "[$($logsArray | ConvertTo-Json -Compress)]" 
} else { 
    $logsArray | ConvertTo-Json -Compress 
}

$metricsJson = if ($metricsArray.Count -eq 1) { 
    "[$($metricsArray | ConvertTo-Json -Compress)]" 
} else { 
    $metricsArray | ConvertTo-Json -Compress 
}

# Az diagnostic-settings create is idempotent (it updates if exists), so safe to run.
$result = az monitor diagnostic-settings create `
    --name $diagName `
    --resource $ResourceId `
    --workspace $WorkspaceId `
    --logs $logsJson `
    --metrics $metricsJson `
    --output json 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to configure diagnostic setting. Error: $result"
    exit 1
}

Write-Output "`n✓ Diagnostic setting '$diagName' successfully configured."
Write-Output "`nEnabled log categories:"
$logsArray | ForEach-Object { Write-Output "  - $($_.category)" }
Write-Output "`nEnabled metric categories:"
$metricsArray | ForEach-Object { Write-Output "  - $($_.category)" }