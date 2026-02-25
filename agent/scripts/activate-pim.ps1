<#
.SYNOPSIS
    Activates PIM (Privileged Identity Management) roles for the current user.

.DESCRIPTION
    This script activates eligible PIM roles for the current user with the specified
    justification and duration. Supports two modes:
    1. ActivateAll: Activates ALL eligible roles across ALL scopes
    2. Specific: Activates specific roles at specific scopes

.PARAMETER ActivateAll
    When set, activates ALL eligible PIM roles across all scopes.

.PARAMETER Scopes
    Comma-separated list of scopes to activate roles on (required when ActivateAll is not set).
    Example: "/subscriptions/sub-id-1,/subscriptions/sub-id-2/resourceGroups/rg-name"

.PARAMETER RoleNames
    Optional. Comma-separated list of role names to activate.
    If not provided with scopes, activates all eligible roles at those scopes.
    Example: "Contributor,Storage Blob Data Owner"

.PARAMETER Justification
    Business justification for the PIM activation (required).

.PARAMETER DurationHours
    Duration in hours for the activation. 0 = use max allowed per role (default).

.EXAMPLE
    .\activate-pim.ps1 -ActivateAll -Justification "Platform work"

.EXAMPLE
    .\activate-pim.ps1 -ActivateAll -Justification "Platform work" -DurationHours 4

.EXAMPLE
    .\activate-pim.ps1 -Scopes "/subscriptions/xxx" -RoleNames "Contributor" -Justification "Deployment" -DurationHours 2
#>

param(
    [Parameter(Mandatory = $false)]
    [switch]$ActivateAll,
    
    [Parameter(Mandatory = $false)]
    [string]$Scopes = "",
    
    [Parameter(Mandatory = $false)]
    [string]$RoleNames = "",
    
    [Parameter(Mandatory = $true)]
    [string]$Justification,
    
    [Parameter(Mandatory = $false)]
    [int]$DurationHours = 0  # 0 means use max allowed per role
)

$ErrorActionPreference = "Stop"

# Load shared PIM utilities
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\pim-utils.ps1"

# Validate parameters
if (-not $ActivateAll -and -not $Scopes) {
    Write-Error "Either -ActivateAll or -Scopes must be provided"
    exit 1
}

# Parse comma-separated inputs
$scopeList = @()
if ($Scopes) {
    $scopeList = $Scopes -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
}
$roleNameList = @()
if ($RoleNames) {
    $roleNameList = $RoleNames -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Activating PIM Roles" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
if ($ActivateAll) {
    Write-Host "Mode          : Activate ALL eligible roles" -ForegroundColor Magenta
} else {
    Write-Host "Scopes        : $($scopeList -join ', ')" -ForegroundColor Gray
    if ($roleNameList.Count -gt 0) {
        Write-Host "Roles         : $($roleNameList -join ', ')" -ForegroundColor Gray
    } else {
        Write-Host "Roles         : All eligible at specified scopes" -ForegroundColor Gray
    }
}
Write-Host "Justification : $Justification" -ForegroundColor Gray
if ($DurationHours -gt 0) {
    Write-Host "Duration      : $DurationHours hours (requested)" -ForegroundColor Gray
} else {
    Write-Host "Duration      : Max allowed per role (default)" -ForegroundColor Gray
}
Write-Host "==========================================" -ForegroundColor Cyan

# Authenticate using shared utility
Write-Host "`nRetrieving user info and access token..." -ForegroundColor Yellow
try {
    $authContext = Get-PIMAuthContext
    Write-Host "User        : $($authContext.UserName)" -ForegroundColor Gray
    if ($authContext.PrincipalId) {
        Write-Host "Principal ID: $($authContext.PrincipalId)" -ForegroundColor Gray
    }
}
catch {
    Write-Host "Authentication failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Get eligible roles based on mode
Write-Host "`nFetching eligible PIM roles..." -ForegroundColor Yellow
if ($ActivateAll) {
    $eligibleRoles = Get-EligiblePIMRoles -Headers $authContext.Headers -FilterScopes $null -FilterRoleNames $roleNameList
} else {
    $eligibleRoles = Get-EligiblePIMRoles -Headers $authContext.Headers -FilterScopes $scopeList -FilterRoleNames $roleNameList
}

if ($eligibleRoles.Count -eq 0) {
    Write-Host "No eligible PIM roles found matching the criteria." -ForegroundColor Yellow
    $output = @{
        summary = @{ total = 0; successful = 0; skipped = 0; failed = 0 }
        justification = $Justification
        message = "No eligible PIM roles found"
    }
    Write-Host "`nJSON Output:" -ForegroundColor Cyan
    $output | ConvertTo-Json -Depth 5
    exit 0
}

# Remove duplicates (same role+scope)
$eligibleRoles = $eligibleRoles | Sort-Object RoleName, Scope -Unique
Write-Host "Found $($eligibleRoles.Count) unique eligible role(s) to activate" -ForegroundColor Green

# Track results
$results = @()
$successCount = 0
$failCount = 0
$skippedCount = 0

# Activate each role
foreach ($role in $eligibleRoles) {
    $roleName = $role.RoleName
    $roleDefId = $role.RoleDefinitionId
    $scope = $role.Scope
    $rolePrincipalId = if ($authContext.PrincipalId) { $authContext.PrincipalId } else { $role.PrincipalId }
    
    Write-Host "`n------------------------------------------" -ForegroundColor Gray
    Write-Host "Activating: $roleName" -ForegroundColor Yellow
    Write-Host "  Scope: $scope" -ForegroundColor Gray
    
    # Check if already active
    if (Test-RoleAlreadyActive -Headers $authContext.Headers -Scope $scope -RoleDefId $roleDefId) {
        Write-Host "  Already active - SKIPPED" -ForegroundColor Yellow
        $results += [PSCustomObject]@{
            RoleName = $roleName
            Scope = $scope
            Status = "Skipped"
            Message = "Already active"
            Duration = "N/A"
        }
        $skippedCount++
        continue
    }
    
    # Get max allowed duration
    $maxHours = Get-MaxActivationDuration -Headers $authContext.Headers -Scope $scope -RoleDefId $roleDefId -PolicyId $role.PolicyId -EligibilityScheduleId $role.EligibilityScheduleId
    
    # Use max allowed if DurationHours not specified, otherwise cap at max
    if ($DurationHours -le 0) {
        $actualHours = $maxHours
        Write-Host "  Using max duration: $actualHours hours" -ForegroundColor Gray
    } else {
        $actualHours = [Math]::Min($DurationHours, $maxHours)
        if ($actualHours -lt $DurationHours) {
            Write-Host "  Duration capped at $actualHours hours (policy max: $maxHours)" -ForegroundColor Yellow
        }
    }
    
    # Activate role using shared utility
    $activationResult = Invoke-PIMRoleActivation `
        -Headers $authContext.Headers `
        -Scope $scope `
        -RoleDefId $roleDefId `
        -RoleName $roleName `
        -PrincipalId $rolePrincipalId `
        -Justification $Justification `
        -DurationHours $actualHours
    
    switch ($activationResult.Status) {
        "Success" {
            Write-Host "  SUCCESS - Active for $actualHours hours" -ForegroundColor Green
            $successCount++
        }
        "PendingApproval" {
            Write-Host "  PENDING APPROVAL - Request submitted" -ForegroundColor Yellow
            $successCount++
        }
        "Skipped" {
            Write-Host "  Already active - SKIPPED" -ForegroundColor Yellow
            $skippedCount++
        }
        "Failed" {
            Write-Host "  FAILED: $($activationResult.Message)" -ForegroundColor Red
            $failCount++
        }
    }
    
    $results += [PSCustomObject]@{
        RoleName = $roleName
        Scope = $scope
        Status = $activationResult.Status
        Message = $activationResult.Message
        Duration = $activationResult.Duration
    }
}

# Summary
Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "PIM ACTIVATION SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total Roles Processed: $($results.Count)" -ForegroundColor White
Write-Host "  Successful      : $successCount" -ForegroundColor Green
Write-Host "  Skipped (active): $skippedCount" -ForegroundColor Yellow
Write-Host "  Failed          : $failCount" -ForegroundColor Red
Write-Host "==========================================" -ForegroundColor Cyan

# Display results table
Write-Host "`nDetailed Results:" -ForegroundColor Cyan
$results | Format-Table -AutoSize -Property RoleName, @{N='ScopeShort';E={if($_.Scope.Length -gt 50){$_.Scope.Substring(0,47)+"..."}else{$_.Scope}}}, Status, Message

# Output JSON
$output = @{
    summary = @{
        total = $results.Count
        successful = $successCount
        skipped = $skippedCount
        failed = $failCount
    }
    justification = $Justification
    requestedDuration = if ($DurationHours -gt 0) { "PT${DurationHours}H" } else { "Max per role" }
    activations = $results | ForEach-Object {
        @{
            roleName = $_.RoleName
            scope = $_.Scope
            status = $_.Status
            message = $_.Message
            duration = $_.Duration
        }
    }
}

Write-Host "`nJSON Output:" -ForegroundColor Cyan
$output | ConvertTo-Json -Depth 5
