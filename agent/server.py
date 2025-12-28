# ============================================================================
# IMPORTS
# ============================================================================

from mcp.server.fastmcp import FastMCP
import subprocess
import os
import re
import shutil
import json
import time
from typing import Dict, Tuple, Optional, Union, Any

# ============================================================================
# CONSTANTS - Error Detection
# ============================================================================

# Keywords that indicate deployment/operation failures
ERROR_KEYWORDS = ["Error", "error", "FAILED", "Failed", "failed"]

# Keywords that indicate successful operations
SUCCESS_KEYWORDS = ["succeeded", "Succeeded", "SUCCESS", "completed"]

# ============================================================================
# MCP SERVER INITIALIZATION
# ============================================================================

# Initialize the server
mcp = FastMCP("azure-agent")

# --- INSTRUCTIONS LOADING ---
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

def get_action_menu() -> str:
    return (
        "Available actions:\n"
        "1. List all active permissions (Live Fetch)\n"
        "2. List all accessible resources (optional resource group)\n"
        "3. Create resource group (requires: name, region, project name)\n"
        "4. Create Azure resources with customazuremcpagent compliance\n"
        "   Usage: create_azure_resource(resource_type, resource_group, **parameters)\n"
        "   \n"
        "   Interactive workflow:\n"
        "   - Call with resource_type (e.g., 'storage-account')\n"
        "   - Agent will ask for missing required parameters\n"
        "   - Provide parameters when prompted\n"
        "   - Agent deploys resource\n"
        "   \n"
        "   Supported types: storage-account | key-vault | openai | ai-search | ai-foundry | cosmos-db | container-registry | log-analytics | fabric-capacity | uami | nsp\n"
        "\n"
        "5. NSP Management (Manual)\n"
        "   - check_nsp_in_resource_group(resource_group) - Check for existing NSP\n"
        "   - create_azure_resource('nsp', resource_group, parameters) - Create new NSP\n"
        "   - attach_resource_to_nsp(resource_group, nsp_name, resource_id) - Attach resource to NSP\n"
        "   Note: If multiple NSPs exist, you'll be prompted to choose one\n"
        "\n"
        "6. Log Analytics Management (Manual)\n"
        "   - check_log_analytics_in_resource_group(resource_group) - Check for existing workspace\n"
        "   - create_azure_resource('log-analytics', resource_group, parameters) - Create new workspace\n"
        "   - attach_diagnostic_settings(resource_group, workspace_id, resource_id) - Attach diagnostic settings\n"
        "   Note: If multiple workspaces exist, you'll be prompted to choose one"
    )

GREETING_PATTERN = re.compile(r"\b(hi|hello|hey|greetings|good (morning|afternoon|evening))\b", re.IGNORECASE)

def is_greeting(text: str) -> bool:
    return bool(GREETING_PATTERN.search(text))

def normalize(text: str) -> str:
    return text.lower().strip()

# ============================================================================
# CONFIGURATION CONSTANTS
# ============================================================================

# Resources that should be attached to NSP (suggestion will be provided after creation)
NSP_MANDATORY_RESOURCES = [
    "storage-account", # ADLS is usually a storage account with HNS enabled
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
    "openai",
    "synapse",
    "data-factory",
    "ai-hub",
    "ai-project",
    "ai-foundry",
    "ai-services",
    "ai-search",
    "front-door",
    "virtual-machine",
    "redis-cache",
    "redis-enterprise",
    "container-registry"
]

# Bicep Templates (All deployments MUST go through MCP server for compliance orchestration)
# Added Cosmos and SQL support
TEMPLATE_MAP = {
    "storage-account": "templates/storage-account.bicep",
    "key-vault": "templates/azure-key-vaults.bicep",
    "openai": "templates/azure-openai.bicep",
    "ai-search": "templates/ai-search.bicep",
    "ai-foundry": "templates/ai-foundry.bicep",
    "cosmos-db": "templates/cosmos-db.bicep",
    "log-analytics": "templates/log-analytics.bicep",
    "uami": "templates/user-assigned-managed-identity.bicep",
    "nsp": "templates/nsp.bicep",
    "fabric-capacity": "templates/fabric-capacity.bicep",
    "container-registry": "templates/container-registry.bicep",
}

# Resource Type to Azure Provider mapping for azure_check_resource and resource ID lookup
RESOURCE_TYPE_PROVIDER_MAP = {
    "nsp": "Microsoft.Network/networkSecurityPerimeters",
    "log-analytics": "Microsoft.OperationalInsights/workspaces",
    "storage-account": "Microsoft.Storage/storageAccounts",
    "key-vault": "Microsoft.KeyVault/vaults",
    "openai": "Microsoft.CognitiveServices/accounts",
    "ai-search": "Microsoft.Search/searchServices",
    "ai-foundry": "Microsoft.CognitiveServices/accounts",
    "ai-services": "Microsoft.CognitiveServices/accounts",
    "ai-hub": "Microsoft.MachineLearningServices/workspaces",
    "ai-project": "Microsoft.MachineLearningServices/workspaces",
    "cosmos-db": "Microsoft.DocumentDB/databaseAccounts",
    "sql-db": "Microsoft.Sql/servers",
    "fabric-capacity": "Microsoft.Fabric/capacities",
    "uami": "Microsoft.ManagedIdentity/userAssignedIdentities",
    "container-registry": "Microsoft.ContainerRegistry/registries",
    "logic-app": "Microsoft.Logic/workflows",
    "function-app": "Microsoft.Web/sites",
    "app-service": "Microsoft.Web/sites",
    "synapse": "Microsoft.Synapse/workspaces",
    "data-factory": "Microsoft.DataFactory/factories",
    "front-door": "Microsoft.Network/frontDoors",
    "virtual-machine": "Microsoft.Compute/virtualMachines",
    "redis-cache": "Microsoft.Cache/redis",
    "redis-enterprise": "Microsoft.Cache/redisEnterprise",
}

# Pipeline YAML Templates
# Maps pipeline types to YAML template files
# Non-1ES = dev/non-prod, 1ES = prod
PIPELINE_TEMPLATE_MAP = {
    "credscan": "templates/credscan_Pipeline.yml",           # Dev/Non-Prod
    "credscan-1es": "templates/credscan_1ES_Pipeline.yml",  # Prod (1ES)
}

# Pipeline type keywords for auto-detection
PIPELINE_TYPE_KEYWORDS = {
    "1es": "credscan-1es",
    "prod": "credscan-1es",
    "production": "credscan-1es",
    "credscan": "credscan",
}

# 3. Operational Scripts (Permissions/Listings)
OP_SCRIPTS = {
    "permissions": "list-azure-permissions.ps1",
    "resources": "list-resources.ps1",
    "create-rg": "create-resourcegroup.ps1",
    "deploy-bicep": "deploy-bicep.ps1"
}

# ============================================================================
# HELPER FUNCTIONS - Command Execution
# ============================================================================

def run_command(command: list[str]) -> str:
    """Generic command runner."""
    try:
        result = subprocess.run(
            command,
            shell=False, 
            capture_output=True,
            text=True,
            encoding='utf-8',
            check=False,
            stdin=subprocess.DEVNULL,  # Prevents hanging on prompts
            timeout=120
        )
        return result.stdout
    except subprocess.TimeoutExpired:
        return f"Error: Command timed out after 120 seconds"
    except Exception as e:
        return f"Error running command {' '.join(command)}: {str(e)}"

# ============================================================================
# HELPER FUNCTIONS - File System
# ============================================================================

def _get_script_path(script_name: str) -> str:
    """Locates the script in the 'scripts' folder."""
    current_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(current_dir, "scripts", script_name)

def _get_template_path(template_rel: str) -> str:
    """Locates the bicep file relative to server file."""
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), template_rel)

def _detect_pipeline_type(pipeline_name: str, user_input: str = "") -> str:
    """
    Detects pipeline type based on pipeline name and user input.
    Returns the template key from PIPELINE_TEMPLATE_MAP.
    """
    combined = f"{pipeline_name} {user_input}".lower()
    
    # Check for specific keywords
    for keyword, pipeline_type in PIPELINE_TYPE_KEYWORDS.items():
        if keyword in combined:
            return pipeline_type
    
    # Default to regular credscan
    return "credscan"

def _get_pipeline_template(pipeline_type: str) -> str:
    """
    Gets the pipeline template path for a given pipeline type.
    Falls back to available template if requested type doesn't exist.
    Returns the full path to the YAML template file.
    """
    # Try requested type first
    if pipeline_type in PIPELINE_TEMPLATE_MAP:
        template_rel = PIPELINE_TEMPLATE_MAP[pipeline_type]
        template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), template_rel)
        if os.path.exists(template_path):
            return template_path
    
    # Fallback: try alternate type (1ES <-> non-1ES)
    alternate_type = "credscan" if "1es" in pipeline_type else "credscan-1es"
    if alternate_type in PIPELINE_TEMPLATE_MAP:
        template_rel = PIPELINE_TEMPLATE_MAP[alternate_type]
        template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), template_rel)
        if os.path.exists(template_path):
            return template_path
    
    # Last resort: return first available template
    for template_rel in PIPELINE_TEMPLATE_MAP.values():
        template_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), template_rel)
        if os.path.exists(template_path):
            return template_path
    
    return None

# ============================================================================
# HELPER FUNCTIONS - Azure Resources
# ============================================================================

def _get_rg_location(resource_group: str) -> str:
    """Fetches location of the resource group."""
    try:
        res = run_command(["az", "group", "show", "-n", resource_group, "--query", "location", "-o", "tsv"])
        return res.strip()
    except:
        return "eastus" # Fallback

def _get_resource_id(resource_group: str, resource_type: str, parameters: Dict[str, str]) -> Optional[str]:
    """
    Attempts to find the Resource ID based on parameters provided during creation.
    We look for common naming parameter keys.
    """
    # Common parameter names for resource names in Bicep templates
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
            
    # If we couldn't find a specific name, we might check the deployment output, 
    # but for now, we fail gracefully if we can't identify the resource name.
    if not resource_name:
        return None

    # Use the global RESOURCE_TYPE_PROVIDER_MAP
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

def _format_deployment_details(resource_type: str, resource_group: str, parameters: Dict[str, str]) -> str:
    """Format deployment details in a user-friendly way based on resource type."""
    details = []
    details.append("═" * 70)
    details.append("✅ DEPLOYMENT SUCCESSFUL")
    details.append("═" * 70)
    details.append("")
    details.append("📦 Deployment Details:")
    details.append("")
    
    # Common details for all resources
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
    
    else:
        # Generic fallback for other resources
        # Try to find resource name from common parameter names
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

def _parse_bicep_parameters(template_path: str) -> Dict[str, Tuple[bool, Optional[str]]]:
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

def _validate_bicep_parameters(resource_type: str, provided: Dict[str, str]) -> Tuple[bool, str, Dict[str, Tuple[bool, Optional[str]]]]:
    if resource_type not in TEMPLATE_MAP:
        return False, f"Unknown resource_type '{resource_type}'.", {}
    template_path = _get_template_path(TEMPLATE_MAP[resource_type])
    if not os.path.exists(template_path):
        return False, f"Template not found at {template_path}", {}
    params = _parse_bicep_parameters(template_path)
    missing = [p for p, (req, _) in params.items() if req and (p not in provided or provided[p] in (None, ""))]
    if missing:
        return False, f"Missing required parameters: {', '.join(missing)}", params
    return True, "OK", params

def _deploy_bicep(resource_group: str, resource_type: str, parameters: Dict[str,str]) -> str:
    if resource_type not in TEMPLATE_MAP:
        return f"Unknown resource_type '{resource_type}'."
    template_path = _get_template_path(TEMPLATE_MAP[resource_type])
    if not os.path.exists(template_path):
        return f"Template not found: {template_path}"
    
    # Normalize case-sensitive parameters for storage accounts
    if resource_type == "storage-account" and "accessTier" in parameters:
        # Bicep/Azure expects capitalized: Hot, Cool, Cold
        parameters["accessTier"] = parameters["accessTier"].lower().capitalize()
    
    # Build parameters string for PowerShell (semicolon-separated key=value pairs)
    param_string = ";".join([f"{k}={v}" for k, v in parameters.items()]) if parameters else ""
    
    # Call deploy-bicep.ps1 script
    script_name = OP_SCRIPTS["deploy-bicep"]
    script_path = _get_script_path(script_name)
    
    if not os.path.exists(script_path):
        return f"Error: Script '{script_name}' not found at {script_path}"
    
    script_params = {
        "ResourceGroup": resource_group,
        "TemplatePath": template_path
    }
    
    if param_string:
        script_params["Parameters"] = param_string
    
    deploy_result = _run_powershell_script(script_path, script_params)
    
    # Check if deployment was successful by looking for provisioningState: Succeeded
    # Avoid false positives from JSON field names like "error" or "onErrorDeployment"
    deployment_successful = (
        '"provisioningState": "Succeeded"' in deploy_result or
        "'provisioningState': 'Succeeded'" in deploy_result or
        "Succeeded" in deploy_result
    ) and "Failed" not in deploy_result
    
    if deployment_successful:
        # Format deployment details
        output = [_format_deployment_details(resource_type, resource_group, parameters)]
        
        # Get resource ID for suggestions
        resource_id = _get_resource_id(resource_group, resource_type, parameters)
        
        # Check if NSP attachment is required
        if resource_type in NSP_MANDATORY_RESOURCES:
            output.append("\n" + "─" * 70)
            output.append("")
            output.append("⚠️  COMPLIANCE REQUIREMENT")
            output.append("═" * 70)
            output.append("")
            output.append("This resource requires NSP attachment to resolve:")
            output.append("   📋 [customazuremcpagent-NS2.2.1] Secure PaaS Resources")
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
        
        # Check if Log Analytics attachment is required
        if resource_type in LOG_ANALYTICS_MANDATORY_RESOURCES:
            output.append("\n" + "═" * 70)
            output.append("⚠️  COMPLIANCE REQUIREMENT")
            output.append("═" * 70)
            output.append("")
            output.append("This resource requires Log Analytics diagnostic settings to resolve:")
            output.append("   📋 [customazuremcpagent-Monitoring] Resource Monitoring & Compliance")
            output.append("")
            output.append("═" * 70)
            output.append("")
            output.append("📊 Do you want to configure Log Analytics for this resource?")
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

def _run_powershell_script(script_path: str, parameters: dict) -> str:
    ps_executable = "pwsh" if shutil.which("pwsh") else "powershell"
    cmd = [ps_executable, "-File", script_path]
    for k, v in parameters.items():
        if v is not None and v != "":
            cmd.append(f"-{k}")
            cmd.append(str(v))
    return run_command(cmd)

# --- INTENT PARSING ---

def parse_intent(text: str) -> str:
    t = normalize(text)
    if is_greeting(t): return "greeting"
    if any(k in t for k in ["menu", "help", "options"]): return "menu"
    if any(k in t for k in ["list permissions", "show permissions", "check permissions"]): return "permissions"
    if "list resources" in t or "show resources" in t or re.search(r"resources in", t): return "resources"
    if any(k in t for k in ["create rg", "create resource group", "new rg", "new resource group"]): return "create-rg"
    if any(k in t for k in ["create", "deploy", "provision"]): return "create"
    return "unknown"

def extract_resource_group(text: str) -> Optional[str]:
    m = re.search(r"resources in ([A-Za-z0-9-_\.]+)", text, re.IGNORECASE)
    return m.group(1) if m else None

# --- TOOLS ---
@mcp.tool()
def azure_list_permissions(user_principal_name: str = None, force_refresh: bool = True) -> str:
    """
    Lists active Azure RBAC role assignments for resources and subscriptions.
    
    USE THIS TOOL when user asks to "list permissions" or "show permissions" without specifying the platform.
    This is the DEFAULT permission listing tool.
    
    Uses force_refresh=True by default to ensure recent role activations are captured.
    
    Args:
        user_principal_name: Optional user email. Defaults to current logged-in user.
        force_refresh: Whether to force refresh the role cache. Default is True.
    
    Returns:
        Table of Azure role assignments (Reader, Contributor, Owner, etc.)
    """
    script_name = OP_SCRIPTS["permissions"]
    script_path = _get_script_path(script_name)
    
    if not os.path.exists(script_path):
        return f"Error: Script '{script_name}' not found."

    params = {}
    if user_principal_name:
        params["UserPrincipalName"] = user_principal_name
    
    # Note: The subprocess call itself ensures a new process is spawned, 
    # preventing variable caching in Python. 
    return _run_powershell_script(script_path, params)

@mcp.tool()
def azure_list_resources(resource_group_name: str = None) -> str:
    """
    Lists Azure resources (all resources or filtered by resource group).
    
    Args:
        resource_group_name: Optional resource group name to filter resources.
    
    Returns:
        Table of Azure resources with name, type, location, and resource group
    """
    script_name = OP_SCRIPTS["resources"]
    script_path = _get_script_path(script_name)
    if not os.path.exists(script_path): return f"Error: Script '{script_name}' not found."
    params = {}
    if resource_group_name: params["ResourceGroup"] = resource_group_name
    return _run_powershell_script(script_path, params)

@mcp.tool()
def fabric_list_permissions(user_principal_name: str = None) -> str:
    """
    Lists Microsoft Fabric workspace permissions for the current user.
    
    USE THIS TOOL ONLY when user specifically asks for "Fabric permissions" or "Fabric workspace access".
    DO NOT use for generic "list permissions" requests.
    
    Shows workspace name, role (Admin/Contributor/Member/Viewer), and access method (direct or via group).
    
    Args:
        user_principal_name: Optional user email. Defaults to current logged-in user.
    
    Returns:
        List of Fabric workspaces with permission levels and access method
    """
    script_path = _get_script_path("list-fabric-permissions.ps1")
    if not os.path.exists(script_path):
        return "Error: list-fabric-permissions.ps1 not found"
    
    params = {}
    if user_principal_name:
        params["UserPrincipalName"] = user_principal_name
    
    try:
        return _run_powershell_script(script_path, params)
    except Exception as e:
        return f"✗ Failed to list Fabric permissions: {e}"

@mcp.tool()
def azure_create_resource_group(resource_group_name: str, region: str, project_name: str) -> str:
    """Creates an Azure resource group with project tagging."""
    if not resource_group_name or not region or not project_name:
        return "Error: All parameters (resource_group_name, region, project_name) are required."
    
    script_name = OP_SCRIPTS["create-rg"]
    script_path = _get_script_path(script_name)
    if not os.path.exists(script_path): 
        return f"Error: Script '{script_name}' not found."
    
    params = {
        "ResourceGroupName": resource_group_name,
        "Region": region,
        "ProjectName": project_name
    }
    return _run_powershell_script(script_path, params)

# ============================================================================
# MCP TOOLS - Azure Compliance (NSP)
# ============================================================================

@mcp.tool()
def azure_check_resource(resource_group: str, resource_type: str) -> str:
    """
    Checks for specific resource types in a resource group.
    Returns a list of resources found, or indicates if none exist.
    
    Args:
        resource_group: Resource group name to check
        resource_type: Type of resource to check (nsp, log-analytics, storage-account, key-vault, openai, ai-search, cosmos-db, sql-db, fabric-capacity, uami)
    
    Returns:
        JSON string with resource information
    """
    if not resource_group or not resource_group.strip():
        return json.dumps({"error": "Resource group name is required"})
    
    resource_type = resource_type.lower().strip()
    if resource_type not in RESOURCE_TYPE_PROVIDER_MAP:
        supported_types = ', '.join(sorted(RESOURCE_TYPE_PROVIDER_MAP.keys()))
        return json.dumps({"error": f"Invalid resource_type. Supported: {supported_types}"})
    
    ps_executable = "pwsh" if shutil.which("pwsh") else "powershell"
    script_path = _get_script_path("check-resource.ps1")
    
    if not os.path.exists(script_path):
        return json.dumps({"error": "check-resource.ps1 script not found"})
    
    # Get provider type from map
    provider_type = RESOURCE_TYPE_PROVIDER_MAP[resource_type]
    
    result = run_command([
        ps_executable, "-File", script_path,
        "-ResourceGroupName", resource_group,
        "-ResourceType", resource_type,
        "-ProviderType", provider_type
    ])
    
    # Parse unified output format
    if "RESOURCE NOT FOUND" in result:
        return json.dumps({
            "count": 0,
            "resources": [],
            "message": f"No {resource_type} found in resource group '{resource_group}'"
        })
    
    # Extract resource information
    resource_names = []
    resource_ids = []
    count = 1
    
    # Parse RESOURCE FOUND line
    found_match = re.search(r'RESOURCE FOUND:\s*(.+)', result)
    if found_match:
        resource_names.append(found_match.group(1).strip())
    
    # Parse RESOURCE ID line
    id_match = re.search(r'RESOURCE ID:\s*(.+)', result)
    if id_match:
        resource_ids.append(id_match.group(1).strip())
    
    # Parse COUNT line
    count_match = re.search(r'COUNT:\s*(\d+)', result)
    if count_match:
        count = int(count_match.group(1))
    
    # Check for multiple resources
    if "MULTIPLE RESOURCES FOUND" in result:
        # Parse additional resources from output
        for line in result.split('\n'):
            if line.strip().startswith('- Name:'):
                name_match = re.search(r'Name:\s*([^,]+)', line)
                id_match_line = re.search(r'ID:\s*(.+)', line)
                if name_match:
                    name = name_match.group(1).strip()
                    if name not in resource_names:
                        resource_names.append(name)
                    if id_match_line:
                        resource_ids.append(id_match_line.group(1).strip())
        
        return json.dumps({
            "count": count,
            "resources": [{"name": name, "id": rid} for name, rid in zip(resource_names, resource_ids)] if resource_ids else [{"name": name} for name in resource_names],
            "message": f"Found {count} {resource_type} resource(s) in '{resource_group}'",
            "requires_selection": True if count > 1 else False,
            "prompt": "Multiple resources detected. Please specify which one to use." if count > 1 else None
        })
    
    # Single resource found
    if resource_names:
        return json.dumps({
            "count": len(resource_names),
            "resources": [{"name": name, "id": rid} for name, rid in zip(resource_names, resource_ids)] if resource_ids else [{"name": name} for name in resource_names],
            "message": f"Found {len(resource_names)} {resource_type} resource(s) in '{resource_group}'"
        })
    
    return json.dumps({
        "count": 0,
        "resources": [],
        "raw_output": result,
        "message": f"Could not parse {resource_type} information from output"
    })

@mcp.tool()
def azure_attach_to_nsp(resource_group: str, nsp_name: str = None, resource_id: str = None) -> str:
    """
    Attaches a resource to a Network Security Perimeter (NSP) with automatic NSP management.
    This resolves compliance requirement [customazuremcpagent-NS2.2.1] Secure PaaS Resources.
    
    Workflow (strictly followed):
    1. Check if NSP exists in the resource group
    2. Create NSP if it doesn't exist (skip if exists)
    3. Attach resource to NSP
    
    IMPORTANT: Only call this tool when:
    - User explicitly confirms the NSP attachment prompt (affirmative response), OR
    - User directly requests to attach a resource to NSP
    
    Do NOT call automatically after deployment without user interaction.
    
    Args:
        resource_group: Resource group name
        nsp_name: Name of the NSP to attach to (optional - will use existing or create with standard name)
        resource_id: Full resource ID of the resource to attach
    
    Returns:
        Attachment result message with workflow steps
    """
    if not resource_group or not resource_group.strip():
        return "Error: Resource group name is required"
    
    if not resource_id or not resource_id.strip():
        return "Error: Resource ID is required"
    
    output = []
    output.append("🔒 Starting NSP Attachment Workflow")
    output.append("=" * 70)
    output.append("")
    
    # Step 1: Check if NSP exists
    output.append("Step 1/3: Checking for existing NSP in resource group...")
    check_result = azure_check_resource(resource_group, "nsp")
    
    try:
        check_data = json.loads(check_result)
    except:
        return f"Error: Failed to parse NSP check result:\n{check_result}"
    
    # Step 2: Create NSP if it doesn't exist, or use existing one
    if check_data.get("count", 0) == 0:
        output.append("   → No NSP found")
        output.append("")
        output.append("Step 2/3: Creating NSP...")
        
        # Create NSP with standard naming: {resource-group}-nsp
        nsp_name = nsp_name or f"{resource_group}-nsp"
        create_params = json.dumps({
            "nspName": nsp_name,
            "location": "eastus"  # Default location, could be made dynamic
        })
        
        create_result = azure_create_resource("nsp", resource_group, create_params)
        
        if any(err in create_result.lower() for err in ERROR_KEYWORDS):
            return "\n".join(output) + f"\n\n✗ Failed to create NSP:\n{create_result}"
        
        output.append(f"   → NSP '{nsp_name}' created successfully")
    else:
        # NSP exists - use it
        resources = check_data.get("resources", [])
        if not resources:
            return "\n".join(output) + "\n\n✗ Error: NSP check returned invalid data"
        
        # Use provided nsp_name or the first found NSP
        if not nsp_name:
            nsp_name = resources[0].get("name")
        
        output.append(f"   → Found existing NSP: '{nsp_name}'")
        output.append("")
        output.append("Step 2/3: Skipping NSP creation (already exists)")
    
    output.append("")
    output.append("Step 3/3: Attaching resource to NSP...")
    
    # Step 3: Attach resource to NSP
    ps_executable = "pwsh" if shutil.which("pwsh") else "powershell"
    attach_nsp_script = _get_script_path("attach-nsp.ps1")
    
    if not os.path.exists(attach_nsp_script):
        return "\n".join(output) + "\n\n✗ Error: attach-nsp.ps1 script not found"
    
    result = run_command([
        ps_executable, "-File", attach_nsp_script,
        "-ResourceGroupName", resource_group,
        "-NSPName", nsp_name,
        "-ResourceId", resource_id
    ])
    
    if any(err in result for err in ERROR_KEYWORDS):
        output.append(f"   ✗ Failed to attach resource to NSP '{nsp_name}'")
        output.append("")
        output.append("=" * 70)
        output.append("Error Details:")
        output.append(result)
        return "\n".join(output)
    
    output.append(f"   → Resource attached to NSP '{nsp_name}' successfully")
    output.append("")
    output.append("=" * 70)
    output.append("✓ WORKFLOW COMPLETED")
    output.append("")
    output.append(f"[customazuremcpagent-NS2.2.1] Compliance requirement resolved.")
    output.append("")
    output.append("Summary:")
    output.append(f"   • Resource Group: {resource_group}")
    output.append(f"   • NSP Name: {nsp_name}")
    output.append(f"   • Resource attached and secured")
    
    return "\n".join(output)

@mcp.tool()
def azure_attach_diagnostic_settings(resource_group: str, workspace_id: str = None, resource_id: str = None) -> str:
    """
    Attaches diagnostic settings to a resource with automatic Log Analytics Workspace management.
    This resolves compliance requirement [customazuremcpagent-Monitoring] Resource Monitoring & Compliance.
    
    Workflow (strictly followed):
    1. Check if Log Analytics Workspace exists in the resource group
    2. Create workspace if it doesn't exist (skip if exists)
    3. Attach diagnostic settings to the resource
    
    IMPORTANT: Only call this tool when:
    - User explicitly confirms the Log Analytics attachment prompt, OR
    - User directly requests to configure Log Analytics for a resource
    
    Do NOT call automatically after deployment without user interaction.
    
    Args:
        resource_group: Resource group name
        workspace_id: Full resource ID of the Log Analytics Workspace (optional - will use existing or create with standard name)
        resource_id: Full resource ID of the resource to attach diagnostic settings to
    
    Returns:
        Configuration result message with workflow steps
    """
    if not resource_group or not resource_group.strip():
        return "Error: Resource group name is required"
    
    if not resource_id or not resource_id.strip():
        return "Error: Resource ID is required"
    
    output = []
    output.append("📊 Starting Log Analytics Configuration Workflow")
    output.append("=" * 70)
    output.append("")
    
    # Step 1: Check if Log Analytics Workspace exists
    output.append("Step 1/3: Checking for existing Log Analytics Workspace...")
    check_result = azure_check_resource(resource_group, "log-analytics")
    
    try:
        check_data = json.loads(check_result)
    except:
        return f"Error: Failed to parse Log Analytics check result:\n{check_result}"
    
    # Step 2: Create workspace if it doesn't exist, or use existing one
    if check_data.get("count", 0) == 0:
        output.append("   → No Log Analytics Workspace found")
        output.append("")
        output.append("Step 2/3: Creating Log Analytics Workspace...")
        
        # Create workspace with standard naming: {resource-group}-law
        workspace_name = f"{resource_group}-law"
        create_params = json.dumps({
            "workspaceName": workspace_name,
            "location": "eastus"  # Default location, could be made dynamic
        })
        
        create_result = azure_create_resource("log-analytics", resource_group, create_params)
        
        if any(err in create_result.lower() for err in ERROR_KEYWORDS):
            return "\n".join(output) + f"\n\n✗ Failed to create Log Analytics Workspace:\n{create_result}"
        
        output.append(f"   → Log Analytics Workspace '{workspace_name}' created successfully")
        
        # Get the workspace ID from the newly created workspace
        check_result_new = azure_check_resource(resource_group, "log-analytics")
        try:
            check_data_new = json.loads(check_result_new)
            resources_new = check_data_new.get("resources", [])
            if resources_new:
                workspace_id = resources_new[0].get("id")
        except:
            return "\n".join(output) + "\n\n✗ Error: Could not retrieve workspace ID after creation"
    else:
        # Workspace exists - use it
        resources = check_data.get("resources", [])
        if not resources:
            return "\n".join(output) + "\n\n✗ Error: Log Analytics check returned invalid data"
        
        # Use provided workspace_id or the first found workspace
        if not workspace_id:
            workspace_id = resources[0].get("id")
            workspace_name = resources[0].get("name")
        else:
            # Extract workspace name from ID if provided
            workspace_name = workspace_id.split("/")[-1] if "/" in workspace_id else workspace_id
        
        output.append(f"   → Found existing Log Analytics Workspace: '{workspace_name}'")
        output.append("")
        output.append("Step 2/3: Skipping workspace creation (already exists)")
    
    output.append("")
    output.append("Step 3/3: Configuring diagnostic settings...")
    
    # Step 3: Attach diagnostic settings
    ps_executable = "pwsh" if shutil.which("pwsh") else "powershell"
    attach_law_script = _get_script_path("attach-log-analytics.ps1")
    
    if not os.path.exists(attach_law_script):
        return "\n".join(output) + "\n\n✗ Error: attach-log-analytics.ps1 script not found"
    
    result = run_command([
        ps_executable, "-File", attach_law_script,
        "-ResourceGroupName", resource_group,
        "-WorkspaceId", workspace_id,
        "-ResourceId", resource_id
    ])
    
    if any(err in result for err in ERROR_KEYWORDS):
        output.append(f"   ✗ Failed to configure diagnostic settings")
        output.append("")
        output.append("=" * 70)
        output.append("Error Details:")
        output.append(result)
        return "\n".join(output)
    
    output.append(f"   → Diagnostic settings configured successfully")
    output.append("")
    output.append("=" * 70)
    output.append("✓ WORKFLOW COMPLETED")
    output.append("")
    output.append(f"[customazuremcpagent-Monitoring] Compliance requirement resolved.")
    output.append("")
    output.append("Summary:")
    output.append(f"   • Resource Group: {resource_group}")
    output.append(f"   • Log Analytics Workspace: {workspace_name}")
    output.append(f"   • Diagnostic settings enabled and monitoring active")
    
    return "\n".join(output)

# ============================================================================
# MCP TOOLS - Azure Resource Management
# ============================================================================

@mcp.tool()
def azure_get_bicep_requirements(resource_type: str) -> str:
    """(Bicep Path) Returns required/optional params for a Bicep template."""
    if resource_type not in TEMPLATE_MAP:
        return f"Unknown resource_type. Valid: {', '.join(TEMPLATE_MAP.keys())}"
    template_path = _get_template_path(TEMPLATE_MAP[resource_type])
    params = _parse_bicep_parameters(template_path)
    structured = {
        "required": [p for p, (req, _) in params.items() if req],
        "optional": [p for p, (req, _) in params.items() if not req],
        "defaults": {p: default for p, (req, default) in params.items() if default is not None}
    }
    return json.dumps(structured, indent=2)

@mcp.tool()
def azure_create_resource(resource_type: str, resource_group: str = None, parameters: str = None) -> str:
    """
    Interactive Azure resource creation.
    
    Workflow:
    1. Validates resource type
    2. Requests missing required parameters from user
    3. Deploys resource using Bicep template
    
    Args:
        resource_type: Type of resource to create (storage-account, key-vault, openai, ai-search, ai-foundry, cosmos-db, sql-db, log-analytics)
        resource_group: Azure resource group name
        parameters: JSON string of resource-specific parameters (will prompt for missing required params)
    
    Returns:
        Deployment status
    """
    # Validate resource type
    if resource_type not in TEMPLATE_MAP:
        return f"Invalid resource type. Supported types:\n" + "\n".join([f"  - {rt}" for rt in TEMPLATE_MAP.keys()])
    
    # Parse parameters from JSON string if provided
    params_dict = {}
    if parameters:
        try:
            params_dict = json.loads(parameters)
        except json.JSONDecodeError:
            return f"Error: Invalid JSON in parameters. Please provide valid JSON format."
    
    # Get template requirements
    template_path = _get_template_path(TEMPLATE_MAP[resource_type])
    param_info = _parse_bicep_parameters(template_path)
    required_params = [p for p, (req, _) in param_info.items() if req]
    optional_params = [p for p, (req, _) in param_info.items() if not req]
    
    # Check for missing parameters
    missing_params = []
    if not resource_group or not resource_group.strip():
        missing_params.append("resource_group")
    
    for param in required_params:
        if param not in params_dict or not params_dict.get(param):
            missing_params.append(param)
    
    # If parameters are missing, provide interactive prompt
    if missing_params:
        response = [f"Creating {resource_type} - Please provide the following parameters:\n"]
        
        if "resource_group" in missing_params:
            response.append("  - resource_group: (Azure resource group name)")
        
        for param in [p for p in missing_params if p != "resource_group"]:
            default_val = param_info[param][1]
            if default_val:
                response.append(f"  - {param}: (default: {default_val})")
            else:
                response.append(f"  - {param}: (required)")
        
        if optional_params:
            response.append(f"\nOptional parameters: {', '.join(optional_params)}")
        
        response.append(f"\nOnce you provide these, I'll:\n")
        response.append(f"   1. Deploy the {resource_type}")
        
        return "\n".join(response)
    
    # All parameters provided - proceed with deployment
    return azure_deploy_bicep_resource(resource_group, resource_type, params_dict)

@mcp.tool()
def azure_deploy_bicep_resource(resource_group: str, resource_type: str, parameters: dict[str, str]) -> str:
    """
    Internal deployment function - validates and deploys a resource.
    
    Warning: Users should call create_azure_resource() instead for interactive parameter collection.
    
    This function:
    1. Validates all parameters against Bicep template
    2. Deploys the resource
    """
    # Strict validation - reject if resource_group or resource_type is empty
    if not resource_group or not resource_group.strip():
        return "STOP: Resource group name is required. Please provide the resource group name."
    
    if not resource_type or not resource_type.strip():
        return f"STOP: Resource type is required. Valid types: {', '.join(TEMPLATE_MAP.keys())}"
    
    # Validate parameters against template
    ok, msg, parsed_params = _validate_bicep_parameters(resource_type, parameters)
    if not ok:
        # Provide helpful message with requirement details
        req_params = [p for p, (req, _) in parsed_params.items() if req]
        return f"STOP: {msg}\n\nPlease call get_bicep_requirements('{resource_type}') to see all required parameters.\nRequired: {', '.join(req_params) if req_params else 'unknown'}"
    
    return _deploy_bicep(resource_group, resource_type, parameters)

@mcp.tool()
def agent_dispatch(user_input: str) -> str:
    """High-level dispatcher for conversational commands."""
    intent = parse_intent(user_input)
    if intent in ("greeting", "menu"): return get_action_menu()
    if intent == "permissions": return azure_list_permissions(force_refresh=True)
    if intent == "resources":
        rg = extract_resource_group(user_input)
        return azure_list_resources(rg) if rg else azure_list_resources()
    if intent == "create-rg":
        return (
            "Resource Group creation flow:\n\n"
            "Please provide:\n"
            "1. Resource Group Name\n"
            "2. Region (e.g., eastus, westus2, westeurope)\n"
            "3. Project Name (for tagging)\n\n"
            "Then call: azure_create_resource_group(resource_group_name, region, project_name)"
        )
    if intent == "create":
        return (
            "Azure Resource Creation (Interactive Mode)\n\n"
            "To create a resource, use: azure_create_resource(resource_type, ...)\n\n"
            "Example: azure_create_resource('storage-account')\n"
            "The agent will then ask you for required parameters interactively.\n\n"
            "Supported resource types:\n"
            "  - storage-account (ADLS Gen2 enabled by default)\n"
            "  - key-vault\n"
            "  - openai\n"
            "  - ai-search\n"
            "  - ai-foundry\n"
            "  - cosmos-db\n"
            "  - fabric-capacity\n"
            "  - nsp\n"
            "  - uami\n"
            "  - log-analytics\n\n"
            "Manual Compliance Tools:\n"
            "  NSP Management:\n"
            "    - azure_check_resource(rg, 'nsp') - Check for NSP\n"
            "    - azure_create_resource('nsp', ...) - Create NSP if doesn't exist\n"
            "    - azure_attach_to_nsp() - Attach resource to NSP\n"
            "  Log Analytics Management:\n"
            "    - azure_check_resource(rg, 'log-analytics') - Check for workspace\n"
            "    - azure_create_resource('log-analytics', ...) - Create workspace if doesn't exist\n"
            "    - azure_attach_diagnostic_settings() - Configure diagnostic settings\n\n"
            "Tip: You can provide all parameters at once if you know them:\n"
            "   azure_create_resource('storage-account', resource_group='my-rg', \n"
            "                        storageAccountName='mystg123', location='eastus', accessTier='Hot')"
        )
    return "Unrecognized command. " + get_action_menu()

@mcp.tool()
def show_agent_instructions() -> str:
    """
    Returns the complete agent instructions and capabilities documentation.
    Use this to understand the agent's features, supported resources, and operational guidelines.
    """
    return load_agent_instructions()

@mcp.tool()
def ado_create_project(organization: str = None, project_name: str = None, repo_name: str = None, description: str = None) -> str:
    """
    Creates an Azure DevOps project using AZ CLI via the PS1 script and sets the initial repo name.

    Behavior: Relies on the PS1 script output entirely (no extra verification).
    Required: organization (URL or org name), project_name, repo_name; description optional.
    """
    # Normalize organization to URL if just the org name is provided
    if organization and not organization.strip().lower().startswith("http"):
        organization = f"https://dev.azure.com/{organization.strip()}"

    missing = []
    if not organization or not organization.strip():
        missing.append("organization (existing org URL where you're admin, e.g., https://dev.azure.com/<org>)")
    if not project_name or not project_name.strip():
        missing.append("project_name (name to keep/create)")
    if not repo_name or not repo_name.strip():
        missing.append("repo_name (initial repo name)")
    if missing:
        return (
            "ADO Project Creation\n\n"
            "Please provide:\n"
            + "\n".join([f"  - {m}" for m in missing]) +
            "\n\nOnly required inputs: organization, project_name, repo_name."
        )

    project_script = _get_script_path("create-devops-project.ps1")
    if not os.path.exists(project_script):
        return "Error: create-devops-project.ps1 not found"

    proj_params = {
        "Organization": organization,
        "ProjectName": project_name,
        "RepoName": repo_name
    }
    if description:
        proj_params["Description"] = description

    try:
        proj_out = _run_powershell_script(project_script, proj_params)
        return proj_out.strip()
    except Exception as e:
        return f"✗ Project/Repo operation crashed: {e}"

@mcp.tool()
def ado_create_repo(organization: str = None, project_name: str = None, repo_name: str = None) -> str:
    """
    Creates a new Azure DevOps Git repository via the PS1 script.

    Behavior: Relies on the PS1 script output entirely (no extra verification).
    Required: organization (URL or org name), project_name, repo_name.
    """
    # Normalize organization to URL if just the org name is provided
    if organization and not organization.strip().lower().startswith("http"):
        organization = f"https://dev.azure.com/{organization.strip()}"

    missing = []
    if not organization or not organization.strip():
        missing.append("organization (existing org URL where you're project admin)")
    if not project_name or not project_name.strip():
        missing.append("project_name (existing project)")
    if not repo_name or not repo_name.strip():
        missing.append("repo_name (new repo name to keep/create)")
    if missing:
        return (
            "ADO Repo Creation\n\n"
            "Please provide:\n"
            + "\n".join([f"  - {m}" for m in missing]) +
            "\n\nOnly required inputs: organization, project_name, repo_name."
        )

    repo_script = _get_script_path("create-devops-repo.ps1")
    if not os.path.exists(repo_script):
        return "Error: create-devops-repo.ps1 not found"

    params = {
        "Organization": organization,
        "ProjectName": project_name,
        "RepoName": repo_name
    }

    try:
        out = _run_powershell_script(repo_script, params)
        return out.strip()
    except Exception as e:
        return f"✗ Repository operation crashed: {e}"

@mcp.tool()
def ado_list_projects(organization: str = None) -> str:
    """
    Lists all Azure DevOps projects in an organization.

    Behavior: Returns list of all projects with their details.
    Required: organization (URL or org name).
    """
    # Normalize organization to URL if just the org name is provided
    if organization and not organization.strip().lower().startswith("http"):
        organization = f"https://dev.azure.com/{organization.strip()}"

    if not organization or not organization.strip():
        return (
            "ADO List Projects\n\n"
            "Please provide:\n"
            "  - organization (org URL to list projects from)\n\n"
            "Only required input: organization."
        )

    list_projects_script = _get_script_path("list-devops-projects.ps1")
    if not os.path.exists(list_projects_script):
        return "Error: list-devops-projects.ps1 not found"

    params = {
        "Organization": organization
    }

    try:
        out = _run_powershell_script(list_projects_script, params)
        return out.strip()
    except Exception as e:
        return f"✗ List projects operation crashed: {e}"

@mcp.tool()
def ado_list_repos(organization: str = None, project_name: str = None) -> str:
    """
    Lists all Azure DevOps repositories in a project.

    Behavior: Returns list of all repos with their details.
    Required: organization (URL or org name), project_name.
    """
    # Normalize organization to URL if just the org name is provided
    if organization and not organization.strip().lower().startswith("http"):
        organization = f"https://dev.azure.com/{organization.strip()}"

    missing = []
    if not organization or not organization.strip():
        missing.append("organization (org URL)")
    if not project_name or not project_name.strip():
        missing.append("project_name (project to list repos from)")
    if missing:
        return (
            "ADO List Repositories\n\n"
            "Please provide:\n"
            + "\n".join([f"  - {m}" for m in missing]) +
            "\n\nOnly required inputs: organization, project_name."
        )

    list_repos_script = _get_script_path("list-devops-repos.ps1")
    if not os.path.exists(list_repos_script):
        return "Error: list-devops-repos.ps1 not found"

    params = {
        "Organization": organization,
        "ProjectName": project_name
    }

    try:
        out = _run_powershell_script(list_repos_script, params)
        return out.strip()
    except Exception as e:
        return f"✗ List repos operation crashed: {e}"

@mcp.tool()
def ado_create_branch(organization: str = None, project_name: str = None, 
                        repo_name: str = None, branch_name: str = None, 
                        base_branch: str = None) -> str:
    """
    Creates a new branch in an Azure DevOps repository from a base branch.

    Behavior: Creates branch from specified base branch (defaults to 'main').
    Branch name can be simple (e.g., 'dev') or folder-based (e.g., 'feature/myfeature').
    Required: organization, project_name, repo_name, branch_name, base_branch (defaults to 'main').
    """
    # Normalize organization to URL if just the org name is provided
    if organization and not organization.strip().lower().startswith("http"):
        organization = f"https://dev.azure.com/{organization.strip()}"

    missing = []
    if not organization or not organization.strip():
        missing.append("organization (org URL)")
    if not project_name or not project_name.strip():
        missing.append("project_name (existing project)")
    if not repo_name or not repo_name.strip():
        missing.append("repo_name (existing repo)")
    if not branch_name or not branch_name.strip():
        missing.append("branch_name (new branch name, e.g., 'dev' or 'feature/myfeature')")
    if not base_branch or not base_branch.strip():
        missing.append("base_branch (branch to create from, usually 'main')")
    if missing:
        return (
            "ADO Create Branch\n\n"
            "Please provide:\n"
            + "\n".join([f"  - {m}" for m in missing]) +
            "\n\nOnly required inputs: organization, project_name, repo_name, branch_name, base_branch."
        )

    branch_script = _get_script_path("create-devops-branch.ps1")
    if not os.path.exists(branch_script):
        return "Error: create-devops-branch.ps1 not found"

    params = {
        "Organization": organization,
        "ProjectName": project_name,
        "RepoName": repo_name,
        "BranchName": branch_name,
        "BaseBranch": base_branch
    }

    try:
        out = _run_powershell_script(branch_script, params)
        return out.strip()
    except Exception as e:
        return f"✗ Branch creation operation crashed: {e}"

# ============================================================================
# MCP TOOLS - Azure DevOps (Pipelines)
# ============================================================================

@mcp.tool()
def ado_deploy_pipeline_yaml(organization: str = None, project_name: str = None, 
                        repo_name: str = None, pipeline_type: str = None,
                        branch: str = None, folder_path: str = None) -> str:
    """
    Deploys a pipeline YAML template from agent/templates to an Azure DevOps repository.
    
    Template Auto-Selection:
    - Available types: credscan (non-prod), credscan-1es (prod), credscan-prod (prod)
    - System auto-detects based on keywords: '1ES', 'prod', 'production'
    - More pipeline types can be added to PIPELINE_TEMPLATE_MAP
    
    Workflow:
    1. Auto-selects template based on pipeline_type or keywords
    2. Clones the repo at specified branch
    3. Copies template to specified folder path
    4. Commits and pushes to repository
    
    Args:
        organization: Azure DevOps organization URL
        project_name: Existing project name
        repo_name: Existing repository name
        pipeline_type: Pipeline type ('credscan' for non-prod, 'credscan-1es' or 'credscan-prod' for production)
        branch: Branch to deploy to (defaults to 'main')
        folder_path: Folder in repo to deploy YAML (defaults to 'pipelines')
    
    Returns:
        Deployment status and YAML location
    """
    # Normalize organization to URL if just the org name is provided
    if organization and not organization.strip().lower().startswith("http"):
        organization = f"https://dev.azure.com/{organization.strip()}"

    missing = []
    if not organization or not organization.strip():
        missing.append("organization (org URL)")
    if not project_name or not project_name.strip():
        missing.append("project_name (existing project)")
    if not repo_name or not repo_name.strip():
        missing.append("repo_name (existing repo)")
    if not pipeline_type or not pipeline_type.strip():
        missing.append(f"pipeline_type (available: {', '.join(PIPELINE_TEMPLATE_MAP.keys())})")
    if not branch or not branch.strip():
        missing.append("branch (branch to deploy to, usually 'main')")
    if not folder_path or not folder_path.strip():
        missing.append("folder_path (folder in repo, e.g., 'pipelines')")
    
    if missing:
        return (
            "Deploy Pipeline YAML\n\n"
            "Please provide:\n"
            + "\n".join([f"  - {m}" for m in missing]) +
            f"\n\nAvailable pipeline types:\n" +
            "\n".join([f"  - {k}: {v}" for k, v in PIPELINE_TEMPLATE_MAP.items()])
        )

    # Auto-detect and get template
    detected_type = _detect_pipeline_type(pipeline_type, pipeline_type)
    template_basename = os.path.basename(PIPELINE_TEMPLATE_MAP.get(detected_type, PIPELINE_TEMPLATE_MAP["credscan"]))
    
    deploy_script = _get_script_path("deploy-pipeline-yaml.ps1")
    if not os.path.exists(deploy_script):
        return "Error: deploy-pipeline-yaml.ps1 not found"

    params = {
        "Organization": organization,
        "ProjectName": project_name,
        "RepoName": repo_name,
        "TemplateName": template_basename.replace(".yml", ""),
        "Branch": branch,
        "FolderPath": folder_path
    }

    try:
        out = _run_powershell_script(deploy_script, params)
        return out.strip()
    except Exception as e:
        return f"✗ Deploy YAML operation crashed: {e}"

@mcp.tool()
def ado_create_pipeline(organization: str = None, project_name: str = None,
                          repo_name: str = None, pipeline_name: str = None,
                          branch: str = None, pipeline_type: str = None) -> str:
    """
    Creates an Azure DevOps pipeline from YAML file in repository.
    
    Template Auto-Selection:
    - Detects pipeline type from pipeline_name or pipeline_type parameter
    - Keywords: '1ES', 'prod', 'production' → selects production (1ES) pipeline
    - Otherwise → selects standard non-production pipeline
    - Auto-constructs yaml_path as: pipelines/{detected_template}.yml
    
    Available Pipeline Types:
    - credscan: Standard credscan pipeline (non-production)
    - credscan-1es: 1ES pipeline template (production, requires pool params)
    - More types can be added to PIPELINE_TEMPLATE_MAP
    
    Workflow:
    1. Auto-detects pipeline type from pipeline_name keywords
    2. Constructs yaml_path automatically
    3. Checks if YAML exists in repository
    4. Creates pipeline referencing the YAML
    
    Args:
        organization: Azure DevOps organization URL
        project_name: Existing project name
        repo_name: Existing repository name
        pipeline_name: Name for pipeline (keywords '1ES'/'prod' trigger production template)
        branch: Branch containing YAML (defaults to 'main')
        pipeline_type: Optional explicit type override (credscan, credscan-1es)
    
    Returns:
        Pipeline creation status and URL
    """
    # Normalize organization to URL if just the org name is provided
    if organization and not organization.strip().lower().startswith("http"):
        organization = f"https://dev.azure.com/{organization.strip()}"

    # Auto-detect pipeline type if not explicitly provided
    if pipeline_name and not pipeline_type:
        pipeline_type = _detect_pipeline_type(pipeline_name, "")
    elif not pipeline_type:
        pipeline_type = "credscan"  # default

    missing = []
    if not organization or not organization.strip():
        missing.append("organization (org URL)")
    if not project_name or not project_name.strip():
        missing.append("project_name (existing project)")
    if not repo_name or not repo_name.strip():
        missing.append("repo_name (existing repo)")
    if not pipeline_name or not pipeline_name.strip():
        missing.append("pipeline_name (include '1ES' or 'prod' for production pipelines)")
    if not branch or not branch.strip():
        missing.append("branch (branch with YAML, usually 'main')")
    
    if missing:
        # Provide intelligent suggestion based on detected type
        suggestion = f"\n\nDetected pipeline type: {pipeline_type}"
        if "1es" in pipeline_type or "prod" in pipeline_type:
            suggestion += "\nThis is a PRODUCTION pipeline (1ES template with pool parameters required)"
        else:
            suggestion += "\nThis is a NON-PRODUCTION pipeline (standard template)"
        
        return (
            "Create Azure DevOps Pipeline\n\n"
            "Please provide:\n"
            + "\n".join([f"  - {m}" for m in missing]) +
            suggestion +
            f"\n\nAvailable types: {', '.join(PIPELINE_TEMPLATE_MAP.keys())}"
        )

    # Auto-construct yaml_path based on detected pipeline type
    template_basename = os.path.basename(PIPELINE_TEMPLATE_MAP.get(pipeline_type, PIPELINE_TEMPLATE_MAP["credscan"]))
    yaml_path = f"pipelines/{template_basename}"

    pipeline_script = _get_script_path("create-devops-pipeline.ps1")
    if not os.path.exists(pipeline_script):
        return "Error: create-devops-pipeline.ps1 not found"

    params = {
        "Organization": organization,
        "ProjectName": project_name,
        "RepoName": repo_name,
        "PipelineName": pipeline_name,
        "Branch": branch,
        "YamlPath": yaml_path
    }

    try:
        out = _run_powershell_script(pipeline_script, params)
        return out.strip()
    except Exception as e:
        return f"✗ Create pipeline operation crashed: {e}"

# ============================================================================
# MCP TOOLS - Microsoft Fabric (Workspaces, Git Integration)
# ============================================================================

@mcp.tool()
def fabric_create_workspace(capacity_id: str = None, workspace_name: str = None, 
                           description: str = "") -> str:
    """
    Creates a Microsoft Fabric workspace in a capacity.
    
    Workflow:
    1. Validates capacity ID and workspace name
    2. Creates workspace using Fabric REST API
    3. Associates workspace with specified capacity
    
    Args:
        capacity_id: Full resource ID of the Fabric capacity (e.g., /subscriptions/.../resourceGroups/.../providers/Microsoft.Fabric/capacities/...)
        workspace_name: Name for the new workspace
        description: Optional description for the workspace
    
    Returns:
        Workspace creation status with workspace ID and details
    """
    missing = []
    if not capacity_id:
        missing.append("capacity_id (full resource ID)")
    if not workspace_name:
        missing.append("workspace_name")
    
    if missing:
        return "Missing required parameters:\n" + "\n".join([f"  - {m}" for m in missing])
    
    workspace_script = _get_script_path("create-fabric-workspace.ps1")
    if not os.path.exists(workspace_script):
        return "Error: create-fabric-workspace.ps1 not found"
    
    params = {
        "CapacityId": capacity_id,
        "WorkspaceName": workspace_name,
        "Description": description
    }
    
    try:
        out = _run_powershell_script(workspace_script, params)
        return out.strip()
    except Exception as e:
        return f"✗ Create workspace operation failed: {e}"

@mcp.tool()
def fabric_attach_workspace_to_git(workspace_id: str = None, organization: str = None,
                                   project_name: str = None, repo_name: str = None,
                                   branch_name: str = None, directory_name: str = "/") -> str:
    """
    Attaches a Microsoft Fabric workspace to an Azure DevOps Git repository.
    
    Workflow:
    1. Validates workspace ID and Git connection details
    2. Connects workspace to specified Azure DevOps repository
    3. Enables Git integration for workspace items
    
    Args:
        workspace_id: Fabric workspace ID (GUID)
        organization: Azure DevOps organization URL or name
        project_name: Azure DevOps project name
        repo_name: Azure DevOps repository name
        branch_name: Git branch name (e.g., 'main')
        directory_name: Directory path in repository (defaults to '/')
    
    Returns:
        Git connection status with workspace and repository details
    """
    missing = []
    if not workspace_id:
        missing.append("workspace_id")
    if not organization:
        missing.append("organization")
    if not project_name:
        missing.append("project_name")
    if not repo_name:
        missing.append("repo_name")
    if not branch_name:
        missing.append("branch_name")
    
    if missing:
        return "Missing required parameters:\n" + "\n".join([f"  - {m}" for m in missing])
    
    # Normalize organization URL
    if organization and "https://" not in organization:
        organization = f"https://dev.azure.com/{organization}"
    
    git_script = _get_script_path("attach-fabric-git.ps1")
    if not os.path.exists(git_script):
        return "Error: attach-fabric-git.ps1 not found"
    
    params = {
        "WorkspaceId": workspace_id,
        "Organization": organization,
        "ProjectName": project_name,
        "RepoName": repo_name,
        "BranchName": branch_name,
        "DirectoryName": directory_name
    }
    
    try:
        out = _run_powershell_script(git_script, params)
        return out.strip()
    except Exception as e:
        return f"✗ Attach Git operation failed: {e}"

def main():
    """Entry point for the MCP server."""
    mcp.run()

if __name__ == "__main__":
    main()