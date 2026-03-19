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
    justification: str = None,
    activate_all: bool = False,
    subscription_name: str = None,
    resource_group_name: str = None,
    resource_name: str = None,
    role_name: str = None,
    duration_hours: int = 0
) -> str:
    """
    Activates eligible PIM (Privileged Identity Management) roles for the current user.
    
    CRITICAL: Justification is MANDATORY. You MUST ask the user for their business 
    justification BEFORE calling this tool. Do NOT guess or make up a justification.
    Ask: "What is your business justification for this PIM activation?"
    
    Supports TWO distinct modes:
    
    ═══════════════════════════════════════════════════════════════════════════════
    MODE 1 - ACTIVATE ALL (activate_all=True)
    ═══════════════════════════════════════════════════════════════════════════════
    Use when user says: "activate all my PIM roles", "activate all PIMs", 
    "activate everything", "activate all eligible roles"
    
    This mode activates ALL eligible PIM roles across ALL scopes.
    Do NOT pass role_name, subscription_name, or resource_group_name in this mode.
    
    Example:
        azure_activate_pim_roles(justification="<user provided>", activate_all=True)
    
    ═══════════════════════════════════════════════════════════════════════════════
    MODE 2 - ACTIVATE SPECIFIC ROLE (activate_all=False)
    ═══════════════════════════════════════════════════════════════════════════════
    Use when user specifies a particular role AND scope, such as:
    - "activate Contributor at MCAPSDE_DEV"
    - "activate Azure AI User on mcapsde_dev subscription"
    - "activate Data Factory Contributor at dfdataplatformprod"
    - "activate Contributor on csu_dataplatform_dev resource group"
    
    REQUIRED in this mode:
    - role_name: The exact role name (e.g., "Contributor", "Azure AI User")
    - subscription_name: The subscription name (e.g., "MCAPSDE_DEV")
    
    OPTIONAL:
    - resource_group_name: For RG-level scope (e.g., "csu_dataplatform_dev")
    - resource_name: For resource-level scope (e.g., "dfdataplatformprod")
    
    Example:
        azure_activate_pim_roles(
            justification="<user provided>",
            role_name="Contributor",
            subscription_name="MCAPSDE_DEV"
        )
    
    ═══════════════════════════════════════════════════════════════════════════════
    
    Args:
        justification: Business justification (REQUIRED - must come from user)
        activate_all: Set True ONLY for "activate all" mode
        subscription_name: Subscription name for specific role mode (e.g., "MCAPSDE_DEV")
        resource_group_name: Resource group name for RG-level scope (optional)
        resource_name: Resource name for resource-level scope (optional)
        role_name: Specific role to activate (e.g., "Contributor", "Reader")
        duration_hours: Duration in hours (0 = max allowed per role policy)
    
    Returns:
        Activation results with success/failure status per role
    """
    return azure.activate_pim_roles(
        justification=justification,
        activate_all=activate_all,
        subscription_name=subscription_name,
        resource_group_name=resource_group_name,
        resource_name=resource_name,
        role_name=role_name,
        duration_hours=duration_hours
    )


@mcp.tool()
def azure_assign_pim_role(
    scope: str = None,
    principal_id: str = None,
    role_name: str = None,
    duration: str = "P1Y"
) -> str:
    """
    Assigns a PIM eligible role to a user, group, or service principal.
    
    Creates an ELIGIBLE (not active) role assignment. The principal can then
    activate the role via PIM when needed.
    
    NOTE: PIM eligible roles can ONLY be assigned at Subscription or Resource Group level.
    Resource-level PIM assignments are NOT supported.
    
    REQUIRED PARAMETERS - Ask user for all three:
    1. scope: Where to assign the role (subscription or RG only)
    2. principal_id: Object ID of the principal (user/group/SP)
    3. role_name: Which role to assign
    
    Args:
        scope: Target scope for the assignment (required)
               - Subscription: /subscriptions/{subscription-id}
               - Resource Group: /subscriptions/{sub-id}/resourceGroups/{rg-name}
               (Resource-level scope is NOT supported for PIM)
        principal_id: Object ID of the user, group, or service principal (required)
                      Find in: Azure Portal > Entra ID > Users > select user > Object ID
        role_name: Name of the role to assign (required)
                   Common roles: Contributor, Reader, Owner, Storage Blob Data Contributor,
                   Key Vault Administrator, Key Vault Secrets User
        duration: ISO 8601 duration (default: P1Y = 1 year)
                  Examples: P1Y (1 year), P6M (6 months), P30D (30 days), P7D (1 week)
    
    Returns:
        Assignment result
    
    Example:
        azure_assign_pim_role(
            scope="/subscriptions/.../resourceGroups/my-rg",
            principal_id="f9dc27bf-e63a-4f03-bb2a-eb9e0227879c",
            role_name="Contributor"
        )
    """
    return azure.assign_pim_eligible_role(
        scope=scope,
        principal_id=principal_id,
        role_name=role_name,
        duration=duration
    )


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
            - "get_identity": Get principalId (object ID) and clientId for any resource with managed identity.
                              For UAMIs: set resource_type="uami". Returns principalId, clientId, tenantId.
                              For other resources: returns system-assigned and/or user-assigned identity details.
            - "custom": Run a custom Azure Resource Graph KQL query (requires custom_query). 
                        Example: "Resources | where type == 'Microsoft.Compute/virtualMachines'"
            - "cli_raw": Run a raw Azure CLI command (requires custom_query).
                         Example: "az identity show --name my-uami -g my-rg"
        resource_name: Resource name (for get_resource, find_resource, get_identity)
        resource_group: Resource group name (for filtering or specific queries)
        resource_type: Resource type filter (storage-account, key-vault, openai, uami, etc.)
        location: Location filter
        custom_query: Azure Resource Graph KQL query (for query_type="custom") or CLI command (for query_type="cli_raw")
    
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


@mcp.tool()
def azure_attach_appinsights(
    app_insights_name: str,
    app_insights_resource_group: str,
    target_app_name: str,
    target_resource_group: str,
    target_type: str
) -> str:
    """
    Attaches Application Insights to a Function App or App Service.
    
    This configures the app to send telemetry, logs, and metrics to Application Insights.
    
    Args:
        app_insights_name: Name of the Application Insights instance
        app_insights_resource_group: Resource group containing Application Insights
        target_app_name: Name of the Function App or App Service to attach
        target_resource_group: Resource group containing the target app
        target_type: Type of target app - 'functionapp' or 'webapp'
    
    Returns:
        Attachment result with configured settings
    """
    return azure.attach_appinsights(
        app_insights_name, app_insights_resource_group,
        target_app_name, target_resource_group, target_type
    )


# ============================================================================
# AZURE TOOLS - Resource Management
# ============================================================================

@mcp.tool()
def azure_get_bicep_requirements(resource_type: str) -> str:
    """(Bicep Path) Returns required/optional params for a Bicep template.
    
    IMPORTANT: For resources with hosting variants, always use the BASE type first:
    - For function apps: use 'function-app' (NOT 'function-app-flex' or 'function-app-appserviceplan')
    This returns the available hosting options for the user to choose from.
    Only use the specific variant AFTER the user has explicitly chosen one.
    """
    return azure.get_bicep_requirements(resource_type)


@mcp.tool()
def azure_create_resource(resource_type: str, resource_group: str = None, parameters: str = None) -> str:
    """Interactive Azure resource creation using Bicep templates.
    
    IMPORTANT: For resources with hosting variants, always use the BASE type first:
    - For function apps: use 'function-app' (NOT 'function-app-flex' or 'function-app-appserviceplan')
    This returns the available hosting options for the user to choose from.
    Only use the specific variant AFTER the user has explicitly chosen one.
    
    Args:
        resource_type: Type of resource to create (e.g. storage-account, key-vault, function-app, etc.)
        resource_group: Azure resource group name
        parameters: JSON string of resource-specific parameters
    
    Returns:
        Deployment status with resource details
    """
    return azure.create_resource(resource_type, resource_group, parameters)


@mcp.tool()
def azure_create_private_endpoint(
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
    
    This tool intelligently handles DNS zone management:
    - If DNS zone doesn't exist: Creates PE + DNS zone + VNet link
    - If DNS zone exists but VNet link doesn't: Creates PE + adds new VNet link to existing zone
    - If both exist: Creates PE and links to existing DNS zone
    
    DNS zones are automatically determined based on the group_id (sub-resource type):
    - Storage: blob, file, table, queue, dfs, web → privatelink.{service}.core.windows.net
    - Key Vault: vault → privatelink.vaultcore.azure.net
    - SQL: sqlServer → privatelink.database.windows.net
    - Cosmos DB: Sql, MongoDB, Cassandra → privatelink.{type}.cosmos.azure.com
    - OpenAI/Cognitive: account → privatelink.cognitiveservices.azure.com
    - Container Registry: registry → privatelink.azurecr.io
    - And more...
    
    Args:
        resource_group: Resource group name for the private endpoint
        private_endpoint_name: Name for the private endpoint (e.g., "pe-storage-blob")
        target_resource_id: Full resource ID of the target Azure resource
        group_id: Sub-resource type for the connection (e.g., 'blob', 'vault', 'sqlServer', 'account')
        subnet_id: Full resource ID of the subnet to deploy the PE into
        location: Azure region (should match VNet location)
        vnet_id: Optional - VNet resource ID (auto-extracted from subnet_id if not provided)
        vnet_link_name: Optional - Custom name for DNS zone VNet link
    
    Returns:
        Deployment status with details about PE and DNS configuration
    """
    return azure.create_private_endpoint(
        resource_group=resource_group,
        private_endpoint_name=private_endpoint_name,
        target_resource_id=target_resource_id,
        group_id=group_id,
        subnet_id=subnet_id,
        location=location,
        vnet_id=vnet_id,
        vnet_link_name=vnet_link_name
    )


@mcp.tool()
def azure_manage_pe_connection(
    action: str = None,
    resource_id: str = None,
    connection_id: str = None,
    connection_name: str = None,
    description: str = None
) -> str:
    """
    Manages private endpoint connections on Azure resources - list, approve, or reject.
    
    This unified tool handles all PE connection operations:
    - 'list': Show all PE connections (pending/approved/rejected) on a resource
    - 'approve': Approve a pending PE connection
    - 'reject': Reject a PE connection request
    
    Workflow:
    1. Call with action='list' and resource_id to see all connections
    2. Copy the connection_id of the target connection
    3. Call with action='approve' or 'reject' and the connection_id
    
    Args:
        action: Action to perform - 'list', 'approve', or 'reject' (required)
        resource_id: Full resource ID of the target resource (required for 'list')
        connection_id: Full PE connection ID (for approve/reject - preferred)
        connection_name: PE connection name (alternative to connection_id, use with resource_id)
        description: Approval/rejection reason (optional)
    
    Returns:
        List of connections or action result
    
    Examples:
        # List connections on a storage account
        azure_manage_pe_connection(action='list', resource_id='/subscriptions/.../storageAccounts/mysa')
        
        # Approve a pending connection
        azure_manage_pe_connection(action='approve', connection_id='<id from list>')
        
        # Reject with custom reason
        azure_manage_pe_connection(action='reject', connection_id='<id>', description='Not authorized')
    """
    return azure.manage_private_endpoint_connection(
        action=action,
        resource_id=resource_id,
        connection_id=connection_id,
        connection_name=connection_name,
        description=description
    )


@mcp.tool()
def azure_integrate_vnet(
    resource_name: str = None,
    resource_group: str = None,
    resource_type: str = None,
    subnet_id: str = None
) -> str:
    """
    Integrates an Azure resource with a Virtual Network (VNet) via Regional VNet Integration or Network ACL rules.
    
    REGIONAL VNET INTEGRATION (for outbound connectivity from resource to VNet):
    - functionapp: Azure Function App - MUST be in SAME REGION as VNet
    - webapp: Azure App Service - MUST be in SAME REGION as VNet
    
    NETWORK ACL RULES (firewall rules to allow VNet subnet access):
    - keyvault: Azure Key Vault
    - storageaccount: Azure Storage Account
    - cosmosdb: Azure Cosmos DB
    - openai: Azure OpenAI Service
    - cognitiveservices: Azure Cognitive Services
    - sqlserver: Azure SQL Server
    - eventhub: Azure Event Hub Namespace
    - servicebus: Azure Service Bus Namespace
    - containerregistry: Azure Container Registry (requires Premium SKU)
    
    NOT SUPPORTED (use Private Endpoints instead via azure_create_private_endpoint):
    - Azure AI Search: Does NOT support VNet integration
    - Azure Data Factory: Use Managed VNet or Private Endpoints
    
    NOTE: This is NOT Private Endpoint. For inbound private access to resources,
    use azure_create_private_endpoint instead.
    
    Prerequisites:
    - Function App/App Service: Must be in SAME REGION as VNet, Basic tier or higher
    - Subnet should have appropriate service endpoint enabled (e.g., Microsoft.KeyVault, Microsoft.Storage)
    - Container Registry: Must be Premium SKU for network rules
    
    Args:
        resource_name: Name of the Azure resource
        resource_group: Resource group containing the resource
        resource_type: Type of resource to integrate (see supported types above)
        subnet_id: Full resource ID of the subnet. Format:
            /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}
    
    Returns:
        Integration status with configuration details
    
    Examples:
        # Integrate Function App with VNet (same region required)
        azure_integrate_vnet(
            resource_name='my-function-app',
            resource_group='my-rg',
            resource_type='functionapp',
            subnet_id='/subscriptions/xxx/resourceGroups/network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/integration-subnet'
        )
        
        # Add Storage Account network rule
        azure_integrate_vnet(
            resource_name='mystorageaccount',
            resource_group='my-rg',
            resource_type='storageaccount',
            subnet_id='/subscriptions/xxx/resourceGroups/network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/app-subnet'
        )
        
        # Add Azure OpenAI network rule
        azure_integrate_vnet(
            resource_name='my-openai',
            resource_group='my-rg',
            resource_type='openai',
            subnet_id='/subscriptions/xxx/resourceGroups/network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/app-subnet'
        )
    """
    return azure.integrate_vnet(
        resource_name=resource_name,
        resource_group=resource_group,
        resource_type=resource_type,
        subnet_id=subnet_id
    )


# ============================================================================
# CONTAINER APPS TOOLS
# ============================================================================

@mcp.tool()
def azure_create_container_apps_env(
    resource_group: str = None,
    environment_name: str = None,
    subnet_id: str = None,
    zone_redundant: bool = False,
    workload_profile_type: str = "Consumption",
    internal_only: bool = False
) -> str:
    """
    Creates a Container Apps Environment with optional VNet integration.
    
    PREREQUISITES:
    - Resource Group must exist (environment uses SAME REGION as RG automatically)
    - For VNet mode: VNet and subnet must exist
    
    REQUIRED INFORMATION (ask user):
    1. resource_group: Target resource group
    2. environment_name: Name for the environment
    
    Args:
        resource_group: Resource group name (environment deployed in same region)
        environment_name: Name for the Container Apps Environment
        subnet_id: Optional - Full subnet resource ID for VNet integration.
            If omitted, uses Azure-managed networking. Format:
            /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}
        zone_redundant: Enable zone redundancy (default: False)
        workload_profile_type: Consumption, D4, D8, D16, D32, E4, E8, E16, E32 (default: Consumption)
        internal_only: No public ingress - internal VNet access only (default: False)
    
    Returns:
        Deployment result with environment details
    
    Examples:
        # Basic environment without VNet (Azure-managed networking)
        azure_create_container_apps_env(
            resource_group='my-rg',
            environment_name='my-aca-env'
        )
        
        # Environment with VNet integration
        azure_create_container_apps_env(
            resource_group='my-rg',
            environment_name='my-aca-env',
            subnet_id='/subscriptions/xxx/resourceGroups/network-rg/providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/aca-subnet'
        )
        
        # Zone-redundant with dedicated workload profile
        azure_create_container_apps_env(
            resource_group='my-rg',
            environment_name='my-aca-env',
            subnet_id='/subscriptions/xxx/.../subnets/aca-subnet',
            zone_redundant=True,
            workload_profile_type='D4'
        )
    """
    return azure.create_container_apps_environment(
        resource_group=resource_group,
        environment_name=environment_name,
        subnet_id=subnet_id,
        log_analytics_workspace_id=None,
        zone_redundant=zone_redundant,
        workload_profile_type=workload_profile_type,
        internal_only=internal_only
    )


@mcp.tool()
def azure_create_container_app(
    resource_group: str = None,
    container_app_name: str = None,
    environment_name: str = None,
    target_port: int = 80,
    external_ingress: bool = True,
    cpu: str = "0.5",
    memory: str = "1Gi",
    min_replicas: int = 0,
    max_replicas: int = 10,
    subnet_id: str = None
) -> str:
    """
    Creates a Container App using the default quickstart image. Auto-creates environment if none exists.
    
    ENVIRONMENT AUTO-DETECTION & AUTO-CREATION:
    - If environment_name not provided, tool finds existing environment in the RG
    - If no environment exists, one is automatically created
    - Use subnet_id to specify VNet integration when auto-creating environment
    
    Args:
        resource_group: Resource group containing the Container Apps Environment
        container_app_name: Name for the Container App (2-32 chars)
        environment_name: Existing environment name (auto-detected/created if not provided)
        target_port: Port the container listens on (default: 80)
        external_ingress: Enable public access (default: True)
        cpu: CPU cores - 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 4 (default: 0.5)
        memory: Memory - 0.5Gi, 1Gi, 1.5Gi, 2Gi, 3Gi, 3.5Gi, 4Gi, 8Gi (default: 1Gi)
        min_replicas: Minimum replicas, 0 for scale-to-zero (default: 0)
        max_replicas: Maximum replicas (default: 10)
        subnet_id: Optional - subnet for VNet integration when auto-creating environment
    
    Returns:
        Deployment result with Container App details and FQDN
    
    Examples:
        # Basic container app with default image
        azure_create_container_app(
            resource_group='my-rg',
            container_app_name='hello-app'
        )
        
        # Auto-create environment with VNet when none exists
        azure_create_container_app(
            resource_group='my-rg',
            container_app_name='hello-app',
            subnet_id='/subscriptions/xxx/.../subnets/aca-subnet'
        )
        
        # With custom configuration
        azure_create_container_app(
            resource_group='my-rg',
            container_app_name='my-worker',
            target_port=8080,
            cpu='1',
            memory='2Gi',
            min_replicas=1,
            max_replicas=5
        )
    """
    return azure.create_container_app(
        resource_group=resource_group,
        container_app_name=container_app_name,
        environment_name=environment_name,
        target_port=target_port,
        external_ingress=external_ingress,
        cpu=cpu,
        memory=memory,
        min_replicas=min_replicas,
        max_replicas=max_replicas,
        subnet_id=subnet_id
    )


# ============================================================================
# DATA COLLECTION ENDPOINT & DATA COLLECTION RULE TOOLS
# ============================================================================

@mcp.tool()
def azure_create_data_collection_endpoint(
    resource_group: str = None,
    dce_name: str = None,
    public_network_access: str = "Enabled",
    description: str = ""
) -> str:
    """
    Creates a Data Collection Endpoint (DCE) for Azure Monitor.
    
    DCE is REQUIRED for:
    - Logs Ingestion API (custom logs)
    - Azure Monitor Private Link Scope (AMPLS)
    - VNet-isolated data ingestion
    
    CREATE ORDER: DCE must be created BEFORE DCR.
    
    Args:
        resource_group: Target resource group
        dce_name: Name for the Data Collection Endpoint
        public_network_access: Enabled (default), Disabled, or SecuredByPerimeter
        description: Optional description
    
    Returns:
        Deployment result with DCE ID, endpoints (logs, metrics, config)
    
    Example:
        azure_create_data_collection_endpoint(
            resource_group='monitoring-rg',
            dce_name='my-dce'
        )
    """
    return azure.create_data_collection_endpoint(
        resource_group=resource_group,
        dce_name=dce_name,
        public_network_access=public_network_access,
        description=description
    )


@mcp.tool()
def azure_create_data_collection_rule(
    resource_group: str = None,
    dcr_name: str = None,
    workspace_name: str = None,
    dce_name: str = None,
    custom_table_base_name: str = None,
    table_columns: list = None,
    create_table: bool = True,
    workspace_resource_group: str = None,
    dce_resource_group: str = None,
    retention_in_days: int = 90,
    total_retention_in_days: int = 180
) -> str:
    """
    Creates a Data Collection Rule (DCR) with optional custom Log Analytics table.
    
    PREREQUISITES:
    1. Log Analytics Workspace must exist
    2. Data Collection Endpoint (DCE) must exist - create with azure_create_data_collection_endpoint first
    
    CREATE ORDER: DCE → DCR → (optional) attach via azure_attach_dce_to_dcr
    
    Args:
        resource_group: Resource group for the DCR
        dcr_name: Name for the Data Collection Rule
        workspace_name: Existing Log Analytics workspace name
        dce_name: Existing Data Collection Endpoint name
        custom_table_base_name: Base name for custom table (e.g., 'MyLogs' creates 'MyLogs_CL')
        table_columns: Column definitions as list. Default: [TimeGenerated, Message]
            Format: [{"name": "ColumnName", "type": "string|dateTime|int|..."}]
        create_table: Create the custom table (default: True)
        workspace_resource_group: RG containing workspace (defaults to resource_group)
        dce_resource_group: RG containing DCE (defaults to resource_group)
        retention_in_days: Interactive retention days (default: 90)
        total_retention_in_days: Total retention including archive (default: 180)
    
    Returns:
        Deployment result with DCR ID, immutable ID, table name, stream name
    
    Example:
        azure_create_data_collection_rule(
            resource_group='monitoring-rg',
            dcr_name='my-dcr',
            workspace_name='my-law',
            dce_name='my-dce',
            custom_table_base_name='MyCustomLogs',
            table_columns=[
                {"name": "TimeGenerated", "type": "dateTime"},
                {"name": "RunID", "type": "string"},
                {"name": "Status", "type": "string"},
                {"name": "Message", "type": "string"}
            ]
        )
    """
    return azure.create_data_collection_rule(
        resource_group=resource_group,
        dcr_name=dcr_name,
        workspace_name=workspace_name,
        dce_name=dce_name,
        custom_table_base_name=custom_table_base_name,
        table_columns=table_columns,
        create_table=create_table,
        workspace_resource_group=workspace_resource_group,
        dce_resource_group=dce_resource_group,
        retention_in_days=retention_in_days,
        total_retention_in_days=total_retention_in_days
    )


@mcp.tool()
def azure_attach_dce_to_dcr(
    dcr_name: str = None,
    dcr_resource_group: str = None,
    dce_name: str = None,
    dce_resource_group: str = None,
    subscription_id: str = None
) -> str:
    """
    Attaches a Data Collection Endpoint (DCE) to an existing Data Collection Rule (DCR).
    
    Use this to:
    - Update an existing DCR to use a different DCE
    - Attach a DCE to a DCR that was created without one
    
    Args:
        dcr_name: Name of the Data Collection Rule
        dcr_resource_group: Resource group containing the DCR
        dce_name: Name of the Data Collection Endpoint to attach
        dce_resource_group: RG containing DCE (defaults to dcr_resource_group)
        subscription_id: Optional subscription ID
    
    Returns:
        Result showing the attached DCE
    
    Example:
        azure_attach_dce_to_dcr(
            dcr_name='my-dcr',
            dcr_resource_group='monitoring-rg',
            dce_name='my-dce'
        )
    """
    return azure.attach_dce_to_dcr(
        dcr_name=dcr_name,
        dcr_resource_group=dcr_resource_group,
        dce_name=dce_name,
        dce_resource_group=dce_resource_group,
        subscription_id=subscription_id
    )


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


@mcp.tool()
def fabric_create_deployment_pipeline(
    pipeline_name: str,
    pipeline_type: str,
    workspace_names: str,
    description: str = ""
) -> str:
    """
    Creates Microsoft Fabric deployment pipeline(s) and assigns workspaces.
    
    IMPORTANT: User MUST choose a pipeline_type. Three options available:
    - "Dev-to-Prod": 1 pipeline (Development -> Production), 2 workspaces
    - "UAT-to-Prod": 1 pipeline (UAT -> Production), 2 workspaces
    - "Dev-to-UAT-to-Prod": 2 pipelines (Dev->UAT + UAT->Prod), 3 workspaces
    
    Args:
        pipeline_name: Name for the pipeline (prefix for Dev-to-UAT-to-Prod)
        pipeline_type: REQUIRED - Must be one of: "Dev-to-Prod", "UAT-to-Prod", or "Dev-to-UAT-to-Prod"
        workspace_names: Comma-separated workspace names matching the type.
            Dev-to-Prod: "DevWS,ProdWS" (2 names)
            UAT-to-Prod: "UATWS,ProdWS" (2 names)
            Dev-to-UAT-to-Prod: "DevWS,UATWS,ProdWS" (3 names)
        description: Optional description for the pipeline(s)
    
    Returns:
        Pipeline creation and workspace assignment results
    """
    return fabric.create_deployment_pipeline(pipeline_name, pipeline_type, workspace_names, description)


@mcp.tool()
def fabric_add_deployment_pipeline_role(
    pipeline_id: str,
    user_email: str,
    role: str = "Admin",
    principal_type: str = "User"
) -> str:
    """
    Adds a role assignment to a deployment pipeline.
    
    Accepts user email and automatically resolves it to the Entra ID Object ID.
    
    Args:
        pipeline_id: The deployment pipeline ID (GUID)
        user_email: The user's email address (auto-resolved to Object ID)
        role: Role to assign - currently only "Admin" is supported
        principal_type: Type of principal - "User", "Group", "ServicePrincipal", or "ServicePrincipalProfile"
    
    Returns:
        JSON with role assignment result
    """
    return fabric.add_deployment_pipeline_role(pipeline_id, user_email, role, principal_type)


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
    - codeql: CodeQL_Pipeline.yml (standard non-production)
    - codeql-1es: CodeQL_1ES_Pipeline.yml (production/1ES)
    
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
        pipeline_type: Optional explicit template type from PIPELINE_TEMPLATE_MAP (e.g., 'codeql', 'codeql-1es')
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
        principal_id: Object ID (GUID) of the user, group, service principal, or managed identity from Azure AD/Entra ID
    
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
