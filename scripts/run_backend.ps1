<#
.SYNOPSIS
    Start the FastAPI backend.

.DESCRIPTION
    Wraps uvicorn with the repository root as the working directory, and prints the LAN
    address a phone on the same WiFi should use.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\run_backend.ps1
    powershell -ExecutionPolicy Bypass -File scripts\run_backend.ps1 -Stub
    powershell -ExecutionPolicy Bypass -File scripts\run_backend.ps1 -Port 8080 -NoReload
#>
param(
    [int]$Port = 8000,
    # Serve synthetic predictions when no checkpoint exists. UI development only.
    [switch]$Stub,
    [switch]$NoReload
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$python = "$repo\.venv\Scripts\python.exe"
if (-not (Test-Path $python)) {
    throw "No virtual environment found. Run scripts\setup_env.ps1 first."
}

if ($Stub) {
    $env:ALLOW_STUB_MODEL = "true"
    Write-Host "STUB MODE: predictions are synthetic. Never use this for a demo." -ForegroundColor Yellow
}

$lan = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixOrigin -ne 'WellKnown' } |
        Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "  docs      http://localhost:$Port/docs" -ForegroundColor Cyan
Write-Host "  health    http://localhost:$Port/health" -ForegroundColor Cyan
if ($lan) {
    Write-Host "  phone     http://${lan}:$Port   (same WiFi; allow the port through the firewall)" -ForegroundColor Cyan
}
Write-Host ""

$arguments = @("-m", "uvicorn", "backend.app.main:app", "--host", "0.0.0.0", "--port", "$Port")
if (-not $NoReload) { $arguments += "--reload" }

& $python @arguments
