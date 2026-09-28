"""Self-tests for `check_docs.py`: `python3 -m unittest discover -s .agents/_tools`."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import check_docs


def _write(path: Path, text: str) -> None:
    """Create a file and its parents.

    Args:
        path: Destination.
        text: File content.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class CheckDocsTests(unittest.TestCase):
    """Exercise each rule against a small synthetic `.agents` tree."""

    def setUp(self) -> None:
        """Point the checker at a minimal valid repository."""
        self._saved = (check_docs.ROOT, check_docs.AGENTS, check_docs.PRODUCT, check_docs.BACKLOG)
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        check_docs.ROOT = root
        check_docs.AGENTS = root / ".agents"
        check_docs.PRODUCT = root / "contracts/product.json"
        check_docs.BACKLOG = root / "contracts/parity-backlog.json"
        _write(check_docs.PRODUCT, json.dumps({
            "pages": [{"id": "songs", "path": "/songs", "guard": "none", "source": "X.tsx:1"}],
            "controls": [{"id": "sort", "testId": "fst.sort", "states": ["a"], "status": "pending"}],
        }))
        _write(check_docs.BACKLOG, json.dumps({"routes": [{"id": "songs", "apple": "partial"}]}))
        header = "# T\n\n> **What:** x. **Read when:** y.\n"
        a = check_docs.AGENTS
        _write(a / "README.md", header + "[p](pages/README.md) [c](controls/README.md)\n")
        _write(a / "pages/README.md", header + f"{check_docs.BEGIN}\n{check_docs.END}\n")
        _write(a / "controls/README.md", header + f"{check_docs.BEGIN}\n{check_docs.END}\n")
        _write(a / "pages/songs/spec.md", header + "## Behavior\n")
        _write(a / "pages/songs/ios.md", header + "## iPhone toolbar\n")
        _write(a / "controls/sort/spec.md", header)
        check_docs.check_indexes(check_docs.Report(), fix=True)

    def tearDown(self) -> None:
        """Restore module globals."""
        check_docs.ROOT, check_docs.AGENTS, check_docs.PRODUCT, check_docs.BACKLOG = self._saved
        self.tmp.cleanup()

    def test_valid_tree_passes(self) -> None:
        """A consistent tree has no errors and routes platform files."""
        report = check_docs.run()
        self.assertEqual(report.errors, [])
        self.assertIn("[ios](songs/ios.md)", (check_docs.AGENTS / "pages/README.md").read_text())

    def test_spec_naming_a_platform_fails(self) -> None:
        """Platform-neutral specs cannot carry platform headings."""
        _write(check_docs.AGENTS / "pages/songs/spec.md", "# T\n\n> x\n## iPad layout\n")
        self.assertTrue(any("platform-neutral" in e for e in check_docs.run().errors))

    def test_platform_file_naming_another_platform_fails(self) -> None:
        """An iPhone file cannot hold iPad sections."""
        _write(check_docs.AGENTS / "pages/songs/ios.md", "# T\n\n> x\n## iPadOS sidebar\n")
        self.assertTrue(any("scoped to" in e for e in check_docs.run().errors))

    def test_generic_file_mixing_platforms_fails(self) -> None:
        """A shared file may name at most one platform family."""
        _write(check_docs.AGENTS / "notes.md", "# T\n\n> x\n## Android\n## Windows\n")
        _write(check_docs.AGENTS / "README.md", "# T\n\n> x\n[p](pages/README.md) [c](controls/README.md) [n](notes.md)\n")
        self.assertTrue(any("mix platforms" in e for e in check_docs.run().errors))

    def test_iphone_duo_counts_as_duo_only(self) -> None:
        """"iPhone Duo" in a Duo file is not an iPhone heading."""
        _write(check_docs.AGENTS / "pages/songs/duo.md", "# T\n\n> x\n## iPhone Duo poses\n")
        check_docs.check_indexes(check_docs.Report(), fix=True)
        self.assertEqual(check_docs.run().errors, [])

    def test_missing_header_and_broken_link_fail(self) -> None:
        """Header line and link targets are required."""
        _write(check_docs.AGENTS / "pages/songs/spec.md", "# T\nno header\n[x](missing.md)\n")
        errors = check_docs.run().errors
        self.assertTrue(any("what/when" in e for e in errors))
        self.assertTrue(any("broken link" in e for e in errors))

    def test_unrouted_file_and_missing_readme_fail(self) -> None:
        """Every folder needs a README that links its children."""
        _write(check_docs.AGENTS / "orphan.md", "# T\n\n> x\n")
        _write(check_docs.AGENTS / "design/fluent.md", "# T\n\n> x\n")
        errors = check_docs.run().errors
        self.assertTrue(any("does not link `orphan.md`" in e for e in errors))
        self.assertTrue(any("needs a README" in e for e in errors))

    def test_missing_spec_is_scaffolded_by_fix(self) -> None:
        """--fix creates stubs for contract pages without a spec."""
        (check_docs.AGENTS / "controls/sort/spec.md").unlink()
        self.assertTrue(any("missing spec" in e for e in check_docs.run().errors))
        self.assertEqual(check_docs.run(fix=True).errors, [])
        self.assertIn("<!-- stub -->", (check_docs.AGENTS / "controls/sort/spec.md").read_text())

    def test_stale_index_fails_until_fixed(self) -> None:
        """Adding a platform file makes the generated table stale."""
        _write(check_docs.AGENTS / "pages/songs/ipados.md", "# T\n\n> x\n")
        self.assertTrue(any("stale" in e for e in check_docs.run().errors))
        self.assertEqual(check_docs.run(fix=True).errors, [])


class RepositoryTests(unittest.TestCase):
    """The real `.agents` tree must satisfy every rule."""

    def test_repository_docs_pass(self) -> None:
        """No errors in the checked-in documentation."""
        self.assertEqual(check_docs.run().errors, [])


if __name__ == "__main__":
    unittest.main()
