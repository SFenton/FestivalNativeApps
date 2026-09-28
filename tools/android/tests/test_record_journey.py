"""Argument handling of ``tools/android/record_journey.py`` (no emulator needed).

Run: ``python -m unittest discover -s tools/android/tests`` from the repo root.
"""

import unittest
from pathlib import Path

from tools.android import record_journey


class ParseTests(unittest.TestCase):
    """``--record`` plus the shared ``device.py drive`` options."""

    def test_record_is_split_from_drive_options_with_app_defaults(self):
        args = record_journey.parse(["--record", "out/j.mp4", "--avd", "FST_Phone", "--launch", "--steps", "wait:1"])
        self.assertEqual(args.record, Path("out/j.mp4"))
        self.assertEqual(args.avd, "FST_Phone")
        self.assertTrue(args.launch)
        self.assertEqual(args.package, record_journey.PACKAGE)
        self.assertEqual(args.activity, ".MainActivity")

    def test_explicit_package_is_kept(self):
        args = record_journey.parse(["--record", "j.mp4", "--package", "x.y", "--steps", "wait:1"])
        self.assertEqual(args.package, "x.y")

    def test_record_is_required(self):
        with self.assertRaises(SystemExit):
            record_journey.parse(["--steps", "wait:1"])


if __name__ == "__main__":
    unittest.main()
