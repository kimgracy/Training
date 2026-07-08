[CmdletBinding()]
param(
    [string]$Video = "",
    [string]$Version = "",
    [string]$RunName = "",
    [string]$ModelPath = "",
    [string]$Split = "val",
    [int]$ImgSize = 960,
    [double]$Conf = 0.15,
    [string]$Name = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_video_utils.ps1")

$Root = Get-ProjectRoot

if ($PSBoundParameters.Count -eq 0) {
    Write-Host "Generate prediction images for one video project."
    Write-Host "Leave RunName and ModelPath blank to use the latest training run for the selected video/version."
    Write-Host ""

    $Video = Read-RequiredString -Name "Video"
    $VideoOnlyPaths = Get-VideoPaths -Root $Root -Video $Video
    $LatestYoloVersion = Get-LatestDirectoryName -Path $VideoOnlyPaths.YoloRoot
    $DefaultVersion = if ([string]::IsNullOrWhiteSpace($LatestYoloVersion)) { Get-DefaultVideoVersion } else { $LatestYoloVersion }
    $Version = Read-StringWithDefault -Name "Version" -Default $DefaultVersion
    $RunName = Read-StringWithDefault -Name "RunName" -Default $RunName
    $ModelPath = Read-StringWithDefault -Name "ModelPath" -Default $ModelPath
    $Split = Read-StringWithDefault -Name "Split" -Default $Split
    $ImgSize = Read-IntWithDefault -Name "ImgSize" -Default $ImgSize
    $Conf = Read-DoubleWithDefault -Name "Conf" -Default $Conf
    $Name = Read-StringWithDefault -Name "Name" -Default $Name
    Write-Host ""
}

if ([string]::IsNullOrWhiteSpace($Video)) {
    $Video = Read-RequiredString -Name "Video"
}
if ([string]::IsNullOrWhiteSpace($Version)) {
    $VideoOnlyPaths = Get-VideoPaths -Root $Root -Video $Video
    $Version = Get-LatestDirectoryName -Path $VideoOnlyPaths.YoloRoot
    if ([string]::IsNullOrWhiteSpace($Version)) {
        $Version = Read-StringWithDefault -Name "Version" -Default (Get-DefaultVideoVersion)
    }
    else {
        $Version = Read-StringWithDefault -Name "Version" -Default $Version
    }
}

$Paths = Get-VideoPaths -Root $Root -Video $Video -Version $Version
$Source = Join-Path $Paths.YoloDir "images\$Split"
$Project = $Paths.PredictRoot

$TrainingHint = ".\scripts\train_video.ps1 -Video `"$($Paths.Video)`" -Version `"$Version`""
$ModelSelection = Resolve-YoloModelSelection -TrainRoot $Paths.TrainRoot -RunName $RunName -ModelPath $ModelPath -TrainingHint $TrainingHint
$RunName = $ModelSelection.RunName
$ModelPath = $ModelSelection.ModelPath

if ([string]::IsNullOrWhiteSpace($Name)) {
    $ConfText = $Conf.ToString("0.###").Replace(".", "p")
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Name = "${RunName}_${Split}_img${ImgSize}_conf${ConfText}_$Timestamp"
}

if (-not (Test-Path -LiteralPath $Source)) {
    throw "Prediction source not found: $Source"
}

New-Item -ItemType Directory -Force -Path $Project | Out-Null
Write-Host "video          : $($Paths.Video)"
Write-Host "version        : $Version"
Write-Host "prediction run : $Name"
Write-Host "training run   : $RunName"
Write-Host "model          : $ModelPath"
Write-Host "source         : $Source"
Write-Host "output dir     : $(Join-Path $Project $Name)"

Push-Location $Root
try {
    Invoke-Yolo -Arguments @(
        "detect",
        "predict",
        "model=$ModelPath",
        "source=$Source",
        "imgsz=$ImgSize",
        "conf=$Conf",
        "save=True",
        "save_txt=True",
        "save_conf=True",
        "project=$Project",
        "name=$Name"
    )
}
finally {
    Pop-Location
}
