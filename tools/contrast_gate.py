"""Enforce WCAG text contrast over the brightest possible dimmed album cover."""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

from tools.generate_tokens import parse_color

ROOT = Path(__file__).resolve().parents[1]
ON_ART_TEXT = ("textPrimary", "textSecondary", "gold")


def luminance(rgb: tuple[int, int, int]) -> float:
    """Convert opaque sRGB bytes to WCAG relative luminance.

    Args:
        rgb: Red, green, and blue bytes in sRGB.

    Returns:
        Linear-light luminance from zero through one.
    """
    channels = [component / 255 for component in rgb]
    linear = [
        value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
        for value in channels
    ]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def ratio(first: tuple[int, int, int], second: tuple[int, int, int]) -> float:
    """Measure WCAG 2.x contrast of two opaque sRGB colors.

    Args:
        first: Foreground RGB bytes.
        second: Background RGB bytes.

    Returns:
        Light-to-dark luminance ratio.
    """
    values = sorted((luminance(first), luminance(second)))
    return (values[1] + 0.05) / (values[0] + 0.05)


def check_on_art(
    colors: dict[str, str], *, dim_opacity: float = 0.7
) -> list[str]:
    """Reject directly-on-art text below 4.5:1 even over a pure-white cover.

    Args:
        colors: Shared Fluent semantic palette from the versioned token contract.
        dim_opacity: Black background dim applied to the native art layer.

    Returns:
        All absent, translucent, or insufficiently contrasting text colors.

    Raises:
        ValueError: If the dim opacity is outside the valid finite range.
    """
    if not math.isfinite(dim_opacity) or not 0 <= dim_opacity <= 1:
        raise ValueError("Artwork dim opacity must be finite and between zero and one")
    brightest = math.ceil(255 * (1 - dim_opacity))
    background = (brightest, brightest, brightest)
    errors: list[str] = []
    for name in ON_ART_TEXT:
        if name not in colors:
            errors.append(f"{name}: missing text color")
            continue
        alpha, red, green, blue = parse_color(colors[name])
        if alpha != 255:
            errors.append(f"{name}: artwork text must be opaque")
            continue
        measured = ratio((red, green, blue), background)
        print(f"artwork.{name}: {measured:.2f}:1 against white cover (need 4.5:1)")
        if measured < 4.5:
            errors.append(f"{name}: contrast {measured:.2f}:1 is below 4.5:1")
    return errors


def main() -> int:
    """Run the source-backed contrast threshold against generated native tokens.

    Returns:
        Exit zero only if every listed exposed text semantic passes 4.5:1.
    """
    try:
        contract = json.loads(
            (ROOT / "contracts/fluent-tokens.json").read_text(encoding="utf-8")
        )
        errors = check_on_art(contract["colors"])
    except (OSError, KeyError, ValueError) as error:
        print(f"Artwork contrast gate error: {error}", file=sys.stderr)
        return 2
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
