<#
.SYNOPSIS
    One-time Python environment setup for Scan4Disease.

.DESCRIPTION
    Creates a Python 3.12 virtual environment and installs PyTorch from the CUDA
    index plus the ML and backend requirements.

    Two machine-specific facts drive this script:
      1. The default `python` on PATH is 3.14, for which PyTorch publishes no wheels.
         We explicitly select 3.12 via the py launcher.
      2. The GPU is an RTX 5050 (Blackwell, compute capability 12.0 / sm_120).
         Default PyPI torch wheels do not ship sm_120 kernels, so we install from
         the CUDA index instead.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\setup_env.ps1
    powershell -ExecutionPolicy Bypass -File scripts\setup_env.ps1 -CudaIndex cu129
    powershell -ExecutionPolicy Bypass -File scripts\setup_env.ps1 -Cpu
#>
param(
    # CUDA wheel index to use. Check https://pytorch.org/get-started/locally/ for the
    # newest one; anything cu128 or later carries sm_120 kernels.
    [string]$CudaIndex = "cu128",
    # Install CPU-only wheels instead (for a deployment box with no GPU).
    [switch]$Cpu,
    [string]$PythonVersion = "3.12"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

Write-Host "=== Scan4Disease environment setup ===" -ForegroundColor Cyan
Write-Host "Repo: $repo"

# --- 1. Locate the right interpreter -----------------------------------------
$launcher = Get-Command py -ErrorAction SilentlyContinue
if (-not $launcher) { throw "The 'py' launcher was not found. Install Python $PythonVersion from python.org." }

# Ask the launcher to actually start the interpreter. Parsing `py -0p` output is
# fragile -- and note `-match` on an array filters instead of returning a boolean,
# which is exactly the trap that broke the first version of this check.
& py "-$PythonVersion" -c "import sys; print(sys.version)"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Interpreters the py launcher knows about:" -ForegroundColor Yellow
    Write-Host ((& py -0p) -join [Environment]::NewLine)
    throw "Python $PythonVersion could not be launched. Install it (winget install Python.Python.3.12) and re-run."
}
Write-Host "Using Python $PythonVersion" -ForegroundColor Green

# --- 2. Create the venv -------------------------------------------------------
if (Test-Path "$repo\.venv") {
    Write-Host ".venv already exists - reusing it. Delete it to start clean." -ForegroundColor Yellow
} else {
    & py "-$PythonVersion" -m venv "$repo\.venv"
    Write-Host "Created .venv" -ForegroundColor Green
}

$vpy = "$repo\.venv\Scripts\python.exe"
& $vpy -m pip install --upgrade pip setuptools wheel

# --- 3. PyTorch, from the correct index --------------------------------------
if ($Cpu) {
    $index = "https://download.pytorch.org/whl/cpu"
    Write-Host "Installing CPU-only PyTorch" -ForegroundColor Yellow
} else {
    $index = "https://download.pytorch.org/whl/$CudaIndex"
    Write-Host "Installing CUDA PyTorch from $CudaIndex" -ForegroundColor Green
}
& $vpy -m pip install torch torchvision --index-url $index

# --- 4. Project requirements --------------------------------------------------
& $vpy -m pip install -r "$repo\ml\requirements.txt"
& $vpy -m pip install -r "$repo\backend\requirements.txt"

# --- 5. Verify ----------------------------------------------------------------
Write-Host "`n=== Verification ===" -ForegroundColor Cyan
& $vpy "$repo\scripts\verify_env.py"

Write-Host "`nDone. Activate with:" -ForegroundColor Cyan
Write-Host "    .\.venv\Scripts\Activate.ps1"
