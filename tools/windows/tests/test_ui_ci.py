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

    def test_modals_run_at_default_and_largest_text(self):
        modal = {(run.mode, run.scan) for run in ci.RUNS if run.pages == "a11y-modals.json"}
        self.assertEqual({("normal", True), ("text-225", True)}, modal)
        large = next(run for run in ci.RUNS if run.pages == "a11y-modals.json" and run.mode == "text-225")
        self.assertIn("compact", large.sizes.split(","))
        self.assertGreaterEqual(large.tabs, 1)

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
        dispatch = text.index("python tools/windows/ui_ci.py --shard")
        self.assertLess(display, dispatch)
        self.assertLess(build, dispatch)
        self.assertNotIn("--live", text)  # fixtures only: no service calls from CI

    def test_one_registry_and_dispatcher(self):
        """Accessibility pages and feature journeys share the one ``windows-ui`` aggregate check."""
        self.assertFalse((ci.JOURNEYS / "ci-ui.json").exists())
        self.assertTrue((ci.JOURNEYS.parent / "ci_ui.py").exists())
        native = (_REPO / ".github" / "workflows" / "native.yml").read_text(encoding="utf-8")
        self.assertNotIn("a11y_matrix", native)
        self.assertNotIn("ui_ci.py", native)

    def test_generated_runs_cover_fixture_a11y_pages(self):
        """Every fixture-backed a11y page runs in CI (in its first declared mode, or normal and large text) unless it
        is ``live_only`` or visibly skipped."""
        skips = json.loads((ci.JOURNEYS.parent / "ci_skip.json").read_text(encoding="utf-8")).get("a11y_pages", {})
        covered = {(run.pages, page) for run in ci.RUNS
                   for page in (run.only.split(",") if run.only else
                                [item["name"] for item in json.loads((ci.JOURNEYS / run.pages).read_text(encoding="utf-8"))])}
        for source in ci.JOURNEYS.glob("a11y-*.json"):
            for page in json.loads(source.read_text(encoding="utf-8")):
                name = page["name"]
                if "live" not in name.lower() and not page.get("live_only") and name not in skips:
                    self.assertIn((source.name, name), covered)


if __name__ == "__main__":
    unittest.main()
