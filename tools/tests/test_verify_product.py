"""Tests for fail-closed page, state and evidence inventory validation."""

import copy
import json
import tempfile
import unittest
from pathlib import Path

from tools.verify_product import ROOT, validate_product


class ProductValidationTests(unittest.TestCase):
    """Ensure missing controls or platform evidence cannot pass parity gates."""

    @classmethod
    def setUpClass(cls):
        """Read the same inventory used by the repository's CI gate."""
        cls.manifest = json.loads((ROOT / "contracts/product.json").read_text(encoding="utf-8"))

    def test_current_inventory_is_structurally_valid(self):
        """A scaffold can pass structure checks without claiming completed parity."""
        self.assertEqual(validate_product(self.manifest, root=ROOT), [])

    def test_strict_mode_rejects_pending_surfaces(self):
        """A route inventory is not evidence of a completed native product."""
        self.assertTrue(any(
            "pending page" in error
            for error in validate_product(self.manifest, root=ROOT, strict=True)
        ))

    def test_rejects_duplicate_route_and_unknown_guard(self):
        """Duplicated screens and missing guard rules fail even without strict mode."""
        manifest = copy.deepcopy(self.manifest)
        manifest["pages"][1]["path"] = manifest["pages"][0]["path"]
        manifest["pages"][1]["guard"] = "secret"
        errors = validate_product(manifest, root=ROOT)
        self.assertTrue(any("duplicate route" in error for error in errors))
        self.assertTrue(any("unknown route guard" in error for error in errors))

    def test_implemented_control_requires_every_platform_and_state(self):
        """Valid-looking tests on one host cannot mask missing cross-platform states."""
        manifest = copy.deepcopy(self.manifest)
        control = manifest["controls"][0]
        control["status"] = "implemented"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "control.md").write_text("# Meter\n", encoding="utf-8")
            (root / "control.test").write_text("tested\n", encoding="utf-8")
            control["spec"] = "control.md"
            control["evidence"] = {
                "ios": {
                    "tests": ["control.test"],
                    "visual": ["control.test"],
                    "accessibility": ["control.test"],
                    "states": ["one"],
                }
            }
            errors = validate_product(manifest, root=root)
        self.assertTrue(any("evidence platforms" in error for error in errors))
        self.assertTrue(any("ios: states must cover" in error for error in errors))

    def test_native_source_ids_must_match_static_or_dynamic_registry(self):
        """Handwritten IDs may not silently bypass the semantic test registry."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "apple/Sources/Feature/Example.swift"
            source.parent.mkdir(parents=True)
            source.write_text(
                'view.accessibilityIdentifier("fst.songs.row.\\(song.id)")',
                encoding="utf-8",
            )
            self.assertEqual(validate_product(self.manifest, root=root), [])
            source.write_text(
                'view.accessibilityIdentifier("fst.song-detail.leaderboard.Solo_Guitar")',
                encoding="utf-8",
            )
            self.assertEqual(validate_product(self.manifest, root=root), [])
            source.write_text(
                'view.accessibilityIdentifier("fst.unfamiliar-area.unknown-control")',
                encoding="utf-8",
            )
            errors = validate_product(self.manifest, root=root)
        self.assertTrue(any("unregistered native test ID" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
