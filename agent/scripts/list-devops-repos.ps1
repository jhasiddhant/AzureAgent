# List Azure DevOps Repositories in a Project
# Simple script matching resource group pattern

param(
  [Parameter(Mandatory=$false)] [string]$Organization,
  [Parameter(Mandatory=$false)] [string]$ProjectName
)

if (-not $Organization) { $Organization = Read-Host "Enter Organization URL (e.g. https://dev.azure.com/yourorg)" }
if (-not $ProjectName) { $ProjectName = Read-Host "Enter Project Name" }

# Normalize organization to URL
if ($Organization -notmatch '^https?://') {
  $Organization = "https://dev.azure.com/$Organization"
}

Write-Host "`nListing Azure DevOps Repositories..." -ForegroundColor Green
Write-Host "Org: $Organization" -ForegroundColor Gray
Write-Host "Project: $ProjectName" -ForegroundColor Gray

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

# List repositories
$repos = az repos list --organization $Organization --project $ProjectName --query "[].{Name:name, Id:id, Size:size, DefaultBranch:defaultBranch}" -o json 2>&1

if ($LASTEXITCODE -ne 0) {
  Write-Host "`nFailed to list repositories." -ForegroundColor Red
  Write-Host "Error: $repos" -ForegroundColor Yellow
  Write-Host "`nCheck:" -ForegroundColor Red
  Write-Host "  1. You're logged in with 'az login'" -ForegroundColor Yellow
  Write-Host "  2. You have access to the project" -ForegroundColor Yellow
  Write-Host "  3. Project '$ProjectName' exists in the organization" -ForegroundColor Yellow
  exit 1
}

$repoList = $repos | ConvertFrom-Json

if ($repoList.Count -eq 0) {
  Write-Host "`nNo repositories found in project." -ForegroundColor Yellow
} else {
  Write-Host "`nFound $($repoList.Count) repository(ies):" -ForegroundColor Green
  Write-Host ""
  $baseUrl = $Organization.TrimEnd('/')
  $repoList | ForEach-Object {
    Write-Host "  Name: $($_.Name)" -ForegroundColor Cyan
    Write-Host "  URL: $baseUrl/$ProjectName/_git/$($_.Name)" -ForegroundColor Gray
    Write-Host "  Default Branch: $($_.DefaultBranch)" -ForegroundColor Gray
    if ($_.Size) {
      $sizeKB = [math]::Round($_.Size / 1024, 2)
      Write-Host "  Size: $sizeKB KB" -ForegroundColor Gray
    }
    Write-Host ""
  }
}
