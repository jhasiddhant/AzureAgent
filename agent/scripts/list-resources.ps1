<#
.SYNOPSIS
Lists Azure resources. Checks existence/permissions first.
#>
Param(
    # Optional: If provided, lists specific RG. If empty, lists entire subscription.
    [string]$ResourceGroup
)

# 1. Check Subscription Access (Basic Login Check)
$subId = az account show --query id -o tsv 2>$null
if (-not $subId) {
    Write-Error "You are not logged in or have no active subscription. Run 'az login'."
    exit 1
}

# 2. Logic Branch
if (-not [string]::IsNullOrWhiteSpace($ResourceGroup)) {
    # CASE A: Specific Resource Group
    Write-Output "Verifying access to Resource Group: $ResourceGroup..."

    # 'az group exists' is the perfect permission check.
    # It returns 'true' ONLY if it exists AND you have 'Reader' (or higher) access.
    $hasAccess = az group exists --name $ResourceGroup 2>$null

    if ($hasAccess -eq "true") {
        Write-Output "Access confirmed. Listing resources in '$ResourceGroup':"
        # Pipe to Out-String so Python agent sees the table format clearly
        az resource list --resource-group $ResourceGroup --output table | Out-String -Width 4096
    }
    else {
        Write-Error "Resource Group '$ResourceGroup' was not found or you do not have permission to view it."
    }
}
else {
    # CASE B: All Resources
    Write-Output "Verifying Subscription access..."
    Write-Output "Access confirmed. Listing all resources in subscription:"
    
    # Listing at subscription level automatically filters to only show what you have permission to see
    az resource list --output table | Out-String -Width 4096
}