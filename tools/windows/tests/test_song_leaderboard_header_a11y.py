"""Song leaderboard header accessibility pages: ``journeys/a11y-song-leaderboard-header.json`` (issues #317, #465).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ui_ci  # noqa: E402  (sibling module)
import uiwin  # noqa: E402  (sibling module)

JOURNEY = Path(__file__).resolve().parents[1] / "journeys" / "a11y-song-leaderboard-header.json"
BAND = "id=fst.song-band-leaderboard"
SOLO = "id=fst.song-leaderboard"
HELP = ", button, Opens Song Details"


def load() -> dict[str, dict]:
    """The journey's pages by name."""
    return {page["name"]: page for page in json.loads(JOURNEY.read_text(encoding="utf-8"))}


def steps(page: dict) -> list[str]:
    """Every step the matrix drives for a page, in order."""
    return [*page.get("setup", []), *page.get("ready", []), *page.get("after_ready", []), *page.get("teardown", [])]


def order(drive: list[str]) -> list[list[str]]:
    """Each ``assertorder`` step's selectors."""
    return [s.split(":", 1)[1].split("|") for s in drive if s.startswith("assertorder:")]


class SongLeaderboardHeaderJourneyTests(unittest.TestCase):
    """The pages parse, keep the #317/#465 checks and run in ``windows-ui``."""

    def test_every_step_parses(self):
        for page in load().values():
            for step in steps(page):
                uiwin.parse_step(step)

    def test_pages_are_fixture_only_without_a_selected_player(self):
        """No service calls from CI and no selected-profile header; the band pages turn on the entry totals."""
        pages = load()
        self.assertEqual(sorted(pages), ["song-band-header", "song-band-header-switch", "song-band-header-unresolved",
                                         "song-solo-header"])
        for name, page in pages.items():
            self.assertNotIn("profile", page, name)
            self.assertTrue(page["route"].startswith("/songs/"), name)
        for name in ("song-band-header", "song-band-header-switch"):
            self.assertIn("--song-band-totals", pages[name]["fixture"])

    def test_header_is_one_target_named_by_every_visible_line(self):
        """#465: Narrator reads the header button as one item, so its name carries title, artist, board and total
        (web role=link named by its content); it is a focusable, invokable 40+ epx button and the title is heading 1."""
        for name, prefix, lines in (("song-band-header", BAND, "Fixture Pulse, Synthetic Quartet, Duos, 29 Duos entries"),
                                    ("song-solo-header", SOLO, "Fixture Pulse, Synthetic Quartet, Lead, 26 Lead entries")):
            drive = steps(load()[name])
            self.assertIn(f"assertread:{prefix}.song|{lines}{HELP}", drive)
            for state in ("type=button", "focusable=true"):
                self.assertIn(f"assertstate:{prefix}.song|{state}", drive)
            self.assertIn(f"assertstate:{prefix}.title|heading=1", drive)
            self.assertIn(f"assertsize:{prefix}.song|40x40", drive)
            self.assertEqual(order(drive)[0][0], f"{prefix}.song", name)
            self.assertEqual(drive[-3:], [f"focus:{prefix}.song", "key:enter", "waitfor:id=fst.song-detail.title@10"])
        band = steps(load()["song-band-header"])
        self.assertEqual(order(band)[0], [f"{BAND}.song", f"{BAND}.band-type-menu", f"{BAND}.row.fixture-band-1:1"])
        self.assertIn(f"assertread:{BAND}.band-type.Band_Duets|Duos, SelectorBarItem, selected", band)

    def test_keyboard_walks_header_switcher_and_rows(self):
        drive = steps(load()["song-band-header"])
        walk = [s.split("@")[0] for s in drive if s.startswith(("focus:", "key:", "assertfocus:"))]
        duos, row = f"{BAND}.band-type.Band_Duets", f"{BAND}.row.fixture-band-1:1"
        self.assertEqual(walk[:10], [f"focus:{BAND}.song", f"assertfocus:{BAND}.song", "key:tab", f"assertfocus:{duos}",
                                     "key:tab", f"assertfocus:{row}", "key:shift+tab", f"assertfocus:{duos}",
                                     "key:shift+tab", f"assertfocus:{BAND}.song"])

    def test_size_switch_renames_the_header_without_the_old_total_while_loading(self):
        """#317 review: the old size's total must not outlive the switch, in the header's name or its total line."""
        page = load()["song-band-header-switch"]
        self.assertEqual(page["fixture"][-2:], ["--song-band-slow", "Band_Trios"])
        drive = steps(page)
        right = drive.index("key:right")
        renamed = drive.index(f"assertread:{BAND}.song|Fixture Pulse, Synthetic Quartet, Trios{HELP}@2")
        landed = drive.index(f"waitfor:{BAND}.empty@10")
        self.assertLess(right, renamed)
        self.assertLess(renamed, landed)
        self.assertIn(f"waitgone:{BAND}.total@1", drive[renamed:landed])
        self.assertIn([f"{BAND}.song", f"{BAND}.band-type-menu", "name=Busy Loading band scores"], order(drive[renamed:landed]))
        self.assertIn("key:shift+tab", drive[renamed:landed])
        self.assertIn(f"assertread:{BAND}.song|Fixture Pulse, Synthetic Quartet, Trios{HELP}", drive[landed:])

    def test_unresolved_song_has_no_header_button(self):
        drive = steps(load()["song-band-header-unresolved"])
        self.assertEqual(load()["song-band-header-unresolved"]["route"], "/songs/missing-song/bands/Band_Trios")
        self.assertIn(f"waitgone:{BAND}.song@1", drive)
        self.assertIn(f"assertread:{BAND}.subtitle|Trios, text", drive)
        self.assertFalse(any(s.startswith(f"assertfocus:{BAND}.song") for s in drive))

    def test_windows_ui_runs_every_page_at_two_sizes_and_225_percent_text(self):
        runs = {(page, size, run.mode) for run in ui_ci.RUNS if run.pages == JOURNEY.name and run.scan
                for page in (run.only.split(",") if run.only else load()) for size in run.sizes.split(",")}
        for page in load():
            for size, mode in (("compact", "normal"), ("medium", "normal"), ("compact", "text-225")):
                self.assertIn((page, size, mode), runs)


if __name__ == "__main__":
    unittest.main()
