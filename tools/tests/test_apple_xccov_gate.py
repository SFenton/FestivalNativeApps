"""Check the scoped iOS coverage gate joins only real executable source lines."""

import io
import json
import os
import time
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from tools.apple_xccov_gate import (
    TARGET_SOURCES, collect_result, device_identity, file_sha256, line_hits, llvm_line_map,
    main, source_manifest, source_omission_reason, union_lines, validate_result_devices,
    validate_llvm_provenance,
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

    def test_target_source_patterns_reach_nested_feature_files(self):
        """FestivalUI/app globs must not stop at their target's top-level files.

        Regression: the real product nests every `FestivalUI` file under
        `Features/**`, `App/**`, `Common/**`, `Design/**` or `Background/**`,
        so a non-recursive `FestivalUI/*.swift` pattern matched zero files.
        """
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            nested = root / "apple/Sources/FestivalUI/Features/Deep/NewControl.swift"
            nested.parent.mkdir(parents=True)
            nested.write_text("production code\n", encoding="utf-8")
            top = root / "apple/Apps/iOS/AppDelegate.swift"
            top.parent.mkdir(parents=True)
            top.write_text("production code\n", encoding="utf-8")
            self.assertEqual(
                {p.resolve() for p in root.glob(TARGET_SOURCES["FestivalUI"])},
                {nested.resolve()},
            )
            self.assertEqual(
                {p.resolve() for p in root.glob(TARGET_SOURCES["FestivalMobile.app"])},
                {top.resolve()},
            )

    def test_uikit_collection_selects_uikit_entry_and_unique_lines(self):
        """UIKit evidence measures its entry source alongside shared UI lines."""
        summary = {
            "result": "Passed", "passedTests": 1, "startTime": 1,
            "devicesAndConfigurations": [{
                "device": {
                    "platform": "iOS Simulator", "modelName": "iPhone 17 Pro",
                    "deviceId": "iphone-1",
                },
            }],
        }
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            shared = root / "apple/Sources/FestivalUI/Shared.swift"
            entry = root / "apple/Apps/iOSUIKit/UKApp.swift"
            shared.parent.mkdir(parents=True)
            entry.parent.mkdir(parents=True)
            shared.write_text("shared\nsecond\n", encoding="utf-8")
            entry.write_text("entry\n", encoding="utf-8")
            result = root / "result.xcresult"
            result.mkdir()
            report = {"targets": [
                {"name": "FestivalUI", "files": [{
                    "path": str(shared), "coveredLines": 1, "executableLines": 2,
                }]},
                {"name": "FestivalMobileUIKit.app", "files": [{
                    "path": str(entry), "coveredLines": 1, "executableLines": 1,
                }]},
            ]}
            archives = [
                {str(shared): [
                    {"line": 4, "isExecutable": True, "executionCount": 2},
                    {"line": 9, "isExecutable": True, "executionCount": 0},
                ]},
                {str(entry): [
                    {"line": 7, "isExecutable": True, "executionCount": 1},
                ]},
            ]
            with patch("tools.apple_xccov_gate.xcode_json",
                       side_effect=[summary, report, *archives]):
                measured, _, _ = collect_result(result, root, "uikit")
            self.assertEqual(measured, {
                "apple/Sources/FestivalUI/Shared.swift": {4: True, 9: False},
                "apple/Apps/iOSUIKit/UKApp.swift": {7: True},
            })

    def test_foreign_app_target_is_rejected(self):
        """A result containing the other app family is not a compatible shard."""
        summary = {
            "result": "Passed", "passedTests": 1, "startTime": 1,
            "devicesAndConfigurations": [{
                "device": {
                    "platform": "iOS Simulator", "modelName": "iPhone 17 Pro",
                    "deviceId": "iphone-1",
                },
            }],
        }
        with TemporaryDirectory() as temporary:
            result = Path(temporary) / "result.xcresult"
            result.mkdir()
            with patch("tools.apple_xccov_gate.xcode_json", side_effect=[
                summary,
                {"targets": [
                    {"name": "FestivalUI", "files": []},
                    {"name": "FestivalMobile.app", "files": []},
                    {"name": "FestivalMobileUIKit.app", "files": []},
                ]},
            ]):
                with self.assertRaisesRegex(ValueError, "foreign app coverage"):
                    collect_result(result, Path(temporary), "uikit")

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

    def test_llvm_line_map_uses_lcov_lines_not_json_region_totals(self):
        """LLVM JSON region totals may differ from canonical LCOV line totals."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            shared = root / "apple/Sources/FestivalUI/Shared.swift"
            shared.parent.mkdir(parents=True)
            shared.write_text("shared\nsecond\n", encoding="utf-8")
            export = {"data": [{"files": [{
                "filename": str(shared),
                "summary": {"lines": {"count": 2, "covered": 1}},
            }]}]}
            line_map = f"SF:{shared}\nDA:1,2\nDA:2,0\nend_of_record\n"
            measured = llvm_line_map(export, line_map, root, {"omittedSources": {}})
            self.assertEqual(measured, {
                "apple/Sources/FestivalUI/Shared.swift": {1: True, 2: False},
            })
            with self.assertRaisesRegex(ValueError, "FestivalUI"):
                llvm_line_map(export, "", root, {})
            # A same-count line outside the source remains invalid; location
            # integrity is checked independently of JSON's aggregate totals.
            line_map = f"SF:{shared}\nDA:1,2\nDA:3,0\nend_of_record\n"
            with self.assertRaisesRegex(ValueError, "outside the source"):
                llvm_line_map(export, line_map, root, {"omittedSources": {}})

    def test_llvm_provenance_rejects_digest_mismatch(self):
        """A profile/export from another build cannot be attached to a result."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = root / "result.xcresult"
            result.mkdir()
            binary, profile = root / "app.debug.dylib", root / "Coverage.profdata"
            export, line_map = root / "export.json", root / "lines.json"
            for path in (binary, profile, export, line_map):
                path.write_text(path.name, encoding="utf-8")
            now = time.time()
            manifest = source_manifest(root)
            provenance = {
                "schemaVersion": 2, "appFamily": "uikit", "architecture": "arm64",
                "sourceDigest": "source", "sourceManifest": manifest,
                "device": ["iPhone", "phone"], "result": {
                    "path": str(result), "startTime": now - 10, "finishTime": now + 10,
                },
                "binary": {
                    "path": str(binary), "sha256": file_sha256(binary),
                    "architecture": "arm64",
                },
                "profile": {"path": str(profile), "sha256": file_sha256(profile), "mtime": now},
                "export": {"path": str(export), "sha256": "wrong", "mtime": now},
                "lineMap": {"path": str(line_map), "sha256": file_sha256(line_map)},
            }
            os.utime(profile, (now, now))
            with patch("tools.apple_xccov_gate.source_digest", return_value="source"):
                with self.assertRaisesRegex(ValueError, "export digest"):
                    validate_llvm_provenance(
                        root / "provenance.json", provenance, result, export,
                        line_map, root, now - 10, now + 10, ("iPhone", "phone"),
                    )

    def test_llvm_provenance_rejects_same_total_wrong_lcov_locations(self):
        """A rewritten LCOV map fails even when its line totals are unchanged."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            result = root / "result.xcresult"
            result.mkdir()
            binary, profile = root / "app.debug.dylib", root / "Coverage.profdata"
            export, line_map = root / "export.json", root / "lines.lcov"
            for path in (binary, profile, export, line_map):
                path.write_text(path.name, encoding="utf-8")
            now = time.time()
            os.utime(profile, (now - 1, now - 1))
            provenance = {
                "schemaVersion": 2, "appFamily": "uikit", "architecture": "arm64",
                "sourceDigest": "source", "sourceManifest": {},
                "device": ["iPhone", "phone"], "result": {
                    "path": str(result), "startTime": now - 10, "finishTime": now,
                },
                "binary": {
                    "path": str(binary), "sha256": file_sha256(binary),
                    "architecture": "arm64",
                },
                "profile": {
                    "path": str(profile), "sha256": file_sha256(profile),
                    "mtime": now - 1,
                },
                "export": {
                    "path": str(export), "sha256": file_sha256(export),
                    "mtime": export.stat().st_mtime,
                },
                "lineMap": {"path": str(line_map), "sha256": file_sha256(line_map)},
                "llvmIdentity": {
                    "architectures": "arm64", "uuids": "u", "profileBinaryIds": "u",
                },
            }
            with patch("tools.apple_xccov_gate.source_manifest", return_value={}), \
                    patch("tools.apple_xccov_gate.source_digest", return_value="source"), \
                    patch("tools.apple_xccov_gate.llvm_identity",
                          return_value=provenance["llvmIdentity"]), \
                    patch("tools.apple_xccov_gate.subprocess.run", return_value=type(
                        "Process", (), {"returncode": 0, "stderr": "", "stdout": "different\n"}
                    )()):
                with self.assertRaisesRegex(ValueError, "LCOV does not match"):
                    validate_llvm_provenance(
                        root / "provenance.json", provenance, result, export,
                        line_map, root, now - 10, now, ("iPhone", "phone"),
                    )

    def test_llvm_omission_requires_source_proof(self):
        """Only guarded macOS or declaration-only files may be absent from iOS LLVM output."""
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            shared = root / "apple/Sources/FestivalUI/Shared.swift"
            omitted = root / "apple/Sources/FestivalUI/Missing.swift"
            shared.parent.mkdir(parents=True)
            shared.write_text("let x = 1\n", encoding="utf-8")
            omitted.write_text("func realWork() {}\n", encoding="utf-8")
            export = {"data": [{"files": [{
                "filename": str(shared),
                "summary": {"lines": {"count": 1, "covered": 1}},
            }]}]}
            lcov = f"SF:{shared}\nDA:1,1\nend_of_record\n"
            with self.assertRaisesRegex(ValueError, "executable owned source"):
                llvm_line_map(export, lcov, root, {"omittedSources": {}})

    def test_source_omission_proof_rejects_computed_and_mixed_platform_code(self):
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            mac = root / "apple/Sources/FestivalUI/Mac/Mixed.swift"
            computed = root / "apple/Sources/FestivalUI/Computed.swift"
            dotted = root / "apple/Sources/FestivalUI/Dotted.swift"
            mac.parent.mkdir(parents=True)
            mac.write_text("#if os(macOS)\nlet x = 1\n#else\nlet x = 2\n#endif\n", encoding="utf-8")
            computed.write_text("var value: Int { get { 1 } }\n", encoding="utf-8")
            dotted.write_text("let value = Factory.make()\n", encoding="utf-8")
            self.assertIsNone(source_omission_reason(mac, root))
            self.assertIsNone(source_omission_reason(computed, root))
            self.assertIsNone(source_omission_reason(dotted, root))


if __name__ == "__main__":
    unittest.main()
