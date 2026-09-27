"""Check the scoped iOS coverage gate joins only real executable source lines."""

import io
import json
import time
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from tools.apple_xccov_gate import (
    collect_result, device_identity, line_hits, main, union_lines,
    validate_result_devices,
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

    def test_scoped_results_require_distinct_paths_and_consistent_devices(self):
        """Phone shards cannot stand in for a phone/tablet pair or change device IDs."""
        first = Path("/fixture/iphone.xcresult")
        second = Path("/fixture/ipad.xcresult")
        third = Path("/fixture/iphone-shard-2.xcresult")
        with self.assertRaisesRegex(ValueError, "at least 2 distinct"):
            validate_result_devices([first], [("iPhone", "phone")], "paired")
        with self.assertRaisesRegex(ValueError, "distinct Xcode"):
            validate_result_devices(
                [first, first], [("iPhone", "phone"), ("iPad", "tablet")], "paired"
            )
        with self.assertRaisesRegex(ValueError, "iPhone and iPad"):
            validate_result_devices(
                [first, second], [("iPhone", "one"), ("iPhone", "one")], "paired"
            )
        with self.assertRaisesRegex(ValueError, "distinct iPhone"):
            validate_result_devices(
                [first, second], [("iPhone", "same"), ("iPad", "same")], "paired"
            )
        with self.assertRaisesRegex(ValueError, "same simulator"):
            validate_result_devices(
                [first, third], [("iPhone", "phone"), ("iPhone", "other")], "iphone"
            )
        with self.assertRaisesRegex(ValueError, "requires only iPhone"):
            validate_result_devices([second], [("iPad", "tablet")], "iphone")
        validate_result_devices([first], [("iPhone", "phone")], "iphone")
        validate_result_devices(
            [first, third], [("iPhone", "phone"), ("iPhone", "phone")], "iphone"
        )
        validate_result_devices(
            [first, second, third],
            [("iPhone", "phone"), ("iPad", "tablet"), ("iPhone", "phone")],
            "paired",
        )

    def test_iphone_shards_union_exact_ninety_without_certifying_pair(self):
        """The explicit phone scope joins disjoint hits while retaining the 90% bar."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "contracts").mkdir()
            (root / "contracts/coverage-rules.json").write_text(
                json.dumps({"thresholds": {"ux": 90}}), encoding="utf-8"
            )
            (root / "UI.swift").write_text("test", encoding="utf-8")
            first, second = root / "first.xcresult", root / "second.xcresult"
            start = time.time() + 10
            first_hits = {"UI.swift": {line: line <= 5 for line in range(1, 11)}}
            second_hits = {"UI.swift": {line: 6 <= line <= 9 for line in range(1, 11)}}
            with (
                patch("tools.apple_xccov_gate.collect_result", side_effect=[
                    (first_hits, start, ("iPhone", "phone")),
                    (second_hits, start, ("iPhone", "phone")),
                ]),
                patch("sys.stdout", new_callable=io.StringIO) as output,
            ):
                self.assertEqual(main([
                    "--root", str(root), "--scope", "iphone",
                    "--result", str(first), "--result", str(second),
                ]), 0)
                self.assertIn("ios.iphone.ui-and-app-ux: 9/10 lines = 90.00%", output.getvalue())
            with (
                patch(
                    "tools.apple_xccov_gate.collect_result",
                    return_value=(first_hits, start, ("iPhone", "phone")),
                ),
                patch("sys.stderr", new_callable=io.StringIO) as errors,
                patch("sys.stdout", new_callable=io.StringIO),
            ):
                self.assertEqual(main([
                    "--root", str(root), "--scope", "iphone", "--result", str(first),
                ]), 1)
                self.assertIn("below 90%", errors.getvalue())

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
