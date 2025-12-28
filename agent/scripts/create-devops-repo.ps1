# Create Azure DevOps Repository
# Simple script matching resource group pattern

param(
  [Parameter(Mandatory=$false)] [string]$Organization,
  [Parameter(Mandatory=$false)] [string]$ProjectName,
  [Parameter(Mandatory=$false)] [string]$RepoName
)

if (-not $Organization) { $Organization = Read-Host "Enter Organization URL (e.g. https://dev.azure.com/yourorg)" }
if (-not $ProjectName) { $ProjectName = Read-Host "Enter Project Name" }
if (-not $RepoName) { $RepoName = Read-Host "Enter Repository Name" }

# Normalize organization to URL
if ($Organization -notmatch '^https?://') {
  $Organization = "https://dev.azure.com/$Organization"
}

Write-Host "\nCreating Azure DevOps Repository..." -ForegroundColor Green
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
az devops configure --defaults organization=$Organization project=$ProjectName | Out-Null

# Create repository
Write-Host "Creating repository..." -ForegroundColor Gray
$createOutput = az repos create --name $RepoName --organization $Organization --project $ProjectName 2>&1

if ($LASTEXITCODE -ne 0) {
  Write-Host "\nRepository creation failed." -ForegroundColor Red
  Write-Host "Error: $createOutput" -ForegroundColor Yellow
  Write-Host "\nCheck:" -ForegroundColor Red
  Write-Host "  1. You're logged in with 'az login'" -ForegroundColor Yellow
  Write-Host "  2. You have Code Write permissions in the project" -ForegroundColor Yellow
  Write-Host "  3. Project '$ProjectName' exists in the organization" -ForegroundColor Yellow
  exit 1
}

Write-Host "Repository created successfully" -ForegroundColor Green

$baseUrl = $Organization.TrimEnd('/')
Write-Host "\ndeployment successful" -ForegroundColor Green
Write-Host "details:" -ForegroundColor Gray
Write-Host "Org: $baseUrl" -ForegroundColor Cyan
Write-Host "Project: $baseUrl/$ProjectName" -ForegroundColor Cyan
Write-Host "Repo: $baseUrl/$ProjectName/_git/$RepoName" -ForegroundColor Cyan
Write-Host "\nNote: Repository created but not initialized." -ForegroundColor Yellow
Write-Host "To initialize, clone the repo and push your first commit:" -ForegroundColor Gray
Write-Host "  git clone $baseUrl/$ProjectName/_git/$RepoName" -ForegroundColor Gray