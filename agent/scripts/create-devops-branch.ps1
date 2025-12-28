# Create Azure DevOps Branch from Base Branch
# Simple script matching resource group pattern

param(
  [Parameter(Mandatory=$false)] [string]$Organization,
  [Parameter(Mandatory=$false)] [string]$ProjectName,
  [Parameter(Mandatory=$false)] [string]$RepoName,
  [Parameter(Mandatory=$false)] [string]$BranchName,
  [Parameter(Mandatory=$false)] [string]$BaseBranch
)

if (-not $Organization) { $Organization = Read-Host "Enter Organization URL (e.g. https://dev.azure.com/yourorg)" }
if (-not $ProjectName) { $ProjectName = Read-Host "Enter Project Name" }
if (-not $RepoName) { $RepoName = Read-Host "Enter Repository Name" }
if (-not $BranchName) { $BranchName = Read-Host "Enter New Branch Name (e.g. dev or feature/myfeature)" }
if (-not $BaseBranch) { $BaseBranch = Read-Host "Enter Base Branch Name (default: main)" }

# Default to main if not provided
if ([string]::IsNullOrWhiteSpace($BaseBranch)) {
  $BaseBranch = "main"
}

# Normalize organization to URL
if ($Organization -notmatch '^https?://') {
  $Organization = "https://dev.azure.com/$Organization"
}

Write-Host "`nCreating Azure DevOps Branch..." -ForegroundColor Green
Write-Host "Org: $Organization" -ForegroundColor Gray
Write-Host "Project: $ProjectName" -ForegroundColor Gray
Write-Host "Repo: $RepoName" -ForegroundColor Gray
Write-Host "New Branch: $BranchName" -ForegroundColor Gray
Write-Host "Base Branch: $BaseBranch" -ForegroundColor Gray

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

# Get the base branch object ID (commit SHA)
Write-Host "Getting base branch commit..." -ForegroundColor Gray
$baseBranchRef = "refs/heads/$BaseBranch"
$branchInfo = az repos ref list --repository $RepoName --organization $Organization --project $ProjectName --filter "heads/$BaseBranch" --query "[0].objectId" -o tsv 2>&1

if ($LASTEXITCODE -ne 0) {
  Write-Host "`nFailed to get base branch." -ForegroundColor Red
  Write-Host "Error: $branchInfo" -ForegroundColor Yellow
  Write-Host "`nCheck:" -ForegroundColor Red
  Write-Host "  1. Base branch '$BaseBranch' exists in the repository" -ForegroundColor Yellow
  Write-Host "  2. Repository '$RepoName' exists and is not empty" -ForegroundColor Yellow
  Write-Host "  3. You have access to the project and repo" -ForegroundColor Yellow
  exit 1
}

$baseCommitId = $branchInfo.Trim()

if ([string]::IsNullOrWhiteSpace($baseCommitId)) {
  Write-Host "`nBase branch '$BaseBranch' not found or repository is empty." -ForegroundColor Red
  exit 1
}

# Create the new branch
Write-Host "Creating branch '$BranchName'..." -ForegroundColor Gray
$newBranchRef = "refs/heads/$BranchName"
$createOutput = az repos ref create --name $newBranchRef --object-id $baseCommitId --repository $RepoName --organization $Organization --project $ProjectName 2>&1

if ($LASTEXITCODE -ne 0) {
  Write-Host "`nBranch creation failed." -ForegroundColor Red
  Write-Host "Error: $createOutput" -ForegroundColor Yellow
  Write-Host "`nCheck:" -ForegroundColor Red
  Write-Host "  1. Branch '$BranchName' doesn't already exist" -ForegroundColor Yellow
  Write-Host "  2. You have Code Write permissions in the project" -ForegroundColor Yellow
  exit 1
}

$baseUrl = $Organization.TrimEnd('/')
Write-Host "`nBranch created successfully" -ForegroundColor Green
Write-Host "details:" -ForegroundColor Gray
Write-Host "Branch: $BranchName" -ForegroundColor Cyan
Write-Host "Base: $BaseBranch" -ForegroundColor Cyan
Write-Host "URL: $baseUrl/$ProjectName/_git/$RepoName?version=GB$BranchName" -ForegroundColor Cyan
