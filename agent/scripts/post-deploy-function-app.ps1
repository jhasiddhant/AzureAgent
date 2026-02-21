Param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$true)]
    [string]$FunctionAppName,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$PrincipalId
)

Write-Host "Running post-deployment tasks for Function App: $FunctionAppName" -ForegroundColor Cyan

# Create required containers (user needs Storage Blob Data Contributor role)
Write-Host "  1. Creating storage containers..." -ForegroundColor Yellow
az storage container create --name "azure-webjobs-hosts" --account-name $StorageAccountName --auth-mode login --only-show-errors --output none
az storage container create --name "azure-webjobs-secrets" --account-name $StorageAccountName --auth-mode login --only-show-errors --output none
az storage container create --name "deployments" --account-name $StorageAccountName --auth-mode login --only-show-errors --output none
az storage container create --name "scm-releases" --account-name $StorageAccountName --auth-mode login --only-show-errors --output none

Write-Host "✓ Containers created successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "⚠️  IMPORTANT: Role Assignment Required" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
Write-Host "Function App Principal ID: $PrincipalId" -ForegroundColor Cyan
Write-Host ""
Write-Host "An admin with Owner role must run this command:" -ForegroundColor White
Write-Host ""
Write-Host "  az role assignment create \" -ForegroundColor Gray
Write-Host "    --assignee $PrincipalId \" -ForegroundColor Gray
Write-Host "    --role 'Storage Blob Data Owner' \" -ForegroundColor Gray
Write-Host "    --scope /subscriptions/<subscription-id>/resourceGroups/$ResourceGroup/providers/Microsoft.Storage/storageAccounts/$StorageAccountName" -ForegroundColor Gray
Write-Host ""
Write-Host "After role assignment, restart the Function App:" -ForegroundColor White
Write-Host "  az functionapp restart -n $FunctionAppName -g $ResourceGroup" -ForegroundColor Gray
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Yellow
