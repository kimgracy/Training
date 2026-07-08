from __future__ import annotations

import argparse
import csv
import json
import random
import re
import shutil
import sys
from pathlib import Path


IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".tif", ".tiff"}
IGNORED_LABEL_FILES = {"train.txt", "val.txt", "test.txt", "obj.names", "obj.data"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare a YOLO detection dataset.")
    parser.add_argument("--dataset", default="", help="Dataset version under exports/. Required for non-interactive runs.")
    parser.add_argument("--export-dir", default="", help="Explicit CVAT export directory. Defaults to exports/<dataset>.")
    parser.add_argument("--output-dir", default="", help="Explicit prepared YOLO output directory. Defaults to data/yolo/<dataset>.")
    parser.add_argument("--val-ratio", type=float, default=0.2, help="Validation split ratio.")
    parser.add_argument("--seed", type=int, default=42, help="Random seed for splitting.")
    parser.add_argument("--class-name", default="ps_particle", help="Single class name.")
    parser.add_argument("--class-names", nargs="+", default=[], help="Class names in YOLO class ID order.")
    parser.add_argument("--class-config", default="", help="Dataset class config YAML with a names block.")
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
        if sys.stdin.isatty():
            args.dataset = read_required_str("Dataset")
        else:
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
    class_names_text = read_str_with_default("Class names, comma-separated", args.class_name)
    args.class_names = [name.strip() for name in class_names_text.split(",") if name.strip()]
    if len(args.class_names) == 1:
        args.class_name = args.class_names[0]
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


def normalized_label_lines(src_label: Path | None, remap_to_zero: bool, class_count: int) -> tuple[list[str], dict[int, int]]:
    if src_label is None or not src_label.exists():
        return [], {}

    out_lines: list[str] = []
    class_counts: dict[int, int] = {}
    for raw_line in src_label.read_text(encoding="utf-8", errors="ignore").splitlines():
        parts = raw_line.strip().split()
        if len(parts) < 5:
            continue
        try:
            class_id = int(parts[0])
        except ValueError:
            continue

        if remap_to_zero:
            class_id = 0
            parts[0] = "0"
        elif class_id < 0 or class_id >= class_count:
            raise ValueError(f"Class ID {class_id} in {src_label} is outside configured range 0..{class_count - 1}")

        class_counts[class_id] = class_counts.get(class_id, 0) + 1
        out_lines.append(" ".join(parts[:5]))
    return out_lines, class_counts


def split_group(items: list[dict], val_ratio: float) -> tuple[list[dict], list[dict]]:
    if len(items) <= 1:
        return items, []

    val_count = max(1, round(len(items) * val_ratio))
    val_count = min(val_count, len(items) - 1)
    return items[val_count:], items[:val_count]


def quote_yaml_value(value: str) -> str:
    if re.search(r"[:#\[\]{},&*?|\-<>=!%@`]", value):
        return json.dumps(value)
    return value


def write_dataset_yaml(out_dir: Path, class_names: list[str]) -> None:
    names_text = "\n".join(f"  {idx}: {quote_yaml_value(name)}" for idx, name in enumerate(class_names))
    yaml_text = f"""train: images/train
val: images/val

names:
{names_text}
"""
    (out_dir / "dataset.yaml").write_text(yaml_text, encoding="utf-8")
    (out_dir / "blood_ps.yaml").write_text(yaml_text, encoding="utf-8")


def resolve_project_path(project_root: Path, value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return project_root / path


def manifest_path(path: Path, project_root: Path) -> str:
    try:
        return path.relative_to(project_root).as_posix()
    except ValueError:
        return path.as_posix()


def strip_yaml_value(value: str) -> str:
    value = value.strip()
    if "#" in value:
        value = value.split("#", 1)[0].strip()
    return value.strip().strip('"').strip("'")


def parse_inline_names(value: str) -> list[str]:
    value = value.strip()
    if not (value.startswith("[") and value.endswith("]")):
        return []
    inner = value[1:-1].strip()
    if not inner:
        return []
    return [strip_yaml_value(part) for part in inner.split(",") if strip_yaml_value(part)]


def read_class_names_from_config(config_path: Path) -> list[str]:
    if not config_path.exists():
        raise RuntimeError(f"Class config not found: {config_path}")

    names: dict[int, str] = {}
    list_names: list[str] = []
    in_names = False

    for line in config_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        if not in_names:
            match = re.match(r"^\s*names\s*:\s*(.*)$", line)
            if not match:
                continue
            tail = match.group(1).strip()
            inline_names = parse_inline_names(tail)
            if inline_names:
                return inline_names
            in_names = True
            continue

        if line.strip() and not line.startswith((" ", "\t", "-")):
            break

        indexed = re.match(r"^\s*(\d+)\s*:\s*(.+?)\s*$", line)
        if indexed:
            names[int(indexed.group(1))] = strip_yaml_value(indexed.group(2))
            continue

        listed = re.match(r"^\s*-\s*(.+?)\s*$", line)
        if listed:
            list_names.append(strip_yaml_value(listed.group(1)))

    if names:
        max_index = max(names)
        return [names.get(idx, f"class_{idx}") for idx in range(max_index + 1)]
    if list_names:
        return list_names

    raise RuntimeError(f"No names block found in class config: {config_path}")


def resolve_class_names(args: argparse.Namespace, project_root: Path) -> list[str]:
    if args.class_config:
        class_config = resolve_project_path(project_root, args.class_config)
        return read_class_names_from_config(class_config)

    if args.class_names:
        return [name.strip() for name in args.class_names if name.strip()]

    return [args.class_name.strip()]


def main() -> None:
    args = parse_args()
    if not 0 < args.val_ratio < 1:
        raise ValueError(f"--val-ratio must be between 0 and 1, got {args.val_ratio}")

    project_root = Path(__file__).resolve().parents[1]
    raw_dir = resolve_project_path(project_root, args.export_dir) if args.export_dir else project_root / "exports" / args.dataset
    out_dir = resolve_project_path(project_root, args.output_dir) if args.output_dir else project_root / "data" / "yolo" / args.dataset
    class_names = resolve_class_names(args, project_root)
    if not class_names:
        raise ValueError("At least one class name is required.")

    remap_to_zero = not args.keep_class_ids and len(class_names) == 1

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
    total_class_counts = {idx: 0 for idx in range(len(class_names))}
    for image in images:
        src_label = label_index.get(image.stem)
        label_lines, class_counts = normalized_label_lines(src_label, remap_to_zero=remap_to_zero, class_count=len(class_names))
        for class_id, count in class_counts.items():
            total_class_counts[class_id] = total_class_counts.get(class_id, 0) + count
        rows.append(
            {
                "image": image,
                "label": src_label,
                "label_lines": label_lines,
                "bbox_count": len(label_lines),
                "class_counts": class_counts,
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
                "image": manifest_path(dst_img, project_root),
                "label": manifest_path(dst_lbl, project_root),
                "source_image": manifest_path(image, project_root),
                "source_label": manifest_path(row["label"], project_root) if row["label"] else "",
                "bbox_count": row["bbox_count"],
            }
        )

    write_dataset_yaml(out_dir, class_names)

    with (out_dir / "manifest.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["subset", "image", "label", "source_image", "source_label", "bbox_count"],
        )
        writer.writeheader()
        writer.writerows(manifest_rows)

    stats = {
        "dataset": args.dataset,
        "class_name": class_names[0],
        "class_names": class_names,
        "class_counts": {str(class_id): total_class_counts.get(class_id, 0) for class_id in range(len(class_names))},
        "keep_class_ids": not remap_to_zero,
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
