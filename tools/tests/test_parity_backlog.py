"""Keep the source-backed native migration checklist complete and honest."""

import copy
import json
import unittest

from tools.parity_backlog import BACKLOG, PRODUCT, ready, validate


class ParityBacklogTests(unittest.TestCase):
    """Require every source route and a valid execution dependency graph."""

    @classmethod
    def setUpClass(cls):
        """Read real, versioned product and backlog manifests."""
        cls.backlog = json.loads(BACKLOG.read_text(encoding="utf-8"))
        cls.product = json.loads(PRODUCT.read_text(encoding="utf-8"))

    def test_all_product_routes_have_real_gap_and_feature_owner(self):
        """No static native placeholder may be mistaken for migrated content."""
        self.assertEqual(validate(self.backlog, self.product), [])
        self.assertEqual(len(self.backlog["routes"]), 23)  # Manual is deprecated
        self.assertTrue(all(route["apple"] != "verified" for route in self.backlog["routes"]))

    def test_new_or_missing_route_must_enter_the_backlog(self):
        """Changes to the source route inventory cannot silently bypass planning."""
        draft = copy.deepcopy(self.backlog)
        draft["routes"].pop()
        self.assertTrue(any("Missing product route" in error for error in validate(draft, self.product)))
        draft = copy.deepcopy(self.backlog)
        draft["routes"].append(copy.deepcopy(draft["routes"][0]))
        self.assertTrue(any("duplicate id" in error for error in validate(draft, self.product)))
        draft["routes"][-1]["id"] = "unknown-route"
        self.assertTrue(any("Unknown product route" in error for error in validate(draft, self.product)))

    def test_citations_acceptance_and_route_owners_are_required(self):
        """A to-do with no source or measurable outcome is not actionable."""
        draft = copy.deepcopy(self.backlog)
        draft["epics"][0]["sourceRefs"] = ["FortniteFestivalWeb/src/App.tsx"]
        draft["epics"][0]["acceptance"] = [""]
        draft["routes"][0]["epics"] = ["made-up-epic"]
        errors = validate(draft, self.product)
        self.assertTrue(any("source file and line" in error for error in errors))
        self.assertTrue(any("acceptance" in error for error in errors))
        self.assertTrue(any("unknown epic" in error for error in errors))

    def test_shared_package_citations_allow_only_reviewed_source_roots(self):
        """Core/theme feature files are valid; other packages and traversal fail closed."""
        draft = copy.deepcopy(self.backlog)
        draft["epics"][0]["sourceRefs"] = ["packages/core/src/app/formatters.ts:145"]
        self.assertEqual(validate(draft, self.product), [])
        draft["epics"][0]["sourceRefs"] = ["packages/unknown/src/app/formatters.ts:145"]
        self.assertTrue(any("cite at least one source file and line" in error
                            for error in validate(draft, self.product)))
        draft["epics"][0]["sourceRefs"] = ["packages/core/../../secrets.ts:1"]
        self.assertTrue(any("cite at least one source file and line" in error
                            for error in validate(draft, self.product)))

    def test_bad_json_field_types_fail_as_errors(self):
        """Malformed status objects and missing page IDs cannot crash the gate."""
        backlog = copy.deepcopy(self.backlog)
        product = copy.deepcopy(self.product)
        backlog["epics"][0]["status"] = {"not": "a state"}
        backlog["routes"][0]["apple"] = ["not", "a state"]
        product["pages"][0]["id"] = None
        errors = validate(backlog, product)
        self.assertTrue(any("invalid status" in error for error in errors))
        self.assertTrue(any("invalid Apple state" in error for error in errors))
        self.assertTrue(any("invalid route id" in error for error in errors))

    def test_unfinished_dependencies_and_cycles_fail_closed(self):
        """Epic completion must not precede its prerequisite or create a loop."""
        draft = copy.deepcopy(self.backlog)
        draft["epics"][1]["status"] = "done"
        errors = validate(draft, self.product)
        self.assertTrue(any("marked done before dependency" in error for error in errors))
        draft = copy.deepcopy(self.backlog)
        draft["epics"][0]["dependsOn"] = ["native-profile-selector"]
        self.assertTrue(any("cyclic dependency" in error for error in validate(draft, self.product)))

    def test_only_unblocked_work_is_ready(self):
        """The closed Windows host and unresolved service gate are not green tasks."""
        queued = {epic["id"] for epic in ready(self.backlog)}
        self.assertIn("native-visual-a11y-performance", queued)
        self.assertNotIn("native-profile-selector", queued)
        self.assertNotIn("android-windows-parity", queued)

    def test_blocked_epic_must_name_the_actual_external_gate(self):
        """An external 403 or powered-off host may not look like ready work."""
        draft = copy.deepcopy(self.backlog)
        blocked = next(e for e in draft["epics"] if e["status"] == "blocked")
        blocked["blockedOn"] = ""
        self.assertTrue(any("blocked work needs an explicit blocker" in error
                            for error in validate(draft, self.product)))

    def test_product_cannot_claim_ported_route_while_apple_is_partial(self):
        """Coverage and native evidence are needed before manifest status changes."""
        product = copy.deepcopy(self.product)
        product["pages"][1]["status"] = "implemented"
        self.assertTrue(any("before Apple verification" in error
                            for error in validate(self.backlog, product)))


if __name__ == "__main__":
    unittest.main()
