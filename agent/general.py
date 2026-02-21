# ============================================================================
# GENERAL FUNCTIONS - User identity and instructions
# ============================================================================

import json

try:
    from .utils import run_powershell_script, get_script_path, load_agent_instructions
except ImportError:
    from utils import run_powershell_script, get_script_path, load_agent_instructions


def get_current_user() -> str:
    """Gets the current Azure subscription, tenant, and user email."""
    script_path = get_script_path("get-current-user.ps1")
    return run_powershell_script(script_path, {})


def list_subscriptions() -> str:
    """Lists all Azure subscriptions the user has access to."""
    script_path = get_script_path("list-subscriptions.ps1")
    return run_powershell_script(script_path, {})


def set_subscription(subscription_id: str = None, subscription_name: str = None) -> str:
    """Sets the active Azure subscription."""
    params = {}
    if subscription_id:
        params["SubscriptionId"] = subscription_id
    if subscription_name:
        params["SubscriptionName"] = subscription_name
    script_path = get_script_path("set-subscription.ps1")
    return run_powershell_script(script_path, params)


def azure_login(selected_subscription_id: str = None) -> str:
    """
    Login to Azure - for first-time users or switching accounts.
    Handles:
    - No subscriptions: uses --allow-no-subscriptions
    - One subscription: sets it as default automatically
    - Multiple subscriptions: returns list for user to choose
    
    Args:
        selected_subscription_id: If provided, sets this subscription after login
    """
    params = {}
    if selected_subscription_id:
        params["SelectedSubscriptionId"] = selected_subscription_id
    script_path = get_script_path("azure-login.ps1")
    return run_powershell_script(script_path, params)


def show_agent_instructions() -> str:
    """Returns the complete agent instructions and capabilities documentation."""
    return load_agent_instructions()
