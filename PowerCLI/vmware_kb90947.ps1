# Identify VMs impacted by KB90947, wherein a problematic MS patch
# will prevent Windows Server 2022 VMs with Secure Boot enabled
# from booting
#
# https://www.virtuallypotato.com/psa-microsoft-kb5022842-breaks-ws2022-secure-boot/

$secureBoot2022VMs = foreach($datacenter in (Get-Datacenter)) {
  $datacenter | Get-VM |
    Where-Object {$_.Guest.OsFullName -Match 'Microsoft Windows Server 2022' -And $_.ExtensionData.Config.BootOptions.EfiSecureBootEnabled} |
      Select-Object @{N="Datacenter";E={$datacenter.Name}},
        Name,
        @{N="Running OS";E={$_.Guest.OsFullName}},
        @{N="Secure Boot";E={$_.ExtensionData.Config.BootOptions.EfiSecureBootEnabled}},
        PowerState
}
$secureBoot2022VMs | Export-Csv -NoTypeInformation -Path ./secureBoot2022VMs.csv
