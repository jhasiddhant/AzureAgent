Param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$TemplatePath,
    
    [Parameter(Mandatory=$false)]
    [string]$Parameters
)

Write-Host "Deploying Bicep template to Resource Group: $ResourceGroup" -ForegroundColor Cyan
Write-Host "Template: $TemplatePath" -ForegroundColor Cyan

# Check if resource group exists
try {
    $rgExists = az group exists -n $ResourceGroup 2>&1
    if ($rgExists -eq "false") {
        Write-Error "Resource group '$ResourceGroup' not found. Please create it first."
        exit 1
    }
} catch {
    Write-Error "Failed to check resource group: $_"
    exit 1
}

# Build deployment command
$deployCmd = "az deployment group create -g `"$ResourceGroup`" -f `"$TemplatePath`""

# Add parameters if provided
if ($Parameters) {
    Write-Host "Parameters: $Parameters" -ForegroundColor Yellow
    $deployCmd += " --parameters"
    $paramPairs = $Parameters -split ';'
    foreach ($pair in $paramPairs) {
        if ($pair.Trim()) {
            $deployCmd += " $($pair.Trim())"
        }
    }
}

Write-Host "Executing: $deployCmd" -ForegroundColor Gray

# Execute deployment using Invoke-Expression to handle the complex command string
try {
    $result = Invoke-Expression $deployCmd 2>&1
    Write-Output $result
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Deployment failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
} catch {
    Write-Error "Deployment execution failed: $_"
    exit 1
}