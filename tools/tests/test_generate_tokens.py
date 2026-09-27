"""Cross-language color generation must preserve the source's sRGB components."""

import unittest

from tools.generate_tokens import parse_color, render_kotlin, render_swift, render_xaml


class TokenGenerationTests(unittest.TestCase):
    """Detect color-channel and alpha mismatches before native builds."""

    def test_hex_and_translucent_surface(self):
        """Brand dark and frosted semantics encode once to three platforms."""
        colors = {
            "appBackground": parse_color("#1A0830"),
            "surfaceFrosted": parse_color("rgba(18,24,38,0.78)"),
        }
        self.assertEqual(colors["appBackground"], (255, 26, 8, 48))
        self.assertEqual(colors["surfaceFrosted"], (199, 18, 24, 38))
        self.assertIn("Color(0xFF1A0830)", render_kotlin(colors))
        self.assertIn("red: 26.0 / 255", render_swift(colors))
        self.assertIn("#C7121826", render_xaml(colors))

    def test_invalid_colors_are_errors(self):
        """Unsupported CSS formats cannot silently produce an incorrect theme."""
        for value in ("#ABC", "#GGGGGG", "rgba(256,2,3,0.5)", "transparent"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                parse_color(value)

    def test_chip_status_strokes_generate_identically_for_three_platforms(self):
        """A missing muted/stroke token must not make native platforms diverge."""
        colors = {
            "goldStroke": parse_color("#CFA500"),
            "statusGreenStroke": parse_color("#1E7F46"),
            "statusRedStroke": parse_color("#8B0000"),
            "surfaceMuted": parse_color("#223047"),
            "textDisabled": parse_color("#607089"),
        }
        self.assertIn("Color(0xFF1E7F46)", render_kotlin(colors))
        self.assertIn("red: 207.0 / 255", render_swift(colors))
        self.assertIn('FSTTextDisabledColor">#FF607089', render_xaml(colors))

    def test_metadata_difficulty_and_surface_tokens_share_exact_channels(self):
        """Contrast-safe pill colors stay identical in Apple, Android and WinUI."""
        colors = {
            "diffPillEasy": parse_color("#2ECC71"),
            "diffPillMedium": parse_color("#C62828"),
            "diffPillHard": parse_color("#2D82E6"),
            "diffPillExpert": parse_color("#7C3AED"),
            "surfaceSubtle": parse_color("#162133"),
            "borderSubtle": parse_color("#1E2A3A"),
        }
        self.assertIn("Color(0xFF2D82E6)", render_kotlin(colors))
        self.assertIn("red: 22.0 / 255", render_swift(colors))
        self.assertIn('FSTDiffPillExpertColor">#FF7C3AED', render_xaml(colors))


if __name__ == "__main__":
    unittest.main()
