"""``windows-ui`` CI dispatcher (``ui_ci.py``) and its workflow (issue #400).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools.windows import a11y_matrix as m
from tools.windows import profile_fixture
from tools.windows import ui_ci as ci
from tools.windows import uiwin as u

_REPO = Path(__file__).resolve().parents[3]
_WORKFLOW = _REPO / ".github" / "workflows" / "windows-ui.yml"


class UiCiTests(unittest.TestCase):
    """Every run is valid and the workflow builds the app and calls the dispatcher."""

    def test_shards_weigh_whole_file_runs_by_page_and_size(self):
        """#571: a run without ``only`` executes its whole file, so it must not weigh 1 when balancing shards."""
        whole = next(run for run in ci.RUNS if not run.only and len(ci.run_pages(run)) > 1)
        sizes = whole.sizes.split(",")
        self.assertEqual(ci.run_weight(whole),
                         sum(len(m.page_sizes(page, sizes, whole.mode)) for page in ci.run_pages(whole)))
        self.assertGreater(ci.run_weight(whole), 1)
        runs = ci.tier_runs(list(ci.RUNS), "full")
        workflow = (ci.JOURNEYS.parents[2] / ".github" / "workflows" / "windows-ui.yml").read_text(encoding="utf-8")
        shards = int(workflow.split("--shards ")[1].split()[0])
        self.assertIn(f"shard: [{', '.join(str(n) for n in range(1, shards + 1))}]", workflow)
        buckets = [ci.shard_runs(runs, shard, shards) for shard in range(1, shards + 1)]
        self.assertEqual(sorted(run.name for bucket in buckets for run in bucket), sorted(run.name for run in runs))
        weights = [sum(map(ci.run_weight, bucket)) for bucket in buckets]
        self.assertLessEqual(max(weights) - min(weights), max(map(ci.run_weight, runs)))

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
                # The runner's 1920x1080 desktop (ci_display.ps1) holds compact, medium and wide (1440x900 plus the
                # taskbar); generated runs add wide only for pages that run at no smaller size.
                self.assertLessEqual(set(sizes), {"compact", "medium", "wide"})
                self.assertTrue(m.mode_pages(pages, run.mode), "no page runs in this mode")
                self.assertTrue(any(m.page_sizes(page, sizes, run.mode) for page in m.mode_pages(pages, run.mode)),
                                "no page runs at this run's sizes")
                for page in pages:
                    self.assertLessEqual(set(page.get("axe_allow", ())), set(m.AXE_ALLOW), page["name"])

    def test_songs_last_played_runs_at_default_and_largest_text(self):
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-songs-last-played.json"}
        self.assertEqual(set(runs), {"normal", "text-225"})
        self.assertIn("wide", runs["normal"].sizes.split(","))
        self.assertIn("compact", runs["text-225"].sizes.split(","))

    def test_quick_links_landing_runs_at_default_and_largest_text(self):
        landing = {run.mode: run for run in ci.RUNS if run.pages == "a11y-quick-links-landing.json"}
        self.assertEqual({"normal", "text-225"}, set(landing))
        self.assertTrue(all(run.scan for run in landing.values()))
        self.assertIn("compact", landing["text-225"].sizes.split(","))

    def test_header_flyouts_gate_without_popup_allowance(self):
        """#534: the Rank By, Quick Links, profile and Notifications flyouts scan clean at 100% and 225% text."""
        popups = {run.mode: run for run in ci.RUNS if run.pages == "a11y.json"}
        self.assertEqual({"normal", "text-225"}, set(popups))
        self.assertTrue(all(run.scan and run.only == ci.POPUP_PAGES for run in popups.values()))
        pages = {page["name"]: page for page in json.loads((ci.JOURNEYS / "a11y.json").read_text(encoding="utf-8"))}
        for name in ci.POPUP_PAGES.split(","):
            with self.subTest(page=name):
                self.assertNotIn("axe_allow", pages[name])

    def test_songs_metadata_chips_run_at_default_and_largest_text(self):
        # Issue #644 review: the chip-height journey gates the release-branch suite at default and 225% text, scanned,
        # with each text pill's height compared to the others (assertheight) and the row's spoken order.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-songs-metadata-chips.json"}
        self.assertEqual({"normal", "text-225"}, set(runs))
        self.assertTrue(all(run.scan and not run.only for run in runs.values()))
        self.assertFalse([run for run in ci.RUNS if run.name.startswith("a11y-songs-metadata-chips")])
        pages = json.loads((ci.JOURNEYS / "a11y-songs-metadata-chips.json").read_text(encoding="utf-8"))
        for mode, run in runs.items():
            chosen = m.mode_pages(pages, mode)
            self.assertEqual(1, len(chosen), mode)
            page = chosen[0]
            self.assertTrue(m.page_sizes(page, run.sizes.split(","), mode), mode)
            steps = page["ready"]
            self.assertTrue(page["scan"])
            for song in ("fixture-song-1", "fixture-song-2"):
                self.assertIn(f"assertheight:raw=fst.songs.metadata.difficulty.{song}|raw=fst.songs.metadata.season.{song}",
                              steps)
                self.assertIn(f"assertheight:raw=fst.songs.metadata.percentage.{song}|raw=fst.songs.metadata.percentile.{song}",
                              steps)
                self.assertTrue(any(s.startswith(f"assertread:id=fst.songs.row.{song}|") for s in steps))
            self.assertIn("assertsize:raw=fst.songs.metadata.stars.fixture-song-1|126x24", steps)
            self.assertIn("assertsize:raw=fst.songs.metadata.intensity.fixture-song-1|74x24", steps)

    def test_suggestions_row_centre_runs_at_every_size_and_largest_text(self):
        # Issue #654: a one-line Suggestions row's art and metadata pill sit on the row's vertical centre within 1 epx
        # (assertmiddle), at compact, medium and wide and at 225% text, with the row still one 40+ epx button.
        pages = {page["name"]: page for page in json.loads((ci.JOURNEYS / "a11y-suggestions.json").read_text(encoding="utf-8"))}
        row = "fst.suggestions.row."
        for name, (song, pill) in {"suggestions-row-centre": ("s032|Solo_PeripheralGuitar", "season"),
                                   "suggestions-row-centre-rival": ("s046|Solo_Guitar", "rival")}.items():
            with self.subTest(page=name):
                steps = pages[name]["after_ready"]
                raw = f"raw={row}{song.replace('|', '.')}"
                self.assertIn(f"assertmiddle:{raw}.art|id={row}{song}|1", steps)
                self.assertIn(f"assertmiddle:{raw}.{pill}|id={row}{song}|1", steps)
                self.assertTrue(any(step.startswith("assertsize:") and step.endswith("|0x40") for step in steps))
                covered = {(mode, size) for run in ci.RUNS if run.pages == "a11y-suggestions.json"
                           and (not run.only or name in run.only.split(","))
                           for mode in [run.mode] for size in m.page_sizes(pages[name], run.sizes.split(","), mode)}
                self.assertLessEqual({("normal", "medium"), ("normal", "wide"), ("text-225", "medium"),
                                      ("text-225", "wide")}, covered)
        # Partial runs come before the full ones, so generated_runs still sees the file as covered.
        names = [run.name for run in ci.RUNS]
        for run in (run for run in ci.RUNS if run.only == ci.SUGGESTIONS_ROW_CENTRE):
            self.assertLess(names.index(run.name), names.index("suggestions"))

    def test_reflow_runs_with_and_without_motion(self):
        # Issue #669: every reflow page runs wide with motion and with each motion-off mode (its reflow_trace then
        # requires instant reflows), and the file also runs at 225% text.
        pages = json.loads((ci.JOURNEYS / "a11y-reflow.json").read_text(encoding="utf-8"))
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-reflow.json"}
        self.assertEqual({"normal", "app-reduced", "no-animations", "text-225"}, set(runs))
        for page in (page for page in pages if page.get("reflow_trace")):
            with self.subTest(page=page["name"]):
                for mode in ("normal", "app-reduced", "no-animations"):
                    self.assertIn(page, m.mode_pages([page], mode))
                    self.assertEqual(["wide"], m.page_sizes(page, runs[mode].sizes.split(","), mode))
        self.assertTrue(any(page in m.mode_pages([page], "text-225") for page in pages))
        self.assertFalse(m.mode_motion("normal") is False)
        self.assertIs(False, m.mode_motion("no-animations"))
        # Issue #669 review: Profile/Statistics card-grid reflows run with motion, app Reduce Motion and Animation
        # effects off (reflow_trace then requires moved=0 entered=0), and stay one column at 225% text.
        by_name = {page["name"]: page for page in pages}
        self.assertEqual({"card-grid": 2}, by_name["reflow-statistics-resize"]["reflow_trace"])
        self.assertEqual([by_name["reflow-statistics-large-text-resize"]],
                         m.mode_pages([by_name["reflow-statistics-large-text-resize"]], "text-225"))
        # R4: motion turned off mid-reflow (a split and a card reflow, each with both settings) runs once, normal mode.
        stops = [page for page in pages if page.get("reflow_stops")]
        self.assertEqual({"split", "cards"}, {key for page in stops for key in page["reflow_stops"]})
        for page in stops:
            with self.subTest(page=page["name"]):
                self.assertEqual([page], m.mode_pages([page], "normal"))
                for mode in ("app-reduced", "no-animations", "text-225"):
                    self.assertEqual([], m.mode_pages([page], mode))
                steps = page["after_ready"]
                self.assertIn("animations:off", steps)
                self.assertEqual("animations:on", [s for s in steps if s.startswith("animations:")][-1])
                self.assertIn("key:ctrl+alt+shift+m", steps)
                self.assertEqual("1", page["env"]["FST_DEBUG_MOTION_KEY"])
                self.assertGreater(int(page["env"]["FST_DEBUG_REFLOW_MS"]), 300)

    def test_wide_columns_run_wide_at_default_and_large_text(self):
        # Issue #653 review: the two-column pages run wide at default text, and the one-column pages also run wide at
        # 150% (the large-text threshold) and 225% text, where text size alone must keep one column.
        pages = {page["name"]: page
                 for page in json.loads((ci.JOURNEYS / "a11y-wide-columns.json").read_text(encoding="utf-8"))}

        def covered(name):
            return {(mode, size) for run in ci.RUNS if run.pages == "a11y-wide-columns.json"
                    and (not run.only or name in run.only.split(","))
                    and pages[name] in m.mode_pages([pages[name]], run.mode)
                    for mode in [run.mode] for size in m.page_sizes(pages[name], run.sizes.split(","), mode)}

        for name in ci.WIDE_COLUMNS_ONE.split(","):
            with self.subTest(page=name):
                self.assertLessEqual({("normal", "compact"), ("normal", "medium"), ("text-150", "wide"),
                                      ("text-225", "compact"), ("text-225", "wide")}, covered(name))
                self.assertNotIn(("normal", "wide"), covered(name))
                self.assertTrue(any(step.startswith("assertbelow:") for step in pages[name]["after_ready"]))
        for name in ("wide-columns-statistics-two", "wide-columns-suggestions-two", "wide-columns-suggestions-load-more",
                     "wide-columns-shop-grid-fill"):
            with self.subTest(page=name):
                self.assertIn(("normal", "wide"), covered(name))
        self.assertTrue(all(run.scan for run in ci.RUNS if run.pages == "a11y-wide-columns.json"))
        self.assertFalse([run for run in ci.RUNS if run.name.startswith("a11y-wide-columns")])
        # Issue #661: the seed 1 cards after Suggestions R1 (#656): cards 9 | 10 end the first batch, 11 | 12 open the next.
        load_more = pages["wide-columns-suggestions-load-more"]["after_ready"]
        self.assertIn("scrollinto:id=fst.suggestions.category.song_rival_dominate_rival-above-2@15", load_more)
        self.assertIn("assertlevel:name=Protect Your Lead vs Rival B2&class=TextBlock|name=Dominate Rival A2&class=TextBlock",
                      load_more)
        self.assertIn("assertorder:name=Top 50% Push, New on Pro Lead|name=Protect Your Lead vs Rival B2, Dominate Rival A2",
                      load_more)
        tab = load_more.index("key:tab")
        self.assertEqual("assertfocus:id=fst.suggestions.row.s006|Solo_Guitar@3", load_more[tab + 1])
        down = load_more.index("key:down")
        self.assertEqual(["assertfocus:id=fst.suggestions.row.s019|Solo_Guitar@3", "key:up",
                          "assertfocus:id=fst.suggestions.row.s055@3"], load_more[down + 1:down + 4])

    def test_songs_chip_rows_run_at_default_and_largest_text(self):
        # Issue #645 review: the narrow chip-row journey gates the release-branch suite at default and 225% text,
        # scanned, at compact: balanced 5 + 4 lines (Pro Lead level with Lead, Pro Bass below it), each line centred on
        # the row (assertmidline), lines apart, 21-epx icons and the row's spoken order; the normal run also re-flows the
        # chips to one centred line after a resize.
        chip = "raw=fst.songs.instrument-status.fixture-pulse."
        row = "id=fst.songs.row.fixture-pulse"
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-songs-chip-rows.json"}
        self.assertEqual({"normal", "text-225"}, set(runs))
        self.assertTrue(all(run.scan and not run.only and run.sizes == "compact" for run in runs.values()))
        self.assertFalse([run for run in ci.RUNS if run.name.startswith("a11y-songs-chip-rows")])
        pages = json.loads((ci.JOURNEYS / "a11y-songs-chip-rows.json").read_text(encoding="utf-8"))
        balanced = [f"assertlevel:{chip}Solo_Guitar|{chip}Solo_PeripheralGuitar",
                    f"assertbelow:{chip}Solo_PeripheralBass|{chip}Solo_PeripheralGuitar",
                    f"assertmidline:{chip}Solo_Guitar|{chip}Solo_PeripheralGuitar|{row}|4",
                    f"assertmidline:{chip}Solo_PeripheralBass|{chip}Solo_PeripheralDrums|{row}|4",
                    f"assertapart:{chip}Solo_PeripheralGuitar|{chip}Solo_PeripheralDrums"]
        for mode, run in runs.items():
            chosen = m.mode_pages(pages, mode)
            self.assertTrue(chosen, mode)
            for page in chosen:
                with self.subTest(mode=mode, page=page["name"]):
                    self.assertTrue(page["scan"])
                    self.assertTrue(m.page_sizes(page, run.sizes.split(","), mode))
                    steps = page["ready"]
                    self.assertIn("resize:360x800", steps)
                    for step in balanced:
                        self.assertIn(step, steps)
        narrow = {page["name"]: page for page in pages}["songs-chip-rows-narrow"]
        self.assertLessEqual({"normal", "text-225"}, set(narrow["modes"]))
        self.assertIn(f"assertsize:{chip}Solo_Guitar|21x21", narrow["ready"])
        self.assertTrue(any(step.startswith(f"assertname:{row}|") for step in narrow["ready"]))
        resize = {page["name"]: page for page in m.mode_pages(pages, "normal")}["songs-chip-rows-resize"]
        after = resize["ready"][resize["ready"].index("resize:compact"):]
        self.assertIn(f"assertmidline:{chip}Solo_Guitar|{chip}Solo_PeripheralDrums|{row}|4", after)

    def test_songs_scroll_runs_at_default_largest_text_and_animations_off(self):
        # Issue #520 (#247): the pinned Songs title after far UIA jumps, a fling back to the top and keyboard End/Home.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-songs-scroll.json"}
        self.assertEqual({"normal", "text-225", "no-animations"}, set(runs))
        self.assertTrue(all(run.scan and not run.only for run in runs.values()))
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        pages = {page["name"]: page for page in
                 json.loads((ci.JOURNEYS / "a11y-songs-scroll.json").read_text(encoding="utf-8"))}
        self.assertEqual({"songs-scroll-far-jumps", "songs-scroll-fling-back", "songs-scroll-keyboard"}, set(pages))
        for page in pages.values():
            with self.subTest(page=page["name"]):
                self.assertEqual(["--large-catalogue"], page["fixture"])
                self.assertFalse(page.get("live_only"))
                steps = page["after_ready"]
                self.assertTrue(any(s.startswith("assertstate:id=fst.songs.section-header|name=~") for s in steps)
                                or "assertname:id=fst.songs.section-header|#" in steps)
                self.assertIn("assertstate:id=fst.songs.section-header|heading=2", steps)
        far = pages["songs-scroll-far-jumps"]["after_ready"]
        self.assertGreaterEqual(sum(s.startswith("scrollto:id=fst.songs.list,") for s in far), 4)
        # #618: a scan after a scroll percent left a row title on the list's bottom edge (zero-height Axe finding) in
        # some runs; the page pins a known L row 8 epx below the top so its scan sees one fixed position.
        last_scroll = [s for s in far if s.startswith(("scrollto:", "scrollinto:", "scrollinset:"))][-1]
        self.assertEqual("scrollinset:id=fst.songs.row.fixture-song-49|id=fst.songs.list|8", last_scroll)
        self.assertIn("assertstate:id=fst.songs.section-header|name=L@5", far)
        self.assertIn("key:end", pages["songs-scroll-keyboard"]["after_ready"])

    def test_song_band_pinned_runs_at_default_and_largest_text(self):
        # Issue #461 (#306): the full band board's pinned "your band" row runs in CI at default and 225% text.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-song-band-pinned.json"}
        self.assertEqual({"normal", "text-225"}, set(runs))
        self.assertTrue(all(run.scan for run in runs.values()))
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        pages = json.loads((ci.JOURNEYS / "a11y-song-band-pinned.json").read_text(encoding="utf-8"))
        names = {page["name"] for page in pages}
        self.assertTrue({"song-band-pin-jump", "song-band-pin-open", "song-band-pin-no-player"} <= names)

    def test_score_history_chart_runs_at_default_largest_text_and_contrast(self):
        # Issue #512 (#198): the Score History chart's arrows, axis text, contrast bars and Retry states run in CI.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-score-history-chart.json"}
        self.assertEqual({"normal", "text-225", "hc-desert"}, set(runs))
        self.assertTrue(all(run.scan for run in runs.values()))
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        self.assertEqual("history-chart-contrast", runs["hc-desert"].only)
        pages = {page["name"]: page for page in
                 json.loads((ci.JOURNEYS / "a11y-score-history-chart.json").read_text(encoding="utf-8"))}
        self.assertTrue({"history-chart-arrows", "history-chart-axis-text", "history-chart-contrast",
                         "history-chart-contrast-switch", "history-states-syncing", "history-states-failed"}
                        <= set(pages))
        self.assertIn("assertsize:id=fst.history.retry|40x40", pages["history-states-syncing"]["after_ready"])

    def test_loading_placement_runs_both_leaderboards_pages_at_default_and_largest_text(self):
        # Issue #649 review (load-transition R1): Quick Links is absent during the first Leaderboards spinner and stays
        # available during an F5 reload; both pages gate the release-branch suite at default and 225% text, scanned.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-loading-placement.json"}
        self.assertEqual({"normal", "text-225"}, set(runs))
        self.assertTrue(all(run.scan and not run.only for run in runs.values()))
        for run in runs.values():
            with self.subTest(mode=run.mode):
                sizes = run.sizes.split(",")
                ran = {page["name"]: m.page_sizes(page, sizes, run.mode) for page in ci.run_pages(run)}
                self.assertTrue(ran["leaderboards-loading-centred"], "first-load page skipped")
                self.assertTrue(ran["leaderboards-reload-centred"], "reload page skipped")
        pages = {page["name"]: page for page in
                 json.loads((ci.JOURNEYS / "a11y-loading-placement.json").read_text(encoding="utf-8"))}
        first = pages["leaderboards-loading-centred"]["ready"]
        self.assertLess(first.index("waitgone:id=fst.quick-links.open@1"), first.index("waitfor:id=fst.leaderboards.card.0f@25"))
        self.assertIn("waitgone:id=fst.quick-links.pane@1", first)
        reload = pages["leaderboards-reload-centred"]["after_ready"]
        self.assertLess(reload.index("waitfor:id=fst.leaderboards.loading@5"), reload.index("waitfor:id=fst.quick-links.open@1"))

    def test_song_band_board_runs_at_default_and_largest_text(self):
        # Issue #510 (#196): the full band board's single-stop rows, empty and error states run in CI at default and
        # 225% text, and its accuracy pill's contrast-theme colours at default size.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-song-band-leaderboard.json"}
        self.assertEqual({"normal", "text-225"}, set(runs))
        self.assertTrue(all(run.scan and run.only == "" for run in runs.values()))
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        self.assertIn("medium", runs["normal"].sizes.split(","))
        pages = {page["name"]: page for page in
                 json.loads((ci.JOURNEYS / "a11y-song-band-leaderboard.json").read_text(encoding="utf-8"))}
        self.assertEqual({"sbl-rows", "sbl-empty", "sbl-error", "sbl-accuracy-pill-contrast"}, set(pages))
        for page in pages.values():
            self.assertNotIn("axe_allow", page)
        row = "fst.song-band-leaderboard.row.fixture-band-1:1"
        steps = pages["sbl-rows"]["after_ready"]
        self.assertTrue(any(step.startswith(f"assertread:id={row}|Rank 1. Band 1 Member A, Lead, 94,500 points.")
                            for step in steps))
        self.assertIn(f"assertstate:id={row}|type=listitem", steps)
        self.assertIn(f"assertstate:id={row}|invoke=true", steps)
        self.assertIn(f"assertsize:id={row}|0x40", steps)
        self.assertIn("waitfor:raw=fst.star-rating.white-5@3", steps)
        self.assertIn("waitgone:id=fst.star-rating.white-5@1", steps)
        self.assertIn(f"waitgone:id={row}.accuracy@1", steps)
        self.assertIn("assertstate:id=fst.song-band-leaderboard.empty|heading=2", pages["sbl-empty"]["after_ready"])
        self.assertIn("assertsize:id=fst.service-status.retry|40x40", pages["sbl-error"]["after_ready"])
        pill = pages["sbl-accuracy-pill-contrast"]
        self.assertIn("contrast:desert", pill["after_ready"])
        self.assertIn("contrast:off", pill["after_ready"])

    def test_full_rankings_pinned_runs_at_default_largest_text_and_reduced_motion(self):
        # Issue #466 (#318): Full Rankings' pinned "your rank" row (also on the player's own page) runs in CI at default
        # and 225% text, and its keyboard jump with in-app Reduce Motion.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-full-rankings.json"}
        self.assertEqual({"normal", "text-225", "app-reduced"}, set(runs))
        self.assertTrue(all(run.scan for run in runs.values()))
        self.assertEqual("", runs["normal"].only)
        self.assertEqual("", runs["text-225"].only)
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        self.assertEqual("fr-pinned-jump-keyboard", runs["app-reduced"].only)
        pages = {page["name"]: page for page in
                 json.loads((ci.JOURNEYS / "a11y-full-rankings.json").read_text(encoding="utf-8"))}
        self.assertEqual({"fr-pinned-own-page", "fr-pinned-own-page-keyboard", "fr-pinned-jump-keyboard"}, set(pages))
        own = pages["fr-pinned-own-page"]
        self.assertTrue(own["profile"].startswith("fixture-player-2:"))
        steps = own["after_ready"]
        self.assertIn("assertsize:id=fst.full-rankings.spotlight-footer|40x40", steps)
        self.assertTrue(any(step.startswith("assertread:id=fst.full-rankings.spotlight-footer|~^Your rank, 2nd")
                            for step in steps))
        self.assertTrue(any(step.startswith("assertorder:id=fst.full-rankings.title|id=fst.rankings.row.fixture-player-2|"
                                            "id=fst.full-rankings.spotlight-footer|id=fst.full-rankings.page-first")
                            for step in steps))

    def test_full_rankings_swap_runs_in_every_motion_and_text_mode(self):
        # Issue #524 (#270): Full Rankings' pinned row load gate runs in CI at default and 225% text, with in-app Reduce
        # Motion and with Windows' Animation effects off.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-full-rankings-swap.json"}
        self.assertEqual({"normal", "text-225", "app-reduced", "no-animations"}, set(runs))
        self.assertTrue(all(run.scan and not run.only for run in runs.values()))
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        pages = {page["name"]: page for page in
                 json.loads((ci.JOURNEYS / "a11y-full-rankings-swap.json").read_text(encoding="utf-8"))}
        self.assertEqual({"fr-swap-rank-by", "fr-swap-page-keeps-pin", "fr-swap-motion-reduced", "fr-swap-motion-system"},
                         set(pages))
        self.assertEqual(["app-reduced"], pages["fr-swap-motion-reduced"]["modes"])
        self.assertEqual(["no-animations"], pages["fr-swap-motion-system"]["modes"])
        footer = "id=fst.full-rankings.spotlight-footer"
        swap = pages["fr-swap-rank-by"]["after_ready"]
        self.assertIn(f"waitgone:{footer}@2", swap)
        self.assertIn("assertorder:id=fst.full-rankings.title|id=fst.rankings.rank-by-menu|name=Busy Loading rankings",
                      swap)
        self.assertIn("assertfocus:id=PART_BackButton@3", swap)
        self.assertIn(f"assertsize:{footer}|40x40", swap)
        self.assertTrue(any(step.startswith(f"assertread:{footer}|~^Your rank, 40th\\. Jump to your position\\. "
                                            "Fixture Rank 40\\. FC Rate") for step in swap))
        page = pages["fr-swap-page-keeps-pin"]["after_ready"]
        self.assertIn(f"assertstate:{footer}|focusable=true", page)
        self.assertTrue(any(step.startswith(f"assertorder:id=fst.rankings.rank-by-menu|name=Busy Loading rankings|{footer}")
                            for step in page))
        for name in ("fr-swap-motion-reduced", "fr-swap-motion-system"):
            self.assertIn(f"assertmotion:{footer}|still", pages[name]["after_ready"])

    def test_leaderboards_card_jump_runs_at_default_largest_text_and_reduced_motion(self):
        # Issue #493 (#370): a Leaderboards card's "your rank" row runs in CI at default and 225% text, and its keyboard
        # jump to Full Rankings with in-app Reduce Motion.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-leaderboards-card-jump.json"}
        self.assertEqual({"normal", "text-225", "app-reduced"}, set(runs))
        self.assertTrue(all(run.scan for run in runs.values()))
        self.assertEqual("", runs["normal"].only)
        self.assertEqual("", runs["text-225"].only)
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        self.assertEqual("card-jump-row-keyboard", runs["app-reduced"].only)
        pages = {page["name"]: page for page in
                 json.loads((ci.JOURNEYS / "a11y-leaderboards-card-jump.json").read_text(encoding="utf-8"))}
        self.assertEqual({"card-jump-row", "card-jump-row-keyboard", "card-in-place-row"}, set(pages))
        spotlight = "id=fst.leaderboards.card.Solo_Guitar.spotlight"
        jump = pages["card-jump-row"]["after_ready"]
        self.assertIn(f"assertsize:{spotlight}|40x40", jump)
        self.assertTrue(any(step.startswith(f"assertread:{spotlight}|~^Your rank, 40th\\. Jump to your position")
                            for step in jump))
        keyboard = pages["card-jump-row-keyboard"]["after_ready"]
        self.assertIn("key:enter", keyboard)
        self.assertIn("waitfor:id=fst.rankings.row.fixture-rank-40@15", keyboard)
        self.assertEqual(f"assertfocus:{spotlight}@3", keyboard[-2])

    def test_suggestions_runs_at_default_and_largest_text(self):
        # Issue #513 (#205): the Suggestions cards, keyboard, filter, states and rival pill contrast run in CI at default
        # and 225% text, with an Axe scan, and pin the regressions #205 and #513 fixed.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-suggestions.json" and not run.only}
        self.assertEqual({"normal", "text-225"}, set(runs))
        self.assertTrue(all(run.scan for run in runs.values()))
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        pages = {page["name"]: page for page in
                 json.loads((ci.JOURNEYS / "a11y-suggestions.json").read_text(encoding="utf-8"))}
        self.assertEqual({"suggestions-cards", "suggestions-keyboard", "suggestions-filter", "suggestions-syncing",
                          "suggestions-no-results", "suggestions-rival-pill-contrast", "suggestions-named-rival",
                          "suggestions-load-more", "suggestions-load-more-keyboard", "suggestions-row-centre",
                          "suggestions-row-centre-rival"}, set(pages))
        cards = pages["suggestions-cards"]["after_ready"]
        self.assertIn("assertstate:name=Pro Lead Untouched for 2 Seasons&class=TextBlock|heading=2", cards)
        keyboard = pages["suggestions-keyboard"]["after_ready"]
        down = keyboard.index("focus:id=fst.suggestions.row.s001|Solo_PeripheralGuitar")
        self.assertEqual(["key:down", "assertfocus:id=fst.suggestions.row.s091@3"], keyboard[down + 1:down + 3])
        filter_steps = pages["suggestions-filter"]["after_ready"]
        self.assertTrue(any(step.startswith("assertread:id=fst.suggestions.filter.instruments|Instruments, button, ")
                            for step in filter_steps))
        expand = filter_steps.index("key:enter", filter_steps.index("assertsize:id=fst.suggestions.filter.reset|0x40"))
        self.assertEqual(["key:tab", "assertfocus:id=fst.suggestions.filter.instrument.Solo_Guitar@3"],
                         [step for step in filter_steps[expand + 1:] if step.startswith(("key:", "assertfocus:"))][:2])
        for name in ("suggestions-syncing", "suggestions-no-results"):
            self.assertTrue(any(step.endswith("|heading=2") for step in pages[name]["after_ready"]), name)
        # Issue #656 (Suggestions R1): a card that names a rival lists only that rival.
        named = pages["suggestions-named-rival"]["after_ready"]
        self.assertIn("assertstate:name=Gain Stars & Beat Rival B3&class=TextBlock|heading=2", named)
        self.assertTrue(all(step.split("|")[0].endswith("Rival B3") for step in named
                            if step.startswith(("assertread:name=Track", "assertsize:name=Track"))))
        contrast = pages["suggestions-rival-pill-contrast"]
        self.assertEqual(["medium"], contrast["sizes"])
        self.assertIn("contrast:desert", contrast["after_ready"])
        self.assertEqual("contrast:off", [s for s in contrast["after_ready"] if s.startswith("contrast:")][-1])

    def test_suggestions_load_more_runs_with_motion_on_and_off(self):
        # Issue #521 (#260): the cards loaded after the first batch fade in; their names, headings, order, targets and
        # keyboard path run with motion on (default and 225% text, the full runs) and with in-app Reduce Motion and
        # Animation effects off, before the full runs so generated_runs still sees the file as covered.
        names = [run.name for run in ci.RUNS]
        partial = {run.mode: run for run in ci.RUNS if run.pages == "a11y-suggestions.json" and run.only
                   and run.only == ci.SUGGESTIONS_LOAD_MORE}
        self.assertEqual({"app-reduced", "no-animations"}, set(partial))
        for run in partial.values():
            self.assertEqual(ci.SUGGESTIONS_LOAD_MORE, run.only)
            self.assertTrue(run.scan)
            self.assertLess(names.index(run.name), names.index("suggestions"))
        self.assertFalse([run for run in ci.RUNS if run.name.startswith("a11y-suggestions-")])
        pages = {page["name"]: page for page in
                 json.loads((ci.JOURNEYS / "a11y-suggestions.json").read_text(encoding="utf-8"))}
        self.assertEqual(set(ci.SUGGESTIONS_LOAD_MORE.split(",")), {"suggestions-load-more", "suggestions-load-more-keyboard"})
        labels = pages["suggestions-load-more"]["after_ready"]
        row = "name=Track 19, X · 2004, Lead, 60 ranks ahead of Rival A2"
        # This card only exists once the second batch (cards 11-16) has loaded.
        self.assertIn("scrollinto:id=fst.suggestions.category.song_rival_dominate_rival-above-2@15", labels)
        self.assertIn("assertstate:name=Dominate Rival A2&class=TextBlock|heading=2", labels)
        self.assertIn(f"assertread:{row}|{row[5:]}, button", labels)
        self.assertIn(f"assertsize:{row}|40x40", labels)
        self.assertIn("assertorder:name=New on Pro Lead|name=Protect Your Lead vs Rival B2", labels)
        keyboard = pages["suggestions-load-more-keyboard"]
        self.assertEqual(0, keyboard["tabs"])
        steps = keyboard["after_ready"]
        down = steps.index("key:down")
        self.assertEqual(["assertfocus:id=fst.suggestions.row.s006|Solo_Guitar@3", "key:up",
                          "assertfocus:id=fst.suggestions.row.s055@3"], steps[down + 1:down + 4])
        # Tab ends on card 17's row, in the third batch, which only exists once Tab has walked to the end of the second.
        self.assertIn("assertfocus:id=fst.suggestions.row.s022|Solo_Bass@5", steps)
        self.assertEqual("key:shift+tab", steps[-3])
        # The Axe scan follows: pin a card 8 epx below the list top so no card ends on the viewport edge (item 3).
        self.assertTrue(steps[-1].startswith("scrollinset:") and steps[-1].endswith("|id=fst.suggestions.list|8"))

    def test_shop_offers_run_at_default_largest_text_and_reduced_motion(self):
        # Issue #516 (#224): the Item Shop tiles, List/Grid toggle, rings and states run in CI at default and 225% text
        # and with in-app Reduce Motion, with an Axe scan, and pin the regressions #516 fixed.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-shop-offers.json"}
        self.assertEqual({"normal", "text-225", "app-reduced"}, set(runs))
        self.assertTrue(all(run.scan for run in runs.values()))
        self.assertFalse(runs["normal"].only or runs["text-225"].only)
        self.assertEqual({"compact", "medium"}, set(runs["text-225"].sizes.split(",")))
        self.assertEqual("shop-offers-view-toggle", runs["app-reduced"].only)
        pages = {page["name"]: page for page in
                 json.loads((ci.JOURNEYS / "a11y-shop-offers.json").read_text(encoding="utf-8"))}
        read = pages["shop-offers-grid-read"]["after_ready"]
        # The toggle sat a line below Filter (layout rounding wrapped it) under the tiles.
        self.assertIn("assertinset:id=fst.shop.view-toggle|id=fst.shop.filter|0", read)
        self.assertIn("assertat:id=fst.shop.view-toggle|0,-18.5", read)
        self.assertIn("assertread:id=fst.shop.song.fixture-orbit|"
                      "Fixture Orbit, Synthetic Quartet · 2026, Leaving Tomorrow, button", read)
        self.assertEqual(["text-225"], pages["shop-offers-text-wrap"]["modes"])
        self.assertIn("assertapart:id=fst.shop.view-toggle|id=fst.shop.song.fixture-orbit",
                      pages["shop-offers-text-wrap"]["after_ready"])
        self.assertIn("waitgone:id=fst.shop.view-toggle", pages["shop-offers-grid-compact"]["after_ready"])
        self.assertIn("assertread:id=fst.shop.loading|Busy Loading Item Shop, ProgressRing",
                      pages["shop-offers-loading"]["after_ready"])
        toggle = pages["shop-offers-view-toggle"]["after_ready"]
        self.assertEqual(2, toggle.count("assertfocus:id=fst.shop.view-toggle@3"))
        # The Leaving pill kept the brand red under a live contrast switch.
        contrast = pages["shop-offers-contrast-live"]
        self.assertEqual((["medium"], ["normal"]), (contrast["sizes"], contrast["modes"]))
        self.assertIn("contrast:desert", contrast["after_ready"])
        self.assertEqual("contrast:off", [s for s in contrast["after_ready"] if s.startswith("contrast:")][-1])
        self.assertTrue(any(s.startswith("assertpaint:id=fst.shop.badge.leaving.fixture-orbit|L-4,M0=#903909")
                            for s in contrast["after_ready"]))

    def test_search_all_section_titles_run_at_default_largest_text_and_reduced_motion(self):
        # Issue #483 (#348): Search's All section titles run in CI at default and 225% text and with in-app Reduce
        # Motion, while the file's other pages keep their generated runs.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-search.json" and run.only == ci.SEARCH_SECTIONS
                and run.mode != "app-reduced"}
        self.assertEqual({"normal", "text-225"}, set(runs))
        reduced = [run for run in ci.RUNS if run.pages == "a11y-search.json" and run.mode == "app-reduced"
                   and run.only == ci.SEARCH_SECTIONS]
        self.assertEqual(["search-all-sections,search-all-sections-keyboard"], [run.only for run in reduced])
        self.assertTrue(all(run.scan for run in (*runs.values(), *reduced)))
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        generated = {run.mode: set(run.only.split(",")) for run in ci.RUNS if run.name.startswith("a11y-search-")}
        self.assertEqual({"normal", "text-225"}, set(generated))
        for pages in generated.values():
            self.assertIn("search-results-all", pages)
            self.assertFalse(pages & set(ci.SEARCH_SECTIONS.split(",")))
        pages = {page["name"]: page for page in
                 json.loads((ci.JOURNEYS / "a11y-search.json").read_text(encoding="utf-8"))}
        steps = pages["search-all-sections"]["after_ready"]
        for section, title in (("songs", "Songs"), ("players", "Players"), ("bands", "Bands")):
            self.assertIn(f"assertread:id=fst.global-search.section.{section}|{title}, text", steps)
            self.assertIn(f"assertstate:id=fst.global-search.section.{section}|heading=2", steps)
            self.assertIn(f"assertstate:id=fst.global-search.section.{section}|focusable=false", steps)
        self.assertIn("assertorder:id=fst.global-search.scope.all|id=fst.global-search.section.songs"
                      "|id=fst.global-search.result.song", steps)
        keyboard = pages["search-all-sections-keyboard"]
        self.assertEqual(0, keyboard["tabs"])
        focus = [step for step in keyboard["after_ready"] if step.startswith("assertfocus:")]
        self.assertEqual(["scope.all", "result.song", "result.player", "result.band", "result.player", "result.song",
                          "scope.all"], [step.split("fst.global-search.")[1].split("@")[0] for step in focus])
        for scope in ("songs", "players", "bands"):
            single = pages[f"search-results-{scope}"]["after_ready"]
            self.assertTrue(any(step.startswith(f"waitgone:id=fst.global-search.section.{scope}") for step in single))

    def test_search_delayed_results_run_at_default_largest_text_and_reduced_motion(self):
        # Issue #521 (#260): song rows that waited behind the spinner for a slow player search appear (fading in with
        # motion on) when it clears; their heading, name, order, target and Tab path run at default and 225% text and
        # with in-app Reduce Motion, and the page is not also a generated run.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-search.json"
                and run.only == ci.SEARCH_DELAYED_RESULTS}
        self.assertEqual({"normal", "text-225", "app-reduced"}, set(runs))
        self.assertTrue(all(run.scan for run in runs.values()))
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        for run in ci.RUNS:
            if run.name.startswith("a11y-search-"):
                self.assertNotIn(ci.SEARCH_DELAYED_RESULTS, run.only.split(","))
        page = {page["name"]: page for page in
                json.loads((ci.JOURNEYS / "a11y-search.json").read_text(encoding="utf-8"))}[ci.SEARCH_DELAYED_RESULTS]
        self.assertEqual(0, page["tabs"])
        steps = page["after_ready"]
        query = next(step.split("|", 1)[1] for step in steps if step.startswith("setvalue:id=fst.global-search.field|"))
        self.assertTrue(query.casefold().startswith(profile_fixture.SLOW_SONG_PREFIX))
        spinning = steps.index("waitfor:id=fst.global-search.loading@5")
        cleared = steps.index("waitgone:id=fst.global-search.loading@15")
        self.assertIn("waitgone:id=fst.global-search.result.song", steps[spinning:cleared])
        self.assertIn("assertfocus:name=Search songs, players and bands@3", steps[spinning:cleared])
        after = steps[cleared:]
        self.assertIn("assertstate:id=fst.global-search.section.songs|heading=2", after)
        self.assertIn("assertsize:id=fst.global-search.result.song|40x40", after)
        self.assertIn("assertorder:id=fst.global-search.scope.all|id=fst.global-search.section.songs"
                      "|id=fst.global-search.result.song", after)
        focus = [step for step in after if step.startswith("assertfocus:")]
        self.assertEqual(["assertfocus:name=Search songs, players and bands@3",
                          "assertfocus:id=fst.global-search.scope.all@3",
                          "assertfocus:id=fst.global-search.result.song@3",
                          "assertfocus:id=fst.global-search.scope.all@3"], focus)

    def test_first_run_demos_run_at_default_and_largest_text(self):
        """#420 review: the first-run demo journey gates PRs, not just its JSON guard."""
        demos = {run.mode: run for run in ci.RUNS if run.pages == "a11y-first-run-demos.json"}
        self.assertEqual({"normal", "text-225"}, set(demos))
        self.assertTrue(all(run.scan and not run.only for run in demos.values()))
        self.assertIn("compact", demos["text-225"].sizes.split(","))
        self.assertEqual({"compact", "medium"}, set(demos["normal"].sizes.split(",")))

    def test_real_control_first_run_demos_run_with_text_and_motion_off(self):
        """#498: the #380 real-control demos gate PRs at default and 225% text, and hold still with animations off."""
        demos = {run.mode: run for run in ci.RUNS if run.pages == "a11y-first-run-real-demos.json"}
        self.assertEqual({"normal", "text-225", "no-animations", "no-transparency"}, set(demos))
        self.assertTrue(all(run.scan for run in demos.values()))
        self.assertFalse(demos["normal"].only or demos["text-225"].only)
        self.assertEqual("frrd-infinite-scroll-static", demos["no-animations"].only)

    def test_real_control_auto_scroll_hard_edge_runs_in_every_r7_setting(self):
        """#498 review: the auto-scroll demo's hard edge (fade=off) is asserted with transparency effects off, Less
        Transparency and More Contrast, and the faded pages skip those modes."""
        demos = {run.mode: run for run in ci.RUNS if run.pages == "a11y-first-run-real-demos.json"}
        self.assertEqual("frrd-infinite-scroll-no-transparency", demos["no-transparency"].only)
        pages = {page["name"]: page for page in ci.run_pages(demos["normal"])}
        self.assertEqual({"lessTransparency": True}, pages["frrd-infinite-scroll-less-transparency"]["settings"])
        self.assertEqual({"moreContrast": True}, pages["frrd-infinite-scroll-more-contrast"]["settings"])
        self.assertNotIn("frrd-infinite-scroll-no-transparency", pages)
        hard = [*ci.run_pages(demos["no-transparency"]), pages["frrd-infinite-scroll-less-transparency"],
                pages["frrd-infinite-scroll-more-contrast"]]
        self.assertEqual(3, len(hard))
        for page in hard:
            status = [step for step in page["after_ready"] if step.startswith("assertstatus:")]
            self.assertTrue(status and all(step.endswith("fade=off$@15") for step in status), page["name"])
            self.assertIn("waitgone:id=fst.first-run.demo.suggestions-infinite-scroll@1", page["after_ready"])
        faded = [page["name"] for mode in ("no-transparency", "app-contrast", "hc-desert")
                 for page in ci.run_pages(ci.Run("x", "a11y-first-run-real-demos.json", mode=mode))
                 if "suggestions-infinite-scroll" in json.dumps(page) and "fade=off" not in json.dumps(page)]
        self.assertEqual([], faded)

    def test_a_full_run_covers_its_file_despite_a_partial_run(self):
        """#498: a reduced-motion ``only`` run must not make the generator re-run the file's pages a second time."""
        generated = {run.name for run in ci.RUNS}
        for stem in ("a11y-grouped-boards", "a11y-first-run-real-demos"):
            self.assertNotIn(f"{stem}-normal", generated)
            self.assertNotIn(f"{stem}-text-225", generated)

    def test_modals_run_at_default_and_largest_text(self):
        modal = {(run.mode, run.scan) for run in ci.RUNS if run.pages == "a11y-modals.json"}
        self.assertEqual({("normal", True), ("text-225", True)}, modal)
        large = next(run for run in ci.RUNS if run.pages == "a11y-modals.json" and run.mode == "text-225")
        self.assertIn("compact", large.sizes.split(","))
        self.assertGreaterEqual(large.tabs, 1)

    def test_modal_legibility_runs_under_contrast_themes_and_largest_text(self):
        # Issue #518 (#239): dialog command labels and the First Run pips paint without the Window-coloured text
        # backplate under Desert and Night sky, and the Feedback field hints wrap at 225% text.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-modal-legibility.json"}
        self.assertEqual({"hc-desert", "hc-night-sky", "text-225"}, set(runs))
        self.assertTrue(all(run.scan and not run.only for run in runs.values()))
        pages = json.loads((ci.JOURNEYS / "a11y-modal-legibility.json").read_text(encoding="utf-8"))
        ran = {mode: {page["name"] for page in m.mode_pages(pages, mode)} for mode in runs}
        self.assertEqual({"modal-contrast-first-run-desert", "modal-contrast-settings-reset"}, ran["hc-desert"])
        self.assertEqual({"modal-contrast-first-run-night-sky", "modal-contrast-settings-reset"}, ran["hc-night-sky"])
        self.assertEqual({"modal-feedback-hints-wrap"}, ran["text-225"])
        by_name = {page["name"]: page for page in pages}
        pips = {"modal-contrast-first-run-desert": "#903909", "modal-contrast-first-run-night-sky": "#D6B4FD"}
        for name, highlight in pips.items():
            steps = by_name[name]["after_ready"]
            self.assertTrue(by_name[name]["ready"][0].startswith("wait:"), "the contrast theme reaches the app late")
            # A Window-coloured backplate would cover the label area, leaving no pixel of the button fill.
            self.assertIn("assertpaint:id=PrimaryButton|fill:L6,M0|C-12,M-5,C12,M5=@fill~16", steps)
            pip = next(step for step in steps if step.startswith("assertpaint:id=fst.first-run.pips|"))
            self.assertIn(f"L6,M-8={highlight}", pip)
            self.assertLess(steps.index("scrollto:id=fst.first-run.body,100"), steps.index(pip))
        reset = by_name["modal-contrast-settings-reset"]["after_ready"]
        self.assertIn("assertpaint:id=CloseButton|fill:L6,M0|C-12,M-5,C12,M5=@fill~16", reset)
        hints = by_name["modal-feedback-hints-wrap"]["after_ready"]
        for hint in ("A short summary of the problem, after [Bug].",
                     "What went wrong? Include the page, song, instrument or player involved.",
                     "What did you expect to happen instead?"):
            self.assertIn(f"assertmarquee:name={hint}&class=TextBlock|wrapped|60", hints)
        self.assertEqual("assertfocus:id=fst.settings.feedback.bug@3",
                         by_name["modal-feedback-hints-wrap"]["teardown"][-1])

    def test_modal_motion_runs_at_default_largest_text_and_motion_off(self):
        """#436: the #83 work-behind-dialogs journey gates PRs (normal, compact) and runs at 225% text and motion off.

        Its runs are generated (one bounded run per mode, so no single shard carries the whole journey); the workflow's
        ``ci_effects.ps1`` turns the hosted runner's Animation effects on before the motion pages launch the app.
        """
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-modal-motion.json"}
        self.assertLessEqual({"normal", "text-225", "no-animations"}, set(runs))
        self.assertTrue(all(run.scan for run in runs.values()))
        names = {mode: set(run.only.split(",")) for mode, run in runs.items()}
        for mode in ("normal", "text-225"):
            self.assertNotIn("mm-first-run-backdrop-static", names[mode])
            self.assertLessEqual({"mm-first-run-backdrop", "mm-whats-new-backdrop", "mm-first-run-shop-pulses",
                                  "mm-first-run-shop-pulses-reduced"}, names[mode])
        self.assertIn("mm-first-run-shop-pulses-static", names["no-animations"])
        self.assertIn("mm-first-run-backdrop-static", {name for run in runs.values() for name in run.only.split(",")})
        pr = [run for run in ci.tier_runs(list(ci.RUNS), "pr") if run.pages == "a11y-modal-motion.json"]
        self.assertEqual([("normal", "compact")], [(run.mode, run.sizes) for run in pr])
        self.assertIn("mm-first-run-shop-pulses", pr[0].only.split(","))
        workflow = _WORKFLOW.read_text(encoding="utf-8")
        self.assertLess(workflow.index("ci_effects.ps1"), workflow.index("python tools/windows/ui_ci.py --tier"))
        pages = json.loads((ci.JOURNEYS / "a11y-modal-motion.json").read_text(encoding="utf-8"))
        shop = next(page for page in pages if page["name"] == "mm-first-run-shop-pulses")
        steps = shop["after_ready"]
        for check in ("assertname:id=fst.first-run.slides|Item Shop", "assertread:id=SecondaryButton|Back, button",
                      "assertorder:id=fst.first-run.slides|id=PrimaryButton|id=SecondaryButton|id=fst.first-run.close",
                      "assertsize:id=fst.first-run.close|40x40", "key:enter"):
            self.assertIn(check, steps)

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
        id=fst.settings.whats-new`` at 225% text). A CI page that scrolls (``scrollinto:``) or reveals (``reveal:``)
        Settings content brings those rows in first
        (scrolling back to page chrome such as the Quick Links entry is not a Settings target). #539's
        ``settings-service-info-unavailable`` revealed the Service Info state row and lost it the same way. A page
        that opens Settings from another tab (Ctrl+comma) is exposed just the same. A page whose fixture reports
        ``feedback: false`` (``feedback_fixture.py --features off``) never gets the rows, so it has no wait."""
        wait = "scrollinto:id=fst.settings.feedback.feature"
        checked = 0
        for run in ci.RUNS:
            for page in json.loads((ci.JOURNEYS / run.pages).read_text(encoding="utf-8")):
                steps = [*page.get("setup", ()), *page.get("ready", ()), *page.get("after_ready", ())]
                if page.get("tab") != "settings" and page.get("route") != "/settings" and "key:ctrl+comma" not in steps:
                    continue
                scrolls = [step for step in steps
                           if step.startswith(("scrollinto:id=fst.settings.", "reveal:id=fst.settings."))]
                if not scrolls:
                    continue
                fixture = list(page.get("fixture", ()))
                if "--features" in fixture and fixture[fixture.index("--features") + 1:][:1] == ["off"]:
                    continue  # the Feedback rows never appear, so nothing can push a target off screen
                checked += 1
                # Scrolling to a Feedback row first is itself the wait.
                first = "scrollinto:id=fst.settings.feedback." if scrolls[0].startswith(
                    "scrollinto:id=fst.settings.feedback.") else wait + "@"
                with self.subTest(run=run.name, page=page["name"]):
                    self.assertTrue(scrolls[0].startswith(first), scrolls[0])
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

    def test_profile_title_runs_at_default_and_largest_text(self):
        # Issue #446 (#97): the avatar-free profile title row runs in CI at default and 225% text, fixture pages only.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-profile-title.json"}
        self.assertEqual({"normal", "text-225"}, set(runs))
        self.assertTrue(all(run.scan for run in runs.values()))
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        pages = json.loads((ci.JOURNEYS / "a11y-profile-title.json").read_text(encoding="utf-8"))
        fixture = {page["name"] for page in pages} - {page["name"] for page in m.live_pages(pages)}
        for run in runs.values():
            with self.subTest(run=run.name):
                only = set(run.only.split(","))
                self.assertFalse({name for name in only if name.startswith("pt-live")}, "CI makes no service calls")
                self.assertTrue({"pt-switch", "pt-anonymous", "pt-selected", "pt-notice"} <= only)
                self.assertLessEqual(fixture, only)
        large = [page["name"] for page in m.mode_pages(pages, "text-225") if page["name"] in runs["text-225"].only]
        self.assertIn("pt-actions-wrap", large)

    def test_experimental_ranks_runs_at_default_and_largest_text(self):
        """#541: the Experimental Ranks toggle and the Rank By gate it drives gate pull requests at 100% and 225% text."""
        runs = {(run.mode, run.scan) for run in ci.RUNS if run.pages == "a11y-experimental-ranks.json"}
        self.assertEqual({("normal", True), ("text-225", True)}, runs)
        pages = {page["name"]: page for page in json.loads(
            (ci.JOURNEYS / "a11y-experimental-ranks.json").read_text(encoding="utf-8"))}
        toggle = pages["xr-settings-toggle"]
        self.assertNotIn("settings", toggle)  # the default: off
        steps = toggle["after_ready"]
        self.assertIn("assertstate:id=fst.settings.experimental-ranks|toggle=off", steps)
        self.assertIn("assertstate:id=fst.settings.experimental-ranks|enabled=true", steps)
        self.assertEqual("waitgone:id=fst.rankings.rank-by-menu@10", steps[-1])
        for name in ("xr-leaderboards-off", "xr-full-rankings-off", "xr-band-rankings-off"):
            with self.subTest(page=name):
                self.assertFalse(pages[name].get("settings", {}).get("experimentalRanks", False))
                self.assertTrue(any(s.startswith("waitgone:") and "rank-by-menu" in s
                                    for s in pages[name]["after_ready"]))
        self.assertTrue(pages["xr-leaderboards-on"]["settings"]["experimentalRanks"])

    def test_shop_filter_runs_at_default_and_largest_text(self):
        # Issue #428 (#19): the Item Shop Filters flyout's accessibility pages gate pull requests at default and 225% text.
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-shop-filter.json"}
        self.assertEqual({"normal", "text-225"}, set(runs))
        self.assertTrue(all(run.scan for run in runs.values()))
        pages = json.loads((ci.JOURNEYS / "a11y-shop-filter.json").read_text(encoding="utf-8"))
        self.assertIn("shop-filter-read", {p["name"] for p in m.mode_pages(pages, "normal")})
        self.assertIn("shop-filter-text", {p["name"] for p in m.mode_pages(pages, "text-225")})
        steps = [s for page in pages for s in (*page.get("ready", []), *page.get("after_ready", []))]
        self.assertIn("assertsize:id=fst.shop.filter.reset|0x40", steps)  # Reset's 40 epx height (32 epx before #428)

    def test_shop_filter_keyboard_runs_at_default_and_largest_text(self):
        """#428 review: the flyout's keyboard journey (Enter, Space, Tab/Shift+Tab, Esc focus return) gates PRs too."""
        runs = {run.mode: run for run in ci.RUNS if run.pages == "a11y-keyboard.json" and "kb-shop-filter" in
                run.only.split(",")}
        self.assertEqual({"normal", "text-225"}, set(runs))
        self.assertTrue(all(run.scan for run in runs.values()))
        self.assertIn("compact", runs["text-225"].sizes.split(","))
        pages = json.loads((ci.JOURNEYS / "a11y-keyboard.json").read_text(encoding="utf-8"))
        page = next(p for p in pages if p["name"] == "kb-shop-filter")
        for mode, run in runs.items():
            with self.subTest(mode=mode):
                self.assertIn(page, m.mode_pages(pages, mode))
                self.assertTrue(m.page_sizes(page, run.sizes.split(","), mode))
        steps = page["after_ready"]
        for key in ("key:enter", "key:space", "key:tab", "key:shift+tab", "key:esc"):
            self.assertIn(key, steps)
        self.assertIn("assertfocus:id=fst.shop.filter@3", steps[steps.index("key:esc"):])  # Esc returns focus

    def test_songs_section_push_runs_at_default_and_largest_text(self):
        # Issue #452 (#288): the pushed section title's Narrator names, headings, order and raw copy, in CI at both sizes.
        runs = {(run.mode, run.scan) for run in ci.RUNS if run.pages == "a11y-songs-section-push.json"}
        self.assertEqual({("normal", True), ("text-225", True)}, runs)
        pages = json.loads((ci.JOURNEYS / "a11y-songs-section-push.json").read_text(encoding="utf-8"))
        self.assertEqual({"push-band", "push-band-reverse", "push-band-keyboard", "push-band-back"}, {page["name"] for page in pages})
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

    def test_songs_section_push_back_returns_mid_push(self):
        # Issue #560: Back to a list left inside the push band keeps the row and list in place (back-keeps-place R5)
        # and redraws the push: the copy is drawn again over the transparent in-list title, which is opaque past it.
        pages = {page["name"]: page for page in json.loads(
            (ci.JOURNEYS / "a11y-songs-section-push.json").read_text(encoding="utf-8"))}
        steps = pages["push-band-back"]["after_ready"]
        back = steps.index("key:alt+left")
        settle = steps.index("wait:1.5", back)
        self.assertLess(steps.index("scrollinset:name=M&class=TextBlock|id=fst.songs.list|16"), back)
        for pin in ("id=fst.songs.list", "id=fst.songs.row.fixture-song-56"):
            self.assertLess(steps.index(f"pin:{pin}"), back)
            self.assertEqual(1, steps[back:settle].count(f"assertpinned:{pin}"))
            self.assertEqual(1, steps[settle:].count(f"assertpinned:{pin}"))
        self.assertIn("assertfocus:id=fst.songs.row.fixture-song-56@3", steps[settle:])
        self.assertLess(back, steps.index("assertname:raw=fst.songs.section-header.incoming|M"))
        self.assertIn("assertpaint:name=M&class=TextBlock|L0,T0,R0,B0=#FFFFFF~40",
                      steps[steps.index("scrollinset:name=M&class=TextBlock|id=fst.songs.list|120"):])

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

    def test_paths_swap_runs_every_page(self):
        # Issue #430 (#70): every Paths swap page (normal, 225% text, Reduce Motion, Animation effects off and the wide
        # selector-box keyboard page) runs in windows-ui, Axe-scanned, at a size the page supports.
        runs = [run for run in ci.RUNS if run.pages == "a11y-paths-swap.json"]
        self.assertEqual({"normal", "text-225", "no-animations"}, {run.mode for run in runs})
        self.assertTrue(all(run.scan and not run.only for run in runs))
        pages = json.loads((ci.JOURNEYS / "a11y-paths-swap.json").read_text(encoding="utf-8"))
        covered = {(page["name"], run.mode) for run in runs for page in m.mode_pages(pages, run.mode)
                   if m.page_sizes(page, run.sizes.split(","), run.mode)}
        self.assertEqual({page["name"] for page in pages}, {name for name, _ in covered})
        self.assertIn(("paths-swap", "text-225"), covered)
        self.assertIn(("paths-swap-keyboard-wide", "text-225"), covered)
        self.assertIn(("paths-swap-motion-system", "no-animations"), covered)
        swap = next(page for page in pages if page["name"] == "paths-swap")["after_ready"]
        for check in ("waitgone:id=fst.paths.image@3", "assertannounced:Loading Lead Hard path@5",
                      "assertread:id=fst.paths.loading|Busy Loading path, ProgressRing",
                      "assertstate:id=fst.paths.difficulty.compact|enabled=true",
                      "assertannounced:Lead Hard path image loaded@5", "assertsize:id=fst.paths.zoom-in|40x40",
                      "assertsize:id=fst.paths.zoom-out|40x40"):
            self.assertIn(check, swap)
        # Design review: the wide instrument circles and the Difficulty/Display selector boxes (issue #650) are 40 epx
        # targets, mid-swap and settled (page-tools-and-nav-chrome R10); both boxes read as named combo boxes with their
        # value and keep keyboard focus across a swap.
        wide = next(page for page in pages if page["name"] == "paths-swap-keyboard-wide")["after_ready"]
        loading = wide.index("waitfor:id=fst.paths.loading@3")
        settled = wide.index("waitfor:name=Lead Hard CHOpt path@15")
        for box in ("difficulty", "display"):
            self.assertIn(f"assertsize:id=fst.paths.{box}|40x40", wide[loading:settled])
        self.assertIn("assertread:id=fst.paths.difficulty|Difficulty, combo box, collapsed", wide[:loading])
        self.assertIn("assertread:id=fst.paths.display|Display, combo box, collapsed", wide[:loading])
        self.assertIn("assertstate:id=fst.paths.difficulty|value=Hard", wide[loading:settled])
        self.assertIn("assertfocus:id=fst.paths.difficulty@3", wide[settled:])
        self.assertIn("assertstate:id=fst.paths.display|value=Text", wide[settled:])
        self.assertIn("assertsize:id=fst.paths.instrument.Solo_Guitar|40x40", wide[settled:])
        self.assertFalse([step for step in wide if "RadioButton" in step])

    def test_paths_selector_surfaces_run_in_every_material_mode(self):
        # Issue #650 (surface-materials R4): the selector boxes' translucent surface (default and 225% text), opaque
        # Transparency-off fill (wide and compact) and Desert system colours each run in an explicit windows-ui Run,
        # Axe-scanned, at the size the page supports; generated runs alone would skip 225% text.
        explicit = {"paths-selectors", "paths-selectors-text-225", "paths-selectors-no-transparency",
                    "paths-selectors-contrast"}
        runs = [run for run in ci.RUNS if run.pages == "a11y-paths-selectors.json"]
        self.assertEqual(explicit, {run.name for run in runs})
        self.assertTrue(all(run.scan and not run.only for run in runs))
        pages = json.loads((ci.JOURNEYS / "a11y-paths-selectors.json").read_text(encoding="utf-8"))
        covered = {(page["name"], run.mode, size) for run in runs for page in m.mode_pages(pages, run.mode)
                   for size in m.page_sizes(page, run.sizes.split(","), run.mode)}
        self.assertEqual({("paths-selector-surface-wide", "normal", "wide"),
                          ("paths-selector-surface-wide", "text-225", "wide"),
                          ("paths-selector-surface-opaque-wide", "no-transparency", "wide"),
                          ("paths-selector-surface-opaque-compact", "no-transparency", "compact"),
                          ("paths-selector-surface-contrast-wide", "hc-desert", "wide")}, covered)
        self.assertEqual({page["name"] for page in pages}, {name for name, _, _ in covered})
        by_name = {page["name"]: page["after_ready"] for page in pages}
        for box in ("difficulty", "display"):
            self.assertIn(f"assertpaint:id=fst.paths.{box}|C0,T8!=#121826~1", by_name["paths-selector-surface-wide"])
            self.assertIn(f"assertpaint:id=fst.paths.{box}|fill:C0,T8=#121826~1|C0,B8=@fill~0|L1,M0!=@fill~6",
                          by_name["paths-selector-surface-opaque-wide"])
            self.assertIn(f"assertpaint:id=fst.paths.{box}|fill:C0,T8|C0,B8=@fill~6",
                          by_name["paths-selector-surface-contrast-wide"])
        for box in ("instrument", "difficulty", "display"):
            self.assertTrue([step for step in by_name["paths-selector-surface-opaque-compact"]
                             if step.startswith(f"assertpaint:id=fst.paths.{box}.compact|fill:C0,T8=#121826~1")])
        self.assertTrue([run for run in ci.tier_runs(runs, "pr") if run.name == "paths-selectors"])

    def test_paths_instrument_picker_runs_in_ci(self):
        # Issue #439 (#88): the compact Instrument ComboBox opens, reads each option by name in order without Karaoke,
        # every option is a 40 epx target, and pointer and keyboard switches announce and keep focus. Checked in
        # windows-ui at default and 225% text and with Animation effects off, Axe-scanned open and after the switch.
        runs = [run for run in ci.RUNS if run.pages == "a11y-paths-swap.json"]
        pages = json.loads((ci.JOURNEYS / "a11y-paths-swap.json").read_text(encoding="utf-8"))
        page = next(page for page in pages if page["name"] == "paths-instrument-picker")
        self.assertTrue(page["scan"])
        modes = {run.mode for run in runs if page in m.mode_pages(pages, run.mode)
                 and m.page_sizes(page, run.sizes.split(","), run.mode)}
        self.assertEqual({"normal", "text-225", "no-animations"}, modes)
        steps = page["after_ready"]
        expand = steps.index("expand:id=fst.paths.instrument.compact")
        select = steps.index("select:name=Bass&class=ComboBoxItem")
        for check in ("assertread:id=fst.paths.instrument.compact|Instrument, combo box, expanded",
                      "assertread:name=Lead&class=ComboBoxItem|Lead, list item, selected",
                      "assertbelow:name=Tap Vocals&class=ComboBoxItem|name=Drums&class=ComboBoxItem",
                      "waitgone:name=Karaoke&class=ComboBoxItem@1", "scan:{stem}-open"):
            self.assertIn(check, steps[expand:select])
        for choice in ("Lead", "Bass", "Drums", "Tap Vocals"):
            self.assertIn(f"assertsize:name={choice}&class=ComboBoxItem|40x40", steps[expand:select])
        for check in ("assertannounced:Loading Bass Expert path@5", "assertstate:id=fst.paths.instrument.compact|value=Bass@5",
                      "key:alt+down", "assertannounced:Loading Lead Expert path@5",
                      "assertfocus:id=fst.paths.instrument.compact@3", "assertfocus:id=fst.paths.difficulty.compact@3"):
            self.assertIn(check, steps[select:])

    def test_paths_instrument_width_runs_in_ci(self):
        # Issue #526 (#280): the compact Instrument box is sized for its longest option, so switching to the longest
        # fixture name (Tap Vocals) by pointer and back to Bass by keyboard leaves all three selector boxes where they
        # were, same width, on one line, read as "Instrument, combo box" with the new value. Checked in windows-ui at
        # default and 225% text and with Animation effects off, Axe-scanned after the switch.
        runs = [run for run in ci.RUNS if run.pages == "a11y-paths-swap.json"]
        pages = json.loads((ci.JOURNEYS / "a11y-paths-swap.json").read_text(encoding="utf-8"))
        page = next(page for page in pages if page["name"] == "paths-instrument-width")
        self.assertTrue(page["scan"])
        modes = {run.mode for run in runs if page in m.mode_pages(pages, run.mode)
                 and m.page_sizes(page, run.sizes.split(","), run.mode)}
        self.assertEqual({"normal", "text-225", "no-animations"}, modes)
        steps = page["after_ready"]
        boxes = ("instrument", "difficulty", "display")
        first = steps.index("select:name=Tap Vocals&class=ComboBoxItem")
        second = steps.index("key:enter")
        for box in boxes:
            self.assertIn(f"pin:id=fst.paths.{box}.compact", steps[:first])
            self.assertIn(f"assertpinned:id=fst.paths.{box}.compact", steps[first:second])
            self.assertIn(f"assertpinned:id=fst.paths.{box}.compact", steps[second:])
        for check in ("assertlevel:id=fst.paths.instrument.compact|id=fst.paths.difficulty.compact",
                      "assertlevel:id=fst.paths.difficulty.compact|id=fst.paths.display.compact"):
            self.assertIn(check, steps[:first])
        for check in ("assertstate:id=fst.paths.instrument.compact|value=Tap Vocals@5",
                      "assertread:id=fst.paths.instrument.compact|Instrument, combo box, collapsed",
                      "assertsize:id=fst.paths.instrument.compact|40x40", "scan:{stem}-tap-vocals"):
            self.assertIn(check, steps[first:second])
        for check in ("assertstate:id=fst.paths.instrument.compact|value=Bass@5",
                      "assertfocus:id=fst.paths.instrument.compact@3", "assertfocus:id=fst.paths.display.compact@3"):
            self.assertIn(check, steps[second:])

    def test_paths_display_focus_ring_runs_in_ci(self):
        # Issue #523 (#269): the dialog content is the dialog less its padding and border, so the compact Display box at
        # the row's right edge keeps its whole keyboard focus ring. Checked in windows-ui at compact and medium, default
        # and 225% text and Animation effects off: the ring's right, top and bottom match its left side.
        runs = [run for run in ci.RUNS if run.pages == "a11y-paths-swap.json"]
        pages = json.loads((ci.JOURNEYS / "a11y-paths-swap.json").read_text(encoding="utf-8"))
        page = next(page for page in pages if page["name"] == "paths-display-focus-ring")
        covered = {(run.mode, size) for run in runs if page in m.mode_pages(pages, run.mode)
                   for size in m.page_sizes(page, run.sizes.split(","), run.mode)}
        self.assertEqual({("normal", "compact"), ("normal", "medium"), ("text-225", "compact"),
                          ("no-animations", "compact")}, covered)
        steps = page["after_ready"]
        self.assertLess(steps.index("key:tab"), steps.index("assertfocus:id=fst.paths.display.compact@3"))
        paint = next(step for step in steps if step.startswith("assertpaint:id=fst.paths.display.compact|"))
        for probe in ("ring:L1,M0", "R1,M0=@ring~48", "C0,T1=@ring~48", "C0,B1=@ring~48", "R-8,M0!=@ring~48"):
            self.assertIn(probe, paint.split("|"))

    def test_paths_chart_runs_every_page(self):
        # Issue #438 (#87, #279): the chart's centring, hidden scroll bars, names, order and keyboard panning are checked
        # in windows-ui at default and 225% text, every page, Axe-scanned.
        runs = [run for run in ci.RUNS if run.pages == "a11y-paths-chart.json"]
        full = [run for run in runs if not run.only]
        self.assertEqual({"normal", "text-225"}, {run.mode for run in full})
        self.assertTrue(all(run.scan for run in runs))
        pages = [page for page in json.loads((ci.JOURNEYS / "a11y-paths-chart.json").read_text(encoding="utf-8"))
                 if not page.get("modes")]
        for mode in ("normal", "text-225"):
            covered = {page["name"] for run in full if run.mode == mode for page in m.mode_pages(pages, run.mode)
                       if m.page_sizes(page, run.sizes.split(","), run.mode)}
            self.assertEqual({page["name"] for page in pages}, covered)
        for page in pages:
            steps = page["after_ready"]
            self.assertIn("scrollbars-always", page["skip_modes"])
            for check in ("assertread:id=fst.paths.image-scroller|Path chart, pane",
                          "assertread:id=fst.paths.image|Lead Expert CHOpt path, image",
                          "assertnoscrollbar:id=fst.paths.image-scroller",
                          "assertaligned:id=fst.paths.image|id=fst.paths.image-scroller"):
                self.assertIn(check, steps)
        chart = next(page for page in pages if page["name"] == "paths-chart")["after_ready"]
        zoomed = chart.index("waitfor:name=225%@5")
        restored = chart.index("waitfor:name=100%@5")
        for check in ("assertfocus:id=fst.paths.image-scroller@3", "key:end",
                      "assertstate:id=fst.paths.image-scroller|scroll=100@3", "assertnoscrollbar:id=fst.paths.image-scroller"):
            self.assertIn(check, chart[zoomed:restored])
        # Zoom out disables at 100% (#279's NormalizeZoom); keyboard focus moves on to Zoom in rather than being lost.
        for check in ("assertstate:id=fst.paths.zoom-out|enabled=false", "assertfocus:id=fst.paths.zoom-in@3",
                      "assertaligned:id=fst.paths.image|id=fst.paths.image-scroller"):
            self.assertIn(check, chart[restored:])

    def test_paths_chart_always_shows_scroll_bars_when_windows_asks(self):
        # Issue #525 (#279's exception): with Settings > Accessibility > Visual effects > "Always show scrollbars" on,
        # the chart holds its scroll bar at rest, zoomed and panned, stays centred, the bar is never a Tab stop, and the
        # zoom round trip keeps names, 40 epx targets and focus; windows-ui runs it at default and 225% text.
        self.assertEqual(m.MODES["scrollbars-always"]["system"], {"always_show_scrollbars": True})
        runs = [run for run in ci.RUNS if run.pages == "a11y-paths-chart.json" and run.only]
        self.assertEqual({"scrollbars-always", "scrollbars-always+text-225"}, {run.mode for run in runs})
        self.assertTrue(all(run.scan and run.only == "paths-chart-scrollbars" for run in runs))
        for run in runs:
            self.assertEqual(["paths-chart-scrollbars"], [page["name"] for page in ci.run_pages(run)])
        pages = json.loads((ci.JOURNEYS / "a11y-paths-chart.json").read_text(encoding="utf-8"))
        page = next(page for page in pages if page["name"] == "paths-chart-scrollbars")
        self.assertEqual(["scrollbars-always"], page["modes"])
        steps = page["after_ready"]
        self.assertNotIn("assertnoscrollbar:id=fst.paths.image-scroller", steps)
        zoomed = steps.index("waitfor:name=225%@5")
        restored = steps.index("waitfor:name=100%@5")
        for part in (steps[:zoomed], steps[zoomed:restored], steps[restored:]):
            self.assertIn("assertscrollbar:id=fst.paths.image-scroller", part)
        for check in ("assertread:id=fst.paths.image-scroller|Path chart, pane",
                      "assertread:id=fst.paths.zoom-out|Zoom out, button, unavailable",
                      "assertorder:id=fst.paths.zoom-out|id=fst.paths.zoom-in|id=fst.paths.image-scroller|id=fst.paths.image|id=CloseButton",
                      "assertsize:id=fst.paths.zoom-in|40x40", "assertaligned:id=fst.paths.image|id=fst.paths.image-scroller"):
            self.assertIn(check, steps[:zoomed])
        # Tab goes zoom -> chart -> Close: the bar's parts are not Tab stops.
        tab = steps.index("key:tab", zoomed)
        self.assertEqual("assertfocus:id=fst.paths.image-scroller@3", steps[tab + 1])
        self.assertIn("assertfocus:id=CloseButton@3", steps[steps.index("key:tab", tab + 1) + 1])
        for check in ("assertstate:id=fst.paths.zoom-out|enabled=false", "assertfocus:id=fst.paths.zoom-in@3",
                      "assertaligned:id=fst.paths.image|id=fst.paths.image-scroller"):
            self.assertIn(check, steps[restored:])

    def test_leaderboard_names_runs_every_page(self):
        # Issue #455 (#292): every long-name page (moving, fits, 150-225% text, Reduce Motion, Animation effects off)
        # runs in windows-ui, Axe-scanned, at a size where the name overflows, and no page is generated twice.
        runs = [run for run in ci.RUNS if run.pages == "a11y-leaderboard-names.json"]
        self.assertEqual({"normal", "text-150", "text-200", "text-225", "no-animations"}, {run.mode for run in runs})
        self.assertTrue(all(run.scan and not run.only for run in runs))
        pages = json.loads((ci.JOURNEYS / "a11y-leaderboard-names.json").read_text(encoding="utf-8"))
        covered = {page["name"] for run in runs for page in m.mode_pages(pages, run.mode)
                   if m.page_sizes(page, run.sizes.split(","), run.mode)}
        self.assertEqual({page["name"] for page in pages}, covered)
        steps = {page["name"]: page["after_ready"] for page in pages}
        self.assertIn("assertmarquee:raw=fst.rankings.row.fixture-player-2.name|moving|30", steps["lb-names-full-rankings"])
        self.assertIn("assertmarquee:raw=fst.rankings.row.fixture-player-1.name|fits|30", steps["lb-names-full-rankings"])
        for reduced in ("lb-names-full-rankings-reduced", "lb-names-full-rankings-system"):
            self.assertIn("assertmarquee:raw=fst.rankings.row.fixture-player-2.name|static|30", steps[reduced])

    def test_leaderboard_name_budget_runs_at_every_large_text_size(self):
        # Issue #455 review (leaderboard-row R2): short, 16-character and placeholder rows keep one pitch at 150-225%.
        pages = {page["name"]: page for page in json.loads((ci.JOURNEYS / "a11y-leaderboard-names.json").read_text(encoding="utf-8"))}
        runs = [run for run in ci.RUNS if run.pages == "a11y-leaderboard-names.json"]
        for name in ("lb-names-budget-full-rankings", "lb-names-budget-overview-skeleton"):
            page = pages[name]
            self.assertIn("--max-name", page["fixture"])
            for mode in ("text-150", "text-200", "text-225"):
                self.assertTrue(any(page in m.mode_pages([page], run.mode) for run in runs if run.mode == mode), (name, mode))
        rows = pages["lb-names-budget-full-rankings"]["after_ready"]
        self.assertIn("markspan:id=fst.rankings.row.fixture-player-1|id=fst.rankings.row.fixture-player-2|pitch", rows)
        self.assertIn("assertspan:id=fst.rankings.row.fixture-player-2|id=fst.rankings.row.fixture-rank-3|pitch", rows)
        card = "fst.leaderboards.card.Solo_PeripheralGuitar"
        skeleton = pages["lb-names-budget-overview-skeleton"]["after_ready"]
        mark = skeleton.index("markspan:id=fst.rankings.row.fixture-player-1|id=fst.rankings.row.fixture-player-2|pitch")
        self.assertLess(mark, skeleton.index(f"assertspan:raw={card}.skeleton.0|raw={card}.skeleton.1|pitch"))
        self.assertIn("Solo_PeripheralGuitar", pages["lb-names-budget-overview-skeleton"]["fixture"])

    def test_paths_text_runs_and_checks_the_table(self):
        # Issue #515 (#223): the Paths text table reads each card once (captions and values Raw), keeps the
        # selectors -> table -> cards -> Close order, keeps values apart, is a keyboard Tab stop, and follows a live
        # contrast switch without clipping the display selector; windows-ui runs it at default, 225% text and Desert.
        runs = [run for run in ci.RUNS if run.pages == "a11y-paths-text.json"]
        self.assertEqual({"normal", "text-225", "hc-desert"}, {run.mode for run in runs})
        self.assertTrue(all(run.scan for run in runs))
        pages = json.loads((ci.JOURNEYS / "a11y-paths-text.json").read_text(encoding="utf-8"))
        names = {page["name"] for page in pages}
        full = [run for run in runs if not run.only]
        self.assertEqual({"normal", "text-225"}, {run.mode for run in full})
        normal = {page["name"] for run in full if run.mode == "normal" for page in m.mode_pages(pages, run.mode)
                  if m.page_sizes(page, run.sizes.split(","), run.mode)}
        self.assertEqual(names, normal)
        large = {page["name"] for run in full if run.mode == "text-225" for page in m.mode_pages(pages, run.mode)
                 if m.page_sizes(page, run.sizes.split(","), run.mode)}
        self.assertEqual({"paths-text", "paths-text-wide", "paths-text-keyboard"}, large)
        # The partial Desert run precedes the full runs, so generated_runs still reads the file as fully covered.
        self.assertLess(ci.RUNS.index(next(run for run in runs if run.only)), ci.RUNS.index(full[0]))
        by_name = {page["name"]: page["after_ready"] for page in pages}
        for name in ("paths-text", "paths-text-wide"):
            steps = by_name[name]
            self.assertIn("assertread:id=fst.paths.table|Path table, pane", steps)
            self.assertIn("assertread:id=fst.paths.activation.1|Activation 1: green, red; beat 5.50; time 00:02:750; "
                          "Overdrive 75%; score 123, group", steps)
            self.assertIn("waitgone:name=00:02:750@1", steps)
            self.assertTrue([s for s in steps if s.startswith("assertorder:") and s.endswith(
                "id=fst.paths.table|id=fst.paths.activation.1|id=fst.paths.activation.2|id=CloseButton")])
            self.assertTrue([s for s in steps if s.startswith("assertapart:raw=fst.paths.activation.")])
        keyboard = by_name["paths-text-keyboard"]
        table = keyboard.index("assertfocus:id=fst.paths.table@3")
        self.assertIn("assertstate:id=fst.paths.table|focusable=true", keyboard[table:])
        self.assertEqual("assertfocus:id=fst.paths.table@3", keyboard[keyboard.index("key:shift+tab") + 1])
        switch = by_name["paths-text-contrast-switch"]
        desert, off = switch.index("contrast:desert"), switch.index("contrast:off")
        self.assertIn("assertpaint:id=fst.paths.display.compact|L0,M-8,L8,M8=#202020~32|R8,M-8,R0,M8=#202020~32",
                      switch[desert:off])
        self.assertTrue([s for s in switch[desert:off] if s.startswith("assertpaint:id=fst.paths.activation.1|")])
        self.assertTrue([s for s in switch[off:] if s.startswith("assertpaint:id=fst.paths.activation.1|")])

    def test_leaderboard_columns_contrast_switch_runs_in_the_normal_pass(self):
        # Issue #519 (#242): a live contrast switch with a song board open repaints the code-set row, pinned-row,
        # selected FC badge and disabled pager brushes; the page runs once at medium in the generated normal pass.
        pages = json.loads((ci.JOURNEYS / "a11y-leaderboard-columns.json").read_text(encoding="utf-8"))
        page = next(item for item in pages if item["name"] == "cols-song-board-contrast-switch")
        self.assertTrue(page["scan"])
        self.assertEqual(["medium"], page["sizes"])
        run = next(run for run in ci.RUNS if run.name == "a11y-leaderboard-columns-normal")
        self.assertIn(page, m.mode_pages(pages, run.mode))
        self.assertTrue(m.page_sizes(page, run.sizes.split(","), run.mode))
        for mode in ("text-225", "hc-desert"):
            self.assertNotIn(page, m.mode_pages(pages, mode))
        steps = page["after_ready"]
        desert, off = steps.index("contrast:desert"), steps.index("contrast:off")
        self.assertLess(desert, off)
        self.assertEqual("contrast:off", [s for s in steps if s.startswith("contrast:")][-1])
        for target in ("id=fst.song-leaderboard.row.fixture-player-3", "id=fst.song-leaderboard.row.fixture-player-2",
                       "raw=fst.score.accuracy.fixture-player-2"):
            for span in (steps[:desert], steps[desert:off], steps[off:]):
                self.assertTrue([s for s in span if s.startswith(f"assertpaint:{target}|")], target)
        self.assertTrue([s for s in steps[desert:off] if s.startswith("assertpaint:id=fst.song-leaderboard.page-first|")])
        self.assertIn("scan:{stem}-desert", steps[desert:off])
        self.assertTrue([s for s in steps[desert:off] if s.startswith("assertorder:") and s.endswith(
            "id=fst.song-leaderboard.spotlight-footer|id=fst.song-leaderboard.page-first|id=fst.song-leaderboard.page-next")])
        # #606 MetadataPills speak the current season as "current season 9"; the column rows must not drift back.
        text = json.dumps(pages)
        self.assertNotIn("(, season 9)?", text)
        self.assertNotIn(", season 9, 5 stars", text)

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
        # Release train: dispatched by the release machine on releases/YYMM.DD only (not on PRs or master).
        self.assertIn("workflow_dispatch:", text)
        self.assertNotIn("pull_request:", text.split("permissions:")[0])
        build, display = text.index("tools/windows/build.ps1"), text.index("tools/windows/ci_display.ps1")
        dispatch = text.index("python tools/windows/ui_ci.py --tier")
        self.assertIn("--tier full", text)
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

    def test_generated_runs_follow_page_sizes(self):
        """A page limited to medium (the Shop row pages) still runs at 225% text: its run adds the first size the page
        allows instead of leaving it with an empty compact pass, while pages without ``sizes`` keep compact."""
        pages = [{"name": "free"}, {"name": "medium-only", "sizes": ["medium", "wide"]},
                 {"name": "wide-only", "sizes": ["wide"]}]
        with tempfile.TemporaryDirectory() as tmp:
            journeys = Path(tmp) / "journeys"
            journeys.mkdir()
            (journeys / "a11y-probe.json").write_text(json.dumps(pages), encoding="utf-8")
            with mock.patch.object(ci, "JOURNEYS", journeys):
                runs = {run.name: run for run in ci.generated_runs(())}
        self.assertEqual((runs["a11y-probe-text-225"].sizes, runs["a11y-probe-text-225"].only),
                         ("compact,medium,wide", "free,medium-only,wide-only"))
        self.assertEqual((runs["a11y-probe-normal"].sizes, runs["a11y-probe-normal"].only),
                         ("compact,medium,wide", "free,medium-only,wide-only"))
        for page in pages:
            self.assertTrue(m.page_sizes(page, runs["a11y-probe-text-225"].sizes.split(","), "text-225"))


    def test_pr_tier_is_normal_mode_at_compact_and_full_is_everything(self):
        pr = ci.tier_runs(list(ci.RUNS), "pr")
        self.assertTrue(pr)
        self.assertTrue(all(run.mode == "normal" and "," not in run.sizes for run in pr))
        self.assertLessEqual({run.name for run in pr}, {run.name for run in ci.RUNS if run.mode == "normal"})
        self.assertTrue(all(ci.run_pages(run) for run in pr))
        self.assertEqual(ci.tier_runs(list(ci.RUNS), "full"), list(ci.RUNS))


if __name__ == "__main__":
    unittest.main()
