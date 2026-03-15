param(
    [Parameter(Mandatory=$true)]
    [string]$Scope,
    
    [Parameter(Mandatory=$true)]
    [string]$PrincipalID,
    
    [Parameter(Mandatory=$true)]
    [string]$RoleName,
    
    [Parameter(Mandatory=$false)]
    [string]$Duration = "P1Y",
    
    [Parameter(Mandatory=$false)]
    [string]$TenantID,
    
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionID
)

$ErrorActionPreference = "Stop"

# Check and install EasyPIM module if not present
$easyPimModule = Get-Module -ListAvailable -Name EasyPIM
if (-not $easyPimModule) {
    Write-Output "EasyPIM module not found. Installing..."
    try {
        # Set PSGallery as trusted temporarily for installation
        $repo = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        $wasTrusted = $repo.InstallationPolicy -eq "Trusted"
        
        if (-not $wasTrusted) {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
        
        Install-Module -Name EasyPIM -Scope CurrentUser -Force -AllowClobber
        
        # Restore original trust setting
        if (-not $wasTrusted) {
            Set-PSRepository -Name PSGallery -InstallationPolicy Untrusted
        }
        
        Write-Output "EasyPIM module installed successfully."
    } catch {
        Write-Error "Failed to install EasyPIM module: $_"
        exit 1
    }
}

# Import EasyPIM module
try {
    Import-Module EasyPIM -ErrorAction Stop
} catch {
    Write-Error "Failed to import EasyPIM module: $_"
    exit 1
}

# Get tenant and subscription from context if not provided
if (-not $TenantID -or -not $SubscriptionID) {
    $context = Get-AzContext
    if (-not $context) {
        Write-Error "Not logged in to Azure. Run Connect-AzAccount first."
        exit 1
    }
    if (-not $TenantID) {
        $TenantID = $context.Tenant.Id
    }
    if (-not $SubscriptionID) {
        $SubscriptionID = $context.Subscription.Id
    }
}

$startDateTime = (Get-Date).ToUniversalTime()

# Check if role is already assigned
$existingRole = Get-AzRoleAssignment -Scope $Scope -PrincipalId $PrincipalID -RoleDefinitionName $RoleName -ErrorAction SilentlyContinue

if ($existingRole) {
    Write-Output "SKIP: Role '$RoleName' is already directly assigned to principal '$PrincipalID' at scope '$Scope'."
    exit 0
}

# Check for existing PIM eligible assignment
try {
    $existingEligible = Get-AzRoleEligibilitySchedule -Scope $Scope -Filter "principalId eq '$PrincipalID'" -ErrorAction SilentlyContinue |
        Where-Object { $_.RoleDefinitionDisplayName -eq $RoleName }
    
    if ($existingEligible) {
        Write-Output "SKIP: PIM eligible assignment for '$RoleName' already exists for principal '$PrincipalID' at scope '$Scope'."
        exit 0
    }
} catch {
    # Continue if check fails - will attempt assignment anyway
}

# Assign PIM eligible role
try {
    New-PIMAzureResourceEligibleAssignment `
        -tenantID $TenantID `
        -subscriptionID $SubscriptionID `
        -rolename $RoleName `
        -principalID $PrincipalID `
        -startDateTime $startDateTime `
        -duration $Duration `
        -scope $Scope
    
    Write-Output "SUCCESS: Assigned PIM eligible role '$RoleName' to principal '$PrincipalID' at scope '$Scope' for duration '$Duration'."
} catch {
    Write-Error "Failed to assign PIM role: $_"
    exit 1
}
