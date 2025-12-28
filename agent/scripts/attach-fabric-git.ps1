param(
    [Parameter(Mandatory = $false)]
    [string]$workspaceId,
    
    [Parameter(Mandatory = $false)]
    [string]$organization,
    
    [Parameter(Mandatory = $false)]
    [string]$projectName,
    
    [Parameter(Mandatory = $false)]
    [string]$repoName,
    
    [Parameter(Mandatory = $false)]
    [string]$branchName,
    
    [Parameter(Mandatory = $false)]
    [string]$directoryName = "/"
)

# Prompt for missing parameters
if (-not $workspaceId) {
    $workspaceId = Read-Host "Enter Fabric Workspace ID"
}

if (-not $organization) {
    $organization = Read-Host "Enter Azure DevOps Organization (name or URL)"
}

if (-not $projectName) {
    $projectName = Read-Host "Enter Azure DevOps Project Name"
}

if (-not $repoName) {
    $repoName = Read-Host "Enter Azure DevOps Repository Name"
}

if (-not $branchName) {
    $branchName = Read-Host "Enter Branch Name (e.g., main)"
}

# Normalize organization URL
if ($organization -notlike "https://*") {
    $organization = "https://dev.azure.com/$organization"
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Attaching Fabric Workspace to Git" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Workspace ID : $workspaceId" -ForegroundColor Yellow
Write-Host "Organization : $organization" -ForegroundColor Yellow
Write-Host "Project      : $projectName" -ForegroundColor Yellow
Write-Host "Repository   : $repoName" -ForegroundColor Yellow
Write-Host "Branch       : $branchName" -ForegroundColor Yellow
Write-Host "Directory    : $directoryName" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

# Get Azure AD token for Fabric API
Write-Host "Getting Azure AD token..." -ForegroundColor Green
$token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv

if (-not $token) {
    Write-Error "Failed to get Azure AD token"
    exit 1
}

# Prepare Git connection request body
$body = @{
    gitProviderDetails = @{
        organizationName = $organization.Split('/')[-1]
        projectName = $projectName
        gitProviderType = "AzureDevOps"
        repositoryName = $repoName
        branchName = $branchName
        directoryName = $directoryName
    }
} | ConvertTo-Json -Depth 10

# Connect workspace to Git using Fabric REST API
Write-Host "Connecting workspace to Git via Fabric API..." -ForegroundColor Green
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

try {
    $response = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/connect" `
        -Method Post `
        -Headers $headers `
        -Body $body

    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Git Connection Successful!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Workspace ID : $workspaceId" -ForegroundColor Cyan
    Write-Host "Repository   : $organization/$projectName/$repoName" -ForegroundColor Cyan
    Write-Host "Branch       : $branchName" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Green
    
    # Return connection details as JSON
    @{
        workspaceId = $workspaceId
        organization = $organization
        project = $projectName
        repository = $repoName
        branch = $branchName
        directory = $directoryName
        status = "connected"
    } | ConvertTo-Json
}
catch {
    Write-Error "Failed to connect workspace to Git: $_"
    Write-Error $_.Exception.Message
    exit 1
}
