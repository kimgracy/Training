# Blood PS YOLO Training Guide

This guide explains the full workflow for training, validating, and visually checking a YOLO detection model from a CVAT-exported dataset. It is written for teammates who are starting from zero.

## 0. Start Here

Open PowerShell, move to the project root, and activate the training environment.

```powershell
cd "C:\Users\Asus\Documents\KIST\혈액과제\Training"
conda activate bloodps
```

If PowerShell blocks script execution, allow scripts for the current terminal session only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Check that YOLO is available:

```powershell
yolo checks
```

## 1. Export From CVAT

After labeling data in CVAT, export the dataset using:

```text
Ultralytics YOLO Detection 1.0
```

This project expects a YOLO detection dataset with image files and YOLO `.txt` label files.

## 2. Save the Exported Dataset

Place the downloaded CVAT export under the `exports/` folder.

Use a dataset folder name in this format:

```text
<MMDD>_v<version>
```

Example:

```text
exports/0706_v1/
```

The exported dataset folder should contain:

```text
exports/0706_v1/
|- images/
|- labels/
|- data.yaml
`- train.txt
```

Each image and label file should share the same stem:

```text
frame_000000.png
frame_000000.txt
```

YOLO label files should use this format:

```text
class_id x_center y_center width height
```

## 3. Prepare the YOLO Dataset

Run:

```powershell
python .\scripts\prepare_yolo_dataset.py
```

The script first asks for `Dataset`. This value has no default. Enter the dataset folder name under `exports/`, for example:

```text
Dataset [required]: 0706_v1
```

Then it asks whether to use default values for the remaining parameters:

```text
Use these default parameters? [Y/n]
```

Default remaining values:

```text
Val ratio: 0.2
Seed: 42
Class name: ps_particle
Keep class IDs: no
Overwrite: no
```

Press Enter or type `Y` to use the defaults. Type `N` to enter the remaining parameters interactively. For those remaining prompts, pressing Enter keeps the value shown in brackets.

For non-interactive use:

```powershell
python .\scripts\prepare_yolo_dataset.py `
  --dataset 0706_v1 `
  --val-ratio 0.2 `
  --seed 42
```

The prepared dataset is created here:

```text
data/yolo/0706_v1/
```

Important files to check before training:

```text
data/yolo/0706_v1/blood_ps.yaml
data/yolo/0706_v1/manifest.csv
data/yolo/0706_v1/dataset_stats.json
```

In `dataset_stats.json`, check:

```text
train_positive_images
val_positive_images
train_bboxes
val_bboxes
```

If positive samples or bounding boxes are heavily skewed toward one split, regenerate the dataset split before training.

## 4. Train the Model

Run from the project root:

```powershell
.\train.ps1
```

This is a convenience wrapper that calls:

```text
scripts/train.ps1
```

The training script first asks for `Dataset`. This value has no default.

```text
Dataset [required]: 0706_v1
```

Then it shows the remaining default training parameters:

```text
Model: yolo11s.pt
ImgSize: 960
Epochs: 100
Batch: 4
Device: 0
Seed: 0
Tag: <blank>
RunName: auto-generated
```

It then asks:

```text
Use these default parameters? [Y/n]
```

Press Enter or type `Y` to train with the defaults. Type `N` to enter the remaining parameters interactively. For non-Dataset prompts, pressing Enter keeps the value shown in brackets.

For non-interactive training:

```powershell
.\train.ps1 `
  -Dataset "0706_v1" `
  -Model "yolo11s.pt" `
  -ImgSize 960 `
  -Epochs 100 `
  -Batch 4 `
  -Device "0" `
  -Seed 0
```

If `RunName` is left blank, the script automatically creates one:

```text
ps_<model>_<dataset>_img<imgsz>_e<epochs>_b<batch>_s<seed>_<timestamp>
```

Example:

```text
ps_yolo11s_0706_v1_img960_e100_b4_s0_20260706_153012
```

Training outputs are saved here:

```text
runs/train/0706_v1/<run_name>/
```

## 5. Run Validation

Run:

```powershell
.\scripts\val.ps1
```

The validation script immediately asks for parameters. There is no default for `Dataset`.

```text
Dataset [required]: 0706_v1
RunName [blank]:
ModelPath [blank]:
ImgSize [960]:
Batch [4]:
Device [0]:
Split [val]:
Name [blank]:
```

Usually, enter only `Dataset` and press Enter for the rest. If `RunName` and `ModelPath` are blank, the script automatically uses the latest training run under:

```text
runs/train/<dataset>/
```

For non-interactive validation:

```powershell
.\scripts\val.ps1 -Dataset "0706_v1"
```

Validation outputs are saved here:

```text
runs/val/0706_v1/<validation_run_name>/
```

## 6. Generate Prediction Images

Run:

```powershell
.\scripts\predict_val.ps1
```

The prediction script immediately asks for parameters. There is no default for `Dataset`.

```text
Dataset [required]: 0706_v1
RunName [blank]:
ModelPath [blank]:
Split [val]:
ImgSize [960]:
Conf [0.15]:
Name [blank]:
```

Usually, enter only `Dataset` and press Enter for the rest. If `RunName` and `ModelPath` are blank, the script automatically uses the latest training run for that dataset.

For non-interactive prediction:

```powershell
.\scripts\predict_val.ps1 `
  -Dataset "0706_v1" `
  -Conf 0.15
```

Prediction images are saved here:

```text
runs/predict/0706_v1/<prediction_run_name>/
```

## 7. Check Results

### Trained Weights

The trained model weights are saved under the training run:

```text
runs/train/0706_v1/<run_name>/weights/
|- best.pt
`- last.pt
```

Use `best.pt` for most validation, prediction, and downstream usage.

### Training Metrics and Graphs

Training metrics and graphs are saved under:

```text
runs/train/0706_v1/<run_name>/
```

Important files:

```text
results.csv
results.png
confusion_matrix.png
confusion_matrix_normalized.png
BoxF1_curve.png
BoxPR_curve.png
BoxP_curve.png
BoxR_curve.png
```

### Training and Validation Preview Images

YOLO also saves preview images in the training run folder:

```text
train_batch*.jpg
val_batch*_labels.jpg
val_batch*_pred.jpg
```

The `val_batch*_pred.jpg` files are useful for quickly checking whether predictions look reasonable.

### Prediction Images With Labels

Images with predicted labels drawn on them are saved under:

```text
runs/predict/0706_v1/<prediction_run_name>/
```

Open the `.jpg` files in that folder to visually inspect detections.

## Project Structure

```text
Training/
|- train.ps1
|- configs/
|  `- train/
|- data/
|  `- yolo/
|     `- <dataset_version>/
|- exports/
|  `- <dataset_version>/
|- models/
|  |- production/
|  `- registry/
|- runs/
|  |- train/
|  |- val/
|  |- predict/
|  `- cache/
`- scripts/
   |- _run_utils.ps1
   |- prepare_yolo_dataset.py
   |- train.ps1
   |- val.ps1
   |- predict_val.ps1
   `- promote_model.ps1
```

## Script Summary

| Script | Purpose |
| --- | --- |
| `scripts/prepare_yolo_dataset.py` | Converts a CVAT YOLO export under `exports/` into this project's `data/yolo/` training structure. |
| `train.ps1` | Project-root wrapper for `scripts/train.ps1`. |
| `scripts/train.ps1` | Runs `yolo detect train`. |
| `scripts/val.ps1` | Runs `yolo detect val`. |
| `scripts/predict_val.ps1` | Runs `yolo detect predict` on a dataset split. |
| `scripts/_run_utils.ps1` | Shared helper functions for automatic run naming and latest-run lookup. |
| `scripts/promote_model.ps1` | Copies selected model artifacts into `models/registry/`. |

## Git Policy

The `.gitignore` file is allowlist-based. Running `git add .` should only track the files below.

Tracked files:

```text
README.md
.gitignore
train.ps1
scripts/
configs/
models/production/current.yaml
data/yolo/*/blood_ps.yaml
data/yolo/*/manifest.csv
data/yolo/*/dataset_stats.json
```

Raw images, labels, run outputs, model weights, caches, and local environment files are not tracked.
