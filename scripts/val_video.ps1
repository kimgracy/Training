[CmdletBinding()]
param(
    [string]$Video = "",
    [string]$Version = "",
    [string]$RunName = "",
    [string]$ModelPath = "",
    [int]$ImgSize = 960,
    [int]$Batch = 4,
    [string]$Device = "0",
    [string]$Split = "val",
    [string]$Name = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_video_utils.ps1")

$Root = Get-ProjectRoot

if ($PSBoundParameters.Count -eq 0) {
    Write-Host "Validate a YOLO model for one video project."
    Write-Host "Leave RunName and ModelPath blank to use the latest training run for the selected video/version."
    Write-Host ""

    $Video = Read-RequiredString -Name "Video"
    $VideoOnlyPaths = Get-VideoPaths -Root $Root -Video $Video
    $LatestYoloVersion = Get-LatestDirectoryName -Path $VideoOnlyPaths.YoloRoot
    $DefaultVersion = if ([string]::IsNullOrWhiteSpace($LatestYoloVersion)) { Get-DefaultVideoVersion } else { $LatestYoloVersion }
    $Version = Read-StringWithDefault -Name "Version" -Default $DefaultVersion
    $RunName = Read-StringWithDefault -Name "RunName" -Default $RunName
    $ModelPath = Read-StringWithDefault -Name "ModelPath" -Default $ModelPath
    $ImgSize = Read-IntWithDefault -Name "ImgSize" -Default $ImgSize
    $Batch = Read-IntWithDefault -Name "Batch" -Default $Batch
    $Device = Read-StringWithDefault -Name "Device" -Default $Device
    $Split = Read-StringWithDefault -Name "Split" -Default $Split
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
$Data = Get-YoloDatasetYaml -YoloDir $Paths.YoloDir
$Project = $Paths.ValRoot

$TrainingHint = ".\scripts\train_video.ps1 -Video `"$($Paths.Video)`" -Version `"$Version`""
$ModelSelection = Resolve-YoloModelSelection -TrainRoot $Paths.TrainRoot -RunName $RunName -ModelPath $ModelPath -TrainingHint $TrainingHint
$RunName = $ModelSelection.RunName
$ModelPath = $ModelSelection.ModelPath

if ([string]::IsNullOrWhiteSpace($Name)) {
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Name = "${RunName}_${Split}_img${ImgSize}_b${Batch}_$Timestamp"
}

New-Item -ItemType Directory -Force -Path $Project | Out-Null
Write-Host "video          : $($Paths.Video)"
Write-Host "version        : $Version"
Write-Host "validation run : $Name"
Write-Host "training run   : $RunName"
Write-Host "model          : $ModelPath"
Write-Host "output dir     : $(Join-Path $Project $Name)"

Push-Location $Root
try {
    Invoke-Yolo -Arguments @(
        "detect",
        "val",
        "model=$ModelPath",
        "data=$Data",
        "imgsz=$ImgSize",
        "batch=$Batch",
        "device=$Device",
        "split=$Split",
        "project=$Project",
        "name=$Name",
        "plots=True"
    )
}
finally {
    Pop-Location
}
