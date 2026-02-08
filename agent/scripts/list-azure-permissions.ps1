# 1. Get the current logged-in user and subscription details
$accountInfo = az account show --output json | ConvertFrom-Json
$upn = $accountInfo.user.name
$subscriptionId = $accountInfo.id
$subscriptionName = $accountInfo.name

# Check if we got a user, otherwise stop
if (-not $upn) {
    Write-Error "No user found. Please run 'az login'."
    exit 1
}

Write-Output "=========================================="
Write-Output "Azure Subscription & User Info"
Write-Output "=========================================="
Write-Output "User: $upn"
Write-Output "Subscription ID: $subscriptionId"
Write-Output "Subscription Name: $subscriptionName"
Write-Output "=========================================="
Write-Output ""
Write-Output "Fetching permissions..."

# 2. List all role assignments for this user in a table format
az role assignment list --assignee $upn --all --output table