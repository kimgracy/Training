[CmdletBinding()]
param(
    [string]$Dataset = "",
    [string]$RunName = "",
    [string]$ModelPath = "",
    [int]$ImgSize = 960,
    [int]$Batch = 4,
    [string]$Device = "0",
    [string]$Split = "val",
    [string]$Name = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "_run_utils.ps1")

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
    Write-Host "Enter validation parameters. Press Enter to keep the value shown in brackets."
    Write-Host "Leave RunName and ModelPath blank to use the latest training run for the selected dataset."
    Write-Host ""

    $Dataset = Read-RequiredString -Name "Dataset"
    $RunName = Read-StringWithDefault -Name "RunName" -Default $RunName
    $ModelPath = Read-StringWithDefault -Name "ModelPath" -Default $ModelPath
    $ImgSize = Read-IntWithDefault -Name "ImgSize" -Default $ImgSize
    $Batch = Read-IntWithDefault -Name "Batch" -Default $Batch
    $Device = Read-StringWithDefault -Name "Device" -Default $Device
    $Split = Read-StringWithDefault -Name "Split" -Default $Split
    $Name = Read-StringWithDefault -Name "Name" -Default $Name
    Write-Host ""
}

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($Dataset)) {
    throw "Dataset is required. Use -Dataset or run interactively and enter a dataset value."
}
$Data = Join-Path $Root "data\yolo\$Dataset\blood_ps.yaml"
$Project = Join-Path $Root "runs\val\$Dataset"

if ([string]::IsNullOrWhiteSpace($ModelPath)) {
    if ([string]::IsNullOrWhiteSpace($RunName)) {
        $LatestRun = Get-LatestYoloTrainRun -Root $Root -Dataset $Dataset
        $RunName = $LatestRun.Name
        $ModelPath = $LatestRun.BestWeight
    }
    else {
        $ModelPath = Join-Path $Root "runs\train\$Dataset\$RunName\weights\best.pt"
    }
}
elseif ([string]::IsNullOrWhiteSpace($RunName)) {
    $RunName = Get-YoloRunNameFromModelPath -ModelPath $ModelPath
}

if ([string]::IsNullOrWhiteSpace($Name)) {
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Name = "${RunName}_${Split}_img${ImgSize}_b${Batch}_$Timestamp"
}

if (-not (Test-Path -LiteralPath $Data)) {
    throw "Dataset YAML not found: $Data"
}
if (-not (Test-Path -LiteralPath $ModelPath)) {
    throw "Model not found: $ModelPath"
}

New-Item -ItemType Directory -Force -Path $Project | Out-Null
Write-Host "validation run: $Name"
Write-Host "source training run: $RunName"
Write-Host "model: $ModelPath"

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

    if ($LASTEXITCODE -ne 0) {
        throw "yolo detect val failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}
