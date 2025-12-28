Param(
  [Parameter(Mandatory=$true)] [string]$ResourceGroupName,
  [Parameter(Mandatory=$true)] [string]$NSPName,
  [Parameter(Mandatory=$true)] [string]$ResourceId
)

$ErrorActionPreference = "Stop"

if (-not $ResourceId -or -not $ResourceGroupName -or -not $NSPName) {
    Write-Error "Missing required parameters."
    exit 1
}

try {
  $SubscriptionId = az account show --query id -o tsv
  # Token fetch needs to be robust
  $token = az account get-access-token --resource-type arm --query accessToken -o tsv
  
  if (-not $token) { Write-Error "Failed to acquire access token."; exit 1 }

  # --- GET PROFILE ---
  $apiVersion = "2023-07-01-preview"
  $baseUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Network/networkSecurityPerimeters/$NSPName"
  
  $headers = @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" }
  
  # Get Profiles
  $url = "$baseUrl/profiles?api-version=$apiVersion"
  $response = Invoke-RestMethod -Method Get -Uri $url -Headers $headers -ErrorAction Stop
  $ProfileNSP = $response.value

  if (-not $ProfileNSP -or $ProfileNSP.Count -eq 0) {
      Write-Error "No profiles found in NSP '$NSPName'."
      exit 1
  }
  # Default to first profile
  $profileIdString = if ($ProfileNSP -is [array]) { $ProfileNSP[0].id } else { $ProfileNSP.id }

  # --- GENERATE ASSOCIATION NAME (DETERMINISTIC) ---
  # REMOVED TIMESTAMP to ensure Idempotency. 
  # Using the same resource ID always generates the same association name.
  $hashedResourceID = [System.Math]::Abs($ResourceId.GetHashCode()).ToString()
  $uniqueAssociationName = "assoc-$hashedResourceID"
  
  Write-Output "Association Name: $uniqueAssociationName"

  # --- CREATE/UPDATE ASSOCIATION ---
  $assocUrl = "$baseUrl/resourceAssociations/$uniqueAssociationName`?api-version=$apiVersion"
  
  Write-Output "URL: $assocUrl"
  
  $body = @{
    properties = @{
        accessMode = "Learning"
        privateLinkResource = @{ id = $ResourceId }
        profile = @{ id = $profileIdString }
    }
  } | ConvertTo-Json -Depth 10

  Write-Output "Body: $body"

  Invoke-RestMethod -Method Put -Uri $assocUrl -Headers $headers -Body $body -ErrorAction Stop
  
  Write-Output "Successfully attached resource to NSP."
  
} catch {
  Write-Error "Failed to attach resource to NSP. Error: $_"
  exit 1
}