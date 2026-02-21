# Get current Azure user information
# Returns: subscription, subscriptionId, tenantId, user_email

$ErrorActionPreference = "Stop"

try {
    $account = az account show --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Output '{"logged_in": false, "error": "Not logged in. Run az login to authenticate."}'
        exit 0
    }
    
    $accountData = $account | ConvertFrom-Json
    
    $result = @{
        logged_in = $true
        user_email = $accountData.user.name
        subscription = $accountData.name
        subscriptionId = $accountData.id
        tenantId = $accountData.tenantId
    }
    
    $result | ConvertTo-Json -Compress
}
catch {
    Write-Output ('{"logged_in": false, "error": "' + $_.Exception.Message.Replace('"', '\"') + '"}')
}
