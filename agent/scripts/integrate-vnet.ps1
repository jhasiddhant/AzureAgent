param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceName,

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory=$true)]
    [ValidateSet("functionapp", "webapp", "keyvault", "storageaccount", "cosmosdb", "openai", "cognitiveservices", "sqlserver", "eventhub", "servicebus", "containerregistry")]
    [string]$ResourceType,

    [Parameter(Mandatory=$true)]
    [string]$SubnetId,

    [Parameter(Mandatory=$false)]
    [string]$VNetName,

    [Parameter(Mandatory=$false)]
    [string]$VNetResourceGroup
)

$ErrorActionPreference = "Stop"

# Extract VNet info from SubnetId if not provided
if (-not $VNetName -or -not $VNetResourceGroup) {
    # SubnetId format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}
    if ($SubnetId -match "/resourceGroups/([^/]+)/providers/Microsoft.Network/virtualNetworks/([^/]+)/subnets/([^/]+)") {
        $VNetResourceGroup = $Matches[1]
        $VNetName = $Matches[2]
        $SubnetName = $Matches[3]
        Write-Host "Extracted VNet info from SubnetId:"
        Write-Host "  VNet Resource Group: $VNetResourceGroup"
        Write-Host "  VNet Name: $VNetName"
        Write-Host "  Subnet Name: $SubnetName"
    } else {
        Write-Error "Could not parse SubnetId. Expected format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}"
        exit 1
    }
}

# Get VNet location for region validation
Write-Host "Getting VNet location..."
$vnetInfo = az network vnet show --name $VNetName --resource-group $VNetResourceGroup --output json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to get VNet info: $vnetInfo"
    exit 1
}
$vnetObj = $vnetInfo | ConvertFrom-Json
$vnetLocation = $vnetObj.location
Write-Host "VNet Location: $vnetLocation"

Write-Host ""
Write-Host "=" * 70
Write-Host "VNET INTEGRATION"
Write-Host "=" * 70
Write-Host ""
Write-Host "Resource:       $ResourceName"
Write-Host "Resource Type:  $ResourceType"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "VNet:           $VNetName ($vnetLocation)"
Write-Host "Subnet:         $SubnetName"
Write-Host ""

# Function to ensure subnet has Microsoft.Web/serverFarms delegation
function Ensure-SubnetDelegation {
    param(
        [string]$VNetRG,
        [string]$VNet,
        [string]$Subnet
    )

    Write-Host "Checking subnet delegation for '$Subnet'..."
    $subnetInfo = az network vnet subnet show `
        --resource-group $VNetRG `
        --vnet-name $VNet `
        --name $Subnet `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to get subnet info: $subnetInfo"
        exit 1
    }

    $subnetObj = $subnetInfo | ConvertFrom-Json
    $hasDelegation = $false

    if ($subnetObj.delegations) {
        foreach ($d in $subnetObj.delegations) {
            if ($d.serviceName -eq "Microsoft.Web/serverFarms") {
                $hasDelegation = $true
                break
            }
        }
    }

    if (-not $hasDelegation) {
        Write-Host "Adding Microsoft.Web/serverFarms delegation to subnet '$Subnet'..."
        $updateResult = az network vnet subnet update `
            --resource-group $VNetRG `
            --vnet-name $VNet `
            --name $Subnet `
            --delegations Microsoft.Web/serverFarms `
            --output json 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to add delegation to subnet: $updateResult"
            exit 1
        }
        Write-Host "Delegation added successfully."
    } else {
        Write-Host "Subnet already has Microsoft.Web/serverFarms delegation."
    }
}

# Function to detect if a Function App uses Flex Consumption plan
function Get-AppPlanSku {
    param(
        [string]$AppName,
        [string]$AppResourceGroup,
        [string]$AppType
    )

    # Get the serverfarm (App Service Plan) ID from the app
    if ($AppType -eq "functionapp") {
        $planId = az functionapp show --name $AppName --resource-group $AppResourceGroup --query "appServicePlanId" -o tsv 2>&1
    } else {
        $planId = az webapp show --name $AppName --resource-group $AppResourceGroup --query "appServicePlanId" -o tsv 2>&1
    }

    if ($LASTEXITCODE -ne 0 -or -not $planId) {
        return @{ Tier = "Unknown"; Name = "Unknown" }
    }

    $planInfo = az resource show --ids $planId --query "sku" -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        return @{ Tier = "Unknown"; Name = "Unknown" }
    }

    $sku = $planInfo | ConvertFrom-Json
    Write-Host "App Service Plan SKU: $($sku.name) (Tier: $($sku.tier))"
    return @{ Tier = $sku.tier; Name = $sku.name }
}

# Function to integrate Function App or Web App with VNet (requires same region)
# Handles all SKU types including Flex Consumption, Consumption, Premium, Standard, etc.
function Integrate-AppServiceVNet {
    param(
        [string]$AppName,
        [string]$AppResourceGroup,
        [string]$AppType,
        [string]$VNet,
        [string]$Subnet,
        [string]$VNetRG,
        [string]$VNetLocation
    )

    Write-Host "Integrating $AppType '$AppName' with VNet..."

    # Check if app exists and get its location
    if ($AppType -eq "functionapp") {
        $app = az functionapp show --name $AppName --resource-group $AppResourceGroup --output json 2>&1
    } else {
        $app = az webapp show --name $AppName --resource-group $AppResourceGroup --output json 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to find $AppType '$AppName': $app"
        exit 1
    }

    $appObj = $app | ConvertFrom-Json
    $appLocation = $appObj.location
    Write-Host "$AppType found: $($appObj.name) (Kind: $($appObj.kind), Location: $appLocation)"

    # REGION VALIDATION: App Service/Function App must be in same region as VNet
    # Normalize location names (remove spaces, lowercase)
    $normalizedAppLocation = $appLocation.ToLower().Replace(" ", "")
    $normalizedVNetLocation = $VNetLocation.ToLower().Replace(" ", "")
    
    if ($normalizedAppLocation -ne $normalizedVNetLocation) {
        Write-Error @"
REGION MISMATCH: Regional VNet Integration requires the $AppType and VNet to be in the SAME region.

  $AppType Location: $appLocation
  VNet Location:     $VNetLocation

Regional VNet Integration only works within the same Azure region.
Options:
  1. Use a VNet in the same region as your $AppType ($appLocation)
  2. Move/recreate the $AppType in the VNet's region ($VNetLocation)
  3. Use Gateway-required VNet Integration for cross-region (requires VPN Gateway)
"@
        exit 1
    }

    # Ensure subnet has Microsoft.Web/serverFarms delegation
    Ensure-SubnetDelegation -VNetRG $VNetRG -VNet $VNet -Subnet $Subnet

    # Detect SKU to decide integration method
    $sku = Get-AppPlanSku -AppName $AppName -AppResourceGroup $AppResourceGroup -AppType $AppType
    $isFlexConsumption = ($sku.Tier -eq "FlexConsumption")
    $isConsumption = ($sku.Tier -eq "Dynamic")

    # Build full subnet resource ID
    $fullSubnetId = "/subscriptions/$((az account show --query id -o tsv))/resourceGroups/$VNetRG/providers/Microsoft.Network/virtualNetworks/$VNet/subnets/$Subnet"

    # Check current VNet integration status
    Write-Host "Checking current VNet integration..."
    if (-not $isFlexConsumption) {
        if ($AppType -eq "functionapp") {
            $vnetConfig = az functionapp vnet-integration list --name $AppName --resource-group $AppResourceGroup --output json 2>&1
        } else {
            $vnetConfig = az webapp vnet-integration list --name $AppName --resource-group $AppResourceGroup --output json 2>&1
        }

        if ($LASTEXITCODE -eq 0 -and $vnetConfig) {
            $vnetConfigObj = $vnetConfig | ConvertFrom-Json
            if ($vnetConfigObj -and $vnetConfigObj.Count -gt 0) {
                Write-Host "WARNING: $AppType already has VNet integration configured:"
                foreach ($config in $vnetConfigObj) {
                    Write-Host "  - VNet: $($config.vnetResourceId)"
                }
                Write-Host "Updating VNet integration..."
            }
        }
    }

    # Add VNet integration using the appropriate method
    Write-Host "Adding VNet integration to $AppType..."

    if ($isFlexConsumption) {
        # Flex Consumption requires setting virtualNetworkSubnetId via az resource update
        Write-Host "Detected Flex Consumption plan - using virtualNetworkSubnetId method..."
        $result = az resource update `
            --ids $appObj.id `
            --set properties.virtualNetworkSubnetId=$fullSubnetId `
            --output json 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to add VNet integration (Flex Consumption): $result"
            exit 1
        }
    } elseif ($isConsumption) {
        # Consumption plan - use az functionapp update with virtualNetworkSubnetId
        Write-Host "Detected Consumption plan - using virtualNetworkSubnetId method..."
        $result = az functionapp update `
            --name $AppName `
            --resource-group $AppResourceGroup `
            --set virtualNetworkSubnetId=$fullSubnetId `
            --output json 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to add VNet integration (Consumption): $result"
            exit 1
        }
    } else {
        # Standard, Premium, Basic, etc. - use vnet-integration add
        if ($AppType -eq "functionapp") {
            $result = az functionapp vnet-integration add `
                --name $AppName `
                --resource-group $AppResourceGroup `
                --vnet $VNet `
                --subnet $Subnet `
                --output json 2>&1
        } else {
            $result = az webapp vnet-integration add `
                --name $AppName `
                --resource-group $AppResourceGroup `
                --vnet $VNet `
                --subnet $Subnet `
                --output json 2>&1
        }
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to add VNet integration: $result"
        exit 1
    }

    Write-Host "Successfully integrated $AppType with VNet!"

    # Verify integration
    if ($isFlexConsumption -or $isConsumption) {
        # For Flex/Consumption, verify via the resource's virtualNetworkSubnetId property
        if ($AppType -eq "functionapp") {
            $verifyApp = az functionapp show --name $AppName --resource-group $AppResourceGroup --query "{virtualNetworkSubnetId:virtualNetworkSubnetId}" -o json 2>&1
        } else {
            $verifyApp = az webapp show --name $AppName --resource-group $AppResourceGroup --query "{virtualNetworkSubnetId:virtualNetworkSubnetId}" -o json 2>&1
        }
        $verifyResult = $verifyApp
    } else {
        if ($AppType -eq "functionapp") {
            $verifyResult = az functionapp vnet-integration list --name $AppName --resource-group $AppResourceGroup --output json 2>&1
        } else {
            $verifyResult = az webapp vnet-integration list --name $AppName --resource-group $AppResourceGroup --output json 2>&1
        }
    }

    return @{
        status = "success"
        resourceType = $AppType
        resourceName = $AppName
        resourceLocation = $appLocation
        vnetName = $VNet
        vnetLocation = $VNetLocation
        subnetName = $Subnet
        skuTier = $sku.Tier
        integration = ($verifyResult | ConvertFrom-Json)
    }
}

# Function to add VNet network rule to Key Vault
function Add-KeyVaultNetworkRule {
    param(
        [string]$VaultName,
        [string]$VaultResourceGroup,
        [string]$SubnetResourceId
    )

    Write-Host "Configuring Key Vault '$VaultName' network rules for VNet access..."

    # Check if Key Vault exists
    $vault = az keyvault show --name $VaultName --resource-group $VaultResourceGroup --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to find Key Vault '$VaultName': $vault"
        exit 1
    }

    $vaultObj = $vault | ConvertFrom-Json
    Write-Host "Key Vault found: $($vaultObj.name)"
    Write-Host "Current network ACL default action: $($vaultObj.properties.networkAcls.defaultAction)"

    # Check current network rules
    $currentRules = $vaultObj.properties.networkAcls.virtualNetworkRules
    if ($currentRules) {
        foreach ($rule in $currentRules) {
            if ($rule.id -eq $SubnetResourceId) {
                Write-Host "Subnet is already in the Key Vault network rules."
                return @{
                    status = "already_configured"
                    resourceType = "keyvault"
                    resourceName = $VaultName
                    subnetId = $SubnetResourceId
                    message = "Subnet is already allowed in Key Vault network rules"
                }
            }
        }
    }

    # Add VNet rule to Key Vault
    Write-Host "Adding VNet rule to Key Vault..."
    $result = az keyvault network-rule add `
        --name $VaultName `
        --resource-group $VaultResourceGroup `
        --subnet $SubnetResourceId `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to add VNet rule to Key Vault: $result"
        exit 1
    }

    # Check if we need to enable network ACLs (set default action to Deny)
    if ($vaultObj.properties.networkAcls.defaultAction -eq "Allow") {
        Write-Host ""
        Write-Host "WARNING: Key Vault default network action is 'Allow' (public access enabled)."
        Write-Host "For VNet integration to be effective, you may want to set default action to 'Deny'."
        Write-Host "Run: az keyvault update --name $VaultName --default-action Deny"
        Write-Host ""
    }

    Write-Host "Successfully added VNet rule to Key Vault!"

    # Verify the rule was added
    $verifyVault = az keyvault show --name $VaultName --resource-group $VaultResourceGroup --output json 2>&1
    $verifyVaultObj = $verifyVault | ConvertFrom-Json

    return @{
        status = "success"
        resourceType = "keyvault"
        resourceName = $VaultName
        subnetId = $SubnetResourceId
        defaultAction = $verifyVaultObj.properties.networkAcls.defaultAction
        virtualNetworkRules = $verifyVaultObj.properties.networkAcls.virtualNetworkRules
    }
}

# Function to add VNet network rule to Storage Account
function Add-StorageAccountNetworkRule {
    param(
        [string]$AccountName,
        [string]$AccountResourceGroup,
        [string]$SubnetResourceId
    )

    Write-Host "Configuring Storage Account '$AccountName' network rules for VNet access..."

    # Check if storage account exists
    $storage = az storage account show --name $AccountName --resource-group $AccountResourceGroup --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to find Storage Account '$AccountName': $storage"
        exit 1
    }

    $storageObj = $storage | ConvertFrom-Json
    Write-Host "Storage Account found: $($storageObj.name)"
    Write-Host "Current default action: $($storageObj.networkRuleSet.defaultAction)"

    # Add VNet rule
    Write-Host "Adding VNet rule to Storage Account..."
    $result = az storage account network-rule add `
        --account-name $AccountName `
        --resource-group $AccountResourceGroup `
        --subnet $SubnetResourceId `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        # Check if already exists
        if ($result -match "already exists") {
            Write-Host "Subnet is already in the Storage Account network rules."
            return @{
                status = "already_configured"
                resourceType = "storageaccount"
                resourceName = $AccountName
                subnetId = $SubnetResourceId
                message = "Subnet is already allowed in Storage Account network rules"
            }
        }
        Write-Error "Failed to add VNet rule to Storage Account: $result"
        exit 1
    }

    if ($storageObj.networkRuleSet.defaultAction -eq "Allow") {
        Write-Host ""
        Write-Host "WARNING: Storage Account default action is 'Allow' (public access enabled)."
        Write-Host "For VNet integration to be effective, set default action to 'Deny':"
        Write-Host "Run: az storage account update --name $AccountName --default-action Deny"
        Write-Host ""
    }

    Write-Host "Successfully added VNet rule to Storage Account!"

    return @{
        status = "success"
        resourceType = "storageaccount"
        resourceName = $AccountName
        subnetId = $SubnetResourceId
    }
}

# Function to add VNet network rule to Cosmos DB
function Add-CosmosDBNetworkRule {
    param(
        [string]$AccountName,
        [string]$AccountResourceGroup,
        [string]$SubnetResourceId
    )

    Write-Host "Configuring Cosmos DB '$AccountName' network rules for VNet access..."

    # Check if Cosmos DB exists
    $cosmos = az cosmosdb show --name $AccountName --resource-group $AccountResourceGroup --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to find Cosmos DB '$AccountName': $cosmos"
        exit 1
    }

    $cosmosObj = $cosmos | ConvertFrom-Json
    Write-Host "Cosmos DB found: $($cosmosObj.name)"

    # Add VNet rule
    Write-Host "Adding VNet rule to Cosmos DB..."
    $result = az cosmosdb network-rule add `
        --name $AccountName `
        --resource-group $AccountResourceGroup `
        --subnet $SubnetResourceId `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        if ($result -match "already exists") {
            Write-Host "Subnet is already in the Cosmos DB network rules."
            return @{
                status = "already_configured"
                resourceType = "cosmosdb"
                resourceName = $AccountName
                subnetId = $SubnetResourceId
                message = "Subnet is already allowed in Cosmos DB network rules"
            }
        }
        Write-Error "Failed to add VNet rule to Cosmos DB: $result"
        exit 1
    }

    Write-Host "Successfully added VNet rule to Cosmos DB!"

    return @{
        status = "success"
        resourceType = "cosmosdb"
        resourceName = $AccountName
        subnetId = $SubnetResourceId
    }
}

# Function to add VNet network rule to Azure OpenAI / Cognitive Services
function Add-CognitiveServicesNetworkRule {
    param(
        [string]$AccountName,
        [string]$AccountResourceGroup,
        [string]$SubnetResourceId
    )

    Write-Host "Configuring Cognitive Services/OpenAI '$AccountName' network rules for VNet access..."

    # Check if resource exists
    $cogServices = az cognitiveservices account show --name $AccountName --resource-group $AccountResourceGroup --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to find Cognitive Services/OpenAI account '$AccountName': $cogServices"
        exit 1
    }

    $cogServicesObj = $cogServices | ConvertFrom-Json
    Write-Host "Cognitive Services found: $($cogServicesObj.name) (Kind: $($cogServicesObj.kind))"

    # Add VNet rule
    Write-Host "Adding VNet rule to Cognitive Services/OpenAI..."
    $result = az cognitiveservices account network-rule add `
        --name $AccountName `
        --resource-group $AccountResourceGroup `
        --subnet $SubnetResourceId `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        if ($result -match "already exists") {
            Write-Host "Subnet is already in the network rules."
            return @{
                status = "already_configured"
                resourceType = "cognitiveservices"
                resourceName = $AccountName
                subnetId = $SubnetResourceId
                message = "Subnet is already allowed in network rules"
            }
        }
        Write-Error "Failed to add VNet rule: $result"
        exit 1
    }

    Write-Host "Successfully added VNet rule to Cognitive Services/OpenAI!"

    return @{
        status = "success"
        resourceType = "cognitiveservices"
        resourceName = $AccountName
        subnetId = $SubnetResourceId
        kind = $cogServicesObj.kind
    }
}

# Function to add VNet rule to SQL Server
function Add-SqlServerNetworkRule {
    param(
        [string]$ServerName,
        [string]$ServerResourceGroup,
        [string]$SubnetResourceId
    )

    Write-Host "Configuring SQL Server '$ServerName' VNet rule..."

    # Check if SQL Server exists
    $sqlServer = az sql server show --name $ServerName --resource-group $ServerResourceGroup --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to find SQL Server '$ServerName': $sqlServer"
        exit 1
    }

    $sqlServerObj = $sqlServer | ConvertFrom-Json
    Write-Host "SQL Server found: $($sqlServerObj.name)"

    # Generate a rule name based on subnet
    $ruleName = "vnet-rule-" + [guid]::NewGuid().ToString().Substring(0, 8)

    # Add VNet rule
    Write-Host "Adding VNet rule '$ruleName' to SQL Server..."
    $result = az sql server vnet-rule create `
        --server $ServerName `
        --resource-group $ServerResourceGroup `
        --name $ruleName `
        --subnet $SubnetResourceId `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to add VNet rule to SQL Server: $result"
        exit 1
    }

    Write-Host "Successfully added VNet rule to SQL Server!"

    return @{
        status = "success"
        resourceType = "sqlserver"
        resourceName = $ServerName
        ruleName = $ruleName
        subnetId = $SubnetResourceId
    }
}

# Function to add VNet rule to Event Hub Namespace
function Add-EventHubNetworkRule {
    param(
        [string]$NamespaceName,
        [string]$NamespaceResourceGroup,
        [string]$SubnetResourceId
    )

    Write-Host "Configuring Event Hub Namespace '$NamespaceName' network rules..."

    # Check if namespace exists
    $namespace = az eventhubs namespace show --name $NamespaceName --resource-group $NamespaceResourceGroup --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to find Event Hub Namespace '$NamespaceName': $namespace"
        exit 1
    }

    $namespaceObj = $namespace | ConvertFrom-Json
    Write-Host "Event Hub Namespace found: $($namespaceObj.name)"

    # Add VNet rule
    Write-Host "Adding VNet rule to Event Hub Namespace..."
    $result = az eventhubs namespace network-rule-set virtual-network-rule add `
        --namespace-name $NamespaceName `
        --resource-group $NamespaceResourceGroup `
        --subnet $SubnetResourceId `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        if ($result -match "already exists") {
            return @{
                status = "already_configured"
                resourceType = "eventhub"
                resourceName = $NamespaceName
                subnetId = $SubnetResourceId
                message = "Subnet is already allowed in Event Hub network rules"
            }
        }
        Write-Error "Failed to add VNet rule to Event Hub: $result"
        exit 1
    }

    Write-Host "Successfully added VNet rule to Event Hub Namespace!"

    return @{
        status = "success"
        resourceType = "eventhub"
        resourceName = $NamespaceName
        subnetId = $SubnetResourceId
    }
}

# Function to add VNet rule to Service Bus Namespace
function Add-ServiceBusNetworkRule {
    param(
        [string]$NamespaceName,
        [string]$NamespaceResourceGroup,
        [string]$SubnetResourceId
    )

    Write-Host "Configuring Service Bus Namespace '$NamespaceName' network rules..."

    # Check if namespace exists
    $namespace = az servicebus namespace show --name $NamespaceName --resource-group $NamespaceResourceGroup --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to find Service Bus Namespace '$NamespaceName': $namespace"
        exit 1
    }

    $namespaceObj = $namespace | ConvertFrom-Json
    Write-Host "Service Bus Namespace found: $($namespaceObj.name)"

    # Add VNet rule
    Write-Host "Adding VNet rule to Service Bus Namespace..."
    $result = az servicebus namespace network-rule-set virtual-network-rule add `
        --namespace-name $NamespaceName `
        --resource-group $NamespaceResourceGroup `
        --subnet $SubnetResourceId `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        if ($result -match "already exists") {
            return @{
                status = "already_configured"
                resourceType = "servicebus"
                resourceName = $NamespaceName
                subnetId = $SubnetResourceId
                message = "Subnet is already allowed in Service Bus network rules"
            }
        }
        Write-Error "Failed to add VNet rule to Service Bus: $result"
        exit 1
    }

    Write-Host "Successfully added VNet rule to Service Bus Namespace!"

    return @{
        status = "success"
        resourceType = "servicebus"
        resourceName = $NamespaceName
        subnetId = $SubnetResourceId
    }
}

# Function to add VNet rule to Container Registry
function Add-ContainerRegistryNetworkRule {
    param(
        [string]$RegistryName,
        [string]$RegistryResourceGroup,
        [string]$SubnetResourceId
    )

    Write-Host "Configuring Container Registry '$RegistryName' network rules..."

    # Check if ACR exists
    $acr = az acr show --name $RegistryName --resource-group $RegistryResourceGroup --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to find Container Registry '$RegistryName': $acr"
        exit 1
    }

    $acrObj = $acr | ConvertFrom-Json
    Write-Host "Container Registry found: $($acrObj.name) (SKU: $($acrObj.sku.name))"

    # Check SKU - network rules require Premium
    if ($acrObj.sku.name -ne "Premium") {
        Write-Error "VNet network rules require Premium SKU. Current SKU: $($acrObj.sku.name)"
        exit 1
    }

    # Add VNet rule
    Write-Host "Adding VNet rule to Container Registry..."
    $result = az acr network-rule add `
        --name $RegistryName `
        --resource-group $RegistryResourceGroup `
        --subnet $SubnetResourceId `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        if ($result -match "already exists") {
            return @{
                status = "already_configured"
                resourceType = "containerregistry"
                resourceName = $RegistryName
                subnetId = $SubnetResourceId
                message = "Subnet is already allowed in Container Registry network rules"
            }
        }
        Write-Error "Failed to add VNet rule to Container Registry: $result"
        exit 1
    }

    Write-Host "Successfully added VNet rule to Container Registry!"

    return @{
        status = "success"
        resourceType = "containerregistry"
        resourceName = $RegistryName
        subnetId = $SubnetResourceId
    }
}

# Main execution
try {
    $output = $null

    switch ($ResourceType) {
        "functionapp" {
            $output = Integrate-AppServiceVNet `
                -AppName $ResourceName `
                -AppResourceGroup $ResourceGroup `
                -AppType "functionapp" `
                -VNet $VNetName `
                -Subnet $SubnetName `
                -VNetRG $VNetResourceGroup `
                -VNetLocation $vnetLocation
        }
        "webapp" {
            $output = Integrate-AppServiceVNet `
                -AppName $ResourceName `
                -AppResourceGroup $ResourceGroup `
                -AppType "webapp" `
                -VNet $VNetName `
                -Subnet $SubnetName `
                -VNetRG $VNetResourceGroup `
                -VNetLocation $vnetLocation
        }
        "keyvault" {
            $output = Add-KeyVaultNetworkRule `
                -VaultName $ResourceName `
                -VaultResourceGroup $ResourceGroup `
                -SubnetResourceId $SubnetId
        }
        "storageaccount" {
            $output = Add-StorageAccountNetworkRule `
                -AccountName $ResourceName `
                -AccountResourceGroup $ResourceGroup `
                -SubnetResourceId $SubnetId
        }
        "cosmosdb" {
            $output = Add-CosmosDBNetworkRule `
                -AccountName $ResourceName `
                -AccountResourceGroup $ResourceGroup `
                -SubnetResourceId $SubnetId
        }
        { $_ -in "openai", "cognitiveservices" } {
            $output = Add-CognitiveServicesNetworkRule `
                -AccountName $ResourceName `
                -AccountResourceGroup $ResourceGroup `
                -SubnetResourceId $SubnetId
        }
        "sqlserver" {
            $output = Add-SqlServerNetworkRule `
                -ServerName $ResourceName `
                -ServerResourceGroup $ResourceGroup `
                -SubnetResourceId $SubnetId
        }
        "eventhub" {
            $output = Add-EventHubNetworkRule `
                -NamespaceName $ResourceName `
                -NamespaceResourceGroup $ResourceGroup `
                -SubnetResourceId $SubnetId
        }
        "servicebus" {
            $output = Add-ServiceBusNetworkRule `
                -NamespaceName $ResourceName `
                -NamespaceResourceGroup $ResourceGroup `
                -SubnetResourceId $SubnetId
        }
        "containerregistry" {
            $output = Add-ContainerRegistryNetworkRule `
                -RegistryName $ResourceName `
                -RegistryResourceGroup $ResourceGroup `
                -SubnetResourceId $SubnetId
        }
    }

    Write-Host ""
    Write-Host "=" * 70
    Write-Host "INTEGRATION COMPLETE"
    Write-Host "=" * 70
    Write-Host ""

    # Output result as JSON
    $output | ConvertTo-Json -Depth 10

} catch {
    Write-Error "VNet integration failed: $_"
    exit 1
}
