from __future__ import annotations

import argparse
import csv
import json
import random
import shutil
import sys
from pathlib import Path


IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff"}
IGNORED_LABEL_FILES = {"train.txt", "val.txt", "test.txt", "obj.names", "obj.data"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare a YOLO detection dataset.")
    parser.add_argument("--dataset", default="", help="Dataset version under exports/. Required for non-interactive runs.")
    parser.add_argument("--val-ratio", type=float, default=0.2, help="Validation split ratio.")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for splitting.")
    parser.add_argument("--class-name", default="ps_particle", help="Single class name.")
    parser.add_argument(
        "--keep-class-ids",
        action="store_true",
        help="Keep original class IDs instead of remapping all labels to class 0.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite data/yolo/<dataset> if it already exists.",
    )
    interactive = len(sys.argv) == 1
    args = parser.parse_args()
    args.interactive = interactive
    if interactive:
        args = prompt_for_args(args)
    elif not args.dataset.strip():
        parser.error("--dataset is required for non-interactive runs.")
    return args


def read_choice(prompt: str, default: bool = True) -> bool:
    suffix = "[Y/n]" if default else "[y/N]"
    while True:
        answer = input(f"{prompt} {suffix} ").strip().lower()
        if not answer:
            return default
        if answer in {"y", "yes"}:
            return True
        if answer in {"n", "no"}:
            return False
        print("Please enter Y or N.")


def read_str_with_default(name: str, default: str) -> str:
    value = input(f"{name} [{default}]: ").strip()
    return value or default


def read_required_str(name: str) -> str:
    while True:
        value = input(f"{name} [required]: ").strip()
        if value:
            return value
        print(f"{name} is required.")


def read_int_with_default(name: str, default: int) -> int:
    while True:
        value = input(f"{name} [{default}]: ").strip()
        if not value:
            return default
        try:
            return int(value)
        except ValueError:
            print("Please enter an integer.")


def read_float_with_default(name: str, default: float) -> float:
    while True:
        value = input(f"{name} [{default}]: ").strip()
        if not value:
            return default
        try:
            parsed = float(value)
        except ValueError:
            print("Please enter a number.")
            continue
        if 0 < parsed < 1:
            return parsed
        print("Please enter a value between 0 and 1.")


def prompt_for_args(args: argparse.Namespace) -> argparse.Namespace:
    print("No dataset preparation parameters were provided.")
    print()
    print("Dataset has no default and must be entered before continuing.")
    args.dataset = read_required_str("Dataset")
    print()
    print("Selected dataset:")
    print(f"  Dataset        : {args.dataset}")
    print()
    print("Default parameters for the remaining fields:")
    print(f"  Val ratio      : {args.val_ratio}")
    print(f"  Seed           : {args.seed}")
    print(f"  Class name     : {args.class_name}")
    print(f"  Keep class IDs : {'yes' if args.keep_class_ids else 'no (remap labels to class 0)'}")
    print(f"  Overwrite      : {'yes' if args.overwrite else 'no'}")
    print()

    use_defaults = read_choice("Use these default parameters?", default=True)
    if use_defaults:
        print()
        return args

    print("Enter dataset preparation parameters. Press Enter to keep the value shown in brackets.")
    args.val_ratio = read_float_with_default("Val ratio", args.val_ratio)
    args.seed = read_int_with_default("Seed", args.seed)
    args.class_name = read_str_with_default("Class name", args.class_name)
    args.keep_class_ids = read_choice("Keep original class IDs instead of remapping to 0?", default=args.keep_class_ids)
    args.overwrite = read_choice("Overwrite output dataset if it already exists?", default=args.overwrite)
    print()
    return args


def find_images(root: Path) -> list[Path]:
    return sorted(p for p in root.rglob("*") if p.suffix.lower() in IMAGE_EXTS)


def build_label_index(root: Path) -> dict[str, Path]:
    label_index: dict[str, Path] = {}
    for txt in root.rglob("*.txt"):
        if txt.name.lower() in IGNORED_LABEL_FILES:
            continue
        label_index.setdefault(txt.stem, txt)
    return label_index


def normalized_label_lines(src_label: Path | None, remap_to_zero: bool) -> list[str]:
    if src_label is None or not src_label.exists():
        return []

    out_lines: list[str] = []
    for raw_line in src_label.read_text(encoding="utf-8", errors="ignore").splitlines():
        parts = raw_line.strip().split()
        if len(parts) < 5:
            continue
        if remap_to_zero:
            parts[0] = "0"
        out_lines.append(" ".join(parts[:5]))
    return out_lines


def split_group(items: list[dict], val_ratio: float) -> tuple[list[dict], list[dict]]:
    if len(items) <= 1:
        return items, []

    val_count = max(1, round(len(items) * val_ratio))
    val_count = min(val_count, len(items) - 1)
    return items[val_count:], items[:val_count]


def write_dataset_yaml(out_dir: Path, class_name: str) -> None:
    yaml_text = f"""train: images/train
val: images/val

names:
  0: {class_name}
"""
    (out_dir / "blood_ps.yaml").write_text(yaml_text, encoding="utf-8")


def main() -> None:
    args = parse_args()
    if not 0 < args.val_ratio < 1:
        raise ValueError(f"--val-ratio must be between 0 and 1, got {args.val_ratio}")

    project_root = Path(__file__).resolve().parents[1]
    raw_dir = project_root / "exports" / args.dataset
    out_dir = project_root / "data" / "yolo" / args.dataset

    if not raw_dir.exists():
        raise RuntimeError(f"Export directory not found: {raw_dir}")
    if out_dir.exists() and any(out_dir.iterdir()):
        if not args.overwrite and args.interactive:
            args.overwrite = read_choice(f"Output dataset already exists: {out_dir}. Overwrite it?", default=False)
        if args.overwrite:
            shutil.rmtree(out_dir)
        else:
            raise RuntimeError(f"Output dataset already exists. Use --overwrite to replace: {out_dir}")

    images = find_images(raw_dir)
    if not images:
        raise RuntimeError(f"No images found: {raw_dir}")

    label_index = build_label_index(raw_dir)
    rows: list[dict] = []
    for image in images:
        src_label = label_index.get(image.stem)
        label_lines = normalized_label_lines(src_label, remap_to_zero=not args.keep_class_ids)
        rows.append(
            {
                "image": image,
                "label": src_label,
                "label_lines": label_lines,
                "bbox_count": len(label_lines),
            }
        )

    rng = random.Random(args.seed)
    positives = [row for row in rows if row["bbox_count"] > 0]
    negatives = [row for row in rows if row["bbox_count"] == 0]
    rng.shuffle(positives)
    rng.shuffle(negatives)

    train_pos, val_pos = split_group(positives, args.val_ratio)
    train_neg, val_neg = split_group(negatives, args.val_ratio)
    split_rows = [("train", row) for row in train_pos + train_neg]
    split_rows.extend(("val", row) for row in val_pos + val_neg)
    split_rows.sort(key=lambda item: (item[0], item[1]["image"].name))

    manifest_rows = []
    for subset, row in split_rows:
        image = row["image"]
        dst_img = out_dir / "images" / subset / image.name
        dst_lbl = out_dir / "labels" / subset / f"{image.stem}.txt"

        dst_img.parent.mkdir(parents=True, exist_ok=True)
        dst_lbl.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(image, dst_img)
        dst_lbl.write_text("\n".join(row["label_lines"]) + ("\n" if row["label_lines"] else ""), encoding="utf-8")

        manifest_rows.append(
            {
                "subset": subset,
                "image": dst_img.relative_to(project_root).as_posix(),
                "label": dst_lbl.relative_to(project_root).as_posix(),
                "source_image": image.relative_to(project_root).as_posix(),
                "source_label": row["label"].relative_to(project_root).as_posix() if row["label"] else "",
                "bbox_count": row["bbox_count"],
            }
        )

    write_dataset_yaml(out_dir, args.class_name)

    with (out_dir / "manifest.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["subset", "image", "label", "source_image", "source_label", "bbox_count"],
        )
        writer.writeheader()
        writer.writerows(manifest_rows)

    stats = {
        "dataset": args.dataset,
        "class_name": args.class_name,
        "seed": args.seed,
        "val_ratio": args.val_ratio,
        "total_images": len(rows),
        "total_bboxes": sum(row["bbox_count"] for row in rows),
        "train_images": len(train_pos) + len(train_neg),
        "train_positive_images": len(train_pos),
        "train_bboxes": sum(row["bbox_count"] for row in train_pos),
        "val_images": len(val_pos) + len(val_neg),
        "val_positive_images": len(val_pos),
        "val_bboxes": sum(row["bbox_count"] for row in val_pos),
    }
    (out_dir / "dataset_stats.json").write_text(json.dumps(stats, indent=2), encoding="utf-8")

    print("done")
    print(f"dataset: {out_dir}")
    print(f"train images: {stats['train_images']} ({stats['train_positive_images']} positive)")
    print(f"val images: {stats['val_images']} ({stats['val_positive_images']} positive)")
    print(f"total boxes: {stats['total_bboxes']}")


if __name__ == "__main__":
    main()
