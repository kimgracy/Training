[CmdletBinding()]
param(
    [string]$Dataset = "",
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
. (Join-Path $PSScriptRoot "..\_run_utils.ps1")

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

if ($PSBoundParameters.Count -eq 0) {
    Write-Host "No training parameters were provided."
    Write-Host ""
    Write-Host "Dataset has no default and must be entered before continuing."
    $Dataset = Read-RequiredString -Name "Dataset"
    Write-Host ""
    Write-Host "Selected dataset:"
    Write-Host "  Dataset : $Dataset"
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

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ([string]::IsNullOrWhiteSpace($Dataset)) {
    $Dataset = Read-RequiredString -Name "Dataset"
}
$Data = Join-Path $Root "data\yolo\$Dataset\blood_ps.yaml"
$Project = Join-Path $Root "runs\train\$Dataset"

if (-not (Test-Path -LiteralPath $Data)) {
    throw "Dataset YAML not found: $Data"
}

if ([string]::IsNullOrWhiteSpace($RunName)) {
    $RunName = New-YoloTrainRunName `
        -Dataset $Dataset `
        -Model $Model `
        -ImgSize $ImgSize `
        -Epochs $Epochs `
        -Batch $Batch `
        -Seed $Seed `
        -Tag $Tag
}

New-Item -ItemType Directory -Force -Path $Project | Out-Null
Write-Host "training run: $RunName"
Write-Host "output dir: $(Join-Path $Project $RunName)"

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
