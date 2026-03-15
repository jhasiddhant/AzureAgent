<#
.SYNOPSIS
    Activates PIM (Privileged Identity Management) roles for the current user.

.DESCRIPTION
    This script activates eligible PIM roles for the current user with the specified
    justification and duration. Supports two modes:
    1. ActivateAll: Activates ALL eligible roles across ALL scopes
    2. Specific: Activates a specific role at a specific scope (using friendly names)

.PARAMETER ActivateAll
    When set, activates ALL eligible PIM roles across all scopes.

.PARAMETER SubscriptionName
    Name of the subscription for specific role activation (e.g., "MCAPSDE_DEV").

.PARAMETER ResourceGroupName
    Optional. Name of the resource group for RG-level scope.

.PARAMETER ResourceName
    Optional. Name of the resource for resource-level scope.

.PARAMETER RoleName
    Name of the role to activate (e.g., "Contributor", "Azure AI User").
    Required when not using ActivateAll.

.PARAMETER Justification
    Business justification for the PIM activation (required).

.PARAMETER DurationHours
    Duration in hours for the activation. 0 = use max allowed per role (default).

.EXAMPLE
    .\activate-pim.ps1 -ActivateAll -Justification "Platform work"

.EXAMPLE
    .\activate-pim.ps1 -SubscriptionName "MCAPSDE_DEV" -RoleName "Contributor" -Justification "Deployment"

.EXAMPLE
    .\activate-pim.ps1 -SubscriptionName "MCAPSDE_DEV" -ResourceGroupName "myRG" -RoleName "Contributor" -Justification "Deployment"
#>

param(
    [Parameter(Mandatory = $false)]
    [switch]$ActivateAll,
    
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionName = "",
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "",
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceName = "",
    
    [Parameter(Mandatory = $false)]
    [string]$RoleName = "",
    
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
if (-not $ActivateAll -and -not $SubscriptionName) {
    Write-Error "Either -ActivateAll or -SubscriptionName must be provided"
    exit 1
}

if (-not $ActivateAll -and -not $RoleName) {
    Write-Error "When not using -ActivateAll, -RoleName must be specified"
    exit 1
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Activating PIM Roles" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
if ($ActivateAll) {
    Write-Host "Mode          : Activate ALL eligible roles" -ForegroundColor Magenta
} else {
    Write-Host "Mode          : Specific role activation" -ForegroundColor Magenta
    Write-Host "Role          : $RoleName" -ForegroundColor Gray
    Write-Host "Subscription  : $SubscriptionName" -ForegroundColor Gray
    if ($ResourceGroupName) {
        Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Gray
    }
    if ($ResourceName) {
        Write-Host "Resource      : $ResourceName" -ForegroundColor Gray
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
    # Mode 1: Activate ALL eligible roles (no filtering)
    $eligibleRoles = Get-EligiblePIMRoles -Headers $authContext.Headers -FilterScopes $null -FilterRoleNames $null
} else {
    # Mode 2: Activate specific role at specific scope
    # First, resolve subscription name to ID
    $subscriptions = az account list --output json 2>$null | ConvertFrom-Json
    $matchingSub = $subscriptions | Where-Object { $_.name -eq $SubscriptionName -or $_.name -like "*$SubscriptionName*" } | Select-Object -First 1
    
    if (-not $matchingSub) {
        Write-Host "Error: Subscription '$SubscriptionName' not found in your account list." -ForegroundColor Red
        Write-Host "Available subscriptions:" -ForegroundColor Yellow
        $subscriptions | ForEach-Object { Write-Host "  - $($_.name)" -ForegroundColor Gray }
        exit 1
    }
    
    $subscriptionId = $matchingSub.id
    Write-Host "Resolved subscription: $($matchingSub.name) ($subscriptionId)" -ForegroundColor Green
    
    # Build scope filter
    $targetScopeBase = "/subscriptions/$subscriptionId"
    if ($ResourceGroupName) {
        $targetScopeBase = "$targetScopeBase/resourceGroups/$ResourceGroupName"
    }
    
    Write-Host "Target scope base: $targetScopeBase" -ForegroundColor Gray
    
    # Get eligible roles filtered by scope prefix and role name
    $eligibleRoles = Get-EligiblePIMRoles -Headers $authContext.Headers -FilterScopes @($targetScopeBase) -FilterRoleNames @($RoleName)
    
    # If ResourceName is specified, further filter to match resource
    if ($ResourceName -and $eligibleRoles.Count -gt 0) {
        $eligibleRoles = $eligibleRoles | Where-Object { $_.Scope -like "*$ResourceName*" }
    }
}

if ($eligibleRoles.Count -eq 0) {
    Write-Host "No eligible PIM roles found matching the criteria." -ForegroundColor Yellow
    $output = @{
        summary = @{ total = 0; successful = 0; skipped = 0; failed = 0 }
        justification = $Justification
        message = "No eligible PIM roles found"
    }
    if (-not $ActivateAll) {
        $output.message = "No eligible role '$RoleName' found at scope '$targetScopeBase'. Check that you have this role assigned in PIM."
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
