# YOLO Video Workflow

This repository manages YOLO detection, validation, prediction, and tracking for microscope videos.

## 0. Start Here

Open PowerShell, move to the repository root, and activate the training environment.

```powershell
cd "<path-to-this-repository>"
conda activate blood_vision
```

If PowerShell blocks script execution, allow scripts for the current terminal session only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Check that YOLO is available:

```powershell
yolo checks
```

All PowerShell workflow scripts are interactive. You can run them with no parameters, or provide only the values you already know. If a required value such as `Video`, `Version`, or `Dataset` is missing, the script asks for it in the terminal and shows a sensible default when one can be inferred.

## 1. Project Layout

Video-centered projects are stored like this:

```text
Training/
|- configs/
|  `- classes/
|     `- blood_ps.yaml
|     `- bead_ctc.yaml
|- videos/
|  `- <video>/
|     |- source/
|     |  `- <original_video>.mp4
|     |- exports/
|     |  `- <version>/
|     |- yolo/
|     |  `- <version>/
|     |- runs/
|     |  |- train/
|     |  |- val/
|     |  |- predict/
|     |  `- track/
|     `- video.yaml
`- scripts/
   |- legacy/
   |- new_video_project.ps1
   |- prepare_video_dataset.ps1
   |- train_video.ps1
   |- val_video.ps1
   |- predict_video.ps1
   `- track_video.ps1
```

Example:

```text
videos/backlight1/
|- source/
|  `- backlight1.mp4
|- exports/
|  `- 0706_v1/
|- yolo/
|  `- 0706_v1/
|- runs/
|  |- train/
|  |- val/
|  |- predict/
|  `- track/
`- video.yaml
```

Class definitions are stored here:

```text
configs/classes/
```

Available class schemas:

```yaml
# configs/classes/blood_ps.yaml
names:
  0: ps_particle

# configs/classes/bead_ctc.yaml
names:
  0: CTC
  1: bead
```

For multi-class datasets, the CVAT class order must match the config exactly. For `bead_ctc.yaml`, labels must use class ID `0` for `CTC` and class ID `1` for `bead`.

## 2. Create a Video Project

For a new video such as `backlight1.mp4`, run:

```powershell
.\scripts\new_video_project.ps1 `
  -VideoFile ".\backlight1.mp4" `
  -Version "0706_v1"
```

If `-Video` is not provided, the script derives the video name from the file name. For `backlight1.mp4`, the video name becomes:

```text
backlight1
```

The script creates:

```text
videos/backlight1/source/
videos/backlight1/exports/0706_v1/
videos/backlight1/yolo/0706_v1/
videos/backlight1/runs/train/0706_v1/
videos/backlight1/runs/val/0706_v1/
videos/backlight1/runs/predict/0706_v1/
videos/backlight1/runs/track/0706_v1/
videos/backlight1/video.yaml
```

Interactive mode is also available:

```powershell
.\scripts\new_video_project.ps1
```

Partial interactive mode is also supported. For example, this asks for the missing `Version` and uses the provided class config:

```powershell
.\scripts\new_video_project.ps1 `
  -VideoFile ".\bead_ctc_4.avi" `
  -ClassConfig "../../configs/classes/bead_ctc.yaml"
```

## 3. Label and Export From CVAT

Label frames from the source video in CVAT.

When exporting from CVAT, use:

```text
Ultralytics YOLO Detection 1.0
```

Place the downloaded export here:

```text
videos/backlight1/exports/0706_v1/
```

The export folder should contain:

```text
videos/backlight1/exports/0706_v1/
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

YOLO label files should use:

```text
class_id x_center y_center width height
```

## 4. Prepare the YOLO Dataset

Run:

```powershell
.\scripts\prepare_video_dataset.ps1 -Video "backlight1" -Version "0706_v1"
```

This reads:

```text
videos/backlight1/exports/0706_v1/
```

and creates:

```text
videos/backlight1/yolo/0706_v1/
```

Important files:

```text
videos/backlight1/yolo/0706_v1/blood_ps.yaml
videos/backlight1/yolo/0706_v1/manifest.csv
videos/backlight1/yolo/0706_v1/dataset_stats.json
```

Default preparation values:

```text
Val ratio: 0.2
Seed: 42
Class name: ps_particle
Keep class IDs: no
Overwrite: no
```

For multi-class datasets, pass a class config and keep the original class IDs:

```powershell
.\scripts\prepare_video_dataset.ps1 `
  -Video "bead_ctc_4" `
  -Version "0707_v1" `
  -ClassConfig "configs/classes/bead_ctc.yaml" `
  -KeepClassIds
```

Interactive mode:

```powershell
.\scripts\prepare_video_dataset.ps1
```

You can also provide only the video name and let the script ask for the missing version:

```powershell
.\scripts\prepare_video_dataset.ps1 -Video "bead_ctc_4"
```

## 5. Train

Run:

```powershell
.\scripts\train_video.ps1 -Video "backlight1" -Version "0706_v1"
```

Default training values:

```text
Model: yolo11s.pt
ImgSize: 960
Epochs: 100
Batch: 4
Device: 0
Seed: 0
RunName: auto-generated
```

Training outputs are saved under:

```text
videos/backlight1/runs/train/0706_v1/<run_name>/
```

Model weights:

```text
videos/backlight1/runs/train/0706_v1/<run_name>/weights/best.pt
videos/backlight1/runs/train/0706_v1/<run_name>/weights/last.pt
```

Interactive mode:

```powershell
.\scripts\train_video.ps1
```

Partial interactive mode:

```powershell
.\scripts\train_video.ps1 -Video "bead_ctc_4"
```

## 6. Validate

Run:

```powershell
.\scripts\val_video.ps1 -Video "backlight1" -Version "0706_v1"
```

If `RunName` and `ModelPath` are blank, the script automatically uses the latest training run for the selected video/version.

Validation outputs are saved under:

```text
videos/backlight1/runs/val/0706_v1/<validation_run_name>/
```

Interactive mode:

```powershell
.\scripts\val_video.ps1
```

Partial interactive mode:

```powershell
.\scripts\val_video.ps1 -Video "bead_ctc_4"
```

## 7. Generate Prediction Images

Run:

```powershell
.\scripts\predict_video.ps1 -Video "backlight1" -Version "0706_v1"
```

This runs detection on:

```text
videos/backlight1/yolo/0706_v1/images/val/
```

Prediction outputs are saved under:

```text
videos/backlight1/runs/predict/0706_v1/<prediction_run_name>/
```

Interactive mode:

```powershell
.\scripts\predict_video.ps1
```

Partial interactive mode:

```powershell
.\scripts\predict_video.ps1 -Video "bead_ctc_4"
```

## 8. Track the Source Video

Run:

```powershell
.\scripts\track_video.ps1 -Video "backlight1" -Version "0706_v1"
```

If `RunName` and `ModelPath` are blank, the script automatically uses the latest `best.pt` model for the selected video/version.

Tracking requires a trained model. If no `weights/best.pt` exists under `videos/<video>/runs/train/<version>/`, run `train_video.ps1` first or enter an existing `ModelPath` when prompted.

Default tracking values:

```text
ImgSize: 960
Conf: 0.15
Iou: 0.7
Device: 0
Tracker: bytetrack.yaml
VidStride: 1
Show live window: Y
Save tracked video: Y
Save track labels as txt: N
Save confidence in txt labels: N
```

Tracking outputs are saved under:

```text
videos/backlight1/runs/track/0706_v1/<tracking_run_name>/
```

You can also track another source with the same model:

```powershell
.\scripts\track_video.ps1 `
  -Video "backlight1" `
  -Version "0706_v1" `
  -Source ".\other_video.mp4"
```

For a webcam or stream:

```powershell
.\scripts\track_video.ps1 -Video "backlight1" -Version "0706_v1" -Source "0"
.\scripts\track_video.ps1 -Video "backlight1" -Version "0706_v1" -Source "rtsp://example-stream-url"
```

The default tracker is `bytetrack.yaml`. Try `botsort.yaml` if object IDs switch too often.

Partial interactive mode:

```powershell
.\scripts\track_video.ps1 -Video "bead_ctc_4"
```

## 9. Full Example: backlight1.mp4

```powershell
.\scripts\new_video_project.ps1 -VideoFile ".\backlight1.mp4" -Version "0706_v1"
```

Put the CVAT export into:

```text
videos/backlight1/exports/0706_v1/
```

Then run:

```powershell
.\scripts\prepare_video_dataset.ps1 -Video "backlight1" -Version "0706_v1"
.\scripts\train_video.ps1 -Video "backlight1" -Version "0706_v1"
.\scripts\val_video.ps1 -Video "backlight1" -Version "0706_v1"
.\scripts\predict_video.ps1 -Video "backlight1" -Version "0706_v1"
.\scripts\track_video.ps1 -Video "backlight1" -Version "0706_v1"
```

## 10. Existing Blood PS Video Workspace

The existing work for `Blood_PS particle_1.mp4` has been organized under:

```text
videos/blood_ps_particle_1/
```

Available versions:

```text
videos/blood_ps_particle_1/exports/0706_v1/
videos/blood_ps_particle_1/exports/0706_v2/
videos/blood_ps_particle_1/yolo/0706_v1/
videos/blood_ps_particle_1/yolo/0706_v2/
videos/blood_ps_particle_1/runs/train/0706_v1/
videos/blood_ps_particle_1/runs/train/0706_v2/
```

The source video is stored at:

```text
videos/blood_ps_particle_1/source/Blood_PS particle_1.mp4
```

To continue from the latest prepared dataset and runs:

```powershell
.\scripts\train_video.ps1 -Video "blood_ps_particle_1" -Version "0706_v2"
.\scripts\val_video.ps1 -Video "blood_ps_particle_1" -Version "0706_v2"
.\scripts\predict_video.ps1 -Video "blood_ps_particle_1" -Version "0706_v2"
.\scripts\track_video.ps1 -Video "blood_ps_particle_1" -Version "0706_v2"
```

## 11. Bead/CTC Video Workspace

The `bead_ctc_4.avi` video uses a different class schema:

```text
0: CTC
1: bead
```

The source video is organized here:

```text
videos/bead_ctc_4/source/bead_ctc_4.avi
```

Its metadata points to:

```text
configs/classes/bead_ctc.yaml
```

After labeling in CVAT, export with:

```text
Ultralytics YOLO Detection 1.0
```

Place the export here:

```text
videos/bead_ctc_4/exports/0707_v1/
```

The export folder should contain:

```text
videos/bead_ctc_4/exports/0707_v1/
|- images/
|- labels/
|- data.yaml
`- train.txt
```

Then run:

```powershell
.\scripts\prepare_video_dataset.ps1 `
  -Video "bead_ctc_4" `
  -Version "0707_v1" `
  -ClassConfig "configs/classes/bead_ctc.yaml" `
  -KeepClassIds

.\scripts\train_video.ps1 -Video "bead_ctc_4" -Version "0707_v1"
.\scripts\val_video.ps1 -Video "bead_ctc_4" -Version "0707_v1"
.\scripts\predict_video.ps1 -Video "bead_ctc_4" -Version "0707_v1"
.\scripts\track_video.ps1 -Video "bead_ctc_4" -Version "0707_v1"
```

Do not run tracking before training unless you provide `ModelPath` to an existing `.pt` file.

Prepared dataset metadata will be saved under:

```text
videos/bead_ctc_4/yolo/0707_v1/
|- dataset.yaml
|- blood_ps.yaml
|- manifest.csv
`- dataset_stats.json
```

Training and tracking outputs will be saved under:

```text
videos/bead_ctc_4/runs/train/0707_v1/
videos/bead_ctc_4/runs/track/0707_v1/
```

## 12. What to Check After Training

Training metrics and graphs:

```text
videos/<video>/runs/train/<version>/<run_name>/
```

Useful files:

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

Training and validation previews:

```text
train_batch*.jpg
val_batch*_labels.jpg
val_batch*_pred.jpg
```

Tracked videos:

```text
videos/<video>/runs/track/<version>/<tracking_run_name>/
```

## Script Summary

| Script | Purpose |
| --- | --- |
| `scripts/new_video_project.ps1` | Creates the standard `videos/<video>/` workspace for a source video. |
| `scripts/prepare_video_dataset.ps1` | Converts a video-specific CVAT export into a prepared YOLO dataset. |
| `scripts/train_video.ps1` | Runs YOLO detection training for one video/version through the active Python environment. |
| `scripts/val_video.ps1` | Runs YOLO validation for one video/version through the active Python environment. |
| `scripts/predict_video.ps1` | Runs YOLO prediction on the prepared validation split through the active Python environment. |
| `scripts/track_video.ps1` | Runs YOLO tracking on the source video, webcam, or stream through the active Python environment. |
| `scripts/_video_utils.ps1` | Shared helpers for video paths, prompts, and source-video lookup. |
| `scripts/_run_utils.ps1` | Shared helpers for safe names, latest training run lookup, and Ultralytics execution. |
| `scripts/prepare_yolo_dataset.py` | Core Python dataset preparation logic used by both workflows. |

## Legacy Dataset Workflow

The older dataset-centered scripts are still available:

```text
scripts/legacy/train_root.ps1
scripts/legacy/train.ps1
scripts/legacy/val.ps1
scripts/legacy/predict_val.ps1
scripts/legacy/promote_model.ps1
```

These use:

```text
exports/<dataset>/
data/yolo/<dataset>/
runs/<mode>/<dataset>/
```

For new video work, prefer the video-centered scripts.

## Git Policy

The `.gitignore` file is allowlist-based. Running `git add .` should track source code, docs, configs, and lightweight metadata only.

Tracked examples:

```text
README.md
.gitignore
scripts/
configs/
models/production/current.yaml
data/yolo/*/blood_ps.yaml
data/yolo/*/manifest.csv
data/yolo/*/dataset_stats.json
videos/*/video.yaml
videos/*/yolo/*/dataset.yaml
videos/*/yolo/*/blood_ps.yaml
videos/*/yolo/*/manifest.csv
videos/*/yolo/*/dataset_stats.json
```

Ignored examples:

```text
videos/*/source/
videos/*/exports/
videos/*/runs/
videos/*/yolo/*/images/
videos/*/yolo/*/labels/
exports/
runs/
models/registry/
*.pt
*.mp4
*.avi
*.jpg
*.png
```
