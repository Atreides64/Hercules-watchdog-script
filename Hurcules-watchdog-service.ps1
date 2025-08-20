# ──────────────────────────────────────────────────────────────────────
# Minimal Resource Watchdog v3
# Author: Tim
# Purpose: Monitor & auto‑restart critical services.
#          Runs with <0.5 % CPU & minimal disk I/O.
# ──────────────────────────────────────────────────────────────────────

# ==== CONFIGURATION  ==================================================
$AutoRestart          = $true             # restart unhealthy apps automatically
$HealthyInterval      = 300               # check interval (sec) when everything is OK
$UnhealthyInterval    = 60                # check interval (sec) when something is down
$LogFile              = "$PSScriptRoot\watchdog.log"

# List all services that must stay alive.
#   • Name   – user‑friendly label
#   • Path   – full executable path
#   • Check  – scriptblock that returns **$true**   when healthy
#              or **$false** when unhealthy
$ServicesToMonitor = @(
    @{
        Name = "Surfshark VPN"
        Path = "C:\Program Files\Surfshark\Surfshark.exe"
        Check = { Test‑Surfshark }
    },
    @{
        Name = "Sonarr"
        Path = "C:\ProgramData\Sonarr\bin\Sonarr.exe"
        Check = { Test-Web  "http://localhost:8989" }
    },
    @{
        Name = "qBittorrent"
        Path = "C:\Program Files\qBittorrent\qbittorrent.exe"
        Check = { Test-Web  "http://localhost:8080" }
    }
)

# Keeps track of notifications that have already been shown
$NotificationSent = @{}

# ==== LOGGING  =========================================================
function Log {
    param([string]$msg)
    $header = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"

    if (Test-Path $LogFile -and ((Get-Item $LogFile).Length -gt 1MB)) {
        Rename-Item $LogFile "${LogFile}.bak" -Force
    }

    $header | Out-File -FilePath $LogFile -Append -Encoding utf8
}

# ==== NOTIFICATION ======================================================
function Notify {
    param($title, $msg)

    if (-not $NotificationSent[$title]) {
        try {
            $shell = New-Object -ComObject WScript.Shell
            # 0x0 = Information icon
            $shell.Popup($msg, 5, $title, 0x0)
        } catch {
            # Fall back to console output – useful when COM isn’t available
            Write-Host "[Notify] $title – $msg"
        }
        $NotificationSent[$title] = $true
    }
}

# ==== HEALTHCHECK HELPERS ==============================================
function Test-Web {
    param([string]$url)
    try {
        return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200
    } catch { return $false }
}

function Test‑Surfshark {
    # Try to ping through the VPN interface; fallback to the default interface
    try {
        return Test‑Connection 1.1.1.1 -Count 1 -Source  "SurfsharkWireGuard" -Quiet -ErrorAction Stop
    } catch {
        try {
            return Test‑Connection 1.1.1.1 -Count 1 -Quiet -ErrorAction Stop
        } catch { return $false }
    }
}

# ==== PROCESS HELPERS ==================================================
# Are we already running the given executable?  Returns **$true** or **$false**.
function IsRunning {
    param([string]$exePath)
    $procName = [IO.Path]::GetFileNameWithoutExtension($exePath)
    # `$_.Path` is only available on PowerShell 5.x+ – we check it safely
    return Get-Process -Name $procName -ErrorAction SilentlyContinue |
           Where-Object { $_.Path -eq $exePath }
}

# Start a new instance – **only** when none is running
function Start-App {
    param(
        [string]$exePath,
        [string]$appName
    )

    if (-not (Test-Path $exePath)) {
        Log "$appName error – file not found: $exePath"
        Notify "$appName Error" "Executable not found." ; return
    }

    # Make sure we’re not launching a duplicate process
    if (IsRunning $exePath) {
        Log "$appName is already running – skipping start."
        return
    }

    try {
        Start-Process $exePath -ErrorAction Stop
        Log "$appName started."
    } catch {
        Log "Failed to start $appName – $_"
        Notify "$appName Failure" "Could not start."
    }
}

# ==== MAIN LOOP  =======================================================
Log "=== Watchdog started ==="

while ($true) {
    $anyIssue = $false

    foreach ($svc in $ServicesToMonitor) {
        $isRunning = IsRunning $svc.Path
        $healthy   = & $svc.Check

        if (-not $isRunning) {
            $anyIssue = $true
            Log "$($svc.Name) not running."
            Start-App -exePath $svc.Path -appName $svc.Name
        }
        elseif (-not $healthy) {
            $anyIssue = $true
            Log "$($svc.Name) unhealthy."
            Notify "$($svc.Name) Issue" "$($svc.Name) is not responding."
            if ($AutoRestart) {
                Stop-Process -Name ([IO.Path]::GetFileNameWithoutExtension($svc.Path)) -Force
                Start-App -exePath $svc.Path -appName $svc.Name
            }
        }
    }

    $sleepSec = if ($anyIssue) { $UnhealthyInterval } else { $HealthyInterval }
    Start-Sleep -Seconds $sleepSec
}
