param(
    [Parameter(Mandatory = $false)]
    [string]$userPrincipalName
)

# Get current user if not provided
if (-not $userPrincipalName) {
    $userPrincipalName = az account show --query user.name -o tsv
}

if (-not $userPrincipalName) {
    Write-Error "No user found. Please run 'az login'."
    exit 1
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Fabric Workspace Permissions" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "User: $userPrincipalName" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

# Get Azure AD token for Fabric API
Write-Host "Getting Azure AD token..." -ForegroundColor Green
$token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv

if (-not $token) {
    Write-Error "Failed to get Azure AD token"
    exit 1
}

# Prepare headers
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

# Get list of workspaces
Write-Host "Fetching workspaces..." -ForegroundColor Green
try {
    $workspacesResponse = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces" `
        -Method Get `
        -Headers $headers
    
    if (-not $workspacesResponse.value -or $workspacesResponse.value.Count -eq 0) {
        Write-Host "No workspaces found." -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "`nFound $($workspacesResponse.value.Count) workspace(s)`n" -ForegroundColor Green
    
    # Create result array
    $results = @()
    
    foreach ($workspace in $workspacesResponse.value) {
        Write-Host "Checking workspace: $($workspace.displayName)..." -ForegroundColor Gray
        
        $userRole = $null
        $accessMethod = "Direct"
        
        # Get workspace role assignments
        try {
            $roleAssignments = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces/$($workspace.id)/roleAssignments" `
                -Method Get `
                -Headers $headers
            
            # Find current user's direct role assignment
            $directRole = $roleAssignments.value | Where-Object { 
                $_.principal.type -eq "User" -and $_.principal.userDetails.userPrincipalName -eq $userPrincipalName 
            }
            
            if ($directRole) {
                # Direct access - show actual role
                $userRole = $directRole.role
                $accessMethod = "Direct"
            }
            else {
                # No direct role found - check group assignments
                $groupRoles = $roleAssignments.value | Where-Object { 
                    $_.principal.type -eq "Group" 
                }
                
                if ($groupRoles) {
                    # User has access via group(s) - show the highest privilege role
                    $roleHierarchy = @{
                        "Admin" = 4
                        "Contributor" = 3
                        "Member" = 2
                        "Viewer" = 1
                    }
                    
                    $highestRole = $groupRoles | Sort-Object { $roleHierarchy[$_.role] } -Descending | Select-Object -First 1
                    $groupName = $highestRole.principal.displayName
                    $userRole = "$($highestRole.role) (via Group: $groupName)"
                    $accessMethod = "Group"
                }
                else {
                    # Workspace is accessible but no explicit role found
                    $userRole = "Accessed via Group"
                    $accessMethod = "Group"
                }
            }
        }
        catch {
            # If we can't get role assignments, assume group access
            Write-Host "  Unable to retrieve role assignments" -ForegroundColor Yellow
            $userRole = "Accessed via Group"
            $accessMethod = "Unknown"
        }
        
        # Add workspace to results (it's in the list, so user has access)
        $results += [PSCustomObject]@{
            WorkspaceName = $workspace.displayName
            WorkspaceId = $workspace.id
            Role = $userRole
            Type = $workspace.type
            CapacityId = if ($workspace.capacityId) { $workspace.capacityId } else { "N/A" }
        }
    }
    
    if ($results.Count -eq 0) {
        Write-Host "No workspaces found." -ForegroundColor Yellow
    }
    else {
        Write-Host "==========================================" -ForegroundColor Green
        Write-Host "Your Fabric Workspace Permissions" -ForegroundColor Green
        Write-Host "==========================================" -ForegroundColor Green
        $results | Format-Table -Property WorkspaceName, Role, Type, WorkspaceId -AutoSize
        
        # Return as JSON for MCP
        $results | ConvertTo-Json -Depth 10
    }
}
catch {
    Write-Error "Failed to fetch workspaces: $_"
    Write-Error $_.Exception.Message
    exit 1
}
