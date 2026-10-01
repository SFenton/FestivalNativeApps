#!/usr/bin/env python3
"""Generate the MSIX logo assets from the first-party FST icon.

Source: ``windows/store/fst-icon-512.png``, a copy of the web app's PWA icon
(``FortniteFestivalWeb/public/icons/fst-icon-512.png``, first-party artwork).
Output: ``windows/Festival.App/Assets/Store/*.png``, referenced by
``windows/Festival.App/Package.appxmanifest`` and packaged only in MSIX builds
(``-p:FstMsix=true``). MRT picks the ``scale-*``/``targetsize-*`` variant.

Usage::

    python3 tools/windows/store_assets.py            # regenerate (needs Pillow)
    python3 tools/windows/store_assets.py --check    # stdlib: every expected file exists at its size
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "windows" / "store" / "fst-icon-512.png"
OUTPUT = ROOT / "windows" / "Festival.App" / "Assets" / "Store"

#: Base asset name -> logical size (DIPs) at scale-100.
SCALED = {"Square44x44Logo": 44, "Square150x150Logo": 150, "StoreLogo": 50}
SCALES = (100, 200)
#: Taskbar/Start list icons drawn without a plate (``altform-unplated``).
TARGET_SIZES = (16, 24, 32, 48, 256)


def expected() -> dict[str, int]:
    """Return every output file name mapped to its square pixel size."""
    files = {f"{name}.scale-{scale}.png": size * scale // 100
             for name, size in SCALED.items() for scale in SCALES}
    for size in TARGET_SIZES:
        files[f"Square44x44Logo.targetsize-{size}_altform-unplated.png"] = size
    return files


def png_size(path: Path) -> tuple[int, int]:
    """Read a PNG's width and height from its IHDR chunk."""
    header = path.read_bytes()[:24]
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    return struct.unpack(">II", header[16:24])


def check() -> list[str]:
    """Return problems with the committed assets (empty when current)."""
    problems = []
    for name, size in expected().items():
        path = OUTPUT / name
        if not path.is_file():
            problems.append(f"missing {name}")
        elif png_size(path) != (size, size):
            problems.append(f"{name} is {png_size(path)}, expected {size}x{size}")
    extra = sorted(p.name for p in OUTPUT.glob("*.png") if p.name not in expected())
    problems += [f"unexpected {name}" for name in extra]
    return problems


def generate() -> None:
    """Resize the source icon into every expected asset (Lanczos)."""
    from PIL import Image

    OUTPUT.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE).convert("RGBA")
    for name, size in expected().items():
        source.resize((size, size), Image.Resampling.LANCZOS).save(OUTPUT / name, optimize=True)


def main(argv: list[str] | None = None) -> int:
    """Generate or check the assets; returns the exit code."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    if args.check:
        problems = check()
        for problem in problems:
            print(problem, file=sys.stderr)
        return 1 if problems else 0
    generate()
    print(f"wrote {len(expected())} assets to {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
