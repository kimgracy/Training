[CmdletBinding()]
param(
    [string]$Dataset = "0706_v1",
    [string]$RunName = "ps_yolo11s",
    [string]$ModelFamily = "ps_yolo11s",
    [string]$RegistryName = "",
    [string]$Status = "candidate"
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SourceRun = Join-Path $Root "runs\train\$Dataset\$RunName"

if ([string]::IsNullOrWhiteSpace($RegistryName)) {
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmm"
    $RegistryName = "${Timestamp}_${Dataset}"
}

$Dest = Join-Path $Root "models\registry\ps_particle\$ModelFamily\$RegistryName"
$Samples = Join-Path $Dest "sample_predictions"

if (-not (Test-Path -LiteralPath $SourceRun)) {
    throw "Training run not found: $SourceRun"
}
if (-not (Test-Path -LiteralPath (Join-Path $SourceRun "weights\best.pt"))) {
    throw "best.pt not found under: $SourceRun"
}

New-Item -ItemType Directory -Force -Path $Dest | Out-Null
New-Item -ItemType Directory -Force -Path $Samples | Out-Null

Copy-Item -LiteralPath (Join-Path $SourceRun "weights\best.pt") -Destination (Join-Path $Dest "best.pt") -Force

foreach ($FileName in @("args.yaml", "results.csv", "results.png", "confusion_matrix.png", "confusion_matrix_normalized.png")) {
    $SourceFile = Join-Path $SourceRun $FileName
    if (Test-Path -LiteralPath $SourceFile) {
        Copy-Item -LiteralPath $SourceFile -Destination (Join-Path $Dest $FileName) -Force
    }
}

$PredictRoot = Join-Path $Root "runs\predict\$Dataset"
if (Test-Path -LiteralPath $PredictRoot) {
    Get-ChildItem -Path $PredictRoot -Recurse -File -Include "*.jpg", "*.png" |
        Select-Object -First 8 |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Samples $_.Name) -Force
        }
}

$Metadata = @"
dataset: $Dataset
task: detect
class_names:
  0: ps_particle
model_family: $ModelFamily
source_run: runs/train/$Dataset/$RunName
weights: best.pt
status: $Status
promoted_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

$Metadata | Set-Content -Path (Join-Path $Dest "metadata.yaml") -Encoding UTF8

Write-Host "promoted: $Dest"
