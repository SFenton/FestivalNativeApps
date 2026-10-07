"""``fade_trace.py``: fade-line parsing, the phase checks and the page wiring tripwire (issues #260, #323).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root (CI: ``native.yml``).
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fade_trace as f  # noqa: E402  (sibling module)

LOAD = ["startup=10.0", "fade-arm list=CardList start=0", "fade-play list=CardList index=0 delay=125 motion=1",
        "fade-play list=CardList index=1 delay=250 motion=1", "ui-frames count=3 max=4",
        "fade-play list=CardList index=2 delay=375 motion=0"]


def events(*lines: str) -> list[f.FadeEvent]:
    return f.parse(list(lines))


class ParseTests(unittest.TestCase):
    def test_reads_only_fade_lines(self):
        parsed = f.parse(LOAD)
        self.assertEqual(["arm", "play", "play", "play"], [e.kind for e in parsed])
        self.assertEqual({"index": 1, "delay": 250, "motion": 1}, parsed[2].values)
        self.assertEqual([0, 1, 2], f.plays(parsed, "CardList"))
        self.assertEqual([0], f.arms(parsed, "CardList"))
        self.assertEqual([], f.plays(parsed, "SongsList"))

    def test_ignores_malformed_lines(self):
        self.assertEqual([], f.parse(["fade-play", "fade-play list=", "fade-other list=A index=1", "fade-arm list=A start="]))

    def test_reads_entrance_targets_and_the_clock(self):
        parsed = f.parse(["fade-enter list=RowsRepeater target=SpotlightPanel delay=125 motion=1 at=5122",
                          "fade-early list=Scroller target=BandBoards left=830 at=5600"])
        self.assertEqual(["enter", "early"], [e.kind for e in parsed])
        self.assertEqual({"target": "SpotlightPanel", "delay": 125, "motion": 1, "at": 5122}, parsed[0].values)
        self.assertEqual("BandBoards", parsed[1].values["target"])


class CheckTests(unittest.TestCase):
    def test_load_passes_contiguous_stagger(self):
        self.assertEqual([], f.check_load(f.parse(LOAD), "CardList"))

    def test_load_fails_without_fades_or_with_gaps(self):
        self.assertIn("no row faded", f.check_load(events("fade-arm list=A start=0"), "A")[0])
        self.assertIn("expected each", f.check_load(events("fade-play list=A index=0", "fade-play list=A index=2"), "A")[0])
        self.assertTrue(f.check_load(events("fade-play list=A index=0", "fade-play list=A index=0"), "A"))

    def test_batch_passes_when_only_new_rows_fade(self):
        found = f.check_batch(events("fade-arm list=A start=16", "fade-play list=A index=16",
                                     "fade-arm list=A start=16", "fade-play list=A index=17"), "A")
        self.assertEqual([], found)

    def test_batch_catches_each_regression(self):
        # Restagger call deleted: no re-arm.
        self.assertIn("no re-arm", f.check_batch([], "A")[0])
        # Re-armed from 0 instead of the batch start.
        self.assertIn("no re-arm", f.check_batch(events("fade-arm list=A start=0", "fade-play list=A index=1"), "A")[0])
        # Re-armed but nothing of the batch faded.
        self.assertIn("no row of the batch", f.check_batch(events("fade-arm list=A start=16"), "A")[0])
        # Old rows fade again, or a row twice.
        self.assertIn("faded again", f.check_batch(events("fade-arm list=A start=16", "fade-play list=A index=16",
                                                          "fade-play list=A index=3"), "A")[0])
        self.assertIn("twice", f.check_batch(events("fade-arm list=A start=16", "fade-play list=A index=16",
                                                    "fade-play list=A index=16"), "A")[0])

    def test_only_new_allows_a_fresh_batch_but_no_replays(self):
        self.assertEqual([], f.check_only_new([], "A"))
        self.assertEqual([], f.check_only_new(events("fade-arm list=A start=16", "fade-play list=A index=16"), "A"))
        self.assertTrue(f.check_only_new(events("fade-play list=A index=3"), "A"))
        self.assertTrue(f.check_only_new(events("fade-arm list=A start=16", "fade-play list=A index=4"), "A"))
        self.assertEqual([], f.check_only_new(events("fade-play list=B index=3"), "A"))

    def test_none(self):
        self.assertEqual([], f.check_none(events("fade-arm list=A start=0")))
        self.assertTrue(f.check_none(events("fade-play list=A index=0")))

    def test_only_new_ignores_rush_close_hold_reveal_and_skip_lines(self):
        self.assertEqual([], f.check_only_new(events("fade-close list=A start=0 since=300", "fade-skip list=A index=6",
                                                     "fade-rush list=A start=0 rushed=0 since=200",
                                                     "fade-hold list=A held=0 wait=900",
                                                     "fade-reveal list=A index=3 wait=900 scrolled=1"), "A"))


SCROLLED = ["fade-arm list=A start=0", "fade-play list=A index=0 delay=125", "fade-play list=A index=1 delay=250",
            "fade-rush list=A start=0 rushed=2 since=420", "fade-play list=A index=5 delay=0", "fade-skip list=A index=6"]


class LoadThenScrollTests(unittest.TestCase):
    def test_parses_rush_close_hold_reveal_and_skip(self):
        parsed = f.parse(SCROLLED + ["fade-close list=A start=0 since=2600", "fade-hold list=A held=8 wait=1650",
                                     "fade-reveal list=A index=17 wait=1650 scrolled=1"])
        self.assertEqual(["arm", "play", "play", "rush", "play", "skip", "close", "hold", "reveal"],
                         [e.kind for e in parsed])
        self.assertEqual({"start": 0, "rushed": 2, "since": 420}, parsed[3].values)
        self.assertEqual({"index": 17, "wait": 1650, "scrolled": 1}, parsed[8].values)

    def test_passes_when_the_scroll_rushes_and_old_rows_fade_together(self):
        self.assertEqual([], f.check_load_then_scroll(events(*SCROLLED), "A"))
        # A batch appended by the scroll may stagger its own rows.
        self.assertEqual([], f.check_load_then_scroll(events(*SCROLLED, "fade-arm list=A start=10",
                                                             "fade-play list=A index=10 delay=125"), "A"))
        # Each kind of proof alone suffices: started pending fades, a delay-0 play or a skip.
        rush_only = SCROLLED[:4]
        self.assertEqual([], f.check_load_then_scroll(events(*rush_only), "A"))
        quiet = [SCROLLED[0], SCROLLED[1], "fade-rush list=A start=0 rushed=0 since=900"]
        self.assertEqual([], f.check_load_then_scroll(events(*quiet, "fade-skip list=A index=6"), "A"))
        self.assertEqual([], f.check_load_then_scroll(events(*quiet, "fade-play list=A index=4 delay=0"), "A"))

    def test_catches_the_r5_regression(self):
        # Rows realized by the scroll kept their stagger instead of fading in together (issue #323).
        found = f.check_load_then_scroll(events(*SCROLLED, "fade-play list=A index=3 delay=375"), "A")
        self.assertIn("kept a stagger instead of fading in together: [3]", found[0])
        # Old rows staggered after a later batch re-armed: only the batch may stagger.
        found = f.check_load_then_scroll(events(*SCROLLED, "fade-arm list=A start=10",
                                                "fade-play list=A index=7 delay=125"), "A")
        self.assertIn("[7]", found[0])
        # A reload arm from 0 after the rush does not license old rows to fade again.
        found = f.check_load_then_scroll(events(*SCROLLED, "fade-arm list=A start=0", "fade-play list=A index=0"), "A")
        self.assertIn("faded in again", found[0])

    def test_a_close_inside_the_window_means_the_rush_is_gone(self):
        closed = [line.replace("fade-rush list=A start=0 rushed=2", "fade-close list=A start=0") for line in SCROLLED]
        self.assertIn("rush is missing", f.check_load_then_scroll(events(*closed), "A")[0])
        late = [line.replace("since=420", "since=1500") for line in closed]
        self.assertIn("not exercised", f.check_load_then_scroll(events(*late), "A")[0])
        # A journey that lengthens the app's window measures the close against that window.
        self.assertIn("rush is missing", f.check_load_then_scroll(events(*late), "A", 4000)[0])

    def test_fails_when_nothing_was_proven(self):
        self.assertIn("fade-rush missing", f.check_load_then_scroll(events(*SCROLLED[:3]), "A")[0])
        quiet = [SCROLLED[0], SCROLLED[1], "fade-rush list=A start=0 rushed=0 since=900"]
        self.assertIn("nothing proven", f.check_load_then_scroll(events(*quiet), "A")[0])
        # Skips of a kept batch's rows are not old rows of the rushed load entrance.
        self.assertIn("nothing proven", f.check_load_then_scroll(
            events(*quiet, "fade-arm list=A start=10", "fade-skip list=A index=12"), "A")[0])
        # The load itself must still have faded its first screen.
        self.assertIn("no row faded", f.check_load_then_scroll(events(*SCROLLED[3:]), "A")[0])

    def test_a_batch_kept_by_the_rush_may_stagger_only_its_own_rows(self):
        kept = ["fade-arm list=A start=0", "fade-play list=A index=0", "fade-arm list=A start=10",
                "fade-rush list=A start=10 rushed=1 since=300", "fade-skip list=A index=6"]
        self.assertEqual([], f.check_load_then_scroll(events(*kept, "fade-play list=A index=10 delay=125"), "A"))
        self.assertIn("[4]", f.check_load_then_scroll(events(*kept, "fade-play list=A index=4 delay=125"), "A")[0])


PAGE = ["fade-arm list=Scroller start=0 at=1000",
        "fade-enter list=Scroller target=TitleRow delay=0 motion=1 at=1000",
        "fade-enter list=Scroller target=OverviewHeading delay=125 motion=1 at=1000",
        "fade-enter list=Scroller target=OverviewGrid delay=1650 motion=1 at=1000"]
"""A page entrance whose last element (OverviewGrid) is still pending when a scroll at 1500 ms rushes it."""
EARLY_RUSH = ["fade-early list=Scroller target=OverviewGrid left=1150 at=1500",
              "fade-rush list=Scroller start=0 rushed=1 kept=0 since=500 at=1500"]


class EntranceRushTests(unittest.TestCase):
    def test_enrolled(self):
        self.assertEqual([], f.check_enrolled(events(*PAGE), "Scroller", ["TitleRow", "OverviewGrid"]))
        # A pinned row faded outside its board's entrance (review #358: a sibling of the list's scroller).
        found = f.check_enrolled(events("fade-arm list=RowsRepeater start=0",
                                        "fade-enter list=Page target=SpotlightPanel delay=125"),
                                 "RowsRepeater", ["SpotlightPanel"])
        self.assertIn("SpotlightPanel did not fade in with its entrance", found[0])
        self.assertIn("entered with Page", found[0])
        self.assertIn("no fade-enter", f.check_enrolled([], "RowsRepeater", ["FooterSpotlight"])[0])

    def test_a_rush_that_starts_every_pending_fade_passes(self):
        self.assertEqual([], f.check_entrance_rush(events(*PAGE, *EARLY_RUSH), "Scroller", ["OverviewGrid"]))
        # Fades that had started before the rush need nothing; later entrances start at once.
        done = PAGE[:3] + ["fade-rush list=Scroller start=0 rushed=0 kept=0 since=500 at=1500",
                           "fade-enter list=Scroller target=Card delay=0 motion=1 at=1600"]
        self.assertEqual([], f.check_entrance_rush(events(*done), "Scroller"))

    def test_a_pending_fade_that_keeps_its_delay_fails(self):
        # The rush did not start the still-pending OverviewGrid (no fade-early): the review's Player Profile regression.
        found = f.check_entrance_rush(events(*PAGE, EARLY_RUSH[1].replace("rushed=1", "rushed=0")), "Scroller")
        self.assertIn("kept their delay through the rush: ['OverviewGrid']", found[0])
        self.assertIn("started 0 fade(s) but 1 were still pending", found[1])
        # A pending fade of the entrance the rush did not reach.
        found = f.check_entrance_rush(events(*PAGE, EARLY_RUSH[0], EARLY_RUSH[1].replace("kept=0", "kept=1")), "Scroller")
        self.assertIn("kept 1 pending fade(s)", found[0])
        # A pending row of a board still due after the rush, not counted in rushed.
        rows = ["fade-arm list=A start=0 at=1000", "fade-play list=A index=9 delay=1250 motion=1 at=1000",
                "fade-rush list=A start=0 rushed=0 kept=0 since=300 at=1300"]
        self.assertIn("1 were still pending", f.check_entrance_rush(events(*rows), "A")[0])

    def test_a_fade_scheduled_after_the_rush_with_a_delay_fails(self):
        late = [*PAGE, *EARLY_RUSH, "fade-enter list=Scroller target=BandBoards delay=300 motion=1 at=1600",
                "fade-play list=Scroller index=2 delay=250 motion=1 at=1600"]
        found = f.check_entrance_rush(events(*late), "Scroller")
        self.assertIn("['BandBoards', 'index 2']", found[0])
        # A re-arm from 0 starts a new entrance, which may stagger again.
        rearmed = [*PAGE, *EARLY_RUSH, "fade-arm list=Scroller start=0 at=9000",
                   "fade-enter list=Scroller target=TitleRow delay=125 motion=1 at=9000"]
        self.assertEqual([], f.check_entrance_rush(events(*rearmed), "Scroller"))

    def test_the_rushed_entrance_is_the_last_arm_before_the_scroll(self):
        # Song Details reloading in place (another song) arms again; only the entrance the scroll hit must hold targets.
        earlier = ["fade-arm list=Scroller start=0 at=0", "fade-enter list=Scroller target=Gone delay=0 motion=1 at=0"]
        self.assertEqual([], f.check_entrance_rush(events(*earlier, *PAGE, *EARLY_RUSH), "Scroller", ["OverviewGrid"]))
        stale = [*PAGE[:1], "fade-enter list=Scroller target=OverviewGrid delay=0 motion=1 at=1000",
                 "fade-arm list=Scroller start=0 at=1100", *EARLY_RUSH[1:]]
        self.assertIn("OverviewGrid did not fade in", f.check_entrance_rush(events(*stale), "Scroller", ["OverviewGrid"])[0])

    def test_the_scroll_must_rush_not_close(self):
        self.assertIn("fade-rush missing", f.check_entrance_rush(events(*PAGE), "Scroller")[0])
        closed = [*PAGE, "fade-close list=Scroller start=0 since=500 at=1500"]
        self.assertIn("rush is missing", f.check_entrance_rush(events(*closed), "Scroller", window_ms=4000)[0])
        self.assertIn("not exercised", f.check_entrance_rush(
            events(*PAGE, "fade-close list=Scroller start=0 since=5000"), "Scroller", window_ms=4000)[0])


BOARD = ["fade-arm list=RowsRepeater start=0 at=1000",
         "fade-play list=RowsRepeater index=0 delay=125 motion=1 at=1000",
         "fade-play list=RowsRepeater index=9 delay=1250 motion=1 at=1000",
         "fade-play list=RowsRepeater index=12 delay=2400 motion=1 at=1000",
         "fade-enter list=RowsRepeater target=SpotlightPanel delay=125 motion=1 at=1001",
         "fade-hold list=RowsRepeater held=2 wait=2025 at=1002",
         "fade-rush list=RowsRepeater start=0 rushed=1 kept=0 since=2030 at=3030",
         "fade-reveal list=RowsRepeater index=16 wait=2025 scrolled=1 at=3030",
         "fade-play list=RowsRepeater index=17 delay=0 motion=1 at=3100"]
"""Song Detail → player score: the board loads, holds its tail, rushes row 12 and scrolls to row 16."""


class RevealTests(unittest.TestCase):
    def test_the_reveal_rushes_the_board_then_scrolls(self):
        self.assertEqual([], f.check_reveal(events(*BOARD), "RowsRepeater", 16, ["SpotlightPanel"]))
        # An earlier board load (another page) before the last arm is ignored.
        self.assertEqual([], f.check_reveal(events("fade-arm list=RowsRepeater start=0 at=10",
                                                   "fade-play list=RowsRepeater index=0 delay=900 at=10", *BOARD),
                                            "RowsRepeater", 16))

    def test_each_regression_is_caught(self):
        self.assertIn("fade-reveal missing", f.check_reveal(events(*BOARD[:7]), "RowsRepeater")[0])
        # The pinned row faded outside the board's entrance.
        unpinned = [line for line in BOARD if "SpotlightPanel" not in line]
        self.assertIn("SpotlightPanel did not fade", f.check_reveal(events(*unpinned), "RowsRepeater", 16, ["SpotlightPanel"])[0])
        # Scrolled without a rush, or the rush left the tail row on its delay.
        self.assertIn("without rushing", f.check_reveal(events(*BOARD[:6], *BOARD[7:]), "RowsRepeater")[0])
        unrushed = [line.replace("rushed=1", "rushed=0") for line in BOARD]
        self.assertIn("1 were still pending", f.check_reveal(events(*unrushed), "RowsRepeater")[0])
        # Scrolled before the row's own entrance finished.
        hasty = [line.replace("index=16 wait=2025 scrolled=1 at=3030", "index=16 wait=2025 scrolled=1 at=1500") for line in BOARD]
        self.assertIn("before the row's own entrance", f.check_reveal(events(*hasty), "RowsRepeater")[0])
        # Went to another row, or did not scroll.
        self.assertIn("row 16, expected 15", f.check_reveal(events(*BOARD), "RowsRepeater", 15)[0])
        still = [line.replace("scrolled=1", "scrolled=0") for line in BOARD]
        self.assertIn("did not scroll", f.check_reveal(events(*still), "RowsRepeater")[0])
        # A row the scroll realized kept a stagger.
        staggered = [*BOARD[:-1], "fade-play list=RowsRepeater index=17 delay=375 motion=1 at=3100"]
        self.assertIn("['index 17']", f.check_reveal(events(*staggered), "RowsRepeater")[0])
        self.assertIn("never armed", f.check_reveal(events(*BOARD[7:]), "RowsRepeater")[0])


class DelayedPlayTests(unittest.TestCase):
    """Every delayed fade belongs to an entrance: no direct ``FadeIn.Play(element, delay)`` (review #358)."""

    def test_the_windows_sources_play_no_delayed_fade_directly(self):
        self.assertEqual([], f.delayed_play_problems())

    def test_a_direct_delayed_play_is_reported(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            page = root / "windows" / "Festival.App" / "Pages" / "Board.xaml.cs"
            page.parent.mkdir(parents=True)
            page.write_text("FadeIn.Play(SpotlightPanel);\n"
                            "// FadeIn.Play(Old, TimeSpan.Zero);\n"
                            "DispatcherQueue.TryEnqueue(() => FadeIn.Play(Footer, PinnedRowReveal.RevealDelay));\n"
                            "FadeIn.Play(Items(0), FadeInTiming.Interval * 2);\n", encoding="utf-8")
            built = root / "windows" / "Festival.App" / "obj" / "Gen.cs"
            built.parent.mkdir(parents=True)
            built.write_text("FadeIn.Play(X, Y);\n", encoding="utf-8")
            problems = f.delayed_play_problems(root)
        self.assertEqual(["windows/Festival.App/Pages/Board.xaml.cs:3", "windows/Festival.App/Pages/Board.xaml.cs:4"],
                         [p.split(": ")[0] for p in problems])


class RunPhasesTests(unittest.TestCase):
    def test_each_phase_sees_only_its_own_lines(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / "perf.log"
            writes = iter([LOAD, ["fade-arm list=CardList start=10", "fade-play list=CardList index=10"], []])
            driven = []

            def drive(steps):
                driven.append(steps)
                with log.open("a", encoding="utf-8") as handle:
                    handle.writelines(line + "\n" for line in next(writes))

            failures = f.run_phases(drive, log, [
                f.Phase("load", ["a"], lambda e: f.check_load(e, "CardList")),
                f.Phase("more", ["b"], lambda e: f.check_batch(e, "CardList")),
                f.Phase("idle", ["c"], f.check_none),
            ])
        self.assertEqual([], failures)
        self.assertEqual([["a", f.SETTLE_STEP], ["b", f.SETTLE_STEP], ["c", f.SETTLE_STEP]], driven)

    def test_failures_name_their_phase(self):
        with tempfile.TemporaryDirectory() as folder:
            failures = f.run_phases(lambda steps: None, Path(folder) / "missing.log",
                                    [f.Phase("load", [], lambda e: f.check_load(e, "CardList"))])
        self.assertEqual(["load: CardList: no row faded in at load"], failures)


class WiringTests(unittest.TestCase):
    """CI cannot run WinUI journeys: fail when a page drops the call a fade journey exercises."""

    def test_page_wiring_is_in_place(self):
        self.assertEqual([], f.wiring_problems())

    def test_a_deleted_or_commented_call_is_reported(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for rel, _, _ in f.WIRING:
                source = (f.ROOT / rel).read_text(encoding="utf-8")
                (root / rel).parent.mkdir(parents=True, exist_ok=True)
                (root / rel).write_text(source, encoding="utf-8")
            suggestions = root / f.WIRING[0][0]
            text = suggestions.read_text(encoding="utf-8")
            suggestions.write_text(text.replace("ViewModel.CardsAdded +=", "// ViewModel.CardsAdded +="), encoding="utf-8")
            search = root / f.WIRING[2][0]
            text = search.read_text(encoding="utf-8")
            search.write_text(text.replace("FadeIn.Restagger(section", "Noop(section"), encoding="utf-8")
            problems = f.wiring_problems(root)
        self.assertEqual(2, len(problems))
        self.assertIn("SuggestionsPage", problems[0])
        self.assertIn("SearchPage", problems[1])

    def test_a_pinned_row_or_profile_fading_outside_its_entrance_is_reported(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for rel, _, _ in f.WIRING:
                source = (f.ROOT / rel).read_text(encoding="utf-8")
                (root / rel).parent.mkdir(parents=True, exist_ok=True)
                (root / rel).write_text(source, encoding="utf-8")
            board = root / "windows/Festival.App/Pages/LeaderboardsFullRankingsPage.xaml.cs"
            board.write_text(board.read_text(encoding="utf-8").replace(
                "FadeIn.Enter(RowsRepeater, FooterSpotlight, PinnedRowReveal.RevealDelay)",
                "FadeIn.Play(FooterSpotlight, PinnedRowReveal.RevealDelay)"), encoding="utf-8")
            profile = root / "windows/Festival.App/Controls/PlayerProfileView.xaml.cs"
            profile.write_text(profile.read_text(encoding="utf-8").replace("FadeIn.BeginEntrance(Scroller);", ""),
                               encoding="utf-8")
            problems = f.wiring_problems(root)
            direct = f.delayed_play_problems(root)
        self.assertEqual(2, len(problems))
        self.assertIn("PlayerProfileView", problems[0])
        self.assertIn("LeaderboardsFullRankingsPage", problems[1])
        self.assertEqual(1, len(direct))
        self.assertIn("LeaderboardsFullRankingsPage", direct[0])


if __name__ == "__main__":
    unittest.main()
