"""`tools/ci_journeys.py` runs apple-ci's journey steps locally (SwiftUI app or UIKit port).

These check the step expansion and the script rewrites against a small workflow and the real
one, without running a simulator.
"""

import os
import socket
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import ci_journeys  # noqa: E402
import ios_sim  # noqa: E402

WORKFLOW = {
    "jobs": {
        "build": {"steps": [
            {"name": "Build", "run": "xcodebuild build"},
            {"name": "Journeys", "env": {"JOURNEYS": "A/testOne B/testTwo"},
             "run": 'device=$(python3 tools/ios_sim.py ci-device)\npython3 tools/ios_sim.py uitest --device "$device"'},
        ]},
        "legs": {
            "strategy": {"matrix": {"include": [
                {"leg": "ipad", "device_type": "iPad Pro 11-inch (M5)", "uitest_args": "--app ipad"},
                {"leg": "duo", "device_type": "iPhone Duo", "uitest_args": "--pose folded"},
            ]}},
            "steps": [{"name": "Filter ${{ matrix.leg }}", "env": {"JOURNEYS": "${{ matrix.leg }}"},
                       "run": "python3 tools/ios_sim.py uitest ${{ matrix.uitest_args }} ${{ secrets.X }}\n"
                              "python3 tools/ios_sim.py shutdown --device \"$udid\""}],
        },
    }
}


class StepsTests(unittest.TestCase):
    def test_only_uitest_steps_are_listed_once_per_leg(self):
        steps = ci_journeys.journey_steps(WORKFLOW)
        self.assertEqual([(s["job"], s["leg"]) for s in steps], [("build", ""), ("legs", "ipad"), ("legs", "duo")])

    def test_matrix_values_substitute_and_other_expressions_drop(self):
        ipad = ci_journeys.journey_steps(WORKFLOW)[1]
        self.assertEqual(ipad["env"]["JOURNEYS"], "ipad")
        self.assertIn("uitest --app ipad ", ipad["run"])
        self.assertNotIn("${{", ipad["run"])

    def test_legs_get_their_local_device(self):
        steps = ci_journeys.journey_steps(WORKFLOW)
        self.assertEqual(steps[1]["env"]["FST_CI_DEVICE"], "ipad")
        self.assertEqual(steps[2]["env"]["FST_CI_DEVICE"], "duo")
        self.assertNotIn("FST_CI_DEVICE", steps[0]["env"])

    def test_ci_devices_become_local_aliases_and_shutdowns_are_skipped(self):
        steps = ci_journeys.journey_steps(WORKFLOW)
        build = ci_journeys.localize(steps[0]["run"])
        self.assertIn("device=$(fst_local_device)", build)
        self.assertNotIn("ci-device", build)
        legs = ci_journeys.localize(steps[1]["run"])
        self.assertNotIn("ios_sim.py shutdown", legs)
        self.assertEqual(ci_journeys.local_alias("iPhone 17 Pro"), "iphone")

    def test_the_real_workflow_lists_iphone_ipad_and_duo_journeys(self):
        steps = ci_journeys.journey_steps(ci_journeys.load_workflow())
        self.assertGreater(len(steps), 5)
        legs = {step["env"].get("FST_CI_DEVICE") for step in steps}
        self.assertTrue({"iphone", "ipad", "duo"} <= legs)
        for step in steps:
            self.assertNotIn("${{", step["run"], step["name"])


class ProductFamilyTests(unittest.TestCase):
    def test_uikit_family_maps_swiftui_products(self):
        with mock.patch.dict(os.environ, {"FST_SIM_PRODUCT_FAMILY": "uikit"}):
            self.assertEqual(ios_sim.select_product(None, "iphone").scheme, "FestivalMobileUIKit")
            self.assertEqual(ios_sim.select_product(None, "ipad").scheme, "FestivalMobileUIKitIPad")
            self.assertEqual(ios_sim.select_product("phone", None).scheme, "FestivalMobileUIKit")

    def test_default_family_is_unchanged(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("FST_SIM_PRODUCT_FAMILY", None)
            self.assertEqual(ios_sim.select_product(None, "ipad").scheme, "FestivalMobileIPad")
            self.assertEqual(ios_sim.select_product("uikit", None).scheme, "FestivalMobileUIKit")


class FullPassSafetyTests(unittest.TestCase):
    def test_owned_devices_replace_aliases_and_ci_created_devices(self):
        device = "F01963C1-E549-4A85-B93B-EA0CE260F908"
        script = ci_journeys.localize(
            'device=$(python3 tools/ios_sim.py ci-device --type "iPhone Duo")\n'
            'python3 tools/ios_sim.py uitest --device duo --only A/testOne',
            {"duo": device},
        )
        self.assertIn(f"echo {device}", script)
        self.assertIn(f"--device {device}", script)
        self.assertIn("uitest --fail-on-skip", script)
        self.assertIn("--owned-device", script)

    def test_changed_source_cannot_resume_previous_acceptance(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "apple/Sources/Page.swift"
            source.parent.mkdir(parents=True)
            source.write_text("before")
            out = root / "evidence"
            out.mkdir()
            ci_journeys.bind_provenance(out, {"app": "uikit"}, root=root)
            source.write_text("after")
            with self.assertRaisesRegex(SystemExit, "source/configuration changed"):
                ci_journeys.bind_provenance(out, {"app": "uikit"}, root=root)

    def test_occupied_fixture_listener_is_left_running(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            port = listener.getsockname()[1]
            with self.assertRaisesRegex(SystemExit, "leave its owner untouched"):
                ci_journeys.require_free_ports(f"python3 tools/mock_service.py --port {port}")
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                pass

    def test_resuming_failed_step_preserves_failure_instead_of_returning_success(self):
        steps = ci_journeys.journey_steps(WORKFLOW)[:1]
        with tempfile.TemporaryDirectory() as temporary:
            out = Path(temporary)
            key = "build/-/Journeys"
            (out / "summary.tsv").write_text(f"{key}\t65\t10\tuitest: failed\n")
            with mock.patch.object(ci_journeys, "load_workflow", return_value=WORKFLOW), \
                 mock.patch.object(ci_journeys, "bind_provenance"), \
                 mock.patch.object(ci_journeys, "run_step") as run:
                code = ci_journeys.main(["--app", "uikit", "--out", str(out), "--job", "build"])
            self.assertEqual(code, 65)
            run.assert_not_called()

    def test_zero_summary_is_not_a_passing_ui_step(self):
        step = {"job": "test", "leg": "", "name": "zero", "env": {}, "run": "true"}
        with tempfile.TemporaryDirectory() as temporary:
            with mock.patch.object(ios_sim, "run_bounded", return_value=0) as run:
                code, _, summary = ci_journeys.run_step(0, step, Path(temporary), "uikit")
            self.assertEqual(run.call_args.kwargs["env"]["FST_UITEST_KEEP_RESULTS"], "1")
        self.assertNotEqual(code, 0)
        self.assertIn("not acceptance evidence", summary)

    def test_source_change_during_step_cannot_write_acceptance(self):
        with tempfile.TemporaryDirectory() as temporary:
            out = Path(temporary)
            with mock.patch.object(ci_journeys, "load_workflow", return_value=WORKFLOW), \
                 mock.patch.object(ci_journeys, "bind_provenance",
                                   side_effect=[None, None, SystemExit("source/configuration changed")]), \
                 mock.patch.object(ci_journeys, "run_step", return_value=(0, 1, "uitest: passed")):
                with self.assertRaisesRegex(SystemExit, "source/configuration changed"):
                    ci_journeys.main(["--app", "uikit", "--out", str(out), "--job", "build"])
            self.assertFalse((out / "summary.tsv").exists())


if __name__ == "__main__":
    unittest.main()
