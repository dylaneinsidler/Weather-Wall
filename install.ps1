# Sets up Weather Wall on this PC: a "Weather Wall" shortcut on the Desktop, and a daily task that opens it.
#   Install:   right-click this file > Run with PowerShell
#   Remove:    run it with -Uninstall
#   Other time: run it with -At '6:30 AM'

param(
    [string]$At = '7:00 AM',
    [switch]$Uninstall
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$shortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Weather Wall.lnk'
$taskName = 'Weather Wall'

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item $shortcut -ErrorAction SilentlyContinue
    Write-Host 'Weather Wall removed (Desktop shortcut and daily task).'
    Start-Sleep -Seconds 5
    return
}

# Windows won't quietly run files downloaded from the internet until they're unblocked.
Get-ChildItem $here -File | Unblock-File

$wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
$launch = "`"$(Join-Path $here 'launch.vbs')`""

$link = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcut)
$link.TargetPath = $wscript
$link.Arguments = $launch
$link.WorkingDirectory = $here
$link.IconLocation = "$(Join-Path $here 'weather.ico'),0"
$link.Description = 'Weather radar on the left screen, forecast on the right'
$link.Save()

# Runs only while you're signed in (it needs your screen), wakes the PC if it's asleep and
# wake timers are allowed, and catches up if the PC was off at that time.
$action = New-ScheduledTaskAction -Execute $wscript -Argument $launch -WorkingDirectory $here
$trigger = New-ScheduledTaskTrigger -Daily -At $At
$settings = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 4)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
    -Description "Opens the Weather Wall screens at $At." -Force | Out-Null

Write-Host "Done. Weather Wall opens every day at $At, and there's a Weather Wall shortcut on your Desktop."
Start-Sleep -Seconds 5
