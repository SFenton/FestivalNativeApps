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

    def test_first_run_demos_run_at_default_and_largest_text(self):
        """#420 review: the first-run demo journey gates PRs, not just its JSON guard."""
        demos = {run.mode: run for run in ci.RUNS if run.pages == "a11y-first-run-demos.json"}
        self.assertEqual({"normal", "text-225"}, set(demos))
        self.assertTrue(all(run.scan and not run.only for run in demos.values()))
        self.assertIn("compact", demos["text-225"].sizes.split(","))
        self.assertEqual({"compact", "medium"}, set(demos["normal"].sizes.split(",")))

    def test_modals_run_at_default_and_largest_text(self):
        modal = {(run.mode, run.scan) for run in ci.RUNS if run.pages == "a11y-modals.json"}
        self.assertEqual({("normal", True), ("text-225", True)}, modal)
        large = next(run for run in ci.RUNS if run.pages == "a11y-modals.json" and run.mode == "text-225")
        self.assertIn("compact", large.sizes.split(","))
        self.assertGreaterEqual(large.tabs, 1)

    def test_back_keeps_place_runs_at_default_and_largest_text(self):
        """#435: the Back-to-cached-page pages (#82) gate pull requests at 100% and 225% text, with an Axe scan."""
        back = {(run.mode, run.scan, run.only) for run in ci.RUNS if run.pages == "a11y-back-keeps-place.json"}
        self.assertEqual({("normal", True, ""), ("text-225", True, "")}, back)

    def test_settings_pages_wait_for_feedback_rows_before_scrolling(self):
        """#535: the Feedback rows appear above every later Settings section once ``/api/features`` answers, so a target
        scrolled into view before then can be pushed back off screen (``no on-screen element
        id=fst.settings.whats-new`` at 225% text). A CI page that scrolls to Settings content brings those rows in first
        (scrolling back to page chrome such as the Quick Links entry is not a Settings target). Any Feedback row is the
        wait (Feedback pages scroll straight to ``feedback.bug``); a page whose fixture turns features off has none."""
        wait = "scrollinto:id=fst.settings.feedback."
        checked = 0
        for run in ci.RUNS:
            for page in json.loads((ci.JOURNEYS / run.pages).read_text(encoding="utf-8")):
                if page.get("tab") != "settings" and page.get("route") != "/settings":
                    continue
                fixture = page.get("fixture") or []
                if "--features" in fixture and fixture[fixture.index("--features") + 1:][:1] == ["off"]:
                    continue
                steps = [*page.get("setup", ()), *page.get("ready", ()), *page.get("after_ready", ())]
                scrolls = [step for step in steps if step.startswith("scrollinto:id=fst.settings.")]
                if not scrolls:
                    continue
                checked += 1
                with self.subTest(run=run.name, page=page["name"]):
                    self.assertTrue(scrolls[0].startswith(wait) and "@" in scrolls[0], scrolls[0])
                    self.assertGreaterEqual(u.parse_step(scrolls[0])["timeout"], 20)
        self.assertGreater(checked, 0)

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
