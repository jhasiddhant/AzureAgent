param(
    [Parameter(Mandatory = $true)]
    [string]$Scope,
    
    [Parameter(Mandatory = $true)]
    [string]$ObjectIds,
    
    [Parameter(Mandatory = $true)]
    [string]$RoleNames
)

# Parse comma-separated strings into arrays
$ObjectIdList = $ObjectIds -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
$RoleNameList = $RoleNames -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Assigning Azure RBAC Roles" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Scope       : $Scope" -ForegroundColor Yellow
Write-Host "Object IDs  : $($ObjectIdList -join ', ')" -ForegroundColor Yellow
Write-Host "Roles       : $($RoleNameList -join ', ')" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

# Check if Az PowerShell module is available
$azModule = Get-Module -ListAvailable -Name Az.Resources
if (-not $azModule) {
    Write-Host "Az.Resources module not found. Attempting to install..." -ForegroundColor Yellow
    try {
        Install-Module -Name Az.Resources -Scope CurrentUser -Force -AllowClobber
        Import-Module Az.Resources
        Write-Host "Az.Resources module installed successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install Az.Resources module. Please install it manually: Install-Module -Name Az.Resources -Scope CurrentUser"
        exit 1
    }
}

# Try to get current context, connect if needed
$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "No Azure context found. Attempting to connect using Azure CLI credentials..." -ForegroundColor Yellow
    
    # Get subscription from scope
    if ($Scope -match "/subscriptions/([^/]+)") {
        $subscriptionId = $Matches[1]
        try {
            Connect-AzAccount -Subscription $subscriptionId -ErrorAction Stop | Out-Null
            Write-Host "Connected to Azure subscription: $subscriptionId" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to connect to Azure. Please run 'Connect-AzAccount' first or ensure you're logged in with 'az login'."
            exit 1
        }
    }
    else {
        Write-Error "Could not extract subscription ID from scope. Please ensure scope starts with '/subscriptions/<subscription-id>/...'"
        exit 1
    }
}
else {
    Write-Host "Using existing Azure context: $($context.Subscription.Name)" -ForegroundColor Green
}

# Validate scope format
if (-not ($Scope -match "^/subscriptions/")) {
    Write-Error "Invalid scope format. Scope must start with '/subscriptions/<subscription-id>/...'"
    exit 1
}

# Track results
$results = @()
$successCount = 0
$failCount = 0
$skipCount = 0

Write-Host "`nProcessing role assignments..." -ForegroundColor Green
Write-Host "------------------------------------------" -ForegroundColor Gray

foreach ($objectId in $ObjectIdList) {
    foreach ($roleName in $RoleNameList) {
        $assignmentKey = "$objectId -> $roleName"
        Write-Host "`nAssigning: $assignmentKey" -ForegroundColor Cyan
        Write-Host "  Scope: $Scope" -ForegroundColor Gray
        
        try {
            # Check if assignment already exists at EXACT scope (not inherited)
            # Get-AzRoleAssignment with -Scope returns inherited assignments too, so we filter
            $existingAssignment = Get-AzRoleAssignment -ObjectId $objectId `
                                                        -RoleDefinitionName $roleName `
                                                        -Scope $Scope `
                                                        -ErrorAction SilentlyContinue | 
                                  Where-Object { $_.Scope -eq $Scope }
            
            if ($existingAssignment) {
                Write-Host "  Role assignment already exists - Skipped" -ForegroundColor Yellow
                $results += [PSCustomObject]@{
                    ObjectId  = $objectId
                    Role      = $roleName
                    Scope     = $Scope
                    Status    = "Skipped"
                    Message   = "Assignment already exists"
                }
                $skipCount++
                continue
            }
            
            # Create new role assignment
            $assignment = New-AzRoleAssignment -ObjectId $objectId `
                                               -RoleDefinitionName $roleName `
                                               -Scope $Scope `
                                               -ErrorAction Stop
            
            Write-Host "  SUCCESS" -ForegroundColor Green
            $results += [PSCustomObject]@{
                ObjectId     = $objectId
                Role         = $roleName
                Scope        = $Scope
                Status       = "Success"
                AssignmentId = $assignment.RoleAssignmentId
                Message      = "Role assigned successfully"
            }
            $successCount++
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-Host "  FAILED: $errorMsg" -ForegroundColor Red
            $results += [PSCustomObject]@{
                ObjectId = $objectId
                Role     = $roleName
                Scope    = $Scope
                Status   = "Failed"
                Message  = $errorMsg
            }
            $failCount++
        }
    }
}

# Summary
Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host "ROLE ASSIGNMENT SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total Assignments Attempted: $($ObjectIdList.Count * $RoleNameList.Count)" -ForegroundColor White
Write-Host "  Successful : $successCount" -ForegroundColor Green
Write-Host "  Skipped   : $skipCount" -ForegroundColor Yellow
Write-Host "  Failed    : $failCount" -ForegroundColor Red
Write-Host "==========================================" -ForegroundColor Cyan

# Display results table
Write-Host "`nDetailed Results:" -ForegroundColor Cyan
$results | Format-Table -AutoSize -Property ObjectId, Role, Status, Message

# Output JSON for programmatic use
Write-Host "`nJSON Output:" -ForegroundColor Cyan
$output = @{
    summary = @{
        total      = $ObjectIds.Count * $RoleNames.Count
        successful = $successCount
        skipped    = $skipCount
        failed     = $failCount
    }
    scope       = $Scope
    assignments = $results
}
$output | ConvertTo-Json -Depth 5
