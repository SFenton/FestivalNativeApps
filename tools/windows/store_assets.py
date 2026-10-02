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
    python3 tools/windows/store_assets.py --listing ~/Desktop/festival-windows-store   # Partner Center art

``--listing`` writes the Store listing images (not committed): 1:1 box art 1080/2160, 2:3 poster
720x1080/1440x2160 and the 300/150/71 px Store display images. They are drawn from the 1024 px iOS app icon (same artwork):
its diagonal gradient is rebuilt at the target size and the FST badge composited unscaled where possible, so
the poster extends the background instead of padding a square.
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


LISTING_SOURCE = ROOT / "apple" / "Apps" / "iOS" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
#: Partner Center listing image -> (width, height).
LISTING = {
    "box-art-1080x1080.png": (1080, 1080),
    "box-art-2160x2160.png": (2160, 2160),
    "poster-720x1080.png": (720, 1080),
    "poster-1440x2160.png": (1440, 2160),
    "app-tile-icon-300x300.png": (300, 300),
    "store-display-150x150.png": (150, 150),
    "store-display-71x71.png": (71, 71),
}


#: Badge width as a share of the tile for Store display images of 150 px and below.
SMALL_BADGE_RATIO = 0.82


def _gradient_lut(icon) -> list[tuple[int, int, int]]:
    """Background colour along the icon's diagonal (t = (x/w + y/h) / 2), from its left and bottom edges."""
    w, h = icon.size
    left = [icon.getpixel((0, y))[:3] for y in range(h)]
    bottom = [icon.getpixel((x, h - 1))[:3] for x in range(w)]
    return left + bottom[1:]


def _background(size: tuple[int, int], lut: list[tuple[int, int, int]]):
    from PIL import Image

    w, h = size
    out = Image.new("RGB", size)
    last = len(lut) - 1
    out.putdata([lut[round((x / (w - 1) + y / (h - 1)) / 2 * last)] for y in range(h) for x in range(w)])
    return out


def listing_art(out_dir: Path) -> list[Path]:
    """Write the Partner Center listing images into ``out_dir``; returns the written paths."""
    from PIL import Image, ImageChops, ImageFilter

    icon = Image.open(LISTING_SOURCE).convert("RGB")
    lut = _gradient_lut(icon)
    plain = _background(icon.size, lut)
    diff = ImageChops.difference(icon, plain).convert("L")
    mask = diff.point(lambda v: 255 if v > 24 else 0).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(2))
    box = mask.getbbox()
    badge, badge_mask = icon.crop(box), mask.crop(box)
    badge_ratio = badge.width / icon.width
    out_dir.mkdir(parents=True, exist_ok=True)
    written = []
    for name, (w, h) in LISTING.items():
        canvas = _background((w, h), lut)
        # Small tiles enlarge the badge so "FST" stays legible.
        target = round(min(w, h) * (max(badge_ratio, SMALL_BADGE_RATIO) if max(w, h) <= 150 else badge_ratio))
        scale = target / badge.width
        size = (target, round(badge.height * scale))
        piece = badge.resize(size, Image.Resampling.LANCZOS)
        piece_mask = badge_mask.resize(size, Image.Resampling.LANCZOS)
        canvas.paste(piece, ((w - size[0]) // 2, (h - size[1]) // 2), piece_mask)
        path = out_dir / name
        canvas.save(path, optimize=True)
        written.append(path)
    return written


def main(argv: list[str] | None = None) -> int:
    """Generate or check the assets; returns the exit code."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--listing", type=Path, help="write Partner Center listing images to this directory")
    args = parser.parse_args(argv)
    if args.listing:
        for path in listing_art(args.listing.expanduser()):
            print(path)
        return 0
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
