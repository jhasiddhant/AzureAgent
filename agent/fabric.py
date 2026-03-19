# ============================================================================
# FABRIC FUNCTIONS - Microsoft Fabric logic
# ============================================================================

import os
import json
from typing import Optional

try:
    from .utils import run_powershell_script, run_command, get_script_path
except ImportError:
    from utils import run_powershell_script, run_command, get_script_path


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


# ============================================================================
# DEPLOYMENT PIPELINE FUNCTIONS
# ============================================================================

def _resolve_workspace_id(workspace_name: str) -> tuple:
    """Resolve a Fabric workspace name to its ID using the Fabric API.
    
    Returns:
        (workspace_id, error_message) - workspace_id is empty string on failure
    """
    script_content = f"""
$tokenResponse = az account get-access-token --resource https://analysis.windows.net/powerbi/api | ConvertFrom-Json
if (-not $tokenResponse -or -not $tokenResponse.accessToken) {{ Write-Error "AUTH_FAILED"; exit 1 }}
$headers = @{{ "Authorization" = "Bearer $($tokenResponse.accessToken)"; "Content-Type" = "application/json" }}
$response = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces" -Method Get -Headers $headers
$ws = $response.value | Where-Object {{ $_.displayName -eq '{workspace_name.replace("'", "''")}' }} | Select-Object -First 1
if ($ws) {{ Write-Output $ws.id }} else {{ Write-Error "WORKSPACE_NOT_FOUND: {workspace_name}" }}
"""
    result = run_command(["powershell.exe", "-ExecutionPolicy", "Bypass", "-Command", script_content])
    result = result.strip()
    if "WORKSPACE_NOT_FOUND" in result or "AUTH_FAILED" in result or "ERROR" in result.upper():
        return "", result
    return result, ""


def _create_single_pipeline(
    pipeline_name: str,
    stage_names: list,
    workspace_names_list: list,
    description: str = ""
) -> str:
    """Creates a single pipeline with given stages and assigns workspaces 1:1.
    
    Args:
        pipeline_name: Name for the pipeline
        stage_names: List of stage names (e.g. ["Development", "Production"])
        workspace_names_list: List of workspace names, same length as stage_names
        description: Optional description
    
    Returns:
        Result string
    """
    import re

    script_path = get_script_path("create-deployment-pipeline.ps1")
    if not os.path.exists(script_path):
        return "Error: create-deployment-pipeline.ps1 not found"

    stages_csv = ",".join(stage_names)
    params = {
        "PipelineName": pipeline_name,
        "Description": description,
        "Stages": stages_csv
    }

    try:
        create_result = run_powershell_script(script_path, params)
    except Exception as e:
        return (f"Fabric deployment pipeline '{pipeline_name}' creation failed\n\n"
                f"Error: {str(e)}\nError Type: {type(e).__name__}\n\n"
                "Common causes:\n- Not authenticated: Run 'az login'\n"
                "- No Fabric access\n- Pipeline name already exists")

    if "ERROR" in create_result.upper() and "SUCCESS" not in create_result.upper():
        return create_result

    # Extract pipeline ID
    pipeline_id = ""
    try:
        for line in create_result.split("\n"):
            line = line.strip()
            if '"id"' in line and '"displayName"' not in line:
                pipeline_id = line.split('"')[3]
                break
        if not pipeline_id:
            match = re.search(r'"id"\s*:\s*"([a-f0-9-]+)"', create_result)
            if match:
                pipeline_id = match.group(1)
    except Exception:
        pass

    if not pipeline_id:
        return create_result + "\n\nWARNING: Pipeline created but could not extract pipeline ID for workspace assignment."

    output = [create_result]
    output.append("")
    output.append(f"Pipeline ID: {pipeline_id}")
    output.append("=" * 50)
    output.append(f"Assigning workspaces to pipeline '{pipeline_name}' stages...")
    output.append("=" * 50)

    # Resolve all workspace names to IDs
    ws_ids = []
    for ws_name in workspace_names_list:
        ws_id, err = _resolve_workspace_id(ws_name)
        if not ws_id:
            output.append(f"\nERROR: Could not resolve workspace '{ws_name}': {err}")
            return "\n".join(output)
        ws_ids.append((ws_name, ws_id))

    # Get pipeline stage IDs
    stages_script = get_script_path("get-deployment-pipeline-stages.ps1")
    if not os.path.exists(stages_script):
        output.append("\nERROR: get-deployment-pipeline-stages.ps1 not found. Workspaces not assigned.")
        return "\n".join(output)

    try:
        stages_result = run_powershell_script(stages_script, {"PipelineId": pipeline_id})
    except Exception as e:
        output.append(f"\nERROR: Failed to get pipeline stages: {str(e)}")
        return "\n".join(output)

    stage_ids = re.findall(r'"id"\s*:\s*"([a-f0-9-]+)"', stages_result)
    if len(stage_ids) < len(stage_names):
        output.append(f"\nERROR: Expected {len(stage_names)} stage IDs, got {len(stage_ids)}.\n{stages_result}")
        return "\n".join(output)

    # Assign each workspace to its corresponding stage
    assign_script = get_script_path("assign-deployment-pipeline-workspace.ps1")
    if not os.path.exists(assign_script):
        output.append("\nERROR: assign-deployment-pipeline-workspace.ps1 not found.")
        return "\n".join(output)

    for i, (ws_name, ws_id) in enumerate(ws_ids):
        try:
            result = run_powershell_script(assign_script, {
                "PipelineId": pipeline_id,
                "StageId": stage_ids[i],
                "WorkspaceId": ws_id
            })
            output.append(f"\nWorkspace '{ws_name}' -> {stage_names[i]}: {result}")
        except Exception as e:
            output.append(f"\nERROR assigning '{ws_name}' to {stage_names[i]}: {str(e)}")

    output.append("")
    output.append("=" * 50)
    output.append("NEXT STEP: Assign roles to this pipeline using:")
    output.append(f"  Tool: fabric_add_deployment_pipeline_role")
    output.append(f"  Pipeline ID: {pipeline_id}")
    output.append(f"  Required: user_email, role (default: Admin)")
    output.append("=" * 50)

    return "\n".join(output)


def create_deployment_pipeline(
    pipeline_name: str,
    pipeline_type: str,
    workspace_names: str,
    description: str = ""
) -> str:
    """Creates Fabric deployment pipeline(s) and assigns workspaces to stages.
    
    Args:
        pipeline_name: Name for the pipeline (used as prefix for Dev-to-UAT-to-Prod)
        pipeline_type: REQUIRED - Must be one of:
            - "Dev-to-Prod": 2 workspaces (Dev, Prod)
            - "UAT-to-Prod": 2 workspaces (UAT, Prod)
            - "Dev-to-UAT-to-Prod": 3 workspaces (Dev, UAT, Prod)
        workspace_names: Comma-separated workspace names.
            Dev-to-Prod: "DevWS,ProdWS" (2 names)
            UAT-to-Prod: "UATWS,ProdWS" (2 names)
            Dev-to-UAT-to-Prod: "DevWS,UATWS,ProdWS" (3 names)
        description: Optional description for the pipeline(s)
    
    Returns:
        Pipeline creation and workspace assignment results
    """
    missing = []
    if not pipeline_name:
        missing.append("pipeline_name")
    if not pipeline_type:
        missing.append("pipeline_type")
    if not workspace_names:
        missing.append("workspace_names")
    if missing:
        return "Missing required parameters:\n" + "\n".join([f"  - {m}" for m in missing])

    allowed_types = ["Dev-to-Prod", "UAT-to-Prod", "Dev-to-UAT-to-Prod"]
    if not pipeline_type:
        return f"""ERROR: pipeline_type is REQUIRED. You must choose one of the following:
  - Dev-to-Prod: Creates 1 pipeline (Development -> Production), requires 2 workspaces
  - UAT-to-Prod: Creates 1 pipeline (UAT -> Production), requires 2 workspaces
  - Dev-to-UAT-to-Prod: Creates 2 pipelines (Dev->UAT + UAT->Prod), requires 3 workspaces

Please specify which deployment pipeline type you want to create."""
    if pipeline_type not in allowed_types:
        return f"Invalid pipeline_type '{pipeline_type}'. Allowed values: {', '.join(allowed_types)}"

    ws_list = [w.strip() for w in workspace_names.split(",") if w.strip()]

    if pipeline_type == "Dev-to-Prod":
        if len(ws_list) != 2:
            return f"Dev-to-Prod requires exactly 2 workspace names (Dev,Prod), got {len(ws_list)}: {ws_list}"
        return _create_single_pipeline(
            pipeline_name=pipeline_name,
            stage_names=["Development", "Production"],
            workspace_names_list=ws_list,
            description=description
        )

    elif pipeline_type == "UAT-to-Prod":
        if len(ws_list) != 2:
            return f"UAT-to-Prod requires exactly 2 workspace names (UAT,Prod), got {len(ws_list)}: {ws_list}"
        return _create_single_pipeline(
            pipeline_name=pipeline_name,
            stage_names=["UAT", "Production"],
            workspace_names_list=ws_list,
            description=description
        )

    elif pipeline_type == "Dev-to-UAT-to-Prod":
        if len(ws_list) != 3:
            return f"Dev-to-UAT-to-Prod requires exactly 3 workspace names (Dev,UAT,Prod), got {len(ws_list)}: {ws_list}"

        output = []

        # Pipeline 1: Dev -> UAT
        output.append("=" * 60)
        output.append(f"PIPELINE 1: {pipeline_name}-Dev-to-UAT")
        output.append("=" * 60)
        result1 = _create_single_pipeline(
            pipeline_name=f"{pipeline_name}-Dev-to-UAT",
            stage_names=["Development", "UAT"],
            workspace_names_list=[ws_list[0], ws_list[1]],
            description=f"{description} (Dev to UAT)".strip()
        )
        output.append(result1)

        output.append("")

        # Pipeline 2: UAT -> Prod
        output.append("=" * 60)
        output.append(f"PIPELINE 2: {pipeline_name}-UAT-to-Prod")
        output.append("=" * 60)
        result2 = _create_single_pipeline(
            pipeline_name=f"{pipeline_name}-UAT-to-Prod",
            stage_names=["UAT", "Production"],
            workspace_names_list=[ws_list[1], ws_list[2]],
            description=f"{description} (UAT to Prod)".strip()
        )
        output.append(result2)

        return "\n".join(output)


def add_deployment_pipeline_role(
    pipeline_id: str,
    user_email: str,
    role: str = "Admin",
    principal_type: str = "User"
) -> str:
    """Adds a role assignment to a deployment pipeline.
    
    Accepts user email and auto-resolves to Entra ID Object ID.
    
    Args:
        pipeline_id: The deployment pipeline ID (GUID)
        user_email: The user's email address (will be resolved to Object ID)
        role: Role to assign - currently only "Admin" is supported
        principal_type: Type of principal - "User", "Group", "ServicePrincipal", or "ServicePrincipalProfile"
    
    Returns:
        JSON with role assignment result
    """
    missing = []
    if not pipeline_id:
        missing.append("pipeline_id")
    if not user_email:
        missing.append("user_email")
    
    if missing:
        return "Missing required parameters:\n" + "\n".join([f"  - {m}" for m in missing])
    
    # Validate principal type
    valid_principal_types = ["User", "Group", "ServicePrincipal", "ServicePrincipalProfile"]
    if principal_type not in valid_principal_types:
        return f"Invalid principal_type: '{principal_type}'. Must be one of: {', '.join(valid_principal_types)}"
    
    # Resolve user email to Object ID
    resolve_cmd = ["az", "ad", "user", "show", "--id", user_email, "--query", "id", "-o", "tsv"]
    principal_id = run_command(resolve_cmd).strip()
    
    if not principal_id or "ERROR" in principal_id.upper():
        return f"Failed to resolve user email '{user_email}' to Object ID.\n\nResult: {principal_id}\n\nCommon causes:\n- User does not exist in Entra ID\n- Not authenticated: Run 'az login'\n- Email address is incorrect"
    
    script_path = get_script_path("add-deployment-pipeline-role.ps1")
    if not os.path.exists(script_path):
        return "Error: add-deployment-pipeline-role.ps1 not found"
    
    params = {
        "PipelineId": pipeline_id,
        "PrincipalId": principal_id,
        "PrincipalType": principal_type,
        "Role": role
    }
    
    try:
        return run_powershell_script(script_path, params)
    except Exception as e:
        return f"Fabric add deployment pipeline role failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nCommon causes:\n- Not authenticated: Run 'az login'\n- Role assignment already exists\n- Invalid pipeline ID\n- Insufficient permissions"