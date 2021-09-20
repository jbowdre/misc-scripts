# PowerCLI_Custom_Functions.ps1
# Usage:
#   0) Edit $vCenterList to reference the vCenters in your environment.
#   1) Call 'Update-Credentials' to create/update a ViCredentialStoreItem to securely store your username and password.
#   2) Call 'Connect-vCenters' to open simultaneously connections to all the vCenters in your environment. 
#   3) Do PowerCLI things.
#   4) Call 'Disconnect-vCenters' to cleanly close all ViServer connections because housekeeping.
# See https://virtuallypotato.com/logging-in-to-multiple-vcenter-servers-at-once-with-powercli for additional setup and usage notes.
 
Import-Module VMware.PowerCLI

$vCenterList = @("vcenter1", "vcenter2", "vcenter3", "vcenter4", "vcenter5")

function Update-Credentials {
    $newCredential = Get-Credential
    ForEach ($vCenter in $vCenterList) {
        New-ViCredentialStoreItem -Host $vCenter -User $newCredential.UserName -Password $newCredential.GetNetworkCredential().password
    }
}

function Connect-vCenters {
    ForEach ($vCenter in $vCenterList) {
        Connect-ViServer -Server $vCenter
    }
}

function Disconnect-vCenters {
    Disconnect-ViServer -Server * -Force -Confirm:$false
}
