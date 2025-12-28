param(
    [Parameter(Mandatory = $false)]
    [string]$capacityId,
    
    [Parameter(Mandatory = $false)]
    [string]$workspaceName,
    
    [Parameter(Mandatory = $false)]
    [string]$description = ""
)

# Prompt for missing parameters
if (-not $capacityId) {
    $capacityId = Read-Host "Enter Fabric Capacity ID (e.g., /subscriptions/.../resourceGroups/.../providers/Microsoft.Fabric/capacities/...)"
}

if (-not $workspaceName) {
    $workspaceName = Read-Host "Enter Workspace Name"
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Creating Fabric Workspace" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Capacity ID  : $capacityId" -ForegroundColor Yellow
Write-Host "Workspace    : $workspaceName" -ForegroundColor Yellow
Write-Host "Description  : $description" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

# Check if capacityId is an Azure resource ID (contains "/subscriptions/")
# If so, convert it to Fabric capacity GUID
if ($capacityId -match "^/subscriptions/") {
    Write-Host "Detected Azure resource ID. Converting to Fabric capacity GUID..." -ForegroundColor Yellow
    
    # Extract capacity name from resource ID
    $capacityName = $capacityId.Split('/')[-1]
    Write-Host "Capacity Name: $capacityName" -ForegroundColor Yellow
    
    # Get Power BI token to query capacities
    $powerBiToken = az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv
    
    if (-not $powerBiToken) {
        Write-Error "Failed to get Power BI token"
        exit 1
    }
    
    # Query Power BI API to find capacity by name
    $powerBiHeaders = @{
        "Authorization" = "Bearer $powerBiToken"
    }
    
    try {
        $capacities = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/capacities" -Headers $powerBiHeaders
        $matchedCapacity = $capacities.value | Where-Object { $_.displayName -eq $capacityName }
        
        if ($matchedCapacity) {
            $capacityGuid = $matchedCapacity.id
            Write-Host "✓ Found capacity GUID: $capacityGuid" -ForegroundColor Green
            $capacityId = $capacityGuid
        } else {
            Write-Error "Capacity '$capacityName' not found in Power BI capacities list"
            exit 1
        }
    }
    catch {
        Write-Error "Failed to query Power BI capacities: $_"
        exit 1
    }
} else {
    # Already a GUID, extract capacity name for display purposes
    $capacityName = $capacityId
}

# Get Azure AD token for Fabric API
Write-Host "Getting Azure AD token..." -ForegroundColor Green
$token = az account get-access-token --resource https://api.fabric.microsoft.com --query accessToken -o tsv

if (-not $token) {
    Write-Error "Failed to get Azure AD token"
    exit 1
}

# Prepare request body
$body = @{
    displayName = $workspaceName
    description = $description
    capacityId = $capacityId
} | ConvertTo-Json

# Create workspace using Fabric REST API
Write-Host "Creating workspace via Fabric API..." -ForegroundColor Green
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

try {
    $response = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces" `
        -Method Post `
        -Headers $headers `
        -Body $body

    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Workspace Created Successfully!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Workspace ID   : $($response.id)" -ForegroundColor Cyan
    Write-Host "Workspace Name : $($response.displayName)" -ForegroundColor Cyan
    Write-Host "Capacity       : $capacityName" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Green
    
    # Return workspace details as JSON
    $response | ConvertTo-Json
}
catch {
    Write-Error "Failed to create workspace: $_"
    Write-Error $_.Exception.Message
    exit 1
}
