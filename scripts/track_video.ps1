[CmdletBinding()]
param(
    [string]$Video = "",
    [string]$Version = "",
    [string]$Dataset = "",
    [string]$RunName = "",
    [string]$ModelPath = "",
    [string]$Source = "",
    [int]$ImgSize = 960,
    [double]$Conf = 0.15,
    [double]$Iou = 0.7,
    [string]$Device = "0",
    [string]$Tracker = "bytetrack.yaml",
    [int]$VidStride = 1,
    [bool]$Show = $true,
    [bool]$Save = $true,
    [bool]$SaveTxt = $false,
    [bool]$SaveConf = $false,
    [string]$Name = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_video_utils.ps1")

function Resolve-TrackingSource {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Source,

        [AllowNull()]
        [pscustomobject]$VideoPaths = $null
    )

    if ($Source -match "^\d+$" -or $Source -match "^(rtsp|http|https)://") {
        return $Source
    }

    if ([System.IO.Path]::IsPathRooted($Source)) {
        return $Source
    }

    $Candidates = @()
    if ($null -ne $VideoPaths) {
        $Candidates += Join-Path $VideoPaths.SourceDir $Source
        $Candidates += Join-Path $VideoPaths.VideoRoot $Source
    }
    $Candidates += Join-Path $Root $Source

    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate) {
            return $Candidate
        }
    }

    return $Candidates[-1]
}

$Root = Get-ProjectRoot

if ($PSBoundParameters.Count -gt 0 -and [string]::IsNullOrWhiteSpace($Video) -and [string]::IsNullOrWhiteSpace($Dataset)) {
    Write-Host "Video is required for the video-centered tracking workflow."
    $Video = Read-RequiredString -Name "Video"
}

if ($PSBoundParameters.Count -eq 0) {
    Write-Host "Track particles for one video project."
    Write-Host "Leave RunName and ModelPath blank to use the latest training run for the selected video/version."
    Write-Host ""

    $Video = Read-RequiredString -Name "Video"
    $VideoOnlyPaths = Get-VideoPaths -Root $Root -Video $Video
    $LatestYoloVersion = Get-LatestDirectoryName -Path $VideoOnlyPaths.YoloRoot
    $DefaultVersion = if ([string]::IsNullOrWhiteSpace($LatestYoloVersion)) { Get-DefaultVideoVersion } else { $LatestYoloVersion }
    $Version = Read-StringWithDefault -Name "Version" -Default $DefaultVersion
    $RunName = Read-StringWithDefault -Name "RunName" -Default $RunName
    $ModelPath = Read-StringWithDefault -Name "ModelPath" -Default $ModelPath

    $InteractivePaths = Get-VideoPaths -Root $Root -Video $Video -Version $Version
    $DefaultSource = Get-VideoSourceFile -Paths $InteractivePaths
    $Source = Read-StringWithDefault -Name "Source" -Default $DefaultSource

    $ImgSize = Read-IntWithDefault -Name "ImgSize" -Default $ImgSize
    $Conf = Read-DoubleWithDefault -Name "Conf" -Default $Conf
    $Iou = Read-DoubleWithDefault -Name "Iou" -Default $Iou
    $Device = Read-StringWithDefault -Name "Device" -Default $Device
    $Tracker = Read-StringWithDefault -Name "Tracker" -Default $Tracker
    $VidStride = Read-IntWithDefault -Name "VidStride" -Default $VidStride
    $Show = Read-BoolWithDefault -Name "Show live window" -Default $Show
    $Save = Read-BoolWithDefault -Name "Save tracked video" -Default $Save
    $SaveTxt = Read-BoolWithDefault -Name "Save track labels as txt" -Default $SaveTxt
    $SaveConf = Read-BoolWithDefault -Name "Save confidence in txt labels" -Default $SaveConf
    $Name = Read-StringWithDefault -Name "Name" -Default $Name
    Write-Host ""
}

$UseVideoMode = -not [string]::IsNullOrWhiteSpace($Video)

if ($UseVideoMode) {
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
    $Project = $Paths.TrackRoot
    $TrainRoot = $Paths.TrainRoot
    $DatasetForName = $Paths.Dataset

    if ([string]::IsNullOrWhiteSpace($Source)) {
        $Source = Get-VideoSourceFile -Paths $Paths
        if ([string]::IsNullOrWhiteSpace($Source)) {
            throw "No source video found under: $($Paths.SourceDir). Use -Source to provide a video, webcam index, or stream URL."
        }
    }

    $ResolvedSource = Resolve-TrackingSource -Root $Root -Source $Source -VideoPaths $Paths
}
else {
    if ([string]::IsNullOrWhiteSpace($Dataset)) {
        $Dataset = Read-RequiredString -Name "Dataset"
    }

    if ([string]::IsNullOrWhiteSpace($Source)) {
        $Source = "Blood_PS particle_1.mp4"
    }

    $Project = Join-Path $Root "runs\track\$Dataset"
    $TrainRoot = Join-Path $Root "runs\train\$Dataset"
    $DatasetForName = $Dataset
    $ResolvedSource = Resolve-TrackingSource -Root $Root -Source $Source
}

if ($ResolvedSource -notmatch "^\d+$" -and $ResolvedSource -notmatch "^(rtsp|http|https)://" -and -not (Test-Path -LiteralPath $ResolvedSource)) {
    throw "Tracking source not found: $ResolvedSource"
}

$TrainingHint = if ($UseVideoMode) {
    ".\scripts\train_video.ps1 -Video `"$($Paths.Video)`" -Version `"$Version`""
}
else {
    ".\scripts\legacy\train.ps1 -Dataset `"$DatasetForName`""
}
$ModelSelection = Resolve-YoloModelSelection -TrainRoot $TrainRoot -RunName $RunName -ModelPath $ModelPath -TrainingHint $TrainingHint
$RunName = $ModelSelection.RunName
$ModelPath = $ModelSelection.ModelPath

if ([string]::IsNullOrWhiteSpace($Name)) {
    $ConfText = $Conf.ToString("0.###").Replace(".", "p")
    $SourceName = ConvertTo-YoloSafeName -Value ([System.IO.Path]::GetFileNameWithoutExtension($ResolvedSource))
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Name = "${RunName}_${SourceName}_track_img${ImgSize}_conf${ConfText}_$Timestamp"
}

New-Item -ItemType Directory -Force -Path $Project | Out-Null

if ($UseVideoMode) {
    Write-Host "video       : $($Paths.Video)"
    Write-Host "version     : $Version"
}
else {
    Write-Host "dataset     : $DatasetForName"
}
Write-Host "tracking run: $Name"
Write-Host "training run: $RunName"
Write-Host "model       : $ModelPath"
Write-Host "source      : $ResolvedSource"
Write-Host "tracker     : $Tracker"
Write-Host "output dir  : $(Join-Path $Project $Name)"

$ShowArg = ConvertTo-YoloBool -Value $Show
$SaveArg = ConvertTo-YoloBool -Value $Save
$SaveTxtArg = ConvertTo-YoloBool -Value $SaveTxt
$SaveConfArg = ConvertTo-YoloBool -Value $SaveConf

Push-Location $Root
try {
    Invoke-Yolo -Arguments @(
        "detect",
        "track",
        "model=$ModelPath",
        "source=$ResolvedSource",
        "imgsz=$ImgSize",
        "conf=$Conf",
        "iou=$Iou",
        "device=$Device",
        "tracker=$Tracker",
        "vid_stride=$VidStride",
        "show=$ShowArg",
        "save=$SaveArg",
        "save_txt=$SaveTxtArg",
        "save_conf=$SaveConfArg",
        "project=$Project",
        "name=$Name"
    )
}
finally {
    Pop-Location
}
