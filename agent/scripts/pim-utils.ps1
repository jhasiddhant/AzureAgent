<#
.SYNOPSIS
    Shared PIM utility functions used by list-pim-roles.ps1 and activate-pim.ps1

.DESCRIPTION
    Contains common functions for:
    - Authentication and token retrieval
    - Fetching eligible PIM roles
    - Resolving role definition names
    - Getting max activation duration from policies
#>

# ============================================================================
# AUTHENTICATION FUNCTIONS
# ============================================================================

function Get-PIMAuthContext {
    <#
    .SYNOPSIS
        Gets authentication context for PIM operations
    .OUTPUTS
        PSCustomObject with Headers, UserName, PrincipalId
    #>
    
    # Check Az context
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $context) {
        throw "No Azure context found. Please run 'Connect-AzAccount' first."
    }
    
    # Get user info
    $accountInfo = az account show --query "{userName:user.name, tenantId:tenantId}" -o json 2>$null | ConvertFrom-Json
    if (-not $accountInfo) {
        throw "Failed to get account info. Please run 'az login' first."
    }
    
    # Get ARM token
    $armToken = az account get-access-token --resource "https://management.azure.com" --query accessToken -o tsv
    if (-not $armToken) {
        throw "Failed to get Azure access token"
    }
    
    $headers = @{
        Authorization = "Bearer $armToken"
        'Content-Type' = 'application/json'
    }
    
    # Try to get principal ID via Graph API (optional - some operations don't need it)
    $principalId = $null
    try {
        $graphToken = az account get-access-token --resource "https://graph.microsoft.com" --query accessToken -o tsv 2>$null
        if ($graphToken) {
            $graphHeaders = @{ Authorization = "Bearer $graphToken"; 'Content-Type' = 'application/json' }
            $meResponse = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/me" -Headers $graphHeaders -Method Get -ErrorAction SilentlyContinue
            $principalId = $meResponse.id
        }
    }
    catch { }
    
    return [PSCustomObject]@{
        Headers = $headers
        UserName = $accountInfo.userName
        TenantId = $accountInfo.tenantId
        PrincipalId = $principalId
    }
}

# ============================================================================
# ROLE DEFINITION FUNCTIONS
# ============================================================================

$script:RoleDefCache = @{}
$script:SubNameCache = @{}

function Get-RoleDefinitionName {
    <#
    .SYNOPSIS
        Resolves role definition ID to role name
    .PARAMETER RoleDefId
        Full role definition ID path
    .PARAMETER Headers
        Auth headers for REST API calls
    #>
    param(
        [string]$RoleDefId,
        [hashtable]$Headers
    )
    
    if ($script:RoleDefCache.ContainsKey($RoleDefId)) {
        return $script:RoleDefCache[$RoleDefId]
    }
    
    $roleName = $RoleDefId -split '/' | Select-Object -Last 1
    
    # Try direct lookup
    try {
        $roleDefUrl = "https://management.azure.com$RoleDefId`?api-version=2022-04-01"
        $roleDef = Invoke-RestMethod -Uri $roleDefUrl -Headers $Headers -Method Get -ErrorAction Stop
        if ($roleDef.properties.roleName) {
            $roleName = $roleDef.properties.roleName
        }
    }
    catch {
        # Try built-in roles lookup
        try {
            $roleGuid = $RoleDefId -split '/' | Select-Object -Last 1
            $builtInUrl = "https://management.azure.com/providers/Microsoft.Authorization/roleDefinitions/$roleGuid`?api-version=2022-04-01"
            $builtInDef = Invoke-RestMethod -Uri $builtInUrl -Headers $Headers -Method Get -ErrorAction Stop
            if ($builtInDef.properties.roleName) {
                $roleName = $builtInDef.properties.roleName
            }
        }
        catch { }
    }
    
    $script:RoleDefCache[$RoleDefId] = $roleName
    return $roleName
}

function Get-SubscriptionName {
    <#
    .SYNOPSIS
        Resolves subscription ID to name
    #>
    param([string]$SubscriptionId)
    
    if ($script:SubNameCache.ContainsKey($SubscriptionId)) {
        return $script:SubNameCache[$SubscriptionId]
    }
    
    $subName = $SubscriptionId
    try {
        $subInfo = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction SilentlyContinue
        if ($subInfo) { $subName = $subInfo.Name }
    }
    catch { }
    
    $script:SubNameCache[$SubscriptionId] = $subName
    return $subName
}

# ============================================================================
# ELIGIBLE ROLES FUNCTIONS
# ============================================================================

function Get-EligiblePIMRoles {
    <#
    .SYNOPSIS
        Fetches all eligible PIM roles for current user
    .PARAMETER Headers
        Auth headers for REST API
    .PARAMETER FilterScopes
        Optional array of scopes to filter by
    .PARAMETER FilterRoleNames
        Optional array of role names to filter by
    .PARAMETER IncludeScopeDetails
        If true, parses scope into Subscription/ResourceGroup/Resource components
    #>
    param(
        [hashtable]$Headers,
        [string[]]$FilterScopes = $null,
        [string[]]$FilterRoleNames = $null,
        [switch]$IncludeScopeDetails
    )
    
    $url = "https://management.azure.com/providers/Microsoft.Authorization/roleEligibilityScheduleInstances?api-version=2020-10-01&`$filter=asTarget()"
    
    $response = Invoke-RestMethod -Uri $url -Headers $Headers -Method Get -ErrorAction Stop
    $eligibleRoles = @()
    
    if (-not $response.value -or $response.value.Count -eq 0) {
        return $eligibleRoles
    }
    
    foreach ($item in $response.value) {
        $props = $item.properties
        $roleScope = $props.scope
        $roleDefId = $props.roleDefinitionId
        
        # Apply scope filter
        if ($FilterScopes -and $FilterScopes.Count -gt 0) {
            $matchesScope = $false
            foreach ($filterScope in $FilterScopes) {
                if ($roleScope -eq $filterScope -or $roleScope.StartsWith("$filterScope/")) {
                    $matchesScope = $true
                    break
                }
            }
            if (-not $matchesScope) { continue }
        }
        
        # Get role name
        $roleName = Get-RoleDefinitionName -RoleDefId $roleDefId -Headers $Headers
        
        # Apply role name filter
        if ($FilterRoleNames -and $FilterRoleNames.Count -gt 0) {
            if ($FilterRoleNames -notcontains $roleName) { continue }
        }
        
        # Build role object
        $roleObj = [PSCustomObject]@{
            RoleName = $roleName
            RoleDefinitionId = $roleDefId
            Scope = $roleScope
            EligibilityScheduleId = $props.roleEligibilityScheduleId
            PolicyId = $props.roleManagementPolicyId
            PrincipalId = $props.principalId
            MembershipType = if ($props.memberType -eq "Group") { "Group" } else { "Direct" }
        }
        
        # Add scope details if requested
        if ($IncludeScopeDetails) {
            $scopeLevel = "Unknown"
            $subscriptionName = ""
            $subscriptionId = ""
            $resourceGroupName = ""
            $resourceName = ""
            
            if ($roleScope -match "/subscriptions/([^/]+)") {
                $subscriptionId = $Matches[1]
                $subscriptionName = Get-SubscriptionName -SubscriptionId $subscriptionId
                $scopeLevel = "Subscription"
                
                if ($roleScope -match "/resourceGroups/([^/]+)") {
                    $resourceGroupName = $Matches[1]
                    $scopeLevel = "ResourceGroup"
                    
                    if ($roleScope -match "/providers/([^/]+)/([^/]+)/([^/]+)") {
                        $resourceName = "$($Matches[3]) ($($Matches[2]))"
                        $scopeLevel = "Resource"
                    }
                }
            }
            
            $roleObj | Add-Member -NotePropertyName "ScopeLevel" -NotePropertyValue $scopeLevel
            $roleObj | Add-Member -NotePropertyName "Subscription" -NotePropertyValue $subscriptionName
            $roleObj | Add-Member -NotePropertyName "SubscriptionId" -NotePropertyValue $subscriptionId
            $roleObj | Add-Member -NotePropertyName "ResourceGroup" -NotePropertyValue $resourceGroupName
            $roleObj | Add-Member -NotePropertyName "Resource" -NotePropertyValue $resourceName
        }
        
        $eligibleRoles += $roleObj
    }
    
    return $eligibleRoles
}

# ============================================================================
# POLICY FUNCTIONS
# ============================================================================

function Get-MaxActivationDuration {
    <#
    .SYNOPSIS
        Gets maximum allowed activation duration from PIM policy
    .OUTPUTS
        Integer hours
    #>
    param(
        [hashtable]$Headers,
        [string]$Scope,
        [string]$RoleDefId,
        [string]$PolicyId = $null,
        [string]$EligibilityScheduleId = $null
    )
    
    $maxHours = 8  # Default
    
    # Method 1: Use PolicyId directly if available
    if ($PolicyId) {
        try {
            $policyUrl = "https://management.azure.com$PolicyId`?api-version=2020-10-01"
            $policy = Invoke-RestMethod -Uri $policyUrl -Headers $Headers -Method Get -ErrorAction SilentlyContinue
            
            if ($policy.properties.effectiveRules) {
                foreach ($rule in $policy.properties.effectiveRules) {
                    if ($rule.id -eq "Expiration_EndUser_Assignment" -and $rule.maximumDuration) {
                        $maxDuration = $rule.maximumDuration
                        if ($maxDuration -match "PT(\d+)H") { return [int]$Matches[1] }
                        elseif ($maxDuration -match "PT(\d+)M") { return [math]::Max(1, [math]::Floor([int]$Matches[1] / 60)) }
                        elseif ($maxDuration -match "P(\d+)D") { return [int]$Matches[1] * 24 }
                    }
                }
            }
        }
        catch { }
    }
    
    # Method 2: Query policy assignments at scope
    try {
        $policyUrl = "https://management.azure.com$Scope/providers/Microsoft.Authorization/roleManagementPolicyAssignments?api-version=2020-10-01&`$filter=roleDefinitionId eq '$RoleDefId'"
        $policyAssignments = Invoke-RestMethod -Uri $policyUrl -Headers $Headers -Method Get -ErrorAction SilentlyContinue
        
        if ($policyAssignments.value -and $policyAssignments.value.Count -gt 0) {
            $fetchedPolicyId = $policyAssignments.value[0].properties.policyId
            $policyRulesUrl = "https://management.azure.com$fetchedPolicyId`?api-version=2020-10-01"
            $policy = Invoke-RestMethod -Uri $policyRulesUrl -Headers $Headers -Method Get -ErrorAction SilentlyContinue
            
            if ($policy.properties.effectiveRules) {
                foreach ($rule in $policy.properties.effectiveRules) {
                    if ($rule.id -eq "Expiration_EndUser_Assignment" -and $rule.maximumDuration) {
                        $maxDuration = $rule.maximumDuration
                        if ($maxDuration -match "PT(\d+)H") { return [int]$Matches[1] }
                        elseif ($maxDuration -match "PT(\d+)M") { return [math]::Max(1, [math]::Floor([int]$Matches[1] / 60)) }
                        elseif ($maxDuration -match "P(\d+)D") { return [int]$Matches[1] * 24 }
                    }
                }
            }
        }
    }
    catch { }
    
    return $maxHours
}

# ============================================================================
# ACTIVATION FUNCTIONS
# ============================================================================

function Test-RoleAlreadyActive {
    <#
    .SYNOPSIS
        Checks if a role is already active
    #>
    param(
        [hashtable]$Headers,
        [string]$Scope,
        [string]$RoleDefId
    )
    
    try {
        $activeUrl = "https://management.azure.com$Scope/providers/Microsoft.Authorization/roleAssignmentScheduleInstances?api-version=2020-10-01&`$filter=asTarget()"
        $activeResponse = Invoke-RestMethod -Uri $activeUrl -Headers $Headers -Method Get -ErrorAction SilentlyContinue
        
        if ($activeResponse.value) {
            foreach ($active in $activeResponse.value) {
                if ($active.properties.roleDefinitionId -eq $RoleDefId -and 
                    $active.properties.scope -eq $Scope) {
                    return $true
                }
            }
        }
    }
    catch { }
    
    return $false
}

function Invoke-PIMRoleActivation {
    <#
    .SYNOPSIS
        Activates a single PIM role
    .OUTPUTS
        PSCustomObject with status and message
    #>
    param(
        [hashtable]$Headers,
        [string]$Scope,
        [string]$RoleDefId,
        [string]$RoleName,
        [string]$PrincipalId,
        [string]$Justification,
        [int]$DurationHours
    )
    
    $durationISO = "PT${DurationHours}H"
    
    try {
        $guid = [guid]::NewGuid().ToString()
        $startTime = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
        
        $activationBody = @{
            properties = @{
                principalId = $PrincipalId
                roleDefinitionId = $RoleDefId
                requestType = "SelfActivate"
                justification = $Justification
                scheduleInfo = @{
                    startDateTime = $startTime
                    expiration = @{
                        type = "AfterDuration"
                        duration = $durationISO
                    }
                }
            }
        } | ConvertTo-Json -Depth 10
        
        $activateUrl = "https://management.azure.com$Scope/providers/Microsoft.Authorization/roleAssignmentScheduleRequests/$guid`?api-version=2020-10-01"
        $response = Invoke-RestMethod -Uri $activateUrl -Headers $Headers -Method Put -Body $activationBody -ErrorAction Stop
        
        $status = $response.properties.status
        if ($status -eq "PendingApproval") {
            return [PSCustomObject]@{
                Status = "PendingApproval"
                Message = "Requires approval"
                Duration = $durationISO
                RequestId = $guid
            }
        }
        else {
            return [PSCustomObject]@{
                Status = "Success"
                Message = "Activated for $DurationHours hours"
                Duration = $durationISO
                RequestId = $guid
            }
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        
        if ($errorMsg -match "RoleAssignmentExists|already.*active|ActiveDurationTooShort") {
            return [PSCustomObject]@{
                Status = "Skipped"
                Message = "Already active"
                Duration = $durationISO
            }
        }
        elseif ($errorMsg -match "PendingApproval") {
            return [PSCustomObject]@{
                Status = "PendingApproval"
                Message = "Requires approval"
                Duration = $durationISO
            }
        }
        else {
            return [PSCustomObject]@{
                Status = "Failed"
                Message = $errorMsg
                Duration = $durationISO
            }
        }
    }
}

# Export functions (for dot-sourcing)
Export-ModuleMember -Function @(
    'Get-PIMAuthContext',
    'Get-RoleDefinitionName',
    'Get-SubscriptionName',
    'Get-EligiblePIMRoles',
    'Get-MaxActivationDuration',
    'Test-RoleAlreadyActive',
    'Invoke-PIMRoleActivation'
) -ErrorAction SilentlyContinue
