"""Song board pinned-row load gate pages: ``journeys/a11y-song-pinned-reveal.json`` (issues #295, #457).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import leaderboards_fixture as fixture  # noqa: E402  (sibling module)
import ui_ci  # noqa: E402  (sibling module)
import uiwin  # noqa: E402  (sibling module)

JOURNEYS = Path(__file__).resolve().parents[1] / "journeys"
JOURNEY = JOURNEYS / "a11y-song-pinned-reveal.json"
BOARD = "id=fst.song-leaderboard"
PINNED = f"{BOARD}.spotlight-footer"
ROW1 = f"{BOARD}.row.fixture-player-1"
NEXT = f"{BOARD}.page-next"
RING = "name=Busy Loading leaderboard"
PINNED_READ = f"assertread:{PINNED}|~^Your rank, 1st\\. Open your statistics\\. Fixture Player 1, .+, button$"
PAINT = f"assertpaint:{PINNED}|bg:L-6,M0|L40,T6!=@bg~20"
BOARD_PATH = "/api/leaderboard/fixture-pulse/Solo_Guitar"


def load() -> dict[str, dict]:
    """The journey's pages by name."""
    return {page["name"]: page for page in json.loads(JOURNEY.read_text(encoding="utf-8"))}


def steps(page: dict) -> list[str]:
    """Every step the matrix drives for a page, in order, without ``@`` timeouts."""
    every = [*page.get("setup", []), *page.get("ready", []), *page.get("after_ready", []), *page.get("teardown", [])]
    return [step.split("@")[0] if not step.startswith("assertpaint:") else step for step in every]


def covered() -> set[tuple[str, str, str]]:
    """``(page, size, mode)`` triples the Axe-scanned ``windows-ui`` runs drive, honouring each page's ``modes``."""
    pages = load()
    return {(name, size, run.mode) for run in ui_ci.RUNS if run.pages == JOURNEY.name and run.scan
            for name in (run.only.split(",") if run.only else pages)
            if run.mode in pages[name].get("modes", [run.mode]) for size in run.sizes.split(",")}


def in_order(test: unittest.TestCase, drive: list[str], sequence: list[str]) -> list[int]:
    """Assert ``sequence`` appears in ``drive`` in order (each step after the previous one); return the positions."""
    positions, start = [], 0
    for step in sequence:
        test.assertIn(step, drive[start:], sequence)
        start = drive.index(step, start) + 1
        positions.append(start - 1)
    return positions


class SlowSongBoardFixtureTests(unittest.TestCase):
    """``--slow-song-board`` delays only the chosen board's first page (and only leeway reads when asked)."""

    def test_first_page_of_a_chosen_board_is_slow(self):
        slow = {"fixture-pulse/Solo_Guitar"}
        self.assertTrue(fixture.slow_song_board(BOARD_PATH, {"top": ["25"], "offset": ["0"]}, slow))
        self.assertTrue(fixture.slow_song_board(BOARD_PATH, {"top": ["25"]}, slow))
        self.assertFalse(fixture.slow_song_board(BOARD_PATH, {"offset": ["25"]}, slow))
        self.assertFalse(fixture.slow_song_board("/api/leaderboard/fixture-pulse/Solo_Bass", {}, slow))
        self.assertFalse(fixture.slow_song_board("/api/leaderboard/fixture-pulse/all", {}, slow))
        self.assertFalse(fixture.slow_song_board(BOARD_PATH, {}, set()))

    def test_leeway_only_delays_only_filter_invalid_score_reloads(self):
        slow = {"fixture-pulse/Solo_Guitar"}
        self.assertFalse(fixture.slow_song_board(BOARD_PATH, {"offset": ["0"]}, slow, leeway_only=True))
        self.assertTrue(fixture.slow_song_board(BOARD_PATH, {"offset": ["0"], "leeway": ["1"]}, slow, leeway_only=True))
        self.assertFalse(fixture.slow_song_board(BOARD_PATH, {"offset": ["25"], "leeway": ["1"]}, slow, leeway_only=True))


class SongPinnedRevealJourneyTests(unittest.TestCase):
    """The pages parse, keep the #295 gate checks and run in ``windows-ui``."""

    def test_every_step_parses(self):
        for page in load().values():
            for step in [*page.get("ready", []), *page.get("after_ready", [])]:
                uiwin.parse_step(step)

    def test_pages_use_the_slow_board_fixture_and_a_selected_player(self):
        """Fixture only (no service calls from CI); the selected player's score index brings the pinned row."""
        for name, page in load().items():
            self.assertEqual(page["fixture"][:3], ["leaderboards_fixture.py", "--slow-song-board", "fixture-pulse/Solo_Guitar"],
                             name)
            self.assertTrue(page["profile"].startswith("fixture-player-1:"), name)
            self.assertEqual(page["route"], "/songs/fixture-pulse/Solo_Guitar", name)
        self.assertIn("--slow-leeway-only", load()["pinned-reveal-leeway-reload"]["fixture"])

    def test_first_load_exposes_only_the_ring_then_the_pinned_row_joins_the_rows(self):
        """#295: the pinned row isn't in UIA under the first-load ring; it reads, orders after the rows, keeps a
        40 epx target and its purple fill once the rows arrive."""
        drive = steps(load()["pinned-reveal-first-load"])
        in_order(self, drive, [f"waitfor:{RING}", f"waitgone:{PINNED}", f"waitgone:{ROW1}", f"waitgone:{NEXT}",
                               f"waitfor:{ROW1}", PINNED_READ, PAINT])
        order = next(s for s in drive if s.startswith("assertorder:"))
        self.assertEqual(order.split(":", 1)[1].split("|"),
                         [f"{BOARD}.song", ROW1, f"{BOARD}.row.fixture-player-2", PINNED, f"{BOARD}.page-first",
                          f"{BOARD}.page-info", NEXT])
        for step in (f"assertsize:{PINNED}|40x40", f"assertstate:{PINNED}|focusable=true",
                     f"assertstate:{PINNED}|invoke=true", f"assertapart:{PINNED}|{NEXT}"):
            self.assertIn(step, drive)

    def test_leeway_reload_drops_the_pinned_row_from_uia_and_tab_then_brings_it_back(self):
        """#295: a Filter Invalid Scores change gates the shown pinned row with the rows. While the slow reload runs,
        the pinned row leaves UIA and Tab goes from the header straight to Next; the header and pager stay. Without
        the gate the row stays exposed, so this page is the regression check (mutation-tested for #457)."""
        drive = steps(load()["pinned-reveal-leeway-reload"])
        toggle = "toggle:id=fst.settings.filter-invalid-scores"
        positions = in_order(self, drive, [
            PINNED_READ, "key:ctrl+comma", toggle, "key:ctrl+1", f"waitfor:{BOARD}.song", f"waitgone:{PINNED}",
            f"waitgone:{ROW1}", f"focus:{BOARD}.song", "key:tab", f"assertfocus:{NEXT}", f"waitfor:{ROW1}"])
        loading = drive[positions[5]:positions[-1]]
        self.assertIn(f"assertorder:{BOARD}.song|{RING}|{NEXT}", loading)
        self.assertTrue(any(s.startswith(f"assertread:{RING}|") for s in loading))
        loaded = drive[positions[-1]:]
        in_order(self, loaded, [PINNED_READ, f"assertorder:{ROW1}|{PINNED}|{NEXT}", PAINT])
        in_order(self, loaded, [f"focus:{BOARD}.song", "key:tab", f"assertfocus:{ROW1}", "key:tab",
                                f"assertfocus:{PINNED}"])

    def test_first_load_tab_walk_reaches_the_pinned_row_after_the_rows(self):
        drive = steps(load()["pinned-reveal-first-load"])
        walk = [s for s in drive if s.startswith(("focus:", "key:", "assertfocus:"))]
        self.assertEqual(walk[:9], [f"focus:{BOARD}.song", f"assertfocus:{BOARD}.song", "key:tab", f"assertfocus:{ROW1}",
                                    "key:tab", f"assertfocus:{PINNED}", "key:tab", f"assertfocus:{NEXT}", "key:shift+tab"])

    def test_reduced_motion_pages_see_the_pinned_row_arrive_still(self):
        pages = load()
        for name, mode in (("pinned-reveal-motion-reduced", "app-reduced"), ("pinned-reveal-motion-system", "no-animations")):
            self.assertEqual(pages[name]["modes"], [mode])
            drive = steps(pages[name])
            in_order(self, drive, [f"waitgone:{PINNED}", f"waitfor:{ROW1}", PINNED_READ, f"assertmotion:{PINNED}|still"])

    def test_windows_ui_runs_every_page_with_text_scaling_and_reduced_motion(self):
        runs = covered()
        for page in ("pinned-reveal-first-load", "pinned-reveal-leeway-reload"):
            for size, mode in (("compact", "normal"), ("medium", "normal"), ("compact", "text-225"),
                               ("medium", "app-reduced"), ("medium", "no-animations")):
                self.assertIn((page, size, mode), runs)
        self.assertIn(("pinned-reveal-motion-reduced", "medium", "app-reduced"), runs)
        self.assertIn(("pinned-reveal-motion-system", "medium", "no-animations"), runs)


if __name__ == "__main__":
    unittest.main()
