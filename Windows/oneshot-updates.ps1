# This can be easily pasted into a remote PowerShell session to automatically install any available updates and reboot. 
# It creates a scheduled task to start the update process after a one-minute delay so that you don't have to maintain
# the session during the process (or have the session timeout), and it also sets the task to automatically delete itself 2 hours later.
# 
# Adapted from https://iamsupergeek.com/self-deleting-scheduled-task-via-powershell/

$action = New-ScheduledTaskAction -Execute 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -Command "& {Install-WUUpdates -Updates (Start-WUScan); if (Get-WUIsPendingReboot) {shutdown.exe /f /r /t 120 /c `"Rebooting to apply updates`"}}"'
$trigger = New-ScheduledTaskTrigger -Once -At ([DateTime]::Now.AddMinutes(1))
$settings = New-ScheduledTaskSettingsSet -Compatibility Win8 -Hidden
Register-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -TaskName "Initial_Updates" -User "NT AUTHORITY\SYSTEM" -RunLevel Highest
$task = Get-ScheduledTask -TaskName "Initial_Updates"
$task.Triggers[0].StartBoundary = [DateTime]::Now.AddMinutes(1).ToString("yyyy-MM-dd'T'HH:mm:ss")
$task.Triggers[0].EndBoundary = [DateTime]::Now.AddHours(2).ToString("yyyy-MM-dd'T'HH:mm:ss")
$task.Settings.AllowHardTerminate = $True
$task.Settings.DeleteExpiredTaskAfter = 'PT0S'
$task.Settings.ExecutionTimeLimit = 'PT2H'
$task.Settings.Volatile = $False
$task | Set-ScheduledTask
