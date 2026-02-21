# Get Azure Activity Log events
# Parameters: -ResourceGroup, -ResourceId, -ResourceName, -Days, -MaxEvents, -OperationType

param(
    [string]$ResourceGroup,
    [string]$ResourceId,
    [string]$ResourceName,
    [int]$Days = 7,
    [int]$MaxEvents = 50,
    [string]$OperationType
)

$ErrorActionPreference = "Stop"

try {
    # Validate days
    if ($Days -lt 1) { $Days = 1 }
    if ($Days -gt 90) { $Days = 90 }
    
    # Validate max events
    if ($MaxEvents -lt 1) { $MaxEvents = 50 }
    if ($MaxEvents -gt 500) { $MaxEvents = 500 }
    
    # If ResourceName provided but not ResourceId, look it up
    if ($ResourceName -and -not $ResourceId) {
        if ($ResourceGroup) {
            $ResourceId = az resource list -g $ResourceGroup --query "[?name=='$ResourceName'].id" -o tsv 2>&1
        } else {
            $ResourceId = az resource list --query "[?name=='$ResourceName'].id" -o tsv 2>&1
        }
        
        if ($ResourceId -is [array]) {
            $ResourceId = $ResourceId | Where-Object { $_ -and $_ -notmatch "ERROR" } | Select-Object -First 1
        }
        
        if (-not $ResourceId -or $ResourceId -match "ERROR") {
            Write-Output ('{"error": "Could not find resource: ' + $ResourceName + '"}')
            exit 0
        }
    }
    
    # Calculate start time
    $startTime = (Get-Date).AddDays(-$Days).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    
    # Build command
    $cmd = @("az", "monitor", "activity-log", "list", "--start-time", $startTime, "--max-events", $MaxEvents, "--output", "json")
    
    if ($ResourceGroup -and -not $ResourceId) {
        $cmd += @("--resource-group", $ResourceGroup)
    }
    
    if ($ResourceId) {
        $cmd += @("--resource-id", $ResourceId)
    }
    
    $result = & $cmd[0] $cmd[1..($cmd.Length-1)] 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Output ('{"error": "Failed to get activity log: ' + ($result -join " ").Replace('"', '\"') + '"}')
        exit 0
    }
    
    $events = $result | ConvertFrom-Json
    
    # Filter by operation type if specified
    if ($OperationType) {
        $events = $events | Where-Object { 
            $_.operationName.value -like "*$OperationType*" -or 
            $_.operationName.localizedValue -like "*$OperationType*" 
        }
    }
    
    # Format events
    $formattedEvents = @()
    $statusCounts = @{}
    
    foreach ($event in $events) {
        $status = if ($event.status.localizedValue) { $event.status.localizedValue } else { $event.status.value }
        
        $formattedEvent = @{
            timestamp = $event.eventTimestamp
            operation = if ($event.operationName.localizedValue) { $event.operationName.localizedValue } else { $event.operationName.value }
            status = $status
            caller = $event.caller
            resourceGroup = $event.resourceGroupName
            resourceType = $event.resourceType.value
            resourceId = $event.resourceId
            level = $event.level
        }
        
        if ($event.description) {
            $formattedEvent.description = $event.description
        }
        
        if ($event.properties.statusCode) {
            $formattedEvent.statusCode = $event.properties.statusCode
        }
        
        $formattedEvents += $formattedEvent
        
        # Count statuses
        if (-not $statusCounts.ContainsKey($status)) {
            $statusCounts[$status] = 0
        }
        $statusCounts[$status]++
    }
    
    @{
        timeRange = "Last $Days day(s)"
        startTime = $startTime
        totalEvents = $formattedEvents.Count
        statusSummary = $statusCounts
        events = $formattedEvents
    } | ConvertTo-Json -Depth 5
}
catch {
    Write-Output ('{"error": "' + $_.Exception.Message.Replace('"', '\"') + '"}')
}
