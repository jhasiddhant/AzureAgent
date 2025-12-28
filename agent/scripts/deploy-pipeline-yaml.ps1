# Deploy YAML Template to Azure DevOps Repository
# Deploys YAML file from agent templates folder to specified repo location

param(
  [Parameter(Mandatory=$false)] [string]$Organization,
  [Parameter(Mandatory=$false)] [string]$ProjectName,
  [Parameter(Mandatory=$false)] [string]$RepoName,
  [Parameter(Mandatory=$false)] [string]$TemplateName,
  [Parameter(Mandatory=$false)] [string]$Branch,
  [Parameter(Mandatory=$false)] [string]$FolderPath
)

if (-not $Organization) { $Organization = Read-Host "Enter Organization URL (e.g. https://dev.azure.com/yourorg)" }
if (-not $ProjectName) { $ProjectName = Read-Host "Enter Project Name" }
if (-not $RepoName) { $RepoName = Read-Host "Enter Repository Name" }
if (-not $TemplateName) { $TemplateName = Read-Host "Enter Template Name (e.g. basic-ci, azure-deploy, hello-world)" }
if (-not $Branch) { $Branch = Read-Host "Enter Branch Name (default: main)" }
if (-not $FolderPath) { $FolderPath = Read-Host "Enter Folder Path in repo (default: pipelines)" }

# Defaults
if ([string]::IsNullOrWhiteSpace($Branch)) { $Branch = "main" }
if ([string]::IsNullOrWhiteSpace($FolderPath)) { $FolderPath = "pipelines" }

# Normalize organization to URL
if ($Organization -notmatch '^https?://') {
  $Organization = "https://dev.azure.com/$Organization"
}

# Build target YAML path
$targetYamlPath = "$FolderPath/$TemplateName.yml"

Write-Host "`nDeploying YAML Template to Repository..." -ForegroundColor Green
Write-Host "Org: $Organization" -ForegroundColor Gray
Write-Host "Project: $ProjectName" -ForegroundColor Gray
Write-Host "Repo: $RepoName" -ForegroundColor Gray
Write-Host "Template: $TemplateName" -ForegroundColor Gray
Write-Host "Branch: $Branch" -ForegroundColor Gray
Write-Host "Target Path: $targetYamlPath" -ForegroundColor Gray

# Ensure extension is installed
$ext = az extension show --name azure-devops 2>$null
if (-not $ext) {
  Write-Host "Installing azure-devops extension..." -ForegroundColor Yellow
  az extension add --name azure-devops | Out-Null
}

# Get Azure AD token for authentication
$token = az account get-access-token --scope 499b84ac-1321-427f-aa17-267ca6975798/.default --query accessToken -o tsv 2>$null
if (-not $token) {
  Write-Host "`nAuthentication failed. Run 'az login' first." -ForegroundColor Red
  exit 1
}
$env:AZURE_DEVOPS_EXT_PAT = $token

# Configure defaults
az devops configure --defaults organization=$Organization project=$ProjectName | Out-Null

# Check if template exists locally
$scriptDir = Split-Path -Parent $PSCommandPath
$templatePath = Join-Path (Split-Path -Parent $scriptDir) "templates\$TemplateName.yml"

if (-not (Test-Path $templatePath)) {
  Write-Host "`nTemplate file not found: $templatePath" -ForegroundColor Red
  Write-Host "Available templates should be in: agent/templates/" -ForegroundColor Yellow
  Write-Host "Expected file: $TemplateName.yml" -ForegroundColor Yellow
  exit 1
}

Write-Host "Template found locally: $templatePath" -ForegroundColor Green

# Check if YAML already exists in repo
Write-Host "Checking if YAML already exists in repository..." -ForegroundColor Gray
$fileCheck = az repos show --repository $RepoName --path $targetYamlPath --branch $Branch --organization $Organization --project $ProjectName 2>&1
$yamlExists = $LASTEXITCODE -eq 0

if ($yamlExists) {
  Write-Host "`nYAML file already exists at $targetYamlPath in branch $Branch" -ForegroundColor Yellow
  $overwrite = Read-Host "Overwrite existing file? (y/n)"
  if ($overwrite -ne 'y') {
    Write-Host "Deployment cancelled." -ForegroundColor Yellow
    exit 0
  }
}

# Deploy YAML to repo using git
Write-Host "Deploying YAML to repository..." -ForegroundColor Gray
$tempDir = Join-Path $env:TEMP "ado-yaml-deploy-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
  Set-Location $tempDir
  
  $baseUrl = $Organization.TrimEnd('/')
  $repoUrl = "$baseUrl/$ProjectName/_git/$RepoName"
  $authenticatedUrl = $repoUrl -replace "https://", "https://:$token@"
  
  # Clone repo
  Write-Host "Cloning repository..." -ForegroundColor Gray
  git clone $authenticatedUrl --branch $Branch --single-branch . 2>&1 | Out-Null
  
  if ($LASTEXITCODE -ne 0) {
    Write-Host "`nFailed to clone repository." -ForegroundColor Red
    Write-Host "Branch '$Branch' may not exist or repository is empty." -ForegroundColor Yellow
    Write-Host "`nTo initialize an empty repo, use the clone URL from Azure DevOps." -ForegroundColor Gray
    exit 1
  }
  
  # Create directory structure if needed
  if ($FolderPath) {
    New-Item -ItemType Directory -Path $FolderPath -Force | Out-Null
  }
  
  # Copy template to target location
  Copy-Item $templatePath -Destination $targetYamlPath -Force
  Write-Host "Template copied to $targetYamlPath" -ForegroundColor Green
  
  # Get current user for git config
  $currentUser = az account show --query user.name -o tsv 2>$null
  if (-not $currentUser) { $currentUser = "Azure Agent" }
  
  git config user.email "$currentUser@azuredevops.com"
  git config user.name $currentUser
  git add $targetYamlPath
  
  $commitMsg = if ($yamlExists) { "Update pipeline YAML: $targetYamlPath" } else { "Add pipeline YAML: $targetYamlPath" }
  git commit -m $commitMsg 2>&1 | Out-Null
  
  Write-Host "Pushing to repository..." -ForegroundColor Gray
  git push origin $Branch 2>&1 | Out-Null
  
  if ($LASTEXITCODE -ne 0) {
    Write-Host "`nFailed to push YAML to repository." -ForegroundColor Red
    exit 1
  }
  
  Write-Host "`nYAML deployed successfully" -ForegroundColor Green
  Write-Host "details:" -ForegroundColor Gray
  Write-Host "Template: $TemplateName" -ForegroundColor Cyan
  Write-Host "Location: $targetYamlPath" -ForegroundColor Cyan
  Write-Host "Branch: $Branch" -ForegroundColor Cyan
  Write-Host "Repo URL: $repoUrl" -ForegroundColor Cyan
  
} catch {
  Write-Host "`nError deploying YAML: $_" -ForegroundColor Red
  exit 1
} finally {
  Set-Location $PSScriptRoot
  Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
