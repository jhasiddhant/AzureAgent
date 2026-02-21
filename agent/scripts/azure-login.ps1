# Login to Azure - handles login and subscription selection
# Scenarios:
# 1. No subscriptions -> uses --allow-no-subscriptions
# 2. One subscription -> sets it as default
# 3. Multiple subscriptions -> returns list for user to choose

param(
    [string]$SelectedSubscriptionId  # Optional: if user already chose a subscription
)

$ErrorActionPreference = "Stop"

try {
    # If a subscription was selected, just set it
    if ($SelectedSubscriptionId) {
        $result = az account set --subscription $SelectedSubscriptionId 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Output ('{"error": "Failed to set subscription: ' + $result + '"}')
            exit 0
        }
        
        $account = az account show --output json 2>&1
        $accountData = $account | ConvertFrom-Json
        
        @{
            success = $true
            action = "subscription_set"
            message = "Switched to subscription: $($accountData.name)"
            user_email = $accountData.user.name
            subscription = $accountData.name
            subscriptionId = $accountData.id
            tenantId = $accountData.tenantId
        } | ConvertTo-Json
        exit 0
    }

    # Logout first
    az logout 2>&1 | Out-Null

    # Login with allow-no-subscriptions flag to handle all cases
    Write-Host "Opening browser for Azure login..." -ForegroundColor Cyan
    $loginResult = az login --allow-no-subscriptions --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Output ('{"error": "Login failed: ' + $loginResult + '"}')
        exit 0
    }

    # Get list of subscriptions
    $subscriptions = az account list --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        $account = az account show --output json 2>&1
        $accountData = $account | ConvertFrom-Json
        
        @{
            success = $true
            action = "logged_in_no_subscriptions"
            message = "Logged in but no subscriptions available. You have tenant-level access only."
            user_email = $accountData.user.name
            tenantId = $accountData.tenantId
        } | ConvertTo-Json
        exit 0
    }

    $subData = $subscriptions | ConvertFrom-Json
    
    # Filter out tenant-level accounts and disabled subscriptions
    $validSubs = @()
    foreach ($sub in $subData) {
        # Skip tenant-level accounts (where subscription id equals tenant id)
        if ($sub.id -eq $sub.tenantId) {
            continue
        }
        # Skip disabled subscriptions
        if ($sub.state -ne "Enabled") {
            continue
        }
        # Skip subscriptions with "N/A" or "tenant level" in name
        if ($sub.name -match "N/A|tenant level") {
            continue
        }
        $validSubs += $sub
    }
    
    $subCount = $validSubs.Count

    if ($subCount -eq 0) {
        # No valid subscriptions
        $account = az account show --output json 2>&1
        $accountData = $account | ConvertFrom-Json
        
        @{
            success = $true
            action = "logged_in_no_subscriptions"
            message = "Logged in but no subscriptions available. You have tenant-level access only."
            user_email = $accountData.user.name
            tenantId = $accountData.tenantId
        } | ConvertTo-Json
    }
    elseif ($subCount -eq 1) {
        # One subscription - set as default
        $sub = $validSubs[0]
        az account set --subscription $sub.id 2>&1 | Out-Null
        
        @{
            success = $true
            action = "single_subscription_set"
            message = "Logged in and set default subscription: $($sub.name)"
            user_email = $sub.user.name
            subscription = $sub.name
            subscriptionId = $sub.id
            tenantId = $sub.tenantId
        } | ConvertTo-Json
    }
    else {
        # Multiple subscriptions - set first as temporary default
        $firstSub = $validSubs[0]
        az account set --subscription $firstSub.id 2>&1 | Out-Null
        
        $subList = @()
        foreach ($sub in $validSubs) {
            $subList += @{
                name = $sub.name
                id = $sub.id
                state = $sub.state
                tenantId = $sub.tenantId
            }
        }
        
        @{
            success = $true
            action = "choose_subscription"
            message = "Logged in. Temporarily set to '$($firstSub.name)'. Please choose a default subscription."
            user_email = $firstSub.user.name
            current_subscription = $firstSub.name
            current_subscriptionId = $firstSub.id
            subscriptions = $subList
            count = $subCount
        } | ConvertTo-Json -Depth 3
    }
}
catch {
    Write-Output ('{"error": "' + $_.Exception.Message.Replace('"', '\"') + '"}')
}