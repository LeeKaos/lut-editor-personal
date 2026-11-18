#!/usr/bin/env python3
"""Move source .cube LUTs outside the app bundle and compile compact runtime LUTs.

Run before building the iOS target. The app bundle stores each channel as IEEE
754 binary16; the original .cube files remain in LUTSource for editing/export.
"""

from __future__ import annotations

import math
import shutil
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESOURCE_DIR = ROOT / "LumaGrade" / "LUTs"
SOURCE_DIR = ROOT / "LUTSource"
MAGIC = b"LUTF"


def migrate_sources() -> None:
    cube_files = sorted(RESOURCE_DIR.rglob("*.cube"))
    if not cube_files:
        return
    for source in cube_files:
        relative = source.relative_to(RESOURCE_DIR)
        destination = SOURCE_DIR / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(source), str(destination))


def compile_cube(source: Path, output: Path) -> None:
    dimension: int | None = None
    values: list[float] = []
    for raw_line in source.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        columns = line.split()
        if columns[0] == "LUT_3D_SIZE":
            dimension = int(columns[1])
            continue
        if columns[0] in {"TITLE", "DOMAIN_MIN", "DOMAIN_MAX"}:
            continue
        if len(columns) == 3:
            values.extend(float(component) for component in columns)

    if dimension is None or len(values) != dimension**3 * 3:
        raise ValueError(f"Invalid 3D LUT: {source}")
    if not all(math.isfinite(value) for value in values):
        raise ValueError(f"Non-finite LUT value: {source}")

    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as stream:
        stream.write(MAGIC)
        stream.write(struct.pack("<I", dimension))
        for value in values:
            stream.write(struct.pack("<e", value))


def main() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    migrate_sources()
    sources = sorted(SOURCE_DIR.rglob("*.cube"))
    if not sources:
        raise SystemExit(f"No source .cube files found in {SOURCE_DIR}")

    expected: set[Path] = set()
    for source in sources:
        relative = source.relative_to(SOURCE_DIR).with_suffix(".lutf")
        output = RESOURCE_DIR / relative
        compile_cube(source, output)
        expected.add(output.resolve())

    for stale in RESOURCE_DIR.rglob("*.lutf"):
        if stale.resolve() not in expected:
            stale.unlink()

    total = sum(path.stat().st_size for path in RESOURCE_DIR.rglob("*.lutf"))
    print(f"Compiled {len(sources)} LUTs to {total / 1_000_000:.1f} MB of app resources")


if __name__ == "__main__":
    main()
