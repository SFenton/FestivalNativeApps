"""Exercise the exact WCAG 4.5:1 gate for text drawn over song art."""

import json
import unittest

from tools.contrast_gate import (
    ROOT, check_on_art, check_song_chip_contrast, check_song_metadata_contrast, ratio,
)


class ArtworkContrastTests(unittest.TestCase):
    """Keep directly-on-art tokens legible on a worst-case white cover."""

    def setUp(self):
        """Read the same semantic palette used by every native platform."""
        contract = json.loads(
            (ROOT / "contracts/fluent-tokens.json").read_text(encoding="utf-8")
        )
        self.colors = contract["colors"]

    def test_exposed_text_meets_white_cover_bar(self):
        """Primary, secondary and gold content pass 4.5:1 at 0.7 dim."""
        self.assertEqual(check_on_art(self.colors), [])

    def test_muted_and_blue_must_not_replace_text_on_art(self):
        """The source's muted and blue tokens fail without an opaque card."""
        for replacement in ("textMuted", "accentBlue"):
            with self.subTest(replacement=replacement):
                colors = dict(self.colors, textSecondary=self.colors[replacement])
                self.assertTrue(any(
                    error.startswith("textSecondary: contrast")
                    for error in check_on_art(colors)
                ))

    def test_invalid_dim_and_exact_ratio(self):
        """Do not silently treat an invalid dim as a passing white surface."""
        with self.assertRaisesRegex(ValueError, "dim opacity"):
            check_on_art(self.colors, dim_opacity=float("nan"))
        self.assertEqual(ratio((255, 255, 255), (0, 0, 0)), 21.0)

    def test_native_chip_statuses_need_readable_marks_and_outlines(self):
        """The solid-card baseline gates glyphs at 4.5 and status edges at 3.0."""
        self.assertEqual(check_song_chip_contrast(self.colors), [])
        for name, value, failing in (
            ("gold", "#0B1220", "full combo glyph"),
            ("statusRed", "#FFD700", "no-score glyph"),
            ("textDisabled", "#223047", "unavailable outline"),
        ):
            with self.subTest(name=name):
                modified = dict(self.colors, **{name: value})
                self.assertTrue(any(
                    error.startswith(failing + ": contrast")
                    for error in check_song_chip_contrast(modified)
                ))
        self.assertTrue(any(
            "must be opaque" in error
            for error in check_song_chip_contrast(
                dict(self.colors, statusGreen="rgba(46,204,113,0.5)")
            )
        ))

    def test_metadata_badges_need_readable_game_difficulty_and_tiers(self):
        """White Easy/Hard glyphs cannot slip into opaque native pills."""
        self.assertEqual(check_song_metadata_contrast(self.colors), [])
        for token, replacement, issue in (
            ("diffPillEasy", "#0B1220", "easy glyph"),
            ("diffPillMedium", "#FFD700", "medium glyph"),
            ("diffPillHard", "#0B1220", "hard glyph"),
            ("textSecondary", "#162133", "current season label"),
        ):
            with self.subTest(token=token):
                changed = dict(self.colors, **{token: replacement})
                self.assertTrue(any(
                    problem.startswith(issue + ": contrast")
                    for problem in check_song_metadata_contrast(changed)
                ))


if __name__ == "__main__":
    unittest.main()
