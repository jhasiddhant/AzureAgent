# ============================================================================
# UTILITIES - Shared helpers, constants, and configurations
# ============================================================================

import subprocess
import os
import re
import shutil
import json
import platform
from typing import Dict, Tuple, Optional, Any

# ============================================================================
# CONSTANTS - Error Detection
# ============================================================================

# Keywords that indicate deployment/operation failures
ERROR_KEYWORDS = ["Error", "error", "FAILED", "Failed", "failed"]

# Azure-specific error patterns with user-friendly messages and solutions
AZURE_ERROR_PATTERNS = {
    "AuthorizationFailed": {
        "message": "Authorization Error",
        "cause": "You don't have sufficient permissions to perform this action.",
        "solutions": [
            "Run 'az login' to refresh your credentials",
            "Verify you have 'Contributor' or 'Owner' role on the resource group",
            "Check if your token has expired (tokens expire after ~1 hour)",
            "Contact your Azure admin to grant required permissions"
        ]
    },
    "ResourceNotFound": {
        "message": "Resource Not Found",
        "cause": "The specified resource does not exist.",
        "solutions": [
            "Verify the resource name and resource group are correct",
            "Check if the resource was deleted or moved",
            "Ensure you're using the correct subscription"
        ]
    },
    "SubscriptionNotFound": {
        "message": "Subscription Not Found",
        "cause": "The specified subscription is not accessible.",
        "solutions": [
            "Run 'az account list' to see available subscriptions",
            "Run 'az account set --subscription <id>' to switch subscriptions",
            "Verify you have access to the subscription"
        ]
    },
    "InvalidResourceType": {
        "message": "Invalid Resource Type",
        "cause": "The resource type specified is not valid.",
        "solutions": [
            "Check the resource type spelling",
            "Verify the API version supports this resource type"
        ]
    },
    "QuotaExceeded": {
        "message": "Quota Exceeded",
        "cause": "You've reached the limit for this resource type in the region.",
        "solutions": [
            "Try a different Azure region",
            "Request a quota increase via Azure portal",
            "Delete unused resources to free up quota"
        ]
    },
    "Conflict": {
        "message": "Resource Conflict",
        "cause": "A resource with this name already exists or is in a conflicting state.",
        "solutions": [
            "Use a different resource name",
            "Wait for any pending operations to complete",
            "Delete the existing resource if it's no longer needed"
        ]
    },
    "InvalidParameter": {
        "message": "Invalid Parameter",
        "cause": "One or more parameters are invalid.",
        "solutions": [
            "Review the parameter values for typos",
            "Check parameter constraints (length, allowed values, format)"
        ]
    },
    "PrivateEndpointCannotBeCreatedInSubnet": {
        "message": "Private Endpoint Subnet Error",
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
    "sql-server"
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
    "document-intelligence",
    "ai-docintelligence",
    "ai-contentsafety",
    "ai-languageservices",
    "front-door",
    "frontdoor",
    "afd",
    "virtual-machine",
    "vm",
    "redis-cache",
    "redis-enterprise",
    "container-registry",
    "acr",
    "sql-database",
    "sql-db",
    "azure-sql-database",
    "automation-account",
    "automation",
    "speech-service",
    "speech",
    "speech-services"
]

# Bicep Templates mapping
TEMPLATE_MAP = {
    "storage-account": "templates/storage-account.bicep",
    "key-vault": "templates/azure-key-vaults.bicep",
    "openai": "templates/azure-openai.bicep",
    "ai-search": "templates/ai-search.bicep",
    "ai-contentsafety": "templates/contentsafety.bicep",
    "ai-docintelligence": "templates/documentintelligence.bicep",
    "ai-languageservice": "templates/languageservice.bicep",
    "cosmos-db": "templates/cosmos-db.bicep",
    "log-analytics": "templates/log-analytics.bicep",
    "uami": "templates/user-assigned-managed-identity.bicep",
    "user-assigned-managed-identity": "templates/user-assigned-managed-identity.bicep",
    "nsp": "templates/network-security-perimeter.bicep",
    "network-security-perimeter": "templates/network-security-perimeter.bicep",
    "fabric-capacity": "templates/fabric-capacity.bicep",
    "container-registry": "templates/container-registry.bicep",
    "acr": "templates/container-registry.bicep",
    "function-app": "templates/function-app-flex.bicep",
    "function-app-flex": "templates/function-app-flex.bicep",
    "funcapp-flex": "templates/function-app-flex.bicep",
    "function-app-appserviceplan": "templates/function-app-appserviceplan.bicep",
    "funcapp-appserviceplan": "templates/function-app-appserviceplan.bicep",
    "app-service": "templates/app-service.bicep",
    "webapp": "templates/app-service.bicep",
    "web-app": "templates/app-service.bicep",
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
    "private-dns-zone": "templates/private-dns-zone.bicep",
    "dns-zone": "templates/private-dns-zone.bicep",
    "dns-zone-vnet-link": "templates/dns-zone-vnet-link.bicep",
    "vnet-link": "templates/dns-zone-vnet-link.bicep",
    "logic-app": "templates/logic-app.bicep",
    "redis-cache": "templates/redis-cache.bicep",
    "redis": "templates/redis-cache.bicep",
    "sql-server": "templates/azure-sql-server.bicep",
    "sql-database": "templates/azure-sql-database.bicep",
    "sql-db": "templates/azure-sql-database.bicep",
    "application-insights": "templates/application-insights.bicep",
    "app-insights": "templates/application-insights.bicep",
    "appinsights": "templates/application-insights.bicep",
    "container-apps-env": "templates/container-apps-env.bicep",
    "container-apps-environment": "templates/container-apps-env.bicep",
    "aca-env": "templates/container-apps-env.bicep",
    "container-app": "templates/container-app.bicep",
    "containerapp": "templates/container-app.bicep",
    "aca": "templates/container-app.bicep",
    "data-collection-endpoint": "templates/data-collection-endpoint.bicep",
    "dce": "templates/data-collection-endpoint.bicep",
    "data-collection-rule": "templates/data-collection-rule.bicep",
    "dcr": "templates/data-collection-rule.bicep",
    "api-management": "templates/api-management.bicep",
    "apim": "templates/api-management.bicep",
    "ai-foundry": "templates/ai-foundry.bicep",
    "ai-hub": "templates/ai-foundry.bicep",
    "azure-firewall": "templates/azure-firewall.bicep",
    "firewall": "templates/azure-firewall.bicep",
    "azfw": "templates/azure-firewall.bicep",
    "nat-gateway": "templates/nat-gateway.bicep",
    "natgw": "templates/nat-gateway.bicep",
    "automation-account": "templates/automation-account.bicep",
    "automation": "templates/automation-account.bicep",
    "waf-policy": "templates/waf-policy.bicep",
    "waf": "templates/waf-policy.bicep",
    "frontdoor-waf": "templates/waf-policy.bicep",
    "front-door": "templates/front-door.bicep",
    "frontdoor": "templates/front-door.bicep",
    "afd": "templates/front-door.bicep",
    "ddos-protection-plan": "templates/ddos-protection-plan.bicep",
    "ddos": "templates/ddos-protection-plan.bicep",
    "vpn-gateway": "templates/vpn-gateway.bicep",
    "vpngateway": "templates/vpn-gateway.bicep",
    "vpngw": "templates/vpn-gateway.bicep",
    "firewall-policy": "templates/firewall-policy.bicep",
    "fw-policy": "templates/firewall-policy.bicep",
    "dns-resolver": "templates/dns-resolver.bicep",
    "dns-private-resolver": "templates/dns-resolver.bicep",
    "dnspr": "templates/dns-resolver.bicep",
    "speech-service": "templates/speech-service.bicep",
    "speech": "templates/speech-service.bicep",
    "speech-services": "templates/speech-service.bicep",
    "log-search-alert": "templates/log-search-alert.bicep",
    "alert-rule": "templates/log-search-alert.bicep",
    "scheduled-query-rule": "templates/log-search-alert.bicep",
    "document-db-mongo": "templates/document-db-mongo.bicep",
    "mongo-cluster": "templates/document-db-mongo.bicep",
    "mongodb-cluster": "templates/document-db-mongo.bicep",
    "docdb-mongo": "templates/document-db-mongo.bicep",
}

# Resource types that have multiple variants - user should choose
RESOURCE_VARIANTS = {
    "function-app": {
        "function-app-flex": "Flex Consumption (serverless, pay-per-execution, auto-scaling)",
        "function-app-appserviceplan": "App Service Plan (dedicated instances, configurable SKU: B1-P3v3)"
    },
    "funcapp": {
        "funcapp-flex": "Flex Consumption (serverless, pay-per-execution, auto-scaling)",
        "funcapp-appserviceplan": "App Service Plan (dedicated instances, configurable SKU: B1-P3v3)"
    }
}

# Private DNS Zone mapping based on groupId (sub-resource)
# Reference: https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns
PRIVATE_DNS_ZONE_MAP = {
    # Storage Account
    "blob": "privatelink.blob.core.windows.net",
    "blob_secondary": "privatelink.blob.core.windows.net",
    "file": "privatelink.file.core.windows.net",
    "file_secondary": "privatelink.file.core.windows.net",
    "table": "privatelink.table.core.windows.net",
    "table_secondary": "privatelink.table.core.windows.net",
    "queue": "privatelink.queue.core.windows.net",
    "queue_secondary": "privatelink.queue.core.windows.net",
    "web": "privatelink.web.core.windows.net",
    "dfs": "privatelink.dfs.core.windows.net",
    "dfs_secondary": "privatelink.dfs.core.windows.net",
    
    # Key Vault
    "vault": "privatelink.vaultcore.azure.net",
    
    # Cosmos DB
    "Sql": "privatelink.documents.azure.com",
    "MongoDB": "privatelink.mongo.cosmos.azure.com",
    "Cassandra": "privatelink.cassandra.cosmos.azure.com",
    "Gremlin": "privatelink.gremlin.cosmos.azure.com",
    "Table": "privatelink.table.cosmos.azure.com",
    "Analytical": "privatelink.analytics.cosmos.azure.com",
    
    # SQL Database
    "sqlServer": "privatelink.database.windows.net",
    
    # Synapse
    "SqlOnDemand": "privatelink.sql.azuresynapse.net",
    "Dev": "privatelink.dev.azuresynapse.net",
    
    # App Service / Function App
    "sites": "privatelink.azurewebsites.net",
    
    # Cognitive Services / OpenAI
    "account": "privatelink.cognitiveservices.azure.com",
    
    # Container Registry
    "registry": "privatelink.azurecr.io",
    
    # Azure AI Search
    "searchService": "privatelink.search.windows.net",
    
    # Event Hub / Service Bus
    "namespace": "privatelink.servicebus.windows.net",
    
    # Data Factory
    "dataFactory": "privatelink.datafactory.azure.net",
    "portal": "privatelink.adf.azure.com",
    
    # Machine Learning
    "amlworkspace": "privatelink.api.azureml.ms",
    
    # Redis Cache
    "redisCache": "privatelink.redis.cache.windows.net",
    
    # SignalR
    "signalr": "privatelink.service.signalr.net",
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
    "document-intelligence": "Microsoft.CognitiveServices/accounts",
    "ai-docintelligence": "Microsoft.CognitiveServices/accounts",
    "ai-languageservice": "Microsoft.CognitiveServices/accounts",
    "ai-contentsafety": "Microsoft.CognitiveServices/accounts",
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
    "function-app-flex": "Microsoft.Web/sites",
    "funcapp-flex": "Microsoft.Web/sites",
    "function-app-appserviceplan": "Microsoft.Web/sites",
    "funcapp-appserviceplan": "Microsoft.Web/sites",
    "app-service": "Microsoft.Web/sites",
    "webapp": "Microsoft.Web/sites",
    "web-app": "Microsoft.Web/sites",
    "synapse": "Microsoft.Synapse/workspaces",
    "azure-synapse-analytics": "Microsoft.Synapse/workspaces",
    "data-factory": "Microsoft.DataFactory/factories",
    "azure-data-factory": "Microsoft.DataFactory/factories",
    "adf": "Microsoft.DataFactory/factories",
    "public-ip": "Microsoft.Network/publicIPAddresses",
    "pip": "Microsoft.Network/publicIPAddresses",
    "front-door": "Microsoft.Cdn/profiles",
    "frontdoor": "Microsoft.Cdn/profiles",
    "afd": "Microsoft.Cdn/profiles",
    "ddos-protection-plan": "Microsoft.Network/ddosProtectionPlans",
    "ddos": "Microsoft.Network/ddosProtectionPlans",
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
    "azure-firewall": "Microsoft.Network/azureFirewalls",
    "firewall": "Microsoft.Network/azureFirewalls",
    "azfw": "Microsoft.Network/azureFirewalls",
    "nat-gateway": "Microsoft.Network/natGateways",
    "natgw": "Microsoft.Network/natGateways",
    "automation-account": "Microsoft.Automation/automationAccounts",
    "automation": "Microsoft.Automation/automationAccounts",
    "waf-policy": "Microsoft.Network/FrontDoorWebApplicationFirewallPolicies",
    "waf": "Microsoft.Network/FrontDoorWebApplicationFirewallPolicies",
    "frontdoor-waf": "Microsoft.Network/FrontDoorWebApplicationFirewallPolicies",
    "vpn-gateway": "Microsoft.Network/virtualNetworkGateways",
    "vpngateway": "Microsoft.Network/virtualNetworkGateways",
    "vpngw": "Microsoft.Network/virtualNetworkGateways",
    "firewall-policy": "Microsoft.Network/firewallPolicies",
    "fw-policy": "Microsoft.Network/firewallPolicies",
    "dns-resolver": "Microsoft.Network/dnsResolvers",
    "dns-private-resolver": "Microsoft.Network/dnsResolvers",
    "dnspr": "Microsoft.Network/dnsResolvers",
    "speech-service": "Microsoft.CognitiveServices/accounts",
    "speech": "Microsoft.CognitiveServices/accounts",
    "speech-services": "Microsoft.CognitiveServices/accounts",
    "log-search-alert": "Microsoft.Insights/scheduledQueryRules",
    "alert-rule": "Microsoft.Insights/scheduledQueryRules",
    "scheduled-query-rule": "Microsoft.Insights/scheduledQueryRules",
}

# Pipeline YAML Templates
PIPELINE_TEMPLATE_MAP = {
    "codeql": "templates/CodeQL_Pipeline.yml",
    "codeql-1es": "templates/CodeQL_1ES_Pipeline.yml",
}

# Pipeline type keywords for auto-detection
PIPELINE_TYPE_KEYWORDS = {
    "1es": "codeql-1es",
    "prod": "codeql-1es",
    "production": "codeql-1es",
    "codeql": "codeql",
}

# Operational Scripts
OP_SCRIPTS = {
    "permissions": "list-azure-permissions.ps1",
    "resources": "list-resources.ps1",
    "create-rg": "create-resourcegroup.ps1",
    "deploy-bicep": "deploy-bicep.ps1",
    "create-funcapp-containers": "create-funcapp-containers.ps1"
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
        # On Windows, az CLI needs cmd /c wrapper when shell=False
        if platform.system() == "Windows" and command and command[0] == "az":
            command = ["cmd", "/c"] + command
        
        result = subprocess.run(
            command,
            shell=False,
            capture_output=True,
            text=True,
            encoding='utf-8',
            errors='replace',
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
                output_parts.append(f"\n═══════════════════════════════════════════════════════════\nError Details:\n═══════════════════════════════════════════════════════════\n{stderr_lines}")
            else:
                output_parts.append(stderr_lines)
        
        if azure_error:
            output_parts.append(azure_error)
        
        if result.returncode != 0:
            output_parts.append(f"\n[Exit Code: {result.returncode}]")
        
        return "\n".join(output_parts) if output_parts else "Command completed with no output"
        
    except subprocess.TimeoutExpired:
        return f"Command timed out after 600 seconds\n\nCommand: {' '.join(command)}\n\nThis usually indicates a hanging process or very slow operation."
    except Exception as e:
        return f"Execution error\n\nCommand: {' '.join(command)}\n\nError: {str(e)}\nError Type: {type(e).__name__}"


def run_powershell_script(script_path: str, parameters: dict) -> str:
    """Execute PowerShell script with enhanced error reporting."""
    ps_executable = "pwsh" if shutil.which("pwsh") else "powershell"
    cmd = [ps_executable, "-ExecutionPolicy", "Bypass", "-File", script_path]
    for k, v in parameters.items():
        if v is not None and v != "":
            cmd.append(f"-{k}")
            cmd.append(str(v))
    
    return run_command(cmd)


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
    
    return "codeql"


def get_pipeline_template(pipeline_type: str) -> Optional[str]:
    """
    Gets the pipeline template path for a given pipeline type.
    Falls back to codeql if requested type doesn't exist.
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
    
    if "codeql" in PIPELINE_TEMPLATE_MAP:
        template_rel = PIPELINE_TEMPLATE_MAP["codeql"]
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
        "factoryName", "cacheName", "frontDoorName", "clusterName", "wafPolicyName",
        "vpnGatewayName", "natGatewayName", "ddosProtectionPlanName", "firewallPolicyName",
        "dnsResolverName", "alertRuleName"
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
    details.append("=" * 70)
    details.append("Deployment successful")
    details.append("=" * 70)
    details.append("")
    details.append("Deployment Details:")
    details.append("")
    
    location = parameters.get("location", "N/A")
    
    if resource_type == "storage-account":
        storage_name = parameters.get("storageAccountName", "N/A")
        access_tier = parameters.get("accessTier", "N/A")
        hns_enabled = parameters.get("enableHierarchicalNamespace", "true")
        
        details.append(f"   Storage Account: {storage_name}")
        details.append(f"   Location: {location}")
        details.append(f"   Access Tier: {access_tier}")
        details.append(f"   ADLS Gen2: {'Enabled' if str(hns_enabled).lower() == 'true' else 'Disabled'}")
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
    
    elif resource_type in ["application-insights", "app-insights", "appinsights"]:
        app_name = parameters.get("appInsightsName", "N/A")
        workspace_id = parameters.get("logAnalyticsWorkspaceId", "N/A")
        workspace_name = workspace_id.split("/")[-1] if workspace_id != "N/A" else "N/A"
        details.append(f"   Application Insights: {app_name}")
        details.append(f"   Location: {location}")
        details.append("")
        details.append("   Configuration:")
        details.append(f"     - Log Analytics Workspace: {workspace_name}")
        details.append("     - Local Auth (API Keys): Disabled")
        details.append("     - Retention: 90 days")
        details.append("")
        details.append("   Connection Details:")
        details.append("     - Instrumentation Key and Connection String available in outputs")
        details.append("     - Use Connection String for new integrations (recommended)")
    
    elif resource_type == "container-registry":
        registry_name = parameters.get("registryName", "N/A")
        sku = parameters.get("sku", "N/A")
        details.append(f"   Container Registry: {registry_name}")
        details.append(f"   Location: {location}")
        details.append(f"   SKU: {sku}")
        details.append(f"   Login Server: {registry_name}.azurecr.io")
    
    elif resource_type in ["redis-cache", "redis"]:
        redis_name = parameters.get("redisCacheName", "N/A")
        sku_name = parameters.get("skuName", "Standard")
        sku_capacity = parameters.get("skuCapacity", "0")
        details.append(f"   Redis Cache: {redis_name}")
        details.append(f"   Location: {location}")
        details.append(f"   SKU: {sku_name} C{sku_capacity}")
        details.append(f"   Host Name: {redis_name}.redis.cache.windows.net")
        details.append(f"   SSL Port: 6380")
        details.append("")
        details.append("   Security Configuration:")
        details.append("     - Microsoft Entra Authentication: Enabled")
        details.append("     - Access Key Authentication: Disabled")
        details.append("     - Minimum TLS Version: 1.2")
        details.append("")
        details.append("   Access Policies Created:")
        details.append("     - Data Owner (full access)")
        details.append("     - Data Contributor (read/write, no dangerous ops)")
        details.append("     - Data Reader (read only)")
    
    elif resource_type in ["sql-server", "azure-sql-server"]:
        server_name = parameters.get("sqlServerName", "N/A")
        admin_login = parameters.get("entraAdminLogin", "N/A")
        details.append(f"   Azure SQL Server: {server_name}")
        details.append(f"   Location: {location}")
        details.append(f"   FQDN: {server_name}.database.windows.net")
        details.append("")
        details.append("   Security Configuration:")
        details.append("     - Microsoft Entra Only Authentication: Enabled")
        details.append("     - SQL Server Authentication: Disabled")
        details.append(f"     - Entra Admin: {admin_login}")
        details.append("     - TLS Version: 1.2")
        details.append("     - Advanced Threat Protection: Enabled")
        details.append("     - SQL Auditing: Enabled (Log Analytics)")
        law_name = parameters.get("logAnalyticsWorkspaceName", "N/A")
        details.append(f"     - Log Analytics Workspace: {law_name}")
        details.append("     - Audit Categories: SQLSecurityAuditEvents, DevOpsOperationsAudit")
        details.append("")
        details.append("   Network Configuration:")
        details.append("     - Allow Azure Services: Enabled")
        details.append("")
        details.append("   Next Steps:")
        details.append("     - Create an Azure SQL Database in this server")
        details.append("     - Configure firewall rules for client access")
        details.append("     - Set up private endpoint for secure connectivity")
    
    elif resource_type in ["sql-database", "sql-db", "azure-sql-database"]:
        db_name = parameters.get("databaseName", "N/A")
        server_name = parameters.get("sqlServerName", "N/A")
        sku_name = parameters.get("skuName", "GP_S_Gen5")
        sku_tier = parameters.get("skuTier", "GeneralPurpose")
        details.append(f"   Azure SQL Database: {db_name}")
        details.append(f"   Azure SQL Server: {server_name}")
        details.append(f"   Location: {location}")
        details.append(f"   SKU: {sku_name} ({sku_tier})")
        details.append("")
        if "GP_S" in sku_name:
            details.append("   Serverless Configuration:")
            min_cap = parameters.get("minCapacity", "0.5")
            auto_pause = parameters.get("autoPauseDelay", "60")
            details.append(f"     - Min vCores: {min_cap}")
            details.append(f"     - Auto-pause Delay: {auto_pause} minutes")
            details.append("")
        details.append("   Security:")
        details.append("     - Transparent Data Encryption: Enabled")
        details.append("     - Backup Retention: 7 days")
    
    elif resource_type in ["function-app", "function-app-flex", "funcapp-flex"]:
        function_name = parameters.get("functionAppName", "N/A")
        runtime = parameters.get("runtimeStack", "python")
        runtime_version = parameters.get("runtimeVersion", "3.11")
        storage_name = parameters.get("storageAccountName", "N/A")
        uami_name = parameters.get("uamiName", "N/A")
        
        details.append(f"   Function App:        {function_name}")
        details.append(f"   App Service Plan:    {function_name}-plan (Flex Consumption FC1)")
        details.append(f"   Location:            {location}")
        details.append(f"   Runtime:             {runtime} {runtime_version}")
        details.append(f"   URL:                 https://{function_name}.azurewebsites.net")
        details.append("")
        details.append("   Identity Configuration:")
        details.append(f"     - System Assigned MI: Enabled (not used)")
        details.append(f"     - User Assigned MI:   {uami_name} (used for deployment & runtime)")
        details.append("")
        details.append(f"   Storage (ADLS):      {storage_name}")
        details.append(f"   Public Access:       Enabled")
        details.append("")
        details.append("─" * 70)
        details.append("")
        details.append("DIAGNOSTIC SETTINGS - ACTION REQUIRED")
        details.append("")
        details.append("   Diagnostic settings are NOT configured by default.")
        details.append("   Configure via Portal or use: azure_attach_diagnostic_settings")
        details.append("")
        details.append("─" * 70)
        details.append("")
        details.append("ROLE ASSIGNMENTS - REQUEST ADMIN")
        details.append("")
        details.append("   An admin must assign these roles on the ADLS storage account:")
        details.append("")
        uami_principal_id = parameters.get("_uamiPrincipalId", "")
        details.append(f"   User Assigned MI → Storage Blob Data Contributor")
        details.append("                    → Storage Account Contributor")
        if uami_principal_id:
            details.append(f"      Principal ID: {uami_principal_id}")
        details.append("")
        details.append(f"   After role assignment: az functionapp restart -n {function_name} -g <resource_group>")
    
    elif resource_type in ["function-app-appserviceplan", "funcapp-appserviceplan"]:
        function_name = parameters.get("functionAppName", "N/A")
        runtime = parameters.get("runtimeStack", "python")
        runtime_version = parameters.get("runtimeVersion", "3.11")
        storage_name = parameters.get("storageAccountName", "N/A")
        uami_name = parameters.get("uamiName", "N/A")
        sku_name = parameters.get("skuName", "S1")
        instance_count = parameters.get("instanceCount", 1)
        always_on = parameters.get("alwaysOn", True)
        
        details.append(f"   Function App:        {function_name}")
        details.append(f"   App Service Plan:    {function_name}-plan ({sku_name})")
        details.append(f"   Instances:           {instance_count}")
        details.append(f"   Location:            {location}")
        details.append(f"   Runtime:             {runtime} {runtime_version}")
        details.append(f"   Always On:           {'Enabled' if always_on else 'Disabled'}")
        details.append(f"   URL:                 https://{function_name}.azurewebsites.net")
        details.append("")
        details.append("   Identity Configuration:")
        details.append(f"     - System Assigned MI: Enabled")
        details.append(f"     - User Assigned MI:   {uami_name}")
        details.append("")
        details.append(f"   Storage Account:     {storage_name}")
        details.append(f"   Public Access:       Enabled")
        details.append("")
        details.append("─" * 70)
        details.append("")
        details.append("ROLE ASSIGNMENTS - REQUEST ADMIN")
        details.append("")
        details.append("   An admin must assign these roles on the storage account:")
        details.append("")
        uami_principal_id = parameters.get("_uamiPrincipalId", "")
        details.append(f"   User Assigned MI → Storage Blob Data Contributor")
        details.append("                    → Storage Account Contributor")
        if uami_principal_id:
            details.append(f"      Principal ID: {uami_principal_id}")
        details.append("")
        details.append(f"   After role assignment: az functionapp restart -n {function_name} -g <resource_group>")
    
    elif resource_type in ["app-service", "webapp", "web-app"]:
        app_name = parameters.get("appServiceName", "N/A")
        uami_name = parameters.get("uamiName", "N/A")
        sku_name = parameters.get("skuName", "B1")
        instance_count = parameters.get("instanceCount", 1)
        always_on = parameters.get("alwaysOn", False)
        runtime = parameters.get("linuxFxVersion", "DOTNET|8.0")
        
        details.append(f"   App Service:         {app_name}")
        details.append(f"   App Service Plan:    {app_name}-plan ({sku_name})")
        details.append(f"   Instances:           {instance_count}")
        details.append(f"   Location:            {location}")
        details.append(f"   Runtime:             {runtime}")
        details.append(f"   Always On:           {'Enabled' if always_on else 'Disabled'}")
        details.append(f"   URL:                 https://{app_name}.azurewebsites.net")
        details.append("")
        details.append("   Security Configuration:")
        details.append("     - HTTPS Only: Enabled")
        details.append("     - TLS Version: 1.3 (minimum)")
        details.append("     - End-to-End TLS: Enabled")
        details.append("     - Remote Debugging: Disabled")
        details.append("     - FTP/FTPS: Disabled")
        details.append("     - SCM Credentials: Disabled")
        details.append("")
        details.append("   Identity Configuration:")
        details.append(f"     - System Assigned MI: Enabled")
        details.append(f"     - User Assigned MI:   {uami_name}")
        details.append("")
        details.append("─" * 70)
        details.append("")
        details.append("DIAGNOSTIC SETTINGS - RECOMMENDED")
        details.append("")
        details.append("   Configure diagnostic settings for compliance:")
        details.append("   1. Log Analytics: azure_attach_diagnostic_settings")
        details.append("   2. App Insights:  azure_attach_appinsights")

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
        details.append("   Admin action required:")
        details.append("   An admin with Owner/User Access Administrator role must assign")
        details.append(f"   'Storage Blob Data Contributor' role to the Synapse workspace")
        details.append(f"   managed identity on storage account '{storage_name}'.")
    
    elif resource_type in ["container-apps-env", "container-apps-environment", "aca-env"]:
        env_name = parameters.get("environmentName", "N/A")
        subnet_id = parameters.get("infrastructureSubnetId", "N/A")
        zone_redundant = parameters.get("zoneRedundant", "false")
        workload_profile = parameters.get("workloadProfileType", "Consumption")
        internal_only = parameters.get("internalOnly", "false")
        log_workspace_id = parameters.get("logAnalyticsWorkspaceId", "N/A")
        log_workspace_name = log_workspace_id.split("/")[-1] if log_workspace_id != "N/A" else "N/A"
        subnet_name = subnet_id.split("/")[-1] if subnet_id != "N/A" else "N/A"
        vnet_name = subnet_id.split("/subnets/")[0].split("/")[-1] if "/subnets/" in subnet_id else "N/A"
        
        details.append(f"   Container Apps Environment: {env_name}")
        details.append(f"   Location: {location}")
        details.append("")
        details.append("   Configuration:")
        details.append(f"     - Workload Profile: {workload_profile}")
        details.append(f"     - Zone Redundant: {zone_redundant}")
        details.append(f"     - Internal Only: {internal_only}")
        details.append("")
        details.append("   Networking:")
        details.append(f"     - VNet: {vnet_name}")
        details.append(f"     - Subnet: {subnet_name}")
        details.append("")
        details.append("   Monitoring:")
        details.append(f"     - Log Analytics Workspace: {log_workspace_name}")
        details.append("")
        details.append("   Next Steps:")
        details.append("     - Deploy a Container App into this environment")
    
    elif resource_type in ["container-app", "containerapp", "aca"]:
        app_name = parameters.get("containerAppName", "N/A")
        env_name = parameters.get("environmentName", "N/A")
        cpu = parameters.get("cpu", "0.5")
        memory = parameters.get("memory", "1Gi")
        min_replicas = parameters.get("minReplicas", "0")
        max_replicas = parameters.get("maxReplicas", "10")
        target_port = parameters.get("targetPort", "80")
        external = parameters.get("externalIngress", "true")
        workload_profile = parameters.get("workloadProfileName", "Consumption")
        
        details.append(f"   Container App: {app_name}")
        details.append(f"   Location: {location}")
        details.append(f"   Environment: {env_name}")
        details.append("")
        details.append("   Container Configuration:")
        details.append(f"     - Image: mcr.microsoft.com/azuredocs/containerapps-helloworld:latest")
        details.append(f"     - CPU: {cpu} cores")
        details.append(f"     - Memory: {memory}")
        details.append(f"     - Workload Profile: {workload_profile}")
        details.append("")
        details.append("   Ingress:")
        details.append(f"     - External Access: {external}")
        details.append(f"     - Target Port: {target_port}")
        details.append(f"     - Transport: auto")
        details.append("")
        details.append("   Scaling:")
        details.append(f"     - Min Replicas: {min_replicas}")
        details.append(f"     - Max Replicas: {max_replicas}")
        details.append(f"     - Scale Rule: HTTP (100 concurrent requests)")
        details.append("")
        details.append("   Identity:")
        details.append(f"     - System Assigned MI: Enabled")
        details.append("")
        details.append(f"   URL: https://{app_name}.<environment-default-domain>")
    
    elif resource_type in ["vpn-gateway", "vpngateway", "vpngw"]:
        gw_name = parameters.get("vpnGatewayName", "N/A")
        sku = parameters.get("skuName", "VpnGw2AZ")
        vpn_type = parameters.get("vpnType", "RouteBased")
        generation = parameters.get("vpnGatewayGeneration", "Generation1")
        vnet_id = parameters.get("vnetId", "N/A")
        vnet_name = vnet_id.split("/")[-1] if vnet_id != "N/A" else "N/A"
        nsg_id = parameters.get("nsgId", "N/A")
        nsg_name = nsg_id.split("/")[-1] if nsg_id != "N/A" else "N/A"
        details.append(f"   VPN Gateway: {gw_name}")
        details.append(f"   Location: {location}")
        details.append(f"   SKU: {sku}")
        details.append(f"   VPN Type: {vpn_type}")
        details.append(f"   Generation: {generation}")
        details.append("")
        details.append("   Configuration:")
        details.append("     - Active-Active: Enabled")
        details.append("     - BGP: Enabled")
        details.append(f"     - VNet: {vnet_name}")
        details.append(f"     - NSG: {nsg_name}")
        details.append("     - Public IPs: 3 (Primary, Secondary, Tertiary)")
        details.append("")
        details.append("   " + "═" * 60)
        details.append("   IMPORTANT: VPN Gateway takes ~30-45 minutes to provision.")
        details.append("   " + "═" * 60)
        details.append("")
        details.append("   Point-to-Site (P2S) Configuration")
        details.append("   " + "─" * 60)
        details.append("   After the VPN Gateway is created, configure the P2S settings")
        details.append("   in the Azure Portal with the following details:")
        details.append("")
        details.append("     1. Address Pool: Add the private address prefix for P2S clients")
        details.append("     2. Tunnel type: Select OpenVPN (SSL)")
        details.append("     3. Authentication type: Select Azure Active Directory")
        details.append("     4. Tenant: https://login.microsoftonline.com/72f988bf-86f1-41af-91ab-2d7cd011db47/")
        details.append("     5. Audience: c632b3df-fb67-4d84-bdcf-b95ad541b5c8")
        details.append("     6. Issuer: https://sts.windows.net/72f988bf-86f1-41af-91ab-2d7cd011db47/")
        details.append("     7. Assign the third Public IP to the P2S configuration")
        details.append("")
        details.append("   Portal Path: VPN Gateway > Point-to-site configuration")

    elif resource_type in ["front-door", "frontdoor", "afd"]:
        fd_name = parameters.get("frontDoorName", "N/A")
        endpoint_name = parameters.get("endpointName", "") or fd_name
        origin_host = parameters.get("originHostName", "N/A")
        sku = parameters.get("skuName", "Premium_AzureFrontDoor")
        waf_id = parameters.get("wafPolicyId", "N/A")
        waf_name = waf_id.split("/")[-1] if waf_id != "N/A" else "N/A"
        details.append(f"   Front Door Profile: {fd_name}")
        details.append(f"   SKU: {sku}")
        details.append(f"   Endpoint: {endpoint_name}")
        details.append("")
        details.append("   Origin Configuration:")
        details.append(f"     - Host: {origin_host}")
        details.append(f"     - Origin Group: {parameters.get('originGroupName', 'default-origin-group')}")
        details.append("")
        details.append("   Security:")
        details.append(f"     - WAF Policy: {waf_name}")
        details.append("     - HTTPS Redirect: Enabled")
        details.append("     - Certificate Name Check: Enforced")
        details.append("")
        details.append("   Endpoint URL:")
        details.append(f"     https://{endpoint_name}.z01.azurefd.net")

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
    """Parse bicep template to extract parameters, @allowed values, @description, and constraints.
    
    Returns dict of param_name -> (required: bool, default_value: str|None)
    Also stores extended info in PARAM_METADATA for allowed values and descriptions.
    """
    global PARAM_METADATA
    params: Dict[str, Tuple[bool, Optional[str]]] = {}
    try:
        with open(template_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        lines = content.split('\n')
        i = 0
        while i < len(lines):
            line_strip = lines[i].strip()
            
            if line_strip.startswith('param '):
                # Look back for decorators (@allowed, @description, @minLength, etc.)
                allowed_values = []
                description = ""
                min_length = None
                max_length = None
                min_value = None
                max_value = None
                
                # Collect decorators by scanning backward from param line
                j = i - 1
                decorator_lines = []
                while j >= 0:
                    prev_line = lines[j].strip()
                    if not prev_line or prev_line.startswith('//'):
                        j -= 1
                        continue
                    if prev_line.startswith('@') or prev_line.startswith("'") or prev_line == '])':
                        decorator_lines.insert(0, (j, prev_line))
                        j -= 1
                    else:
                        break
                
                # Parse the collected decorator block
                full_block = '\n'.join([l for _, l in decorator_lines])
                
                # Parse @description
                desc_match = re.search(r"@description\('(.+?)'\)", full_block)
                if desc_match:
                    description = desc_match.group(1)
                
                # Parse @minLength
                ml_match = re.search(r"@minLength\((\d+)\)", full_block)
                if ml_match:
                    min_length = int(ml_match.group(1))
                
                # Parse @maxLength
                xl_match = re.search(r"@maxLength\((\d+)\)", full_block)
                if xl_match:
                    max_length = int(xl_match.group(1))
                
                # Parse @minValue
                mv_match = re.search(r"@minValue\((\d+)\)", full_block)
                if mv_match:
                    min_value = int(mv_match.group(1))
                
                # Parse @maxValue
                xv_match = re.search(r"@maxValue\((\d+)\)", full_block)
                if xv_match:
                    max_value = int(xv_match.group(1))
                
                # Parse @allowed - multi-line block
                if '@allowed([' in full_block:
                    values_match = re.findall(r"'([^']+)'", full_block[full_block.index('@allowed(['):])
                    if values_match:
                        allowed_values = values_match
                
                m = re.match(r"param\s+(\w+)\s+[^=\n]+(?:=\s*(.+))?", line_strip)
                if m:
                    name = m.group(1)
                    default_raw = m.group(2).strip() if m.group(2) else None
                    required = default_raw is None
                    params[name] = (required, default_raw)
                    
                    # Store extended metadata
                    PARAM_METADATA[name] = {
                        'allowed': allowed_values,
                        'description': description,
                        'min_length': min_length,
                        'max_length': max_length,
                        'min_value': min_value,
                        'max_value': max_value,
                    }
            i += 1
    except Exception:
        pass
    return params


# Global metadata storage for parameter constraints parsed from Bicep templates
PARAM_METADATA: Dict[str, dict] = {}


def validate_bicep_parameters(resource_type: str, provided: Dict[str, str]) -> Tuple[bool, str, Dict[str, Tuple[bool, Optional[str]]]]:
    """Validate provided parameters against bicep template requirements.
    
    Checks:
    1. All required parameters are present
    2. Values match @allowed constraints if defined
    3. String lengths match @minLength/@maxLength
    4. Numeric values match @minValue/@maxValue
    """
    if resource_type not in TEMPLATE_MAP:
        return False, f"Unknown resource_type '{resource_type}'.", {}
    template_path = get_template_path(TEMPLATE_MAP[resource_type])
    if not os.path.exists(template_path):
        return False, f"Template not found at {template_path}", {}
    params = parse_bicep_parameters(template_path)
    
    auto_calculated = []
    # Fabric capacity location is auto-detected from tenant region
    if resource_type == "fabric-capacity":
        auto_calculated.append("location")
    
    missing = [p for p, (req, _) in params.items() if req and p not in auto_calculated and (p not in provided or provided[p] in (None, ""))]
    if missing:
        return False, f"Missing required parameters: {', '.join(missing)}", params
    
    # Validate @allowed values
    invalid_values = []
    for param_name, value in provided.items():
        if param_name in PARAM_METADATA and value not in (None, ""):
            meta = PARAM_METADATA[param_name]
            allowed = meta.get('allowed', [])
            if allowed and str(value).strip("'\"") not in allowed:
                invalid_values.append(
                    f"  - {param_name}: '{value}' is not valid. Allowed values: {', '.join(allowed)}"
                )
    
    if invalid_values:
        return False, "Invalid parameter values:\n" + "\n".join(invalid_values), params
    
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
    
    # NOTE: Subnet parameters (subnetStartingAddress, subnetSize) must be provided by the user
    # No auto-calculation - user must specify IP address pool and size
    
    # Build parameters string for PowerShell
    # Filter out empty/None values so Bicep template defaults are used
    filtered_params = {k: v for k, v in parameters.items() if v not in (None, "", "''", '""')}
    param_string = ";".join([f"{k}={v}" for k, v in filtered_params.items()]) if filtered_params else ""
    
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
            output_lines = []
            output_lines.append("")
            output_lines.append("Running post-deployment tasks for Function App...")
            
            function_app_name = parameters.get("functionAppName", "")
            storage_account_name = parameters.get("storageAccountName", "")
            uami_name = parameters.get("uamiName", "")
            
            # Get UAMI Principal ID via CLI
            uami_principal_id = ""
            if uami_name:
                try:
                    uami_cmd = [
                        "az", "identity", "show",
                        "-n", uami_name,
                        "-g", resource_group,
                        "--query", "principalId",
                        "-o", "tsv"
                    ]
                    uami_principal_id = run_command(uami_cmd).strip()
                    if "ERROR" in uami_principal_id or "error" in uami_principal_id.lower():
                        uami_principal_id = ""
                except Exception:
                    pass
            
            # Create ADLS containers via PowerShell script
            if storage_account_name:
                container_script = OP_SCRIPTS.get("create-funcapp-containers")
                if container_script:
                    container_script_path = os.path.join(os.path.dirname(__file__), "scripts", container_script)
                    container_cmd = [
                        "powershell.exe", "-ExecutionPolicy", "Bypass", "-File",
                        container_script_path,
                        "-StorageAccountName", storage_account_name,
                        "-ResourceGroup", resource_group
                    ]
                    container_result = run_command(container_cmd)
                    output_lines.append(container_result)
            
            # Store principal IDs for format_deployment_details
            parameters["_uamiPrincipalId"] = uami_principal_id
            
            output = output_lines + [format_deployment_details(resource_type, resource_group, parameters)]
        
        else:
            output = [format_deployment_details(resource_type, resource_group, parameters)]
        
        resource_id = get_resource_id(resource_group, resource_type, parameters)
        
        # NSP compliance prompt
        if resource_type in NSP_MANDATORY_RESOURCES:
            output.append("\n" + "─" * 70)
            output.append("")
            output.append("Compliance Requirement")
            output.append("═" * 70)
            output.append("")
            output.append("This resource requires NSP attachment for:")
            output.append("   - Secure PaaS Resources - Network Isolation")
            output.append("")
            output.append("═" * 70)
            output.append("")
            output.append("Do you want to attach this resource to NSP?")
            output.append("")
            output.append("   Type 'yes' or 'attach to NSP' to proceed")
            output.append("   Type 'no' to skip (not recommended - resource will not be compliant)")
            output.append("")
            output.append("Automated workflow will:")
            output.append("   1. Check if NSP exists in the resource group")
            output.append("   2. Create NSP if it doesn't exist (skip if exists)")
            output.append("   3. Attach the resource to the NSP")
            output.append("")
        
        # Log Analytics compliance prompt
        if resource_type in LOG_ANALYTICS_MANDATORY_RESOURCES:
            output.append("\n" + "═" * 70)
            output.append("Compliance Requirement")
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
            output.append("   1. Check if Log Analytics Workspace exists in the resource group")
            output.append("   2. Create workspace if it doesn't exist (skip if exists)")
            output.append("   3. Configure diagnostic settings for the resource")
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
