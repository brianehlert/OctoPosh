<#
.SYNOPSIS
	A script to move Octoblu devices from the ownership of one user to another
.DESCRIPTION
	This script is designed to facilitate setting up demonstrations. 
    It is common to develop using personal accounts and then having to rebuild
    using a shared account during the process of executing demos and prototypes.
    This works around having to re-build Octoblu devices by moving the ownership.

    There is no way to bypass the verification - by design.

.PARAMETERS
    deviceOwner - the user that currently owns the device
    deviceOwnerToken - the secret token of the user that currently owns the device
    deviceNewOwner - the user that the device is being moved to
    deviceNewOwnerToken - the secret token of the user the device is being moved to
    deviceToMove - The name of the device(s) to be moved
.AUTHOR
    Brian Ehlert, Citrix Labs, Redmond, WA 
#>

Param
(
    [parameter(Mandatory = $false)]
    [String]$deviceOwner,

    [parameter(Mandatory = $false)]
    [Alias("deviceOwnerToken")]
    [String]$deviceOwnerSecret,

    [parameter(Mandatory = $false)]
    [String]$deviceNewOwner,

    [parameter(Mandatory = $false)]
    [Alias("deviceNewOwnerToken")]
    [String]$deviceNewOwnerSecret,

    [parameter(Mandatory = $false)]
    [Alias("deviceToMove")]
    [String]$nameToMove
)

# What is the UUID and token of the current device owner?
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


# What is the UUID of the user you will be moving your devices to?
# and test that it is actually good.
Do {
    Do {
        if (!$deviceNewOwner) { $deviceNewOwner = Read-Host -Prompt "What is the uuid of the new device owner? " }
        if (!$deviceNewOwnerSecret) { $deviceNewOwnerSecret = Read-Host -Prompt "What is the secret token of the new device owner? " }

        $youAuthHeader = @{
            meshblu_auth_uuid = $deviceNewOwner   
            meshblu_auth_token = $deviceNewOwnerSecret
        }

        If ($deviceNewOwnerSecret) {
            $you = Invoke-RestMethod -URI ("http://meshblu.octoblu.com/devices/" + $deviceNewOwner) -Headers $youAuthHeader -Method Get -ErrorAction SilentlyContinue
        } else { $you.devices.octoblu.email = "No token provided. Unable to validate" }

    } until ($you)
    
    # echo back what you find
    "The new device owner will be: " + $you.devices[0].octoblu.email

} until ( (Read-Host -Prompt "Is this the correct new device owner? Type 'YES'") -eq 'YES' )


# List all of 'my devices' in a nice, neat way with the important bits - name, uuid, device type
$devices = Invoke-RestMethod -URI http://meshblu.octoblu.com/mydevices -Headers $meAuthHeader -Method Get

# Which device <name> will you be moving to another user?
# base on device name as everything associated in the case of Gateblu needs to go.
Do {
    $devices.devices | Sort-Object Name | Format-Table -AutoSize name, uuid, type, subtype, online

    Do {
        if (!$nameToMove) { $nameToMove = Read-Host -Prompt "What is the name of the device you will be moving to the other user? (this is a match)" }

        $deviceToMove = $devices.devices -match $nameToMove }

    Until ( $deviceToMove )

    "The following device(s) matched: "
    $deviceToMove | Format-Table -AutoSize Name, UUID

} until ( (Read-Host -Prompt "proceed to move your device(s)? Type 'YES'") -eq 'YES' )

# The device only needs to be discoverable to take ownership.
foreach ( $device in $deviceToMove ) {
    
    If ( $device.discoverWhitelist ) {
        $device.discoverWhitelist += $deviceNewOwner

        $json = @{
            "discoverWhitelist" = $device.discoverWhitelist
        }

    } else {
        $json = @{
            "discoverWhitelist" = $deviceNewOwner
        }
    }

    $json = $json | ConvertTo-Json

    # make the device discoverable by the new owner
    Invoke-RestMethod -URI ( "http://meshblu.octoblu.com/devices/" + $device.uuid ) -ContentType "application/json" -Body $json -Headers $meAuthHeader -Method Put

    If ( $youAuthHeader.meshblu_auth_token ) {
        # claim the device as the new owner
        # only if you know the token - otherwise the other user will need to do that
        Invoke-RestMethod -URI ("http://meshblu.octoblu.com/claimdevice/" + $device.uuid ) -ContentType "application/json" -Headers $youAuthHeader -Method Put
    }
}
