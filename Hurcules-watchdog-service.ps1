# Minimal Resource Watchdog v2
# Author: Tim
# Purpose: Monitor and restart critical services with ultra-low CPU and disk use

# ==== CONFIGURATION ====
$AutoRestart = $true
$HealthyInterval = 300   # seconds when all services OK
$UnhealthyInterval = 60  # seconds when something's down
$LogFile = "$PSScriptRoot\watchdog.log"

$ServicesToMonitor = @(
    @{ Name="Surfshark VPN"; Path="C:\Program Files\Surfshark\Surfshark.exe"; Check={ Test-Surfshark } },
    @{ Name="Sonarr"; Path="C:\ProgramData\Sonarr\bin\Sonarr.exe"; Check={ Test-Web "http://localhost:8989" } },
    @{ Name="qBittorrent"; Path="C:\Program Files\qBittorrent\qbittorrent.exe"; Check={ Test-Web "http://localhost:8080" } }
)

$NotificationSent = @{}

# ==== FUNCTIONS ====
function Log {
    param([string]$msg)
    if ((Test-Path $LogFile) -and ((Get-Item $LogFile).Length -gt 1MB)) {
        Rename-Item $LogFile "$LogFile.bak" -Force
    }
    "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) | $msg" |
        Out-File -FilePath $LogFile -Append -Encoding utf8
}

function Notify {
    param($title, $msg)
    if (-not $NotificationSent[$title]) {
        try {
            $balloon = New-Object -ComObject WScript.Shell
            $balloon.Popup($msg, 5, $title, 0x0)
        } catch {
            Write-Host "[Notify] $title - $msg"
        }
        $NotificationSent[$title] = $true
    }
}

function Test-Web {
    param([string]$url)
    try {
        (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200
    } catch { $false }
}

function Test-Surfshark {
    try {
        Test-Connection 1.1.1.1 -Count 1 -Source "SurfsharkWireGuard" -Quiet -ErrorAction Stop
    } catch {
        try {
            Test-Connection 1.1.1.1 -Count 1 -Quiet -ErrorAction Stop
        } catch { $false }
    }
}

function IsRunning {
    param($exePath)
    $procName = [System.IO.Path]::GetFileNameWithoutExtension($exePath)
    Get-Process -Name $procName -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $exePath }
}

function Start-App {
    param($exePath, $name)
    if (-not (Test-Path $exePath)) {
        Log "$name path invalid: $exePath"
        Notify "$name Error" "Path not found."
        return
    }
    try {
        Start-Process $exePath -ErrorAction Stop
        Log "$name started."
    } catch {
        Log "Failed to start $name: $_"
        Notify "$name Failure" "Could not start."
    }
}

# ==== MAIN LOOP ====
Log "=== Watchdog started ==="
while ($true) {
    $somethingUnhealthy = $false

    foreach ($svc in $ServicesToMonitor) {
        $running = IsRunning $svc.Path
        $healthy = & $svc.Check

        if (-not $running) {
            $somethingUnhealthy = $true
            Log "$($svc.Name) not running."
            Start-App $svc.Path $svc.Name
        }
        elseif (-not $healthy) {
            $somethingUnhealthy = $true
            Log "$($svc.Name) unhealthy."
            Notify "$($svc.Name) Issue" "$($svc.Name) is not responding."
            if ($AutoRestart) {
                Stop-Process -Name ([IO.Path]::GetFileNameWithoutExtension($svc.Path)) -Force
                Start-App $svc.Path $svc.Name
            }
        }
    }

    Start-Sleep -Seconds ($(if ($somethingUnhealthy) { $UnhealthyInterval } else { $HealthyInterval }))
}
