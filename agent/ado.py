# ============================================================================
# ADO FUNCTIONS - Azure DevOps logic
# ============================================================================

import os
import json
from typing import Optional

try:
    from .utils import (
        run_powershell_script, get_script_path,
        detect_pipeline_type, PIPELINE_TEMPLATE_MAP
    )
except ImportError:
    from utils import (
        run_powershell_script, get_script_path,
        detect_pipeline_type, PIPELINE_TEMPLATE_MAP
    )


# ============================================================================
# Azure DevOps - Projects & Repos
# ============================================================================

def create_project(organization: str = None, project_name: str = None, repo_name: str = None, description: str = None) -> str:
    """Creates an Azure DevOps project using AZ CLI via the PS1 script and sets the initial repo name."""
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

    project_script = get_script_path("create-devops-project.ps1")
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
        proj_out = run_powershell_script(project_script, proj_params)
        return proj_out.strip()
    except Exception as e:
        return f"Project creation failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {project_script}\nParameters: {proj_params}"


def create_repo(organization: str = None, project_name: str = None, repo_name: str = None) -> str:
    """Creates a new Azure DevOps Git repository via the PS1 script."""
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

    repo_script = get_script_path("create-devops-repo.ps1")
    if not os.path.exists(repo_script):
        return "Error: create-devops-repo.ps1 not found"

    params = {
        "Organization": organization,
        "ProjectName": project_name,
        "RepoName": repo_name
    }

    try:
        out = run_powershell_script(repo_script, params)
        return out.strip()
    except Exception as e:
        return f"Repository creation failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {repo_script}\nParameters: {params}"


def list_projects(organization: str = None) -> str:
    """Lists all Azure DevOps projects in an organization."""
    if organization and not organization.strip().lower().startswith("http"):
        organization = f"https://dev.azure.com/{organization.strip()}"

    if not organization or not organization.strip():
        return (
            "ADO List Projects\n\n"
            "Please provide:\n"
            "  - organization (org URL to list projects from)\n\n"
            "Only required input: organization."
        )

    list_projects_script = get_script_path("list-devops-projects.ps1")
    if not os.path.exists(list_projects_script):
        return "Error: list-devops-projects.ps1 not found"

    params = {
        "Organization": organization
    }

    try:
        out = run_powershell_script(list_projects_script, params)
        return out.strip()
    except Exception as e:
        return f"List projects failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {list_projects_script}\n\nCommon causes:\n- Not authenticated: Run 'az login'\n- Missing Azure DevOps extension: Run 'az extension add --name azure-devops'\n- Invalid organization URL\n- No access to organization"


def list_repos(organization: str = None, project_name: str = None) -> str:
    """Lists all Azure DevOps repositories in a project."""
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

    list_repos_script = get_script_path("list-devops-repos.ps1")
    if not os.path.exists(list_repos_script):
        return "Error: list-devops-repos.ps1 not found"

    params = {
        "Organization": organization,
        "ProjectName": project_name
    }

    try:
        out = run_powershell_script(list_repos_script, params)
        return out.strip()
    except Exception as e:
        return f"List repositories failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {list_repos_script}\nParameters: {params}\n\nCommon causes:\n- Project does not exist\n- No access to project\n- Authentication issue"


def create_branch(organization: str = None, project_name: str = None, 
                  repo_name: str = None, branch_name: str = None, 
                  base_branch: str = None) -> str:
    """Creates a new branch in an Azure DevOps repository from a base branch."""
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

    branch_script = get_script_path("create-devops-branch.ps1")
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
        out = run_powershell_script(branch_script, params)
        return out.strip()
    except Exception as e:
        return f"Branch creation failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {branch_script}\nParameters: {params}\n\nCommon causes:\n- Base branch does not exist\n- Branch already exists\n- No write access to repository"


# ============================================================================
# Azure DevOps - Pipelines
# ============================================================================

def deploy_custom_yaml(organization: str, project_name: str, repo_name: str,
                       branch: str, file_name: str, yaml_content: str,
                       folder_path: str = "pipelines") -> str:
    """Deploys custom YAML content directly to an Azure DevOps repository."""
    missing = []
    if not organization or not organization.strip():
        missing.append("organization (Azure DevOps org URL)")
    if not project_name or not project_name.strip():
        missing.append("project_name (existing project)")
    if not repo_name or not repo_name.strip():
        missing.append("repo_name (existing repo)")
    if not branch or not branch.strip():
        missing.append("branch (target branch, e.g., 'main', 'dev')")
    if not file_name or not file_name.strip():
        missing.append("file_name (display name for YAML, e.g., 'sourcebranchvalidation.yml')")
    if not yaml_content or not yaml_content.strip():
        missing.append("yaml_content (the actual YAML content to deploy)")
    
    if missing:
        return (
            "Deploy Custom YAML - Missing Required Parameters\n\n"
            "Please provide:\n"
            + "\n".join([f"  - {m}" for m in missing]) +
            "\n\nExample usage:\n"
            "  organization: 'https://dev.azure.com/myorg'\n"
            "  project_name: 'MyProject'\n"
            "  repo_name: 'MyRepo'\n"
            "  branch: 'dev'\n"
            "  file_name: 'my-pipeline.yml'\n"
            "  yaml_content: '<paste your YAML content>'"
        )
    
    if not organization.strip().lower().startswith("http"):
        organization = f"https://dev.azure.com/{organization.strip()}"
    
    if not file_name.endswith('.yml') and not file_name.endswith('.yaml'):
        file_name = f"{file_name}.yml"
    
    deploy_script = get_script_path("deploy-pipeline-yaml.ps1")
    if not os.path.exists(deploy_script):
        return "Error: deploy-pipeline-yaml.ps1 not found"
    
    params = {
        "Organization": organization,
        "ProjectName": project_name,
        "RepoName": repo_name,
        "TemplateName": file_name.replace('.yml', '').replace('.yaml', ''),
        "Branch": branch,
        "FolderPath": folder_path,
        "CustomYamlContent": yaml_content,
        "YamlFileName": file_name
    }
    
    try:
        out = run_powershell_script(deploy_script, params)
        return out.strip()
    except Exception as e:
        return f"Custom YAML deployment failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {deploy_script}\nParameters: {params}\n\nCommon causes:\n- Repository not initialized\n- Branch does not exist\n- No write access\n- Git authentication failed\n- Invalid YAML syntax"


def deploy_pipeline_yaml(organization: str = None, project_name: str = None, 
                         repo_name: str = None, pipeline_type: str = None,
                         branch: str = None, folder_path: str = None,
                         custom_yaml_content: str = None, yaml_file_name: str = None) -> str:
    """Deploys a pipeline YAML template from agent/templates OR custom YAML content to an Azure DevOps repository."""
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
        missing.append("pipeline_type (template key like 'credscan', 'credscan-1es', or name for custom)")
    if not branch or not branch.strip():
        missing.append("branch (target branch, usually 'main')")
    if missing:
        templates_list = ', '.join(sorted(PIPELINE_TEMPLATE_MAP.keys())) if PIPELINE_TEMPLATE_MAP else "(none)"
        return (
            "Deploy Pipeline YAML\n\n"
            "Please provide:\n"
            + "\n".join([f"  - {m}" for m in missing]) +
            f"\n\nAvailable templates: {templates_list}"
            "\n\nOptional: folder_path (defaults to 'pipelines'), custom_yaml_content, yaml_file_name"
        )

    if not folder_path:
        folder_path = "pipelines"

    deploy_script = get_script_path("deploy-pipeline-yaml.ps1")
    if not os.path.exists(deploy_script):
        return "Error: deploy-pipeline-yaml.ps1 not found"

    if custom_yaml_content:
        yaml_name = yaml_file_name or f"{pipeline_type}.yml"
        if not yaml_name.endswith('.yml') and not yaml_name.endswith('.yaml'):
            yaml_name = f"{yaml_name}.yml"
        
        params = {
            "Organization": organization,
            "ProjectName": project_name,
            "RepoName": repo_name,
            "TemplateName": yaml_name.replace('.yml', '').replace('.yaml', ''),
            "Branch": branch,
            "FolderPath": folder_path,
            "CustomYamlContent": custom_yaml_content,
            "YamlFileName": yaml_name
        }
    else:
        detected_type = detect_pipeline_type(pipeline_type, pipeline_type)
        
        if detected_type in PIPELINE_TEMPLATE_MAP:
            template_basename = os.path.basename(PIPELINE_TEMPLATE_MAP[detected_type])
            params = {
                "Organization": organization,
                "ProjectName": project_name,
                "RepoName": repo_name,
                "TemplateName": template_basename.replace(".yml", ""),
                "Branch": branch,
                "FolderPath": folder_path
            }
        else:
            return (
                f"Pipeline template '{pipeline_type}' not found in agent/templates.\n\n"
                f"Available templates: {', '.join(PIPELINE_TEMPLATE_MAP.keys())}\n\n"
                "To deploy custom YAML, provide the custom_yaml_content parameter with your YAML content."
            )

    try:
        out = run_powershell_script(deploy_script, params)
        return out.strip()
    except Exception as e:
        return f"YAML deployment failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {deploy_script}\nParameters: {params}\n\nCommon causes:\n- Repository not initialized\n- Branch does not exist\n- No write access\n- Git authentication failed"


def create_pipeline(organization: str = None, project_name: str = None,
                    repo_name: str = None, pipeline_name: str = None,
                    branch: str = None, pipeline_type: str = None,
                    yaml_path: str = None) -> str:
    """Creates an Azure DevOps pipeline from YAML file in repository."""
    if organization and not organization.strip().lower().startswith("http"):
        organization = f"https://dev.azure.com/{organization.strip()}"

    if pipeline_name and not pipeline_type:
        pipeline_type = detect_pipeline_type(pipeline_name, "")
    elif not pipeline_type:
        pipeline_type = "credscan"

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
        suggestion = f"\n\nDetected pipeline type: {pipeline_type}"
        if "1es" in pipeline_type or "prod" in pipeline_type:
            suggestion += "\nThis is a PRODUCTION pipeline (1ES template with pool parameters required)"
        else:
            suggestion += "\nThis is a standard pipeline template"
        
        templates_list = ', '.join(sorted(PIPELINE_TEMPLATE_MAP.keys())) if PIPELINE_TEMPLATE_MAP else "(none discovered)"
        
        return (
            "Create Azure DevOps Pipeline\n\n"
            "Please provide:\n"
            + "\n".join([f"  - {m}" for m in missing]) +
            suggestion +
            f"\n\nAvailable templates (auto-discovered): {templates_list}"
        )

    if pipeline_type in PIPELINE_TEMPLATE_MAP:
        template_basename = os.path.basename(PIPELINE_TEMPLATE_MAP[pipeline_type])
    elif PIPELINE_TEMPLATE_MAP:
        first_key = sorted(PIPELINE_TEMPLATE_MAP.keys())[0]
        template_basename = os.path.basename(PIPELINE_TEMPLATE_MAP[first_key])
    else:
        template_basename = "pipeline.yml"
    
    if yaml_path and yaml_path.strip():
        final_yaml_path = yaml_path.strip()
    else:
        final_yaml_path = f"pipelines/{template_basename}"

    pipeline_script = get_script_path("create-devops-pipeline.ps1")
    if not os.path.exists(pipeline_script):
        return "Error: create-devops-pipeline.ps1 not found"

    params = {
        "Organization": organization,
        "ProjectName": project_name,
        "RepoName": repo_name,
        "PipelineName": pipeline_name,
        "Branch": branch,
        "YamlPath": final_yaml_path
    }

    try:
        out = run_powershell_script(pipeline_script, params)
        return out.strip()
    except Exception as e:
        return f"Pipeline creation failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {pipeline_script}\nParameters: {params}\n\nCommon causes:\n- YAML file does not exist in repository\n- No 'Build Administrators' permission\n- Invalid YAML path\n- Branch does not exist"


# ============================================================================
# Azure DevOps - Role Assignment
# ============================================================================

def assign_role(
    organization: str,
    project_name: str,
    role_name: str,
    principal_id: str
) -> str:
    """Assigns a role (security group membership) to a principal in an Azure DevOps project.
    
    Common built-in roles:
    - Project Administrators: Full control over project settings and security
    - Build Administrators: Manage build pipelines and definitions
    - Release Administrators: Manage release pipelines and deployments
    - Contributors: Create and modify code, work items, and pipelines
    - Readers: View-only access to project resources
    - Endpoint Administrators: Manage service connections
    - Endpoint Creators: Create service connections
    
    Custom roles/groups are also supported - provide the exact group name.
    
    Args:
        organization: Azure DevOps organization URL or name (e.g., 'https://dev.azure.com/myorg' or 'myorg')
        project_name: Name of the Azure DevOps project
        role_name: Name of the security group/role to assign
        principal_id: Object ID (GUID) of the user, group, or service principal from Azure AD/Entra ID
    
    Returns:
        Role assignment result with status and details
    """
    # Validate required parameters
    missing = []
    if not organization:
        missing.append("organization (Azure DevOps org URL or name)")
    if not project_name:
        missing.append("project_name (name of the ADO project)")
    if not role_name:
        missing.append("role_name (e.g., 'Project Administrators', 'Contributors', 'Readers')")
    if not principal_id:
        missing.append("principal_id (Object ID / GUID of the user, group, or service principal)")
    
    if missing:
        return "Missing required parameters:\n" + "\n".join([f"  - {m}" for m in missing])
    
    # Normalize organization URL
    if organization and not organization.strip().lower().startswith("http"):
        organization = f"https://dev.azure.com/{organization.strip()}"
    
    script_path = get_script_path("assign-ado-role.ps1")
    if not os.path.exists(script_path):
        return "Error: assign-ado-role.ps1 not found"
    
    params = {
        "Organization": organization,
        "ProjectName": project_name,
        "RoleName": role_name,
        "PrincipalId": principal_id
    }
    
    try:
        return run_powershell_script(script_path, params)
    except Exception as e:
        return f"ADO role assignment failed\n\nError: {str(e)}\nError Type: {type(e).__name__}\n\nScript: {script_path}\nParameters: {params}\n\nCommon causes:\n- Not authenticated: Run 'az login'\n- No Project Administrator or Collection Administrator access\n- Invalid organization URL or project name\n- Invalid principal ID (Object ID)\n- Role/group does not exist in the project"
