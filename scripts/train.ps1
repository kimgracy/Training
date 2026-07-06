[CmdletBinding()]
param(
    [string]$Dataset = "0706_v1",
    [string]$Model = "yolo11s.pt",
    [int]$ImgSize = 960,
    [int]$Epochs = 100,
    [int]$Batch = 4,
    [string]$Device = "0",
    [int]$Seed = 0,
    [string]$RunName = ""
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Data = Join-Path $Root "data\yolo\$Dataset\blood_ps.yaml"
$Project = Join-Path $Root "runs\train\$Dataset"

if (-not (Test-Path -LiteralPath $Data)) {
    throw "Dataset YAML not found: $Data"
}

if ([string]::IsNullOrWhiteSpace($RunName)) {
    $ModelStem = [System.IO.Path]::GetFileNameWithoutExtension($Model)
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmm"
    $RunName = "ps_${ModelStem}_img${ImgSize}_e${Epochs}_b${Batch}_s${Seed}_$Timestamp"
}

New-Item -ItemType Directory -Force -Path $Project | Out-Null

Push-Location $Root
try {
    yolo detect train `
        model=$Model `
        data="$Data" `
        imgsz=$ImgSize `
        epochs=$Epochs `
        batch=$Batch `
        device=$Device `
        seed=$Seed `
        project="$Project" `
        name="$RunName"
}
finally {
    Pop-Location
}
