# 1. Get the current logged-in user email (UPN)
$upn = az account show --query user.name -o tsv

# Check if we got a user, otherwise stop
if (-not $upn) {
    Write-Error "No user found. Please run 'az login'."
    exit 1
}

Write-Output "User found: $upn"
Write-Output "Fetching permissions..."

# 2. List all role assignments for this user in a table format
az role assignment list --assignee $upn --all --output table