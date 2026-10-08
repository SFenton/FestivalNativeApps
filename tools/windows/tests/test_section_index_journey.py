"""Songs Jump index accessibility pages: ``journeys/a11y-section-index.json`` (issues #48, #248, #415).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ui_ci  # noqa: E402  (sibling module)
import uiwin  # noqa: E402  (sibling module)

JOURNEY = Path(__file__).resolve().parents[1] / "journeys" / "a11y-section-index.json"
HEADER = "id=fst.songs.section-header"
#: "Rhythm Signal", the third of four R rows in the large catalogue. Placing it 8 epx below the list top (not a scroll
#: percent, which lands on Q at some window sizes and scales) keeps R's title above the viewport and S's two rows below,
#: so the bar names R whatever the window size, display scale or text size.
R_ROW = "id=fst.songs.row.fixture-song-75"


def load() -> dict[str, dict]:
    """The journey's pages by name."""
    return {page["name"]: page for page in json.loads(JOURNEY.read_text(encoding="utf-8"))}


def steps(page: dict) -> list[str]:
    """Every step the matrix drives for a page, in order."""
    return [*page.get("setup", []), *page.get("ready", []), *page.get("after_ready", []), *page.get("teardown", [])]


class SectionIndexJourneyTests(unittest.TestCase):
    """The pages parse and keep the #48 backward-pick regression checks."""

    def test_every_step_parses(self):
        for page in load().values():
            for step in steps(page):
                uiwin.parse_step(step)

    def test_live_pages_need_no_fixture(self):
        """#248's live pages stay runnable with ``--live`` (no fixture wrapper or fixture player)."""
        pages = load()
        for name in ("index-open", "index-far-jumps", "index-far-scroll", "index-keyboard"):
            self.assertNotIn("fixture", pages[name])
            self.assertFalse(str(pages[name].get("profile", "")).startswith("fixture-"))

    def test_backward_pick_after_scroll_names_the_picked_section(self):
        """#48: Jump to P, scroll down to R, then pick B. The pinned header must name B (it kept the old letter) and
        stay a Level 2 heading read between Jump and the list, by pointer and by keyboard."""
        pages = load()
        for name in ("index-backward-after-scroll", "index-backward-after-scroll-keyboard"):
            page = pages[name]
            self.assertIn("--large-catalogue", page.get("fixture", []), name)
            drive = steps(page)
            order = [f"assertname:{HEADER}|P", f"scrollinto:{R_ROW}@5", f"scrollinset:{R_ROW}|id=fst.songs.list|8",
                     f"assertname:{HEADER}|R",
                     "assertfocus:name=R@5", f"assertname:{HEADER}|B", f"assertread:{HEADER}|B, text",
                     f"assertstate:{HEADER}|heading=2"]
            positions = [drive.index(step) for step in order]
            self.assertEqual(positions, sorted(positions), name)

    def test_pointer_page_checks_name_target_size_and_reading_order(self):
        drive = steps(load()["index-backward-after-scroll"])
        self.assertIn("assertsize:id=fst.songs.section-index-button|40x40", drive)
        # Jump collapses to its glyph at compact; the icon-only button keeps its accessible name.
        self.assertIn("assertname:id=fst.songs.section-index-button|Jump to Section", drive)
        self.assertIn(f"assertorder:id=fst.songs.section-index-button|{HEADER}|id=fst.songs.list", drive)

    def test_keyboard_page_picks_with_keys_only(self):
        drive = steps(load()["index-backward-after-scroll-keyboard"])
        pick = drive[drive.index("assertfocus:name=R@5"):drive.index(f"assertname:{HEADER}|B")]
        self.assertEqual([s for s in pick if s.startswith(("invoke:", "click"))], [])
        self.assertIn("key:home", pick)
        self.assertIn("assertfocus:name=B@3", pick)

    def test_windows_ui_ci_runs_both_pages_at_225_percent_text(self):
        """#415 review: the ``windows-ui`` job (``ui_ci.RUNS``) runs both pages, Axe-scanned, at compact (Jump is
        icon-only) and medium (labelled), at 100% and 225% text."""
        covered = {(page, size, run.mode) for run in ui_ci.RUNS if run.pages == JOURNEY.name and run.scan
                   for page in (run.only.split(",") if run.only else load()) for size in run.sizes.split(",")}
        for page in ("index-backward-after-scroll", "index-backward-after-scroll-keyboard"):
            for size in ("compact", "medium"):
                for mode in ("normal", "text-225"):
                    self.assertIn((page, size, mode), covered)


if __name__ == "__main__":
    unittest.main()
