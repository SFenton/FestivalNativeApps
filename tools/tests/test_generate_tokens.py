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


if __name__ == "__main__":
    unittest.main()
