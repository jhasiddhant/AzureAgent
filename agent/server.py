# ============================================================================
# MCP SERVER - Tool definitions only
# ============================================================================
# All business logic is in separate modules:
#   - azure.py   : Azure resource management functions
#   - ado.py     : Azure DevOps functions
#   - fabric.py  : Microsoft Fabric functions  
#   - general.py : User identity and instructions
#   - utils.py   : Shared helpers and constants
# ============================================================================

from mcp.server.fastmcp import FastMCP

# Import function modules - handle both package and direct execution
try:
    from . import azure
    from . import ado
    from . import fabric
    from . import general
except ImportError:
    import azure
    import ado
    import fabric
    import general

# ============================================================================
# MCP SERVER INITIALIZATION
# ============================================================================

mcp = FastMCP("azure-agent")

# ============================================================================
# GENERAL TOOLS
# ============================================================================

@mcp.tool()
def get_current_user() -> str:
    """
    Gets the current Azure subscription, tenant, and user email.
    
    Returns:
        JSON with subscription name, subscriptionId, tenantId, and user_email
    """
    return general.get_current_user()


@mcp.tool()
def show_agent_instructions() -> str:
    """
    Returns the complete agent instructions and capabilities documentation.
    Use this to understand the agent's features, supported resources, and operational guidelines.
    """
    return general.show_agent_instructions()


@mcp.tool()
def azure_login(selected_subscription_id: str = None) -> str:
    """
    Login to Azure - for first-time users or switching accounts.
    Opens browser for authentication.
    
    Handles three scenarios automatically:
    1. No subscriptions: Logs in with --allow-no-subscriptions
    2. One subscription: Sets it as default automatically
    3. Multiple subscriptions: Returns list for user to choose, then call again with selected_subscription_id
    
    Args:
        selected_subscription_id: Optional. If user has multiple subscriptions, call this tool again 
                                  with the chosen subscription ID to set it as default.
    
    Returns:
        JSON with login status and subscription info. If action is "choose_subscription", 
        user must select one and call this tool again with selected_subscription_id.
    """
    return general.azure_login(selected_subscription_id)


# ============================================================================
# AZURE TOOLS - Permissions & Subscriptions
# ============================================================================

@mcp.tool()
def azure_list_roles(
    role_type: str = None,
    user_principal_name: str = None,
    force_refresh: bool = True
) -> str:
    """
    Lists Azure roles for the current user - either active assignments or eligible PIM roles.
    
    USE THIS TOOL for ANY request about listing, showing, or viewing Azure roles/permissions.
    
    BEHAVIOR BASED ON USER REQUEST:
    
    1. User asks for "active roles", "current roles", "my assignments", "what roles do I have":
       → Use role_type="active"
       
    2. User asks for "PIM roles", "eligible roles", "roles I can activate":
       → Use role_type="eligible"
       
    3. User just says "list my roles" or "show permissions" WITHOUT specifying type:
       → ASK the user: "Would you like to see your active (currently assigned) roles 
         or eligible (PIM roles available for activation)?"
       → Do NOT guess - the user must specify which type they want
    
    Args:
        role_type: REQUIRED - Type of roles to list:
            - "active": Currently active/assigned RBAC roles (includes permanent assignments 
              AND temporarily activated PIM roles)
            - "eligible": Eligible PIM roles that can be activated (not yet active)
            - If not specified, returns a message to ask the user which type they want
        user_principal_name: Optional user email. Defaults to current logged-in user.
            Only applicable for role_type="active"
        force_refresh: Whether to force refresh the role cache. Default is True.
            Only applicable for role_type="active"
    
    Returns:
        For role_type="active": Table of current Azure role assignments
        For role_type="eligible": List of eligible PIM roles with max activation hours
    
    Examples:
        # User says "show my active roles"
        azure_list_roles(role_type="active")
        
        # User says "what PIM roles can I activate" or "list eligible roles"
        azure_list_roles(role_type="eligible")
        
        # User says "list my roles" (ambiguous - must ask)
        # First ask user which type, then call with their answer
    """
    return azure.list_roles(role_type, user_principal_name, force_refresh)


@mcp.tool()
def azure_assign_rbac_role(
    scope: str,
    object_ids: list,
    role_names: list,
    principal_type: str
) -> str:
    """
    Assigns Azure RBAC roles to Service Principals (SPN) or Managed Identities (MSI/WSI) ONLY.
    
    [POLICY] Direct RBAC role assignments to Users or Groups are NOT RECOMMENDED.
    For user access, use Azure PIM (Privileged Identity Management) instead.
    For application access, use Managed Identities or Service Principals.
    
    Supports multiple scenarios:
    - Single role to single identity
    - Multiple roles to single identity  
    - Single role to multiple identities
    - Multiple roles to multiple identities
    
    Args:
        scope: Azure resource scope for the role assignment. Examples:
            - Subscription: /subscriptions/<subscription-id>
            - Resource Group: /subscriptions/<subscription-id>/resourceGroups/<rg-name>
            - Resource: /subscriptions/<subscription-id>/resourceGroups/<rg-name>/providers/<provider>/<type>/<name>
        object_ids: List of Object IDs (Principal IDs) to assign roles to. Can be a single ID or multiple.
            For Service Principals: Use Object ID (not Application ID)
            For Managed Identities: Use Principal ID
        role_names: List of Azure RBAC role names to assign. Examples:
            - "Owner", "Contributor", "Reader"
            - "Storage Blob Data Contributor", "Storage Blob Data Reader"
            - "Key Vault Secrets User", "Key Vault Administrator"
            - "Cognitive Services OpenAI Contributor"
            - "Azure AI Inference Deployment Operator"
            - "Search Index Data Contributor", "Search Service Contributor"
        principal_type: Type of principal receiving the role. MUST be one of:
            - "ServicePrincipal": For App Registrations / Service Principals
            - "ManagedIdentity": For System-assigned or User-assigned Managed Identities
            NOTE: "User" and "Group" are NOT RECOMMENDED - use Azure PIM for user access instead.
    
    Returns:
        Summary of role assignments with success/failure status for each.
        Returns policy violation message with PIM guidance if User or Group is specified.
    
    Examples:
        # Assign to Managed Identity
        azure_assign_rbac_role(
            scope="/subscriptions/xxx/resourceGroups/my-rg",
            object_ids=["managed-identity-principal-id"],
            role_names=["Storage Blob Data Contributor"],
            principal_type="ManagedIdentity"
        )
        
        # Assign to Service Principal
        azure_assign_rbac_role(
            scope="/subscriptions/xxx/resourceGroups/my-rg",
            object_ids=["spn-object-id"],
            role_names=["Cognitive Services Contributor"],
            principal_type="ServicePrincipal"
        )
    """
    return azure.assign_rbac_role(scope, object_ids, role_names, principal_type)


@mcp.tool()
def azure_activate_pim_roles(
    justification: str,
    activate_all: bool = False,
    scopes: list = None,
    role_names: list = None,
    duration_hours: int = 0
) -> str:
    """
    Activates eligible PIM (Privileged Identity Management) roles for the current user.
    
    IMPORTANT: Always ask the user to provide the justification. Do NOT guess or make up
    a justification. The justification is required by policy and must come from the user.
    
    PIM provides just-in-time privileged access with automatic expiration.
    Supports two modes:
    
    MODE 1 - Activate ALL eligible roles (activate_all=True):
        Fetches all eligible PIM roles across ALL scopes and activates them.
        Use this when user says "activate all PIMs" or "activate all my PIM roles".
    
    MODE 2 - Activate specific roles (activate_all=False):
        Activates roles at specified scopes, optionally filtered by role names.
        Use this when user provides specific scope and/or role names.
    
    Args:
        justification: Business justification for the activation (required by policy).
            MUST be provided by the user - do not guess this value.
            Ask the user: "What is your business justification for this PIM activation?"
        activate_all: If True, activates ALL eligible roles across ALL scopes.
            If False (default), requires scopes parameter.
        scopes: List of Azure scopes to activate roles on (required when activate_all=False).
            Examples:
            - ["/subscriptions/<sub-id>"] - Subscription level
            - ["/subscriptions/<sub-id>/resourceGroups/<rg-name>"] - RG level
        role_names: Optional. List of specific role names to activate.
            If not provided, activates all eligible roles.
            Examples: ["Contributor"], ["Contributor", "Storage Blob Data Owner"]
        duration_hours: Optional. Duration in hours for all roles.
            If 0 or not specified (default), uses max allowed duration per role from policy.
            Each role may have different max duration - this uses each role's maximum.
    
    Returns:
        Summary of activation results for each role:
        - Success: Role activated with actual duration
        - Skipped: Role already active
        - PendingApproval: Role requires approval (check PIM portal)
        - Failed: Activation failed with error message
    
    Examples:
        # CASE 1: Activate ALL eligible PIM roles with max duration per role
        # First ask user: "What is your business justification?"
        azure_activate_pim_roles(
            justification="<user provided justification>",
            activate_all=True
        )
        
        # CASE 2: Activate specific roles at specific scopes
        azure_activate_pim_roles(
            justification="<user provided justification>",
            scopes=["/subscriptions/3ae194eb-3ad9-4d16-b344-0d36018a362a"],
            role_names=["Contributor"]
        )
    """
    return azure.activate_pim_roles(justification, activate_all, scopes, role_names, duration_hours)


@mcp.tool()
def azure_get_resource_info(
    query_type: str,
    resource_name: str = None,
    resource_group: str = None,
    resource_type: str = None,
    location: str = None,
    custom_query: str = None
) -> str:
    """
    Unified tool for querying Azure resources, resource groups, and their properties.
    
    Args:
        query_type: Type of query to perform. Options:
            - "list_rgs": List all resource groups in subscription
            - "list_resources": List resources (optionally filtered by resource_group or resource_type)
            - "get_resource": Get detailed info for a specific resource - name, type, location, tags, ID (requires resource_name)
            - "find_resource": Find which RG contains a resource (requires resource_name)
            - "check_type_in_rg": Check if resource type exists in RG (requires resource_group, resource_type)
            - "get_rg_info": Get resource group info (requires resource_group)
            - "custom": Run a custom Azure Resource Graph query (requires custom_query)
        resource_name: Resource name (for get_resource, find_resource) - supports partial match
        resource_group: Resource group name (for filtering or specific queries)
        resource_type: Resource type filter (storage-account, key-vault, openai, etc.)
        location: Location filter
        custom_query: Azure Resource Graph query string (for query_type="custom")
    
    Returns:
        JSON with query results
    """
    return azure.query_resources(query_type, resource_name, resource_group, resource_type, location, custom_query)


@mcp.tool()
def azure_list_subscriptions() -> str:
    """
    Lists all Azure subscriptions the current user has access to.
    Returns subscription name, ID, state, and whether it's the default.
    
    Returns:
        JSON with list of accessible subscriptions
    """
    return general.list_subscriptions()


@mcp.tool()
def azure_set_subscription(subscription_id: str = None, subscription_name: str = None) -> str:
    """
    Sets the active Azure subscription for subsequent commands.
    
    Args:
        subscription_id: Subscription ID (GUID) to switch to
        subscription_name: Subscription name to switch to (alternative to ID)
    
    Returns:
        Confirmation message with the new active subscription
    """
    return general.set_subscription(subscription_id, subscription_name)


@mcp.tool()
def azure_update_tags(
    resource_id: str = None,
    resource_name: str = None,
    resource_group: str = None,
    resource_type: str = None,
    tags: str = None,
    operation: str = "merge"
) -> str:
    """
    Adds, updates, or replaces tags on an Azure resource.
    
    IMPORTANT: Before calling this tool, ask the user for:
    1. The resource to tag (resource_id OR resource_name + resource_group)
    2. The tag key-value pairs in format: "key1=value1,key2=value2"
    3. Whether to merge with existing tags or replace all tags
    
    Args:
        resource_id: Full resource ID (preferred if available)
        resource_name: Resource name (requires resource_group)
        resource_group: Resource group name
        resource_type: Resource type short name (nsg, vnet, kv, storage-account, etc.)
        tags: Tag in format "key1=value1,key2=value2"
        operation: "merge" (add/update, keep existing) or "replace" (remove all existing, set new)
    
    Returns:
        Tag update status
    """
    return azure.update_tags(resource_id, resource_name, resource_group, resource_type, tags, operation)


@mcp.tool()
def azure_get_activity_log(
    resource_group: str = None,
    resource_id: str = None,
    resource_name: str = None,
    days: int = None,
    max_events: int = 50,
    operation_type: str = None
) -> str:
    """
    Retrieves Azure Activity Log events for auditing and troubleshooting.
    
    IMPORTANT: Before calling this tool, ask the user:
    1. How many days of logs to retrieve (default: 7 days, max: 90 days)
    2. Optional: Specific resource group, resource name, or resource ID to filter
    3. Optional: Maximum number of events to return
    
    Args:
        resource_group: Filter logs by resource group name
        resource_id: Filter logs by specific resource ID
        resource_name: Filter logs by resource name (will look up resource ID automatically)
        days: Number of days to look back (1-90). Default: 7. Ask user if not specified.
        max_events: Maximum number of events to return (default: 50, max: 500)
        operation_type: Filter by operation type (e.g., "Write", "Delete", "Action")
    
    Returns:
        JSON with activity log events including timestamp, operation, status, and caller
    """
    return azure.get_activity_log(resource_group, resource_id, resource_name, days, max_events, operation_type)


@mcp.tool()
def azure_create_resource_group(resource_group_name: str, region: str, project_name: str) -> str:
    """Creates an Azure resource group with project tagging."""
    return azure.create_resource_group(resource_group_name, region, project_name)


# ============================================================================
# AZURE TOOLS - Compliance (NSP & Diagnostics)
# ============================================================================

@mcp.tool()
def azure_check_resource(resource_group: str, resource_type: str) -> str:
    """
    Checks for specific resource types in a resource group.
    Returns a list of resources found, or indicates if none exist.
    
    Args:
        resource_group: Resource group name to check
        resource_type: Type of resource to check (nsp, network-security-perimeter, log-analytics, storage-account, key-vault, openai, ai-search, cosmos-db, sql-db, fabric-capacity, uami)
    
    Returns:
        JSON string with resource information
    """
    return azure.check_resource(resource_group, resource_type)


@mcp.tool()
def azure_attach_to_nsp(resource_group: str, nsp_name: str = None, resource_id: str = None) -> str:
    """
    Attaches a resource to a Network Security Perimeter (NSP) with automatic NSP management.
    Ensures secure network isolation for PaaS resources.
    
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
    return azure.attach_to_nsp(resource_group, nsp_name, resource_id)


@mcp.tool()
def azure_attach_diagnostic_settings(resource_group: str, workspace_id: str = None, resource_id: str = None) -> str:
    """
    Attaches diagnostic settings to a resource with automatic Log Analytics Workspace management.
    Ensures resource monitoring and compliance.
    
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
    return azure.attach_diagnostic_settings(resource_group, workspace_id, resource_id)


# ============================================================================
# AZURE TOOLS - Resource Management
# ============================================================================

@mcp.tool()
def azure_get_bicep_requirements(resource_type: str) -> str:
    """(Bicep Path) Returns required/optional params for a Bicep template."""
    return azure.get_bicep_requirements(resource_type)


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
    return azure.create_resource(resource_type, resource_group, parameters)


@mcp.tool()
def azure_deploy_bicep_resource(resource_group: str, resource_type: str, parameters: dict[str, str]) -> str:
    """
    Internal deployment function - validates and deploys a resource.
    
    Warning: Users should call create_azure_resource() instead for interactive parameter collection.
    
    This function:
    1. Validates all parameters against Bicep template
    2. Deploys the resource
    """
    return azure.deploy_bicep_resource(resource_group, resource_type, parameters)


# ============================================================================
# FABRIC TOOLS
# ============================================================================

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
    return fabric.list_permissions(user_principal_name)


@mcp.tool()
def fabric_create_managed_private_endpoint(
    workspace_id: str,
    endpoint_name: str,
    target_resource_id: str,
    group_id: str
) -> str:
    """
    Creates a Managed Private Endpoint in Microsoft Fabric for secure outbound connectivity to Azure resources.
    
    This allows Fabric notebooks and Spark jobs to securely connect to Azure resources (Storage, Key Vault, SQL, etc.)
    via private networking. After creation, the endpoint requires APPROVAL on the target Azure resource.
    
    Args:
        workspace_id: Fabric workspace ID (GUID). Get from workspace URL or fabric_list_workspaces.
        endpoint_name: Name for the managed private endpoint (e.g., "adls-mydata", "kv-secrets")
        target_resource_id: Full Azure resource ID to connect to
        group_id: Sub-resource type (e.g., "blob", "dfs", "vault", "sqlServer")
    
    Returns:
        Creation status with endpoint details and approval instructions
    """
    return fabric.create_managed_private_endpoint(workspace_id, endpoint_name, target_resource_id, group_id)


@mcp.tool()
def fabric_list_managed_private_endpoints(workspace_id: str) -> str:
    """
    Lists all Managed Private Endpoints in a Fabric workspace.
    
    Args:
        workspace_id: Fabric workspace ID (GUID)
    
    Returns:
        List of managed private endpoints with their name, target resource, and approval status
    """
    return fabric.list_managed_private_endpoints(workspace_id)


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
    return fabric.create_workspace(capacity_id, workspace_name, description)


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
    return fabric.attach_workspace_to_git(workspace_id, organization, project_name, repo_name, branch_name, directory_name)


@mcp.tool()
def fabric_assign_role(
    workspace_identifier: str,
    role_name: str,
    principal_id: str,
    principal_type: str
) -> str:
    """
    Assigns a role to a user, group, service principal, or managed identity in a Microsoft Fabric workspace.
    
    Use this tool when a user wants to grant access to a Fabric workspace.
    
    Args:
        workspace_identifier: Workspace name or workspace ID (GUID). Can use either.
        role_name: Role to assign. Must be one of: Admin, Contributor, Member, Viewer
            - Admin: Full control including managing permissions and deleting workspace
            - Contributor: Can create, edit, delete items but cannot manage permissions
            - Member: Can view and interact with items
            - Viewer: Read-only access to workspace items
        principal_id: Object ID (Principal ID) of the identity to grant access to.
            For Users: User's Object ID from Entra ID
            For Groups: Group's Object ID from Entra ID  
            For Service Principals: Application's Object ID (not Application ID)
            For Managed Identities: Principal ID of the managed identity
        principal_type: Type of principal. Must be one of:
            - User: For individual user accounts
            - Group: For Entra ID security groups or Microsoft 365 groups
            - ServicePrincipal: For app registrations / service principals
            - ServicePrincipalProfile: For managed identities
    
    Returns:
        Role assignment status with details
    """
    return fabric.assign_role(workspace_identifier, role_name, principal_id, principal_type)


# ============================================================================
# AZURE DEVOPS TOOLS - Projects & Repos
# ============================================================================

@mcp.tool()
def ado_create_project(organization: str = None, project_name: str = None, repo_name: str = None, description: str = None) -> str:
    """
    Creates an Azure DevOps project using AZ CLI via the PS1 script and sets the initial repo name.

    Behavior: Relies on the PS1 script output entirely (no extra verification).
    Required: organization (URL or org name), project_name, repo_name; description optional.
    """
    return ado.create_project(organization, project_name, repo_name, description)


@mcp.tool()
def ado_create_repo(organization: str = None, project_name: str = None, repo_name: str = None) -> str:
    """
    Creates a new Azure DevOps Git repository via the PS1 script.

    Behavior: Relies on the PS1 script output entirely (no extra verification).
    Required: organization (URL or org name), project_name, repo_name.
    """
    return ado.create_repo(organization, project_name, repo_name)


@mcp.tool()
def ado_list_projects(organization: str = None) -> str:
    """
    Lists all Azure DevOps projects in an organization.

    Behavior: Returns list of all projects with their details.
    Required: organization (URL or org name).
    """
    return ado.list_projects(organization)


@mcp.tool()
def ado_list_repos(organization: str = None, project_name: str = None) -> str:
    """
    Lists all Azure DevOps repositories in a project.

    Behavior: Returns list of all repos with their details.
    Required: organization (URL or org name), project_name.
    """
    return ado.list_repos(organization, project_name)


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
    return ado.create_branch(organization, project_name, repo_name, branch_name, base_branch)


# ============================================================================
# AZURE DEVOPS TOOLS - Pipelines
# ============================================================================

@mcp.tool()
def ado_deploy_custom_yaml(organization: str, project_name: str, repo_name: str,
                           branch: str, file_name: str, yaml_content: str,
                           folder_path: str = "pipelines") -> str:
    """
    Deploys custom YAML content directly to an Azure DevOps repository.
    Use this when you have YAML content to deploy (not using templates).
    
    Args:
        organization: Azure DevOps organization URL (required)
        project_name: Existing project name (required)
        repo_name: Existing repository name (required)
        branch: Branch to deploy to (required, e.g., 'main', 'dev')
        file_name: Target filename/display name for the YAML file (required, e.g., 'sourcebranchvalidation.yml')
        yaml_content: The actual YAML content to deploy (required - paste full YAML here)
        folder_path: Folder in repo for YAML (defaults to 'pipelines')
    
    Returns:
        Deployment status and YAML location
    """
    return ado.deploy_custom_yaml(organization, project_name, repo_name, branch, file_name, yaml_content, folder_path)


@mcp.tool()
def ado_deploy_pipeline_yaml(organization: str = None, project_name: str = None, 
                        repo_name: str = None, pipeline_type: str = None,
                        branch: str = None, folder_path: str = None,
                        custom_yaml_content: str = None, yaml_file_name: str = None) -> str:
    """
    Deploys a pipeline YAML template from agent/templates OR custom YAML content to an Azure DevOps repository.
    
    Workflow:
    1. If custom_yaml_content provided → deploys custom YAML
    2. If pipeline_type matches PIPELINE_TEMPLATE_MAP entry → uses that template
    3. Otherwise → prompts for custom YAML content
    4. Clones repo, copies YAML to specified folder, commits and pushes
    
    Template Management (Similar to Bicep TEMPLATE_MAP):
    - Templates are mapped in PIPELINE_TEMPLATE_MAP (see server.py)
    - To add new templates:
      1. Add .yml file to agent/templates/
      2. Add entry to PIPELINE_TEMPLATE_MAP: "template-key": "templates/YourTemplate.yml"
    
    Available Templates:
    - credscan: credscan_Pipeline.yml (standard non-production)
    - credscan-1es: credscan_1ES_Pipeline.yml (production/1ES)
    
    Args:
        organization: Azure DevOps organization URL
        project_name: Existing project name
        repo_name: Existing repository name
        pipeline_type: Template key from PIPELINE_TEMPLATE_MAP OR identifier for custom YAML
        branch: Branch to deploy to (defaults to 'main')
        folder_path: Folder in repo to deploy YAML (defaults to 'pipelines')
        custom_yaml_content: Custom YAML content to deploy (optional - overrides template)
        yaml_file_name: Custom filename for YAML (optional - defaults to pipeline_type.yml)
    
    Returns:
        Deployment status and YAML location
    """
    return ado.deploy_pipeline_yaml(organization, project_name, repo_name, pipeline_type, branch, folder_path, custom_yaml_content, yaml_file_name)


@mcp.tool()
def ado_create_pipeline(organization: str = None, project_name: str = None,
                          repo_name: str = None, pipeline_name: str = None,
                          branch: str = None, pipeline_type: str = None,
                          yaml_path: str = None) -> str:
    """
    Creates an Azure DevOps pipeline from YAML file in repository.
    
    Template Management (Similar to Bicep TEMPLATE_MAP):
    - Pipeline templates are defined in PIPELINE_TEMPLATE_MAP
    - Keywords: '1ES', 'prod', 'production' → selects 1ES template
    - Auto-constructs yaml_path as: pipelines/{template_file}.yml
    - OR use yaml_path parameter to specify a custom YAML file path
    
    Workflow:
    1. Auto-detects pipeline type from pipeline_name keywords (if yaml_path not provided)
    2. Constructs yaml_path from PIPELINE_TEMPLATE_MAP (if yaml_path not provided)
    3. Checks if YAML exists in repository
    4. Creates pipeline referencing the YAML
    
    Note: YAML file must already exist in repository (use ado_deploy_pipeline_yaml first)
    
    Args:
        organization: Azure DevOps organization URL
        project_name: Existing project name
        repo_name: Existing repository name
        pipeline_name: Name for pipeline (keywords '1ES'/'prod' select production template)
        branch: Branch containing YAML (defaults to 'main')
        pipeline_type: Optional explicit template type from PIPELINE_TEMPLATE_MAP (e.g., 'credscan', 'credscan-1es')
        yaml_path: Optional custom YAML file path in repository (e.g., 'pipelines/sourcebranchvalidation.yml')
    
    Returns:
        Pipeline creation status and URL
    """
    return ado.create_pipeline(organization, project_name, repo_name, pipeline_name, branch, pipeline_type, yaml_path)


@mcp.tool()
def ado_assign_role(
    organization: str = None,
    project_name: str = None,
    role_name: str = None,
    principal_id: str = None
) -> str:
    """
    Assigns a role (security group membership) to a principal in an Azure DevOps project.
    
    Common built-in roles:
    - Project Administrators: Full control over project settings and security
    - Build Administrators: Manage build pipelines and definitions
    - Release Administrators: Manage release pipelines and deployments
    - Contributors: Create and modify code, work items, and pipelines
    - Readers: View-only access to project resources
    - Endpoint Administrators: Manage service connections
    - Endpoint Creators: Create service connections
    
    Custom roles/groups are also supported - provide the exact group name.
    
    If the role does not exist, the tool will return an error listing available groups.
    
    Args:
        organization: Azure DevOps organization URL or name
        project_name: Name of the Azure DevOps project
        role_name: Name of the security group/role to assign
        principal_id: Object ID (GUID) of the user, group, or service principal from Azure AD/Entra ID
    
    Returns:
        Role assignment result with status and details
    """
    return ado.assign_role(organization, project_name, role_name, principal_id)


# ============================================================================
# ENTRY POINT
# ============================================================================

def main():
    """Entry point for the MCP server."""
    mcp.run()


if __name__ == "__main__":
    main()
