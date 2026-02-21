# Update tags on an Azure resource
# Parameters: -ResourceId, -ResourceName, -ResourceGroup, -ResourceType, -Tags, -Operation

param(
    [string]$ResourceId,
    [string]$ResourceName,
    [string]$ResourceGroup,
    [string]$ResourceType,
    [string]$Tags,          # Format: key1=value1,key2=value2
    [string]$Operation = "merge"  # merge or replace
)

$ErrorActionPreference = "Stop"

# Resource type to provider mapping
$resourceTypeMap = @{
    "storage" = "Microsoft.Storage/storageAccounts"
    "storageaccount" = "Microsoft.Storage/storageAccounts"
    "keyvault" = "Microsoft.KeyVault/vaults"
    "functionapp" = "Microsoft.Web/sites"
    "webapp" = "Microsoft.Web/sites"
    "logicapp" = "Microsoft.Logic/workflows"
    "cosmosdb" = "Microsoft.DocumentDB/databaseAccounts"
    "synapse" = "Microsoft.Synapse/workspaces"
    "datafactory" = "Microsoft.DataFactory/factories"
    "adf" = "Microsoft.DataFactory/factories"
    "openai" = "Microsoft.CognitiveServices/accounts"
    "cognitiveservices" = "Microsoft.CognitiveServices/accounts"
    "aisearch" = "Microsoft.Search/searchServices"
    "search" = "Microsoft.Search/searchServices"
    "containerregistry" = "Microsoft.ContainerRegistry/registries"
    "acr" = "Microsoft.ContainerRegistry/registries"
    "vnet" = "Microsoft.Network/virtualNetworks"
    "virtualnetwork" = "Microsoft.Network/virtualNetworks"
    "nsg" = "Microsoft.Network/networkSecurityGroups"
    "loganalytics" = "Microsoft.OperationalInsights/workspaces"
    "appinsights" = "Microsoft.Insights/components"
}

try {
    # Validate tags
    if (-not $Tags) {
        Write-Output '{"error": "Tags parameter is required in format key1=value1,key2=value2"}'
        exit 0
    }
    
    # Parse tags
    $tagDict = @{}
    foreach ($pair in $Tags.Split(",")) {
        if ($pair -match "=") {
            $parts = $pair.Split("=", 2)
            $tagDict[$parts[0].Trim()] = $parts[1].Trim()
        }
    }
    
    if ($tagDict.Count -eq 0) {
        Write-Output '{"error": "No valid tags found. Use format: key1=value1,key2=value2"}'
        exit 0
    }
    
    # Get resource ID if not provided
    if (-not $ResourceId) {
        if (-not $ResourceName -or -not $ResourceGroup) {
            Write-Output '{"error": "Either ResourceId OR (ResourceName + ResourceGroup) is required"}'
            exit 0
        }
        
        # Try with resource type first
        if ($ResourceType) {
            $provider = $resourceTypeMap[$ResourceType.ToLower()]
            if ($provider) {
                $ResourceId = az resource show -g $ResourceGroup -n $ResourceName --resource-type $provider --query id -o tsv 2>&1
            }
        }
        
        # If still no ID, search by name
        if (-not $ResourceId -or $ResourceId -match "ERROR") {
            $ResourceId = az resource list -g $ResourceGroup --query "[?name=='$ResourceName'].id" -o tsv 2>&1
            if ($ResourceId -is [array]) {
                $ResourceId = $ResourceId | Where-Object { $_ -and $_ -notmatch "ERROR" } | Select-Object -First 1
            }
        }
    }
    
    if (-not $ResourceId -or $ResourceId -match "ERROR") {
        Write-Output ('{"error": "Could not find resource ' + $ResourceName + ' in resource group ' + $ResourceGroup + '"}')
        exit 0
    }
    
    # Build tag arguments
    $tagArgs = @()
    foreach ($key in $tagDict.Keys) {
        $tagArgs += "$key=$($tagDict[$key])"
    }
    
    # Execute tag command
    if ($Operation.ToLower() -eq "replace") {
        $result = az tag create --resource-id $ResourceId --tags $tagArgs 2>&1
    }
    else {
        $result = az tag update --resource-id $ResourceId --operation merge --tags $tagArgs 2>&1
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Output ('{"error": "Failed to update tags: ' + ($result -join " ").Replace('"', '\"') + '"}')
        exit 0
    }
    
    @{
        success = $true
        message = "Tags updated successfully"
        resourceId = $ResourceId
        appliedTags = $tagDict
        operation = $Operation
    } | ConvertTo-Json
}
catch {
    Write-Output ('{"error": "' + $_.Exception.Message.Replace('"', '\"') + '"}')
}
