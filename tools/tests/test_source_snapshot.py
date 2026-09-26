"""Source provenance must distinguish committed and untracked review inputs."""

import tempfile
import unittest
from pathlib import Path
from subprocess import DEVNULL, run

from tools.source_snapshot import create_snapshot, tracked_source_paths, validate_citation_lines


class SourceSnapshotTests(unittest.TestCase):
    """No source code is copied into generated metadata."""

    def test_backlog_citations_expand_source_snapshot_without_copying_code(self):
        """Every new audited feature source becomes drift-checked automatically."""
        refs = {"epics": [
            {"sourceRefs": ["FortniteFestivalWeb/src/pages/example/Example.tsx:19"]},
            {"sourceRefs": ["FSTService/Api/Example.cs:3"]},
            {"sourceRefs": [
                "packages/core/src/app/formatters.ts:145",
                "packages/theme/src/colors.ts:1",
            ]},
        ]}
        self.assertEqual(tracked_source_paths(refs, ("before.ts",)), (
            "FSTService/Api/Example.cs",
            "FortniteFestivalWeb/src/pages/example/Example.tsx",
            "before.ts",
            "packages/core/src/app/formatters.ts",
            "packages/theme/src/colors.ts",
        ))
        refs["epics"][0]["sourceRefs"] = ["../../../secrets.env:1"]
        with self.assertRaisesRegex(ValueError, "Invalid parity source reference"):
            tracked_source_paths(refs, ())
        refs["epics"][0]["sourceRefs"] = ["packages/core/../../secrets.ts:1"]
        with self.assertRaisesRegex(ValueError, "Invalid parity source reference"):
            tracked_source_paths(refs, ())

    def test_committed_then_modified_source_hashes(self):
        """Dirty bytes are labeled as modifications to their original commit."""
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp)
            run(["git", "init", "-q", str(source)], check=True, stdout=DEVNULL)
            run(["git", "-C", str(source), "config", "user.name", "Fixture"], check=True)
            run(["git", "-C", str(source), "config", "user.email", "fixture@example.invalid"], check=True)
            path = source / "test.txt"
            path.write_text("first\n", encoding="utf-8")
            run(["git", "-C", str(source), "add", "test.txt"], check=True)
            run(["git", "-C", str(source), "commit", "-qm", "fixture"], check=True)
            clean = create_snapshot(source, ("test.txt",))
            self.assertEqual(clean["files"]["test.txt"]["status"], "committed")
            path.write_text("changed\n", encoding="utf-8")
            changed = create_snapshot(source, ("test.txt",))
            self.assertEqual(changed["files"]["test.txt"]["status"], "modified")
            self.assertNotEqual(clean["files"]["test.txt"]["sha256"], changed["files"]["test.txt"]["sha256"])
            other = source / "new.txt"
            other.write_text("new\n", encoding="utf-8")
            untracked = create_snapshot(source, ("new.txt",))
            self.assertEqual(untracked["files"]["new.txt"]["status"], "untracked")

    def test_source_citation_line_bounds_include_markdown_ranges(self):
        """A valid hash cannot conceal a nonexistent line or reversed doc range."""
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            docs = root / "guidance"
            path = source / "packages/theme/src/goldStyles.ts"
            path.parent.mkdir(parents=True)
            path.write_text("first\nsecond\nthird\n", encoding="utf-8")
            extra = source / "FSTService/Api/AccountEndpoints.cs"
            extra.parent.mkdir(parents=True)
            extra.write_text("account\n", encoding="utf-8")
            docs.mkdir()
            doc = docs / "accuracy.md"
            backlog = {"epics": [{"sourceRefs": ["packages/theme/src/goldStyles.ts:2"]}]}
            doc.write_text(
                "Source: `packages/theme/src/goldStyles.ts:1-3, 2-3`, "
                "`FSTService/Api/AccountEndpoints.cs:1`", encoding="utf-8"
            )
            self.assertEqual(tracked_source_paths(backlog, (), docs), (
                "FSTService/Api/AccountEndpoints.cs",
                "packages/theme/src/goldStyles.ts",
            ))
            validate_citation_lines(source, backlog, docs)
            doc.write_text("Source: `packages/theme/src/goldStyles.ts:1-3,4`", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "source line out of range"):
                validate_citation_lines(source, backlog, docs)
            doc.write_text("Source: `packages/theme/src/goldStyles.ts:1-3,3-2`", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "range ends before"):
                validate_citation_lines(source, backlog, docs)
            doc.write_text("Source: `packages/theme/src/goldStyles.ts:1-4`", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "source line out of range"):
                validate_citation_lines(source, backlog, docs)
            doc.write_text("Source: `packages/theme/src/goldStyles.ts:3-2`", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "range ends before"):
                validate_citation_lines(source, backlog, docs)
            doc.write_text("Source: `packages/theme/src/goldStyles.ts:1-3`", encoding="utf-8")
            backlog["epics"][0]["sourceRefs"] = ["packages/theme/src/goldStyles.ts:4"]
            with self.assertRaisesRegex(ValueError, "source line out of range"):
                validate_citation_lines(source, backlog, docs)


if __name__ == "__main__":
    unittest.main()
