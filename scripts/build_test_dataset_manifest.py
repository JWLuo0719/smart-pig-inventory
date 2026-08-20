#!/usr/bin/env python3
"""Create a local, reproducible manifest for an external YOLO dataset.

The script never copies, moves, rewrites, or uploads source images or labels.
Its output belongs in test-assets/generated/, which is ignored by Git.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from datetime import UTC, datetime
from pathlib import Path

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def count_yolo_objects(label_path: Path) -> tuple[int, list[str]]:
    if not label_path.exists():
        return 0, ["missing_label"]

    issues: list[str] = []
    count = 0
    for number, raw_line in enumerate(label_path.read_text(encoding="utf-8").splitlines(), start=1):
        if not raw_line.strip():
            continue
        parts = raw_line.split()
        if len(parts) != 5:
            issues.append(f"invalid_yolo_columns:line_{number}")
            continue
        try:
            class_id = int(parts[0])
            coordinates = [float(value) for value in parts[1:]]
        except ValueError:
            issues.append(f"invalid_yolo_number:line_{number}")
            continue
        if class_id < 0 or any(value < 0 or value > 1 for value in coordinates):
            issues.append(f"invalid_yolo_range:line_{number}")
            continue
        count += 1
    return count, issues


def inspect_split(source: Path, split: str) -> tuple[list[dict], list[dict]]:
    image_directory = source / split / "images"
    label_directory = source / split / "labels"
    records: list[dict] = []
    problems: list[dict] = []
    if not image_directory.is_dir():
        return records, [{"split": split, "issue": "missing_images_directory"}]

    for image_path in sorted(
        (path for path in image_directory.rglob("*") if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES),
        key=lambda path: path.as_posix(),
    ):
        relative_image = image_path.relative_to(source).as_posix()
        label_path = label_directory / image_path.relative_to(image_directory).with_suffix(".txt")
        object_count, label_issues = count_yolo_objects(label_path)
        record = {
            "split": split,
            "image": relative_image,
            "label": label_path.relative_to(source).as_posix(),
            "sha256": sha256_file(image_path),
            "expected_pig_count": object_count,
        }
        records.append(record)
        for issue in label_issues:
            problems.append({"image": relative_image, "issue": issue})
    return records, problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path, help="Read-only YOLO dataset root")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("test-assets/generated/yolo-source-manifest.json"),
        help="Ignored local output JSON path",
    )
    parser.add_argument("--max-fixtures", type=int, default=12, help="Candidate test images to list from test split")
    args = parser.parse_args()

    source = args.source.resolve()
    if not source.is_dir():
        parser.error(f"source directory does not exist: {source}")

    all_records: list[dict] = []
    all_problems: list[dict] = []
    for split in ("train", "val", "test"):
        records, problems = inspect_split(source, split)
        all_records.extend(records)
        all_problems.extend(problems)

    per_split = {
        split: {
            "images": sum(record["split"] == split for record in all_records),
            "expected_pigs": sum(record["expected_pig_count"] for record in all_records if record["split"] == split),
        }
        for split in ("train", "val", "test")
    }
    fixture_candidates = sorted(
        (record for record in all_records if record["split"] == "test"),
        key=lambda record: (-record["expected_pig_count"], record["image"]),
    )[: args.max_fixtures]
    source_digest = hashlib.sha256(
        "\n".join(f"{record['image']}:{record['sha256']}" for record in all_records).encode("utf-8")
    ).hexdigest()
    manifest = {
        "schema_version": 1,
        "created_at_utc": datetime.now(UTC).isoformat(),
        "source_dataset": str(source),
        "source_digest_sha256": source_digest,
        "policy": "Source images and labels are read-only; this manifest contains metadata only and is Git-ignored.",
        "summary": {"splits": per_split, "images": len(all_records), "expected_pigs": sum(record["expected_pig_count"] for record in all_records)},
        "integrity_problems": all_problems,
        "fixture_candidates": fixture_candidates,
        "records": all_records,
    }
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(output), "summary": manifest["summary"], "problems": len(all_problems)}, ensure_ascii=False))
    return 1 if all_problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
