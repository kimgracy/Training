# Blood PS YOLO Training Guide

This repository contains a YOLO-based workflow for training and managing a blood PS particle detection model. It is organized to keep raw exports, YOLO-ready datasets, training outputs, prediction outputs, and promoted model artifacts separate.

## Project Structure

```text
Training/
|- configs/
|  `- train/
|     `- ps_yolo11s_img960_e100_b4.yaml
|- data/
|  `- yolo/
|     `- <dataset_version>/
|        |- blood_ps.yaml
|        |- manifest.csv
|        |- dataset_stats.json
|        |- images/
|        |  |- train/
|        |  `- val/
|        `- labels/
|           |- train/
|           `- val/
|- exports/
|  `- <dataset_version>/
|- models/
|  |- production/
|  |  `- current.yaml
|  `- registry/
|     `- ps_particle/
|        `- ps_yolo11s/
|- runs/
|  |- train/
|  |- val/
|  |- predict/
|  `- cache/
`- scripts/
   |- prepare_yolo_dataset.py
   |- train.ps1
   |- val.ps1
   |- predict_val.ps1
   `- promote_model.ps1
```

## Directory Roles

| Path | Purpose |
| --- | --- |
| `exports/<dataset_version>/` | Raw exported data. Treat this as read-only source data. |
| `data/yolo/<dataset_version>/` | YOLO-ready dataset generated from the raw export. |
| `runs/train/<dataset_version>/` | Training outputs from `yolo detect train`. |
| `runs/val/<dataset_version>/` | Validation outputs from `yolo detect val`. |
| `runs/predict/<dataset_version>/` | Prediction visualization outputs from `yolo detect predict`. |
| `models/registry/` | Curated model artifacts worth keeping for comparison or future use. |
| `models/production/current.yaml` | Pointer file for the currently selected production model. |
| `configs/train/` | Training configuration records. |
| `scripts/` | Automation scripts for dataset preparation, training, validation, prediction, and model promotion. |

## Important Files

| File | Purpose |
| --- | --- |
| `blood_ps.yaml` | Dataset config read by YOLO. Defines train/val paths and class names. |
| `manifest.csv` | Per-image split record, label path, source path, and bounding box count. |
| `dataset_stats.json` | Dataset summary such as image count, positive image count, and bounding box count. |
| `results.csv` | Per-epoch loss, precision, recall, and mAP values. |
| `results.png` | Training curve plot. |
| `confusion_matrix.png` | Confusion matrix image. |
| `weights/best.pt` | Best model checkpoint selected by validation performance. |
| `weights/last.pt` | Last epoch model checkpoint. |
| `metadata.yaml` | Registry metadata for a promoted model. |

## What Are `.ps1` Files?

`.ps1` files are PowerShell scripts. They let you run repeatable command sequences without typing long YOLO commands manually each time.

| Script | Purpose |
| --- | --- |
| `scripts/train.ps1` | Runs `yolo detect train`. |
| `scripts/val.ps1` | Runs `yolo detect val`. |
| `scripts/predict_val.ps1` | Runs `yolo detect predict` on a validation split. |
| `scripts/promote_model.ps1` | Copies selected model artifacts into `models/registry/`. |

If PowerShell blocks script execution, allow scripts for the current terminal session only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Environment Setup

Open PowerShell and move to the project root:

```powershell
cd "C:\Users\Asus\Documents\KIST\혈액과제\Training"
```

Activate the training environment:

```powershell
conda activate bloodps
```

Check that YOLO is available:

```powershell
yolo checks
```

## Train With the Existing Dataset

The currently prepared dataset version is `0706_v1`.

```powershell
.\scripts\train.ps1 `
  -Dataset "0706_v1" `
  -Model "yolo11s.pt" `
  -ImgSize 960 `
  -Epochs 100 `
  -Batch 4 `
  -Device "0" `
  -Seed 0 `
  -RunName "ps_yolo11s_img960_e100_b4_s0_retry01"
```

Training outputs will be saved under:

```text
runs/train/0706_v1/ps_yolo11s_img960_e100_b4_s0_retry01/
```

Key files to inspect:

```text
weights/best.pt
weights/last.pt
results.csv
results.png
confusion_matrix.png
val_batch*_pred.jpg
```

## Run Validation

Run quantitative validation for a trained model:

```powershell
.\scripts\val.ps1 `
  -Dataset "0706_v1" `
  -RunName "ps_yolo11s_img960_e100_b4_s0_retry01"
```

Validation outputs will be saved under:

```text
runs/val/0706_v1/
```

## Generate Prediction Images

Generate visual prediction results on the validation images:

```powershell
.\scripts\predict_val.ps1 `
  -Dataset "0706_v1" `
  -RunName "ps_yolo11s_img960_e100_b4_s0_retry01" `
  -Conf 0.15
```

Prediction outputs will be saved under:

```text
runs/predict/0706_v1/
```

## Promote a Good Model to the Registry

If a run looks useful, copy its core artifacts into the model registry:

```powershell
.\scripts\promote_model.ps1 `
  -Dataset "0706_v1" `
  -RunName "ps_yolo11s_img960_e100_b4_s0_retry01" `
  -RegistryName "20260706_retry01_0706_v1"
```

Promoted model artifacts will be saved under:

```text
models/registry/ps_particle/ps_yolo11s/20260706_retry01_0706_v1/
```

## Train With a New Dataset

Always create a new dataset version instead of overwriting an existing one. A recommended naming format is `<MMDD>_v<version>`, for example `0708_v1`.

### 1. Place Raw Data

Place the new raw export here:

```text
exports/0708_v1/
```

Image and label filenames must share the same stem:

```text
frame_000000.png
frame_000000.txt
```

YOLO detection labels must use this format:

```text
class_id x_center y_center width height
```

### 2. Prepare the YOLO Dataset

```powershell
python .\scripts\prepare_yolo_dataset.py `
  --dataset 0708_v1 `
  --val-ratio 0.2 `
  --seed 42
```

The generated dataset will be saved under:

```text
data/yolo/0708_v1/
```

Check these files before training:

```text
data/yolo/0708_v1/dataset_stats.json
data/yolo/0708_v1/manifest.csv
```

Pay special attention to:

```text
train_positive_images
val_positive_images
train_bboxes
val_bboxes
```

If positive samples or bounding boxes are heavily skewed toward one split, regenerate the split before training.

### 3. Train

```powershell
.\scripts\train.ps1 `
  -Dataset "0708_v1" `
  -Model "yolo11s.pt" `
  -ImgSize 960 `
  -Epochs 100 `
  -Batch 4 `
  -Device "0" `
  -Seed 0 `
  -RunName "ps_yolo11s_img960_e100_b4_s0_0708_v1"
```

Training outputs:

```text
runs/train/0708_v1/ps_yolo11s_img960_e100_b4_s0_0708_v1/
```

### 4. Validate

```powershell
.\scripts\val.ps1 `
  -Dataset "0708_v1" `
  -RunName "ps_yolo11s_img960_e100_b4_s0_0708_v1"
```

### 5. Generate Prediction Images

```powershell
.\scripts\predict_val.ps1 `
  -Dataset "0708_v1" `
  -RunName "ps_yolo11s_img960_e100_b4_s0_0708_v1" `
  -Conf 0.15
```

### 6. Promote the Model

```powershell
.\scripts\promote_model.ps1 `
  -Dataset "0708_v1" `
  -RunName "ps_yolo11s_img960_e100_b4_s0_0708_v1" `
  -RegistryName "20260708_0708_v1"
```

## Git Policy

Commit code, configs, documentation, and small metadata files.

Recommended to commit:

```text
README.md
scripts/
configs/
models/production/current.yaml
data/yolo/*/blood_ps.yaml
data/yolo/*/manifest.csv
data/yolo/*/dataset_stats.json
```

Recommended to exclude:

```text
exports/
data/yolo/*/images/
data/yolo/*/labels/
runs/
models/registry/
*.pt
```

Raw images, labels, run outputs, and model weights are usually large and change often. Store them in a shared drive, NAS, artifact storage, or another dataset/model storage system instead of Git.

## Current `0706_v1` Dataset Notes

Current dataset summary:

```text
total_images: 60
total_bboxes: 42
train_images: 48
train_positive_images: 1
train_bboxes: 4
val_images: 12
val_positive_images: 6
val_bboxes: 38
```

The current split is skewed: most positive samples are in validation rather than training. This is preserved for reproducibility of the existing run, but future experiments should regenerate a better-balanced split.
