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
                self.assertTrue(any(m.page_sizes(page, sizes, run.mode) for page in m.mode_pages(pages, run.mode)),
                                "no page runs at this run's sizes")
                for page in pages:
                    self.assertLessEqual(set(page.get("axe_allow", ())), set(m.AXE_ALLOW), page["name"])

    def test_quick_links_landing_runs_at_default_and_largest_text(self):
        landing = {run.mode: run for run in ci.RUNS if run.pages == "a11y-quick-links-landing.json"}
        self.assertEqual({"normal", "text-225"}, set(landing))
        self.assertTrue(all(run.scan for run in landing.values()))
        self.assertIn("compact", landing["text-225"].sizes.split(","))

    def test_song_band_pinned_runs_at_default_and_largest_text(self):
        # Issue #461 (#306): the full band board's pinned "your band" row runs in CI at default and 225% text.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-song-band-pinned.json"}
        self.assertEqual({"normal", "text-225"}, set(runs))
        self.assertTrue(all(run.scan for run in runs.values()))
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        pages = json.loads((ci.JOURNEYS / "a11y-song-band-pinned.json").read_text(encoding="utf-8"))
        names = {page["name"] for page in pages}
        self.assertTrue({"song-band-pin-jump", "song-band-pin-open", "song-band-pin-no-player"} <= names)

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

    def test_whats_new_runs_grouped_notes_at_default_and_largest_text(self):
        # Issue #434: #80's grouped tester/store notes are checked in CI, with heading levels, at default and 225% text.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-whats-new.json"}
        self.assertEqual({"normal", "text-225"}, set(runs))
        self.assertTrue(all(run.scan for run in runs.values()))
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        pages = {page["name"]: page for page in json.loads((ci.JOURNEYS / "a11y-whats-new.json").read_text(encoding="utf-8"))}
        for name in ("whats-new-tester-grouped", "whats-new-store-grouped", "kb-whats-new-tester-grouped"):
            self.assertIn(name, pages)
        for name in ("whats-new-tester-grouped", "whats-new-store-grouped"):
            steps = pages[name]["after_ready"]
            self.assertIn("assertstate:id=fst.whats-new.section.0|heading=2", steps)
            self.assertIn("assertstate:id=fst.whats-new.group.0.0|heading=3", steps)
            self.assertIn("assertsize:id=fst.whats-new.dismiss|40x40", steps)
            self.assertTrue(any(step.startswith("assertorder:id=fst.whats-new.list|id=fst.whats-new.section.0|") for step in steps))

    def test_back_keeps_place_runs_at_default_and_largest_text(self):
        """#435: the Back-to-cached-page pages (#82) gate pull requests at 100% and 225% text, with an Axe scan."""
        back = {(run.mode, run.scan, run.only) for run in ci.RUNS if run.pages == "a11y-back-keeps-place.json"}
        self.assertEqual({("normal", True, ""), ("text-225", True, "")}, back)

    def test_settings_pages_wait_for_feedback_rows_before_scrolling(self):
        """#535: the Feedback rows appear above every later Settings section once ``/api/features`` answers, so a target
        scrolled into view before then can be pushed back off screen (``no on-screen element
        id=fst.settings.whats-new`` at 225% text). A CI page that scrolls to Settings content brings those rows in first
        (scrolling back to page chrome such as the Quick Links entry is not a Settings target)."""
        wait = "scrollinto:id=fst.settings.feedback.feature"
        checked = 0
        for run in ci.RUNS:
            for page in json.loads((ci.JOURNEYS / run.pages).read_text(encoding="utf-8")):
                if page.get("tab") != "settings" and page.get("route") != "/settings":
                    continue
                steps = [*page.get("setup", ()), *page.get("ready", ()), *page.get("after_ready", ())]
                scrolls = [step for step in steps if step.startswith("scrollinto:id=fst.settings.")]
                if not scrolls:
                    continue
                checked += 1
                with self.subTest(run=run.name, page=page["name"]):
                    self.assertTrue(scrolls[0].startswith(wait + "@"), scrolls[0])
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

    def test_songs_section_push_runs_at_default_and_largest_text(self):
        # Issue #452 (#288): the pushed section title's Narrator names, headings, order and raw copy, in CI at both sizes.
        runs = {(run.mode, run.scan) for run in ci.RUNS if run.pages == "a11y-songs-section-push.json"}
        self.assertEqual({("normal", True), ("text-225", True)}, runs)
        pages = json.loads((ci.JOURNEYS / "a11y-songs-section-push.json").read_text(encoding="utf-8"))
        self.assertEqual({"push-band", "push-band-reverse", "push-band-keyboard"}, {page["name"] for page in pages})
        for page in pages:
            with self.subTest(page=page["name"]):
                steps = page["after_ready"]
                inset = steps.index("scrollinset:name=M&class=TextBlock|id=fst.songs.list|16")
                drawn = steps.index("assertname:raw=fst.songs.section-header.incoming|M")
                self.assertLess(inset, drawn)  # inside the 40 epx push band the copy is drawn...
                self.assertEqual(steps[drawn + 1], "waitgone:id=fst.songs.section-header.incoming@2")  # ...but raw
                self.assertIn("assertread:id=fst.songs.section-header|L, text", steps[drawn:])
                self.assertIn("assertread:name=M&class=TextBlock|M, text", steps[drawn:])
                self.assertTrue(any(s.startswith("assertorder:id=fst.songs.section-index-button|id=fst.songs.section-header|"
                                                  "name=M&class=TextBlock") for s in steps))
        for page in (p for p in pages if p["name"] != "push-band-keyboard"):  # at 120 epx the copy is gone again
            steps = page["after_ready"]
            self.assertIn("waitgone:raw=fst.songs.section-header.incoming@3", steps[steps.index(
                "scrollinset:name=M&class=TextBlock|id=fst.songs.list|120"):])

    def test_songs_section_push_keyboard_keeps_focus_on_real_list_items(self):
        # Issue #452 review: a keyboard pick reaches M, then focus moves by arrow keys through the 16 epx push band; it
        # stays on the real row/header (never the raw copy), leaves the band by Up and Tab still re-enters the list.
        pages = {page["name"]: page for page in json.loads(
            (ci.JOURNEYS / "a11y-songs-section-push.json").read_text(encoding="utf-8"))}
        steps = pages["push-band-keyboard"]["after_ready"]
        self.assertEqual(["focus:id=fst.songs.section-index-button", "key:enter"], steps[:2])
        self.assertEqual(13, steps.count("key:right"))  # # -> M across the Jump grid, by keys only
        self.assertLess(steps.index("assertfocus:name=M@3"), steps.index("key:enter", 2))
        inset = steps.index("scrollinset:name=M&class=TextBlock|id=fst.songs.list|16")
        in_band = steps[inset:]
        row, header, out = (in_band.index("assertfocus:id=fst.songs.row.fixture-song-56@3"),
                            in_band.index("assertfocus:name=M&class=ListViewHeaderItem@3"),
                            in_band.index("assertfocus:id=fst.songs.row.fixture-song-49@3"))
        self.assertLess(row, header)
        self.assertLess(header, out)
        for focused in (row, header):  # focus on a real item while the copy is drawn and out of the control view
            self.assertEqual("assertname:raw=fst.songs.section-header.incoming|M",
                             next(s for s in in_band[focused:] if s.startswith("assertname:raw=")))
            self.assertIn("waitgone:id=fst.songs.section-header.incoming@2", in_band[focused:out])
        self.assertEqual("key:up", in_band[out - 2])
        self.assertEqual("waitgone:raw=fst.songs.section-header.incoming@3", in_band[out + 1])
        self.assertEqual(["focus:id=fst.songs.section-index-button", "key:tab", "wait:1",
                          "assertfocus:id=fst.songs.row.fixture-song-56@3"], steps[-4:])

    def test_load_swap_runs_every_page(self):
        # Issue #431 (#71) review: every load-swap page (normal, 225% text, Reduce Motion and Animation effects off)
        # runs in windows-ui, Axe-scanned, at a size the page supports.
        runs = [run for run in ci.RUNS if run.pages == "a11y-load-swap.json"]
        self.assertEqual({"normal", "text-225", "no-animations"}, {run.mode for run in runs})
        self.assertTrue(all(run.scan and not run.only for run in runs))
        pages = json.loads((ci.JOURNEYS / "a11y-load-swap.json").read_text(encoding="utf-8"))
        covered = {page["name"] for run in runs for page in m.mode_pages(pages, run.mode)
                   if m.page_sizes(page, run.sizes.split(","), run.mode)}
        self.assertEqual({page["name"] for page in pages}, covered)
        self.assertIn("load-swap-full-rankings-motion-system", covered)

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
