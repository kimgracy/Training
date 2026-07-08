. (Join-Path $PSScriptRoot "_run_utils.ps1")

$script:VideoExtensions = @(".mp4", ".avi", ".mov", ".mkv", ".wmv", ".m4v")

function Get-ProjectRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-DefaultVideoVersion {
    $DatePart = Get-Date -Format "MMdd"
    return "${DatePart}_v1"
}

function Get-LatestDirectoryName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    $Latest = Get-ChildItem -LiteralPath $Path -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $Latest) {
        return ""
    }

    return $Latest.Name
}

function Resolve-VideoName {
    param(
        [AllowEmptyString()]
        [string]$Video = "",

        [AllowEmptyString()]
        [string]$VideoFile = ""
    )

    if (-not [string]::IsNullOrWhiteSpace($Video)) {
        return (ConvertTo-YoloSafeName -Value $Video).ToLowerInvariant()
    }

    if (-not [string]::IsNullOrWhiteSpace($VideoFile)) {
        $Stem = [System.IO.Path]::GetFileNameWithoutExtension($VideoFile)
        return (ConvertTo-YoloSafeName -Value $Stem).ToLowerInvariant()
    }

    return ""
}

function Get-VideoPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Video,

        [AllowEmptyString()]
        [string]$Version = ""
    )

    $SafeVideo = (ConvertTo-YoloSafeName -Value $Video).ToLowerInvariant()
    $VideoRoot = Join-Path $Root "videos\$SafeVideo"
    $DatasetName = if ([string]::IsNullOrWhiteSpace($Version)) {
        $SafeVideo
    }
    else {
        "${SafeVideo}_$(ConvertTo-YoloSafeName -Value $Version)"
    }

    [pscustomobject]@{
        Root = $Root
        Video = $SafeVideo
        Version = $Version
        Dataset = $DatasetName
        VideoRoot = $VideoRoot
        SourceDir = Join-Path $VideoRoot "source"
        ExportsRoot = Join-Path $VideoRoot "exports"
        ExportDir = if ([string]::IsNullOrWhiteSpace($Version)) { "" } else { Join-Path $VideoRoot "exports\$Version" }
        YoloRoot = Join-Path $VideoRoot "yolo"
        YoloDir = if ([string]::IsNullOrWhiteSpace($Version)) { "" } else { Join-Path $VideoRoot "yolo\$Version" }
        RunsRoot = Join-Path $VideoRoot "runs"
        TrainRoot = if ([string]::IsNullOrWhiteSpace($Version)) { "" } else { Join-Path $VideoRoot "runs\train\$Version" }
        ValRoot = if ([string]::IsNullOrWhiteSpace($Version)) { "" } else { Join-Path $VideoRoot "runs\val\$Version" }
        PredictRoot = if ([string]::IsNullOrWhiteSpace($Version)) { "" } else { Join-Path $VideoRoot "runs\predict\$Version" }
        TrackRoot = if ([string]::IsNullOrWhiteSpace($Version)) { "" } else { Join-Path $VideoRoot "runs\track\$Version" }
        MetadataPath = Join-Path $VideoRoot "video.yaml"
    }
}

function Initialize-VideoProjectFolders {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Paths
    )

    $Dirs = @(
        $Paths.VideoRoot,
        $Paths.SourceDir,
        $Paths.ExportsRoot,
        $Paths.YoloRoot,
        (Join-Path $Paths.RunsRoot "train"),
        (Join-Path $Paths.RunsRoot "val"),
        (Join-Path $Paths.RunsRoot "predict"),
        (Join-Path $Paths.RunsRoot "track")
    )

    foreach ($Dir in $Dirs) {
        New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($Paths.Version)) {
        New-Item -ItemType Directory -Force -Path $Paths.ExportDir | Out-Null
        New-Item -ItemType Directory -Force -Path $Paths.YoloDir | Out-Null
        New-Item -ItemType Directory -Force -Path $Paths.TrainRoot | Out-Null
        New-Item -ItemType Directory -Force -Path $Paths.ValRoot | Out-Null
        New-Item -ItemType Directory -Force -Path $Paths.PredictRoot | Out-Null
        New-Item -ItemType Directory -Force -Path $Paths.TrackRoot | Out-Null
    }
}

function Get-VideoSourceFile {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Paths
    )

    if (Test-Path -LiteralPath $Paths.SourceDir) {
        $Source = Get-ChildItem -LiteralPath $Paths.SourceDir -File |
            Where-Object { $script:VideoExtensions -contains $_.Extension.ToLowerInvariant() } |
            Sort-Object Name |
            Select-Object -First 1

        if ($null -ne $Source) {
            return $Source.FullName
        }
    }

    $MetadataSource = Get-VideoMetadataValue -MetadataPath $Paths.MetadataPath -Key "source_video"
    if ([string]::IsNullOrWhiteSpace($MetadataSource)) {
        return ""
    }

    if ([System.IO.Path]::IsPathRooted($MetadataSource)) {
        if (Test-Path -LiteralPath $MetadataSource) {
            return $MetadataSource
        }
        return ""
    }

    $Candidate = Join-Path $Paths.VideoRoot $MetadataSource
    if (Test-Path -LiteralPath $Candidate) {
        return $Candidate
    }

    return ""
}

function Get-VideoMetadataValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$MetadataPath,

        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    if (-not (Test-Path -LiteralPath $MetadataPath)) {
        return ""
    }

    foreach ($Line in Get-Content -LiteralPath $MetadataPath) {
        if ($Line -match "^\s*$([regex]::Escape($Key))\s*:\s*(.*)$") {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }

    return ""
}

function Write-VideoMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Paths,

        [AllowEmptyString()]
        [string]$SourceVideo = "",

        [string]$ClassConfig = "../../configs/classes/blood_ps.yaml",

        [switch]$Overwrite
    )

    if ((Test-Path -LiteralPath $Paths.MetadataPath) -and -not $Overwrite) {
        return
    }

    $RelativeSource = ""
    if (-not [string]::IsNullOrWhiteSpace($SourceVideo)) {
        try {
            $RelativeSource = [System.IO.Path]::GetRelativePath($Paths.VideoRoot, $SourceVideo).Replace("\", "/")
        }
        catch {
            $RelativeSource = $SourceVideo.Replace("\", "/")
        }
    }

    $Content = @(
        "video: $($Paths.Video)",
        "default_version: $($Paths.Version)",
        "source_video: $RelativeSource",
        "dataset_prefix: $($Paths.Video)",
        "class_config: $ClassConfig"
    )

    $Content | Set-Content -Path $Paths.MetadataPath -Encoding UTF8
}

function Get-YoloDatasetYaml {
    param(
        [Parameter(Mandatory = $true)]
        [string]$YoloDir
    )

    $DatasetYaml = Join-Path $YoloDir "dataset.yaml"
    if (Test-Path -LiteralPath $DatasetYaml) {
        return $DatasetYaml
    }

    $LegacyYaml = Join-Path $YoloDir "blood_ps.yaml"
    if (Test-Path -LiteralPath $LegacyYaml) {
        return $LegacyYaml
    }

    throw "Dataset YAML not found under: $YoloDir"
}

function Resolve-VideoClassConfig {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Paths,

        [AllowEmptyString()]
        [string]$ClassConfig = ""
    )

    $Value = $ClassConfig
    if ([string]::IsNullOrWhiteSpace($Value)) {
        $Value = Get-VideoMetadataValue -MetadataPath $Paths.MetadataPath -Key "class_config"
    }

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    if ([System.IO.Path]::IsPathRooted($Value)) {
        return $Value
    }

    $FromVideoRoot = Join-Path $Paths.VideoRoot $Value
    if (Test-Path -LiteralPath $FromVideoRoot) {
        return $FromVideoRoot
    }

    return (Join-Path $Paths.Root $Value)
}

function Read-Choice {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [string]$Default = "Y"
    )

    while ($true) {
        $Answer = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($Answer)) {
            $Answer = $Default
        }

        switch ($Answer.Trim().ToLowerInvariant()) {
            { $_ -in @("y", "yes") } { return $true }
            { $_ -in @("n", "no") } { return $false }
            default { Write-Host "Please enter Y or N." }
        }
    }
}

function Read-StringWithDefault {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowEmptyString()]
        [string]$Default = ""
    )

    if ([string]::IsNullOrEmpty($Default)) {
        $Value = Read-Host "$Name [blank]"
    }
    else {
        $Value = Read-Host "$Name [$Default]"
    }

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Default
    }

    return $Value.Trim()
}

function Read-RequiredString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    while ($true) {
        $Value = Read-Host "$Name [required]"
        if (-not [string]::IsNullOrWhiteSpace($Value)) {
            return $Value.Trim()
        }

        Write-Host "$Name is required."
    }
}

function Read-IntWithDefault {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [int]$Default
    )

    while ($true) {
        $Value = Read-Host "$Name [$Default]"
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $Default
        }

        $Parsed = 0
        if ([int]::TryParse($Value.Trim(), [ref]$Parsed)) {
            return $Parsed
        }

        Write-Host "Please enter an integer."
    }
}

function Read-DoubleWithDefault {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [double]$Default
    )

    while ($true) {
        $Value = Read-Host "$Name [$Default]"
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $Default
        }

        $Parsed = 0.0
        if ([double]::TryParse($Value.Trim(), [ref]$Parsed)) {
            return $Parsed
        }

        Write-Host "Please enter a number."
    }
}

function Read-BoolWithDefault {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [bool]$Default
    )

    $DefaultText = if ($Default) { "Y" } else { "N" }
    while ($true) {
        $Value = Read-Host "$Name [$DefaultText]"
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $Default
        }

        switch ($Value.Trim().ToLowerInvariant()) {
            { $_ -in @("y", "yes", "true", "1") } { return $true }
            { $_ -in @("n", "no", "false", "0") } { return $false }
            default { Write-Host "Please enter Y or N." }
        }
    }
}

function ConvertTo-YoloBool {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Value
    )

    if ($Value) {
        return "True"
    }
    return "False"
}

function Resolve-YoloModelSelection {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TrainRoot,

        [AllowEmptyString()]
        [string]$RunName = "",

        [AllowEmptyString()]
        [string]$ModelPath = "",

        [AllowEmptyString()]
        [string]$TrainingHint = ""
    )

    if ([string]::IsNullOrWhiteSpace($ModelPath)) {
        if ([string]::IsNullOrWhiteSpace($RunName)) {
            try {
                $LatestRun = Get-LatestYoloTrainRunFromPath -TrainRoot $TrainRoot
                $RunName = $LatestRun.Name
                $ModelPath = $LatestRun.BestWeight
            }
            catch {
                Write-Host ""
                Write-Host "[Notice] No trained model weights were found." -ForegroundColor Yellow
                Write-Host "Tracking, validation, and prediction require a trained weights\best.pt file." -ForegroundColor Yellow
                if (-not [string]::IsNullOrWhiteSpace($TrainingHint)) {
                    Write-Host ""
                    Write-Host "Run training first:"
                    Write-Host "  $TrainingHint"
                }
                Write-Host ""
                Write-Host "After training finishes, run this script again and it will use the latest best.pt automatically."
                Write-Host "If you already have a trained .pt file, enter its path below as ModelPath."
                Write-Host "If you do not have one yet, press Ctrl+C and run training first."
                $ModelPath = Read-RequiredString -Name "ModelPath"
                $RunName = Get-YoloRunNameFromModelPath -ModelPath $ModelPath
            }
        }
        else {
            $ModelPath = Join-Path $TrainRoot "$RunName\weights\best.pt"
        }
    }
    elseif ([string]::IsNullOrWhiteSpace($RunName)) {
        $RunName = Get-YoloRunNameFromModelPath -ModelPath $ModelPath
    }

    if (-not (Test-Path -LiteralPath $ModelPath)) {
        Write-Host ""
        Write-Host "[Notice] Model file not found: $ModelPath" -ForegroundColor Yellow
        Write-Host "Tracking, validation, and prediction require a trained weights\best.pt file." -ForegroundColor Yellow
        if (-not [string]::IsNullOrWhiteSpace($TrainingHint)) {
            Write-Host ""
            Write-Host "Run training first:"
            Write-Host "  $TrainingHint"
        }
        Write-Host ""
        Write-Host "After training finishes, run this script again and it will use the latest best.pt automatically."
        Write-Host "If you already have a trained .pt file, enter its path below as ModelPath."
        Write-Host "If you do not have one yet, press Ctrl+C and run training first."
        $ModelPath = Read-RequiredString -Name "ModelPath"
        if (-not (Test-Path -LiteralPath $ModelPath)) {
            throw "Model not found: $ModelPath"
        }
        $RunName = Get-YoloRunNameFromModelPath -ModelPath $ModelPath
    }

    return [pscustomobject]@{
        RunName = $RunName
        ModelPath = $ModelPath
    }
}
