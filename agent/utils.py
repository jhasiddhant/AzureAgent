# ============================================================================
# UTILITIES - Shared helpers, constants, and configurations
# ============================================================================

import subprocess
import os
import re
import shutil
import json
from typing import Dict, Tuple, Optional, Any

# ============================================================================
# CONSTANTS - Error Detection
# ============================================================================

# Keywords that indicate deployment/operation failures
ERROR_KEYWORDS = ["Error", "error", "FAILED", "Failed", "failed"]

# Azure-specific error patterns with user-friendly messages and solutions
AZURE_ERROR_PATTERNS = {
    "AuthorizationFailed": {
        "message": "⚠️ AUTHORIZATION ERROR",
        "cause": "You don't have sufficient permissions to perform this action.",
        "solutions": [
            "Run 'az login' to refresh your credentials",
            "Verify you have 'Contributor' or 'Owner' role on the resource group",
            "Check if your token has expired (tokens expire after ~1 hour)",
            "Contact your Azure admin to grant required permissions"
        ]
    },
    "ResourceNotFound": {
        "message": "⚠️ RESOURCE NOT FOUND",
        "cause": "The specified resource does not exist.",
        "solutions": [
            "Verify the resource name and resource group are correct",
            "Check if the resource was deleted or moved",
            "Ensure you're using the correct subscription"
        ]
    },
    "SubscriptionNotFound": {
        "message": "⚠️ SUBSCRIPTION NOT FOUND",
        "cause": "The specified subscription is not accessible.",
        "solutions": [
            "Run 'az account list' to see available subscriptions",
            "Run 'az account set --subscription <id>' to switch subscriptions",
            "Verify you have access to the subscription"
        ]
    },
    "InvalidResourceType": {
        "message": "⚠️ INVALID RESOURCE TYPE",
        "cause": "The resource type specified is not valid.",
        "solutions": [
            "Check the resource type spelling",
            "Verify the API version supports this resource type"
        ]
    },
    "QuotaExceeded": {
        "message": "⚠️ QUOTA EXCEEDED",
        "cause": "You've reached the limit for this resource type in the region.",
        "solutions": [
            "Try a different Azure region",
            "Request a quota increase via Azure portal",
            "Delete unused resources to free up quota"
        ]
    },
    "Conflict": {
        "message": "⚠️ RESOURCE CONFLICT",
        "cause": "A resource with this name already exists or is in a conflicting state.",
        "solutions": [
            "Use a different resource name",
            "Wait for any pending operations to complete",
            "Delete the existing resource if it's no longer needed"
        ]
    },
    "InvalidParameter": {
        "message": "⚠️ INVALID PARAMETER",
        "cause": "One or more parameters are invalid.",
        "solutions": [
            "Review the parameter values for typos",
            "Check parameter constraints (length, allowed values, format)"
        ]
    },
    "PrivateEndpointCannotBeCreatedInSubnet": {
        "message": "⚠️ PRIVATE ENDPOINT SUBNET ERROR",
        "cause": "The subnet cannot host private endpoints.",
        "solutions": [
            "Ensure 'privateEndpointNetworkPolicies' is set to 'Disabled' on the subnet",
            "Use a different subnet designated for private endpoints"
        ]
    }
}

# ============================================================================
# CONFIGURATION CONSTANTS
# ============================================================================

# Resources that should be attached to NSP (suggestion will be provided after creation)
NSP_MANDATORY_RESOURCES = [
    "storage-account",
    "key-vault",
    "cosmos-db",
    "sql-db"
]

# Resources that should have diagnostic settings (suggestion will be provided after creation)
LOG_ANALYTICS_MANDATORY_RESOURCES = [
    "logic-app",
    "function-app",
    "app-service",
    "key-vault",
    "kv",
    "openai",
    "azure-openai",
    "synapse",
    "azure-synapse-analytics",
    "data-factory",
    "azure-data-factory",
    "adf",
    "ai-hub",
    "ai-project",
    "ai-foundry",
    "ai-services",
    "ai-search",
    "front-door",
    "virtual-machine",
    "vm",
    "redis-cache",
    "redis-enterprise",
    "container-registry",
    "acr"
]

# Bicep Templates mapping
TEMPLATE_MAP = {
    "storage-account": "templates/storage-account.bicep",
    "key-vault": "templates/azure-key-vaults.bicep",
    "openai": "templates/azure-openai.bicep",
    "ai-search": "templates/ai-search.bicep",
    "ai-foundry": "templates/ai-foundry.bicep",
    "cosmos-db": "templates/cosmos-db.bicep",
    "log-analytics": "templates/log-analytics.bicep",
    "uami": "templates/user-assigned-managed-identity.bicep",
    "user-assigned-managed-identity": "templates/user-assigned-managed-identity.bicep",
    "nsp": "templates/network-security-perimeter.bicep",
    "network-security-perimeter": "templates/network-security-perimeter.bicep",
    "fabric-capacity": "templates/fabric-capacity.bicep",
    "container-registry": "templates/container-registry.bicep",
    "acr": "templates/container-registry.bicep",
    "function-app": "templates/function-app.bicep",
    "public-ip": "templates/public-ip.bicep",
    "pip": "templates/public-ip.bicep",
    "data-factory": "templates/azure-data-factory.bicep",
    "azure-data-factory": "templates/azure-data-factory.bicep",
    "adf": "templates/azure-data-factory.bicep",
    "synapse": "templates/azure-synapse-analytics.bicep",
    "azure-synapse-analytics": "templates/azure-synapse-analytics.bicep",
    "nsg": "templates/network-security-group.bicep",
    "network-security-group": "templates/network-security-group.bicep",
    "vnet": "templates/virtual-network.bicep",
    "virtual-network": "templates/virtual-network.bicep",
    "subnet": "templates/subnet.bicep",
    "private-endpoint": "templates/private-endpoint.bicep",
    "pe": "templates/private-endpoint.bicep",
    "logic-app": "templates/logic-app.bicep",
}

# Resource Type to Azure Provider mapping
RESOURCE_TYPE_PROVIDER_MAP = {
    "nsp": "Microsoft.Network/networkSecurityPerimeters",
    "network-security-perimeter": "Microsoft.Network/networkSecurityPerimeters",
    "log-analytics": "Microsoft.OperationalInsights/workspaces",
    "law": "Microsoft.OperationalInsights/workspaces",
    "storage-account": "Microsoft.Storage/storageAccounts",
    "storage": "Microsoft.Storage/storageAccounts",
    "key-vault": "Microsoft.KeyVault/vaults",
    "kv": "Microsoft.KeyVault/vaults",
    "openai": "Microsoft.CognitiveServices/accounts",
    "azure-openai": "Microsoft.CognitiveServices/accounts",
    "ai-search": "Microsoft.Search/searchServices",
    "ai-foundry": "Microsoft.CognitiveServices/accounts",
    "ai-services": "Microsoft.CognitiveServices/accounts",
    "ai-hub": "Microsoft.MachineLearningServices/workspaces",
    "ai-project": "Microsoft.MachineLearningServices/workspaces",
    "cosmos-db": "Microsoft.DocumentDB/databaseAccounts",
    "cosmosdb": "Microsoft.DocumentDB/databaseAccounts",
    "fabric-capacity": "Microsoft.Fabric/capacities",
    "fabric": "Microsoft.Fabric/capacities",
    "uami": "Microsoft.ManagedIdentity/userAssignedIdentities",
    "user-assigned-managed-identity": "Microsoft.ManagedIdentity/userAssignedIdentities",
    "container-registry": "Microsoft.ContainerRegistry/registries",
    "acr": "Microsoft.ContainerRegistry/registries",
    "logic-app": "Microsoft.Logic/workflows",
    "function-app": "Microsoft.Web/sites",
    "app-service": "Microsoft.Web/sites",
    "synapse": "Microsoft.Synapse/workspaces",
    "azure-synapse-analytics": "Microsoft.Synapse/workspaces",
    "data-factory": "Microsoft.DataFactory/factories",
    "azure-data-factory": "Microsoft.DataFactory/factories",
    "adf": "Microsoft.DataFactory/factories",
    "public-ip": "Microsoft.Network/publicIPAddresses",
    "pip": "Microsoft.Network/publicIPAddresses",
    "front-door": "Microsoft.Network/frontDoors",
    "nsg": "Microsoft.Network/networkSecurityGroups",
    "network-security-group": "Microsoft.Network/networkSecurityGroups",
    "vnet": "Microsoft.Network/virtualNetworks",
    "virtual-network": "Microsoft.Network/virtualNetworks",
    "subnet": "Microsoft.Network/virtualNetworks/subnets",
    "private-endpoint": "Microsoft.Network/privateEndpoints",
    "pe": "Microsoft.Network/privateEndpoints",
    "virtual-machine": "Microsoft.Compute/virtualMachines",
    "vm": "Microsoft.Compute/virtualMachines",
    "redis-cache": "Microsoft.Cache/redis",
    "redis-enterprise": "Microsoft.Cache/redisEnterprise",
}

# Pipeline YAML Templates
PIPELINE_TEMPLATE_MAP = {
    "credscan": "templates/credscan_Pipeline.yml",
    "credscan-1es": "templates/credscan_1ES_Pipeline.yml",
}

# Pipeline type keywords for auto-detection
PIPELINE_TYPE_KEYWORDS = {
    "1es": "credscan-1es",
    "prod": "credscan-1es",
    "production": "credscan-1es",
    "credscan": "credscan",
}

# Operational Scripts
OP_SCRIPTS = {
    "permissions": "list-azure-permissions.ps1",
    "resources": "list-resources.ps1",
    "create-rg": "create-resourcegroup.ps1",
    "deploy-bicep": "deploy-bicep.ps1",
    "post-deploy-function-app": "post-deploy-function-app.ps1"
}

# ============================================================================
# HELPER FUNCTIONS - Command Execution
# ============================================================================

def _detect_azure_error(output: str) -> Optional[str]:
    """
    Detects known Azure error patterns and returns a formatted error message with solutions.
    Returns None if no known error pattern is detected.
    """
    for error_code, error_info in AZURE_ERROR_PATTERNS.items():
        if error_code in output:
            solutions_text = "\n".join(f"  • {s}" for s in error_info["solutions"])
            return f"""
╔══════════════════════════════════════════════════════════════════════════════╗
║ {error_info['message']}
╠══════════════════════════════════════════════════════════════════════════════╣
║ Cause: {error_info['cause']}
║
║ Solutions:
{solutions_text}
╚══════════════════════════════════════════════════════════════════════════════╝
"""
    return None


def run_command(command: list[str]) -> str:
    """Generic command runner with enhanced error reporting."""
    try:
        result = subprocess.run(
            command,
            shell=False, 
            capture_output=True,
            text=True,
            encoding='utf-8',
            check=False,
            stdin=subprocess.DEVNULL,
            timeout=600
        )
        
        full_output = f"{result.stdout or ''}\n{result.stderr or ''}"
        azure_error = _detect_azure_error(full_output)
        output_parts = []
        
        if result.stdout and result.stdout.strip():
            output_parts.append(result.stdout.strip())
        
        if result.stderr and result.stderr.strip():
            stderr_lines = result.stderr.strip()
            if result.returncode != 0 or any(err_word in stderr_lines.lower() for err_word in ['error', 'failed', 'exception', 'cannot', 'unauthorized', 'forbidden', 'not found']):
                output_parts.append(f"\n═══════════════════════════════════════════════════════════\n✗ ERROR DETAILS:\n═══════════════════════════════════════════════════════════\n{stderr_lines}")
            else:
                output_parts.append(stderr_lines)
        
        if azure_error:
            output_parts.append(azure_error)
        
        if result.returncode != 0:
            output_parts.append(f"\n[Exit Code: {result.returncode}]")
        
        return "\n".join(output_parts) if output_parts else "Command completed with no output"
        
    except subprocess.TimeoutExpired:
        return f"✗ ERROR: Command timed out after 600 seconds\n\nCommand: {' '.join(command)}\n\nThis usually indicates a hanging process or very slow operation."
    except Exception as e:
        return f"✗ EXECUTION ERROR:\n\nCommand: {' '.join(command)}\n\nError: {str(e)}\nError Type: {type(e).__name__}"


def run_powershell_script(script_path: str, parameters: dict) -> str:
    """Execute PowerShell script with enhanced error reporting."""
    ps_executable = "pwsh" if shutil.which("pwsh") else "powershell"
    cmd = [ps_executable, "-ExecutionPolicy", "Bypass", "-File", script_path]
    for k, v in parameters.items():
        if v is not None and v != "":
            cmd.append(f"-{k}")
            cmd.append(str(v))
    
    result = run_command(cmd)
    
    if any(pattern in result for pattern in ['Write-Error', 'TerminatingError', 'Exception', 'At line:']):
        return result
    
    return result


# ============================================================================
# HELPER FUNCTIONS - File System
# ============================================================================

def get_script_path(script_name: str) -> str:
    """Locates the script in the 'scripts' folder."""
    current_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(current_dir, "scripts", script_name)


def get_template_path(template_rel: str) -> str:
    """Locates the bicep file relative to server file."""
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), template_rel)


def detect_pipeline_type(pipeline_name: str, user_input: str = "") -> str:
    """
    Detects pipeline type based on pipeline name and user input.
    Returns the template key from PIPELINE_TEMPLATE_MAP.
    """
    combined = f"{pipeline_name} {user_input}".lower()
    
    for keyword, pipeline_type in PIPELINE_TYPE_KEYWORDS.items():
        if keyword in combined and pipeline_type in PIPELINE_TEMPLATE_MAP:
            return pipeline_type
    
    normalized_name = pipeline_name.lower().replace('_', '-').replace(' ', '-')
    if normalized_name in PIPELINE_TEMPLATE_MAP:
        return normalized_name
    
    for template_key in PIPELINE_TEMPLATE_MAP.keys():
        if template_key in normalized_name or normalized_name in template_key:
            return template_key
    
    return "credscan"


def get_pipeline_template(pipeline_type: str) -> Optional[str]:
    """
    Gets the pipeline template path for a given pipeline type.
    Falls back to credscan if requested type doesn't exist.
    """
    if pipeline_type in PIPELINE_TEMPLATE_MAP:
        template_rel = PIPELINE_TEMPLATE_MAP[pipeline_type]
        template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), template_rel)
        if os.path.exists(template_path):
            return template_path
    
    normalized_type = pipeline_type.lower().replace('_', '-').replace(' ', '-')
    if normalized_type in PIPELINE_TEMPLATE_MAP:
        template_rel = PIPELINE_TEMPLATE_MAP[normalized_type]
        template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), template_rel)
        if os.path.exists(template_path):
            return template_path
    
    if "credscan" in PIPELINE_TEMPLATE_MAP:
        template_rel = PIPELINE_TEMPLATE_MAP["credscan"]
        template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), template_rel)
        if os.path.exists(template_path):
            return template_path
    
    for template_rel in PIPELINE_TEMPLATE_MAP.values():
        template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), template_rel)
        if os.path.exists(template_path):
            return template_path
    
    return None


# ============================================================================
# HELPER FUNCTIONS - Azure Resources
# ============================================================================

def get_rg_location(resource_group: str) -> str:
    """Fetches location of the resource group."""
    try:
        res = run_command(["az", "group", "show", "-n", resource_group, "--query", "location", "-o", "tsv"])
        return res.strip()
    except:
        return "eastus"


def get_vnet_subnets(resource_group: str, vnet_name: str) -> list[dict]:
    """Gets existing subnets in a VNet with their address prefixes."""
    try:
        cmd = f'az network vnet subnet list -g "{resource_group}" --vnet-name "{vnet_name}" --query "[].{{name:name, addressPrefix:addressPrefix}}" -o json'
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=60
        )
        
        if result.returncode == 0 and result.stdout.strip():
            return json.loads(result.stdout.strip())
        return []
    except Exception as e:
        print(f"[WARN] Failed to get VNet subnets: {e}")
        return []


def calculate_next_subnet_address(resource_group: str, vnet_name: str, subnet_size: int = 27) -> Optional[str]:
    """Calculates the next available subnet starting address based on existing subnets."""
    try:
        cmd = f'az network vnet show -g "{resource_group}" -n "{vnet_name}" --query "addressSpace.addressPrefixes[0]" -o tsv'
        result = subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=60
        )
        
        if result.returncode != 0 or not result.stdout.strip():
            print(f"[WARN] Failed to get VNet address space: {result.stderr}")
            return None
        
        vnet_cidr = result.stdout.strip()
        vnet_base_ip = vnet_cidr.split('/')[0]
        vnet_prefix = int(vnet_cidr.split('/')[1])
        
        base_octets = [int(x) for x in vnet_base_ip.split('.')]
        base_int = (base_octets[0] << 24) + (base_octets[1] << 16) + (base_octets[2] << 8) + base_octets[3]
        
        vnet_size = 2 ** (32 - vnet_prefix)
        vnet_end = base_int + vnet_size
        
        subnets = get_vnet_subnets(resource_group, vnet_name)
        new_subnet_size = 2 ** (32 - subnet_size)
        
        used_ranges = []
        for subnet in subnets:
            prefix = subnet.get('addressPrefix', '')
            if '/' in prefix:
                subnet_ip = prefix.split('/')[0]
                subnet_cidr = int(prefix.split('/')[1])
                subnet_octets = [int(x) for x in subnet_ip.split('.')]
                subnet_start = (subnet_octets[0] << 24) + (subnet_octets[1] << 16) + (subnet_octets[2] << 8) + subnet_octets[3]
                subnet_range = 2 ** (32 - subnet_cidr)
                used_ranges.append((subnet_start, subnet_start + subnet_range))
        
        used_ranges.sort(key=lambda x: x[0])
        candidate = base_int
        
        for start, end in used_ranges:
            if candidate + new_subnet_size <= start:
                break
            if candidate < end:
                candidate = end
        
        if candidate + new_subnet_size > vnet_end:
            print(f"[WARN] No available space in VNet. Candidate={candidate}, VNet end={vnet_end}")
            return None
        
        next_addr = f"{(candidate >> 24) & 255}.{(candidate >> 16) & 255}.{(candidate >> 8) & 255}.{candidate & 255}"
        print(f"[INFO] Calculated next subnet address: {next_addr}")
        return next_addr
        
    except Exception as e:
        print(f"[WARN] Failed to calculate next subnet address: {e}")
        return None


def get_fabric_tenant_region() -> Optional[str]:
    """Gets the Fabric/Power BI tenant home region by querying existing capacities."""
    try:
        result = run_command([
            "az", "account", "get-access-token", 
            "--resource", "https://analysis.windows.net/powerbi/api", 
            "--query", "accessToken", "-o", "tsv"
        ])
        token = result.strip()
        
        if not token or "ERROR" in token:
            return None
        
        import urllib.request
        
        req = urllib.request.Request(
            "https://api.powerbi.com/v1.0/myorg/capacities",
            headers={"Authorization": f"Bearer {token}"}
        )
        
        with urllib.request.urlopen(req, timeout=30) as response:
            data = json.loads(response.read().decode())
            
        if data.get("value") and len(data["value"]) > 0:
            return data["value"][0].get("region")
        
        return None
    except Exception:
        return None


def get_resource_id(resource_group: str, resource_type: str, parameters: Dict[str, str]) -> Optional[str]:
    """Attempts to find the Resource ID based on parameters provided during creation."""
    name_keys = [
        "name", "accountName", "keyVaultName", "serverName", "databaseName", "storageAccountName",
        "workspaceName", "searchServiceName", "serviceName", "vmName", "virtualMachineName",
        "siteName", "functionAppName", "appServiceName", "logicAppName", "workflowName",
        "factoryName", "cacheName", "frontDoorName", "clusterName"
    ]
    
    resource_name = None
    for key in name_keys:
        if key in parameters:
            resource_name = parameters[key]
            break
            
    if not resource_name:
        return None

    provider = RESOURCE_TYPE_PROVIDER_MAP.get(resource_type)
    if not provider:
        return None

    try:
        cmd = [
            "az", "resource", "show", 
            "-g", resource_group, 
            "-n", resource_name, 
            "--resource-type", provider, 
            "--query", "id", "-o", "tsv"
        ]
        return run_command(cmd).strip()
    except:
        return None


def format_deployment_details(resource_type: str, resource_group: str, parameters: Dict[str, str]) -> str:
    """Format deployment details in a user-friendly way based on resource type."""
    details = []
    details.append("═" * 70)
    details.append("✅ DEPLOYMENT SUCCESSFUL")
    details.append("═" * 70)
    details.append("")
    details.append("📦 Deployment Details:")
    details.append("")
    
    location = parameters.get("location", "N/A")
    
    if resource_type == "storage-account":
        storage_name = parameters.get("storageAccountName", "N/A")
        access_tier = parameters.get("accessTier", "N/A")
        hns_enabled = parameters.get("enableHierarchicalNamespace", "true")
        
        details.append(f"   Storage Account: {storage_name}")
        details.append(f"   Location: {location}")
        details.append(f"   Access Tier: {access_tier}")
        details.append(f"   ADLS Gen2: {'Enabled' if hns_enabled.lower() == 'true' else 'Disabled'}")
        details.append(f"   Blob Endpoint: https://{storage_name}.blob.core.windows.net/")
        details.append(f"   DFS Endpoint: https://{storage_name}.dfs.core.windows.net/")
    
    elif resource_type == "key-vault":
        vault_name = parameters.get("keyVaultName", "N/A")
        details.append(f"   Key Vault: {vault_name}")
        details.append(f"   Location: {location}")
        details.append(f"   Vault URI: https://{vault_name}.vault.azure.net/")
    
    elif resource_type == "cosmos-db":
        account_name = parameters.get("cosmosAccountName", "N/A")
        details.append(f"   Cosmos DB Account: {account_name}")
        details.append(f"   Location: {location}")
    
    elif resource_type == "openai":
        openai_name = parameters.get("openAIServiceName", "N/A")
        details.append(f"   Azure OpenAI: {openai_name}")
        details.append(f"   Location: {location}")
        details.append(f"   Endpoint: https://{openai_name}.openai.azure.com/")
    
    elif resource_type == "ai-search":
        search_name = parameters.get("searchServiceName", "N/A")
        sku = parameters.get("sku", "standard")
        details.append(f"   AI Search Service: {search_name}")
        details.append(f"   Location: {location}")
        details.append(f"   SKU: {sku}")
        details.append(f"   Endpoint: https://{search_name}.search.windows.net/")
    
    elif resource_type == "log-analytics":
        workspace_name = parameters.get("workspaceName", "N/A")
        details.append(f"   Log Analytics Workspace: {workspace_name}")
        details.append(f"   Location: {location}")
    
    elif resource_type == "container-registry":
        registry_name = parameters.get("registryName", "N/A")
        sku = parameters.get("sku", "N/A")
        details.append(f"   Container Registry: {registry_name}")
        details.append(f"   Location: {location}")
        details.append(f"   SKU: {sku}")
        details.append(f"   Login Server: {registry_name}.azurecr.io")
    
    elif resource_type == "function-app":
        function_name = parameters.get("functionAppName", "N/A")
        hosting_plan = parameters.get("hostingPlanType", "N/A")
        runtime = parameters.get("runtimeStack", "N/A")
        details.append(f"   Function App: {function_name}")
        details.append(f"   Location: {location}")
        details.append(f"   Hosting Plan: {hosting_plan}")
        details.append(f"   Runtime: {runtime}")
        details.append(f"   URL: https://{function_name}.azurewebsites.net")
        details.append("")
        details.append("Storage containers created automatically")
        details.append("")
        details.append("   ⚠️ ADMIN ACTION REQUIRED:")
        details.append("   An admin with Owner role must assign 'Storage Blob Data Owner'")
        details.append("   to the Function App's managed identity, then restart the app.")
    
    elif resource_type in ["azure-synapse-analytics", "synapse"]:
        synapse_name = parameters.get("synapseName", "N/A")
        storage_name = parameters.get("storageAccountName", "N/A")
        filesystem_name = parameters.get("filesystemName", "N/A")
        create_storage = parameters.get("createStorageAccount", "true").lower() == "true"
        create_container = parameters.get("createContainer", "true").lower() == "true"
        details.append(f"   Synapse Workspace: {synapse_name}")
        details.append(f"   Location: {location}")
        details.append(f"   Storage Account: {storage_name}")
        details.append(f"   Filesystem/Container: {filesystem_name}")
        details.append(f"   Storage Created: {'Yes' if create_storage else 'No (existing)'}")
        details.append(f"   Container Created: {'Yes' if create_container else 'No (existing)'}")
        details.append(f"   Synapse Studio: https://web.azuresynapse.net?workspace=%2Fsubscriptions%2F...%2F{synapse_name}")
        details.append("")
        details.append("   ⚠️ ADMIN ACTION REQUIRED:")
        details.append("   An admin with Owner/User Access Administrator role must assign")
        details.append(f"   'Storage Blob Data Contributor' role to the Synapse workspace")
        details.append(f"   managed identity on storage account '{storage_name}'.")
    
    else:
        name_keys = ["name", "accountName", "serverName", "serviceName"]
        resource_name = None
        for key in name_keys:
            if key in parameters:
                resource_name = parameters[key]
                break
        
        if resource_name:
            details.append(f"   Resource Name: {resource_name}")
        details.append(f"   Resource Type: {resource_type}")
        details.append(f"   Location: {location}")
    
    details.append("")
    details.append("─" * 70)
    details.append("")
    
    return "\n".join(details)


def parse_bicep_parameters(template_path: str) -> Dict[str, Tuple[bool, Optional[str]]]:
    """Parse bicep template to extract parameters."""
    params: Dict[str, Tuple[bool, Optional[str]]] = {}
    try:
        with open(template_path, 'r', encoding='utf-8') as f:
            for line in f:
                line_strip = line.strip()
                if line_strip.startswith('param '):
                    m = re.match(r"param\s+(\w+)\s+[^=\n]+(?:=\s*(.+))?", line_strip)
                    if m:
                        name = m.group(1)
                        default_raw = m.group(2).strip() if m.group(2) else None
                        required = default_raw is None
                        params[name] = (required, default_raw)
    except Exception:
        pass
    return params


def validate_bicep_parameters(resource_type: str, provided: Dict[str, str]) -> Tuple[bool, str, Dict[str, Tuple[bool, Optional[str]]]]:
    """Validate provided parameters against bicep template requirements."""
    if resource_type not in TEMPLATE_MAP:
        return False, f"Unknown resource_type '{resource_type}'.", {}
    template_path = get_template_path(TEMPLATE_MAP[resource_type])
    if not os.path.exists(template_path):
        return False, f"Template not found at {template_path}", {}
    params = parse_bicep_parameters(template_path)
    
    auto_calculated = []
    if resource_type == "subnet":
        auto_calculated.append("subnetStartingAddress")
    elif resource_type == "fabric-capacity":
        auto_calculated.append("location")
    
    missing = [p for p, (req, _) in params.items() if req and p not in auto_calculated and (p not in provided or provided[p] in (None, ""))]
    if missing:
        return False, f"Missing required parameters: {', '.join(missing)}", params
    return True, "OK", params


def deploy_bicep(resource_group: str, resource_type: str, parameters: Dict[str, str]) -> str:
    """Deploy a resource using bicep template."""
    if resource_type not in TEMPLATE_MAP:
        return f"Unknown resource_type '{resource_type}'."
    template_path = get_template_path(TEMPLATE_MAP[resource_type])
    if not os.path.exists(template_path):
        return f"Template not found: {template_path}"
    
    # Normalize case-sensitive parameters for storage accounts
    if resource_type == "storage-account" and "accessTier" in parameters:
        parameters["accessTier"] = parameters["accessTier"].lower().capitalize()
    
    # Special handling for Fabric Capacity
    if resource_type == "fabric-capacity":
        tenant_region = get_fabric_tenant_region()
        
        if tenant_region:
            tenant_region_normalized = tenant_region.lower().replace(" ", "")
            parameters["location"] = tenant_region_normalized
            print(f"[INFO] Auto-detected Fabric tenant region: {tenant_region} -> {tenant_region_normalized}")
        else:
            parameters["location"] = "westcentralus"
            print("[WARN] Could not detect Fabric tenant region. Using default: westcentralus")
    
    # Special handling for Subnet
    if resource_type == "subnet":
        vnet_name = parameters.get("vnetName", "")
        if vnet_name and "subnetStartingAddress" not in parameters:
            subnet_size = int(parameters.get("subnetSize", 27))
            next_address = calculate_next_subnet_address(resource_group, vnet_name, subnet_size)
            
            if next_address:
                parameters["subnetStartingAddress"] = next_address
                print(f"[INFO] Auto-calculated subnet starting address: {next_address}")
            else:
                return f"Error: Could not calculate next available subnet address in VNet '{vnet_name}'. The VNet may be full or not accessible."
    
    # Build parameters string for PowerShell
    param_string = ";".join([f"{k}={v}" for k, v in parameters.items()]) if parameters else ""
    
    script_name = OP_SCRIPTS["deploy-bicep"]
    script_path = get_script_path(script_name)
    
    if not os.path.exists(script_path):
        return f"Error: Script '{script_name}' not found at {script_path}"
    
    script_params = {
        "ResourceGroup": resource_group,
        "TemplatePath": template_path
    }
    
    if param_string:
        script_params["Parameters"] = param_string
    
    deploy_result = run_powershell_script(script_path, script_params)
    
    deployment_successful = (
        '"provisioningState": "Succeeded"' in deploy_result or
        "'provisioningState': 'Succeeded'" in deploy_result or
        "Succeeded" in deploy_result
    ) and "Failed" not in deploy_result
    
    if deployment_successful:
        # Handle post-deployment for Function App
        if resource_type == "function-app":
            output_lines = ["Running post-deployment tasks for Function App..."]
            post_script_path = get_script_path(OP_SCRIPTS["post-deploy-function-app"])
            
            if os.path.exists(post_script_path):
                post_params = {
                    "ResourceGroup": resource_group,
                    "FunctionAppName": parameters.get("functionAppName", ""),
                    "StorageAccountName": parameters.get("storageAccountName", ""),
                    "PrincipalId": ""
                }
                
                try:
                    deploy_json = json.loads(deploy_result) if deploy_result.strip().startswith("{") else {}
                    principal_id = deploy_json.get("properties", {}).get("outputs", {}).get("systemAssignedIdentityPrincipalId", {}).get("value", "")
                    if principal_id:
                        post_params["PrincipalId"] = principal_id
                        post_result = run_powershell_script(post_script_path, post_params)
                        output_lines.append(post_result)
                except Exception as e:
                    output_lines.append(f"Warning: Could not run post-deployment tasks: {str(e)}")
            
            output = output_lines + [format_deployment_details(resource_type, resource_group, parameters)]
        
        elif resource_type == "logic-app" and parameters.get("logicAppType") == "standard":
            logic_app_name = parameters.get("logicAppName", "")
            storage_name = parameters.get("storageAccountName", "")
            
            output = [format_deployment_details(resource_type, resource_group, parameters)]
            output.append("")
            output.append("═" * 70)
            output.append("🔐 REQUIRED RBAC ROLE ASSIGNMENTS")
            output.append("═" * 70)
            output.append("")
            output.append("The Logic App System Assigned Managed Identity needs these roles")
            output.append(f"on Storage Account '{storage_name}':")
            output.append("")
            output.append("┌─────────────────────────────────────┬──────────────────────────────────────┐")
            output.append("│ Role Name                           │ Role Definition ID                   │")
            output.append("├─────────────────────────────────────┼──────────────────────────────────────┤")
            output.append("│ Storage Blob Data Owner             │ b7e6dc6d-f1e8-4753-8033-0f276bb0955b │")
            output.append("│ Storage Account Contributor         │ 17d1049b-9a84-46fb-8f53-869881c3d3ab │")
            output.append("│ Storage Queue Data Contributor      │ 974c5e8b-45b9-4653-ba55-5f855dd0fb88 │")
            output.append("│ Storage Table Data Contributor      │ 0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3 │")
            output.append("│ Storage File Data SMB Share Contrib │ 0c867c2a-1d8c-454a-a3db-ab2ea1bdc8bb │")
            output.append("└─────────────────────────────────────┴──────────────────────────────────────┘")
            output.append("")
            output.append("Ask your admin to provide these roles to the Logic App's managed identity for proper functioning.")
            output.append("═" * 70)
        
        else:
            output = [format_deployment_details(resource_type, resource_group, parameters)]
        
        resource_id = get_resource_id(resource_group, resource_type, parameters)
        
        # NSP compliance prompt
        if resource_type in NSP_MANDATORY_RESOURCES:
            output.append("\n" + "─" * 70)
            output.append("")
            output.append("⚠️  COMPLIANCE REQUIREMENT")
            output.append("═" * 70)
            output.append("")
            output.append("This resource requires NSP attachment for:")
            output.append("   📋 Secure PaaS Resources - Network Isolation")
            output.append("")
            output.append("═" * 70)
            output.append("")
            output.append("🔒 Do you want to attach this resource to NSP?")
            output.append("")
            output.append("   Type 'yes' or 'attach to NSP' to proceed")
            output.append("   Type 'no' to skip (not recommended - resource will not be compliant)")
            output.append("")
            output.append("Automated workflow will:")
            output.append("   1. ✓ Check if NSP exists in the resource group")
            output.append("   2. ✓ Create NSP if it doesn't exist (skip if exists)")
            output.append("   3. ✓ Attach the resource to the NSP")
            output.append("")
        
        # Log Analytics compliance prompt
        if resource_type in LOG_ANALYTICS_MANDATORY_RESOURCES:
            output.append("\n" + "═" * 70)
            output.append("⚠️  COMPLIANCE REQUIREMENT")
            output.append("═" * 70)
            output.append("")
            output.append("This resource requires Log Analytics diagnostic settings for:")
            output.append("   Resource Monitoring & Compliance")
            output.append("")
            output.append("═" * 70)
            output.append("")
            output.append("Do you want to configure Log Analytics for this resource?")
            output.append("")
            output.append("   Type 'yes' or 'configure Log Analytics' to proceed")
            output.append("   Type 'no' to skip (not recommended - resource will not have monitoring)")
            output.append("")
            output.append("Automated workflow will:")
            output.append("   1. ✓ Check if Log Analytics Workspace exists in the resource group")
            output.append("   2. ✓ Create workspace if it doesn't exist (skip if exists)")
            output.append("   3. ✓ Configure diagnostic settings for the resource")
            output.append("")
        
        return "\n".join(output)
    
    return deploy_result


# ============================================================================
# INSTRUCTIONS LOADING
# ============================================================================

AGENT_INSTRUCTIONS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "AGENT_INSTRUCTIONS.md")


def load_agent_instructions() -> str:
    """Load the AGENT_INSTRUCTIONS.md file content if present."""
    if os.path.exists(AGENT_INSTRUCTIONS_FILE):
        try:
            with open(AGENT_INSTRUCTIONS_FILE, "r", encoding="utf-8") as f:
                return f.read()
        except Exception as e:
            return f"Failed to read instructions: {e}"
    return "Instructions file not found."
