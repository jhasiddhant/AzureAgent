# Set the active Azure subscription
# Parameters: -SubscriptionId OR -SubscriptionName

param(
    [string]$SubscriptionId,
    [string]$SubscriptionName
)

$ErrorActionPreference = "Stop"

try {
    if (-not $SubscriptionId -and -not $SubscriptionName) {
        Write-Output '{"error": "Provide either SubscriptionId or SubscriptionName"}'
        exit 0
    }
    
    $identifier = if ($SubscriptionId) { $SubscriptionId } else { $SubscriptionName }
    
    $result = az account set --subscription $identifier 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Output ('{"error": "Failed to set subscription: ' + $result.Replace('"', '\"') + '"}')
        exit 0
    }
    
    # Get the new active subscription to confirm
    $account = az account show --output json 2>&1
    $accountData = $account | ConvertFrom-Json
    
    @{
        success = $true
        message = "Switched to subscription: $($accountData.name)"
        subscription = $accountData.name
        subscriptionId = $accountData.id
        tenantId = $accountData.tenantId
    } | ConvertTo-Json
}
catch {
    Write-Output ('{"error": "' + $_.Exception.Message.Replace('"', '\"') + '"}')
}
