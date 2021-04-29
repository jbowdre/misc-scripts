function handler($context, $inputs) {
    # Initialize variables
    $template_password = $context.getSecret($inputs.customProperties.template_password)
    $template_user = $inputs.customProperties.template_user
    $vcUser = $inputs.customProperties.vCenterUser
    $vcPassword = $context.getSecret($inputs.customProperties.vCenterPassword)
    $vCenter = $inputs.customProperties.vCenter
    $domainLong = $inputs.customProperties.dnsDomain
    $adminsList = $inputs.customProperties.adminsList
    
    # Standardize users entered without domain as DOMAIN\username
    If ($adminsList.Length -gt 0) {
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
    # Create vmtools connection to the VM 
    $name = $inputs.resourceNames[0]
    Connect-ViServer $vCenter -User $vcUser -Password $vcPassword -Force
    Write-Host "Waiting for VM Tools to start..."
    do {
        $toolsStatus = (Get-VM -Name $name | Get-View).Guest.ToolsStatus 
        Write-Host $toolsStatus
        sleep 3
    } until ($toolsStatus -eq 'toolsOk')
    $vm = Get-VM -Name $name
    
    # Detect hostname and OS type
    $hostname = ($vm | Get-View).Guest.HostName.toLower()
    Write-Host "VM hostname is $hostname"
    $osType = ($vm | Get-View).Guest.GuestFamily
    Write-Host "VM OS type is $osType"
    
    # Run OS-specific tasks
    if ($osType.Equals("windowsGuest")) {
        # Add domain accounts to local administrators group
        if ($adminsList.Length -gt 0) {
            $adminScript = "Add-LocalGroupMember -Group Administrators -Member $admins"
            Start-Sleep -s 10
            Write-Host "Attempting to add administrator accounts..."
            $runAdminScript = Invoke-VMScript -VM $vm -ScriptText $adminScript -GuestUser $template_user -GuestPassword $template_password -ToolsWaitSecs 300
            if ($runAdminScript.ScriptOutput.Length -eq 0) {
                Write-Host "Successfully added [$admins] to Administrators group."
            } else {
                Write-Host "Attempt to add [$admins] to Administrators group completed with warnings:"
                Write-Host "==========================================================`n" $runAdminScript.ScriptOutput "=========================================================="
            }
        } else {
            Write-Host "No admins to add..."
        }
        # Extend C: volume to fill system drive
        $partitionScript = "`$Partition = Get-Volume -DriveLetter C | Get-Partition; `$Partition | Resize-Partition -Size (`$Partition | Get-PartitionSupportedSize).sizeMax"
        Start-Sleep -s 10
        Write-Host "Attempting to extend system volume..."
        $runPartitionScript = Invoke-VMScript -VM $vm -ScriptText $partitionScript -GuestUser $template_user -GuestPassword $template_password -ToolsWaitSecs 300
        if ($runPartitionScript.ScriptOutput.Length -eq 0) {
            Write-Host "Successfully extended system partition."
        } else {
            Write-Host "Attempt to extend system volume completed with warnings:"
            Write-Host "==========================================================`n" $runPartitionScript.ScriptOutput "=========================================================="            
        }
        # Create scheduled task to apply updates and reboot
        $updateScript = "`$action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -Command `"& {Install-WUUpdates -Updates (Start-WUScan); if (Get-WUIsPendingReboot) {Restart-Computer -Force}}`"'
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
        Write-Host "Creating a scheduled task to apply updates and reboot..."
        $runUpdateScript = Invoke-VMScript -VM $vm -ScriptText $updateScript -GuestUser $template_user -GuestPassword $template_password -ToolsWaitSecs 300
        Write-Host "Created task:"
        Write-Host "==========================================================`n" $runUpdateScript.ScriptOutput "=========================================================="            
    }
    # TODO: add Linux tasks here
}
