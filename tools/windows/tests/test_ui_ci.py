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
                m.mode_spec(run.mode)
                sizes = run.sizes.split(",")
                for size in sizes:
                    u.preset_op(size)
                # The runner's 1920x1080 desktop holds compact and medium, not wide (1440x900 plus the taskbar).
                self.assertNotIn("wide", sizes)
                self.assertTrue(m.mode_pages(pages, run.mode), "no page runs in this mode")

    def test_modals_run_at_default_and_largest_text(self):
        modal = {(run.mode, run.scan) for run in ci.RUNS if run.pages == "a11y-modals.json"}
        self.assertEqual({("normal", True), ("text-225", True)}, modal)
        large = next(run for run in ci.RUNS if run.pages == "a11y-modals.json" and run.mode == "text-225")
        self.assertIn("compact", large.sizes.split(","))
        self.assertGreaterEqual(large.tabs, 1)

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


if __name__ == "__main__":
    unittest.main()
