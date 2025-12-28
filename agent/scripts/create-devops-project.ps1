# Create Azure DevOps Project with initial repository
# Simple script matching resource group pattern

param(
  [Parameter(Mandatory = $true)] [string]$Organization,
  [Parameter(Mandatory = $true)] [string]$ProjectName,
  [Parameter(Mandatory = $true)] [string]$RepoName,
  [Parameter(Mandatory = $false)] [string]$Description
)

if (-not $Organization) { $Organization = Read-Host "Enter Organization URL (e.g. https://dev.azure.com/yourorg)" }
if (-not $ProjectName) { $ProjectName = Read-Host "Enter Project Name" }
if (-not $RepoName) { $RepoName = Read-Host "Enter Repository Name" }
if (-not $Description) { $Description = Read-Host "Enter Project Description (optional)" }

# Normalize organization to URL
if ($Organization -notmatch '^https?://') {
  $Organization = "https://dev.azure.com/$Organization"
}

Write-Host "\nCreating Azure DevOps Project..." -ForegroundColor Green
Write-Host "Org: $Organization" -ForegroundColor Gray
Write-Host "Project: $ProjectName" -ForegroundColor Gray
Write-Host "Repo: $RepoName" -ForegroundColor Gray

# Ensure extension is installed
$ext = az extension show --name azure-devops 2>$null
if (-not $ext) {
  Write-Host "Installing azure-devops extension..." -ForegroundColor Yellow
  az extension add --name azure-devops | Out-Null
}

# Get Azure AD token for authentication
$token = az account get-access-token --scope 499b84ac-1321-427f-aa17-267ca6975798/.default --query accessToken -o tsv 2>$null
if (-not $token) {
  Write-Host "\nAuthentication failed. Run 'az login' first." -ForegroundColor Red
  exit 1
}
$env:AZURE_DEVOPS_EXT_PAT = $token

# Configure defaults
az devops configure --defaults organization=$Organization | Out-Null

# Create project
az devops project create `
  --name $ProjectName `
  --org $Organization `
  --visibility private `
  --source-control Git `
  --description $Description 2>$null

if ($LASTEXITCODE -ne 0) {
  Write-Host "\nProject creation failed. Check:" -ForegroundColor Red
  Write-Host "  1. You're logged in with 'az login'" -ForegroundColor Yellow
  Write-Host "  2. You have Project Create permissions in the organization" -ForegroundColor Yellow
  Write-Host "  3. Organization URL is correct" -ForegroundColor Yellow
  exit 1
}

# Rename default repo to desired name if different
az devops configure --defaults organization=$Organization project=$ProjectName | Out-Null

if ($RepoName -ne $ProjectName) {
  Write-Host "Renaming default repository to '$RepoName'..." -ForegroundColor Gray
  Start-Sleep -Seconds 2
  
  # Get the default repo ID
  $repoId = az repos list --organization $Organization --project $ProjectName --query "[0].id" -o tsv 2>$null
  
  if ($repoId) {
    $repoUpdateResult = az repos update --repository $repoId --name $RepoName --organization $Organization --project $ProjectName 2>&1
    if ($LASTEXITCODE -eq 0) {
      Write-Host "Repository renamed successfully" -ForegroundColor Green
    } else {
      Write-Host "Warning: Could not rename repository. Using project name '$ProjectName' as repo name." -ForegroundColor Yellow
      $RepoName = $ProjectName
    }
  } else {
    Write-Host "Warning: Could not get repository ID. Using project name '$ProjectName' as repo name." -ForegroundColor Yellow
    $RepoName = $ProjectName
  }
}

$baseUrl = $Organization.TrimEnd('/')
Write-Host "\ndeployment successful" -ForegroundColor Green
Write-Host "details:" -ForegroundColor Gray
Write-Host "Org: $baseUrl" -ForegroundColor Cyan
Write-Host "Project: $baseUrl/$ProjectName" -ForegroundColor Cyan
Write-Host "Repo: $baseUrl/$ProjectName/_git/$RepoName" -ForegroundColor Cyan
Write-Host "\nNote: Repository created but not initialized." -ForegroundColor Yellow
Write-Host "To initialize, clone the repo and push your first commit:" -ForegroundColor Gray
Write-Host "  git clone $baseUrl/$ProjectName/_git/$RepoName" -ForegroundColor Gray