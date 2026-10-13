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


class SyntheticTreeTestCase(unittest.TestCase):
    """Base for tests that run the checker against a small synthetic `.agents` tree."""

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


class CheckDocsTests(SyntheticTreeTestCase):
    """Exercise each rule against a small synthetic `.agents` tree."""

    def test_valid_tree_passes(self) -> None:
        """A consistent tree has no errors and routes platform files."""
        report = check_docs.run()
        self.assertEqual(report.errors, [])
        self.assertIn("[ios](songs/ios.md)", (check_docs.AGENTS / "pages/README.md").read_text())

    def test_skill_folders_need_frontmatter_and_routing(self) -> None:
        """Skills are `<name>/SKILL.md` with name/description frontmatter, routed by `skills/README.md`."""
        a = check_docs.AGENTS
        header = "# T\n\n> **What:** x. **Read when:** y.\n"
        _write(a / "README.md", header + "[p](pages/README.md) [c](controls/README.md) [s](skills/README.md)\n")
        _write(a / "skills/README.md", header + "[fix](fix/SKILL.md)\n")
        _write(a / "skills/fix/SKILL.md", "---\nname: fix\ndescription: Fix things.\n---\n\n" + header)
        self.assertEqual(check_docs.run().errors, [])
        _write(a / "skills/fix/SKILL.md", "---\nname: other\n---\n\n" + header)
        _write(a / "skills/flat.md", header)
        errors = "\n".join(check_docs.run().errors)
        self.assertIn("frontmatter `name` must be `fix`", errors)
        self.assertIn("needs a `description`", errors)
        self.assertIn("skills live in `<name>/SKILL.md` folders", errors)

    def test_duplicate_pattern_rule_numbers_fail(self) -> None:
        """A pattern doc that numbers two rules the same is an error, so the run exits non-zero."""
        _write(check_docs.AGENTS / "patterns/demo.md",
               "# T\n\n> x\n\n- **R1. One.** a\n- **R2. Two.** b\n- **R1. One.** a, newer\n")
        report = check_docs.Report()
        check_docs.check_pattern_rules(report)
        self.assertEqual(len(report.errors), 1)
        self.assertIn("rule R1 is defined 2 times (lines 5, 7)", report.errors[0])
        self.assertEqual(report.warnings, [])
        self.assertTrue(any("rule R1 is defined 2 times" in e for e in check_docs.run().errors))

    def test_distinct_pattern_rule_numbers_in_any_order_pass(self) -> None:
        """Unique rule numbers, in any order, and prose that cites a rule are fine."""
        _write(check_docs.AGENTS / "patterns/demo.md",
               "# T\n\n> x\n\n- **R2. Two.** b, see R1\n- **R1. One.** a\n- Guard (R1): x\n")
        report = check_docs.Report()
        check_docs.check_pattern_rules(report)
        self.assertEqual(report.errors, [])

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

    def _write_pattern(self, rules: str) -> None:
        """Add a routed pattern doc with the given rule lines.

        Args:
            rules: Markdown for the doc's `## Rules` section.
        """
        a = check_docs.AGENTS
        header = "# T\n\n> **What:** x. **Read when:** y.\n"
        _write(a / "README.md", header + "[p](pages/README.md) [c](controls/README.md) [pt](patterns/README.md)\n")
        _write(a / "patterns/README.md", header + "[s](scroll.md)\n")
        _write(a / "patterns/scroll.md", header + "## Rules\n\n" + rules)

    def test_distinct_pattern_rule_numbers_pass(self) -> None:
        """Each rule number once, with mentions of other rules in the text, is clean."""
        self._write_pattern("- **R1. One.** See R2.\n- **R2. Two.** Unlike R1.\n- **R10. Ten.**\n")
        self.assertEqual(check_docs.run().errors, [])

    def test_duplicated_pattern_rule_number_is_an_error(self) -> None:
        """A merge that keeps two copies of a rule fails the run, naming every line (#621)."""
        self._write_pattern("- **R1. Old.**\n- **R2. Two.**\n- **R1. New.**\n- **R2. Other.**\n- **R2. Third.**\n")
        report = check_docs.run()
        self.assertIn("patterns/scroll.md: rule R1 is defined 2 times (lines 6, 8)", "\n".join(report.errors))
        self.assertTrue(any("rule R2 is defined 3 times (lines 7, 9, 10)" in e for e in report.errors))
        self.assertFalse(any("rule R" in w for w in report.warnings))
        self.assertEqual(check_docs.main(["--quiet"]), 1)

    def test_rule_numbers_inside_code_fences_are_ignored(self) -> None:
        """An example rule in a fenced block is not a second definition."""
        self._write_pattern("- **R1. One.**\n\n```md\n- **R1. Example.**\n```\n")
        self.assertEqual(check_docs.run().errors, [])


class PatternRuleTests(SyntheticTreeTestCase):
    """Pattern docs define each rule number once (#621)."""

    def _pattern(self, rules: str) -> None:
        """Write a routed pattern doc with the given Rules block.

        Args:
            rules: Markdown for the rule list.
        """
        a = check_docs.AGENTS
        header = "# T\n\n> **What:** x. **Read when:** y.\n"
        _write(a / "README.md", header + "[p](pages/README.md) [c](controls/README.md) [x](patterns/README.md)\n")
        _write(a / "patterns/README.md", header + "[s](scroll.md) R1 R1\n- **R1. Not a rule doc.** x\n- **R1. Same.** y\n")
        _write(a / "patterns/scroll.md", header + "\n## Rules\n\n" + rules)

    def test_unique_rule_numbers_pass(self) -> None:
        """Both list styles, out-of-order numbers and fenced examples are fine."""
        self._pattern(
            "- **R1. One.** a\n- **R3. Three.** b (see R1)\n- **R2. Two.** c\n"
            "4. **R4. Four.** d\n\n```\n- **R1. Example.** e\n```\n"
        )
        self.assertEqual(check_docs.run().errors, [])
        self.assertEqual(check_docs.pattern_rules("- **R2. A.**\n1. **R2. B.**\n"), {2: [1, 2]})

    def test_duplicate_rule_number_is_an_error(self) -> None:
        """Two definitions of one number fail the run, naming the rule and its lines."""
        self._pattern("- **R1. Old copy.** a\n- **R2. Two.** b\n- **R1. New copy.** a, plus c\n")
        errors = check_docs.run().errors
        self.assertEqual(len(errors), 1)
        self.assertIn("patterns/scroll.md: rule R1 is defined 2 times (lines 7, 9)", errors[0])
        self.assertEqual(check_docs.main(["--quiet"]), 1)

    def test_three_copies_and_numbered_list_style_are_reported(self) -> None:
        """A rule kept three times, in either list style, is reported once with every line."""
        self._pattern("1. **R5. A.** a\n2. **R5. B.** b\n- **R5. C.** c\n")
        errors = check_docs.run().errors
        self.assertEqual(len(errors), 1)
        self.assertIn("rule R5 is defined 3 times (lines 7, 8, 9)", errors[0])

    def test_fix_preserves_duplicate_rules_and_still_fails(self) -> None:
        """--fix never chooses between conflicting requirements or downgrades errors."""
        self._pattern("- **R7. Old placement.** under the card\n+ **R7. New placement.** inside the card\n")
        doc = check_docs.AGENTS / "patterns/scroll.md"
        original = doc.read_text(encoding="utf-8")
        self.assertEqual(check_docs.main(["--fix", "--quiet"]), 1)
        self.assertEqual(doc.read_text(encoding="utf-8"), original)
        report = check_docs.run()
        self.assertEqual(len(report.errors), 1)
        self.assertIn("rule R7 is defined 2 times (lines 7, 8)", report.errors[0])
        self.assertEqual(report.warnings, [])


class RepositoryTests(unittest.TestCase):
    """The real `.agents` tree must satisfy every rule."""

    def test_repository_docs_pass(self) -> None:
        """No errors in the checked-in documentation."""
        self.assertEqual(check_docs.run().errors, [])


if __name__ == "__main__":
    unittest.main()
