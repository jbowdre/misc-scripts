function handler($context, $inputs) {
    # Initialize global variables
    # $template_password = $context.getSecret($inputs.customProperties.template_password)
    # $template_user = $inputs.customProperties.template_user
    $vcUser = $inputs.customProperties.vCenterUser
    # $vcPassword = $context.getSecret($inputs.customProperties.vCenterPassword)
    $vcPassword = $context.getSecret($inputs."vCenterPassword")
    $vCenter = $inputs.customProperties.vCenter
    # $domainLong = $inputs.customProperties.dnsDomain
    # $adminsList = $inputs.customProperties.adminsList
    
    # Create vmtools connection to the VM 
    $name = $inputs.resourceNames[0]
    Connect-ViServer $vCenter -User $vcUser -Password $vcPassword -Force
    $vm = Get-VM -Name $name
    Write-Host "Waiting for VM Tools to start..."
    if (-not (Wait-Tools -VM $vm -TimeoutSeconds 180)) {
        Write-Error "Unable to establish connection with VM tools" -ErrorAction Stop
    }
    
    # Detect hostname and OS type
    $hostname = ($vm | Get-View).Guest.HostName.toLower()
    Write-Host "VM hostname is $hostname"
    $osType = ($vm | Get-View).Guest.GuestFamily
    Write-Host "VM OS type is $osType"
    $toolsStatus = (Get-VM -Name $name | Get-View).Guest.ToolsStatus 
    
    # Update tools on Windows if out of date
    if ($osType.Equals("windowsGuest") -And $toolsStatus.Equals("toolsOld")) {
        Write-Host "Updating VM Tools..."
        Update-Tools $vm
        Write-Host "Waiting for VM Tools to start..."
        if (-not (Wait-Tools -VM $vm -TimeoutSeconds 180)) {
            Write-Error "Unable to establish connection with VM tools" -ErrorAction Stop
        }
    }
    
    # Run OS-specific tasks
    if ($osType.Equals("windowsGuest")) {
        # Initialize Windows variables
        $domainLong = $inputs.customProperties.dnsDomain
        $adminsList = $inputs.customProperties.adminsList
        $adJoin = $inputs.customProperties.adObject
        $template_user = $inputs.customProperties.template_user
        $template_password = $adJoin.Equals("true") ? $context.getSecret($inputs."templatePassWinDomain") : $context.getSecret($inputs."templatePassWinWorkgroup")
      
        # Add domain accounts to local administrators group
        if ($adminsList.Length -gt 0) {
            # Standardize users entered without domain as DOMAIN\username
            if ($adminsList.Length -gt 0) {
                $domainShort = $domainLong.split('.')[0]
                $adminsArray = @(($adminsList -Split ',').Trim())
                For ($i=0; $i -lt $adminsArray.Length; $i++) {
                    If ($adminsArray[$i] -notmatch "$domainShort.*\\" -And $adminsArray[$i] -notmatch "@$domainShort") {
                        $adminsArray[$i] = $domainShort + "\" + $adminsArray[$i]
                    }
            }
            $admins = '"{0}"' -f ($adminsArray -join '","')
            Write-Host "Administrators: $admins"
            }
            $adminScript = "Add-LocalGroupMember -Group Administrators -Member $admins"
            Start-Sleep -s 10
            Write-Host "Attempting to add administrator accounts..."
            $runAdminScript = Invoke-VMScript -VM $vm -ScriptText $adminScript -GuestUser $template_user -GuestPassword $template_password
            if ($runAdminScript.ScriptOutput.Length -eq 0) {
                Write-Host "Successfully added [$admins] to Administrators group."
            } else {
                Write-Host "Attempt to add [$admins] to Administrators group completed with warnings:"
                Write-Host "==========================================================`n" $runAdminScript.ScriptOutput "=========================================================="
            }
        } else {
            Write-Host "No admins to add..."
        }
        # Create local admin account
        if (! $adJoin.Equals("true")) {
            $adminUser = $inputs.customProperties.adminUser
            $adminPass = $context.getSecret($inputs.customProperties.adminPass)
            $adminScript = "`$password = ConvertTo-SecureString `"$adminPass`" -AsPlainText -Force
                New-LocalUser -Name $adminUser -Password `$password -Description 'Administrator account created by vRA'
                Add-LocalGroupMember -Group Administrators -Member $adminUser
                `$user=[ADSI]`"WinNT://localhost/$adminUser`";
                `$user.passwordExpired = 1;
                `$user.setinfo();"
            Start-Sleep -s 10
            Write-Host "Creating local admin account..."
            $runAdminScript = Invoke-VMScript -VM $vm -ScriptText $adminScript -GuestUser $template_user -GuestPassword $template_password
            Write-Host "Result:"
            Write-Host "==========================================================`n" $runAdminScript.ScriptOutput "=========================================================="            
        }
        # Extend C: volume to fill system drive
        $partitionScript = "`$Partition = Get-Volume -DriveLetter C | Get-Partition; `$Partition | Resize-Partition -Size (`$Partition | Get-PartitionSupportedSize).sizeMax"
        Start-Sleep -s 10
        Write-Host "Attempting to extend system volume..."
        $runPartitionScript = Invoke-VMScript -VM $vm -ScriptText $partitionScript -GuestUser $template_user -GuestPassword $template_password
        if ($runPartitionScript.ScriptOutput.Length -eq 0) {
            Write-Host "Successfully extended system partition."
        } else {
            Write-Host "Attempt to extend system volume completed with warnings:"
            Write-Host "==========================================================`n" $runPartitionScript.ScriptOutput "=========================================================="            
        }
        # Set up remote access
        $remoteScript = "Enable-NetFirewallRule -DisplayGroup `"Remote Desktop`"
            Enable-NetFirewallRule -DisplayGroup `"Windows Management Instrumentation (WMI)`"
            Enable-NetFirewallRule -DisplayGroup `"File and Printer Sharing`"
            Enable-PsRemoting
            Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name `"fDenyTSConnections`" -Value 0"
        Start-Sleep -s 10
        Write-Host "Attempting to enable remote access (RDP, WMI, File and Printer Sharing, PSRemoting)..."
        $runRemoteScript = Invoke-VMScript -VM $vm -ScriptText $remoteScript -GuestUser $template_user -GuestPassword $template_password
        if ($runRemoteScript.ScriptOutput.Length -eq 0) {
            Write-Host "Successfully enabled remote access."
        } else {
            Write-Host "Attempt to enable remote access completed with warnings:"
            Write-Host "==========================================================`n" $runRemoteScript.ScriptOutput "=========================================================="            
        }
        # Create scheduled task to apply updates
        $updateScript = "`$action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -Command `"& {Install-WUUpdates -Updates (Start-WUScan)}`"'
            `$trigger = New-ScheduledTaskTrigger -Once -At ([DateTime]::Now.AddMinutes(1))
            `$settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -Hidden
            Register-ScheduledTask -Action `$action -Trigger `$trigger -Settings `$settings -TaskName `"Initial_Updates`" -User `"NT AUTHORITY\SYSTEM`" -RunLevel Highest
            `$task = Get-ScheduledTask -TaskName `"Initial_Updates`"
            `$task.Triggers[0].StartBoundary = [DateTime]::Now.AddMinutes(1).ToString(`"yyyy-MM-dd'T'HH:mm:ss`")
            `$task.Triggers[0].EndBoundary = [DateTime]::Now.AddHours(3).ToString(`"yyyy-MM-dd'T'HH:mm:ss`")
            `$task.Settings.AllowHardTerminate = `$True
            `$task.Settings.DeleteExpiredTaskAfter = 'PT0S'
            `$task.Settings.ExecutionTimeLimit = 'PT2H'
            `$task.Settings.Volatile = `$False
            `$task | Set-ScheduledTask"
        Start-Sleep -s 10
        Write-Host "Creating a scheduled task to apply updates..."
        $runUpdateScript = Invoke-VMScript -VM $vm -ScriptText $updateScript -GuestUser $template_user -GuestPassword $template_password
        Write-Host "Created task:"
        Write-Host "==========================================================`n" $runUpdateScript.ScriptOutput "=========================================================="            
    } elseif ($osType.Equals("linuxGuest")) {
        $linUser = $inputs.customProperties.userName
        $linPass = $context.getSecret($inputs.customProperties.password)
        $template_user = $inputs.customProperties.template_user
        $template_password = $context.getSecret($inputs."templatePassLin")
        $linFillDisk = $inputs.customProperties.fillDisk
        $linSatellite = $inputs.customProperties.satellite
        $linNfsScriptShare = $inputs.customProperties.nfsScriptShare
        $linPartitionScript = $inputs.customProperties.partitionScript
        $linSatelliteScript = $inputs.customProperties.satelliteScript
        # Create Linux admin account
        Write-Host "Attempting to create user $linUser..."
        $userScript = "if [ `$(getent group wheel) ]; then adminGroup='-G wheel'; elif [ `$(getent group sudo) ]; then adminGroup='-G sudo'; fi; useradd -s /bin/bash `$adminGroup -m $linUser; echo `"$linUser`:$linPass`" | chpasswd; passwd -e $linUser"
        Start-Sleep -s 10
        $runUserScript = Invoke-VMScript -VM $vm -ScriptText $userScript -GuestUser $template_user -GuestPassword $template_password
        Write-Host "Result:"
        Write-Host "==========================================================`n" $runUserScript.ScriptOutput "=========================================================="            
        # Extend root LVM to fill VMDK
        if ($linFillDisk -eq $True) {
            Write-Host "Attempting to expand root partition..."
            $partitionScript = "mkdir -p /repo; mount -t nfs $linNfsScriptShare /repo; /repo/$linPartitionScript; umount /repo; rm -rf /repo"
            Start-Sleep -s 10
            $runPartitionScript = Invoke-VMScript -VM $vm -ScriptText $partitionScript -GuestUser $template_user -GuestPassword $template_password
            Write-Host "Result:"
            Write-Host "==========================================================`n" $runPartitionScript.ScriptOutput "=========================================================="            
        }
        # Register with Satellite
        if ($linSatellite -eq $True) {
            Write-Host "Attempting to register with TDY Satellite..."
            $satelliteScript = "mkdir -p /repo; mount -t nfs $linNfsScriptShare /repo; /repo/$linSatelliteScript; umount /repo; rm -rf /repo"
            Start-Sleep 10
            $runSatelliteScript = Invoke-VMScript -VM $vm -ScriptText $satelliteScript -GuestUser $template_user -GuestPassword $template_password
            Write-Host "Result:"
            Write-Host "==========================================================`n" $runSatelliteScript.ScriptOutput "=========================================================="            
        }
    }
}
