# Weather Wall: radar on the left monitor, forecast on the right, both full screen.
# Started each morning by the "Weather Wall" scheduled task (see install.ps1), or any time from the Desktop shortcut.
#   - Opened before the close time: screens stay on, then everything closes at the close time.
#   - Opened after it: screens stay on for 2 hours; the windows stay until you close them (Esc).

$closeTime = '10:30'   # 24-hour clock

$ErrorActionPreference = 'SilentlyContinue'
$self = $MyInvocation.MyCommand.Path
$here = Split-Path -Parent $self
# Browser profiles live in AppData, not next to these files: thousands of small files that change
# constantly, which would churn a synced folder like Google Drive.
$profiles = Join-Path $env:LOCALAPPDATA 'WeatherWall'
$closeAt = (Get-Date).Date + [TimeSpan]$closeTime

function Get-PanelProcesses {
    Get-CimInstance Win32_Process -Filter "Name='chrome.exe' OR Name='msedge.exe'" |
        Where-Object { $_.CommandLine -like "*AppData\Local\WeatherWall\profile-*" }
}

function Close-Panels {
    Get-PanelProcesses | Where-Object { $_.CommandLine -notlike '*--type=*' } |
        ForEach-Object { taskkill.exe /F /T /PID $_.ProcessId | Out-Null }
    # Wait until the browser lets go of each profile. A window opened before then just vanishes.
    foreach ($name in 'radar', 'forecast') {
        $lock = Join-Path $profiles "profile-$name\lockfile"
        for ($i = 0; $i -lt 20 -and (Test-Path $lock); $i++) {
            Remove-Item $lock -Force
            if (Test-Path $lock) { Start-Sleep -Milliseconds 500 }
        }
    }
}

# An earlier launcher may still be running its 10:30 timer; this one takes over.
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine.Contains($self) -and $_.ProcessId -ne $PID } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Close-Panels

$browser = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

function Open-Panel($name, $screen) {
    $profileDir = Join-Path $profiles "profile-$name"
    # Skip Chrome's "restore pages?" prompt after a forced close.
    $prefs = Join-Path $profileDir 'Default\Preferences'
    if (Test-Path $prefs) {
        $text = [IO.File]::ReadAllText($prefs) -replace '"exit_type":"Crashed"', '"exit_type":"Normal"'
        [IO.File]::WriteAllText($prefs, $text, (New-Object Text.UTF8Encoding $false))
    }
    $url = ([Uri](Join-Path $here "$name.html")).AbsoluteUri
    # Aim at the middle of the monitor; kiosk mode then fills that monitor.
    $x = $screen.Bounds.X + [int]($screen.Bounds.Width / 2) - 200
    $y = $screen.Bounds.Y + [int]($screen.Bounds.Height / 2) - 150
    Start-Process $browser -ArgumentList @(
        "--user-data-dir=`"$profileDir`"",
        '--no-first-run', '--no-default-browser-check', '--hide-crash-restore-bubble',
        "--app=$url", "--window-position=$x,$y", '--window-size=400,300', '--kiosk'
    )
}

Add-Type -AssemblyName System.Windows.Forms
$screens = [System.Windows.Forms.Screen]::AllScreens | Sort-Object { $_.Bounds.X }
Open-Panel 'radar' $screens[0]
Open-Panel 'forecast' $screens[-1]

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class WeatherWallNative {
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, UIntPtr extra);
    [DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);
}
"@
# Turn the screens on (a one-pixel mouse nudge counts as activity) and keep them on.
[WeatherWallNative]::mouse_event(1, 1, 0, 0, [UIntPtr]::Zero)
[WeatherWallNative]::mouse_event(1, -1, 0, 0, [UIntPtr]::Zero)
[WeatherWallNative]::SetThreadExecutionState([uint32]2147483651) | Out-Null  # CONTINUOUS | SYSTEM | DISPLAY

$autoClose = (Get-Date) -lt $closeAt
$until = if ($autoClose) { $closeAt } else { (Get-Date).AddHours(2) }
Start-Sleep -Seconds 20
while ((Get-Date) -lt $until) {
    if (-not (Get-PanelProcesses)) { exit }   # you closed both windows yourself
    Start-Sleep -Seconds 30
}
if ($autoClose) { Close-Panels }
