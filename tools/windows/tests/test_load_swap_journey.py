"""Load-swap accessibility pages (``journeys/a11y-load-swap.json``, issue #431).

Issue #71 (PR #67) gave every Windows board the web's load swap (``LoadSwap`` + ``LoadSwapVisual``, load-transition
R1-R4, R6): the stale rows leave, one labelled ProgressRing shows while the next page loads, and the header, selectors
and pager stay usable. These pages pin what that swap exposes to Narrator and the keyboard on each surface #71 changed:
the spinner's name and role, rows absent from UIA under it, reading order header → spinner → pager, controls enabled
and 40 epx, keyboard focus kept on the pager button pressed (Previous once Next disables on the last page), the new rows
readable after the swap, Axe clean at first load and after it, plus 225% text and the swap with Reduce Motion or
system animations off. Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import uiwin as u

_PAGES = json.loads((Path(__file__).resolve().parents[1] / "journeys" / "a11y-load-swap.json")
                    .read_text(encoding="utf-8"))
_BY_NAME = {p["name"]: p for p in _PAGES}

# Board page → (spinner name, ID prefix of the pager, stale first-page row, settled page-2 row).
_BOARDS = {
    "load-swap-full-rankings": ("Busy Loading rankings", "fst.full-rankings",
                                "fst.rankings.row.fixture-player-1", "fst.rankings.row.fixture-rank-26"),
    "load-swap-band-rankings": ("Busy Loading rankings", "fst.band-rankings",
                                "fst.band-rankings.row.fixture-team-1", "fst.band-rankings.row.fixture-team-26"),
    "load-swap-song-leaderboard": ("Busy Loading leaderboard", "fst.song-leaderboard",
                                   "fst.song-leaderboard.row.fixture-player-1",
                                   "fst.song-leaderboard.row.fixture-player-26"),
    "load-swap-song-band-leaderboard": ("Busy Loading band scores", "fst.song-band-leaderboard",
                                        "fst.song-band-leaderboard.row.fixture-band-1:1",
                                        "fst.song-band-leaderboard.row.fixture-band-26:26"),
    "load-swap-player-bands": ("Busy Loading bands", "fst.player-bands",
                               "fst.player-bands.row.fixture-band-1", "fst.player-bands.row.fixture-pband-trio-8"),
}


def _steps(page: dict) -> list[str]:
    """A page's ready and after-ready steps, in run order."""
    return [*page.get("ready", []), *page.get("after_ready", [])]


def _index(steps: list[str], prefix: str) -> int:
    """Index of the first step starting with ``prefix``."""
    return next(i for i, st in enumerate(steps) if st.startswith(prefix))


class LoadSwapJourneyTests(unittest.TestCase):
    """The pages parse and cover every surface and requirement #431 asks for."""

    def test_every_step_parses_and_names_are_unique(self):
        self.assertEqual(len(_BY_NAME), len(_PAGES))
        for page in _PAGES:
            for step in _steps(page):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step.replace("{stem}", "x"))

    def test_every_board_reads_the_spinner_and_hides_stale_rows_during_the_reload(self):
        for name, (spinner, prefix, stale, settled) in _BOARDS.items():
            with self.subTest(page=name):
                page = _BY_NAME[name]
                self.assertTrue(page["scan"])
                self.assertEqual(page["modes"], ["normal"])
                steps = page["after_ready"]
                press = _index(steps, f"invoke:id={prefix}.page-next")
                shown = steps.index(f"waitfor:name={spinner}@3", press)
                self.assertGreater(steps.index(f"waitgone:id={stale}@3"), shown)
                gone = steps.index(f"waitgone:name={spinner}@5", shown)
                # Controls stay outside the gate, usable and 40 epx while the next page loads (R4).
                between = steps[shown:gone]
                self.assertTrue(any(st.startswith(f"assertsize:id={prefix}.page-") and st.endswith("|40x40")
                                    for st in between))
                self.assertTrue(any(st.startswith("assertorder:") and f"|name={spinner}|" in st for st in between))
                self.assertTrue(any(st.startswith("assertstate:") and st.endswith("|enabled=true") for st in between))
                after = steps[gone:]
                self.assertTrue(any(st.startswith(f"assertname:id={prefix}.page-info|Page 2 of ") for st in after))
                self.assertTrue(any(st.startswith(f"assertread:id={settled}|") for st in after))
                self.assertTrue(any(st.startswith(f"assertfocus:id={prefix}.page-") for st in after))
                # The page-level Axe scan runs after the journey; a focused pager button's tooltip opens a PopupHost
                # that Axe flags (windows-accessibility.md, open issue 8), so the journey ends on a row.
                self.assertEqual(steps[-2], f"focus:id={settled}")

    def test_spinner_is_named_and_read_at_first_load(self):
        for name, (spinner, _, _, _) in _BOARDS.items():
            if name == "load-swap-song-leaderboard":
                continue  # the plain mock answers page 1 at once; its later pages take 3 s
            with self.subTest(page=name):
                ready = _BY_NAME[name]["ready"]
                self.assertIn(f"assertread:name={spinner}|{spinner}, ProgressRing", ready)
                # WinUI's ProgressRing briefly exposes its AnimatedVisualPlayer as a non-control Image while it starts
                # (Axe IsControlElementTrueRequired; windows-accessibility.md open issue 10), so the scan settles first
                # and the fixture holds the read long enough (6 s) for the spinner to still be up.
                scan = ready.index("scan:{stem}-loading")
                self.assertEqual(ready[scan - 1], "wait:1")
                self.assertEqual(_BY_NAME[name]["fixture"][-1], "6")
        reload = _BY_NAME["load-swap-song-leaderboard"]["after_ready"]
        self.assertIn("assertread:name=Busy Loading leaderboard|Busy Loading leaderboard, ProgressRing", reload)
        self.assertIn("assertread:id=fst.song-leaderboard.song|Fixture Pulse, button, Opens Song Details", reload)

    def test_focus_stays_on_the_pressed_button(self):
        for name in ("load-swap-full-rankings", "load-swap-band-rankings", "load-swap-song-leaderboard",
                     "load-swap-song-band-leaderboard"):
            prefix = _BOARDS[name][1]
            self.assertIn(f"assertfocus:id={prefix}.page-next", _BY_NAME[name]["after_ready"], name)
        # Next disables on the last page and hands focus to Previous so keyboard paging can continue.
        bands = _BY_NAME["load-swap-player-bands"]["after_ready"]
        self.assertLess(bands.index("assertstate:id=fst.player-bands.page-next|enabled=false"),
                        bands.index("assertfocus:id=fst.player-bands.page-previous"))

    def test_overview_metric_reload_shows_the_gate(self):
        steps = _BY_NAME["load-swap-leaderboards"]["after_ready"]
        pick = steps.index("toggle:id=fst.rankings.rank-by.fcrate")
        self.assertGreater(steps.index("waitfor:name=Busy Loading leaderboards@3"), pick)
        self.assertIn("waitgone:id=fst.leaderboards.card.Solo_Guitar@3", steps)
        self.assertIn("assertread:name=Busy Loading leaderboards|Busy Loading leaderboards, ProgressRing", steps)
        self.assertIn("assertstate:id=fst.rankings.rank-by-menu|enabled=true", steps)
        self.assertIn("assertname:id=fst.rankings.rank-by-menu|Rank by: FC Rate", steps)

    def test_text_pages_run_only_at_large_text(self):
        for name in ("load-swap-full-rankings-text", "load-swap-song-band-leaderboard-text"):
            with self.subTest(page=name):
                page = _BY_NAME[name]
                self.assertEqual(m.mode_pages([page], "normal"), [])
                self.assertEqual(m.mode_pages([page], "text-225"), [page])
                steps = _steps(page)
                self.assertTrue(any(st.startswith("assertapart:name=Busy Loading ") for st in steps))
                self.assertTrue(any(st.endswith(".page-next|40x40") for st in steps))
                self.assertTrue(any(st.endswith(".page-next") and st.startswith("assertfocus:") for st in steps))

    def test_motion_pages_swap_without_animation(self):
        reduced = _BY_NAME["load-swap-full-rankings-motion-reduced"]
        self.assertTrue(reduced["settings"]["reduceMotion"])
        self.assertEqual(m.mode_pages([reduced], "normal"), [reduced])
        system = _BY_NAME["load-swap-full-rankings-motion-system"]
        self.assertEqual(m.mode_pages([system], "normal"), [])
        self.assertEqual(m.mode_pages([system], "no-animations"), [system])
        for page in (reduced, system):
            with self.subTest(page=page["name"]):
                steps = page["after_ready"]
                self.assertIn("assertread:name=Busy Loading rankings|Busy Loading rankings, ProgressRing", steps)
                self.assertIn("waitgone:id=fst.rankings.row.fixture-player-1@3", steps)
                self.assertIn("assertfocus:id=fst.full-rankings.page-next", steps)

    def test_fixture_pages_stay_off_live_runs(self):
        self.assertTrue(all(p.get("fixture") for p in _PAGES))
        self.assertEqual(m.live_pages(_PAGES), [])


if __name__ == "__main__":
    unittest.main()
