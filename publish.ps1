<#
.SYNOPSIS
    Build and publish azure-customazuremcpagent-agent package to Production PyPI.

.DESCRIPTION
    This script builds and publishes to PRODUCTION PyPI (pypi.org).
    ⚠️  WARNING: Production uploads are PERMANENT and cannot be deleted.
    Always test with publish-test.ps1 first!

.PARAMETER SkipBuild
    Skip the build step and only upload existing dist/ files.

.PARAMETER SkipConfirmation
    Skip the safety confirmation prompt (use for CI/CD only).

.EXAMPLE
    .\publish-prod.ps1
    # Build and upload to Production PyPI with confirmation

.EXAMPLE
    .\publish-prod.ps1 -SkipBuild
    # Upload existing dist/ files to Production PyPI

.EXAMPLE
    .\publish-prod.ps1 -SkipConfirmation
    # Upload without confirmation (CI/CD use)
#>

param(
    [switch]$SkipBuild,
    [switch]$SkipConfirmation
)

$ErrorActionPreference = "Stop"

# Colors
function Write-Success { Write-Host $args -ForegroundColor Green }
function Write-Info { Write-Host $args -ForegroundColor Cyan }
function Write-Warning { Write-Host $args -ForegroundColor Yellow }
function Write-Error { Write-Host $args -ForegroundColor Red }

$packageDir = $PSScriptRoot

Write-Info "================================================================"
Write-Warning "  Azure customazuremcpagent Agent - PRODUCTION PyPI Publisher"
Write-Info "================================================================"
Write-Info ""

# Check if required tools are installed
Write-Info "Checking prerequisites..."
try {
    python --version | Out-Null
    Write-Success "✓ Python installed"
} catch {
    Write-Error "✗ Python not found. Please install Python 3.10+"
    exit 1
}

try {
    python -m pip --version | Out-Null
    Write-Success "✓ pip installed"
} catch {
    Write-Error "✗ pip not found"
    exit 1
}

# Install/upgrade build tools
Write-Info ""
Write-Info "Installing/upgrading build tools..."
python -m pip install --upgrade pip build twine --quiet
Write-Success "✓ Build tools ready"

# Prompt for version
Write-Info ""
Write-Info "==================================================="
Write-Warning "Production Version Configuration"
Write-Info "==================================================="
$prodVersion = Read-Host "Enter version for Production PyPI (e.g., 1.0.0, 1.1.0)"
if (-not $prodVersion -or $prodVersion.Trim() -eq "") {
    Write-Error "Version is required. Exiting."
    exit 1
}
Write-Info "Version set to: $prodVersion"

if (-not $SkipBuild) {
    # Navigate to package directory
    Write-Info ""
    Write-Info "Working in: $packageDir"
    Push-Location $packageDir

    try {
        # Modify version in pyproject.toml
        Write-Info ""
        Write-Info "Updating version in pyproject.toml..."
        $pyprojectPath = "pyproject.toml"
        $pyprojectBackup = "pyproject.toml.backup"
        
        # Backup original pyproject.toml
        Copy-Item $pyprojectPath $pyprojectBackup -Force
        
        # Modify the version in pyproject.toml
        $content = Get-Content $pyprojectPath -Raw
        $content = $content -replace 'version = "[^"]+"', "version = `"$prodVersion`""
        Set-Content $pyprojectPath $content -NoNewline
        Write-Success "✓ Version: $prodVersion"
        
        # Clean previous builds
        Write-Info ""
        Write-Info "Cleaning previous builds..."
        $dirsToRemove = @("dist", "build")
        foreach ($dir in $dirsToRemove) {
            if (Test-Path $dir) {
                Remove-Item -Recurse -Force $dir
                Write-Info "  Removed $dir/"
            }
        }
        Get-ChildItem -Filter "*.egg-info" -Directory | Remove-Item -Recurse -Force
        Write-Success "✓ Cleaned build directories"

        # Build the package
        Write-Info ""
        Write-Info "Building package..."
        python -m build
        
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed with exit code $LASTEXITCODE"
        }
        
        Write-Success "✓ Package built successfully"
        
        # Show what was built
        Write-Info ""
        Write-Info "Built files:"
        Get-ChildItem dist/ | ForEach-Object {
            Write-Info "  - $($_.Name) ($([math]::Round($_.Length/1KB, 2)) KB)"
        }
        
        # Restore original pyproject.toml
        Write-Info ""
        Write-Info "Restoring original pyproject.toml..."
        $pyprojectBackup = "pyproject.toml.backup"
        if (Test-Path $pyprojectBackup) {
            Move-Item $pyprojectBackup "pyproject.toml" -Force
            Write-Success "✓ Original pyproject.toml restored"
        }
    }
    catch {
        # Ensure backup is restored even on error
        $pyprojectBackup = "pyproject.toml.backup"
        if (Test-Path $pyprojectBackup) {
            Move-Item $pyprojectBackup "pyproject.toml" -Force
        }
        throw
    }
    finally {
        Pop-Location
    }
} else {
    Write-Warning "Skipping build - using existing dist/ files"
}

# Safety confirmation
Write-Info ""
Write-Info "==================================================="
Write-Warning "⚠️  PRODUCTION PyPI UPLOAD"
Write-Info "==================================================="
Write-Info ""
Write-Warning "You are about to upload to PRODUCTION PyPI (https://pypi.org)"
Write-Warning "Package: customazuremcpagent"
Write-Warning "Version: $prodVersion"
Write-Warning "This action is PERMANENT and cannot be undone!"
Write-Info ""
Write-Info "Checklist before proceeding:"
Write-Host "  ☐ Tested on TestPyPI successfully" -ForegroundColor Yellow
Write-Host "  ☐ Version number is correct and incremented" -ForegroundColor Yellow
Write-Host "  ☐ CHANGELOG updated" -ForegroundColor Yellow
Write-Host "  ☐ All tests passing" -ForegroundColor Yellow
Write-Host "  ☐ Code reviewed and approved" -ForegroundColor Yellow
Write-Info ""

if (-not $SkipConfirmation) {
    $confirmation = Read-Host "Type 'PUBLISH' to confirm production upload"
    if ($confirmation -ne "PUBLISH") {
        Write-Warning "Upload cancelled - confirmation not received."
        exit 0
    }
}

# Upload to Production PyPI
Write-Info ""
Write-Info "Uploading to Production PyPI..."
Write-Info ""

Push-Location $packageDir
try {
    $pypircPath = Join-Path $packageDir ".pypirc"
    Write-Info "Using config file: $pypircPath"
    python -m twine upload --config-file $pypircPath dist/*
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success ""
        Write-Success "✓ Successfully uploaded to Production PyPI!"
        Write-Info ""
        Write-Info "Install with:"
        Write-Host "  pip install customazuremcpagent" -ForegroundColor Cyan
        Write-Info ""
        Write-Info "Or run with uvx:"
        Write-Host "  uvx customazuremcpagent" -ForegroundColor Cyan
        Write-Info ""
        Write-Success "View at: https://pypi.org/project/customazuremcpagent/"
        Write-Info ""
        Write-Success "🎉 Package is now live on PyPI!"
    } else {
        Write-Error "Upload failed with exit code $LASTEXITCODE"
        exit 1
    }
}
finally {
    Pop-Location
}

Write-Info ""
Write-Success "==================================================="
Write-Success "  Done!"
Write-Success "==================================================="
