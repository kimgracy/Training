[CmdletBinding()]
param(
    [string]$Dataset = "0706_v1",
    [string]$RunName = "ps_yolo11s",
    [string]$ModelPath = "",
    [int]$ImgSize = 960,
    [int]$Batch = 4,
    [string]$Device = "0",
    [string]$Split = "val",
    [string]$Name = ""
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Data = Join-Path $Root "data\yolo\$Dataset\blood_ps.yaml"
$Project = Join-Path $Root "runs\val\$Dataset"

if ([string]::IsNullOrWhiteSpace($ModelPath)) {
    $ModelPath = Join-Path $Root "runs\train\$Dataset\$RunName\weights\best.pt"
}

if ([string]::IsNullOrWhiteSpace($Name)) {
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmm"
    $Name = "${RunName}_${Split}_$Timestamp"
}

if (-not (Test-Path -LiteralPath $Data)) {
    throw "Dataset YAML not found: $Data"
}
if (-not (Test-Path -LiteralPath $ModelPath)) {
    throw "Model not found: $ModelPath"
}

New-Item -ItemType Directory -Force -Path $Project | Out-Null

Push-Location $Root
try {
    yolo detect val `
        model="$ModelPath" `
        data="$Data" `
        imgsz=$ImgSize `
        batch=$Batch `
        device=$Device `
        split=$Split `
        project="$Project" `
        name="$Name" `
        plots=True
}
finally {
    Pop-Location
}
