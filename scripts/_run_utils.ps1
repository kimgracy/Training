function ConvertTo-YoloSafeName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $Safe = $Value.Trim() -replace "[^A-Za-z0-9._-]+", "_"
    $Safe = $Safe.Trim("_", ".", "-")
    if ([string]::IsNullOrWhiteSpace($Safe)) {
        return "unnamed"
    }
    return $Safe
}

function Get-YoloModelStem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Model
    )

    $FileName = [System.IO.Path]::GetFileName($Model)
    $Stem = [System.IO.Path]::GetFileNameWithoutExtension($FileName)
    return ConvertTo-YoloSafeName -Value $Stem
}

function New-YoloTrainRunName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Dataset,

        [Parameter(Mandatory = $true)]
        [string]$Model,

        [Parameter(Mandatory = $true)]
        [int]$ImgSize,

        [Parameter(Mandatory = $true)]
        [int]$Epochs,

        [Parameter(Mandatory = $true)]
        [int]$Batch,

        [Parameter(Mandatory = $true)]
        [int]$Seed,

        [string]$Tag = ""
    )

    $ModelStem = Get-YoloModelStem -Model $Model
    $DatasetName = ConvertTo-YoloSafeName -Value $Dataset
    $Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Parts = @("ps", $ModelStem, $DatasetName, "img$ImgSize", "e$Epochs", "b$Batch", "s$Seed")

    if (-not [string]::IsNullOrWhiteSpace($Tag)) {
        $Parts += ConvertTo-YoloSafeName -Value $Tag
    }

    $Parts += $Timestamp
    return ($Parts -join "_")
}

function Get-LatestYoloTrainRun {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Dataset
    )

    $TrainRoot = Join-Path $Root "runs\train\$Dataset"
    if (-not (Test-Path -LiteralPath $TrainRoot)) {
        throw "Training run directory not found: $TrainRoot"
    }

    $Runs = @(Get-ChildItem -LiteralPath $TrainRoot -Directory |
        ForEach-Object {
            $BestWeight = Join-Path $_.FullName "weights\best.pt"
            if (Test-Path -LiteralPath $BestWeight) {
                $WeightItem = Get-Item -LiteralPath $BestWeight
                [pscustomobject]@{
                    Name = $_.Name
                    FullName = $_.FullName
                    BestWeight = $BestWeight
                    SortTime = $WeightItem.LastWriteTime
                }
            }
        } |
        Sort-Object SortTime -Descending)

    if (-not $Runs -or $Runs.Count -eq 0) {
        throw "No training run with weights\best.pt found under: $TrainRoot"
    }

    return $Runs[0]
}

function Get-YoloRunNameFromModelPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModelPath
    )

    $WeightDir = Split-Path -Parent $ModelPath
    $RunDir = Split-Path -Parent $WeightDir
    return Split-Path -Leaf $RunDir
}

function Get-YoloModelFamilyFromRunName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunName
    )

    if ($RunName -match "^(ps_[^_]+)") {
        return $Matches[1]
    }

    return "ps_model"
}
