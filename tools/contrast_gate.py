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


def check_semantic_pairs(
    colors: dict[str, str],
    pairs: tuple[tuple[str, str, str, float], ...],
    *,
    prefix: str,
) -> list[str]:
    """Check a typed list of opaque native glyph/surface or status/card pairs.

    Args:
        colors: Semantic palette from the shared Fluent token contract.
        pairs: Name, foreground token, background token and minimum contrast.
        prefix: Stable diagnostic category for the native control.

    Returns:
        Missing, translucent or low-contrast color-pair diagnostics.
    """
    errors: list[str] = []
    for label, foreground, background, minimum in pairs:
        if foreground not in colors or background not in colors:
            errors.append(f"{label}: missing {prefix} color token")
            continue
        first = parse_color(colors[foreground])
        second = parse_color(colors[background])
        if first[0] != 255 or second[0] != 255:
            errors.append(f"{label}: {prefix} colors must be opaque")
            continue
        measured = ratio(first[1:], second[1:])
        print(f"{prefix}.{label}: {measured:.2f}:1 (need {minimum:.1f}:1)")
        if measured < minimum:
            errors.append(
                f"{label}: contrast {measured:.2f}:1 is below {minimum:.1f}:1"
            )
    return errors


def check_song_chip_contrast(colors: dict[str, str]) -> list[str]:
    """Require readable native chip glyphs and discernible muted/red boundaries.

    Args:
        colors: Opaque semantic colors rendered inside native Songs cards.

    Returns:
        Missing, translucent or low-contrast chip token pairs.
    """
    return check_semantic_pairs(colors, (
        ("full combo glyph", "cardBackground", "gold", 4.5),
        ("scored glyph", "cardBackground", "statusGreen", 4.5),
        ("no-score glyph", "textPrimary", "statusRed", 4.5),
        ("unavailable glyph", "textPrimary", "surfaceMuted", 4.5),
        ("unavailable outline", "textDisabled", "cardBackground", 3.0),
        ("no-score fill", "statusRed", "cardBackground", 3.0),
    ), prefix="song-chip")


def check_song_metadata_contrast(colors: dict[str, str]) -> list[str]:
    """Enforce text and status-edge bars for one native score-metadata row.

    Args:
        colors: Opaque generated Fluent colors rather than composited web frost.

    Returns:
        Every badge with insufficient text or essential fill contrast.
    """
    return check_semantic_pairs(colors, (
        ("easy glyph", "cardBackground", "diffPillEasy", 4.5),
        ("medium glyph", "textPrimary", "diffPillMedium", 4.5),
        ("hard glyph", "cardBackground", "diffPillHard", 4.5),
        ("expert glyph", "textPrimary", "diffPillExpert", 4.5),
        ("full combo label", "gold", "cardBackground", 4.5),
        ("top tier label", "gold", "cardBackground", 4.5),
        ("ordinary percentile label", "textSecondary", "surfaceMuted", 4.5),
        ("current season label", "surfaceSubtle", "textSecondary", 4.5),
        ("older season label", "textSecondary", "surfaceSubtle", 4.5),
        ("medium difficulty fill", "diffPillMedium", "cardBackground", 3.0),
        ("expert difficulty fill", "diffPillExpert", "cardBackground", 3.0),
    ), prefix="song-metadata")


def main() -> int:
    """Run text/art and chip contrast thresholds against native color tokens.

    Returns:
        Exit zero only if every listed exposed text semantic passes 4.5:1.
    """
    try:
        contract = json.loads(
            (ROOT / "contracts/fluent-tokens.json").read_text(encoding="utf-8")
        )
        errors = check_on_art(contract["colors"])
        errors.extend(check_song_chip_contrast(contract["colors"]))
        errors.extend(check_song_metadata_contrast(contract["colors"]))
    except (OSError, KeyError, ValueError) as error:
        print(f"Artwork contrast gate error: {error}", file=sys.stderr)
        return 2
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
