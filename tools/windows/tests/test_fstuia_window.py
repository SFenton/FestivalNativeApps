"""``FstUia``'s target-window lookup only returns elements backed by a native window (issue #661).

``releases/2610.12``'s ``song-detail-loading-verification`` (compact) died with "The requested property
'NativeWindowHandle [#30020]' is not supported": ``TopWindow`` picked a top-level element of the app's process that has
no HWND (a WinUI windowed popup's content root), and every command reads the target's handle unguarded. All commands
get their target from ``TopWindow`` (through ``WaitForWindow``) or ``MinimizedWindow``, so pinning both covers them.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import re
import unittest

from tools.windows import uiwin as u


class TargetWindowSourceTests(unittest.TestCase):
    """Window lookups skip top-level elements without a ``NativeWindowHandle``."""

    @classmethod
    def setUpClass(cls):
        cls.source = (u.DRIVER_DIR / "Program.cs").read_text(encoding="utf-8")

    def body(self, start: str, end: str) -> str:
        return self.source.split(start, 1)[1].split(end, 1)[0]

    def test_top_window_requires_a_native_window(self):
        top = self.body("private Window? TopWindow(", "private Window FindWindow(")
        self.assertIn("&& HasNativeWindow(e))", top)
        helper = self.body("private static bool HasNativeWindow(", ";")
        self.assertIn("NativeWindowHandle.ValueOrDefault != IntPtr.Zero", helper)

    def test_minimized_window_requires_a_native_window(self):
        minimized = self.body("private Window? MinimizedWindow(", ".FirstOrDefault();")
        self.assertIn("NativeWindowHandle.ValueOrDefault is var hwnd && hwnd != IntPtr.Zero", minimized)

    def test_windows_come_only_from_the_guarded_lookups(self):
        # Every AsWindow() is inside TopWindow or MinimizedWindow, so no command gets an unguarded target.
        self.assertEqual(2, len(re.findall(r"\.AsWindow\(\)", self.source)))
        for lookup in ("private Window? TopWindow(", "private Window? MinimizedWindow("):
            with self.subTest(lookup=lookup):
                self.assertIn(".AsWindow()", self.body(lookup, ".FirstOrDefault()"))


if __name__ == "__main__":
    unittest.main()
