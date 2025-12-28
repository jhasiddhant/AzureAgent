Param(
    [Parameter(Mandatory=$true)] [string]$ResourceGroupName,
    [Parameter(Mandatory=$true)] [string]$ResourceType,
    [Parameter(Mandatory=$false)] [string]$ProviderType
)
$ErrorActionPreference = "Stop"

# Normalize resource type
$ResourceType = $ResourceType.ToLower().Trim()

# Use provider type if specified, otherwise use common mappings
if ([string]::IsNullOrEmpty($ProviderType)) {
    # Default mappings for all supported resource types (matches RESOURCE_TYPE_PROVIDER_MAP in server.py)
    switch ($ResourceType) {
        "nsp" { $ProviderType = "Microsoft.Network/networkSecurityPerimeters" }
        "log-analytics" { $ProviderType = "Microsoft.OperationalInsights/workspaces" }
        "storage-account" { $ProviderType = "Microsoft.Storage/storageAccounts" }
        "key-vault" { $ProviderType = "Microsoft.KeyVault/vaults" }
        "openai" { $ProviderType = "Microsoft.CognitiveServices/accounts" }
        "ai-search" { $ProviderType = "Microsoft.Search/searchServices" }
        "ai-foundry" { $ProviderType = "Microsoft.CognitiveServices/accounts" }
        "ai-services" { $ProviderType = "Microsoft.CognitiveServices/accounts" }
        "ai-hub" { $ProviderType = "Microsoft.MachineLearningServices/workspaces" }
        "ai-project" { $ProviderType = "Microsoft.MachineLearningServices/workspaces" }
        "cosmos-db" { $ProviderType = "Microsoft.DocumentDB/databaseAccounts" }
        "sql-db" { $ProviderType = "Microsoft.Sql/servers" }
        "fabric-capacity" { $ProviderType = "Microsoft.Fabric/capacities" }
        "uami" { $ProviderType = "Microsoft.ManagedIdentity/userAssignedIdentities" }
        "logic-app" { $ProviderType = "Microsoft.Logic/workflows" }
        "function-app" { $ProviderType = "Microsoft.Web/sites" }
        "app-service" { $ProviderType = "Microsoft.Web/sites" }
        "synapse" { $ProviderType = "Microsoft.Synapse/workspaces" }
        "data-factory" { $ProviderType = "Microsoft.DataFactory/factories" }
        "front-door" { $ProviderType = "Microsoft.Network/frontDoors" }
        "virtual-machine" { $ProviderType = "Microsoft.Compute/virtualMachines" }
        "redis-cache" { $ProviderType = "Microsoft.Cache/redis" }
        "redis-enterprise" { $ProviderType = "Microsoft.Cache/redisEnterprise" }
        default {
            Write-Error "Unknown resource type: $ResourceType. Please provide -ProviderType parameter."
            exit 1
        }
    }
}

# Special handling for Log Analytics (uses different CLI command)
if ($ResourceType -eq "log-analytics") {
    $workspaces = az monitor log-analytics workspace list --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    
    if ($workspaces.Count -gt 0) {
        # Priority: Look for standard name "$ResourceGroupName-law"
        $targetWs = $workspaces | Where-Object { $_.name -eq "$ResourceGroupName-law" } | Select-Object -First 1
        
        # If not found, pick the first one
        if (-not $targetWs) {
            $targetWs = $workspaces[0]
        }
        
        Write-Output "RESOURCE FOUND: $($targetWs.name)"
        Write-Output "RESOURCE ID: $($targetWs.id)"
        Write-Output "COUNT: $($workspaces.Count)"
        
        # Output all workspace details if multiple exist
        if ($workspaces.Count -gt 1) {
            Write-Output "MULTIPLE RESOURCES FOUND"
            foreach ($ws in $workspaces) {
                Write-Output "  - Name: $($ws.name), ID: $($ws.id)"
            }
        }
    } else {
        Write-Output "RESOURCE NOT FOUND"
        Write-Output "TYPE: $ResourceType"
    }
} else {
    # Generic resource check using az resource list
    $resources = az resource list --resource-group $ResourceGroupName --resource-type $ProviderType --output json | ConvertFrom-Json
    
    if ($resources.Count -gt 0) {
        Write-Output "RESOURCE FOUND: $($resources[0].name)"
        Write-Output "RESOURCE ID: $($resources[0].id)"
        Write-Output "COUNT: $($resources.Count)"
        
        # Output all resource details if multiple exist
        if ($resources.Count -gt 1) {
            Write-Output "MULTIPLE RESOURCES FOUND"
            foreach ($res in $resources) {
                Write-Output "  - Name: $($res.name), ID: $($res.id)"
            }
        }
    } else {
        Write-Output "RESOURCE NOT FOUND"
        Write-Output "TYPE: $ResourceType"
    }
}
