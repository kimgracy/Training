[CmdletBinding()]
param(
    [string]$Dataset = "0706_v1",
    [string]$RunName = "ps_yolo11s",
    [string]$ModelPath = "",
    [string]$Split = "val",
    [int]$ImgSize = 960,
    [double]$Conf = 0.15,
    [string]$Name = ""
)

$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Source = Join-Path $Root "data\yolo\$Dataset\images\$Split"
$Project = Join-Path $Root "runs\predict\$Dataset"

if ([string]::IsNullOrWhiteSpace($ModelPath)) {
    $ModelPath = Join-Path $Root "runs\train\$Dataset\$RunName\weights\best.pt"
}

if ([string]::IsNullOrWhiteSpace($Name)) {
    $ConfText = $Conf.ToString("0.###").Replace(".", "p")
    $Name = "${RunName}_${Split}_conf${ConfText}"
}

if (-not (Test-Path -LiteralPath $Source)) {
    throw "Prediction source not found: $Source"
}
if (-not (Test-Path -LiteralPath $ModelPath)) {
    throw "Model not found: $ModelPath"
}

New-Item -ItemType Directory -Force -Path $Project | Out-Null

Push-Location $Root
try {
    yolo detect predict `
        model="$ModelPath" `
        source="$Source" `
        imgsz=$ImgSize `
        conf=$Conf `
        save=True `
        save_txt=True `
        save_conf=True `
        project="$Project" `
        name="$Name"
}
finally {
    Pop-Location
}
