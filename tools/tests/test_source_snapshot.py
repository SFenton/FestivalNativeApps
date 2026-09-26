"""Source provenance must distinguish committed and untracked review inputs."""

import tempfile
import unittest
from pathlib import Path
from subprocess import DEVNULL, run

from tools.source_snapshot import create_snapshot, tracked_source_paths


class SourceSnapshotTests(unittest.TestCase):
    """No source code is copied into generated metadata."""

    def test_backlog_citations_expand_source_snapshot_without_copying_code(self):
        """Every new audited feature source becomes drift-checked automatically."""
        refs = {"epics": [
            {"sourceRefs": ["FortniteFestivalWeb/src/pages/example/Example.tsx:19"]},
            {"sourceRefs": ["FSTService/Api/Example.cs:3"]},
        ]}
        self.assertEqual(tracked_source_paths(refs, ("before.ts",)), (
            "FSTService/Api/Example.cs",
            "FortniteFestivalWeb/src/pages/example/Example.tsx",
            "before.ts",
        ))
        refs["epics"][0]["sourceRefs"] = ["../../../secrets.env:1"]
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


if __name__ == "__main__":
    unittest.main()
