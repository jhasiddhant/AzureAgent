# Create Azure DevOps Pipeline
# Checks if YAML exists, then creates pipeline

param(
  [Parameter(Mandatory=$false)] [string]$Organization,
  [Parameter(Mandatory=$false)] [string]$ProjectName,
  [Parameter(Mandatory=$false)] [string]$RepoName,
  [Parameter(Mandatory=$false)] [string]$PipelineName,
  [Parameter(Mandatory=$false)] [string]$Branch,
  [Parameter(Mandatory=$false)] [string]$YamlPath
)

if (-not $Organization) { $Organization = Read-Host "Enter Organization URL (e.g. https://dev.azure.com/yourorg)" }
if (-not $ProjectName) { $ProjectName = Read-Host "Enter Project Name" }
if (-not $RepoName) { $RepoName = Read-Host "Enter Repository Name" }
if (-not $PipelineName) { $PipelineName = Read-Host "Enter Pipeline Name" }
if (-not $Branch) { $Branch = Read-Host "Enter Branch (default: main)" }
if (-not $YamlPath) { $YamlPath = Read-Host "Enter YAML File Path (e.g. pipelines/basic-ci.yml)" }

# Defaults
if ([string]::IsNullOrWhiteSpace($Branch)) { $Branch = "main" }

# Normalize organization to URL
if ($Organization -notmatch '^https?://') {
  $Organization = "https://dev.azure.com/$Organization"
}

Write-Host "`nCreating Azure DevOps Pipeline..." -ForegroundColor Green
Write-Host "Org: $Organization" -ForegroundColor Gray
Write-Host "Project: $ProjectName" -ForegroundColor Gray
Write-Host "Repo: $RepoName" -ForegroundColor Gray
Write-Host "Pipeline: $PipelineName" -ForegroundColor Gray
Write-Host "YAML: $YamlPath" -ForegroundColor Gray
Write-Host "Branch: $Branch" -ForegroundColor Gray

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

# Create pipeline directly (az pipelines create will fail if YAML doesn't exist)
Write-Host "`nCreating pipeline..." -ForegroundColor Gray
$createOutput = az pipelines create `
  --name $PipelineName `
  --repository $RepoName `
  --repository-type tfsgit `
  --branch $Branch `
  --yaml-path $YamlPath `
  --organization $Organization `
  --project $ProjectName `
  --skip-first-run 2>&1

if ($LASTEXITCODE -ne 0) {
  Write-Host "`nPipeline creation failed." -ForegroundColor Red
  Write-Host "Error: $createOutput" -ForegroundColor Yellow
  Write-Host "`nCheck:" -ForegroundColor Red
  Write-Host "  1. YAML file exists at path: $YamlPath in branch: $Branch" -ForegroundColor Yellow
  Write-Host "  2. You have Build Administrator permissions" -ForegroundColor Yellow
  Write-Host "  3. Pipeline name '$PipelineName' doesn't already exist" -ForegroundColor Yellow
  Write-Host "  4. YAML file has valid pipeline syntax" -ForegroundColor Yellow
  Write-Host "`nIf YAML is missing, deploy it first using: deploy_pipeline_yaml tool" -ForegroundColor Gray
  exit 1
}

# Get pipeline details
$pipelineData = $createOutput | ConvertFrom-Json
$pipelineId = $pipelineData.id
$baseUrl = $Organization.TrimEnd('/')

Write-Host "`nPipeline created successfully" -ForegroundColor Green
Write-Host "details:" -ForegroundColor Gray
Write-Host "Pipeline: $PipelineName" -ForegroundColor Cyan
Write-Host "YAML: $YamlPath" -ForegroundColor Cyan
Write-Host "Branch: $Branch" -ForegroundColor Cyan
Write-Host "URL: $baseUrl/$ProjectName/_build?definitionId=$pipelineId" -ForegroundColor Cyan
Write-Host "`nTo run the pipeline:" -ForegroundColor Yellow
Write-Host "  az pipelines run --name `"$PipelineName`" --organization $Organization --project $ProjectName" -ForegroundColor Gray
