[CmdletBinding()]
param(
    [string]$Video = "",
    [string]$Version = "",
    [double]$ValRatio = 0.2,
    [int]$Seed = 42,
    [string]$ClassName = "ps_particle",
    [string[]]$ClassNames = @(),
    [string]$ClassConfig = "",
    [switch]$KeepClassIds,
    [switch]$Overwrite,
    [string]$Python = "python"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_video_utils.ps1")

$UseKeepClassIds = $KeepClassIds.IsPresent
$UseOverwrite = $Overwrite.IsPresent
$Root = Get-ProjectRoot

if ($PSBoundParameters.Count -eq 0) {
    Write-Host "Prepare a video-centered YOLO dataset."
    Write-Host ""

    $Video = Read-RequiredString -Name "Video"
    $VideoOnlyPaths = Get-VideoPaths -Root $Root -Video $Video
    $LatestExportVersion = Get-LatestDirectoryName -Path $VideoOnlyPaths.ExportsRoot
    $DefaultVersion = if ([string]::IsNullOrWhiteSpace($LatestExportVersion)) { Get-DefaultVideoVersion } else { $LatestExportVersion }
    $Version = Read-StringWithDefault -Name "Version" -Default $DefaultVersion
    $PreviewPaths = Get-VideoPaths -Root $Root -Video $Video -Version $Version
    $PreviewClassConfig = Resolve-VideoClassConfig -Paths $PreviewPaths -ClassConfig $ClassConfig
    if ([string]::IsNullOrWhiteSpace($PreviewClassConfig)) {
        $PreviewClassConfig = "<none; using Class name below>"
    }

    Write-Host ""
    Write-Host "Default parameters for the remaining fields:"
    Write-Host "  Val ratio      : $ValRatio"
    Write-Host "  Seed           : $Seed"
    Write-Host "  Class name     : $ClassName"
    Write-Host "  Class config   : $PreviewClassConfig"
    Write-Host "  Keep class IDs : no (remap labels to class 0)"
    Write-Host "  Overwrite      : no"
    Write-Host ""

    $UseDefaults = Read-Choice -Prompt "Use these default parameters? [Y/n]" -Default "Y"
    if (-not $UseDefaults) {
        Write-Host ""
        Write-Host "Enter dataset preparation parameters. Press Enter to keep the value shown in brackets."
        $ValRatio = Read-DoubleWithDefault -Name "Val ratio" -Default $ValRatio
        $Seed = Read-IntWithDefault -Name "Seed" -Default $Seed
        $ClassConfig = Read-StringWithDefault -Name "ClassConfig" -Default $ClassConfig
        if ([string]::IsNullOrWhiteSpace($ClassConfig)) {
            $ClassNamesText = Read-StringWithDefault -Name "Class names, comma-separated" -Default $ClassName
            $ClassNames = @($ClassNamesText.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($ClassNames.Count -eq 1) {
                $ClassName = $ClassNames[0]
            }
        }
        $UseKeepClassIds = Read-BoolWithDefault -Name "Keep original class IDs instead of remapping to 0" -Default $UseKeepClassIds
        $UseOverwrite = Read-BoolWithDefault -Name "Overwrite output dataset if it already exists" -Default $UseOverwrite
    }
    Write-Host ""
}

if ([string]::IsNullOrWhiteSpace($Video)) {
    $Video = Read-RequiredString -Name "Video"
}
if ([string]::IsNullOrWhiteSpace($Version)) {
    $VideoOnlyPaths = Get-VideoPaths -Root $Root -Video $Video
    $Version = Get-LatestDirectoryName -Path $VideoOnlyPaths.ExportsRoot
    if ([string]::IsNullOrWhiteSpace($Version)) {
        $Version = Read-StringWithDefault -Name "Version" -Default (Get-DefaultVideoVersion)
    }
    else {
        $Version = Read-StringWithDefault -Name "Version" -Default $Version
    }
}
if ($ValRatio -le 0 -or $ValRatio -ge 1) {
    throw "ValRatio must be between 0 and 1."
}

$Paths = Get-VideoPaths -Root $Root -Video $Video -Version $Version
Initialize-VideoProjectFolders -Paths $Paths

$ResolvedClassConfig = Resolve-VideoClassConfig -Paths $Paths -ClassConfig $ClassConfig

if (-not (Test-Path -LiteralPath $Paths.ExportDir)) {
    throw "CVAT export directory not found: $($Paths.ExportDir)"
}

$OutputHasContent = (Test-Path -LiteralPath $Paths.YoloDir) -and $null -ne (Get-ChildItem -LiteralPath $Paths.YoloDir -Force | Select-Object -First 1)
if ($OutputHasContent -and -not $UseOverwrite) {
    Write-Host ""
    Write-Host "Output dataset already exists: $($Paths.YoloDir)"
    $UseOverwrite = Read-BoolWithDefault -Name "Overwrite existing prepared dataset" -Default $false
    if (-not $UseOverwrite) {
        throw "Output dataset already exists. Re-run and choose overwrite, or pass -Overwrite."
    }
}

$PrepareScript = Join-Path $PSScriptRoot "prepare_yolo_dataset.py"
$ArgsList = @(
    $PrepareScript,
    "--dataset", $Paths.Dataset,
    "--export-dir", $Paths.ExportDir,
    "--output-dir", $Paths.YoloDir,
    "--val-ratio", $ValRatio,
    "--seed", $Seed
)

if (-not [string]::IsNullOrWhiteSpace($ResolvedClassConfig)) {
    $ArgsList += @("--class-config", $ResolvedClassConfig)
}
elseif ($ClassNames.Count -gt 0) {
    $ArgsList += "--class-names"
    $ArgsList += $ClassNames
}
else {
    $ArgsList += @("--class-name", $ClassName)
}

if ($UseKeepClassIds) {
    $ArgsList += "--keep-class-ids"
}
if ($UseOverwrite) {
    $ArgsList += "--overwrite"
}

Write-Host "video      : $($Paths.Video)"
Write-Host "version    : $Version"
Write-Host "dataset    : $($Paths.Dataset)"
Write-Host "export dir : $($Paths.ExportDir)"
Write-Host "output dir : $($Paths.YoloDir)"
if (-not [string]::IsNullOrWhiteSpace($ResolvedClassConfig)) {
    Write-Host "class config: $ResolvedClassConfig"
}
elseif ($ClassNames.Count -gt 0) {
    Write-Host "class names : $($ClassNames -join ', ')"
}
else {
    Write-Host "class name  : $ClassName"
}

& $Python @ArgsList
if ($LASTEXITCODE -ne 0) {
    throw "prepare_yolo_dataset.py failed with exit code $LASTEXITCODE"
}

$MetadataClassConfig = if ([string]::IsNullOrWhiteSpace($ClassConfig)) { Get-VideoMetadataValue -MetadataPath $Paths.MetadataPath -Key "class_config" } else { $ClassConfig }
if ([string]::IsNullOrWhiteSpace($MetadataClassConfig) -and -not [string]::IsNullOrWhiteSpace($ResolvedClassConfig)) {
    $MetadataClassConfig = $ResolvedClassConfig
}
Write-VideoMetadata -Paths $Paths -SourceVideo (Get-VideoSourceFile -Paths $Paths) -ClassConfig $MetadataClassConfig
