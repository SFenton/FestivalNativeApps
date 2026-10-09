"""``windows-ui`` CI dispatcher (``ui_ci.py``) and its workflow (issue #400).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import ui_ci as ci
from tools.windows import uiwin as u

_REPO = Path(__file__).resolve().parents[3]
_WORKFLOW = _REPO / ".github" / "workflows" / "windows-ui.yml"


class UiCiTests(unittest.TestCase):
    """Every run is valid and the workflow builds the app and calls the dispatcher."""

    def test_runs_are_valid(self):
        names = [run.name for run in ci.RUNS]
        self.assertEqual(len(names), len(set(names)))
        for run in ci.RUNS:
            with self.subTest(run=run.name):
                pages = json.loads((ci.JOURNEYS / run.pages).read_text(encoding="utf-8"))
                self.assertTrue(run.pages.startswith("a11y"))
                if run.only:
                    names = {page["name"] for page in pages}
                    only = run.only.split(",")
                    self.assertLessEqual(set(only), names, "--only names a missing page")
                    pages = [page for page in pages if page["name"] in only]
                m.mode_spec(run.mode)
                sizes = run.sizes.split(",")
                for size in sizes:
                    u.preset_op(size)
                # The runner's 1920x1080 desktop holds compact and medium, not wide (1440x900 plus the taskbar).
                self.assertNotIn("wide", sizes)
                self.assertTrue(m.mode_pages(pages, run.mode), "no page runs in this mode")
                for page in pages:
                    self.assertLessEqual(set(page.get("axe_allow", ())), set(m.AXE_ALLOW), page["name"])

    def test_quick_links_landing_runs_at_default_and_largest_text(self):
        landing = {run.mode: run for run in ci.RUNS if run.pages == "a11y-quick-links-landing.json"}
        self.assertEqual({"normal", "text-225"}, set(landing))
        self.assertTrue(all(run.scan for run in landing.values()))
        self.assertIn("compact", landing["text-225"].sizes.split(","))

    def test_modals_run_at_default_and_largest_text(self):
        modal = {(run.mode, run.scan) for run in ci.RUNS if run.pages == "a11y-modals.json"}
        self.assertEqual({("normal", True), ("text-225", True)}, modal)
        large = next(run for run in ci.RUNS if run.pages == "a11y-modals.json" and run.mode == "text-225")
        self.assertIn("compact", large.sizes.split(","))
        self.assertGreaterEqual(large.tabs, 1)

    def test_modal_motion_runs_at_default_largest_text_and_motion_off(self):
        """#436: the #83 work-behind-dialogs journey gates PRs with motion on, at 225% text and with motion off."""
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-modal-motion.json"}
        self.assertEqual({"normal", "text-225", "no-animations"}, set(runs))
        self.assertTrue(all(run.scan and not run.only for run in runs.values()))
        pages = json.loads((ci.JOURNEYS / "a11y-modal-motion.json").read_text(encoding="utf-8"))
        names = {mode: {page["name"] for page in m.mode_pages(pages, mode)} for mode in runs}
        for mode in ("normal", "text-225"):
            self.assertLessEqual({"mm-first-run-backdrop", "mm-whats-new-backdrop", "mm-first-run-shop-pulses"}, names[mode])
        self.assertLessEqual({"mm-first-run-backdrop-static", "mm-first-run-shop-pulses-static"}, names["no-animations"])
        shop = next(page for page in pages if page["name"] == "mm-first-run-shop-pulses")
        steps = shop["after_ready"]
        for check in ("assertname:id=fst.first-run.slides|Item Shop", "assertread:id=SecondaryButton|Back, button",
                      "assertorder:id=fst.first-run.slides|id=PrimaryButton|id=SecondaryButton|id=fst.first-run.close",
                      "assertsize:id=fst.first-run.close|40x40", "key:enter"):
            self.assertIn(check, steps)

    def test_songs_filter_runs_at_default_and_largest_text(self):
        # Issue #432 (#77): the no-profile Filter flyout's accessibility pages run in CI at default and 225% text.
        runs = {(run.mode, run.scan) for run in ci.RUNS if run.pages == "a11y-songs-filter.json"}
        self.assertEqual({("normal", True), ("text-225", True)}, runs)
        pages = json.loads((ci.JOURNEYS / "a11y-songs-filter.json").read_text(encoding="utf-8"))
        names = {page["name"] for page in pages}
        self.assertTrue({"songs-filter-anonymous", "songs-filter-anonymous-year", "kb-songs-filter-anonymous"} <= names)
        for page in pages:
            with self.subTest(page=page["name"]):
                self.assertNotIn("profile", page)  # no selected player: the General-only drawer
                steps = page.get("after_ready", [])
                self.assertTrue(any(s.startswith(("assertread:", "assertfocus:")) for s in steps))
        steps = [s for page in pages for s in page.get("after_ready", [])]
        for target in ("fst.songs.filter|", "fst.songs.filter.reset|", "fst.songs.filter.year.select-all|",
                       "fst.songs.filter.year.clear-all|"):
            self.assertIn(f"assertsize:id={target}40x40", steps)

    def test_argv(self):
        run = ci.Run("x", "a11y-modals.json", sizes="compact", mode="text-225", tabs=30)
        argv = run.argv(Path("C:/out"), "debug")
        self.assertEqual(argv[argv.index("--mode") + 1], "text-225")
        self.assertEqual(argv[argv.index("--out") + 1], str(Path("C:/out") / "x"))
        self.assertEqual(argv[argv.index("--pages") + 1], str(ci.JOURNEYS / "a11y-modals.json"))
        self.assertIn("--scan", argv)
        self.assertEqual(argv[-2:], ["--exe", "debug"])
        self.assertNotIn("--scan", ci.Run("y", "a11y-modals.json", scan=False).argv(Path("C:/out")))
        self.assertNotIn("--only", argv)
        only = ci.Run("z", "a11y-section-index.json", only="a,b").argv(Path("C:/out"))
        self.assertEqual(only[only.index("--only") + 1], "a,b")

    def test_select(self):
        self.assertEqual(ci.select(ci.RUNS, None), list(ci.RUNS))
        self.assertEqual([r.name for r in ci.select(ci.RUNS, "modals-text-225")], ["modals-text-225"])
        with self.assertRaises(ValueError):
            ci.select(ci.RUNS, "nope")

    def test_list_needs_no_desktop(self):
        self.assertEqual(ci.main(["--list"]), 0)

    def test_workflow_builds_and_dispatches(self):
        text = _WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("runs-on: windows-latest", text)
        self.assertIn("pull_request:", text)
        for path in ("'windows/**'", "'tools/windows/**'", "'.github/workflows/windows-ui.yml'"):
            self.assertIn(path, text)
        build, display = text.index("tools/windows/build.ps1"), text.index("tools/windows/ci_display.ps1")
        dispatch = text.index("python tools/windows/ui_ci.py --out")
        self.assertLess(display, dispatch)
        self.assertLess(build, dispatch)
        self.assertNotIn("--live", text)  # fixtures only: no service calls from CI

    def test_one_registry_and_dispatcher(self):
        """#415 review: ``RUNS`` + ``windows-ui.yml`` is the only accessibility-journey gate; no second manifest or job
        (``native.yml`` lacked the hard-failing ``ci_display.ps1`` and let wide/compact clamp silently)."""
        self.assertFalse((ci.JOURNEYS / "ci-ui.json").exists())
        self.assertFalse((ci.JOURNEYS.parent / "ci_ui.py").exists())
        native = (_REPO / ".github" / "workflows" / "native.yml").read_text(encoding="utf-8")
        self.assertNotIn("a11y_matrix", native)
        self.assertNotIn("ui_ci.py", native)


if __name__ == "__main__":
    unittest.main()
