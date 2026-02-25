# ============================================================================
# FABRIC FUNCTIONS - Microsoft Fabric logic
# ============================================================================

import os
import json
from typing import Optional

try:
    from .utils import run_powershell_script, get_script_path
except ImportError:
    from utils import run_powershell_script, get_script_path


def list_permissions(user_principal_name: str = None) -> str:
    """Lists Microsoft Fabric workspace permissions for the current user."""
    script_path = get_script_path("list-fabric-permissions.ps1")
    if not os.path.exists(script_path):
        return "Error: list-fabric-permissions.ps1 not found"
    
    params = {}
    if user_principal_name:
        params["UserPrincipalName"] = user_principal_name
    
    try:
        return run_powershell_script(script_path, params)
    except Exception as e:
        return f"Fabric permissions list failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {script_path}\n\nCommon causes:\n- Not authenticated: Run 'az login'\n- No Fabric access\n- Invalid user principal name\n- Fabric API unavailable"


def create_managed_private_endpoint(
    workspace_id: str,
    endpoint_name: str,
    target_resource_id: str,
    group_id: str
) -> str:
    """Creates a Managed Private Endpoint in Microsoft Fabric for secure outbound connectivity to Azure resources."""
    if not workspace_id:
        return json.dumps({"error": "workspace_id is required"})
    if not endpoint_name:
        return json.dumps({"error": "endpoint_name is required"})
    if not target_resource_id:
        return json.dumps({"error": "target_resource_id is required"})
    if not group_id:
        return json.dumps({"error": "group_id is required (e.g., 'blob', 'dfs', 'vault', 'sqlServer')"})
    
    script_path = get_script_path("create-fabric-managed-pe.ps1")
    if not os.path.exists(script_path):
        return "Error: create-fabric-managed-pe.ps1 not found"
    
    params = {
        "WorkspaceId": workspace_id,
        "EndpointName": endpoint_name,
        "TargetResourceId": target_resource_id,
        "GroupId": group_id
    }
    
    try:
        return run_powershell_script(script_path, params)
    except Exception as e:
        return f"Fabric managed private endpoint creation failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {script_path}\n\nCommon causes:\n- Not authenticated: Run 'az login'\n- No Admin/Contributor access to Fabric workspace\n- Invalid workspace ID or resource ID\n- Fabric capacity doesn't support managed private endpoints"


def list_managed_private_endpoints(workspace_id: str) -> str:
    """Lists all Managed Private Endpoints in a Fabric workspace."""
    if not workspace_id:
        return json.dumps({"error": "workspace_id is required"})
    
    script_path = get_script_path("list-fabric-managed-pe.ps1")
    if not os.path.exists(script_path):
        return "Error: list-fabric-managed-pe.ps1 not found"
    
    params = {
        "WorkspaceId": workspace_id
    }
    
    try:
        return run_powershell_script(script_path, params)
    except Exception as e:
        return f"Fabric list managed private endpoints failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {script_path}\n\nCommon causes:\n- Not authenticated: Run 'az login'\n- Invalid workspace ID\n- No access to the workspace"


def create_workspace(capacity_id: str = None, workspace_name: str = None, 
                     description: str = "") -> str:
    """Creates a Microsoft Fabric workspace in a capacity."""
    missing = []
    if not capacity_id:
        missing.append("capacity_id (full resource ID)")
    if not workspace_name:
        missing.append("workspace_name")
    
    if missing:
        return "Missing required parameters:\n" + "\n".join([f"  - {m}" for m in missing])
    
    workspace_script = get_script_path("create-fabric-workspace.ps1")
    if not os.path.exists(workspace_script):
        return "Error: create-fabric-workspace.ps1 not found"
    
    params = {
        "CapacityId": capacity_id,
        "WorkspaceName": workspace_name,
        "Description": description
    }
    
    try:
        out = run_powershell_script(workspace_script, params)
        return out.strip()
    except Exception as e:
        return f"Fabric workspace creation failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {workspace_script}\nParameters: {params}\n\nCommon causes:\n- Capacity does not exist or is not active\n- No Fabric admin access\n- Invalid capacity ID\n- Workspace name already exists"


def attach_workspace_to_git(workspace_id: str = None, organization: str = None,
                            project_name: str = None, repo_name: str = None,
                            branch_name: str = None, directory_name: str = "/") -> str:
    """Attaches a Microsoft Fabric workspace to an Azure DevOps Git repository."""
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
    
    if organization and "https://" not in organization:
        organization = f"https://dev.azure.com/{organization}"
    
    git_script = get_script_path("attach-fabric-git.ps1")
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
        out = run_powershell_script(git_script, params)
        return out.strip()
    except Exception as e:
        return f"Fabric Git attachment failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {git_script}\nParameters: {params}\n\nCommon causes:\n- Workspace does not exist\n- Not a workspace admin\n- Repository/branch does not exist\n- No DevOps access\n- Git already connected to this workspace"


def assign_role(
    workspace_identifier: str,
    role_name: str,
    principal_id: str,
    principal_type: str
) -> str:
    """Assigns a role to a user, group, service principal, or managed identity in a Fabric workspace."""
    # Validate required parameters
    missing = []
    if not workspace_identifier:
        missing.append("workspace_identifier (workspace name or workspace ID)")
    if not role_name:
        missing.append("role_name (Admin, Contributor, Member, Viewer)")
    if not principal_id:
        missing.append("principal_id (Object ID / Principal ID of the user, group, SPN, or managed identity)")
    if not principal_type:
        missing.append("principal_type (User, Group, ServicePrincipal, ServicePrincipalProfile)")
    
    if missing:
        return "Missing required parameters:\n" + "\n".join([f"  - {m}" for m in missing])
    
    # Validate role name
    valid_roles = ["Admin", "Contributor", "Member", "Viewer"]
    if role_name not in valid_roles:
        return f"Invalid role_name: '{role_name}'. Must be one of: {', '.join(valid_roles)}"
    
    # Validate principal type
    valid_principal_types = ["User", "Group", "ServicePrincipal", "ServicePrincipalProfile"]
    if principal_type not in valid_principal_types:
        return f"Invalid principal_type: '{principal_type}'. Must be one of: {', '.join(valid_principal_types)}"
    
    script_path = get_script_path("assign-fabric-role.ps1")
    if not os.path.exists(script_path):
        return "Error: assign-fabric-role.ps1 not found"
    
    params = {
        "WorkspaceIdentifier": workspace_identifier,
        "RoleName": role_name,
        "PrincipalId": principal_id,
        "PrincipalType": principal_type
    }
    
    try:
        return run_powershell_script(script_path, params)
    except Exception as e:
        return f"Fabric role assignment failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {script_path}\nParameters: {params}\n\nCommon causes:\n- Not authenticated: Run 'az login'\n- No Admin access to the workspace\n- Invalid workspace ID or name\n- Invalid principal ID (Object ID)\n- Role assignment already exists"