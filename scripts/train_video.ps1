[CmdletBinding()]
param(
    [string]$Video = "",
    [string]$Version = "",
    [string]$Model = "yolo11s.pt",
    [int]$ImgSize = 960,
    [int]$Epochs = 100,
    [int]$Batch = 4,
    [string]$Device = "0",
    [int]$Seed = 0,
    [string]$Tag = "",
    [string]$RunName = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_video_utils.ps1")

$Root = Get-ProjectRoot

if ($PSBoundParameters.Count -eq 0) {
    Write-Host "Train a YOLO model for one video project."
    Write-Host ""

    $Video = Read-RequiredString -Name "Video"
    $VideoOnlyPaths = Get-VideoPaths -Root $Root -Video $Video
    $LatestYoloVersion = Get-LatestDirectoryName -Path $VideoOnlyPaths.YoloRoot
    $DefaultVersion = if ([string]::IsNullOrWhiteSpace($LatestYoloVersion)) { Get-DefaultVideoVersion } else { $LatestYoloVersion }
    $Version = Read-StringWithDefault -Name "Version" -Default $DefaultVersion

    Write-Host ""
    Write-Host "Default parameters for the remaining fields:"
    Write-Host "  Model   : $Model"
    Write-Host "  ImgSize : $ImgSize"
    Write-Host "  Epochs  : $Epochs"
    Write-Host "  Batch   : $Batch"
    Write-Host "  Device  : $Device"
    Write-Host "  Seed    : $Seed"
    Write-Host "  Tag     : <blank>"
    Write-Host "  RunName : auto-generated"
    Write-Host ""

    $UseDefaults = Read-Choice -Prompt "Use these default parameters? [Y/n]" -Default "Y"
    if (-not $UseDefaults) {
        Write-Host ""
        Write-Host "Enter training parameters. Press Enter to keep the value shown in brackets."
        $Model = Read-StringWithDefault -Name "Model" -Default $Model
        $ImgSize = Read-IntWithDefault -Name "ImgSize" -Default $ImgSize
        $Epochs = Read-IntWithDefault -Name "Epochs" -Default $Epochs
        $Batch = Read-IntWithDefault -Name "Batch" -Default $Batch
        $Device = Read-StringWithDefault -Name "Device" -Default $Device
        $Seed = Read-IntWithDefault -Name "Seed" -Default $Seed
        $Tag = Read-StringWithDefault -Name "Tag" -Default $Tag
        $RunName = Read-StringWithDefault -Name "RunName" -Default $RunName
    }
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
$Project = $Paths.TrainRoot

if ([string]::IsNullOrWhiteSpace($RunName)) {
    $RunName = New-YoloTrainRunName `
        -Dataset $Paths.Dataset `
        -Model $Model `
        -ImgSize $ImgSize `
        -Epochs $Epochs `
        -Batch $Batch `
        -Seed $Seed `
        -Tag $Tag
}

New-Item -ItemType Directory -Force -Path $Project | Out-Null
Write-Host "video       : $($Paths.Video)"
Write-Host "version     : $Version"
Write-Host "dataset     : $($Paths.Dataset)"
Write-Host "training run: $RunName"
Write-Host "data yaml   : $Data"
Write-Host "output dir  : $(Join-Path $Project $RunName)"

Push-Location $Root
try {
    Invoke-Yolo -Arguments @(
        "detect",
        "train",
        "model=$Model",
        "data=$Data",
        "imgsz=$ImgSize",
        "epochs=$Epochs",
        "batch=$Batch",
        "device=$Device",
        "seed=$Seed",
        "project=$Project",
        "name=$RunName"
    )
}
finally {
    Pop-Location
}

$RunManifest = Join-Path $Project "latest_run.txt"
$RunName | Set-Content -Path $RunManifest -Encoding UTF8
Write-Host "latest run recorded: $RunManifest"
