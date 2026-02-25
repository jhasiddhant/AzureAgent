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

# Build argument list for az CLI
$azArgs = @("deployment", "group", "create", "-g", $ResourceGroup, "-f", $TemplatePath)

# Add parameters if provided
if ($Parameters) {
    Write-Host "Parameters: $Parameters" -ForegroundColor Yellow
    $azArgs += "--parameters"
    $paramPairs = $Parameters -split ';'
    foreach ($pair in $paramPairs) {
        if ($pair.Trim()) {
            $azArgs += $pair.Trim()
        }
    }
}

# Build display command for logging
$displayCmd = "az " + ($azArgs -join " ")
Write-Host "Executing: $displayCmd" -ForegroundColor Gray

# Execute deployment - capture stdout and stderr
$ErrorActionPreference = "Continue"

try {
    # Run az CLI directly and capture all output
    $result = & az @azArgs 2>&1
    $exitCode = $LASTEXITCODE
    
    # Separate stdout and stderr from combined output
    $stdout = @()
    $stderr = @()
    
    foreach ($line in $result) {
        if ($line -is [System.Management.Automation.ErrorRecord]) {
            $stderr += $line.ToString()
        } else {
            $stdout += $line
        }
    }
    
    $stdoutText = $stdout -join "`n"
    $stderrText = $stderr -join "`n"
    $allOutput = "$stdoutText`n$stderrText".Trim()
    
    if ($exitCode -ne 0) {
        # Use [Console]::Error to ensure output reaches subprocess stderr
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("═══════════════════════════════════════════════════════════")
        [Console]::Error.WriteLine("DEPLOYMENT FAILED")
        [Console]::Error.WriteLine("═══════════════════════════════════════════════════════════")
        
        if ($allOutput) {
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("Azure CLI Output:")
            [Console]::Error.WriteLine($allOutput)
            
            # Try to extract JSON error details
            if ($allOutput -match '"code"\s*:\s*"([^"]+)"') {
                [Console]::Error.WriteLine("")
                [Console]::Error.WriteLine("Error Code: $($Matches[1])")
            }
            if ($allOutput -match '"message"\s*:\s*"([^"]+)"') {
                [Console]::Error.WriteLine("Error Message: $($Matches[1])")
            }
        } else {
            [Console]::Error.WriteLine("")
            [Console]::Error.WriteLine("No output captured from Azure CLI")
        }
        
        [Console]::Error.WriteLine("")
        [Console]::Error.WriteLine("═══════════════════════════════════════════════════════════")
        exit $exitCode
    }
    
    # Success - output the result
    if ($stdoutText) {
        Write-Output $stdoutText
    }
} catch {
    Write-Error "Deployment execution failed: $_"
    exit 1
}