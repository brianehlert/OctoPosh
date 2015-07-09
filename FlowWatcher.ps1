<#
.SYNOPSIS
	A script to monitor Octoblu workflows and restart them if they stop
.DESCRIPTION
	This script is designed to run as a service and monitor the running status of workflows.
    It can start and then monitor flows to keep them running.  It can monitor existing flows and
    ensure they remain running if they become stopped for any reason.
    This does not check that a flow is responding, only tht it is running.

    There is no way to bypass the authentication verification - by design.
.PARAMETERS
    none - built to run interactively only
.AUTHOR
    Brian Ehlert, Citrix Labs, Redmond, WA 
#>


# What is the UUID and token of the flow owner? 
# and test that it is actually good 
 Do { 
     Do { 
         if (!$deviceOwner) { $deviceOwner = Read-Host -Prompt "What is the uuid of the current device owner? (your account)" } 
         if (!$deviceOwnerSecret) { $deviceOwnerSecret = Read-Host -Prompt "What is the secret token of the current device owner? (your account)" } 

         $meAuthHeader = @{ 
             meshblu_auth_uuid = $deviceOwner    
             meshblu_auth_token = $deviceOwnerSecret 
         } 
 
         $me = Invoke-RestMethod -URI ("http://meshblu.octoblu.com/devices/" + $deviceOwner) -Headers $meAuthHeader -Method Get -ErrorAction SilentlyContinue 
 
     } Until ( $me ) 
 
     # echo back what you find 
     "The current device owner is: " + $me.devices[0].octoblu.email 
 
} until ( (Read-Host -Prompt "Is this correct? Type 'YES'") -eq 'YES' ) 

# Get all flows belonging to this owner
$allFlows = Invoke-RestMethod -URI ("https://app.octoblu.com/api/flows/") -Headers $meAuthHeader -Method Get

# List the flows for selection
$allFlows | ft @{Label="number"; Expression={ [array]::IndexOf($allFlows, $_) }}, name, flowid -AutoSize

$items = (Read-Host -Prompt 'Enter the number of the flow(s) that will be monitored. If more than one add a comma in-between') -split ","

# Build the array of flows to watch for running state
$flowsToWatch = @()

foreach ($item in $items) {
    $flowsToWatch += $allFlows[$item].flowId
}

# The loop
$duration = New-TimeSpan -Hours (Read-Host -Prompt "How many hours would you like to watch the flow(s)?")
$hesitation = New-TimeSpan -Seconds (Read-Host -Prompt "How many seconds in between checking the flow(s)?")
$stop = Read-Host -Prompt "Would you like the flows to be stopped when monitoring ends? (yes or no)" 
$now = Get-Date
$end = $now + $duration

"start time: " + $now
"end time will be: " + $end

do {

    foreach ($flowId in $flowsToWatch) {

        # Get the flow from Meshblu
        $objFlowDevice = Invoke-RestMethod -URI ("http://meshblu.octoblu.com/devices/" + $flowId) -Headers $meAuthHeader -Method Get

        ## If $objFlowDevice.devices is empty the flow has never run
        if (! $objFlowDevice.devices[0] ) {
            
            # get the flow from Octoblu
            $objFlow = Invoke-RestMethod -URI ("https://app.octoblu.com/api/flows/" + $flowId) -Headers $meAuthHeader -Method Get

            # if $objFlow is empty then the flow UUID is incorrect / flow does not exist
            If (! $objFlow) { 
                "The flow does not exist" 
                # remove the flow from being watched
            } else {
                "Creating and starting the flow " + $flowId
                Invoke-RestMethod -URI ("https://app.octoblu.com/api/flows/" + $flowId + "/instance") -Headers $meAuthHeader -Method Post
            }
        }

        # If $objFlowDevice.devices.online -eq $false then the flow is not running
        if (! $objFlowDevice.devices[0].online ) {
            
            "double checking flow running status"  # This is necessary when strange things are happening.
            if (! (Invoke-RestMethod -URI ("http://meshblu.octoblu.com/devices/" + $flowId) -Headers $meAuthHeader -Method Get).devices[0].online ) {

                "Starting the flow " + $flowId
                Invoke-RestMethod -URI ("https://app.octoblu.com/api/flows/" + $flowId + "/instance") -Headers $meAuthHeader -Method Post
            }
        } else { "The flow " + $flowId + " is running" }

    }

    Start-Sleep $hesitation.TotalSeconds

} while ( (get-date) -le $end )


if ($stop -match "y") {

    foreach ($flowId in $flowsToWatch) {
        
        # Stop a flow
        Invoke-RestMethod -URI ("https://app.octoblu.com/api/flows/" + $flowId + "/instance") -Headers $meAuthHeader -Method Delete
    }

} else { "Flows will remain unchanged"}

