<#
.SYNOPSIS
    Lists eligible PIM (Privileged Identity Management) roles for the current user.

.DESCRIPTION
    This script retrieves ALL eligible PIM role assignments for the current user
    across ALL scopes (subscriptions, resource groups, resources).
    Returns the role name, scope, and maximum allowed activation duration.

.EXAMPLE
    .\list-pim-roles.ps1
    Lists all eligible PIM roles for the current user across all scopes.
#>

$ErrorActionPreference = "Stop"

# Load shared PIM utilities
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\pim-utils.ps1"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Listing PIM Eligible Roles" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Authenticate
try {
    $authContext = Get-PIMAuthContext
    Write-Host "User     : $($authContext.UserName)" -ForegroundColor Gray
    Write-Host "Tenant   : $($authContext.TenantId)" -ForegroundColor Gray
    Write-Host "==========================================" -ForegroundColor Cyan
}
catch {
    Write-Host "Authentication failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Fetch all eligible roles with scope details
Write-Host "`nFetching ALL eligible PIM roles across all scopes..." -ForegroundColor Yellow

try {
    $allEligibleRoles = Get-EligiblePIMRoles -Headers $authContext.Headers -IncludeScopeDetails
    Write-Host "Found $($allEligibleRoles.Count) eligible role assignment(s)" -ForegroundColor Green
}
catch {
    Write-Host "Error fetching PIM roles: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if ($allEligibleRoles.Count -eq 0) {
    Write-Host "`nNo eligible PIM roles found." -ForegroundColor Yellow
    $output = @{
        user = $authContext.UserName
        roles = @()
        message = "No eligible PIM roles found"
    }
    Write-Host "`nJSON Output:" -ForegroundColor Cyan
    $output | ConvertTo-Json -Depth 5
    exit 0
}

# Remove duplicates
$uniqueRoles = $allEligibleRoles | Sort-Object RoleName, Scope -Unique

# Get max durations from policies
Write-Host "Retrieving maximum activation durations..." -ForegroundColor Yellow

$scopePolicies = @{}
foreach ($role in $uniqueRoles) {
    $policyKey = "$($role.Scope)|$($role.RoleDefinitionId)"
    
    if (-not $scopePolicies.ContainsKey($policyKey)) {
        $maxHours = Get-MaxActivationDuration -Headers $authContext.Headers -Scope $role.Scope -RoleDefId $role.RoleDefinitionId -PolicyId $role.PolicyId
        $scopePolicies[$policyKey] = $maxHours
    }
    
    $role | Add-Member -NotePropertyName "MaxHours" -NotePropertyValue $scopePolicies[$policyKey] -Force
}

# Display results
Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "ELIGIBLE PIM ROLES ($($uniqueRoles.Count) roles)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$displayData = $uniqueRoles | Sort-Object Subscription, ResourceGroup, Resource, RoleName | ForEach-Object {
    [PSCustomObject]@{
        Role          = $_.RoleName
        Subscription  = if ($_.Subscription.Length -gt 20) { $_.Subscription.Substring(0,17) + "..." } else { $_.Subscription }
        ResourceGroup = if ($_.ResourceGroup) { $_.ResourceGroup } else { "-" }
        Resource      = if ($_.Resource) { $_.Resource } else { "-" }
        MaxHrs        = $_.MaxHours
    }
}

$displayData | Format-Table -Property Role, Subscription, ResourceGroup, Resource, MaxHrs -AutoSize -Wrap

# Output JSON
$output = @{
    user = $authContext.UserName
    roleCount = $uniqueRoles.Count
    roles = $uniqueRoles | ForEach-Object {
        @{
            roleName = $_.RoleName
            scope = $_.Scope
            scopeLevel = $_.ScopeLevel
            subscription = $_.Subscription
            resourceGroup = $_.ResourceGroup
            resource = $_.Resource
            maxHours = $_.MaxHours
        }
    }
}

Write-Host "`nJSON Output:" -ForegroundColor Cyan
$output | ConvertTo-Json -Depth 5
