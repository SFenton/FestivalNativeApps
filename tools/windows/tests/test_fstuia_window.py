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
        # Every AsWindow() is inside TopWindow, MinimizedWindow or Reacquire (from a guarded window's own non-zero
        # handle), so no command gets an unguarded target.
        self.assertEqual(3, len(re.findall(r"\.AsWindow\(\)", self.source)))
        for lookup in ("private Window? TopWindow(", "private Window? MinimizedWindow("):
            with self.subTest(lookup=lookup):
                self.assertIn(".AsWindow()", self.body(lookup, ".FirstOrDefault()"))
        reacquire = self.body("private Window Reacquire(", "\n    }\n")
        self.assertIn("if (hwnd == IntPtr.Zero || automation.FromHandle(hwnd) is not { } fresh) return window;", reacquire)
        self.assertIn("fresh.AsWindow()", reacquire)


class ReacquireWindowSourceTests(unittest.TestCase):
    """A search re-acquires its window from the handle after a transient error or a run of misses (issue #676).

    ``releases/2610.19``'s ``history-anonymous`` invoked the History header's song, then found no Song Detail title for
    15 s with no UIA error left: the window provider rebuilds during that page swap (E_UNEXPECTED, #674), and the
    window element the drive started with can keep searching the old provider.
    """

    @classmethod
    def setUpClass(cls):
        cls.source = (u.DRIVER_DIR / "Program.cs").read_text(encoding="utf-8")
        cls.find = cls.source.split("internal AutomationElement Find(", 1)[1].split("\n    }\n", 1)[0]

    def test_find_searches_the_reacquired_root(self):
        self.assertIn("root = Reacquire(root);", self.find)
        self.assertIn("search.FindFirstDescendant(condition)", self.find)
        self.assertNotIn("window.FindFirstDescendant", self.find)

    def test_a_transient_error_reacquires_on_the_next_search(self):
        catch = self.find.split("catch (Exception error) when (IsTransientUia(error)", 1)[1]
        self.assertIn("reacquireAt = DateTime.UtcNow;", catch.split("continue;", 1)[0])

    def test_the_timeout_says_what_was_last_seen(self):
        self.assertIn('$"no on-screen element {label} ({seen})"', self.find)

    def test_drive_adopts_the_reacquired_window(self):
        self.assertIn("if (reacquired is not null) (window, reacquired) = (reacquired, null);", self.source)

    def test_a_stale_window_reacquires_from_the_cached_handle(self):
        # #677: the stale window element threw a raw UIA_E_ELEMENTNOTAVAILABLE reading its own handle, which aborted the
        # step; the drive now caches the handle at its start and Reacquire falls back to it.
        drive = self.source.split("private JsonNode Drive(", 1)[1].split("foreach (var node in steps)", 1)[0]
        self.assertIn("windowHandle = HandleOf(window);", drive)
        reacquire = self.source.split("private Window Reacquire(", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("var hwnd = HandleOf(window);", reacquire)
        self.assertIn("if (hwnd == IntPtr.Zero) hwnd = windowHandle;", reacquire)
        self.assertNotIn("Properties.NativeWindowHandle", reacquire)
        handle_of = self.source.split("private static IntPtr HandleOf(", 1)[1].split("\n    }\n", 1)[0]
        self.assertIn("catch (Exception error) when (IsTransientUia(error))", handle_of)
        self.assertIn("return IntPtr.Zero;", handle_of)


if __name__ == "__main__":
    unittest.main()
