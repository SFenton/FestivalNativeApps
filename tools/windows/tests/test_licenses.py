"""Tests for tools/windows/licenses.py (Windows Licenses manifest generator)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import licenses  # noqa: E402


class DisplayVersionTests(unittest.TestCase):
    """The runtime pack shows its servicing band; every other package keeps its exact version."""

    def test_runtime_pack_shows_servicing_band(self) -> None:
        for version in ("9.0.8", "9.0.20", "9.0.20-servicing.1"):
            self.assertEqual(licenses.display_version("Microsoft.NETCore.App.Runtime.win-x64", version), "9.0.x")

    def test_other_packages_keep_exact_version(self) -> None:
        self.assertEqual(licenses.display_version("Microsoft.WindowsAppSDK", "2.5.1"), "2.5.1")
        self.assertEqual(licenses.display_version("Microsoft.Windows.SDK.NET.Ref", "10.0.26100.87"), "10.0.26100.87")

    def test_unexpected_runtime_version_is_kept(self) -> None:
        self.assertEqual(licenses.display_version("microsoft.netcore.app.runtime.win-x64", "9"), "9")


class NormalizeTests(unittest.TestCase):
    """Identical bodies with different line endings de-duplicate."""

    def test_line_endings_and_trailing_space(self) -> None:
        self.assertEqual(licenses.normalize("a  \r\nb\r\n\r\n"), licenses.normalize("a\nb"))


if __name__ == "__main__":
    unittest.main()
