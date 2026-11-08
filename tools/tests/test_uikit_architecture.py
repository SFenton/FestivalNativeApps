"""Tests for fail-closed ownership and explicit UIKit lifecycle inventory."""

import tempfile
import unittest
from pathlib import Path

from tools.uikit_architecture import SOURCE, main, refresh, validate


class UIKitArchitectureTests(unittest.TestCase):
    """Bind ownership to actual source instead of counts or inherited labels."""

    def make_source(self, root, name, source):
        """Create a small UIKit fixture under the actual discovery boundary."""
        path = root / SOURCE / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("#if os(iOS)\n" + source + "\n#endif\n", encoding="utf-8")

    def test_new_and_changed_sources_require_fresh_review(self):
        """A previous complete list cannot accept an unseen page or changed implementation."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_source(root, "Screen.swift", "class UKScreenViewController: UIViewController {}")
            contract = refresh(root, {})
            self.assertEqual(validate(contract, root=root), [])
            self.make_source(root, "Page.swift", "class UKPageViewController: UKScreenViewController {}")
            self.assertTrue(any("unreviewed new" in error for error in validate(contract, root=root)))
            contract = refresh(root, contract)
            contract["files"][0]["disposition"] = "shared-component"
            self.make_source(root, "Page.swift", "class UKPageViewController: UKScreenViewController { let added = 1 }")
            self.assertTrue(any("source changed" in error for error in validate(contract, root=root)))
            updated = refresh(root, contract)
            self.assertEqual(updated["files"][0]["disposition"], "pending")

    def test_controller_cannot_bypass_shared_lifecycle(self):
        """A file record does not excuse a feature-local UIViewController base."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_source(root, "Page.swift", "class UKFeatureViewController: UIViewController {}")
            errors = validate(refresh(root, {}), root=root)
        self.assertTrue(any("bypasses UKScreenViewController" in error for error in errors))

    def test_swizzling_and_hosting_are_not_architecture_completion(self):
        """Declared ownership still rejects global appearance interception and SwiftUI rendering."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_source(root, "Hook.swift", "import SwiftUI\nmethod_exchangeImplementations(a, b)")
            errors = validate(refresh(root, {}), root=root)
        self.assertTrue(any("global method swizzling" in error for error in errors))
        self.assertTrue(any("SwiftUI rendering" in error for error in errors))

    def test_controller_name_does_not_hide_unowned_lifecycle(self):
        """A renamed or indirectly derived controller still needs the screen foundation."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_source(root, "Hidden.swift", "class UKHidden: UITableViewController {}\nclass UKChild: UKHidden {}")
            errors = validate(refresh(root, {}), root=root)
        self.assertEqual(sum("bypasses UKScreenViewController" in error for error in errors), 2)

    def test_nonprefixed_controller_is_still_discovered(self):
        """A different class prefix cannot evade the controller ownership guard."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_source(root, "Renamed.swift", "class Renamed: UIViewController {}")
            errors = validate(refresh(root, {}), root=root)
        self.assertTrue(any("Renamed bypasses" in error for error in errors))

    def test_feature_local_presentation_cannot_bypass_the_window_owner(self):
        """Native task and alert sites must use the central admission lifecycle."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_source(root, "Sheet.swift", "func show() { self.present(sheet, animated: true) }")
            errors = validate(refresh(root, {}), root=root)
        self.assertTrue(any("presentation bypasses" in error for error in errors))

    def test_strict_gate_does_not_accept_pending_or_missing_verification(self):
        """An inventory alone is not a completed full pass."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_source(root, "Component.swift", "class UKComponent: UIView {}")
            errors = validate(refresh(root, {}), root=root, strict=True)
        self.assertTrue(any("review is pending" in error for error in errors))
        self.assertTrue(any("verification references" in error for error in errors))

    def test_explicit_review_cannot_accept_changed_source(self):
        """A review command cannot bless a different source snapshot implicitly."""
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.make_source(root, "Component.swift", "class UKComponent: UIView {}")
            main(["--root", str(root), "--refresh"])
            proof = root / "proof.txt"
            proof.write_text("source review reference")
            arguments = [
                "--root", str(root), "--review", f"{SOURCE}/Component.swift",
                "--owner", "UKComponent", "--disposition", "shared-component",
                "--note", "Canonical native component", "--verification", "proof.txt",
            ]
            self.assertEqual(main(arguments), 0)
            self.assertEqual(main(["--root", str(root), "--strict"]), 0)
            self.make_source(root, "Component.swift", "class UKComponent: UIView { let changed = 1 }")
            with self.assertRaises(SystemExit):
                main(arguments)


if __name__ == "__main__":
    unittest.main()
