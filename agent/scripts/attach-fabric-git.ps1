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

# Get Azure AD token for Fabric API
Write-Host "Getting Azure AD token..." -ForegroundColor Green
$token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv

if (-not $token) {
    Write-Error "Failed to get Azure AD token"
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

# Check if workspaceId is a GUID or a name - if not a GUID, look it up
$guidPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
if ($workspaceId -notmatch $guidPattern) {
    Write-Host "Looking up workspace ID for: $workspaceId" -ForegroundColor Yellow
    
    try {
        $workspacesUrl = "https://api.fabric.microsoft.com/v1/workspaces"
        $workspacesResponse = Invoke-RestMethod -Uri $workspacesUrl -Method GET -Headers $headers -TimeoutSec 30
        
        $workspace = $workspacesResponse.value | Where-Object { $_.displayName -eq $workspaceId -or $_.displayName -like "*$workspaceId*" } | Select-Object -First 1
        
        if (-not $workspace) {
            Write-Output ('{"error": "Workspace not found: ' + $workspaceId + '"}')
            exit 0
        }
        
        $workspaceId = $workspace.id
        Write-Host "Found workspace: $($workspace.displayName) (ID: $workspaceId)" -ForegroundColor Green
    } catch {
        Write-Output ('{"error": "Failed to lookup workspace: ' + $_.Exception.Message + '"}')
        exit 0
    }
}

Write-Host "Workspace ID : $workspaceId" -ForegroundColor Yellow
Write-Host "Organization : $organization" -ForegroundColor Yellow
Write-Host "Project      : $projectName" -ForegroundColor Yellow
Write-Host "Repository   : $repoName" -ForegroundColor Yellow
Write-Host "Branch       : $branchName" -ForegroundColor Yellow
Write-Host "Directory    : $directoryName" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

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
    # Extract detailed error information from Fabric API response
    $errorMessage = $_.Exception.Message
    $errorDetails = ""
    
    # Try to extract JSON error from Fabric API if available
    if ($_.ErrorDetails.Message) {
        try {
            $errorJson = $_.ErrorDetails.Message | ConvertFrom-Json
            if ($errorJson.error) {
                $errorDetails = $errorJson.error.message
                if ($errorJson.error.code) {
                    $errorDetails = "[$($errorJson.error.code)] $errorDetails"
                }
            }
        } catch {
            $errorDetails = $_.ErrorDetails.Message
        }
    }
    
    # Display error in same format as success messages
    Write-Host "" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "✗ Git Connection Failed" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "Workspace ID : $workspaceId" -ForegroundColor Yellow
    Write-Host "Repository   : $organization/$projectName/$repoName" -ForegroundColor Yellow
    Write-Host "Branch       : $branchName" -ForegroundColor Yellow
    Write-Host "Directory    : $directoryName" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "ERROR DETAILS:" -ForegroundColor Red
    Write-Host "─────────────────────────────────────────" -ForegroundColor Red
    if ($errorDetails) {
        Write-Host $errorDetails -ForegroundColor Yellow
    } else {
        Write-Host $errorMessage -ForegroundColor Yellow
    }
    Write-Host "" -ForegroundColor Red
    
    # Check if the error is specifically about branch/directory not existing
    # Only try auto-fix if we're certain it's a branch issue
    $isBranchIssue = $errorMessage -match "branch.*not.*found|branch.*doesn't.*exist|branch.*does.*not.*exist" -and 
                     $errorMessage -notmatch "permission|forbidden|unauthorized|access.*denied"
    
    if ($isBranchIssue) {
        Write-Host "SUGGESTED FIX:" -ForegroundColor Cyan
        Write-Host "The branch '$branchName' may not exist in the repository." -ForegroundColor Cyan
        Write-Host "Would you like to create it? (This was previously attempted automatically)" -ForegroundColor Cyan
        Write-Host "" -ForegroundColor Red
        Write-Host "To create the branch manually:" -ForegroundColor Yellow
        Write-Host "  1. Navigate to: $organization/$projectName/_git/$repoName" -ForegroundColor Gray
        Write-Host "  2. Create branch '$branchName'" -ForegroundColor Gray
        Write-Host "  3. Make at least one commit to the branch" -ForegroundColor Gray
        Write-Host "  4. Retry the Fabric Git connection" -ForegroundColor Gray
    } else {
        Write-Host "COMMON CAUSES:" -ForegroundColor Cyan
        Write-Host "  • Not a workspace admin (requires Admin role on workspace)" -ForegroundColor Gray
        Write-Host "  • Workspace already connected to Git (disconnect first)" -ForegroundColor Gray
        Write-Host "  • No access to the DevOps repository" -ForegroundColor Gray
        Write-Host "  • Repository or project doesn't exist" -ForegroundColor Gray
        Write-Host "  • Invalid workspace ID or repository path" -ForegroundColor Gray
        Write-Host "  • Branch exists but has no commits (needs at least one commit)" -ForegroundColor Gray
        Write-Host "" -ForegroundColor Red
        Write-Host "TROUBLESHOOTING:" -ForegroundColor Cyan
        Write-Host "  1. Verify workspace ID: Get-PowerBIWorkspace -Name 'YourWorkspace'" -ForegroundColor Gray
        Write-Host "  2. Check workspace role: Ensure you have 'Admin' role" -ForegroundColor Gray
        Write-Host "  3. Verify repository: Browse to $organization/$projectName/_git/$repoName" -ForegroundColor Gray
        Write-Host "  4. Check branch: Ensure '$branchName' exists with at least one commit" -ForegroundColor Gray
        Write-Host "  5. If Git already connected: Disconnect first in Fabric workspace settings" -ForegroundColor Gray
    }
    Write-Host "==========================================" -ForegroundColor Red
    
    exit 1
}
