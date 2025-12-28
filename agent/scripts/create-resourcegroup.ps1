# Create Azure Resource Group
# Prompts user for required parameters

param(
  [Parameter(Mandatory=$false)] [string]$ResourceGroupName,
  [Parameter(Mandatory=$false)] [string]$Region,
  [Parameter(Mandatory=$false)] [string]$ProjectName
)

if (-not $ResourceGroupName) { $ResourceGroupName = Read-Host "Enter Resource Group Name" }
if (-not $Region) { $Region = Read-Host "Enter Region (e.g. eastus, westcentralus)" }
if (-not $ProjectName) { $ProjectName = Read-Host "Enter Project Name" }

Write-Host "`nCreating Resource Group..." -ForegroundColor Green
Write-Host "Name: $ResourceGroupName" -ForegroundColor Gray
Write-Host "Region: $Region" -ForegroundColor Gray
Write-Host "Project: $ProjectName" -ForegroundColor Gray

# Create the resource group with tags
az group create `
  --name $ResourceGroupName `
  --location $Region `
  --tags "Project=$ProjectName"

if ($LASTEXITCODE -eq 0) { 
  Write-Host "`nResource Group created successfully" -ForegroundColor Green
  Write-Host "Resource Group: $ResourceGroupName" -ForegroundColor Cyan
  Write-Host "Location: $Region" -ForegroundColor Cyan
  Write-Host "Tagged with Project: $ProjectName" -ForegroundColor Cyan
} else { 
  Write-Host "`nResource Group creation failed" -ForegroundColor Red
  exit 1 
}
