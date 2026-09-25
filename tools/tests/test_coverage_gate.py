"""Require measured coverage ratios and prevent missing files from disappearing."""

import json
import tempfile
import unittest
from pathlib import Path

from tools.coverage_gate import check_coverage, llvm_file_totals, xml_file_totals


class CoverageGateTests(unittest.TestCase):
    """Prove the actual 95/90 bar, not a proxy based on test names."""

    def setUp(self):
        """Create two representative source files per temporary repository."""
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ("Sources/Logic/Example.swift", "Sources/UI/Example.swift"):
            path = self.root / name
            path.parent.mkdir(parents=True)
            path.write_text("source\n", encoding="utf-8")
        self.rules = {
            "thresholds": {"logic": 95, "ux": 90},
            "swift": {
                "sourceRoots": ["Sources/**/*.swift"],
                "logic": ["Sources/Logic/*.swift"],
                "ux": ["Sources/UI/*.swift"],
            },
        }

    def test_exact_bars_pass(self):
        """Exactly 95% logic and 90% UI must count as passing."""
        totals = {
            "Sources/Logic/Example.swift": (95, 100),
            "Sources/UI/Example.swift": (90, 100),
        }
        self.assertEqual(check_coverage(totals, self.root, self.rules, "swift"), [])

    def test_below_bar_fails_each_category(self):
        """A one-line miss below either threshold fails the relevant category."""
        totals = {
            "Sources/Logic/Example.swift": (94, 100),
            "Sources/UI/Example.swift": (89, 100),
        }
        errors = check_coverage(totals, self.root, self.rules, "swift")
        self.assertEqual(len(errors), 2)
        self.assertTrue(any("94.00%" in error for error in errors))
        self.assertTrue(any("89.00%" in error for error in errors))

    def test_missing_source_and_duplicate_report_fail(self):
        """A report must include every configured file exactly once."""
        totals = {"Sources/Logic/Example.swift": (100, 100)}
        errors = check_coverage(totals, self.root, self.rules, "swift")
        self.assertTrue(any("missing coverage" in error for error in errors))
        report = self.root / "coverage.json"
        content = {
            "data": [{
                "files": [{
                    "filename": str(self.root / "Sources/Logic/Example.swift"),
                    "summary": {"lines": {"covered": 100, "count": 100}},
                }]
            }]
        }
        report.write_text(json.dumps(content), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "duplicated"):
            llvm_file_totals([report, report], self.root)

    def test_only_nonexecutable_generated_tokens_may_be_excluded(self):
        """Generated constants are drift-checked, but executable UX still needs tests."""
        generated = self.root / "Sources/UI/Generated.swift"
        generated.write_text("generated constants\n", encoding="utf-8")
        rules = dict(self.rules)
        rules["swift"] = dict(self.rules["swift"], exclude=["Sources/UI/Generated.swift"])
        totals = {
            "Sources/Logic/Example.swift": (95, 100),
            "Sources/UI/Example.swift": (90, 100),
        }
        self.assertEqual(check_coverage(totals, self.root, rules, "swift"), [])
        totals["Sources/UI/Generated.swift"] = (0, 1)
        self.assertTrue(any(
            "executable source cannot be excluded" in error
            for error in check_coverage(totals, self.root, rules, "swift")
        ))

    def test_unclassified_nested_production_source_fails(self):
        """A new nested Swift file cannot evade flat coverage patterns."""
        nested = self.root / "Sources/UI/Nested/NewControl.swift"
        nested.parent.mkdir(parents=True)
        nested.write_text("production code\n", encoding="utf-8")
        totals = {
            "Sources/Logic/Example.swift": (95, 100),
            "Sources/UI/Example.swift": (90, 100),
        }
        errors = check_coverage(totals, self.root, self.rules, "swift")
        self.assertTrue(any(
            "unclassified production source" in error and "NewControl.swift" in error
            for error in errors
        ))

    def test_invalid_source_roots_are_rejected(self):
        """A malformed inventory cannot silently disable completeness checks."""
        rules = dict(self.rules)
        rules["swift"] = dict(self.rules["swift"], sourceRoots=[])
        totals = {
            "Sources/Logic/Example.swift": (95, 100),
            "Sources/UI/Example.swift": (90, 100),
        }
        self.assertTrue(any(
            "invalid sourceRoots patterns" in error
            for error in check_coverage(totals, self.root, rules, "swift")
        ))

    def test_jacoco_combines_host_and_instrumented_lines(self):
        """The Android gate joins the same source line across both test types."""
        source = self.root / "Sources/Logic/Example.swift"
        report = self.root / "jacoco.xml"
        report.write_text(
            '<report name="fixture"><package name="Sources/Logic">'
            '<sourcefile name="Example.swift"><line nr="1" mi="1" ci="0"/>'
            '<line nr="2" mi="0" ci="1"/></sourcefile></package></report>',
            encoding="utf-8",
        )
        instrumented = self.root / "instrumented.xml"
        instrumented.write_text(
            '<report name="fixture"><package name="Sources/Logic">'
            '<sourcefile name="Example.swift"><line nr="1" mi="0" ci="1"/>'
            '</sourcefile></package></report>',
            encoding="utf-8",
        )
        totals = xml_file_totals([report, instrumented], {
            source.relative_to(self.root).as_posix()
        })
        self.assertEqual(totals["Sources/Logic/Example.swift"], (2, 2))

    def test_cobertura_and_ambiguous_filename(self):
        """Windows XML hits are parsed; duplicate basenames must be disambiguated."""
        report = self.root / "cobertura.xml"
        report.write_text(
            '<coverage><packages><package><classes><class filename="Sources/UI/Example.swift">'
            '<lines><line number="1" hits="1"/><line number="2" hits="0"/>'
            '</lines></class></classes></package></packages></coverage>',
            encoding="utf-8",
        )
        totals = xml_file_totals([report], {"Sources/UI/Example.swift"})
        self.assertEqual(totals["Sources/UI/Example.swift"], (1, 2))
        report.write_text(
            report.read_text(encoding="utf-8").replace(
                "Sources/UI/Example.swift",
                "C:\\Users\\sfent\\workspace\\FestivalNativeApps-windows"
                "\\Sources\\UI\\Example.swift",
            ),
            encoding="utf-8",
        )
        self.assertEqual(
            xml_file_totals([report], {"Sources/UI/Example.swift"})["Sources/UI/Example.swift"],
            (1, 2),
        )
        report.write_text(
            '<coverage><package><class filename="Example.swift"><lines>'
            '<line number="1" hits="1"/></lines></class></package></coverage>',
            encoding="utf-8",
        )
        with self.assertRaisesRegex(ValueError, "expected one matching"):
            xml_file_totals([report], {
                "Sources/UI/Example.swift", "Other/Sources/UI/Example.swift"
            })


if __name__ == "__main__":
    unittest.main()
