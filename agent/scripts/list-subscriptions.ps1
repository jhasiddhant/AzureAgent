# List all Azure subscriptions the user has access to
# Returns: JSON array with subscription details

$ErrorActionPreference = "Stop"

try {
    $subscriptions = az account list --output json 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Output '{"error": "Failed to list subscriptions. Run az login to authenticate."}'
        exit 0
    }
    
    $subData = $subscriptions | ConvertFrom-Json
    
    $result = @()
    foreach ($sub in $subData) {
        $result += @{
            name = $sub.name
            id = $sub.id
            state = $sub.state
            isDefault = $sub.isDefault
            tenantId = $sub.tenantId
        }
    }
    
    @{
        subscriptions = $result
        count = $result.Count
    } | ConvertTo-Json -Depth 3
}
catch {
    Write-Output ('{"error": "' + $_.Exception.Message.Replace('"', '\"') + '"}')
}
