"""Check that the cross-device iOS coverage gate joins real executable lines."""

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from tools.apple_xccov_gate import (
    collect_result, device_identity, line_hits, union_lines, validate_device_pair,
)


class XcodeCoverageTests(unittest.TestCase):
    """Reject misleading target percentages and incomplete source lists."""

    def test_union_accepts_exact_ninety_percent(self):
        """A device pair covers nine of ten lines even when neither does alone."""
        iphone = {"UI.swift": {line: line <= 5 for line in range(1, 11)}}
        ipad = {"UI.swift": {line: 6 <= line <= 9 for line in range(1, 11)}}
        self.assertEqual(union_lines([iphone, ipad]), (9, 10))

    def test_changed_source_and_executable_lines_fail(self):
        """Cross-build drift cannot produce a false pass."""
        with self.assertRaisesRegex(ValueError, "different production source"):
            union_lines([{"A.swift": {1: True}}, {"B.swift": {1: True}}])
        with self.assertRaisesRegex(ValueError, "executable lines differ"):
            union_lines([{"A.swift": {1: True}}, {"A.swift": {2: True}}])

    def test_archive_must_agree_with_xcode_report(self):
        """SwiftUI specialization totals may exceed unique lines, never trail them."""
        source = Path("/fixture/UI.swift")
        archive = {str(source): [
            {"line": 1, "isExecutable": True, "executionCount": 2},
            {"line": 2, "isExecutable": True, "executionCount": 0},
        ]}
        self.assertEqual(line_hits(archive, source, covered=1, executable=2), {
            1: True, 2: False,
        })
        self.assertEqual(line_hits(archive, source, covered=2, executable=3), {
            1: True, 2: False,
        })
        with self.assertRaisesRegex(ValueError, "exceed"):
            line_hits(archive, source, covered=0, executable=1)

    def test_requires_two_distinct_phone_and_tablet_results(self):
        """One result, its duplicate, or two phones must not satisfy the UX gate."""
        first, second = Path("/fixture/iphone.xcresult"), Path("/fixture/ipad.xcresult")
        with self.assertRaisesRegex(ValueError, "two distinct"):
            validate_device_pair([first], [("iPhone", "phone")])
        with self.assertRaisesRegex(ValueError, "two distinct"):
            validate_device_pair([first, first], [("iPhone", "phone"), ("iPad", "tablet")])
        with self.assertRaisesRegex(ValueError, "iPhone and iPad"):
            validate_device_pair([first, second], [("iPhone", "one"), ("iPhone", "two")])
        with self.assertRaisesRegex(ValueError, "distinct iPhone"):
            validate_device_pair([first, second], [("iPhone", "same"), ("iPad", "same")])
        validate_device_pair([first, second], [("iPhone", "phone"), ("iPad", "tablet")])

    def test_rejects_missing_identity_and_coverage_target(self):
        """A passing but incomplete Xcode report cannot count as UX evidence."""
        summary = {
            "result": "Passed", "passedTests": 1, "startTime": 1,
            "devicesAndConfigurations": [{
                "device": {
                    "platform": "iOS Simulator", "modelName": "iPad Pro 11-inch",
                    "deviceId": "ipad-1",
                },
            }],
        }
        self.assertEqual(device_identity(summary), ("iPad", "ipad-1"))
        with self.assertRaisesRegex(ValueError, "exactly one device"):
            device_identity(dict(summary, devicesAndConfigurations=[]))
        with TemporaryDirectory() as temporary:
            result = Path(temporary) / "result.xcresult"
            result.mkdir()
            with patch("tools.apple_xccov_gate.xcode_json", side_effect=[
                summary, {"targets": [{"name": "FestivalMobile.app", "files": []}]},
            ]):
                with self.assertRaisesRegex(ValueError, "missing FestivalUI coverage"):
                    collect_result(result, Path(temporary))


if __name__ == "__main__":
    unittest.main()
