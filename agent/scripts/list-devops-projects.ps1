# List Azure DevOps Projects in an Organization
# Simple script matching resource group pattern

param(
  [Parameter(Mandatory=$false)] [string]$Organization
)

if (-not $Organization) { $Organization = Read-Host "Enter Organization URL (e.g. https://dev.azure.com/yourorg)" }

# Normalize organization to URL
if ($Organization -notmatch '^https?://') {
  $Organization = "https://dev.azure.com/$Organization"
}

Write-Host "`nListing Azure DevOps Projects..." -ForegroundColor Green
Write-Host "Org: $Organization" -ForegroundColor Gray

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
az devops configure --defaults organization=$Organization | Out-Null

# List projects
$projects = az devops project list --organization $Organization --query "value[].{Name:name, Id:id, State:state, Visibility:visibility}" -o json 2>&1

if ($LASTEXITCODE -ne 0) {
  Write-Host "`nFailed to list projects." -ForegroundColor Red
  Write-Host "Error: $projects" -ForegroundColor Yellow
  Write-Host "`nCheck:" -ForegroundColor Red
  Write-Host "  1. You're logged in with 'az login'" -ForegroundColor Yellow
  Write-Host "  2. You have access to the organization" -ForegroundColor Yellow
  Write-Host "  3. Organization URL is correct" -ForegroundColor Yellow
  exit 1
}

$projectList = $projects | ConvertFrom-Json

if ($projectList.Count -eq 0) {
  Write-Host "`nNo projects found in organization." -ForegroundColor Yellow
} else {
  Write-Host "`nFound $($projectList.Count) project(s):" -ForegroundColor Green
  Write-Host ""
  $projectList | ForEach-Object {
    $baseUrl = $Organization.TrimEnd('/')
    Write-Host "  Name: $($_.Name)" -ForegroundColor Cyan
    Write-Host "  URL: $baseUrl/$($_.Name)" -ForegroundColor Gray
    Write-Host "  State: $($_.State)" -ForegroundColor Gray
    Write-Host "  Visibility: $($_.Visibility)" -ForegroundColor Gray
    Write-Host ""
  }
}
