"""Every iOS UITest launch must go through the shared FestivalApp helper."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UI_TEST_DIR = ROOT / "apple/Apps/iOSUITests"
HELPER_FILE = UI_TEST_DIR / "FestivalApp.swift"

# A real construction is always an assignment (`let app = XCUIApplication()`);
# matching only that shape (not a bare substring) keeps this from tripping on
# `FestivalApp.swift`'s own doc comment, which mentions the literal name in
# prose without constructing anything. Outside the helper, any construction
# means a journey built its own launch environment by hand — which is exactly
# how more than one journey forgot `FST_DEBUG_STILL_BACKGROUND=1` and hung the
# shared simulator's XCUITest lock (see `FestivalApp.swift`'s doc comment and
# `.agents/testing/apple/xcuitest.md`).
CONSTRUCTOR = re.compile(r"=\s*XCUIApplication\(\)")


class LaunchHelperTests(unittest.TestCase):
    """Fail closed if a new or edited journey bypasses the shared launch helper."""

    def test_helper_file_exists_and_sets_the_still_background_default(self):
        """The helper itself must be the one place defaulting the flag."""
        self.assertTrue(HELPER_FILE.is_file(), f"missing {HELPER_FILE}")
        source = HELPER_FILE.read_text(encoding="utf-8")
        self.assertIn("enum FestivalApp", source)
        self.assertIn('"FST_DEBUG_STILL_BACKGROUND": "1"', source)
        self.assertEqual(len(CONSTRUCTOR.findall(source)), 1)

    def test_no_other_ui_test_file_constructs_xcuiapplication_directly(self):
        """Every journey launches through FestivalApp.makeApp/launch, not directly."""
        self.assertTrue(UI_TEST_DIR.is_dir(), f"missing {UI_TEST_DIR}")
        offenders: dict[str, list[int]] = {}
        checked = 0
        for path in sorted(UI_TEST_DIR.glob("*.swift")):
            if path == HELPER_FILE:
                continue
            checked += 1
            lines = path.read_text(encoding="utf-8").splitlines()
            hits = [
                number for number, line in enumerate(lines, start=1)
                if CONSTRUCTOR.search(line)
            ]
            if hits:
                offenders[path.name] = hits
        self.assertGreater(checked, 0, "expected to scan at least one journey file")
        self.assertEqual(
            offenders, {},
            "Construct via FestivalApp.makeApp(_:)/FestivalApp.launch(_:) instead "
            "of XCUIApplication() directly, so every launch keeps "
            "FST_DEBUG_STILL_BACKGROUND=1 (or an explicit override, like "
            "DriverTests.swift's --animate passthrough) by construction.",
        )


if __name__ == "__main__":
    unittest.main()
