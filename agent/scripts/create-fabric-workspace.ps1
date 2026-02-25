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
# If so, convert it to Fabric capacity GUID using Azure ARM API
if ($capacityId -match "^/subscriptions/") {
    Write-Host "Detected Azure resource ID. Converting to Fabric capacity GUID..." -ForegroundColor Yellow
    
    # Extract capacity name from resource ID
    $capacityName = $capacityId.Split('/')[-1]
    Write-Host "Capacity Name: $capacityName" -ForegroundColor Yellow
    
    # First, verify the capacity exists and is active using Azure ARM API
    Write-Host "Checking capacity status in Azure..." -ForegroundColor Yellow
    $armCapacity = az resource show --ids $capacityId --query "{name:name, state:properties.state, provisioningState:properties.provisioningState}" -o json 2>$null | ConvertFrom-Json
    
    if (-not $armCapacity) {
        Write-Error "Capacity not found in Azure. Please verify the resource ID is correct."
        exit 1
    }
    
    if ($armCapacity.provisioningState -ne "Succeeded") {
        Write-Error "Capacity provisioning state is '$($armCapacity.provisioningState)'. Please wait for provisioning to complete."
        exit 1
    }
    
    if ($armCapacity.state -ne "Active") {
        Write-Error "Capacity state is '$($armCapacity.state)'. Capacity must be 'Active' to create workspaces."
        exit 1
    }
    
    Write-Host "Capacity is Active and Provisioned" -ForegroundColor Green
    
    # Try to get capacity GUID from Power BI API first
    $powerBiToken = az account get-access-token --resource https://analysis.windows.net/powerbi/api --query accessToken -o tsv
    $capacityGuid = $null
    
    if ($powerBiToken) {
        $powerBiHeaders = @{
            "Authorization" = "Bearer $powerBiToken"
        }
        
        try {
            $capacities = Invoke-RestMethod -Uri "https://api.powerbi.com/v1.0/myorg/capacities" -Headers $powerBiHeaders
            $matchedCapacity = $capacities.value | Where-Object { $_.displayName -eq $capacityName }
            
            if ($matchedCapacity) {
                $capacityGuid = $matchedCapacity.id
                Write-Host "Found capacity GUID via Power BI API: $capacityGuid" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Power BI API lookup failed, will try ARM API..." -ForegroundColor Yellow
        }
    }
    
    # If Power BI API didn't find it, try Azure ARM API to get the capacity GUID
    if (-not $capacityGuid) {
        Write-Host "Capacity not yet visible in Power BI API. Trying Azure ARM API..." -ForegroundColor Yellow
        
        # Get ARM token
        $armToken = az account get-access-token --query accessToken -o tsv
        
        if ($armToken) {
            $armHeaders = @{
                "Authorization" = "Bearer $armToken"
                "Content-Type" = "application/json"
            }
            
            # Extract subscription, resource group from the resource ID
            $resourceIdParts = $capacityId -split '/'
            $subscriptionId = $resourceIdParts[2]
            $resourceGroup = $resourceIdParts[4]
            
            # Use ARM API to get capacity details including the GUID
            $armApiUrl = "https://management.azure.com$capacityId`?api-version=2023-11-01"
            
            try {
                $armResponse = Invoke-RestMethod -Uri $armApiUrl -Headers $armHeaders -Method Get
                
                # The capacity GUID should be in the response - it's typically in properties or as part of the resource
                # For Fabric capacities, we can derive the GUID from the resource name or it may be in properties
                if ($armResponse.properties -and $armResponse.properties.capacityId) {
                    $capacityGuid = $armResponse.properties.capacityId
                    Write-Host "Found capacity GUID via ARM API: $capacityGuid" -ForegroundColor Green
                } else {
                    # If no explicit GUID, use the capacity name as-is (Fabric API may accept it)
                    Write-Host "Could not find explicit capacity GUID. Will attempt to use capacity name directly." -ForegroundColor Yellow
                    Write-Host "  This may work if the Fabric service recognizes the capacity." -ForegroundColor Yellow
                    
                    # Try to find by listing all Fabric capacities in the subscription
                    $listUrl = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Fabric/capacities?api-version=2023-11-01"
                    $allCapacities = Invoke-RestMethod -Uri $listUrl -Headers $armHeaders -Method Get
                    
                    $foundCapacity = $allCapacities.value | Where-Object { $_.name -eq $capacityName }
                    if ($foundCapacity -and $foundCapacity.properties.capacityId) {
                        $capacityGuid = $foundCapacity.properties.capacityId
                        Write-Host "Found capacity GUID from subscription list: $capacityGuid" -ForegroundColor Green
                    }
                }
            }
            catch {
                Write-Host "ARM API lookup failed: $_" -ForegroundColor Yellow
            }
        }
    }
    
    # Final fallback: if we still don't have a GUID, provide guidance
    if (-not $capacityGuid) {
        Write-Host "" -ForegroundColor Red
        Write-Host "==========================================" -ForegroundColor Red
        Write-Host "Capacity GUID Not Found" -ForegroundColor Red
        Write-Host "==========================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "The capacity '$capacityName' exists in Azure but is not yet visible" -ForegroundColor Yellow
        Write-Host "in the Fabric/Power BI API. This is a known synchronization delay." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "OPTIONS:" -ForegroundColor Cyan
        Write-Host "1. Wait 5-10 more minutes for sync to complete" -ForegroundColor Gray
        Write-Host "2. Get the Capacity GUID from Azure Portal:" -ForegroundColor Gray
        Write-Host "   - Go to Azure Portal → Resource Groups → $resourceGroup" -ForegroundColor Gray
        Write-Host "   - Open the Fabric Capacity '$capacityName'" -ForegroundColor Gray
        Write-Host "   - Look for 'Capacity ID' or GUID in the Overview/Properties" -ForegroundColor Gray
        Write-Host "3. Provide the GUID directly when calling this script" -ForegroundColor Gray
        Write-Host ""
        Write-Host "==========================================" -ForegroundColor Red
        exit 1
    }
    
    $capacityId = $capacityGuid
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

    # CRITICAL: Workspace ID must be present in response
    if (-not $response.id) {
        Write-Warning "Workspace creation response doesn't contain workspace ID"
        Write-Host "This may be an async operation. Checking workspace list..." -ForegroundColor Yellow
        
        Start-Sleep -Seconds 5
        
        # Try to find the workspace by name
        $allWorkspaces = Invoke-RestMethod -Uri "https://api.fabric.microsoft.com/v1/workspaces" `
            -Method Get `
            -Headers $headers
        
        $foundWorkspace = $allWorkspaces.value | Where-Object { $_.displayName -eq $workspaceName }
        
        if ($foundWorkspace -and $foundWorkspace.id) {
            $response = $foundWorkspace
            Write-Host "Found workspace in list" -ForegroundColor Green
        } else {
            # Workspace ID not found - consider this a failure
            Write-Host "" -ForegroundColor Red
            Write-Host "==========================================" -ForegroundColor Red
            Write-Host "Workspace Creation Failed" -ForegroundColor Red
            Write-Host "==========================================" -ForegroundColor Red
            Write-Host "Workspace Name : $workspaceName" -ForegroundColor Yellow
            Write-Host "Capacity ID    : $capacityId" -ForegroundColor Yellow
            Write-Host "==========================================" -ForegroundColor Red
            Write-Host "" -ForegroundColor Red
            Write-Host "FAILURE REASON:" -ForegroundColor Red
            Write-Host "─────────────────────────────────────────" -ForegroundColor Red
            Write-Host "Workspace ID was not returned by Fabric API." -ForegroundColor Yellow
            Write-Host "This indicates the workspace was NOT successfully created." -ForegroundColor Yellow
            Write-Host "" -ForegroundColor Red
            Write-Host "POSSIBLE CAUSES:" -ForegroundColor Cyan
            Write-Host "  • Capacity is not active or in a valid state" -ForegroundColor Gray
            Write-Host "  • Insufficient Fabric admin permissions" -ForegroundColor Gray
            Write-Host "  • Workspace name already exists in another capacity" -ForegroundColor Gray
            Write-Host "  • Capacity does not exist or ID is incorrect" -ForegroundColor Gray
            Write-Host "  • Capacity resource is not provisioned yet" -ForegroundColor Gray
            Write-Host "" -ForegroundColor Red
            Write-Host "TROUBLESHOOTING:" -ForegroundColor Cyan
            Write-Host "  1. Verify capacity exists and is active:" -ForegroundColor Gray
            Write-Host "     az fabric capacity show --ids '$capacityId'" -ForegroundColor Gray
            Write-Host "  2. Check capacity state is 'Active' not 'Paused'" -ForegroundColor Gray
            Write-Host "  3. Verify you have Capacity Admin role" -ForegroundColor Gray
            Write-Host "  4. Try a different workspace name" -ForegroundColor Gray
            Write-Host "  5. Wait 5 minutes if capacity was just created" -ForegroundColor Gray
            Write-Host "==========================================" -ForegroundColor Red
            exit 1
        }
    }

    # VALIDATION: Ensure workspace ID is present before declaring success
    if (-not $response.id) {
        Write-Host "" -ForegroundColor Red
        Write-Host "==========================================" -ForegroundColor Red
        Write-Host "Workspace Creation Failed" -ForegroundColor Red
        Write-Host "==========================================" -ForegroundColor Red
        Write-Host "FAILURE REASON: No Workspace ID returned" -ForegroundColor Red
        Write-Host "The workspace was NOT created successfully." -ForegroundColor Yellow
        Write-Host "==========================================" -ForegroundColor Red
        exit 1
    }

    # SUCCESS: Workspace ID is present
    Write-Host "" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Workspace Created Successfully!" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "Workspace ID   : $($response.id)" -ForegroundColor Cyan
    Write-Host "Workspace Name : $($response.displayName)" -ForegroundColor Cyan
    Write-Host "Capacity       : $capacityName" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Green
    Write-Host "" -ForegroundColor Green
    Write-Host "IMPORTANT: Save this Workspace ID for future operations" -ForegroundColor Yellow
    Write-Host "Workspace ID: $($response.id)" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Green
    
    # Return workspace details as JSON with workspace ID prominently included
    $outputObject = @{
        workspaceId = $response.id
        workspaceName = $response.displayName
        capacityId = $capacityId
        capacityName = $capacityName
        status = "created"
        fullResponse = $response
    }
    
    $outputObject | ConvertTo-Json -Depth 5
}
catch {
    # Extract detailed error information
    $errorMessage = $_.Exception.Message
    $errorDetails = ""
    
    # Try to extract JSON error from Fabric API if available
    if ($_.ErrorDetails.Message) {
        try {
            $errorJson = $_.ErrorDetails.Message | ConvertFrom-Json
            if ($errorJson.error) {
                $errorDetails = $errorJson.error.message
                if ($errorJson.error.code) {
                    $errorDetails = "[$($errorJson.error.code)] $errorDetails"
                }
            }
        } catch {
            $errorDetails = $_.ErrorDetails.Message
        }
    }
    
    Write-Host "" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "Workspace Creation Failed" -ForegroundColor Red
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "Workspace Name : $workspaceName" -ForegroundColor Yellow
    Write-Host "Capacity ID    : $capacityId" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Red
    Write-Host "" -ForegroundColor Red
    Write-Host "ERROR DETAILS:" -ForegroundColor Red
    Write-Host "─────────────────────────────────────────" -ForegroundColor Red
    if ($errorDetails) {
        Write-Host $errorDetails -ForegroundColor Yellow
    } else {
        Write-Host $errorMessage -ForegroundColor Yellow
    }
    Write-Host "" -ForegroundColor Red
    Write-Host "COMMON CAUSES:" -ForegroundColor Cyan
    Write-Host "  • Capacity does not exist or is invalid" -ForegroundColor Gray
    Write-Host "  • Capacity is in 'Paused' state (must be 'Active')" -ForegroundColor Gray
    Write-Host "  • No Fabric Capacity Admin permissions" -ForegroundColor Gray
    Write-Host "  • Workspace name already exists" -ForegroundColor Gray
    Write-Host "  • Invalid capacity ID format" -ForegroundColor Gray
    Write-Host "  • Subscription doesn't have Fabric enabled" -ForegroundColor Gray
    Write-Host "" -ForegroundColor Red
    Write-Host "TROUBLESHOOTING:" -ForegroundColor Cyan
    Write-Host "  1. Verify capacity exists:" -ForegroundColor Gray
    Write-Host "     az resource show --ids '$capacityId'" -ForegroundColor Gray
    Write-Host "  2. Check provisioning state is 'Succeeded':" -ForegroundColor Gray
    Write-Host "     az resource show --ids '$capacityId' --query properties.state" -ForegroundColor Gray
    Write-Host "  3. Verify you're logged in:" -ForegroundColor Gray
    Write-Host "     az account show" -ForegroundColor Gray
    Write-Host "  4. Check Fabric admin access in Azure portal" -ForegroundColor Gray
    Write-Host "  5. Try creating workspace via Fabric portal to test permissions" -ForegroundColor Gray
    Write-Host "==========================================" -ForegroundColor Red
    
    exit 1
}
