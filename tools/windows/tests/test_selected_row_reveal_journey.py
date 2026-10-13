"""Selected-row reveal pages: ``journeys/a11y-selected-row-reveal.json`` (issues #323, #470).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ui_ci  # noqa: E402  (sibling module)
import uiwin  # noqa: E402  (sibling module)

JOURNEY = Path(__file__).resolve().parents[1] / "journeys" / "a11y-selected-row-reveal.json"
SONG = "id=fst.song-leaderboard"
SONG_ROW = f"{SONG}.row.fixture-player-17"
SONG_PINNED = f"{SONG}.spotlight-footer"
PREVIEW = "id=fst.song-detail.preview-row.Solo_Guitar.fixture-player-17"
RANK_ROW = "id=fst.rankings.row.fixture-rank-60"
RANK_PINNED = "id=fst.full-rankings.spotlight-footer"
CARD = "id=fst.leaderboards.card.Solo_Guitar.spotlight"
# (page, entry control, revealed row, pinned row, rows above/below, pager control after the pinned row)
REVEALS = (
    ("reveal-song-score", PREVIEW, SONG_ROW, SONG_PINNED,
     (f"{SONG}.row.fixture-player-16", f"{SONG}.row.fixture-player-18"), f"{SONG}.page-next"),
    ("reveal-full-rankings-card", CARD, RANK_ROW, RANK_PINNED,
     ("id=fst.rankings.row.fixture-rank-59", "id=fst.rankings.row.fixture-rank-61"), "id=fst.full-rankings.page-first"),
)
STILL = {"reveal-song-score-still": (PREVIEW, SONG_ROW, SONG_PINNED),
         "reveal-full-rankings-still": (CARD, RANK_ROW, RANK_PINNED)}


def load() -> dict[str, dict]:
    """The journey's pages by name."""
    return {page["name"]: page for page in json.loads(JOURNEY.read_text(encoding="utf-8"))}


def steps(page: dict) -> list[str]:
    """Every step the matrix drives for a page, in order, without ``@`` timeouts."""
    every = [*page.get("ready", []), *page.get("after_ready", [])]
    return [step.split("@")[0] if not step.startswith("assertpaint:") else step for step in every]


def covered() -> set[tuple[str, str, str]]:
    """``(page, size, mode)`` triples the ``windows-ui`` runs drive, honouring each page's ``modes``."""
    pages = load()
    return {(name, size, run.mode) for run in ui_ci.RUNS if run.pages == JOURNEY.name
            for name in (run.only.split(",") if run.only else pages)
            if run.mode in pages[name].get("modes", [run.mode]) for size in run.sizes.split(",")}


def in_order(test: unittest.TestCase, drive: list[str], sequence: list[str]) -> None:
    """Assert ``sequence`` appears in ``drive`` in order."""
    start = 0
    for step in sequence:
        test.assertIn(step, drive[start:], sequence)
        start = drive.index(step, start) + 1


class SelectedRowRevealJourneyTests(unittest.TestCase):
    """The pages parse, keep the #323 reveal checks and run in ``windows-ui`` with text scaling and motion off."""

    def test_every_step_parses(self):
        for page in load().values():
            for step in [*page.get("ready", []), *page.get("after_ready", [])]:
                uiwin.parse_step(step)

    def test_pages_are_fixture_only_with_a_selected_player(self):
        """No service calls from CI; the selected player's rank drives the reveal."""
        for name, page in load().items():
            self.assertEqual(page["fixture"], ["fade_fixture.py", "--large-rankings"], name)
            self.assertEqual(page["tabs"], 0, name)
            song = page["route"] == "/songs/fixture-pulse"
            self.assertTrue(page["profile"].startswith("fixture-player-17:" if song else "fixture-rank-60:"), name)

    def test_keyboard_reveal_names_paints_and_keeps_the_row_clear_and_in_order(self):
        pages = load()
        for name, entry, row, pinned, (above, below), pager in REVEALS:
            drive = steps(pages[name])
            in_order(self, drive, [f"focus:{entry}", f"assertfocus:{entry}", "key:enter", f"waitfor:{row}", "wait:1"])
            self.assertTrue(any(s.startswith(f"assertread:{entry}|~^") for s in drive), name)
            self.assertIn(f"assertsize:{entry}|0x40", drive)
            self.assertIn(f"assertsize:{row}|0x40", drive)
            self.assertIn(f"assertapart:{row}|{pinned}", drive)
            self.assertIn(f"assertorder:{above}|{row}|{below}|{pinned}|{pager}", drive)
            self.assertIn(f"assertpaint:{row}|above:L40,T-20|L40,T6!=@above~20", drive)
            self.assertTrue(any(s.startswith(f"assertread:{row}|~^Your rank, ") for s in drive), name)
            in_order(self, drive, [f"assertmotion:{row}|still", f"focus:{row}", "key:down",
                                   f"assertfocus:{below}", "key:up", f"assertfocus:{row}",
                                   "key:tab", f"assertfocus:{pinned}", "key:tab", f"assertfocus:{pager}",
                                   "key:shift+tab", f"assertfocus:{pinned}"])

    def test_motion_off_pages_reach_the_row_and_see_it_still(self):
        """#470: with motion off the reveal must still land on the row (it used to scroll before the rows existed)."""
        pages = load()
        for name, (entry, row, pinned) in STILL.items():
            page = pages[name]
            self.assertEqual(page["modes"], ["app-reduced", "no-animations"], name)
            drive = steps(page)
            in_order(self, drive, [f"focus:{entry}", "key:enter", f"waitfor:{row}", f"assertapart:{row}|{pinned}",
                                   f"assertmotion:{row}|still"])
            self.assertTrue(any(s.startswith(f"assertorder:") and f"|{row}|" in s for s in drive), name)

    def test_windows_ui_runs_every_page_with_text_scaling_and_motion_off(self):
        runs = covered()
        for name, *_ in REVEALS:
            for size, mode in (("compact", "normal"), ("medium", "normal"), ("compact", "text-225"),
                               ("medium", "app-reduced"), ("medium", "no-animations")):
                self.assertIn((name, size, mode), runs)
        for name in STILL:
            for mode in ("app-reduced", "no-animations"):
                self.assertIn((name, "medium", mode), runs)


if __name__ == "__main__":
    unittest.main()
