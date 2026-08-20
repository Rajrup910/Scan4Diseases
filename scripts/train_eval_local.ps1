<#
.SYNOPSIS
    Train and evaluate one classifier locally, on the same committed split as the others,
    and produce the full report set. Local equivalent of the Colab notebooks.

.DESCRIPTION
    Runs the identical pipeline (same split_v1.csv, seed 42, two-stage transfer schedule,
    effective-number class weighting) so the result is directly comparable to ResNet-50 and
    ConvNeXt-Tiny. Writes checkpoints to ml\checkpoints\ and the report set to
    ml\results\eval_<arch>-on-HAM\.

    PREREQUISITE: Windows Smart App Control must be OFF, or scikit-learn's binaries are
    blocked and evaluation cannot run. The script checks this first and stops with
    instructions if scikit-learn still fails to import.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\train_eval_local.ps1 -Arch efficientnet_b0
    powershell -ExecutionPolicy Bypass -File scripts\train_eval_local.ps1 -Arch efficientnet_b0 -WithGradcam
#>
param(
    [ValidateSet('resnet50', 'efficientnet_b0', 'densenet121', 'efficientnet_b3', 'convnext_small')]
    [string]$Arch = 'convnext_small',
    # Lower this (e.g. 16) if a bigger model runs out of GPU memory. 0 = use the config default.
    [int]$BatchSize = 0,
    [switch]$WithGradcam
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$py = Join-Path $repo '.venv\Scripts\python.exe'
if (-not (Test-Path $py)) { throw "No virtual environment at $py. Run scripts\setup_env.ps1 first." }

# 1. Confirm scikit-learn loads (i.e. Smart App Control is really off) BEFORE spending
#    30+ minutes training only to crash at the evaluation step.
Write-Host "[1/4] Checking scikit-learn loads..." -ForegroundColor Cyan
& $py -c "import sklearn.metrics; from sklearn.metrics._pairwise_distances_reduction import ArgKmin; print('scikit-learn OK:', sklearn.__version__)"
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "scikit-learn is still blocked -- Smart App Control is on." -ForegroundColor Red
    Write-Host "Turn it off: Windows Security > App & browser control > Smart App Control > Off, then reboot." -ForegroundColor Yellow
    exit 1
}

# 2. Confirm the GPU + dataset are present.
Write-Host "[2/4] Checking GPU and dataset..." -ForegroundColor Cyan
& $py -c "import torch; print('CUDA:', torch.cuda.is_available(), '|', (torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU'))"
if (-not (Test-Path (Join-Path $repo 'data\ham10000\HAM10000_metadata.csv'))) {
    throw "HAM10000 not found under data\ham10000. The committed manifest points there."
}

# 3. Train (checkpoints -> ml\checkpoints\<arch>_best.pt, log -> ml\results\experiments.csv).
Write-Host "[3/4] Training $Arch (same split, seed 42, two-stage transfer)..." -ForegroundColor Cyan
$trainArgs = @('-m', 'ml.training.train', '--arch', $Arch)
if ($BatchSize -gt 0) { $trainArgs += @('--batch-size', "$BatchSize") }
& $py @trainArgs

# 4. Evaluate on the held-out TEST split with temperature calibration; write the report set.
$evalName = "eval_${Arch}-on-HAM"
$outDir = "ml/results/$evalName"
Write-Host "[4/4] Evaluating $Arch on the test split (+ calibration)..." -ForegroundColor Cyan
& $py -m ml.evaluation.evaluate --checkpoint "ml/checkpoints/${Arch}_best.pt" --calibrate --out-dir $outDir

if ($WithGradcam) {
    Write-Host "Generating Grad-CAM overlays..." -ForegroundColor Cyan
    try { & $py -m ml.explainability.generate_gradcam --checkpoint "ml/checkpoints/${Arch}_best.pt" }
    catch { Write-Host "Grad-CAM step failed (non-fatal): $_" -ForegroundColor Yellow }
}

# 5. Copy every artifact into the mponline phase 1 folder so the results live where you work.
$reviewMl = Join-Path (Split-Path $repo -Parent) 'mponline phase 1\01_ML_project_(full)'
Write-Host "Copying results into the review folder ($reviewMl)..." -ForegroundColor Cyan
robocopy "$repo\ml\checkpoints" "$reviewMl\checkpoints" "${Arch}_best.pt" "${Arch}_last.pt" /NFL /NDL /NJH /NJS /NP | Out-Null
robocopy "$repo\ml\results\$evalName" "$reviewMl\results\$evalName" /E /NFL /NDL /NJH /NJS /NP | Out-Null
robocopy "$repo\ml\results" "$reviewMl\results" "experiments.csv" "experiments.jsonl" /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Write-Host "  (copy reported an error)" -ForegroundColor Yellow } else { $global:LASTEXITCODE = 0 }

Write-Host ""
Write-Host "DONE. $Arch results are now in BOTH places:" -ForegroundColor Green
Write-Host "  Review folder : $reviewMl\results\$evalName\metrics.md   <- open this" -ForegroundColor Green
Write-Host "  Project copy  : $repo\ml\results\$evalName\" -ForegroundColor DarkGray
Write-Host "  Checkpoint    : $reviewMl\checkpoints\${Arch}_best.pt" -ForegroundColor DarkGray
