# ============================================================================
# AZURE FUNCTIONS - Azure resource management logic
# ============================================================================

import os
import re
import json
import shutil
from datetime import datetime, timedelta
from typing import Optional, Dict, Tuple

try:
    from .utils import (
        run_command, run_powershell_script, get_script_path, get_template_path,
        ERROR_KEYWORDS, TEMPLATE_MAP, RESOURCE_TYPE_PROVIDER_MAP, OP_SCRIPTS,
        NSP_MANDATORY_RESOURCES, LOG_ANALYTICS_MANDATORY_RESOURCES,
        parse_bicep_parameters, validate_bicep_parameters, deploy_bicep,
        get_fabric_tenant_region
    )
except ImportError:
    from utils import (
        run_command, run_powershell_script, get_script_path, get_template_path,
        ERROR_KEYWORDS, TEMPLATE_MAP, RESOURCE_TYPE_PROVIDER_MAP, OP_SCRIPTS,
        NSP_MANDATORY_RESOURCES, LOG_ANALYTICS_MANDATORY_RESOURCES,
        parse_bicep_parameters, validate_bicep_parameters, deploy_bicep,
        get_fabric_tenant_region
    )


# ============================================================================
# Azure Permissions & Subscriptions
# ============================================================================

def list_permissions(user_principal_name: str = None, force_refresh: bool = True) -> str:
    """Lists active Azure RBAC role assignments for resources and subscriptions."""
    script_name = OP_SCRIPTS["permissions"]
    script_path = get_script_path(script_name)
    
    if not os.path.exists(script_path):
        return f"Error: Script '{script_name}' not found."

    params = {}
    if user_principal_name:
        params["UserPrincipalName"] = user_principal_name
    
    return run_powershell_script(script_path, params)


def query_resources(
    query_type: str,
    resource_name: str = None,
    resource_group: str = None,
    resource_type: str = None,
    location: str = None,
    custom_query: str = None
) -> str:
    """Unified tool for querying Azure resources, resource groups, and their properties."""
    query_type = query_type.lower().strip()
    
    if query_type == "custom":
        if not custom_query:
            return json.dumps({"error": "custom_query is required for custom query_type"})
        
        cmd = ["az", "graph", "query", "-q", custom_query, "-o", "json"]
        result = run_command(cmd)
        try:
            data = json.loads(result)
            return json.dumps({"query": custom_query, "results": data.get("data", data)}, indent=2)
        except json.JSONDecodeError:
            if "ERROR" in result or "error" in result.lower():
                return result
            return json.dumps({"error": "Failed to execute custom query", "raw_output": result})
    
    elif query_type == "list_rgs":
        cmd = ["az", "group", "list", "--query", "[].{name:name, location:location, state:properties.provisioningState}", "-o", "json"]
        result = run_command(cmd)
        try:
            rgs = json.loads(result)
            return json.dumps({"count": len(rgs), "resourceGroups": rgs}, indent=2)
        except json.JSONDecodeError:
            return json.dumps({"error": "Failed to parse resource groups", "raw_output": result})
    
    elif query_type == "list_resources":
        cmd = ["az", "resource", "list"]
        if resource_group:
            cmd.extend(["-g", resource_group])
        cmd.extend(["--query", "[].{name:name, type:type, location:location, resourceGroup:resourceGroup}", "-o", "json"])
        
        result = run_command(cmd)
        try:
            resources = json.loads(result)
            if resource_type:
                provider = RESOURCE_TYPE_PROVIDER_MAP.get(resource_type.lower())
                if provider:
                    resources = [r for r in resources if r.get("type", "").lower() == provider.lower()]
            
            return json.dumps({
                "count": len(resources),
                "filters": {"resourceGroup": resource_group, "resourceType": resource_type},
                "resources": resources
            }, indent=2)
        except json.JSONDecodeError:
            return json.dumps({"error": "Failed to parse resources", "raw_output": result})
    
    elif query_type == "get_resource":
        if not resource_name:
            return json.dumps({"error": "resource_name is required for get_resource query"})
        
        cmd = ["az", "resource", "list", "--query", f"[?name=='{resource_name}']", "-o", "json"]
        if resource_group:
            cmd = ["az", "resource", "list", "-g", resource_group, "--query", f"[?name=='{resource_name}']", "-o", "json"]
        
        result = run_command(cmd)
        try:
            resources = json.loads(result)
            if resources:
                return json.dumps({"found": True, "resource": resources[0]}, indent=2)
            return json.dumps({"found": False, "message": f"Resource '{resource_name}' not found"})
        except json.JSONDecodeError:
            return json.dumps({"error": "Failed to parse resource info", "raw_output": result})
    
    elif query_type == "find_resource":
        if not resource_name:
            return json.dumps({"error": "resource_name is required for find_resource query"})
        
        cmd = ["az", "resource", "list", "--query", f"[?name=='{resource_name}'].{{name:name, resourceGroup:resourceGroup, type:type}}", "-o", "json"]
        result = run_command(cmd)
        try:
            resources = json.loads(result)
            if resources:
                return json.dumps({"found": True, "count": len(resources), "matches": resources}, indent=2)
            return json.dumps({"found": False, "message": f"No resource named '{resource_name}' found in any resource group"})
        except json.JSONDecodeError:
            return json.dumps({"error": "Failed to search for resource", "raw_output": result})
    
    elif query_type == "check_type_in_rg":
        if not resource_group or not resource_type:
            return json.dumps({"error": "resource_group and resource_type are required for check_type_in_rg query"})
        
        provider = RESOURCE_TYPE_PROVIDER_MAP.get(resource_type.lower())
        if not provider:
            return json.dumps({"error": f"Unknown resource_type: {resource_type}", "valid_types": list(RESOURCE_TYPE_PROVIDER_MAP.keys())})
        
        cmd = ["az", "resource", "list", "-g", resource_group, "--resource-type", provider, "-o", "json"]
        result = run_command(cmd)
        try:
            resources = json.loads(result)
            return json.dumps({
                "resourceGroup": resource_group,
                "resourceType": resource_type,
                "exists": len(resources) > 0,
                "count": len(resources),
                "resources": [{"name": r.get("name"), "id": r.get("id")} for r in resources]
            }, indent=2)
        except json.JSONDecodeError:
            return json.dumps({"error": "Failed to check resources", "raw_output": result})
    
    elif query_type == "get_rg_info":
        if not resource_group:
            return json.dumps({"error": "resource_group is required for get_rg_info query"})
        
        cmd = ["az", "group", "show", "-n", resource_group, "-o", "json"]
        result = run_command(cmd)
        try:
            rg_info = json.loads(result)
            return json.dumps({
                "name": rg_info.get("name"),
                "location": rg_info.get("location"),
                "state": rg_info.get("properties", {}).get("provisioningState"),
                "tags": rg_info.get("tags", {}),
                "id": rg_info.get("id")
            }, indent=2)
        except json.JSONDecodeError:
            return json.dumps({"error": "Failed to check resources", "raw_output": result})
    
    else:
        return json.dumps({
            "error": f"Unknown query_type: {query_type}",
            "valid_types": ["list_rgs", "list_resources", "get_resource", "find_resource", "check_type_in_rg", "get_rg_info", "custom"]
        })


def update_tags(
    resource_id: str = None,
    resource_name: str = None,
    resource_group: str = None,
    resource_type: str = None,
    tags: str = None,
    operation: str = "merge"
) -> str:
    """Adds, updates, or replaces tags on an Azure resource."""
    if not tags:
        return json.dumps({"error": "tags parameter is required in format 'key1=value1,key2=value2'"})
    
    if not resource_id and not (resource_name and resource_group):
        return json.dumps({"error": "Either resource_id OR (resource_name + resource_group) is required"})
    
    params = {"Tags": tags, "Operation": operation}
    if resource_id:
        params["ResourceId"] = resource_id
    if resource_name:
        params["ResourceName"] = resource_name
    if resource_group:
        params["ResourceGroup"] = resource_group
    if resource_type:
        params["ResourceType"] = resource_type
    
    script_path = get_script_path("update-tags.ps1")
    return run_powershell_script(script_path, params)


def get_activity_log(
    resource_group: str = None,
    resource_id: str = None,
    resource_name: str = None,
    days: int = None,
    max_events: int = 50,
    operation_type: str = None
) -> str:
    """Retrieves Azure Activity Log events for auditing and troubleshooting."""
    if days is None:
        return json.dumps({
            "prompt": "How many days of activity logs would you like to retrieve?",
            "options": [
                {"value": 1, "label": "Last 24 hours"},
                {"value": 7, "label": "Last 7 days (recommended)"},
                {"value": 14, "label": "Last 14 days"},
                {"value": 30, "label": "Last 30 days"},
                {"value": 90, "label": "Last 90 days (maximum)"}
            ],
            "default": 7,
            "note": "Larger time ranges may take longer to retrieve"
        })
    
    params = {"Days": str(days), "MaxEvents": str(max_events)}
    if resource_group:
        params["ResourceGroup"] = resource_group
    if resource_id:
        params["ResourceId"] = resource_id
    if resource_name:
        params["ResourceName"] = resource_name
    if operation_type:
        params["OperationType"] = operation_type
    
    script_path = get_script_path("get-activity-log.ps1")
    return run_powershell_script(script_path, params)


def create_resource_group(resource_group_name: str, region: str, project_name: str) -> str:
    """Creates an Azure resource group with project tagging."""
    if not resource_group_name or not region or not project_name:
        return "Error: All parameters (resource_group_name, region, project_name) are required."
    
    script_name = OP_SCRIPTS["create-rg"]
    script_path = get_script_path(script_name)
    if not os.path.exists(script_path): 
        return f"Error: Script '{script_name}' not found."
    
    params = {
        "ResourceGroupName": resource_group_name,
        "Region": region,
        "ProjectName": project_name
    }
    return run_powershell_script(script_path, params)


# ============================================================================
# Azure Compliance (NSP & Diagnostics)
# ============================================================================

def check_resource(resource_group: str, resource_type: str) -> str:
    """Checks for specific resource types in a resource group."""
    if not resource_group or not resource_group.strip():
        return json.dumps({"error": "Resource group name is required"})
    
    resource_type = resource_type.lower().strip()
    
    if "network" in resource_type and "security" in resource_type and "perimeter" in resource_type:
        resource_type = "nsp"
    
    if resource_type not in RESOURCE_TYPE_PROVIDER_MAP:
        supported_types = ', '.join(sorted(RESOURCE_TYPE_PROVIDER_MAP.keys()))
        return json.dumps({"error": f"Invalid resource_type. Supported: {supported_types}"})
    
    ps_executable = "pwsh" if shutil.which("pwsh") else "powershell"
    script_path = get_script_path("check-resource.ps1")
    
    if not os.path.exists(script_path):
        return json.dumps({"error": "check-resource.ps1 script not found"})
    
    provider_type = RESOURCE_TYPE_PROVIDER_MAP[resource_type]
    
    result = run_command([
        ps_executable, "-ExecutionPolicy", "Bypass", "-File", script_path,
        "-ResourceGroupName", resource_group,
        "-ResourceType", resource_type,
        "-ProviderType", provider_type
    ])
    
    if "RESOURCE NOT FOUND" in result:
        return json.dumps({
            "count": 0,
            "resources": [],
            "message": f"No {resource_type} found in resource group '{resource_group}'"
        })
    
    resource_names = []
    resource_ids = []
    count = 1
    
    found_match = re.search(r'RESOURCE FOUND:\s*(.+)', result)
    if found_match:
        resource_names.append(found_match.group(1).strip())
    
    id_match = re.search(r'RESOURCE ID:\s*(.+)', result)
    if id_match:
        resource_ids.append(id_match.group(1).strip())
    
    count_match = re.search(r'COUNT:\s*(\d+)', result)
    if count_match:
        count = int(count_match.group(1))
    
    if "MULTIPLE RESOURCES FOUND" in result:
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


def attach_to_nsp(resource_group: str, nsp_name: str = None, resource_id: str = None) -> str:
    """Attaches a resource to a Network Security Perimeter (NSP)."""
    if not resource_group or not resource_group.strip():
        return "Error: Resource group name is required"
    
    if not resource_id or not resource_id.strip():
        return "Error: Resource ID is required"
    
    output = []
    output.append("🔒 Starting NSP Attachment Workflow")
    output.append("=" * 70)
    output.append("")
    
    output.append("Step 1/3: Checking for existing NSP...")
    check_result = check_resource(resource_group, "nsp")
    
    try:
        check_data = json.loads(check_result)
    except:
        return f"Error: Failed to parse NSP check result:\n{check_result}"
    
    if check_data.get("count", 0) == 0:
        output.append("   → No NSP found in resource group")
        output.append("")
        output.append("Step 2/3: Creating NSP...")
        
        nsp_name = nsp_name or f"{resource_group}-nsp"
        create_params = {"name": nsp_name, "location": "global"}
        
        create_result = create_resource("nsp", resource_group, json.dumps(create_params))
        
        if any(err in create_result.lower() for err in ERROR_KEYWORDS):
            return "\n".join(output) + f"\n\n✗ Failed to create NSP:\n{create_result}"
        
        output.append(f"   → NSP '{nsp_name}' created successfully")
    else:
        resources = check_data.get("resources", [])
        if not resources:
            return "\n".join(output) + "\n\n✗ Error: NSP check returned invalid data"
        
        if nsp_name:
            matching = [r for r in resources if r.get("name") == nsp_name]
            if matching:
                nsp_name = matching[0].get("name")
            else:
                nsp_name = resources[0].get("name")
        else:
            nsp_name = resources[0].get("name")
        
        output.append(f"   → Found existing NSP: '{nsp_name}'")
        output.append("")
        output.append("Step 2/3: Skipping NSP creation (already exists)")
    
    output.append("")
    output.append("Step 3/3: Attaching resource to NSP...")
    
    ps_executable = "pwsh" if shutil.which("pwsh") else "powershell"
    attach_nsp_script = get_script_path("attach-nsp.ps1")
    
    if not os.path.exists(attach_nsp_script):
        return "\n".join(output) + "\n\n✗ Error: attach-nsp.ps1 script not found"
    
    result = run_command([
        ps_executable, "-ExecutionPolicy", "Bypass", "-File", attach_nsp_script,
        "-ResourceGroupName", resource_group,
        "-NspName", nsp_name,
        "-ResourceId", resource_id
    ])
    
    if any(err in result for err in ERROR_KEYWORDS):
        output.append(f"   ✗ Failed to attach resource to NSP")
        output.append("")
        output.append("=" * 70)
        output.append("Error Details:")
        output.append(result)
        return "\n".join(output)
    
    output.append(f"   → Resource attached to NSP '{nsp_name}'")
    output.append("")
    output.append("=" * 70)
    output.append("✓ WORKFLOW COMPLETED")
    output.append("")
    output.append("Network security compliance resolved.")
    output.append("")
    output.append("Summary:")
    output.append(f"   • Resource Group: {resource_group}")
    output.append(f"   • NSP Name: {nsp_name}")
    output.append(f"   • Resource attached and secured")
    
    return "\n".join(output)


def attach_diagnostic_settings(resource_group: str, workspace_id: str = None, resource_id: str = None) -> str:
    """Attaches diagnostic settings to a resource with automatic Log Analytics Workspace management."""
    if not resource_group or not resource_group.strip():
        return "Error: Resource group name is required"
    
    if not resource_id or not resource_id.strip():
        return "Error: Resource ID is required"
    
    output = []
    output.append("📊 Starting Log Analytics Configuration Workflow")
    output.append("=" * 70)
    output.append("")
    
    output.append("Step 1/3: Checking for existing Log Analytics Workspace...")
    check_result = check_resource(resource_group, "log-analytics")
    
    try:
        check_data = json.loads(check_result)
    except:
        return f"Error: Failed to parse Log Analytics check result:\n{check_result}"
    
    workspace_name = None
    if check_data.get("count", 0) == 0:
        output.append("   → No Log Analytics Workspace found")
        output.append("")
        output.append("Step 2/3: Creating Log Analytics Workspace...")
        
        workspace_name = f"{resource_group}-law"
        create_params = json.dumps({
            "workspaceName": workspace_name,
            "location": "eastus"
        })
        
        create_result = create_resource("log-analytics", resource_group, create_params)
        
        if any(err in create_result.lower() for err in ERROR_KEYWORDS):
            return "\n".join(output) + f"\n\n✗ Failed to create Log Analytics Workspace:\n{create_result}"
        
        output.append(f"   → Log Analytics Workspace '{workspace_name}' created successfully")
        
        check_result_new = check_resource(resource_group, "log-analytics")
        try:
            check_data_new = json.loads(check_result_new)
            resources_new = check_data_new.get("resources", [])
            if resources_new:
                workspace_id = resources_new[0].get("id")
        except:
            return "\n".join(output) + "\n\n✗ Error: Could not retrieve workspace ID after creation"
    else:
        resources = check_data.get("resources", [])
        if not resources:
            return "\n".join(output) + "\n\n✗ Error: Log Analytics check returned invalid data"
        
        if not workspace_id:
            workspace_id = resources[0].get("id")
            workspace_name = resources[0].get("name")
        else:
            workspace_name = workspace_id.split("/")[-1] if "/" in workspace_id else workspace_id
        
        output.append(f"   → Found existing Log Analytics Workspace: '{workspace_name}'")
        output.append("")
        output.append("Step 2/3: Skipping workspace creation (already exists)")
    
    output.append("")
    output.append("Step 3/3: Configuring diagnostic settings...")
    
    ps_executable = "pwsh" if shutil.which("pwsh") else "powershell"
    attach_law_script = get_script_path("attach-log-analytics.ps1")
    
    if not os.path.exists(attach_law_script):
        return "\n".join(output) + "\n\n✗ Error: attach-log-analytics.ps1 script not found"
    
    result = run_command([
        ps_executable, "-ExecutionPolicy", "Bypass", "-File", attach_law_script,
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
    output.append("Monitoring compliance resolved.")
    output.append("")
    output.append("Summary:")
    output.append(f"   • Resource Group: {resource_group}")
    output.append(f"   • Log Analytics Workspace: {workspace_name}")
    output.append(f"   • Diagnostic settings enabled and monitoring active")
    
    return "\n".join(output)


# ============================================================================
# Azure Resource Management
# ============================================================================

def get_bicep_requirements(resource_type: str) -> str:
    """Returns required/optional params for a Bicep template."""
    if resource_type not in TEMPLATE_MAP:
        return f"Unknown resource_type. Valid: {', '.join(TEMPLATE_MAP.keys())}"
    template_path = get_template_path(TEMPLATE_MAP[resource_type])
    params = parse_bicep_parameters(template_path)
    
    if resource_type == "fabric-capacity":
        tenant_region = get_fabric_tenant_region()
        region_info = f" (auto-detected: {tenant_region})" if tenant_region else " (will use default: westcentralus)"
        
        structured = {
            "required": [p for p, (req, _) in params.items() if req and p != "location"],
            "optional": [p for p, (req, _) in params.items() if not req and p != "location"],
            "defaults": {p: default for p, (req, default) in params.items() if default is not None and p != "location"},
            "auto_detected": {
                "location": tenant_region if tenant_region else "westcentralus"
            },
            "note": f"Location is automatically set to your Fabric tenant's home region{region_info}. You do not need to specify it."
        }
        return json.dumps(structured, indent=2)
    
    structured = {
        "required": [p for p, (req, _) in params.items() if req],
        "optional": [p for p, (req, _) in params.items() if not req],
        "defaults": {p: default for p, (req, default) in params.items() if default is not None}
    }
    return json.dumps(structured, indent=2)


def create_resource(resource_type: str, resource_group: str = None, parameters: str = None) -> str:
    """Interactive Azure resource creation."""
    if resource_type not in TEMPLATE_MAP:
        return f"Invalid resource type. Supported types:\n" + "\n".join([f"  - {rt}" for rt in TEMPLATE_MAP.keys()])
    
    params_dict = {}
    if parameters:
        try:
            params_dict = json.loads(parameters) if isinstance(parameters, str) else parameters
        except json.JSONDecodeError:
            return f"Error: Invalid JSON in parameters: {parameters}"
    
    if not resource_group:
        return (
            f"Creating {resource_type}\n\n"
            f"Please provide:\n"
            f"  - resource_group (required): The Azure resource group name\n\n"
            f"Once you provide the resource group, I'll check for the required template parameters."
        )
    
    template_path = get_template_path(TEMPLATE_MAP[resource_type])
    template_params = parse_bicep_parameters(template_path)
    
    auto_calculated = []
    if resource_type == "subnet":
        auto_calculated.append("subnetStartingAddress")
    elif resource_type == "fabric-capacity":
        auto_calculated.append("location")
    
    required_params = [p for p, (req, _) in template_params.items() if req and p not in auto_calculated]
    optional_params = [p for p, (req, _) in template_params.items() if not req and p not in auto_calculated]
    
    missing_required = [p for p in required_params if p not in params_dict or params_dict[p] in (None, "")]
    
    if missing_required:
        response = [f"Creating {resource_type} in '{resource_group}'\n"]
        response.append("Please provide the following required parameters:\n")
        
        for param in missing_required:
            response.append(f"  - {param}")
        
        if resource_type == "fabric-capacity":
            response.append(f"\nNote: 'location' will be auto-detected from your Fabric tenant region.")
        elif resource_type == "subnet":
            response.append(f"\nNote: 'subnetStartingAddress' will be auto-calculated based on existing subnets.")
        
        display_optional = [p for p in optional_params if p not in auto_calculated]
        if resource_type == "fabric-capacity":
            display_optional = [p for p in display_optional if p != "location"]
            if display_optional:
                response.append(f"\nOptional parameters: {', '.join(display_optional)}")
        elif optional_params:
            response.append(f"\nOptional parameters: {', '.join(optional_params)}")
        
        response.append(f"\nOnce you provide these, I'll:\n")
        response.append(f"   1. Deploy the {resource_type}")
        
        return "\n".join(response)
    
    return deploy_bicep_resource(resource_group, resource_type, params_dict)


def deploy_bicep_resource(resource_group: str, resource_type: str, parameters: dict) -> str:
    """Internal deployment function - validates and deploys a resource."""
    if not resource_group or not resource_group.strip():
        return "STOP: Resource group name is required. Please provide the resource group name."
    
    if not resource_type or not resource_type.strip():
        return f"STOP: Resource type is required. Valid types: {', '.join(TEMPLATE_MAP.keys())}"
    
    ok, msg, parsed_params = validate_bicep_parameters(resource_type, parameters)
    if not ok:
        req_params = [p for p, (req, _) in parsed_params.items() if req]
        return f"STOP: {msg}\n\nPlease call get_bicep_requirements('{resource_type}') to see all required parameters.\nRequired: {', '.join(req_params) if req_params else 'unknown'}"
    
    return deploy_bicep(resource_group, resource_type, parameters)
