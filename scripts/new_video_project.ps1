[CmdletBinding()]
param(
    [string]$VideoFile = "",
    [string]$Video = "",
    [string]$Version = "",
    [string]$ClassConfig = "../../configs/classes/blood_ps.yaml",
    [switch]$NoCopy,
    [switch]$Overwrite
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_video_utils.ps1")

if ($PSBoundParameters.Count -eq 0) {
    Write-Host "Create a video-centered YOLO workspace."
    Write-Host "Press Enter to keep the value shown in brackets."
    Write-Host ""

    $VideoFile = Read-StringWithDefault -Name "VideoFile" -Default $VideoFile
    $DerivedVideo = Resolve-VideoName -Video $Video -VideoFile $VideoFile
    if ([string]::IsNullOrWhiteSpace($DerivedVideo)) {
        $Video = Read-RequiredString -Name "Video"
    }
    else {
        $Video = Read-StringWithDefault -Name "Video" -Default $DerivedVideo
    }
    $Version = Read-StringWithDefault -Name "Version" -Default (Get-DefaultVideoVersion)
    $ClassConfig = Read-StringWithDefault -Name "ClassConfig" -Default $ClassConfig

    if (-not [string]::IsNullOrWhiteSpace($VideoFile)) {
        $CopyVideo = Read-BoolWithDefault -Name "Copy video into this project" -Default (-not $NoCopy)
        $NoCopy = -not $CopyVideo
    }
    Write-Host ""
}

$Root = Get-ProjectRoot

if ([string]::IsNullOrWhiteSpace($Video) -and [string]::IsNullOrWhiteSpace($VideoFile)) {
    Write-Host "VideoFile or Video is required to create a video workspace."
    $VideoFile = Read-StringWithDefault -Name "VideoFile" -Default $VideoFile
    if ([string]::IsNullOrWhiteSpace($VideoFile)) {
        $Video = Read-RequiredString -Name "Video"
    }
}

$Video = Resolve-VideoName -Video $Video -VideoFile $VideoFile
if ([string]::IsNullOrWhiteSpace($Video)) {
    $Video = Read-RequiredString -Name "Video"
}
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = Read-StringWithDefault -Name "Version" -Default (Get-DefaultVideoVersion)
}
if ([string]::IsNullOrWhiteSpace($ClassConfig)) {
    $ClassConfig = Read-StringWithDefault -Name "ClassConfig" -Default "../../configs/classes/blood_ps.yaml"
}

$Paths = Get-VideoPaths -Root $Root -Video $Video -Version $Version
Initialize-VideoProjectFolders -Paths $Paths

$SourceVideo = ""
if (-not [string]::IsNullOrWhiteSpace($VideoFile)) {
    $ResolvedVideoFile = if ([System.IO.Path]::IsPathRooted($VideoFile)) {
        $VideoFile
    }
    else {
        Join-Path $Root $VideoFile
    }

    if (-not (Test-Path -LiteralPath $ResolvedVideoFile)) {
        throw "Video file not found: $ResolvedVideoFile"
    }

    if ($NoCopy) {
        $SourceVideo = (Resolve-Path -LiteralPath $ResolvedVideoFile).Path
    }
    else {
        $DestVideo = Join-Path $Paths.SourceDir ([System.IO.Path]::GetFileName($ResolvedVideoFile))
        $ResolvedVideoPath = (Resolve-Path -LiteralPath $ResolvedVideoFile).Path
        $ResolvedDestPath = if (Test-Path -LiteralPath $DestVideo) { (Resolve-Path -LiteralPath $DestVideo).Path } else { $DestVideo }
        if ($ResolvedVideoPath -eq $ResolvedDestPath) {
            $SourceVideo = $DestVideo
        }
        else {
            if ((Test-Path -LiteralPath $DestVideo) -and -not $Overwrite) {
                throw "Source video already exists. Use -Overwrite to replace it: $DestVideo"
            }
            Copy-Item -LiteralPath $ResolvedVideoFile -Destination $DestVideo -Force:$Overwrite
            $SourceVideo = $DestVideo
        }
    }
}
else {
    $SourceVideo = Get-VideoSourceFile -Paths $Paths
}

Write-VideoMetadata -Paths $Paths -SourceVideo $SourceVideo -ClassConfig $ClassConfig -Overwrite:$Overwrite

Write-Host "video project: $($Paths.VideoRoot)"
Write-Host "source dir   : $($Paths.SourceDir)"
Write-Host "export dir   : $($Paths.ExportDir)"
Write-Host "yolo dir     : $($Paths.YoloDir)"
Write-Host "runs dir     : $($Paths.RunsRoot)"
Write-Host "class config : $ClassConfig"
Write-Host "metadata     : $($Paths.MetadataPath)"
Write-Host ""
Write-Host "Next step: put the CVAT Ultralytics YOLO Detection 1.0 export into:"
Write-Host $Paths.ExportDir
