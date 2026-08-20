<#
.SYNOPSIS
    Re-establish the phone -> laptop backend tunnel for the Scan4Disease app.

.DESCRIPTION
    The installed debug APK talks to http://127.0.0.1:8000. On a phone, 127.0.0.1 is the
    PHONE, so it only reaches the laptop's backend through an adb reverse tunnel. That
    tunnel is dropped whenever the phone sleeps, wireless-debugging disconnects, the adb
    server restarts, or the laptop reboots -- which is why "Connection refused" keeps
    coming back. Run this to put the tunnel back. No app rebuild needed.

    Prerequisite: the phone is paired with adb (USB debugging, or wireless debugging on the
    same Wi-Fi) and the backend is running (scripts\run_backend.ps1).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\connect_phone.ps1
#>
param(
    # Port the phone/app talks to (the app is hard-coded to 127.0.0.1:8000, so keep this 8000).
    [int]$Port = 8000,
    # Port the backend actually listens on, on the laptop. Defaults to $Port. Use this when the
    # normal 8000 is occupied by a stale/hung process and you started the backend on e.g. 8001.
    [int]$BackendPort = 0
)
if ($BackendPort -le 0) { $BackendPort = $Port }

$ErrorActionPreference = "Stop"

$adb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    $onPath = Get-Command adb -ErrorAction SilentlyContinue
    if ($onPath) { $adb = $onPath.Source } else {
        throw "adb not found. Install Android platform-tools or add adb to PATH."
    }
}

Write-Host "Using adb: $adb" -ForegroundColor DarkGray

$devices = & $adb devices | Select-String "`tdevice$"
if (-not $devices) {
    Write-Host "No device connected." -ForegroundColor Red
    Write-Host "  USB:      plug in the phone, enable USB debugging, accept the prompt." -ForegroundColor Yellow
    Write-Host "  Wireless: Settings > Developer options > Wireless debugging, then" -ForegroundColor Yellow
    Write-Host "            '$adb pair <ip:port>' once, then '$adb connect <ip:port>'." -ForegroundColor Yellow
    exit 1
}
Write-Host "Device(s) connected:" -ForegroundColor Green
& $adb devices | Select-Object -Skip 1 | Where-Object { $_.Trim() }

# Reverse tunnel: phone's 127.0.0.1:$Port -> laptop's 127.0.0.1:$BackendPort.
# Removing a non-existent listener makes adb write to stderr; under ErrorActionPreference=Stop
# that would abort the script, so run the cleanup with errors suppressed and never fatal.
try { & $adb reverse --remove tcp:$Port 2>$null | Out-Null } catch { }
& $adb reverse tcp:$Port tcp:$BackendPort | Out-Null
Write-Host "Reverse tunnel set: phone 127.0.0.1:$Port -> laptop 127.0.0.1:$BackendPort" -ForegroundColor Green

# Prove the phone can now reach the backend through the tunnel.
$fromPhone = & $adb shell "curl -s -m 5 http://127.0.0.1:$Port/health" 2>$null
if ($fromPhone -match '"model_loaded":true') {
    Write-Host "Verified from the phone: backend is reachable and a model is loaded." -ForegroundColor Green
    Write-Host "You can log in / screen now." -ForegroundColor Cyan
} elseif ($fromPhone -match '"status":"ok"') {
    Write-Host "Phone reached the backend (stub/degraded model): $fromPhone" -ForegroundColor Yellow
} else {
    Write-Host "Tunnel is set, but the phone could not reach the backend." -ForegroundColor Red
    Write-Host "Is the backend running?  ->  scripts\run_backend.ps1" -ForegroundColor Yellow
    Write-Host "Device response: $fromPhone" -ForegroundColor DarkGray
    exit 1
}
