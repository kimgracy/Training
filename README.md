# Blood PS YOLO Training Guide

혈액 PS particle detection 모델 학습을 위한 YOLO 프로젝트입니다. 이 repository는 데이터셋 버전 관리, 학습/검증 실행, prediction 결과 확인, 모델 registry 관리를 쉽게 하기 위한 구조로 정리되어 있습니다.

## 1. 프로젝트 구조

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

## 2. 주요 폴더 역할

| 경로 | 역할 |
| --- | --- |
| `exports/<dataset_version>/` | 원본 export 데이터 보관 위치입니다. 원본 보존을 위해 직접 수정하지 않는 것을 권장합니다. |
| `data/yolo/<dataset_version>/` | YOLO 학습용으로 변환된 데이터셋입니다. |
| `runs/train/<dataset_version>/` | YOLO training 결과가 저장됩니다. |
| `runs/val/<dataset_version>/` | 학습된 모델의 validation 결과가 저장됩니다. |
| `runs/predict/<dataset_version>/` | prediction 시각화 이미지가 저장됩니다. |
| `models/registry/` | 보관할 가치가 있는 모델과 핵심 산출물을 복사해 관리합니다. |
| `models/production/current.yaml` | 실제 사용 모델을 지정하기 위한 파일입니다. |
| `configs/train/` | 학습 설정 기록용 config 파일을 보관합니다. |
| `scripts/` | 데이터 준비, 학습, 검증, prediction, 모델 승격 자동화 스크립트입니다. |

## 3. 주요 파일 역할

| 파일 | 역할 |
| --- | --- |
| `blood_ps.yaml` | YOLO가 읽는 dataset 설정 파일입니다. train/val 경로와 class 이름을 정의합니다. |
| `manifest.csv` | 이미지별 split, label 경로, bbox 개수를 기록합니다. |
| `dataset_stats.json` | 데이터셋 이미지 수, positive image 수, bbox 수를 요약합니다. |
| `results.csv` | epoch별 loss, precision, recall, mAP 기록입니다. |
| `results.png` | 학습 곡선 이미지입니다. |
| `confusion_matrix.png` | confusion matrix 결과입니다. |
| `weights/best.pt` | validation 기준 가장 좋은 모델 weight입니다. |
| `weights/last.pt` | 마지막 epoch의 모델 weight입니다. |
| `metadata.yaml` | registry에 보관한 모델의 데이터셋, run, 학습 조건 기록입니다. |

## 4. `.ps1` 파일이란?

`.ps1`은 PowerShell script 파일입니다. PowerShell에서 여러 줄의 명령을 매번 직접 입력하지 않고, 하나의 파일로 실행할 수 있게 만든 자동화 스크립트입니다.

이 프로젝트의 `.ps1` 파일은 다음 YOLO 명령을 쉽게 재사용하기 위한 wrapper입니다.

| 스크립트 | 역할 |
| --- | --- |
| `scripts/train.ps1` | `yolo detect train` 실행 |
| `scripts/val.ps1` | `yolo detect val` 실행 |
| `scripts/predict_val.ps1` | `yolo detect predict` 실행 |
| `scripts/promote_model.ps1` | 좋은 모델을 `models/registry`로 복사 |

PowerShell에서 `.ps1` 실행이 막히면 현재 터미널 세션에서만 아래 명령으로 허용할 수 있습니다.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## 5. 환경 준비

프로젝트 루트로 이동합니다.

```powershell
cd "C:\Users\Asus\Documents\KIST\혈액과제\Training"
```

가상환경을 활성화합니다.

```powershell
conda activate bloodps
```

YOLO 명령이 동작하는지 확인합니다.

```powershell
yolo checks
```

## 6. 기존 데이터셋으로 새 학습 실행

현재 정리된 데이터셋은 `0706_v1`입니다.

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

학습 결과는 아래 위치에서 확인합니다.

```text
runs/train/0706_v1/ps_yolo11s_img960_e100_b4_s0_retry01/
```

주요 확인 파일은 다음과 같습니다.

```text
weights/best.pt
weights/last.pt
results.csv
results.png
confusion_matrix.png
val_batch*_pred.jpg
```

## 7. Validation 실행

학습이 끝난 모델을 정량 평가합니다.

```powershell
.\scripts\val.ps1 `
  -Dataset "0706_v1" `
  -RunName "ps_yolo11s_img960_e100_b4_s0_retry01"
```

결과는 아래 위치에서 확인합니다.

```text
runs/val/0706_v1/
```

## 8. Prediction 이미지 생성

validation 이미지에 대해 detection 결과 이미지를 저장합니다.

```powershell
.\scripts\predict_val.ps1 `
  -Dataset "0706_v1" `
  -RunName "ps_yolo11s_img960_e100_b4_s0_retry01" `
  -Conf 0.15
```

결과는 아래 위치에서 확인합니다.

```text
runs/predict/0706_v1/
```

## 9. 좋은 모델을 registry로 보관

성능이 괜찮은 run만 registry로 복사합니다.

```powershell
.\scripts\promote_model.ps1 `
  -Dataset "0706_v1" `
  -RunName "ps_yolo11s_img960_e100_b4_s0_retry01" `
  -RegistryName "20260706_retry01_0706_v1"
```

결과는 아래 위치에 저장됩니다.

```text
models/registry/ps_particle/ps_yolo11s/20260706_retry01_0706_v1/
```

## 10. 새로운 training set으로 학습하는 방법

새 training set은 반드시 새 버전명으로 분리합니다. 예를 들어 `0708_v1`처럼 날짜와 버전을 함께 적습니다.

### 10.1 원본 데이터 배치

새 원본 데이터를 아래 위치에 둡니다.

```text
exports/0708_v1/
```

이미지와 라벨 파일은 같은 stem을 가져야 합니다.

```text
frame_000000.png
frame_000000.txt
```

YOLO detection label 형식은 다음과 같습니다.

```text
class_id x_center y_center width height
```

### 10.2 YOLO 학습용 데이터셋 생성

```powershell
python .\scripts\prepare_yolo_dataset.py `
  --dataset 0708_v1 `
  --val-ratio 0.2 `
  --seed 42
```

생성 결과:

```text
data/yolo/0708_v1/
```

먼저 아래 파일을 확인합니다.

```text
data/yolo/0708_v1/dataset_stats.json
data/yolo/0708_v1/manifest.csv
```

`train_positive_images`, `val_positive_images`, `train_bboxes`, `val_bboxes`가 너무 한쪽에 몰려 있으면 split을 다시 만드는 것을 권장합니다.

### 10.3 새 데이터셋으로 training

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

결과:

```text
runs/train/0708_v1/ps_yolo11s_img960_e100_b4_s0_0708_v1/
```

### 10.4 Validation

```powershell
.\scripts\val.ps1 `
  -Dataset "0708_v1" `
  -RunName "ps_yolo11s_img960_e100_b4_s0_0708_v1"
```

### 10.5 Prediction 확인

```powershell
.\scripts\predict_val.ps1 `
  -Dataset "0708_v1" `
  -RunName "ps_yolo11s_img960_e100_b4_s0_0708_v1" `
  -Conf 0.15
```

### 10.6 모델 registry 보관

```powershell
.\scripts\promote_model.ps1 `
  -Dataset "0708_v1" `
  -RunName "ps_yolo11s_img960_e100_b4_s0_0708_v1" `
  -RegistryName "20260708_0708_v1"
```

## 11. Git 관리 정책

Git에는 코드, 설정, 문서, 작은 메타데이터를 올리는 것을 권장합니다.

권장 포함:

```text
README.md
scripts/
configs/
models/production/current.yaml
data/yolo/*/blood_ps.yaml
data/yolo/*/manifest.csv
data/yolo/*/dataset_stats.json
```

권장 제외:

```text
exports/
data/yolo/*/images/
data/yolo/*/labels/
runs/
models/registry/
*.pt
```

원본 이미지, 라벨, weight 파일은 용량이 크고 자주 바뀌므로 Git보다는 별도 공유 스토리지나 NAS에 보관하는 것이 좋습니다.

## 12. 현재 `0706_v1` 데이터셋 참고

현재 `0706_v1`의 요약은 다음과 같습니다.

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

현재 split은 positive sample이 validation 쪽에 많이 몰려 있습니다. 기존 run 재현성은 유지되지만, 성능 개선 목적의 새 실험에서는 split을 다시 구성하는 것을 권장합니다.
