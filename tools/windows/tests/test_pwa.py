"""Pure logic of ``tools/windows/pwa.py`` (installed-PWA lab in Edge)."""

import unittest

from tools.windows import pwa


class WindowsPwaTests(unittest.TestCase):
    """Window presets, capture arguments and step parsing."""

    WORK = (2560, 0, 2560, 1392)  # second monitor, DIPs

    def test_size_presets_centre_and_clamp(self):
        self.assertEqual(pwa.preset_bounds("compact", self.WORK),
                         {"left": 2560 + 1030, "top": 296, "width": 500, "height": 800})
        tablet = pwa.preset_bounds("portrait-tablet", self.WORK)
        self.assertEqual((tablet["width"], tablet["height"], tablet["top"]), (800, 1280, 56))
        self.assertIsNone(pwa.clamp_note("portrait-tablet", tablet))
        small = pwa.preset_bounds("portrait-tablet", (0, 0, 1000, 700))
        self.assertIn("clamped", pwa.clamp_note("portrait-tablet", small))
        self.assertEqual(pwa.preset_bounds("640x480", self.WORK)["width"], 640)

    def test_state_and_snap_presets(self):
        self.assertEqual(pwa.preset_bounds("maximized", self.WORK), {"windowState": "maximized"})
        self.assertEqual(pwa.preset_bounds("full-screen", self.WORK),
                         {"windowState": "fullscreen"})
        self.assertEqual(pwa.preset_bounds("snap-right", self.WORK),
                         {"left": 3840, "top": 0, "width": 1280, "height": 1392})
        with self.assertRaises(ValueError):
            pwa.preset_bounds("huge", self.WORK)

    def test_gdigrab_args_use_even_sizes(self):
        args = pwa.gdigrab_args((10, 20, 765, 1211), 30)
        self.assertIn("754x1190", args)
        self.assertEqual(args[-2:], ["-i", "desktop"])

    def test_lab_monitor_prefers_secondary(self):
        mons = [{"primary": True, "device": "1"}, {"primary": False, "device": "2"}]
        self.assertEqual(pwa.lab_monitor(mons)["device"], "2")
        self.assertEqual(pwa.lab_monitor(mons[:1])["device"], "1")

    def test_drive_steps(self):
        steps = pwa.parse_drive_steps("resize:wide; shot:{out}/a.png; back", None, {"out": "o"})
        self.assertEqual(steps, [("resize", "wide", False), ("shot", "o/a.png", False),
                                 ("back", "", False)])
        with self.assertRaises(ValueError):
            pwa.parse_drive_steps("resize:huge", None)


if __name__ == "__main__":
    unittest.main()
