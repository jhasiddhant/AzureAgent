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
        get_fabric_tenant_region, PRIVATE_DNS_ZONE_MAP, PARAM_METADATA,
        RESOURCE_VARIANTS
    )
except ImportError:
    from utils import (
        run_command, run_powershell_script, get_script_path, get_template_path,
        ERROR_KEYWORDS, TEMPLATE_MAP, RESOURCE_TYPE_PROVIDER_MAP, OP_SCRIPTS,
        NSP_MANDATORY_RESOURCES, LOG_ANALYTICS_MANDATORY_RESOURCES,
        parse_bicep_parameters, validate_bicep_parameters, deploy_bicep,
        get_fabric_tenant_region, PRIVATE_DNS_ZONE_MAP, PARAM_METADATA,
        RESOURCE_VARIANTS
    )


# ============================================================================
# Azure Permissions & Subscriptions
# ============================================================================

def list_roles(role_type: str = None, user_principal_name: str = None, force_refresh: bool = True) -> str:
    """
    Unified function to list Azure roles for the current user.
    
    Args:
        role_type: Type of roles to list:
            - "active": Currently active/assigned RBAC roles
            - "eligible": Eligible PIM roles that can be activated
            - None: Returns error asking to specify role type
        user_principal_name: Optional user email (only used for active roles)
        force_refresh: Whether to force refresh (only used for active roles)
    
    Returns:
        List of roles based on role_type
    """
    if not role_type:
        return """ERROR: role_type not specified.

Please specify which roles you want to see:
- "active": Show currently active/assigned RBAC roles (permanent assignments + activated PIM roles)
- "eligible": Show eligible PIM roles that can be activated (not yet active)

Ask the user: 'Would you like to see your active (currently assigned) roles or eligible (PIM roles available for activation)?'"""
    
    role_type = role_type.lower().strip()
    
    if role_type == "active":
        return list_permissions(user_principal_name, force_refresh)
    elif role_type == "eligible":
        return list_pim_roles()
    else:
        return f"""ERROR: Invalid role_type '{role_type}'.

Valid options:
- "active": Show currently active/assigned RBAC roles
- "eligible": Show eligible PIM roles that can be activated"""


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
        
        # Detect if user passed a CLI command instead of a Resource Graph query
        if custom_query.strip().startswith("az "):
            return json.dumps({
                "error": "custom_query should be an Azure Resource Graph KQL query, not an Azure CLI command",
                "hint": "Use query_type='cli_raw' to run raw CLI commands, or use a KQL query like: Resources | where type == 'Microsoft.Compute/virtualMachines'",
                "received": custom_query
            })
        
        cmd = ["az", "graph", "query", "-q", custom_query, "-o", "json"]
        result = run_command(cmd)
        try:
            data = json.loads(result)
            return json.dumps({"query": custom_query, "results": data.get("data", data)}, indent=2)
        except json.JSONDecodeError:
            if "ERROR" in result or "error" in result.lower():
                return result
            return json.dumps({"error": "Failed to execute custom query", "raw_output": result})
    
    elif query_type == "cli_raw":
        # Run a raw Azure CLI command
        if not custom_query:
            return json.dumps({"error": "custom_query (the CLI command) is required for cli_raw query_type"})
        
        # Parse the CLI command - support both "az ..." and just the command without "az"
        cli_cmd = custom_query.strip()
        if cli_cmd.startswith("az "):
            cli_cmd = cli_cmd[3:]  # Remove "az " prefix
        
        # Split and build command - ensure JSON output
        import shlex
        try:
            args = shlex.split(cli_cmd)
        except ValueError as e:
            return json.dumps({"error": f"Failed to parse CLI command: {e}"})
        
        # Add -o json if not already specified
        if "-o" not in args and "--output" not in args:
            args.extend(["-o", "json"])
        
        cmd = ["az"] + args
        result = run_command(cmd)
        try:
            data = json.loads(result)
            return json.dumps({"command": custom_query, "result": data}, indent=2)
        except json.JSONDecodeError:
            if "ERROR" in result or "error" in result.lower():
                return json.dumps({"error": "CLI command failed", "raw_output": result})
            return json.dumps({"command": custom_query, "result": result})
    
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
    
    elif query_type == "get_identity":
        # Get principalId (object ID) and clientId for any resource with managed identity
        if not resource_name:
            return json.dumps({"error": "resource_name is required for get_identity query"})
        
        # Check if it's a User-Assigned Managed Identity (UAMI)
        is_uami = resource_type and resource_type.lower() in ["uami", "user-assigned-managed-identity", "managedidentity"]
        
        if is_uami:
            # Use az identity show for UAMIs
            cmd = ["az", "identity", "show", "--name", resource_name, "-o", "json"]
            if resource_group:
                cmd.extend(["-g", resource_group])
            
            result = run_command(cmd)
            try:
                identity = json.loads(result)
                return json.dumps({
                    "found": True,
                    "resourceName": resource_name,
                    "resourceType": "User-Assigned Managed Identity",
                    "principalId": identity.get("principalId"),
                    "clientId": identity.get("clientId"),
                    "tenantId": identity.get("tenantId"),
                    "resourceId": identity.get("id")
                }, indent=2)
            except json.JSONDecodeError:
                if "could not be found" in result.lower() or "not found" in result.lower():
                    return json.dumps({"found": False, "message": f"UAMI '{resource_name}' not found"})
                return json.dumps({"error": "Failed to get identity info", "raw_output": result})
        else:
            # For other resources, first find the resource then get its identity
            find_cmd = ["az", "resource", "list", "--query", f"[?name=='{resource_name}']", "-o", "json"]
            if resource_group:
                find_cmd = ["az", "resource", "list", "-g", resource_group, "--query", f"[?name=='{resource_name}']", "-o", "json"]
            
            result = run_command(find_cmd)
            try:
                resources = json.loads(result)
                if not resources:
                    return json.dumps({"found": False, "message": f"Resource '{resource_name}' not found"})
                
                resource = resources[0]
                resource_id = resource.get("id")
                
                # Get full resource details including identity
                show_cmd = ["az", "resource", "show", "--ids", resource_id, "-o", "json"]
                show_result = run_command(show_cmd)
                resource_details = json.loads(show_result)
                
                identity_info = resource_details.get("identity", {})
                if not identity_info:
                    return json.dumps({
                        "found": True,
                        "resourceName": resource_name,
                        "resourceType": resource.get("type"),
                        "hasIdentity": False,
                        "message": "Resource does not have a managed identity configured"
                    }, indent=2)
                
                response = {
                    "found": True,
                    "resourceName": resource_name,
                    "resourceType": resource.get("type"),
                    "hasIdentity": True,
                    "identityType": identity_info.get("type")
                }
                
                # System-assigned identity
                if identity_info.get("principalId"):
                    response["systemAssigned"] = {
                        "principalId": identity_info.get("principalId"),
                        "tenantId": identity_info.get("tenantId")
                    }
                
                # User-assigned identities
                user_identities = identity_info.get("userAssignedIdentities", {})
                if user_identities:
                    response["userAssigned"] = []
                    for uami_id, uami_info in user_identities.items():
                        response["userAssigned"].append({
                            "resourceId": uami_id,
                            "principalId": uami_info.get("principalId"),
                            "clientId": uami_info.get("clientId")
                        })
                
                return json.dumps(response, indent=2)
                
            except json.JSONDecodeError:
                return json.dumps({"error": "Failed to get identity info", "raw_output": result})
    
    else:
        return json.dumps({
            "error": f"Unknown query_type: {query_type}",
            "valid_types": ["list_rgs", "list_resources", "get_resource", "find_resource", "check_type_in_rg", "get_rg_info", "get_identity", "custom"]
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
    output.append("Starting NSP Attachment Workflow")
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
            return "\n".join(output) + f"\n\nFailed to create NSP:\n{create_result}"
        
        output.append(f"   → NSP '{nsp_name}' created successfully")
    else:
        resources = check_data.get("resources", [])
        if not resources:
            return "\n".join(output) + "\n\nError: NSP check returned invalid data"
        
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
        return "\n".join(output) + "\n\nError: attach-nsp.ps1 script not found"
    
    result = run_command([
        ps_executable, "-ExecutionPolicy", "Bypass", "-File", attach_nsp_script,
        "-ResourceGroupName", resource_group,
        "-NspName", nsp_name,
        "-ResourceId", resource_id
    ])
    
    if any(err in result for err in ERROR_KEYWORDS):
        output.append(f"   Failed to attach resource to NSP")
        output.append("")
        output.append("=" * 70)
        output.append("Error Details:")
        output.append(result)
        return "\n".join(output)
    
    output.append(f"   → Resource attached to NSP '{nsp_name}'")
    output.append("")
    output.append("=" * 70)
    output.append("Workflow completed")
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
            return "\n".join(output) + f"\n\nFailed to create Log Analytics Workspace:\n{create_result}"
        
        output.append(f"   → Log Analytics Workspace '{workspace_name}' created successfully")
        
        check_result_new = check_resource(resource_group, "log-analytics")
        try:
            check_data_new = json.loads(check_result_new)
            resources_new = check_data_new.get("resources", [])
            if resources_new:
                workspace_id = resources_new[0].get("id")
        except:
            return "\n".join(output) + "\n\nError: Could not retrieve workspace ID after creation"
    else:
        resources = check_data.get("resources", [])
        if not resources:
            return "\n".join(output) + "\n\nError: Log Analytics check returned invalid data"
        
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
        return "\n".join(output) + "\n\nError: attach-log-analytics.ps1 script not found"
    
    result = run_command([
        ps_executable, "-ExecutionPolicy", "Bypass", "-File", attach_law_script,
        "-ResourceGroupName", resource_group,
        "-WorkspaceId", workspace_id,
        "-ResourceId", resource_id
    ])
    
    if any(err in result for err in ERROR_KEYWORDS):
        output.append(f"   Failed to configure diagnostic settings")
        output.append("")
        output.append("=" * 70)
        output.append("Error Details:")
        output.append(result)
        return "\n".join(output)
    
    output.append(f"   → Diagnostic settings configured successfully")
    output.append("")
    output.append("=" * 70)
    output.append("Workflow completed")
    output.append("")
    output.append("Monitoring compliance resolved.")
    output.append("")
    output.append("Summary:")
    output.append(f"   • Resource Group: {resource_group}")
    output.append(f"   • Log Analytics Workspace: {workspace_name}")
    output.append(f"   • Diagnostic settings enabled and monitoring active")
    
    return "\n".join(output)


def attach_appinsights(
    app_insights_name: str,
    app_insights_resource_group: str,
    target_app_name: str,
    target_resource_group: str,
    target_type: str
) -> str:
    """Attaches Application Insights to a Function App or App Service."""
    if not app_insights_name or not app_insights_name.strip():
        return "Error: Application Insights name is required"
    
    if not app_insights_resource_group or not app_insights_resource_group.strip():
        return "Error: Application Insights resource group is required"
    
    if not target_app_name or not target_app_name.strip():
        return "Error: Target app name is required"
    
    if not target_resource_group or not target_resource_group.strip():
        return "Error: Target resource group is required"
    
    if target_type not in ["functionapp", "webapp"]:
        return "Error: Target type must be 'functionapp' or 'webapp'"
    
    ps_executable = "pwsh" if shutil.which("pwsh") else "powershell"
    script_path = get_script_path("attach-appinsights.ps1")
    
    if not os.path.exists(script_path):
        return "Error: attach-appinsights.ps1 script not found"
    
    result = run_command([
        ps_executable, "-ExecutionPolicy", "Bypass", "-File", script_path,
        "-AppInsightsName", app_insights_name,
        "-AppInsightsResourceGroup", app_insights_resource_group,
        "-TargetAppName", target_app_name,
        "-TargetResourceGroup", target_resource_group,
        "-TargetType", target_type
    ])
    
    if any(err in result for err in ERROR_KEYWORDS):
        return f"Failed to attach Application Insights:\n{result}"
    
    target_type_display = "Function App" if target_type == "functionapp" else "App Service"
    
    output = []
    output.append(f"✅ Application Insights attached successfully")
    output.append("")
    output.append(f"Application Insights: {app_insights_name}")
    output.append(f"Target {target_type_display}: {target_app_name}")
    output.append("")
    output.append("Configured settings:")
    output.append("  • APPLICATIONINSIGHTS_CONNECTION_STRING")
    output.append("  • APPINSIGHTS_INSTRUMENTATIONKEY")
    output.append("  • ApplicationInsightsAgent_EXTENSION_VERSION=~3")
    output.append("")
    output.append(f"The {target_type_display} will now send telemetry to Application Insights.")
    
    return "\n".join(output)


def integrate_vnet(
    resource_name: str,
    resource_group: str,
    resource_type: str,
    subnet_id: str
) -> str:
    """
    Integrates an Azure resource with a Virtual Network (VNet).
    
    This enables VNet-based network access control:
    
    REGIONAL VNET INTEGRATION (outbound from resource to VNet):
    - Function Apps: Enables outbound calls to VNet resources (MUST be same region as VNet)
    - App Services: Enables outbound calls to VNet resources (MUST be same region as VNet)
    
    NETWORK ACL RULES (inbound firewall rules allowing VNet subnet access):
    - Key Vault: Adds subnet to allowed virtual network rules
    - Storage Account: Adds subnet to allowed virtual network rules
    - Cosmos DB: Adds subnet to allowed virtual network rules
    - Azure OpenAI: Adds subnet to allowed virtual network rules
    - Cognitive Services: Adds subnet to allowed virtual network rules
    - SQL Server: Creates VNet firewall rule
    - Event Hub: Adds subnet to namespace network rules
    - Service Bus: Adds subnet to namespace network rules
    - Container Registry: Adds subnet to allowed network rules (Premium SKU only)
    
    NOT SUPPORTED (use Private Endpoints instead):
    - Azure AI Search: Does NOT support VNet integration, only Private Endpoints
    - Azure Data Factory: Use Managed VNet or Private Endpoints
    
    NOTE: This is NOT Private Endpoint. For inbound private access to resources, use azure_create_private_endpoint.
    
    Args:
        resource_name: Name of the Azure resource
        resource_group: Resource group containing the resource
        resource_type: Type of resource (see supported types below)
        subnet_id: Full resource ID of the subnet
            Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}
    
    Returns:
        Integration result with status and configuration details
    """
    # Validate required parameters
    missing = []
    if not resource_name:
        missing.append("resource_name (name of the Azure resource)")
    if not resource_group:
        missing.append("resource_group (resource group containing the resource)")
    if not resource_type:
        missing.append("resource_type (see supported types)")
    if not subnet_id:
        missing.append("subnet_id (full resource ID of the subnet)")
    
    if missing:
        return "Missing required parameters:\n" + "\n".join([f"  - {m}" for m in missing])
    
    # Validate resource type
    valid_types = [
        "functionapp", "webapp",  # Regional VNet Integration
        "keyvault", "storageaccount", "cosmosdb",  # Network ACL rules
        "openai", "cognitiveservices",  # AI services
        "sqlserver", "eventhub", "servicebus", "containerregistry"  # Other services
    ]
    resource_type_lower = resource_type.lower().strip()
    
    # Check for unsupported resources
    unsupported_types = ["aisearch", "search", "cognitiveservices-search", "datafactory", "adf"]
    if resource_type_lower in unsupported_types:
        return f"""VNet Integration NOT SUPPORTED for '{resource_type}'

Azure AI Search and Azure Data Factory do NOT support VNet integration via network rules.

For these resources, use Private Endpoints instead:
  - Use azure_create_private_endpoint tool to create a private endpoint
  - This provides inbound private connectivity to the resource

Example for AI Search:
  azure_create_private_endpoint(
      resource_group='my-rg',
      private_endpoint_name='pe-search',
      target_resource_id='/subscriptions/.../searchServices/my-search',
      group_id='searchService',
      subnet_id='...',
      location='eastus'
  )"""
    
    if resource_type_lower not in valid_types:
        return f"""Invalid resource_type: '{resource_type}'

Supported resource types:

REGIONAL VNET INTEGRATION (outbound connectivity, requires SAME REGION as VNet):
  - functionapp: Azure Function App
  - webapp: Azure App Service / Web App

NETWORK ACL RULES (firewall rules to allow VNet subnet access):
  - keyvault: Azure Key Vault
  - storageaccount: Azure Storage Account
  - cosmosdb: Azure Cosmos DB
  - openai: Azure OpenAI Service
  - cognitiveservices: Azure Cognitive Services
  - sqlserver: Azure SQL Server
  - eventhub: Azure Event Hub Namespace
  - servicebus: Azure Service Bus Namespace
  - containerregistry: Azure Container Registry (Premium SKU only)

NOT SUPPORTED (use Private Endpoints):
  - AI Search: Use azure_create_private_endpoint
  - Data Factory: Use Managed VNet or Private Endpoints"""
    
    # Validate subnet_id format
    if not subnet_id.startswith("/subscriptions/"):
        return f"""Invalid subnet_id format.

Expected format:
  /subscriptions/{{subscription-id}}/resourceGroups/{{rg-name}}/providers/Microsoft.Network/virtualNetworks/{{vnet-name}}/subnets/{{subnet-name}}

Example:
  /subscriptions/12345678-1234-1234-1234-123456789abc/resourceGroups/my-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/integration-subnet"""
    
    script_path = get_script_path("integrate-vnet.ps1")
    if not os.path.exists(script_path):
        return "Error: integrate-vnet.ps1 script not found"
    
    params = {
        "ResourceName": resource_name,
        "ResourceGroup": resource_group,
        "ResourceType": resource_type_lower,
        "SubnetId": subnet_id
    }
    
    try:
        result = run_powershell_script(script_path, params)
        return result
    except Exception as e:
        resource_type_display = {
            "functionapp": "Function App",
            "webapp": "App Service",
            "keyvault": "Key Vault",
            "storageaccount": "Storage Account",
            "cosmosdb": "Cosmos DB",
            "openai": "Azure OpenAI",
            "cognitiveservices": "Cognitive Services",
            "sqlserver": "SQL Server",
            "eventhub": "Event Hub",
            "servicebus": "Service Bus",
            "containerregistry": "Container Registry"
        }.get(resource_type_lower, resource_type)
        
        error_msg = f"""VNet integration failed for {resource_type_display}

Error: {str(e)}
Error Type: {type(e).__name__}

Common causes:
  - Not authenticated: Run 'az login'
  - Resource not found: Verify the resource name and resource group
  - Subnet not found: Verify the subnet ID
  - Insufficient permissions: Need Contributor or Network Contributor on the VNet"""
        
        # Add resource-specific hints
        if resource_type_lower in ["functionapp", "webapp"]:
            error_msg += """
  - REGION MISMATCH: App Service/Function App must be in the SAME region as VNet
  - App must be on Basic tier or higher (not Consumption plan for Functions)
  - Subnet must be delegated to Microsoft.Web/serverFarms"""
        elif resource_type_lower == "keyvault":
            error_msg += "\n  - Ensure subnet has service endpoint 'Microsoft.KeyVault' enabled"
        elif resource_type_lower == "storageaccount":
            error_msg += "\n  - Ensure subnet has service endpoint 'Microsoft.Storage' enabled"
        elif resource_type_lower == "cosmosdb":
            error_msg += "\n  - Ensure subnet has service endpoint 'Microsoft.AzureCosmosDB' enabled"
        elif resource_type_lower == "containerregistry":
            error_msg += "\n  - Container Registry must be Premium SKU for network rules"
        elif resource_type_lower in ["openai", "cognitiveservices"]:
            error_msg += "\n  - Ensure subnet has service endpoint 'Microsoft.CognitiveServices' enabled"
        elif resource_type_lower == "sqlserver":
            error_msg += "\n  - Ensure subnet has service endpoint 'Microsoft.Sql' enabled"
        elif resource_type_lower in ["eventhub", "servicebus"]:
            error_msg += "\n  - Namespace must be Standard or Premium tier"
        
        return error_msg


# ============================================================================
# CONTAINER APPS
# ============================================================================

def _get_resource_group_location(resource_group: str) -> tuple:
    """
    Get the location of a resource group.
    
    Returns:
        (location: str, error: str)
    """
    cmd = ["az", "group", "show", "-n", resource_group, "-o", "json"]
    result = run_command(cmd)
    
    if "ERROR" in result or "error" in result.lower():
        return "", f"Failed to get resource group location: {result}"
    
    try:
        data = json.loads(result)
        return data.get("location", ""), ""
    except json.JSONDecodeError:
        return "", f"Failed to parse resource group info: {result}"


def _find_container_apps_environment(resource_group: str) -> tuple:
    """
    Find an existing Container Apps Environment in the resource group.
    
    Returns:
        (env_name: str, env_id: str, error: str)
    """
    cmd = [
        "az", "containerapp", "env", "list",
        "-g", resource_group,
        "-o", "json"
    ]
    result = run_command(cmd)
    
    if "ERROR" in result or "error" in result.lower():
        return "", "", f"Failed to list Container Apps Environments: {result}"
    
    try:
        envs = json.loads(result)
        if envs and len(envs) > 0:
            return envs[0].get("name", ""), envs[0].get("id", ""), ""
        return "", "", ""
    except json.JSONDecodeError:
        return "", "", f"Failed to parse environment list: {result}"


def create_container_apps_environment(
    resource_group: str,
    environment_name: str,
    subnet_id: str,
    log_analytics_workspace_id: str = None,
    zone_redundant: bool = False,
    workload_profile_type: str = "Consumption",
    internal_only: bool = False
) -> str:
    """
    Creates a Container Apps Environment with VNet integration.
    
    The environment is automatically deployed in the SAME region as the Resource Group.
    
    Args:
        resource_group: Resource group name (environment will use same region)
        environment_name: Name for the Container Apps Environment
        subnet_id: Full resource ID of subnet for VNet integration. REQUIRED.
            Subnet requirements: minimum /23 for Consumption, /27 for workload profiles
        log_analytics_workspace_id: Full resource ID of existing Log Analytics workspace. 
            If not provided, auto-discovers first workspace in the resource group.
        zone_redundant: Enable zone redundancy for high availability
        workload_profile_type: Consumption, D4, D8, D16, D32, E4, E8, E16, E32
        internal_only: If true, no public ingress (internal VNet only)
    
    Returns:
        Deployment result with environment details
    """
    # Validate required parameters
    missing = []
    if not resource_group:
        missing.append("resource_group")
    if not environment_name:
        missing.append("environment_name")
    if not subnet_id:
        missing.append("subnet_id (full resource ID of subnet for VNet integration)")
    
    if missing:
        return f"""Missing required parameters for Container Apps Environment:
  - {chr(10).join(missing)}

Required information:
  1. resource_group: Target resource group (environment will use same region)
  2. environment_name: Name for the Container Apps Environment
  3. subnet_id: Full subnet resource ID for VNet integration
     Format: /subscriptions/{{sub}}/resourceGroups/{{rg}}/providers/Microsoft.Network/virtualNetworks/{{vnet}}/subnets/{{subnet}}

Optional:
  - log_analytics_workspace_id: Full resource ID of Log Analytics workspace (auto-discovered if omitted)
  - zone_redundant: Enable zone redundancy (default: false)
  - workload_profile_type: Consumption, D4, D8, etc. (default: Consumption)
  - internal_only: No public ingress (default: false)"""
    
    # Auto-discover Log Analytics workspace if not provided
    if not log_analytics_workspace_id:
        try:
            result = subprocess.run(
                ["az", "monitor", "log-analytics", "workspace", "list",
                 "--resource-group", resource_group,
                 "--query", "[0].id", "-o", "tsv"],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode == 0 and result.stdout.strip():
                log_analytics_workspace_id = result.stdout.strip()
            else:
                return f"""No Log Analytics workspace found in resource group '{resource_group}'.

Please create one first or provide log_analytics_workspace_id parameter.
Format: /subscriptions/{{sub}}/resourceGroups/{{rg}}/providers/Microsoft.OperationalInsights/workspaces/{{name}}"""
        except Exception as e:
            return f"Error discovering Log Analytics workspace: {e}"
    
    # Get resource group location
    rg_location, err = _get_resource_group_location(resource_group)
    if err:
        return err
    if not rg_location:
        return f"Error: Could not determine location for resource group '{resource_group}'"
    
    # Validate subnet_id format
    if not subnet_id.startswith("/subscriptions/"):
        return f"""Invalid subnet_id format.

Expected format:
  /subscriptions/{{sub}}/resourceGroups/{{rg}}/providers/Microsoft.Network/virtualNetworks/{{vnet}}/subnets/{{subnet}}

The subnet must:
  - Be minimum /23 CIDR for Consumption workload profile
  - Be minimum /27 CIDR for dedicated workload profiles
  - Not have any other delegations"""
    
    # Validate log_analytics_workspace_id format
    if not log_analytics_workspace_id.startswith("/subscriptions/") or "Microsoft.OperationalInsights/workspaces" not in log_analytics_workspace_id:
        return f"""Invalid log_analytics_workspace_id format.

Expected format:
  /subscriptions/{{sub}}/resourceGroups/{{rg}}/providers/Microsoft.OperationalInsights/workspaces/{{workspaceName}}"""
    
    # Build parameters for Bicep deployment
    params = {
        "environmentName": environment_name,
        "location": rg_location,
        "infrastructureSubnetId": subnet_id,
        "logAnalyticsWorkspaceId": log_analytics_workspace_id,
        "zoneRedundant": str(zone_redundant).lower(),
        "workloadProfileType": workload_profile_type,
        "internalOnly": str(internal_only).lower()
    }
    
    output_lines = []
    output_lines.append("=" * 70)
    output_lines.append("CREATING CONTAINER APPS ENVIRONMENT")
    output_lines.append("=" * 70)
    output_lines.append("")
    output_lines.append(f"  Environment Name: {environment_name}")
    output_lines.append(f"  Resource Group:   {resource_group}")
    output_lines.append(f"  Location:         {rg_location} (same as RG)")
    output_lines.append(f"  Workload Profile: {workload_profile_type}")
    output_lines.append(f"  Zone Redundant:   {zone_redundant}")
    output_lines.append(f"  Internal Only:    {internal_only}")
    output_lines.append(f"  VNet Subnet:      {subnet_id.split('/')[-1]}")
    output_lines.append(f"  Log Analytics:    {log_analytics_workspace_id.split('/')[-1]}")
    output_lines.append("")
    
    # Deploy using Bicep
    result = deploy_bicep(resource_group, "container-apps-env", params)
    output_lines.append(result)
    
    return "\n".join(output_lines)


def create_container_app(
    resource_group: str,
    container_app_name: str,
    environment_name: str = None,
    target_port: int = 80,
    external_ingress: bool = True,
    cpu: str = "0.5",
    memory: str = "1Gi",
    min_replicas: int = 0,
    max_replicas: int = 10,
    env_vars: list = None,
    subnet_id: str = None
) -> str:
    """
    Creates a Container App using the default quickstart image, auto-creating environment if none exists.
    
    The environment is auto-detected from the resource group. If no environment exists,
    one is automatically created (with VNet if subnet_id provided, otherwise Azure-managed).
    
    Args:
        resource_group: Resource group containing the Container Apps Environment
        container_app_name: Name for the Container App
        environment_name: Name of existing environment (auto-detected/created if not provided)
        target_port: Port the container listens on (default: 80)
        external_ingress: Public access (default: True)
        cpu: CPU cores - 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2 (default: 0.5)
        memory: Memory - 0.5Gi, 1Gi, 1.5Gi, 2Gi, 3Gi, 3.5Gi, 4Gi (default: 1Gi)
        min_replicas: Minimum replicas (default: 0)
        max_replicas: Maximum replicas (default: 10)
        env_vars: Environment variables as list of {"name": "VAR", "value": "val"}
        subnet_id: Optional subnet for VNet integration when auto-creating environment
    
    Returns:
        Deployment result with Container App details and FQDN
    """
    # Validate required parameters
    missing = []
    if not resource_group:
        missing.append("resource_group")
    if not container_app_name:
        missing.append("container_app_name")
    
    if missing:
        return f"""Missing required parameters for Container App:
  - {chr(10).join(missing)}

Required: resource_group, container_app_name

Example:
  create_container_app(
    resource_group='my-rg',
    container_app_name='myapp'
  )

Optional parameters:
  - environment_name: Auto-detected/created if not specified
  - subnet_id: Subnet for VNet integration when auto-creating environment
  - target_port: Container port (default: 80)
  - external_ingress: Public access (default: True)
  - cpu, memory, min_replicas, max_replicas"""
    
    # Auto-detect environment if not provided
    actual_env_name = environment_name
    env_created = False
    if not actual_env_name:
        env_name, env_id, err = _find_container_apps_environment(resource_group)
        if err:
            return f"Error finding Container Apps Environment: {err}"
        if not env_name:
            # No environment exists - create one automatically
            auto_env_name = f"{container_app_name}-env"
            create_result = create_container_apps_environment(
                resource_group=resource_group,
                environment_name=auto_env_name,
                subnet_id=subnet_id
            )
            if "Error" in create_result or "Failed" in create_result:
                return f"""No Container Apps Environment found. Auto-creation failed:

{create_result}"""
            actual_env_name = auto_env_name
            env_created = True
        else:
            actual_env_name = env_name
    
    # Get resource group location for the container app
    rg_location, err = _get_resource_group_location(resource_group)
    if err:
        return err
    
    # Build parameters for Bicep deployment
    params = {
        "containerAppName": container_app_name,
        "location": rg_location,
        "environmentName": actual_env_name,
        "targetPort": str(target_port),
        "externalIngress": str(external_ingress).lower(),
        "cpu": cpu,
        "memory": memory,
        "minReplicas": str(min_replicas),
        "maxReplicas": str(max_replicas)
    }
    
    if env_vars:
        params["envVars"] = json.dumps(env_vars)
    
    output_lines = []
    output_lines.append("=" * 70)
    output_lines.append("CREATING CONTAINER APP")
    output_lines.append("=" * 70)
    output_lines.append("")
    output_lines.append(f"  Container App:   {container_app_name}")
    output_lines.append(f"  Resource Group:  {resource_group}")
    env_status = " (auto-created)" if env_created else (" (auto-detected)" if not environment_name else "")
    output_lines.append(f"  Environment:     {actual_env_name}" + env_status)
    output_lines.append(f"  Location:        {rg_location}")
    output_lines.append("")
    output_lines.append(f"  Image Source:    Default (mcr.microsoft.com/azuredocs/containerapps-helloworld)")
    output_lines.append("")
    output_lines.append(f"  CPU:             {cpu}")
    output_lines.append(f"  Memory:          {memory}")
    output_lines.append(f"  Replicas:        {min_replicas} - {max_replicas}")
    output_lines.append(f"  External Access: {external_ingress}")
    output_lines.append(f"  Target Port:     {target_port}")
    output_lines.append("")
    
    # Deploy using Bicep
    result = deploy_bicep(resource_group, "container-app", params)
    output_lines.append(result)
    
    return "\n".join(output_lines)


# ============================================================================
# Azure Resource Management
# ============================================================================

# Parameter descriptions for user guidance (description, example)
PARAM_DESCRIPTIONS = {
    "functionAppName": ("Function App name (globally unique)", "func-myapp-001"),
    "storageAccountName": ("Storage account name (3-24 chars, lowercase)", "stmyappstorage"),
    "uamiName": ("User Assigned Managed Identity name", "uami-myapp"),
    "location": ("Azure region", "eastus, westus2, centralindia"),
    "runtimeStack": ("Runtime language", "python, node, dotnet-isolated, java"),
    "runtimeVersion": ("Runtime version", "3.11 for Python, 20 for Node"),
    "maximumInstanceCount": ("Max scaling instances (1-1000)", "100"),
    "instanceMemoryMB": ("Instance memory in MB", "512, 2048, 4096"),
    "skuName": ("SKU/pricing tier", "B1, S1, P1v2, P1v3"),
    "instanceCount": ("Number of instances", "1-30"),
    "alwaysOn": ("Keep app always running", "true, false"),
    "accessTier": ("Storage access tier", "Hot, Cool"),
    "enableHierarchicalNamespace": ("Enable ADLS Gen2", "true, false"),
    "keyVaultName": ("Key Vault name (globally unique)", "kv-myapp-001"),
    "capacityName": ("Fabric capacity name", "fabriccap001"),
    "sku": ("Fabric SKU", "F2, F4, F8, F16, F32, F64"),
    "adminMembers": ("Admin email addresses", "user@contoso.com"),
    "workspaceName": ("Log Analytics workspace name", "law-myapp-001"),
    "retentionInDays": ("Data retention in days", "30, 90, 180, 365"),
    "nspName": ("Network Security Perimeter name", "nsp-myapp"),
    "vnetName": ("Virtual Network name", "vnet-myapp"),
    "addressPrefix": ("VNet address space", "10.0.0.0/16"),
    "subnetName": ("Subnet name", "subnet-default"),
    "subnetPrefix": ("Subnet address range", "10.0.1.0/24"),
    "appServiceName": ("App Service name (globally unique)", "app-myapp-001"),
    "linuxFxVersion": ("Runtime stack version", "PYTHON|3.11, NODE|20-lts"),
    "cosmosAccountName": ("Cosmos DB account name", "cosmos-myapp-001"),
    "databaseName": ("Database name", "mydb"),
    "containerName": ("Container/collection name", "mycontainer"),
    "registryName": ("Container Registry name", "acrmyapp001"),
    "sqlServerName": ("SQL Server name", "sql-myapp-001"),
    "entraAdminLogin": ("Entra admin email", "admin@contoso.com"),
    "entraAdminObjectId": ("Entra admin Object ID (GUID)", "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"),
}


def get_bicep_requirements(resource_type: str) -> str:
    """Returns required/optional params for a Bicep template in a formatted display."""
    # Check if the resource type has variants - ask user to specify first
    if resource_type in RESOURCE_VARIANTS:
        variants = RESOURCE_VARIANTS[resource_type]
        response = []
        response.append("=" * 70)
        response.append(f"  {resource_type.upper()} - SELECT VARIANT")
        response.append("=" * 70)
        response.append("")
        response.append("This resource has multiple options. Choose one first:")
        response.append("")
        for variant_key, variant_desc in variants.items():
            response.append(f"  [{variant_key}]")
            response.append(f"      {variant_desc}")
            response.append("")
        response.append("=" * 70)
        return "\n".join(response)
    
    if resource_type not in TEMPLATE_MAP:
        return f"Unknown resource_type. Valid: {', '.join(sorted(TEMPLATE_MAP.keys()))}"
    
    template_path = get_template_path(TEMPLATE_MAP[resource_type])
    params = parse_bicep_parameters(template_path)
    
    auto_calculated = []
    if resource_type == "fabric-capacity":
        auto_calculated.append("location")
        tenant_region = get_fabric_tenant_region()
    
    required = [p for p, (req, _) in params.items() if req and p not in auto_calculated]
    optional = [(p, params[p][1]) for p, (req, _) in params.items() if not req and p not in auto_calculated]
    
    response = []
    response.append("=" * 70)
    response.append(f"  {resource_type.upper()} - PARAMETERS")
    response.append("=" * 70)
    response.append("")
    
    response.append("REQUIRED")
    response.append("-" * 70)
    response.append(f"  {'Parameter':<28} {'Description':<30} {'Example'}")
    response.append("-" * 70)
    for param in required:
        desc, example = PARAM_DESCRIPTIONS.get(param, (param, ""))
        response.append(f"  {param:<28} {desc:<30} {example}")
        meta = PARAM_METADATA.get(param, {})
        allowed = meta.get('allowed', [])
        if allowed:
            response.append(f"  {'':<28} Allowed: {', '.join(allowed)}")
    response.append("")
    
    if optional:
        response.append("OPTIONAL (with defaults)")
        response.append("-" * 70)
        response.append(f"  {'Parameter':<28} {'Default':<15} {'Example'}")
        response.append("-" * 70)
        for param, default in optional:
            if param in auto_calculated:
                continue
            desc, example = PARAM_DESCRIPTIONS.get(param, (param, ""))
            default_str = str(default) if default else "-"
            response.append(f"  {param:<28} {default_str:<15} {example}")
            meta = PARAM_METADATA.get(param, {})
            allowed = meta.get('allowed', [])
            if allowed:
                response.append(f"  {'':<28} Allowed: {', '.join(allowed)}")
        response.append("")
    
    if resource_type == "fabric-capacity":
        region = tenant_region if tenant_region else "westcentralus"
        response.append(f"AUTO-DETECTED: location = {region}")
        response.append("")
    
    response.append("=" * 70)
    
    return "\n".join(response)


def create_resource(resource_type: str, resource_group: str = None, parameters: str = None) -> str:
    """Interactive Azure resource creation with formatted parameter prompts."""
    # Check if the resource type has variants that require user choice
    if resource_type in RESOURCE_VARIANTS:
        variants = RESOURCE_VARIANTS[resource_type]
        response = []
        response.append("=" * 70)
        response.append(f"  CREATE {resource_type.upper()} - SELECT HOSTING PLAN")
        response.append("=" * 70)
        response.append("")
        response.append("This resource has multiple hosting options. Please choose one:")
        response.append("")
        for variant_key, variant_desc in variants.items():
            response.append(f"  [{variant_key}]")
            response.append(f"      {variant_desc}")
            response.append("")
        response.append("-" * 70)
        response.append(f"Reply with your choice (e.g., '{list(variants.keys())[0]}')")
        response.append("=" * 70)
        return "\n".join(response)
    
    if resource_type not in TEMPLATE_MAP:
        return f"Invalid resource type. Supported types:\n" + "\n".join([f"  - {rt}" for rt in sorted(TEMPLATE_MAP.keys())])
    
    params_dict = {}
    if parameters:
        try:
            params_dict = json.loads(parameters) if isinstance(parameters, str) else parameters
        except json.JSONDecodeError:
            return f"Error: Invalid JSON in parameters: {parameters}"
    
    template_path = get_template_path(TEMPLATE_MAP[resource_type])
    template_params = parse_bicep_parameters(template_path)
    
    auto_calculated = []
    if resource_type == "fabric-capacity":
        auto_calculated.append("location")
    
    required_params = [p for p, (req, _) in template_params.items() if req and p not in auto_calculated]
    optional_params = [(p, template_params[p][1]) for p, (req, _) in template_params.items() if not req and p not in auto_calculated]
    
    # If no resource group provided, ask for everything at once
    if not resource_group:
        all_missing = required_params
    else:
        all_missing = [p for p in required_params if p not in params_dict or params_dict[p] in (None, "")]
    
    if not resource_group or all_missing:
        response = []
        response.append("=" * 70)
        response.append(f"  CREATE {resource_type.upper()}")
        response.append("=" * 70)
        response.append("")
        
        # Always show resource group first if missing
        if not resource_group:
            response.append("REQUIRED PARAMETERS")
            response.append("-" * 70)
            response.append(f"  {'Parameter':<28} {'Description':<30} {'Example'}")
            response.append("-" * 70)
            response.append(f"  {'resource_group':<28} {'Resource group name':<30} {'rg-myapp-dev'}")
        else:
            response.append(f"Resource Group: {resource_group}")
            response.append("")
            response.append("REQUIRED PARAMETERS")
            response.append("-" * 70)
            response.append(f"  {'Parameter':<28} {'Description':<30} {'Example'}")
            response.append("-" * 70)
        
        # Add all required parameters with allowed values
        params_to_show = required_params if not resource_group else all_missing
        for param in params_to_show:
            desc, example = PARAM_DESCRIPTIONS.get(param, (param, ""))
            meta = PARAM_METADATA.get(param, {})
            allowed = meta.get('allowed', [])
            response.append(f"  {param:<28} {desc:<30} {example}")
            if allowed:
                response.append(f"  {'':<28} Allowed: {', '.join(allowed)}")
            constraints = []
            if meta.get('min_length'):
                constraints.append(f"min length: {meta['min_length']}")
            if meta.get('max_length'):
                constraints.append(f"max length: {meta['max_length']}")
            if meta.get('min_value') is not None:
                constraints.append(f"min: {meta['min_value']}")
            if meta.get('max_value') is not None:
                constraints.append(f"max: {meta['max_value']}")
            if constraints:
                response.append(f"  {'':<28} Constraints: {', '.join(constraints)}")
        
        response.append("")
        
        # Show optional parameters with defaults and allowed values
        display_optional = [(p, d) for p, d in optional_params if p not in auto_calculated]
        if resource_type == "fabric-capacity":
            display_optional = [(p, d) for p, d in display_optional if p != "location"]
        
        if display_optional:
            response.append("OPTIONAL PARAMETERS (with defaults)")
            response.append("-" * 70)
            response.append(f"  {'Parameter':<28} {'Default':<15} {'Example'}")
            response.append("-" * 70)
            for param, default in display_optional:
                desc, example = PARAM_DESCRIPTIONS.get(param, (param, ""))
                default_str = str(default) if default else "-"
                response.append(f"  {param:<28} {default_str:<15} {example}")
                meta = PARAM_METADATA.get(param, {})
                allowed = meta.get('allowed', [])
                if allowed:
                    response.append(f"  {'':<28} Allowed: {', '.join(allowed)}")
            response.append("")
        
        # Special notes
        if resource_type == "fabric-capacity":
            response.append("NOTE: Location is auto-detected from your Fabric tenant region.")
            response.append("")
        elif resource_type == "subnet":
            response.append("NOTE: Subnet IP range must be within the VNet address space.")
            response.append("")
        elif resource_type in ["function-app-flex", "function-app-appserviceplan", "function-app"]:
            response.append("NOTE: Requires existing Storage Account and UAMI with")
            response.append("      'Storage Blob Data Contributor' role assigned.")
            response.append("")
        elif resource_type == "redis":
            response.append("NOTE: Redis cache provisioning typically takes 15-20 minutes.")
            response.append("         The deployment will run in the background on Azure.")
            response.append("")
        
        response.append("=" * 70)
        
        return "\n".join(response)
    
    return deploy_bicep_resource(resource_group, resource_type, params_dict)


def deploy_bicep_resource(resource_group: str, resource_type: str, parameters: dict) -> str:
    """Internal deployment function - validates and deploys a resource.
    
    Re-asks user for missing or invalid parameters instead of just failing.
    """
    if not resource_group or not resource_group.strip():
        return "STOP: Resource group name is required. Please provide the resource group name."
    
    if not resource_type or not resource_type.strip():
        return f"STOP: Resource type is required. Valid types: {', '.join(TEMPLATE_MAP.keys())}"
    
    ok, msg, parsed_params = validate_bicep_parameters(resource_type, parameters)
    if not ok:
        response = []
        response.append("=" * 70)
        response.append(f"  CANNOT DEPLOY {resource_type.upper()} - PARAMETERS NEEDED")
        response.append("=" * 70)
        response.append("")
        response.append(f"  Resource Group: {resource_group}")
        response.append("")
        response.append(f"  Issue: {msg}")
        response.append("")
        
        # Show what was provided
        if parameters:
            response.append("  Parameters received:")
            for k, v in parameters.items():
                if v not in (None, ""):
                    response.append(f"    {k}: {v}")
            response.append("")
        
        # Show what's still missing with allowed values
        missing = [p for p, (req, _) in parsed_params.items() if req and (p not in parameters or parameters.get(p) in (None, ""))]
        if missing:
            response.append("  MISSING REQUIRED PARAMETERS:")
            response.append("-" * 70)
            for param in missing:
                meta = PARAM_METADATA.get(param, {})
                desc = meta.get('description', param)
                allowed = meta.get('allowed', [])
                response.append(f"    {param}: {desc}")
                if allowed:
                    response.append(f"      Allowed values: {', '.join(allowed)}")
            response.append("")
        
        response.append("=" * 70)
        response.append("Please provide the missing/corrected parameters and try again.")
        response.append("=" * 70)
        return "\n".join(response)
    
    return deploy_bicep(resource_group, resource_type, parameters)


# ============================================================================
# PRIVATE ENDPOINT WITH DNS - Intelligent PE + DNS Zone Management
# ============================================================================

def _check_dns_zone_exists(resource_group: str, dns_zone_name: str) -> tuple:
    """
    Check if a Private DNS Zone exists and return its details.
    
    Returns:
        (exists: bool, dns_zone_id: str, error: str)
        - exists: True if zone exists, False if it doesn't
        - dns_zone_id: The resource ID if exists, empty string otherwise
        - error: Error message if check failed (not a "not found" error)
    """
    cmd = [
        "az", "network", "private-dns", "zone", "show",
        "-g", resource_group,
        "-n", dns_zone_name,
        "-o", "json"
    ]
    result = run_command(cmd)
    
    # Check for "not found" errors - this means zone doesn't exist
    if "ResourceNotFound" in result or "was not found" in result.lower():
        return False, "", ""
    
    # Check for other errors (permissions, network, etc.)
    if "ERROR" in result or "error" in result.lower():
        return False, "", f"Error checking DNS zone: {result}"
    
    try:
        data = json.loads(result)
        return True, data.get("id", ""), ""
    except (json.JSONDecodeError, KeyError):
        return False, "", ""


def _check_vnet_link_exists(resource_group: str, dns_zone_name: str, vnet_id: str) -> tuple:
    """
    Check if a VNet link already exists for the given DNS zone and VNet.
    
    Returns:
        (exists: bool, link_name: str, error: str)
    """
    cmd = [
        "az", "network", "private-dns", "link", "vnet", "list",
        "-g", resource_group,
        "-z", dns_zone_name,
        "-o", "json"
    ]
    result = run_command(cmd)
    
    # Check for errors
    if "ERROR" in result or "error" in result.lower():
        return False, "", f"Error checking VNet links: {result}"
    
    try:
        links = json.loads(result)
        for link in links:
            linked_vnet = link.get("virtualNetwork", {}).get("id", "")
            if linked_vnet.lower() == vnet_id.lower():
                return True, link.get("name", ""), ""
        return False, "", ""
    except (json.JSONDecodeError, KeyError):
        return False, "", ""


def _extract_vnet_id_from_subnet(subnet_id: str) -> str:
    """Extract VNet ID from subnet ID."""
    # Subnet ID format: /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}
    parts = subnet_id.split("/")
    if len(parts) >= 9:
        return "/".join(parts[:9])
    return ""


def create_private_endpoint(
    resource_group: str,
    private_endpoint_name: str,
    target_resource_id: str,
    group_id: str,
    subnet_id: str,
    location: str,
    vnet_id: str = None,
    vnet_link_name: str = None
) -> str:
    """
    Creates a Private Endpoint with automatic DNS zone configuration.
    
    This function intelligently handles DNS zone management:
    1. If DNS zone doesn't exist: Creates PE + DNS zone + VNet link
    2. If DNS zone exists but VNet link doesn't: Creates PE + adds VNet link
    3. If both exist: Creates PE and links to existing DNS zone
    
    Args:
        resource_group: Resource group name for the private endpoint
        private_endpoint_name: Name for the private endpoint
        target_resource_id: Resource ID of the target Azure resource
        group_id: Sub-resource type (e.g., 'blob', 'vault', 'sqlServer')
        subnet_id: Resource ID of the subnet for the PE
        location: Azure region (should match VNet location)
        vnet_id: Optional VNet ID (extracted from subnet_id if not provided)
        vnet_link_name: Optional name for VNet link
    
    Returns:
        Deployment status with details about PE and DNS configuration
    """
    # Validate required parameters
    missing_params = []
    if not resource_group:
        missing_params.append("resource_group")
    if not private_endpoint_name:
        missing_params.append("private_endpoint_name")
    if not target_resource_id:
        missing_params.append("target_resource_id")
    if not group_id:
        missing_params.append("group_id")
    if not subnet_id:
        missing_params.append("subnet_id")
    if not location:
        missing_params.append("location")
    
    if missing_params:
        return f"STOP: Missing required parameters: {', '.join(missing_params)}"
    
    # Get DNS zone name from mapping
    dns_zone_name = PRIVATE_DNS_ZONE_MAP.get(group_id)
    if not dns_zone_name:
        return f"""STOP: Unknown group_id '{group_id}'.

Valid group IDs include:
  Storage: blob, file, table, queue, dfs, web
  Key Vault: vault
  Cosmos DB: Sql, MongoDB, Cassandra, Gremlin, Table
  SQL Database: sqlServer
  App Service/Functions: sites
  Cognitive Services/OpenAI: account
  Container Registry: registry
  AI Search: searchService
  Data Factory: dataFactory, portal
  And more...

Please use a valid group_id from the above list."""
    
    # Extract VNet ID if not provided
    if not vnet_id:
        vnet_id = _extract_vnet_id_from_subnet(subnet_id)
    
    if not vnet_id:
        return "STOP: Could not extract VNet ID from subnet_id. Please provide vnet_id parameter."
    
    vnet_name = vnet_id.split("/")[-1]
    actual_link_name = vnet_link_name if vnet_link_name else f"{vnet_name}-link"
    
    output_lines = []
    output_lines.append("=" * 70)
    output_lines.append("PRIVATE ENDPOINT CREATION WITH DNS")
    output_lines.append("=" * 70)
    output_lines.append("")
    
    # Check if DNS zone already exists
    dns_exists, existing_dns_id, dns_check_error = _check_dns_zone_exists(resource_group, dns_zone_name)
    
    if dns_check_error:
        output_lines.append(f"[WARN] {dns_check_error}")
        output_lines.append("[INFO] Proceeding to create new DNS zone...")
        dns_exists = False
    
    if dns_exists:
        output_lines.append(f"[INFO] Private DNS Zone '{dns_zone_name}' already exists")
        
        # Check if VNet link already exists
        link_exists, existing_link_name, link_check_error = _check_vnet_link_exists(resource_group, dns_zone_name, vnet_id)
        
        if link_check_error:
            output_lines.append(f"[WARN] {link_check_error}")
            output_lines.append("[INFO] Proceeding to create new VNet link...")
            link_exists = False
        
        if link_exists:
            output_lines.append(f"[INFO] VNet link '{existing_link_name}' already exists for VNet '{vnet_name}'")
            output_lines.append("")
            output_lines.append("Creating Private Endpoint and linking to existing DNS zone...")
            output_lines.append("")
            
            # Deploy PE with existing DNS zone reference, skip VNet link
            pe_params = {
                "privateEndpointName": private_endpoint_name,
                "location": location,
                "targetResourceId": target_resource_id,
                "groupId": group_id,
                "subnetId": subnet_id,
                "existingDnsZoneId": existing_dns_id,
                "skipVnetLink": "true"
            }
            deploy_result = deploy_bicep(resource_group, "private-endpoint", pe_params)
            output_lines.append(deploy_result)
            
            # Check for deployment failure
            if "FAILED" in deploy_result or "Failed" in deploy_result or "error" in deploy_result.lower():
                output_lines.append("")
                output_lines.append("[ERROR] Private Endpoint deployment failed. See details above.")
            
        else:
            output_lines.append(f"[INFO] VNet link does not exist for VNet '{vnet_name}'")
            output_lines.append("")
            output_lines.append("Creating Private Endpoint and adding new VNet link to existing DNS zone...")
            output_lines.append("")
            
            # First, add VNet link to existing DNS zone
            link_params = {
                "privateDnsZoneName": dns_zone_name,
                "vnetId": vnet_id,
                "vnetLinkName": actual_link_name
            }
            link_result = deploy_bicep(resource_group, "dns-zone-vnet-link", link_params)
            output_lines.append("VNet Link Creation:")
            output_lines.append(link_result)
            output_lines.append("")
            
            # Check if VNet link creation succeeded before creating PE
            if "FAILED" in link_result or "Failed" in link_result or "error" in link_result.lower():
                output_lines.append("[ERROR] VNet Link creation failed. Aborting PE creation.")
                return "\n".join(output_lines)
            
            # Then deploy PE with existing DNS zone reference
            pe_params = {
                "privateEndpointName": private_endpoint_name,
                "location": location,
                "targetResourceId": target_resource_id,
                "groupId": group_id,
                "subnetId": subnet_id,
                "existingDnsZoneId": existing_dns_id,
                "skipVnetLink": "true"
            }
            output_lines.append("Private Endpoint Creation:")
            pe_result = deploy_bicep(resource_group, "private-endpoint", pe_params)
            output_lines.append(pe_result)
    
    else:
        output_lines.append(f"[INFO] Private DNS Zone '{dns_zone_name}' does not exist")
        output_lines.append("")
        output_lines.append("Creating Private Endpoint + DNS Zone + VNet Link...")
        output_lines.append("")
        
        # Deploy PE with DNS zone creation (no existingDnsZoneId = creates new zone)
        pe_params = {
            "privateEndpointName": private_endpoint_name,
            "location": location,
            "targetResourceId": target_resource_id,
            "groupId": group_id,
            "subnetId": subnet_id,
            "vnetId": vnet_id,
            "vnetLinkName": actual_link_name
        }
        deploy_result = deploy_bicep(resource_group, "private-endpoint", pe_params)
        output_lines.append(deploy_result)
    
    output_lines.append("")
    output_lines.append("=" * 70)
    output_lines.append("SUMMARY")
    output_lines.append("=" * 70)
    output_lines.append(f"  Private Endpoint: {private_endpoint_name}")
    output_lines.append(f"  Target Resource:  {target_resource_id.split('/')[-1]}")
    output_lines.append(f"  Group ID:         {group_id}")
    output_lines.append(f"  DNS Zone:         {dns_zone_name}")
    output_lines.append(f"  VNet:             {vnet_name}")
    output_lines.append(f"  VNet Link:        {actual_link_name}")
    output_lines.append("")
    
    return "\n".join(output_lines)


# ============================================================================
# PRIVATE ENDPOINT CONNECTION MANAGEMENT
# ============================================================================

def _get_resource_type_for_pe_connection(resource_id: str) -> tuple:
    """
    Extract resource type info for private endpoint connection commands.
    
    Returns:
        (resource_type: str, type_param: str)
        e.g., ('Microsoft.Storage/storageAccounts', 'Microsoft.Storage/storageAccounts')
    """
    # Parse resource ID to get provider and type
    # Format: /subscriptions/{sub}/resourceGroups/{rg}/providers/{provider}/{type}/{name}
    parts = resource_id.split("/providers/")
    if len(parts) < 2:
        return "", ""
    
    provider_parts = parts[1].split("/")
    if len(provider_parts) >= 2:
        resource_type = f"{provider_parts[0]}/{provider_parts[1]}"
        return resource_type, resource_type
    
    return "", ""


def _parse_resource_id(resource_id: str) -> tuple:
    """Extract resource group and resource name from a resource ID."""
    parts = resource_id.split("/")
    rg_index = -1
    for i, part in enumerate(parts):
        if part.lower() == "resourcegroups":
            rg_index = i + 1
            break
    
    if rg_index < 0 or rg_index >= len(parts):
        return "", ""
    
    return parts[rg_index], parts[-1]


def manage_private_endpoint_connection(
    action: str,
    resource_id: str = None,
    connection_id: str = None,
    connection_name: str = None,
    description: str = None
) -> str:
    """
    Unified tool for managing private endpoint connections on Azure resources.
    
    Actions:
        - list: List all PE connections on a resource (pending/approved/rejected)
        - approve: Approve a pending PE connection
        - reject: Reject a PE connection
    
    Args:
        action: Action to perform - 'list', 'approve', or 'reject'
        resource_id: Full resource ID of the target resource (required for 'list')
        connection_id: Full PE connection ID (for approve/reject - preferred)
        connection_name: PE connection name (for approve/reject with resource_id)
        description: Approval/rejection reason (optional)
    
    Returns:
        Result of the action
    """
    if not action:
        return """STOP: 'action' is required.

Valid actions:
  - list: List PE connections on a resource
  - approve: Approve a pending connection
  - reject: Reject a connection

Example:
  manage_private_endpoint_connection(action='list', resource_id='...')
  manage_private_endpoint_connection(action='approve', connection_id='...')"""
    
    action = action.lower().strip()
    
    # ========== LIST ==========
    if action == "list":
        if not resource_id:
            return "STOP: 'resource_id' is required for listing PE connections."
        
        cmd = [
            "az", "network", "private-endpoint-connection", "list",
            "--id", resource_id,
            "-o", "json"
        ]
        
        result = run_command(cmd)
        
        if "ERROR" in result or "error" in result.lower():
            return f"Error listing private endpoint connections: {result}"
        
        try:
            connections = json.loads(result)
            if not connections:
                return "No private endpoint connections found on this resource."
            
            output_lines = []
            output_lines.append("=" * 70)
            output_lines.append("PRIVATE ENDPOINT CONNECTIONS")
            output_lines.append("=" * 70)
            output_lines.append("")
            
            pending_count = 0
            approved_count = 0
            rejected_count = 0
            
            for conn in connections:
                conn_id = conn.get("id", "")
                conn_name = conn.get("name", "Unknown")
                props = conn.get("properties", {})
                pls_props = props.get("privateLinkServiceConnectionState", {})
                status = pls_props.get("status", "Unknown")
                desc = pls_props.get("description", "")
                pe_id = props.get("privateEndpoint", {}).get("id", "")
                pe_name = pe_id.split("/")[-1] if pe_id else "Unknown"
                
                if status.lower() == "pending":
                    pending_count += 1
                    status_icon = "⏳"
                elif status.lower() == "approved":
                    approved_count += 1
                    status_icon = "✅"
                elif status.lower() == "rejected":
                    rejected_count += 1
                    status_icon = "❌"
                else:
                    status_icon = "❓"
                
                output_lines.append(f"{status_icon} Connection: {conn_name}")
                output_lines.append(f"   Status:           {status}")
                output_lines.append(f"   Private Endpoint: {pe_name}")
                if desc:
                    output_lines.append(f"   Description:      {desc}")
                output_lines.append(f"   Connection ID:    {conn_id}")
                output_lines.append("")
            
            output_lines.append("-" * 70)
            output_lines.append(f"Summary: {len(connections)} total | {pending_count} pending | {approved_count} approved | {rejected_count} rejected")
            output_lines.append("")
            
            if pending_count > 0:
                output_lines.append("To approve a pending connection:")
                output_lines.append("  azure_manage_pe_connection(action='approve', connection_id='<id>')")
            
            return "\n".join(output_lines)
            
        except json.JSONDecodeError:
            return f"Error parsing response: {result}"
    
    # ========== APPROVE / REJECT ==========
    elif action in ["approve", "reject"]:
        if not description:
            description = f"{'Approved' if action == 'approve' else 'Rejected'} by Azure Platform Agent"
        
        if connection_id:
            cmd = [
                "az", "network", "private-endpoint-connection", action,
                "--id", connection_id,
                "--description", description,
                "-o", "json"
            ]
        elif resource_id and connection_name:
            resource_type, _ = _get_resource_type_for_pe_connection(resource_id)
            if not resource_type:
                return "STOP: Could not determine resource type from resource_id."
            
            resource_group, resource_name = _parse_resource_id(resource_id)
            if not resource_group:
                return "STOP: Could not parse resource group from resource_id."
            
            cmd = [
                "az", "network", "private-endpoint-connection", action,
                "-g", resource_group,
                "-n", connection_name,
                "--resource-name", resource_name,
                "--type", resource_type,
                "--description", description,
                "-o", "json"
            ]
        else:
            return f"""STOP: Missing parameters for '{action}'.

Provide either:
  - connection_id: Full PE connection ID (from 'list' action)

Or both:
  - resource_id: Resource ID of the target
  - connection_name: PE connection name"""
        
        action_title = "APPROVING" if action == "approve" else "REJECTING"
        action_past = "approved" if action == "approve" else "rejected"
        
        output_lines = []
        output_lines.append("=" * 70)
        output_lines.append(f"{action_title} PRIVATE ENDPOINT CONNECTION")
        output_lines.append("=" * 70)
        output_lines.append("")
        
        result = run_command(cmd)
        
        if "ERROR" in result or "error" in result.lower():
            output_lines.append(f"[ERROR] Failed to {action} connection:")
            output_lines.append(result)
            return "\n".join(output_lines)
        
        try:
            data = json.loads(result)
            status = data.get("properties", {}).get("privateLinkServiceConnectionState", {}).get("status", "Unknown")
            
            output_lines.append(f"[SUCCESS] Private endpoint connection {action_past}!")
            output_lines.append("")
            output_lines.append(f"  Connection: {data.get('name', 'Unknown')}")
            output_lines.append(f"  Status:     {status}")
            output_lines.append(f"  Reason:     {description}")
            
        except json.JSONDecodeError:
            if action_past in result.lower() or "succeeded" in result.lower():
                output_lines.append(f"[SUCCESS] Private endpoint connection {action_past}!")
            else:
                output_lines.append(result)
        
        output_lines.append("")
        return "\n".join(output_lines)
    
    else:
        return f"""STOP: Invalid action '{action}'.

Valid actions:
  - list: List PE connections on a resource
  - approve: Approve a pending connection
  - reject: Reject a connection"""


def assign_rbac_role(
    scope: str,
    object_ids: list,
    role_names: list,
    principal_type: str
) -> str:
    """
    Assigns Azure RBAC roles to Service Principals (SPN) or Managed Identities (MSI/WSI) only.
    
    POLICY: Direct RBAC role assignments to Users or Groups are NOT allowed.
    Use Managed Identities or Service Principals for programmatic access.
    
    Supports all scenarios:
    - Single role to single identity
    - Multiple roles to single identity
    - Single role to multiple identities
    - Multiple roles to multiple identities
    """
    # Validate required parameters
    missing = []
    if not scope:
        missing.append("scope (e.g., /subscriptions/<sub-id>/resourceGroups/<rg-name>)")
    if not object_ids:
        missing.append("object_ids (list of Object IDs / Principal IDs)")
    if not role_names:
        missing.append("role_names (list of role names, e.g., 'Storage Blob Data Contributor')")
    if not principal_type:
        missing.append("principal_type (ServicePrincipal or ManagedIdentity)")
    
    if missing:
        return "Missing required parameters:\n" + "\n".join([f"  - {m}" for m in missing])
    
    # Validate principal type - ONLY allow ServicePrincipal or ManagedIdentity
    valid_principal_types = ["ServicePrincipal", "ManagedIdentity"]
    principal_type_normalized = principal_type.strip()
    
    # Check for blocked principal types (User or Group)
    blocked_types = ["User", "Group"]
    if principal_type_normalized in blocked_types:
        return f"""RBAC Role Assignment Blocked

Direct RBAC role assignments to {principal_type_normalized}s are not recommended.

Security Best Practice:
   Azure RBAC roles should NOT be assigned directly to Users or Groups.
   Instead, use Privileged Identity Management (PIM) for user access,
   or Managed Identities/Service Principals for application access.

Recommended Alternatives:

   For User Access - Use Azure PIM (Privileged Identity Management):
      - PIM provides just-in-time (JIT) privileged access
      - Users activate roles only when needed, with time-limited access
      - Requires approval workflows and audit trails
      - Reduces standing access and attack surface
      - Configure PIM at: Azure Portal > Entra ID > Privileged Identity Management
   
   For Application/Service Access - Use Managed Identity:
      - Attach a Managed Identity to your compute resource (VM, App Service, Function, etc.)
      - Assign the RBAC role to the Managed Identity's Principal ID
      - No credentials to manage or rotate
   
   For External Apps/Automation - Use Service Principal:
      - Create an App Registration in Entra ID
      - Assign the RBAC role to the Service Principal's Object ID

Why Direct User/Group RBAC is Not Recommended:
   - Creates permanent standing access (security risk)
   - No activation workflow or time limits
   - Harder to audit and review
   - Violates principle of least privilege

To Proceed:
   - For user access: Configure PIM roles in Azure Portal instead
   - For application access: Provide a Managed Identity Principal ID or Service Principal Object ID,
     and set principal_type to 'ServicePrincipal' or 'ManagedIdentity'"""
    
    # Validate it's one of the allowed types
    if principal_type_normalized not in valid_principal_types:
        return f"Invalid principal_type: '{principal_type}'\n\nAllowed values: {', '.join(valid_principal_types)}\n\nNote: User and Group assignments are blocked by policy. Use Managed Identity or Service Principal instead."
    
    # Ensure lists
    if isinstance(object_ids, str):
        object_ids = [object_ids]
    if isinstance(role_names, str):
        role_names = [role_names]
    
    # Validate scope format
    if not scope.startswith("/subscriptions/"):
        return f"Invalid scope format. Scope must start with '/subscriptions/<subscription-id>/...'\n\nExamples:\n  - Subscription: /subscriptions/<sub-id>\n  - Resource Group: /subscriptions/<sub-id>/resourceGroups/<rg-name>\n  - Resource: /subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/<provider>/<resource-type>/<resource-name>"
    
    script_path = get_script_path("assign-azure-rbac.ps1")
    if not os.path.exists(script_path):
        return "Error: assign-azure-rbac.ps1 not found"
    
    # Convert lists to PowerShell array format
    object_ids_str = ",".join(object_ids)
    role_names_str = ",".join(role_names)
    
    params = {
        "Scope": scope,
        "ObjectIds": object_ids_str,
        "RoleNames": role_names_str
    }
    
    try:
        return run_powershell_script(script_path, params)
    except Exception as e:
        return f"Azure RBAC role assignment failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {script_path}\nParameters: {params}\n\nCommon causes:\n- Not authenticated: Run 'az login' or 'Connect-AzAccount'\n- You don't have Owner or User Access Administrator role on the scope\n- Invalid Object ID (use Object ID, not Application ID for SPNs)\n- Role name is incorrect or doesn't exist\n- Invalid scope format"


# ============================================================================
# Azure PIM (Privileged Identity Management)
# ============================================================================

def list_pim_roles() -> str:
    """
    Lists eligible PIM (Privileged Identity Management) roles for the current user.
    
    Returns all eligible roles across ALL scopes (subscriptions, resource groups, resources)
    with role name, scope, and maximum allowed activation hours.
    """
    script_path = get_script_path("list-pim-roles.ps1")
    if not os.path.exists(script_path):
        return "Error: list-pim-roles.ps1 not found"
    
    try:
        return run_powershell_script(script_path, {})
    except Exception as e:
        return f"Failed to list PIM roles\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nCommon causes:\n- Not authenticated: Run 'Connect-AzAccount'\n- No eligible PIM roles assigned to your account"


def activate_pim_roles(
    justification: str = None,
    activate_all: bool = False,
    subscription_name: str = None,
    resource_group_name: str = None,
    resource_name: str = None,
    role_name: str = None,
    duration_hours: int = 0
) -> str:
    """
    Activates eligible PIM roles for the current user.
    
    Two modes:
    1. activate_all=True: Activates ALL eligible roles across ALL scopes
    2. activate_all=False: Activates a specific role at a specific scope
    
    Args:
        justification: Business justification for the activation (REQUIRED)
        activate_all: If True, activates ALL eligible roles across all scopes
        subscription_name: Subscription name (for specific role mode)
        resource_group_name: Resource group name (optional, for RG-level scope)
        resource_name: Resource name (optional, for resource-level scope)
        role_name: Role name to activate (for specific role mode)
        duration_hours: Duration in hours. If 0 or not specified, uses max allowed per role.
    """
    # Validate required parameters
    if not justification:
        return "Missing required parameter: justification\n\nYou MUST ask the user for their business justification before activating PIM roles."
    
    if not activate_all:
        # Specific role mode requires role_name and subscription_name
        missing = []
        if not role_name:
            missing.append("role_name (e.g., 'Contributor', 'Azure AI User')")
        if not subscription_name:
            missing.append("subscription_name (e.g., 'MCAPSDE_DEV')")
        
        if missing:
            return "Missing required parameters for specific role activation:\n" + "\n".join([f"  - {m}" for m in missing]) + "\n\nOr set activate_all=True to activate all eligible roles."
    
    script_path = get_script_path("activate-pim.ps1")
    if not os.path.exists(script_path):
        return "Error: activate-pim.ps1 not found"
    
    # Build parameters
    params = {
        "Justification": justification
    }
    
    # Only pass DurationHours if specified (> 0)
    if duration_hours and duration_hours > 0:
        params["DurationHours"] = str(duration_hours)
    
    if activate_all:
        params["ActivateAll"] = "$true"
    else:
        # Pass subscription name, RG, resource, and role name for specific mode
        params["SubscriptionName"] = subscription_name
        params["RoleName"] = role_name
        
        if resource_group_name:
            params["ResourceGroupName"] = resource_group_name
        if resource_name:
            params["ResourceName"] = resource_name
    
    try:
        return run_powershell_script(script_path, params)
    except Exception as e:
        return f"Failed to activate PIM roles\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nCommon causes:\n- Not authenticated: Run 'Connect-AzAccount'\n- No eligible PIM roles at the specified scope\n- Duration exceeds maximum allowed by policy\n- Role requires approval (check PIM portal)\n- Az.Resources module not installed"


def assign_pim_eligible_role(
    scope: str = None,
    principal_id: str = None,
    role_name: str = None,
    duration: str = "P1Y",
    tenant_id: str = None,
    subscription_id: str = None
) -> str:
    """
    Assigns a PIM eligible role to a principal using EasyPIM module.
    
    Creates an eligible (not active) role assignment that the principal can
    activate when needed via PIM.
    
    NOTE: PIM eligible roles can ONLY be assigned at Subscription or Resource Group level.
    Resource-level PIM assignments are NOT supported.
    
    Args:
        scope: Target scope for the role assignment (required)
               - Subscription: /subscriptions/{sub-id}
               - Resource Group: /subscriptions/{sub-id}/resourceGroups/{rg-name}
               (Resource-level scope is NOT supported for PIM)
        principal_id: Object ID of the user, group, or service principal (required)
        role_name: Name of the role to assign (required)
                   e.g., 'Contributor', 'Storage Blob Data Contributor', 'Reader'
        duration: ISO 8601 duration for the eligible assignment (default: P1Y = 1 year)
                  Examples: P1Y (1 year), P6M (6 months), P30D (30 days)
        tenant_id: Azure AD tenant ID (optional, uses current context if not provided)
        subscription_id: Subscription ID (optional, uses current context if not provided)
    
    Returns:
        Assignment result
    """
    if not scope:
        return """STOP: 'scope' is required.

Provide the target scope for the role assignment:
  - Subscription: /subscriptions/{subscription-id}
  - Resource Group: /subscriptions/{sub-id}/resourceGroups/{rg-name}

NOTE: PIM eligible roles can ONLY be assigned at Subscription or Resource Group level.
Resource-level PIM assignments are NOT supported."""
    
    if not principal_id:
        return """STOP: 'principal_id' is required.

Provide the object ID of the user, group, or service principal to assign the role to.
You can find this in Azure Portal > Entra ID > Users/Groups > select user > Object ID"""
    
    if not role_name:
        return """STOP: 'role_name' is required.

Common Azure roles:
  - Contributor
  - Reader
  - Owner
  - Storage Blob Data Contributor
  - Storage Blob Data Reader
  - Key Vault Administrator
  - Key Vault Secrets User"""
    
    script_path = get_script_path("assign-eligible-pim.ps1")
    if not os.path.exists(script_path):
        return "Error: assign-eligible-pim.ps1 not found"
    
    params = {
        "Scope": scope,
        "PrincipalID": principal_id,
        "RoleName": role_name,
        "Duration": duration
    }
    
    if tenant_id:
        params["TenantID"] = tenant_id
    if subscription_id:
        params["SubscriptionID"] = subscription_id
    
    output_lines = []
    output_lines.append("=" * 70)
    output_lines.append("ASSIGNING PIM ELIGIBLE ROLE")
    output_lines.append("=" * 70)
    output_lines.append("")
    output_lines.append(f"  Role:         {role_name}")
    output_lines.append(f"  Principal ID: {principal_id}")
    output_lines.append(f"  Scope:        {scope}")
    output_lines.append(f"  Duration:     {duration}")
    output_lines.append("")
    
    try:
        result = run_powershell_script(script_path, params)
        output_lines.append(result)
        return "\n".join(output_lines)
    except Exception as e:
        output_lines.append(f"[ERROR] Failed to assign PIM eligible role")
        output_lines.append(f"Error: {str(e)}")
        output_lines.append("")
        output_lines.append("Common causes:")
        output_lines.append("  - EasyPIM module auto-install failed (check network/permissions)")
        output_lines.append("  - Not authenticated: Run Connect-AzAccount")
        output_lines.append("  - Insufficient permissions to assign PIM roles")
        output_lines.append("  - Invalid principal ID or scope")
        return "\n".join(output_lines)


# ============================================================================
# DATA COLLECTION ENDPOINT & DATA COLLECTION RULE
# ============================================================================

def create_data_collection_endpoint(
    resource_group: str,
    dce_name: str,
    public_network_access: str = "Enabled",
    description: str = ""
) -> str:
    """
    Creates a Data Collection Endpoint (DCE) for Azure Monitor.
    
    DCE is required for:
    - Logs Ingestion API (custom logs)
    - Azure Monitor Private Link Scope (AMPLS)
    - VNet-isolated data ingestion
    
    Args:
        resource_group: Resource group name
        dce_name: Name for the Data Collection Endpoint
        public_network_access: Enabled, Disabled, or SecuredByPerimeter (default: Enabled)
        description: Optional description for the DCE
    
    Returns:
        Deployment result with DCE details and endpoints
    """
    missing = []
    if not resource_group:
        missing.append("resource_group")
    if not dce_name:
        missing.append("dce_name")
    
    if missing:
        return f"""Missing required parameters for Data Collection Endpoint:
  - {chr(10).join(missing)}

Required information:
  1. resource_group: Target resource group
  2. dce_name: Name for the Data Collection Endpoint

Optional:
  - public_network_access: Enabled (default), Disabled, SecuredByPerimeter
  - description: Optional description"""
    
    # Get resource group location
    rg_location, err = _get_resource_group_location(resource_group)
    if err:
        return err
    
    params = {
        "dceName": dce_name,
        "location": rg_location,
        "publicNetworkAccess": public_network_access
    }
    
    if description:
        params["description"] = description
    
    output_lines = []
    output_lines.append("=" * 70)
    output_lines.append("CREATING DATA COLLECTION ENDPOINT")
    output_lines.append("=" * 70)
    output_lines.append("")
    output_lines.append(f"  DCE Name:              {dce_name}")
    output_lines.append(f"  Resource Group:        {resource_group}")
    output_lines.append(f"  Location:              {rg_location}")
    output_lines.append(f"  Public Network Access: {public_network_access}")
    output_lines.append("")
    
    result = deploy_bicep(resource_group, "dce", params)
    output_lines.append(result)
    
    return "\n".join(output_lines)


def create_data_collection_rule(
    resource_group: str,
    dcr_name: str,
    workspace_name: str,
    dce_name: str,
    custom_table_base_name: str,
    table_columns: list = None,
    create_table: bool = True,
    workspace_resource_group: str = None,
    dce_resource_group: str = None,
    retention_in_days: int = 90,
    total_retention_in_days: int = 180,
    dcr_description: str = "Custom ingestion via Logs Ingestion API"
) -> str:
    """
    Creates a Data Collection Rule (DCR) with optional custom Log Analytics table.
    
    Prerequisites:
    1. Log Analytics Workspace must exist
    2. Data Collection Endpoint (DCE) must exist
    
    Args:
        resource_group: Resource group for the DCR
        dcr_name: Name for the Data Collection Rule
        workspace_name: Existing Log Analytics workspace name
        dce_name: Existing Data Collection Endpoint name
        custom_table_base_name: Base name for custom table (without _CL suffix)
        table_columns: List of column definitions. Default: TimeGenerated, Message
            Format: [{"name": "ColumnName", "type": "string|dateTime|int|..."}]
        create_table: True to create the custom table (default: True)
        workspace_resource_group: RG containing workspace (defaults to resource_group)
        dce_resource_group: RG containing DCE (defaults to resource_group)
        retention_in_days: Interactive retention (default: 90)
        total_retention_in_days: Total retention including archive (default: 180)
        dcr_description: Description for the DCR
    
    Returns:
        Deployment result with DCR details, table name, and stream name
    """
    missing = []
    if not resource_group:
        missing.append("resource_group")
    if not dcr_name:
        missing.append("dcr_name")
    if not workspace_name:
        missing.append("workspace_name (existing Log Analytics workspace)")
    if not dce_name:
        missing.append("dce_name (existing Data Collection Endpoint)")
    if not custom_table_base_name:
        missing.append("custom_table_base_name (e.g., 'MyCustomLogs' creates 'MyCustomLogs_CL')")
    
    if missing:
        return f"""Missing required parameters for Data Collection Rule:
  - {chr(10).join(missing)}

Required information:
  1. resource_group: Resource group for the DCR
  2. dcr_name: Name for the Data Collection Rule
  3. workspace_name: Existing Log Analytics workspace name
  4. dce_name: Existing Data Collection Endpoint name
  5. custom_table_base_name: Base name for custom table (without _CL suffix)

Optional:
  - table_columns: Column definitions (default: TimeGenerated, Message)
  - create_table: Create the table if true (default: true)
  - workspace_resource_group: RG containing workspace
  - dce_resource_group: RG containing DCE
  - retention_in_days: Interactive retention (default: 90)
  - total_retention_in_days: Total retention (default: 180)"""
    
    # Get resource group location
    rg_location, err = _get_resource_group_location(resource_group)
    if err:
        return err
    
    # Default columns if not provided
    if not table_columns:
        table_columns = [
            {"name": "TimeGenerated", "type": "dateTime"},
            {"name": "Message", "type": "string"}
        ]
    
    params = {
        "dcrName": dcr_name,
        "location": rg_location,
        "workspaceName": workspace_name,
        "dceName": dce_name,
        "customTableBaseName": custom_table_base_name,
        "createTable": str(create_table).lower(),
        "retentionInDays": str(retention_in_days),
        "totalRetentionInDays": str(total_retention_in_days),
        "dcrDescription": dcr_description,
        "tableColumns": json.dumps(table_columns)
    }
    
    if workspace_resource_group:
        params["workspaceResourceGroup"] = workspace_resource_group
    if dce_resource_group:
        params["dceResourceGroup"] = dce_resource_group
    
    output_lines = []
    output_lines.append("=" * 70)
    output_lines.append("CREATING DATA COLLECTION RULE")
    output_lines.append("=" * 70)
    output_lines.append("")
    output_lines.append(f"  DCR Name:         {dcr_name}")
    output_lines.append(f"  Resource Group:   {resource_group}")
    output_lines.append(f"  Location:         {rg_location}")
    output_lines.append(f"  Workspace:        {workspace_name}")
    output_lines.append(f"  DCE:              {dce_name}")
    output_lines.append(f"  Custom Table:     {custom_table_base_name}_CL")
    output_lines.append(f"  Create Table:     {create_table}")
    output_lines.append(f"  Retention:        {retention_in_days} days (total: {total_retention_in_days})")
    output_lines.append("")
    
    result = deploy_bicep(resource_group, "dcr", params)
    output_lines.append(result)
    
    return "\n".join(output_lines)


def attach_dce_to_dcr(
    dcr_name: str,
    dcr_resource_group: str,
    dce_name: str,
    dce_resource_group: str = None,
    subscription_id: str = None
) -> str:
    """
    Attaches a Data Collection Endpoint (DCE) to a Data Collection Rule (DCR).
    
    This is required for:
    - Logs Ingestion API
    - Azure Monitor Private Link Scope (AMPLS)
    - VNet-isolated data ingestion
    
    Args:
        dcr_name: Name of the Data Collection Rule
        dcr_resource_group: Resource group containing the DCR
        dce_name: Name of the Data Collection Endpoint to attach
        dce_resource_group: Resource group containing the DCE (defaults to dcr_resource_group)
        subscription_id: Optional subscription ID
    
    Returns:
        Result of the attachment operation
    """
    missing = []
    if not dcr_name:
        missing.append("dcr_name")
    if not dcr_resource_group:
        missing.append("dcr_resource_group")
    if not dce_name:
        missing.append("dce_name")
    
    if missing:
        return f"""Missing required parameters for attaching DCE to DCR:
  - {chr(10).join(missing)}

Required information:
  1. dcr_name: Name of the Data Collection Rule
  2. dcr_resource_group: Resource group containing the DCR
  3. dce_name: Name of the Data Collection Endpoint

Optional:
  - dce_resource_group: RG containing DCE (defaults to dcr_resource_group)
  - subscription_id: Subscription ID"""
    
    script_path = get_script_path("attach-dce.ps1")
    if not os.path.exists(script_path):
        return "Error: attach-dce.ps1 not found"
    
    params = {
        "DcrName": dcr_name,
        "DcrResourceGroup": dcr_resource_group,
        "DceName": dce_name
    }
    
    if dce_resource_group:
        params["DceResourceGroup"] = dce_resource_group
    if subscription_id:
        params["SubscriptionId"] = subscription_id
    
    output_lines = []
    output_lines.append("=" * 70)
    output_lines.append("ATTACHING DCE TO DCR")
    output_lines.append("=" * 70)
    output_lines.append("")
    output_lines.append(f"  DCR:  {dcr_name} (RG: {dcr_resource_group})")
    output_lines.append(f"  DCE:  {dce_name} (RG: {dce_resource_group or dcr_resource_group})")
    output_lines.append("")
    
    result = run_powershell_script(script_path, params)
    output_lines.append(result)
    
    return "\n".join(output_lines)
