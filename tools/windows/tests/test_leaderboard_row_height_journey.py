"""Leaderboard row height and reading-order accessibility pages: ``journeys/a11y-leaderboard-row-height.json``
(issues #90, #440).

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
JOURNEY = JOURNEYS / "a11y-leaderboard-row-height.json"
CARD = "fst.leaderboards.card.Solo_PeripheralGuitar"
BAND_CARD = "fst.leaderboards.band-card.Band_Duets"
#: Rows (and pinned rows) each page must measure at the shared 48 epx ``LeaderboardRowMetrics.MinHeight``.
ROWS = {
    "row-height-overview-skeleton": ["id=fst.rankings.row.fixture-player-1", "id=fst.rankings.row.fixture-player-2",
                                     f"raw={CARD}.skeleton.0", f"raw={CARD}.skeleton.1"],
    "row-height-overview-band-skeleton": [f"raw={BAND_CARD}.skeleton.0", "id=fst.band-rankings.row.fixture-team-1",
                                          "id=fst.band-rankings.row.fixture-team-2"],
    "row-height-full-rankings": ["id=fst.rankings.row.fixture-player-1", "id=fst.rankings.row.fixture-player-2",
                                 "id=fst.full-rankings.spotlight-footer"],
    "row-height-band-rankings": ["id=fst.band-rankings.row.fixture-team-1", "id=fst.band-rankings.row.fixture-team-2"],
    "row-height-song-board": ["id=fst.song-leaderboard.row.fixture-player-1", "id=fst.song-leaderboard.row.fixture-player-2",
                              "id=fst.song-leaderboard.spotlight-footer"],
    "row-height-song-preview": ["id=fst.song-detail.preview-row.Solo_Guitar.fixture-player-1",
                                "id=fst.song-detail.preview-row.Solo_Guitar.fixture-player-2"],
}


def load() -> dict[str, dict]:
    """The journey's pages by name."""
    return {page["name"]: page for page in json.loads(JOURNEY.read_text(encoding="utf-8"))}


def steps(page: dict) -> list[str]:
    """Every step the matrix drives for a page, in order."""
    return [*page.get("setup", []), *page.get("ready", []), *page.get("after_ready", []), *page.get("teardown", [])]


def order(step: str) -> list[str]:
    """The selectors an ``assertorder:`` step expects, in reading order."""
    return step.split(":", 1)[1].split("|")


class LeaderboardRowHeightJourneyTests(unittest.TestCase):
    """The pages parse, keep the #90 row checks and run in ``windows-ui``."""

    def test_every_step_parses(self):
        for page in load().values():
            for step in steps(page):
                uiwin.parse_step(step)

    def test_every_board_row_is_a_48_epx_row(self):
        """#90: every leaderboard surface draws the same row, at least ``LeaderboardRowMetrics.MinHeight`` tall."""
        pages = load()
        self.assertEqual(sorted(pages), sorted(ROWS))
        for name, rows in ROWS.items():
            drive = steps(pages[name])
            for row in rows:
                self.assertIn(f"assertsize:{row}|0x48", drive, name)

    def test_placeholders_match_the_loaded_pitch_and_stay_out_of_the_control_view(self):
        """#90: a loading card's placeholder rows sit at the loaded rows' pitch, so the card keeps its height, and
        they are raw-view only (no invisible text or tab stops for Narrator) until the loaded rows replace them."""
        drive = steps(load()["row-height-overview-skeleton"])
        mark = drive.index("markspan:id=fst.rankings.row.fixture-player-1|id=fst.rankings.row.fixture-player-2|pitch")
        span = drive.index(f"assertspan:raw={CARD}.skeleton.0|raw={CARD}.skeleton.1|pitch")
        self.assertLess(mark, span)
        for i in (0, 1):
            self.assertIn(f"waitgone:id={CARD}.skeleton.{i}@1", drive)
        loading, loaded = [s for s in drive if s.startswith("assertorder:")]
        self.assertEqual(order(loading), [f"id={CARD}", "id=fst.leaderboards.card.Solo_PeripheralBass"])
        # #455: at 225% text the compact loading card fills the window, so the order is read in the medium window.
        self.assertLess(drive.index("resize:medium"), drive.index(loading))
        self.assertLess(span, drive.index("resize:medium"))
        self.assertEqual(order(loaded), [f"id={CARD}", f"id={CARD}.view-all", "id=fst.leaderboards.card.Solo_PeripheralBass"])
        self.assertLess(drive.index(f"waitgone:raw={CARD}.skeleton.0@5"), drive.index(loaded))

        band = steps(load()["row-height-overview-band-skeleton"])
        mark = band.index(f"markspan:raw={BAND_CARD}.skeleton.0|raw={BAND_CARD}.skeleton.1|pitch")
        done = band.index(f"waitgone:raw={BAND_CARD}.skeleton.0@5")
        span = band.index("assertspan:id=fst.band-rankings.row.fixture-team-1|id=fst.band-rankings.row.fixture-team-2|pitch")
        self.assertLess(mark, done)
        self.assertLess(done, span)
        self.assertIn(f"waitgone:id={BAND_CARD}.skeleton.0@1", band[:mark])

    def test_rows_read_as_one_button_in_visual_order(self):
        pages = load()
        reads = [s for page in pages.values() for s in steps(page) if s.startswith("assertread:")]
        self.assertIn("assertread:id=fst.rankings.row.fixture-player-2|Rank #2, Fixture Player 2. Total Score 88,000,000, "
                      "38 / 50 songs, button", reads)
        self.assertTrue(all(s.endswith(", button") for s in reads))
        for name, page in pages.items():
            self.assertTrue(any(s.startswith("assertorder:") for s in steps(page)), name)

    def test_scans_end_on_a_pinned_scroll_position(self):
        """testing/windows.md: a scrolled overview page pins its final position, so no row is clipped at the
        viewport edge in the Axe scan (the 225% text failures this page hit before the pins)."""
        for name, target in (("row-height-overview-skeleton", f"id={CARD}"),
                             ("row-height-overview-band-skeleton", "id=fst.band-rankings.row.fixture-team-2")):
            drive = steps(load()[name])
            last = max(i for i, s in enumerate(drive) if s.startswith("scrollinset:"))
            self.assertTrue(drive[last].startswith(f"scrollinset:{target}|id=fst.leaderboards|"), name)
            self.assertFalse(any(s.startswith(("scroll", "toggle", "invoke")) for s in drive[last + 1:]), name)

    def test_windows_ui_runs_every_page_at_100_and_225_percent_text(self):
        every = load()
        runs = {(page, size, run.mode) for run in ui_ci.RUNS if run.pages == JOURNEY.name and run.scan
                for page in (run.only.split(",") if run.only else every) for size in run.sizes.split(",")}
        for page in every:
            for size, mode in (("compact", "normal"), ("medium", "normal"), ("compact", "text-225")):
                self.assertIn((page, size, mode), runs)


if __name__ == "__main__":
    unittest.main()
