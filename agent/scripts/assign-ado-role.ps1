<#
.SYNOPSIS
    Assigns a role (security group membership) to a principal in an Azure DevOps project.

.DESCRIPTION
    This script adds a user, group, or service principal to a security group in Azure DevOps.
    Common built-in groups include:
    - Project Administrators
    - Build Administrators
    - Release Administrators
    - Contributors
    - Readers
    - Endpoint Administrators
    - Endpoint Creators
    
    Custom groups are also supported - the script will search for them by name.

.PARAMETER Organization
    The Azure DevOps organization URL (e.g., https://dev.azure.com/myorg)

.PARAMETER ProjectName
    The name of the Azure DevOps project

.PARAMETER RoleName
    The name of the security group/role to assign (e.g., "Project Administrators", "Contributors")

.PARAMETER PrincipalId
    The Object ID (GUID) of the user, group, or service principal from Azure AD/Entra ID

.EXAMPLE
    .\assign-ado-role.ps1 -Organization "https://dev.azure.com/myorg" -ProjectName "MyProject" -RoleName "Contributors" -PrincipalId "12345678-1234-1234-1234-123456789abc"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Organization,

    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter(Mandatory = $true)]
    [string]$RoleName,

    [Parameter(Mandatory = $true)]
    [string]$PrincipalId
)

$ErrorActionPreference = "Stop"

# Normalize organization URL
if (-not $Organization.StartsWith("http")) {
    $Organization = "https://dev.azure.com/$Organization"
}
$Organization = $Organization.TrimEnd('/')

# Extract org name for API calls
$orgName = $Organization -replace "https://dev.azure.com/", ""
$orgName = $orgName -replace "https://", "" -replace "\.visualstudio\.com.*", ""

Write-Host "Azure DevOps Role Assignment" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Organization : $Organization" -ForegroundColor Gray
Write-Host "Project      : $ProjectName" -ForegroundColor Gray
Write-Host "Role         : $RoleName" -ForegroundColor Gray
Write-Host "Principal ID : $PrincipalId" -ForegroundColor Gray
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Get Azure DevOps access token
Write-Host "Getting Azure DevOps access token..." -ForegroundColor Yellow
$adoToken = az account get-access-token --resource 499b84ac-1321-427f-aa17-267ca6975798 --query accessToken -o tsv

if (-not $adoToken) {
    Write-Error "Failed to get Azure DevOps access token. Please run 'az login' first."
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $adoToken"
    "Content-Type"  = "application/json"
}

# Step 1: Get the project ID
Write-Host "Finding project '$ProjectName'..." -ForegroundColor Yellow

try {
    $projectUrl = "$Organization/_apis/projects/$ProjectName`?api-version=7.1"
    $project = Invoke-RestMethod -Uri $projectUrl -Headers $headers -Method Get
    $projectId = $project.id
    Write-Host "Found project ID: $projectId" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "Project Not Found" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "Project '$ProjectName' was not found in organization '$Organization'" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Possible causes:" -ForegroundColor Cyan
    Write-Host "  - Project name is incorrect" -ForegroundColor Gray
    Write-Host "  - You don't have access to the project" -ForegroundColor Gray
    Write-Host "  - Organization URL is incorrect" -ForegroundColor Gray
    exit 1
}

# Step 2: Get the project scope descriptor
Write-Host "Finding security group '$RoleName'..." -ForegroundColor Yellow

$vsspsUrl = "https://vssps.dev.azure.com/$orgName"

# First, get the proper scope descriptor for the project
$descriptorUrl = "$vsspsUrl/_apis/graph/descriptors/$projectId`?api-version=7.1-preview.1"
$scopeDescriptor = $null

try {
    $descriptorResponse = Invoke-RestMethod -Uri $descriptorUrl -Headers $headers -Method Get
    $scopeDescriptor = $descriptorResponse.value
    Write-Host "Found project scope descriptor" -ForegroundColor Green
}
catch {
    Write-Host "Could not get project descriptor, trying alternative method..." -ForegroundColor Yellow
}

$groups = @()

if ($scopeDescriptor) {
    # Use the proper scope descriptor to get groups
    $graphUrl = "$vsspsUrl/_apis/graph/groups?scopeDescriptor=$scopeDescriptor&api-version=7.1-preview.1"
    
    try {
        $groupsResponse = Invoke-RestMethod -Uri $graphUrl -Headers $headers -Method Get
        $groups = $groupsResponse.value
    }
    catch {
        Write-Host "Graph API failed, trying alternative lookup..." -ForegroundColor Yellow
    }
}

# Fallback: Try using the Teams/Security API
if ($groups.Count -eq 0) {
    Write-Host "Trying alternative group lookup..." -ForegroundColor Yellow
    
    # Try getting security groups via the Security namespace
    $securityUrl = "$Organization/_apis/securitynamespaces?api-version=7.1"
    
    # Alternative: Get groups via the project teams/groups endpoint  
    $teamsUrl = "$Organization/_apis/projects/$projectId/teams?api-version=7.1"
    try {
        $teamsResponse = Invoke-RestMethod -Uri $teamsUrl -Headers $headers -Method Get
        # Teams are a subset, also need to get the security groups
    }
    catch {
        # Ignore teams error
    }
    
    # Try identity picker API for groups
    $identityUrl = "$vsspsUrl/_apis/identities?searchFilter=General&filterValue=[$ProjectName]&queryMembership=None&api-version=7.1"
    try {
        $identitiesResponse = Invoke-RestMethod -Uri $identityUrl -Headers $headers -Method Get
        $groups = $identitiesResponse.value | Where-Object { $_.providerDisplayName -like "*$ProjectName*" }
    }
    catch {
        # Last resort: try Graph groups without scope
        $graphUrl = "$vsspsUrl/_apis/graph/groups?api-version=7.1-preview.1"
        try {
            $groupsResponse = Invoke-RestMethod -Uri $graphUrl -Headers $headers -Method Get
            # Filter to project-scoped groups
            $groups = $groupsResponse.value | Where-Object { 
                $_.principalName -like "*$ProjectName*" -or $_.displayName -like "*$ProjectName*"
            }
        }
        catch {
            Write-Error "Failed to retrieve security groups: $_"
            exit 1
        }
    }
}

# Find the matching group
$targetGroup = $null

# Common built-in group name patterns
$commonGroups = @{
    "Project Administrators" = "Project Administrators"
    "Project Administrator"  = "Project Administrators"
    "ProjectAdmin"           = "Project Administrators"
    "Admin"                  = "Project Administrators"
    "Build Administrators"   = "Build Administrators"
    "Build Administrator"    = "Build Administrators"
    "BuildAdmin"             = "Build Administrators"
    "Release Administrators" = "Release Administrators"
    "Release Administrator"  = "Release Administrators"
    "ReleaseAdmin"           = "Release Administrators"
    "Contributors"           = "Contributors"
    "Contributor"            = "Contributors"
    "Readers"                = "Readers"
    "Reader"                 = "Readers"
    "Endpoint Administrators" = "Endpoint Administrators"
    "Endpoint Creators"      = "Endpoint Creators"
}

# Normalize the role name
$normalizedRoleName = $RoleName
if ($commonGroups.ContainsKey($RoleName)) {
    $normalizedRoleName = $commonGroups[$RoleName]
}

# Search for the group
foreach ($group in $groups) {
    $groupName = $group.principalName
    if (-not $groupName) {
        $groupName = $group.displayName
    }
    if (-not $groupName) {
        $groupName = $group.providerDisplayName
    }
    
    # Check for exact match or pattern match
    if ($groupName -like "*\$normalizedRoleName" -or 
        $groupName -eq $normalizedRoleName -or
        $groupName -like "*]$normalizedRoleName" -or
        $groupName -like "[$ProjectName]\$normalizedRoleName") {
        $targetGroup = $group
        break
    }
}

# If not found, try a more flexible search
if (-not $targetGroup) {
    foreach ($group in $groups) {
        $groupName = $group.principalName
        if (-not $groupName) {
            $groupName = $group.displayName
        }
        if (-not $groupName) {
            $groupName = $group.providerDisplayName
        }
        
        if ($groupName -like "*$normalizedRoleName*") {
            $targetGroup = $group
            break
        }
    }
}

if (-not $targetGroup) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "Role Not Found" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "Security group '$RoleName' was not found in project '$ProjectName'" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Available groups in this project:" -ForegroundColor Cyan
    foreach ($group in $groups) {
        $gName = $group.principalName
        if (-not $gName) { $gName = $group.displayName }
        if (-not $gName) { $gName = $group.providerDisplayName }
        if ($gName) {
            # Extract just the group name part
            $shortName = $gName -replace "^\[.*\]\\", ""
            Write-Host "  - $shortName" -ForegroundColor Gray
        }
    }
    Write-Host ""
    Write-Host "Common built-in groups:" -ForegroundColor Cyan
    Write-Host "  - Project Administrators" -ForegroundColor Gray
    Write-Host "  - Build Administrators" -ForegroundColor Gray
    Write-Host "  - Release Administrators" -ForegroundColor Gray
    Write-Host "  - Contributors" -ForegroundColor Gray
    Write-Host "  - Readers" -ForegroundColor Gray
    exit 1
}

$groupDescriptor = $targetGroup.descriptor
$groupName = $targetGroup.principalName
if (-not $groupName) { $groupName = $targetGroup.displayName }
Write-Host "Found group: $groupName" -ForegroundColor Green

# Step 3: Resolve the principal (user/SPN) from Azure AD Object ID
Write-Host "Resolving principal ID '$PrincipalId'..." -ForegroundColor Yellow

# First, try to find if user already exists in Azure DevOps
$userDescriptor = $null

# Try to look up by origin ID (Azure AD Object ID)
$lookupUrl = "$vsspsUrl/_apis/graph/users?api-version=7.1-preview.1"
try {
    $usersResponse = Invoke-RestMethod -Uri $lookupUrl -Headers $headers -Method Get
    $existingUser = $usersResponse.value | Where-Object { $_.originId -eq $PrincipalId }
    
    if ($existingUser) {
        $userDescriptor = $existingUser.descriptor
        Write-Host "Found existing user in Azure DevOps" -ForegroundColor Green
    }
}
catch {
    # User lookup failed, will try to add directly
}

# If user doesn't exist in ADO, we need to add them first
if (-not $userDescriptor) {
    Write-Host "User not found in Azure DevOps, attempting to add from Azure AD..." -ForegroundColor Yellow
    
    # Get the Azure AD storage key for the organization
    $storageKeyUrl = "$vsspsUrl/_apis/graph/storagekeys/Microsoft.IdentityModel.Claims.ClaimsIdentity?api-version=7.1-preview.1"
    
    try {
        # Create user in Azure DevOps from Azure AD
        $createUserUrl = "$vsspsUrl/_apis/graph/users?api-version=7.1-preview.1"
        $createUserBody = @{
            originId = $PrincipalId
            storageKey = $null
        } | ConvertTo-Json
        
        $newUser = Invoke-RestMethod -Uri $createUserUrl -Headers $headers -Method Post -Body $createUserBody
        $userDescriptor = $newUser.descriptor
        Write-Host "Added user to Azure DevOps organization" -ForegroundColor Green
    }
    catch {
        $errorMessage = $_.ErrorDetails.Message
        
        # Try adding as a service principal instead
        Write-Host "Trying to add as service principal..." -ForegroundColor Yellow
        
        try {
            $createSpnUrl = "$vsspsUrl/_apis/graph/serviceprincipals?api-version=7.1-preview.1"
            $createSpnBody = @{
                originId = $PrincipalId
            } | ConvertTo-Json
            
            $newSpn = Invoke-RestMethod -Uri $createSpnUrl -Headers $headers -Method Post -Body $createSpnBody
            $userDescriptor = $newSpn.descriptor
            Write-Host "Added service principal to Azure DevOps organization" -ForegroundColor Green
        }
        catch {
            Write-Host ""
            Write-Host "==========================================" -ForegroundColor Red
            Write-Host "Principal Resolution Failed" -ForegroundColor Red
            Write-Host "==========================================" -ForegroundColor Red
            Write-Host "Could not resolve or add principal '$PrincipalId' to Azure DevOps" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Possible causes:" -ForegroundColor Cyan
            Write-Host "  - Principal ID (Object ID) is incorrect" -ForegroundColor Gray
            Write-Host "  - Principal does not exist in Azure AD" -ForegroundColor Gray
            Write-Host "  - Organization is not connected to Azure AD" -ForegroundColor Gray
            Write-Host "  - Insufficient permissions to add users" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Error: $errorMessage" -ForegroundColor Red
            exit 1
        }
    }
}

# Step 4: Add user to the security group
Write-Host "Adding principal to group '$($targetGroup.displayName)'..." -ForegroundColor Yellow

$membershipUrl = "$vsspsUrl/_apis/graph/memberships/$userDescriptor/$groupDescriptor`?api-version=7.1-preview.1"

try {
    $membershipResult = Invoke-RestMethod -Uri $membershipUrl -Headers $headers -Method Put
    
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Role Assignment Successful" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    
    # Output result details
    $result = [PSCustomObject]@{
        Status       = "Success"
        Organization = $Organization
        Project      = $ProjectName
        Role         = $normalizedRoleName
        PrincipalId  = $PrincipalId
        GroupName    = $groupName
    }
    
    $result | Format-List
    
    # JSON output
    Write-Host "JSON Output:" -ForegroundColor Cyan
    $result | ConvertTo-Json
}
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    $errorMessage = $_.ErrorDetails.Message
    
    # Check if already a member
    if ($errorMessage -like "*already exists*" -or $statusCode -eq 409) {
        Write-Host ""
        Write-Host "==========================================" -ForegroundColor Yellow
        Write-Host "Already a Member" -ForegroundColor Yellow
        Write-Host "==========================================" -ForegroundColor Yellow
        Write-Host "Principal '$PrincipalId' is already a member of '$normalizedRoleName'" -ForegroundColor Yellow
        
        $result = [PSCustomObject]@{
            Status       = "AlreadyMember"
            Organization = $Organization
            Project      = $ProjectName
            Role         = $normalizedRoleName
            PrincipalId  = $PrincipalId
            Message      = "Principal is already a member of this group"
        }
        
        $result | Format-List
        Write-Host "JSON Output:" -ForegroundColor Cyan
        $result | ConvertTo-Json
    }
    else {
        Write-Host ""
        Write-Host "==========================================" -ForegroundColor Red
        Write-Host "Role Assignment Failed" -ForegroundColor Red
        Write-Host "==========================================" -ForegroundColor Red
        Write-Host "Status Code: $statusCode" -ForegroundColor Red
        Write-Host "Error: $errorMessage" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Possible causes:" -ForegroundColor Cyan
        Write-Host "  - Insufficient permissions (need Project Admin or Collection Admin)" -ForegroundColor Gray
        Write-Host "  - Group does not allow external members" -ForegroundColor Gray
        Write-Host "  - API version mismatch" -ForegroundColor Gray
        exit 1
    }
}
