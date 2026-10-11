"""Song leaderboard footer and paging accessibility pages: ``journeys/a11y-song-leaderboard.json`` (issues #93, #443),
the song board end (#456) and the states #197 changed (``a11y-song-board-states.json``, #511).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ui_ci  # noqa: E402  (sibling module)
import uiwin  # noqa: E402  (sibling module)

JOURNEYS = Path(__file__).resolve().parents[1] / "journeys"
JOURNEY = JOURNEYS / "a11y-song-leaderboard.json"
FOOTER_FADE = JOURNEYS / "a11y-board-footer-fade.json"
BOARD = "id=fst.song-leaderboard"
PAGER = [f"{BOARD}.page-{part}" for part in ("first", "previous", "next", "last")]
PINNED = f"{BOARD}.spotlight-footer"
FADE = f"{BOARD}.footer-fade"


def load(path: Path = JOURNEY) -> dict[str, dict]:
    """A journey's pages by name."""
    return {page["name"]: page for page in json.loads(path.read_text(encoding="utf-8"))}


def steps(page: dict) -> list[str]:
    """Every step the matrix drives for a page, in order."""
    return [*page.get("setup", []), *page.get("ready", []), *page.get("after_ready", []), *page.get("teardown", [])]


def covered(pages: str) -> set[tuple[str, str, str]]:
    """``(page, size, mode)`` triples the Axe-scanned ``windows-ui`` runs drive for a journey file."""
    every = load(JOURNEYS / pages)
    return {(page, size, run.mode) for run in ui_ci.RUNS if run.pages == pages and run.scan
            for page in (run.only.split(",") if run.only else every) for size in run.sizes.split(",")}


class SongLeaderboardJourneyTests(unittest.TestCase):
    """The pages parse, keep the #93 checks and run in ``windows-ui``."""

    def test_every_step_parses(self):
        for page in load().values():
            for step in steps(page):
                uiwin.parse_step(step)

    def test_pages_use_the_slow_paging_fixture_and_a_selected_player(self):
        """Fixture only (no service calls from CI); the selected player brings the pinned row."""
        for name, page in load().items():
            self.assertIn("--song-leaderboard-paging", page.get("fixture", []), name)
            self.assertTrue(page["profile"].startswith("fixture-player-1:"), name)

    def test_footer_names_states_targets_and_order(self):
        """The floating footer (#93): pinned row and pager read with their names and states, are 40x40 epx targets,
        and read after the header and rows; the fade layer is decorative (raw view only) yet fades 40 epx."""
        drive = steps(load()["song-board-footer"])
        for step in ("assertread:id=fst.song-leaderboard.page-first|First page, button, unavailable",
                     "assertread:id=fst.song-leaderboard.page-previous|Previous page, button, unavailable",
                     "assertread:id=fst.song-leaderboard.page-info|Page 1 of 4, text",
                     "assertread:id=fst.song-leaderboard.page-next|Next page, button",
                     "assertread:id=fst.song-leaderboard.page-last|Last page, button",
                     f"waitgone:{FADE}@2", f"assertstatus:{FADE}|fading:40@5"):
            self.assertIn(step, drive)
        self.assertTrue(any(s.startswith(f"assertread:{PINNED}|~^Your rank, 1st\\. Open your statistics") for s in drive))
        for target in [*PAGER, PINNED]:
            self.assertIn(f"assertsize:{target}|40x40", drive)
        order = next(s for s in drive if s.startswith("assertorder:"))
        self.assertEqual(order.split(":", 1)[1].split("|"),
                         [f"{BOARD}.song", f"{BOARD}.row.fixture-player-2", PINNED, PAGER[0], PAGER[1],
                          f"{BOARD}.page-info", PAGER[2], PAGER[3]])

    def test_keyboard_page_change_keeps_header_pinned_row_and_pager(self):
        """#93: a page change used to hide the header and pager. While the slow page loads (rows gone, ring named),
        the header, pinned row and pager stay in reading order and focus stays on Next; then page 2 is announced,
        Previous becomes available and the pinned row turns into the jump (leaderboard-row R7)."""
        drive = steps(load()["song-board-paging-keyboard"])
        self.assertEqual([s for s in drive if s.startswith(("invoke:", "click"))], [])
        sequence = [f"focus:{PAGER[2]}", "key:enter",
                    "waitgone:id=fst.song-leaderboard.row.fixture-player-2@5",
                    f"assertfocus:{PAGER[2]}",
                    "assertread:class=Microsoft.UI.Xaml.Controls.ProgressRing|~Loading leaderboard@2",
                    "waitfor:id=fst.song-leaderboard.row.fixture-player-26@15",
                    "assertread:id=fst.song-leaderboard.page-info|Page 2 of 4, text@5",
                    "assertread:id=fst.song-leaderboard.page-previous|Previous page, button"]
        positions = [drive.index(step) for step in sequence]
        self.assertEqual(positions, sorted(positions))
        loading = drive[positions[3]:positions[5]]
        order = next(s for s in loading if s.startswith("assertorder:"))
        self.assertEqual(order.split(":", 1)[1].split("|"),
                         [f"{BOARD}.song", PINNED, PAGER[0], f"{BOARD}.page-info", PAGER[2], PAGER[3]])
        loaded = drive[positions[5]:]
        self.assertIn(f"assertfocus:{PAGER[2]}", loaded)
        self.assertTrue(any(s.startswith(f"assertread:{PINNED}|~^Your rank, 1st\\. Jump to your position") for s in loaded))
        # The keyboard-focus tooltip's popup bridge is a framework Axe finding; the scan runs with it closed.
        self.assertEqual(drive[-2:], [f"focus:{BOARD}.song", "waitgone:class=ToolTip@5"])

    def test_tab_order_at_rest_while_loading_and_after_a_page_change(self):
        """#443 review: Tab/Shift+Tab, not only the reading order, walk header -> rows -> pinned row -> enabled pager
        buttons on page 1; while the next page loads (rows gone, First/Previous disabled) Next -> pinned row -> header
        and back; on page 2 First and Previous rejoin. The Enter activation stays a separate ``focus:`` retention check."""
        drive = steps(load()["song-board-paging-keyboard"])
        song, row1, nxt = f"{BOARD}.song", f"{BOARD}.row.fixture-player-1", PAGER[2]
        rest = [f"focus:{song}", f"assertfocus:{song}", "key:tab", f"assertfocus:{row1}", "key:tab",
                f"assertfocus:{PINNED}", "key:tab", f"assertfocus:{nxt}", "key:tab", f"assertfocus:{PAGER[3]}",
                "key:shift+tab", f"assertfocus:{nxt}", "key:shift+tab", f"assertfocus:{PINNED}",
                "key:shift+tab", "key:shift+tab", f"assertfocus:{song}"]
        activate = [f"focus:{nxt}", "key:enter", f"assertfocus:{nxt}"]
        loading = ["key:shift+tab", f"assertfocus:{PINNED}", "key:shift+tab", f"assertfocus:{song}",
                   "key:tab", f"assertfocus:{PINNED}", "key:tab", f"assertfocus:{nxt}"]
        loaded = [f"assertfocus:{nxt}", "key:shift+tab", f"assertfocus:{PAGER[1]}", "key:shift+tab",
                  f"assertfocus:{PAGER[0]}", "key:shift+tab", f"assertfocus:{PINNED}", "key:shift+tab", "key:shift+tab",
                  f"assertfocus:{song}", "key:tab", "key:tab", f"assertfocus:{PINNED}", "key:tab",
                  f"assertfocus:{PAGER[0]}", "key:tab", f"assertfocus:{PAGER[1]}", "key:tab", f"assertfocus:{nxt}",
                  "key:tab", f"assertfocus:{PAGER[3]}", f"focus:{song}"]
        walk = [s.split("@")[0] for s in drive if s.startswith(("focus:", "key:", "assertfocus:"))]
        self.assertEqual(walk, rest + activate + loading + loaded)
        # The loading walk runs between the rows leaving and the ring's "Loading leaderboard" read, so it can only
        # pass while page 2 is still loading (with rows back, Shift+Tab from the pinned row would land on a row).
        gone = drive.index("waitgone:id=fst.song-leaderboard.row.fixture-player-2@5")
        ring = drive.index("assertread:class=Microsoft.UI.Xaml.Controls.ProgressRing|~Loading leaderboard@2")
        self.assertEqual([s.split("@")[0] for s in drive[gone + 1:ring]], activate[2:] + loading)

    def test_windows_ui_runs_both_pages_at_225_percent_text_and_paging_with_reduce_motion(self):
        runs = covered(JOURNEY.name)
        for page in load():
            for size, mode in (("compact", "normal"), ("medium", "normal"), ("compact", "text-225")):
                self.assertIn((page, size, mode), runs)
        self.assertIn(("song-board-paging-keyboard", "medium", "app-reduced"), runs)

    def test_windows_ui_runs_the_song_board_footer_fade_pages(self):
        """The #93 fade states (rest, mid, end, More Contrast and Less Transparency hard edge) at 100% and 225% text."""
        pages = load(FOOTER_FADE)
        names = [name for name in pages if name.startswith("footer-fade-song-leaderboard-") and "system" not in name]
        self.assertEqual(sorted(names), sorted(ui_ci.SONG_BOARD_FOOTER_FADE.split(",")))
        runs = covered(FOOTER_FADE.name)
        for name in names:
            for size, mode in (("compact", "normal"), ("medium", "normal"), ("compact", "text-225")):
                self.assertIn((name, size, mode), runs)
        for name in ("footer-fade-song-leaderboard-more-contrast", "footer-fade-song-leaderboard-less-transparency"):
            self.assertIn(f"assertstatus:{FADE}|hard-edge@5", steps(pages[name]))


END_JOURNEY = JOURNEYS / "a11y-song-board-end.json"
LAST = f"{BOARD}.row.fixture-player-25"


class SongBoardEndJourneyTests(unittest.TestCase):
    """``journeys/a11y-song-board-end.json`` (issue #456): the end of the list that #293 changed."""

    def test_every_step_parses(self):
        for page in load(END_JOURNEY).values():
            for step in steps(page):
                uiwin.parse_step(step)

    def test_pages_cover_pinned_row_no_score_and_no_player(self):
        pages = load(END_JOURNEY)
        self.assertEqual(set(pages), {"song-board-end-player", "song-board-end-no-score", "song-board-end-anonymous"})
        self.assertTrue(pages["song-board-end-player"]["profile"].startswith("fixture-player-1:"))
        self.assertTrue(pages["song-board-end-no-score"]["profile"].startswith("fixture-empty:"))
        self.assertNotIn("profile", pages["song-board-end-anonymous"])
        for name in ("song-board-end-no-score", "song-board-end-anonymous"):
            self.assertIn(f"waitgone:{PINNED}@5", steps(pages[name]), name)
        for page in pages.values():
            self.assertTrue(page["scan"], page["name"])

    def test_last_row_reached_by_keyboard_sits_one_row_gap_above_the_footer(self):
        """#293: the list ends one 4 epx row gap above the footer's first part (pinned row, else the pager), the last
        row is clear of it (WCAG 2.4.11), reads before it, keeps a 40 epx target, and the fade is gone at the end."""
        for name, page in load(END_JOURNEY).items():
            drive = steps(page)
            first = PINNED if name == "song-board-end-player" else PAGER[0]
            self.assertEqual(drive.count("key:down"), 24, name)
            self.assertIn(f"assertfocus:{LAST}@3", drive, name)
            self.assertIn(f"assertstate:{BOARD}.list|scroll=100@3", drive, name)
            self.assertIn(f"assertgap:{LAST}|{first}|4", drive, name)
            self.assertIn(f"assertapart:{LAST}|{PAGER[2]}" if first == PAGER[0] else f"assertapart:{LAST}|{PINNED}",
                          drive, name)
            self.assertIn(f"assertsize:{LAST}|0x40", drive, name)
            self.assertIn(f"assertstatus:{FADE}|end@5", drive, name)
            order = next(s for s in drive if s.startswith("assertorder:")).split(":", 1)[1].split("|")
            expected = [f"{BOARD}.row.fixture-player-24", LAST, *([PINNED] if first == PINNED else []),
                        PAGER[0], PAGER[1], f"{BOARD}.page-info", PAGER[2], PAGER[3]]
            self.assertEqual(order, expected, name)

    def test_tab_leaves_the_last_row_for_the_footer_and_shift_tab_returns(self):
        pages = load(END_JOURNEY)
        hops = {"song-board-end-player": [PINNED, PAGER[2], PINNED, LAST],
                "song-board-end-no-score": [PAGER[2], LAST], "song-board-end-anonymous": [PAGER[2], LAST]}
        for name, expected in hops.items():
            drive = steps(pages[name])
            start = drive.index(f"assertstatus:{FADE}|end@5")
            walk = [s.split("@")[0][len("assertfocus:"):] for s in drive[start:] if s.startswith("assertfocus:")]
            self.assertEqual(walk, expected, name)

    def test_windows_ui_runs_every_page_at_100_and_225_percent_text(self):
        runs = covered(END_JOURNEY.name)
        for page in load(END_JOURNEY):
            for size, mode in (("compact", "normal"), ("medium", "normal"), ("compact", "text-225")):
                self.assertIn((page, size, mode), runs)


STATES_JOURNEY = JOURNEYS / "a11y-song-board-states.json"
LONG_NAME = "Fixture Player With An Extraordinarily Long Display Name That Never Fits"
DESERT_WINDOW_TEXT = "#3D3D3D"


class SongBoardStatesJourneyTests(unittest.TestCase):
    """``journeys/a11y-song-board-states.json`` (issue #511): the song board states #197 changed."""

    def test_every_step_parses(self):
        for page in load(STATES_JOURNEY).values():
            for step in steps(page):
                uiwin.parse_step(step)

    def test_pages_and_their_modes(self):
        """The plate only exists under a contrast theme and the tool tip only while the marquee is stopped."""
        pages = load(STATES_JOURNEY)
        self.assertEqual(set(pages), {"song-board-pinned-own-id", "song-board-empty-total",
                                      "song-board-contrast-plate", "song-board-name-tooltip"})
        self.assertNotIn("modes", pages["song-board-pinned-own-id"])
        self.assertNotIn("modes", pages["song-board-empty-total"])
        self.assertEqual(["hc-desert"], pages["song-board-contrast-plate"]["modes"])
        self.assertEqual(["app-reduced"], pages["song-board-name-tooltip"]["modes"])
        self.assertEqual(["leaderboards_fixture.py", "--long-name"], pages["song-board-name-tooltip"]["fixture"])
        for page in pages.values():
            self.assertTrue(page["profile"].startswith("fixture-player-1:"), page["name"])

    def test_pinned_row_is_its_own_element(self):
        drive = steps(load(STATES_JOURNEY)["song-board-pinned-own-id"])
        row1 = f"{BOARD}.row.fixture-player-1"
        self.assertIn(f"assertapart:{row1}|{PINNED}", drive)
        self.assertTrue(any(s.startswith(f"assertread:{row1}|~^Your rank, 1st\\. Fixture Player 1") for s in drive))
        self.assertTrue(any(s.startswith(f"assertread:{PINNED}|~^Your rank, 1st\\. Open your statistics") for s in drive))
        self.assertIn(f"assertorder:{BOARD}.song|{row1}|{BOARD}.row.fixture-player-2|{PINNED}", drive)

    def test_empty_board_names_no_total(self):
        page = load(STATES_JOURNEY)["song-board-empty-total"]
        self.assertTrue(page["route"].endswith("/Solo_Bass"))
        drive = steps(page)
        for step in (f"assertread:{BOARD}.song|Fixture Pulse, Synthetic Quartet, Bass, button, Opens Song Details",
                     f"waitgone:{BOARD}.total@2", f"assertstate:{BOARD}.title|heading=1",
                     f"assertsize:{BOARD}.song|40x40", f"assertorder:{BOARD}.song|{BOARD}.empty",
                     f"waitgone:{BOARD}.page-info@2", f"waitgone:{PINNED}@2"):
            self.assertIn(step, drive)

    def test_contrast_plate_keeps_row_text_out_of_the_footer(self):
        drive = steps(load(STATES_JOURNEY)["song-board-contrast-plate"])
        scroll = drive.index(f"scrollto:{BOARD}.list,50")
        hard = drive.index(f"assertstatus:{FADE}|hard-edge@5")
        paints = [i for i, s in enumerate(drive) if s.startswith("assertpaint:") and f"!={DESERT_WINDOW_TEXT}" in s]
        self.assertLess(scroll, hard)
        self.assertEqual(3, len(paints))
        self.assertTrue(all(hard < i for i in paints))
        self.assertEqual({PAGER[0], PAGER[3], PINNED}, {drive[i].split("|")[0][len("assertpaint:"):] for i in paints})

    def test_trimmed_name_shows_its_tool_tip_on_keyboard_focus(self):
        drive = steps(load(STATES_JOURNEY)["song-board-name-tooltip"])
        self.assertEqual([s for s in drive if s.startswith(("invoke:", "click"))], [])
        sequence = [f"focus:{BOARD}.row.fixture-player-1", "key:down",
                    f"assertfocus:{BOARD}.row.fixture-player-2@3", "waitfor:class=ToolTip@6",
                    f"assertread:class=ToolTip|{LONG_NAME}, tool tip", "key:down",
                    f"assertfocus:{BOARD}.row.fixture-player-3@3", "waitgone:class=ToolTip@5"]
        start = 0
        for step in sequence:  # in this order; drive.index raises if a step is missing or out of order
            start = drive.index(step, start) + 1
        self.assertEqual(drive[-2:], [f"focus:{BOARD}.song", "waitgone:class=ToolTip@5"])

    def test_windows_ui_runs_each_page_in_its_modes(self):
        runs = covered(STATES_JOURNEY.name)
        for page in ("song-board-pinned-own-id", "song-board-empty-total"):
            for size, mode in (("compact", "normal"), ("medium", "normal"), ("compact", "text-225")):
                self.assertIn((page, size, mode), runs)
        for size in ("compact", "medium"):
            self.assertIn(("song-board-contrast-plate", size, "hc-desert"), runs)
        self.assertIn(("song-board-name-tooltip", "medium", "app-reduced"), runs)
        self.assertFalse([run for run in ui_ci.RUNS if run.name.startswith("a11y-song-board-states")],
                         "the explicit runs cover the file; no generated duplicates")


if __name__ == "__main__":
    unittest.main()
