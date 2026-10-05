"""Tests for the pattern registry checker (`tools/pattern_guard.py`)."""

import json
import tempfile
import unittest
from pathlib import Path

from tools import pattern_guard as pg


def _write(root: Path, rel: str, text: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


class PatternGuardTests(unittest.TestCase):
    """The registry must stay truthful and guards must stop parallel implementations."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        _write(self.root, "contracts/product.json", json.dumps({"pages": [{"id": "songs"}], "controls": []}))
        _write(self.root, ".agents/patterns/README.md", "# P\n\n> x\n\n| [edge](edge.md) |\n")
        _write(self.root, ".agents/patterns/edge.md",
               "# Edge\n\n> x\n\n- **R1.** one mechanism\n\n- `edge/apple-mask`\n")
        _write(self.root, "apple/Sources/Design/Fade.swift", "struct EdgeFade {}\nlet x = y.mask { }\n")
        _write(self.root, "apple/Sources/Features/List.swift", "// .mask { } in a comment is fine\nlet a = 1\n")
        self.entry = {
            "id": "edge", "title": "Edge", "status": "current", "doc": ".agents/patterns/edge.md",
            "summary": "s", "canonical": {"apple": [{"path": "apple/Sources/Design/Fade.swift", "symbol": "EdgeFade"}]},
            "guards": [{"id": "apple-mask", "glob": "apple/Sources/**/*.swift", "regex": r"\.mask\s*[({]",
                        "allow": ["apple/Sources/Design/**"], "message": "use EdgeFade (edge R1)"}],
            "related": {"pages": ["songs"]},
        }
        self._save()

    def tearDown(self):
        self.tmp.cleanup()

    def _save(self):
        _write(self.root, "contracts/patterns.json", json.dumps({"schemaVersion": 1, "patterns": [self.entry]}))

    def test_clean_registry_passes(self):
        report = pg.check(self.root, web=None)
        self.assertEqual(report.errors, [])

    def test_new_parallel_mask_fails_with_rule_citation(self):
        _write(self.root, "apple/Sources/Features/List.swift", "let a = b.mask(LinearGradient())\n")
        errors = pg.check(self.root, web=None).errors
        self.assertTrue(any("List.swift:1: edge/apple-mask: use EdgeFade (edge R1)" in e for e in errors), errors)

    def test_debt_is_allowed_but_stale_debt_fails(self):
        _write(self.root, "apple/Sources/Features/List.swift", "let a = b.mask { }\n")
        self.entry["guards"][0]["debt"] = ["apple/Sources/Features/List.swift"]
        self._save()
        report = pg.check(self.root, web=None)
        self.assertEqual(report.errors, [])
        self.assertTrue(any("known debt" in w for w in report.warnings))
        _write(self.root, "apple/Sources/Features/List.swift", "let a = 1\n")
        self.assertTrue(any("no longer violates" in e for e in pg.check(self.root, web=None).errors))

    def test_missing_canonical_symbol_doc_rules_and_router(self):
        self.entry["canonical"]["apple"][0]["symbol"] = "Nope"
        self.entry["related"]["controls"] = ["ghost"]
        self._save()
        _write(self.root, ".agents/patterns/edge.md", "# Edge\n\n> x\n\nno rules\n")
        _write(self.root, ".agents/patterns/README.md", "# P\n\n> x\n")
        errors = "\n".join(pg.check(self.root, web=None).errors)
        for needle in ("symbol `Nope` not found", "numbered Rules block", "not listed in .agents/patterns/README.md",
                       "related control `ghost`", "doc must name guard `edge/apple-mask`"):
            self.assertIn(needle, errors)

    def test_glob_translation(self):
        self.assertTrue(pg.matches("apple/Sources/A/B.swift", ["apple/Sources/**/*.swift"]))
        self.assertTrue(pg.matches("apple/Sources/B.swift", ["apple/Sources/**/*.swift"]))
        self.assertFalse(pg.matches("apple/Tests/B.swift", ["apple/Sources/**/*.swift"]))
        self.assertFalse(pg.matches("apple/Sources/A/B.kt", ["apple/Sources/*.swift"]))

    def test_changed_report_flags_canonical_change_without_doc(self):
        data = {"patterns": [self.entry]}
        text, missing = pg.changed_report(data, ["apple/Sources/Design/Fade.swift"])
        self.assertTrue(missing)
        self.assertIn("not updated", text)
        text, missing = pg.changed_report(data, ["apple/Sources/Design/Fade.swift", ".agents/patterns/edge.md"])
        self.assertFalse(missing)
        self.assertEqual(pg.owners(data, "apple/Sources/Features/List.swift"), [("edge", "guarded")])

    def test_index_skips_superseded(self):
        old = dict(self.entry, id="old", status="superseded")
        text = pg.index({"patterns": [self.entry, old]})
        self.assertIn("[edge]", text)
        self.assertNotIn("[old]", text)


class RepositoryRegistryTests(unittest.TestCase):
    """The committed registry passes its own checks (the web tree is optional in CI)."""

    def test_repository_registry_is_clean(self):
        report = pg.check(pg.ROOT, pg.web_root())
        self.assertEqual(report.errors, [])


if __name__ == "__main__":
    unittest.main()
