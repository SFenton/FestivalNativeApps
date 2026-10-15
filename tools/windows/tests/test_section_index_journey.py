"""Songs Jump index accessibility pages: ``journeys/a11y-section-index.json`` (issues #48, #231, #248, #415, #517, #648).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import a11y_matrix  # noqa: E402  (sibling module)
import ui_ci  # noqa: E402  (sibling module)
import uiwin  # noqa: E402  (sibling module)

JOURNEY = Path(__file__).resolve().parents[1] / "journeys" / "a11y-section-index.json"
HEADER = "id=fst.songs.section-header"
#: "Rhythm Signal", the third of four R rows in the large catalogue. Placing it 8 epx below the list top (not a scroll
#: percent, which lands on Q at some window sizes and scales) keeps R's title above the viewport and S's two rows below,
#: so the bar names R whatever the window size, display scale or text size.
R_ROW = "id=fst.songs.row.fixture-song-75"
JUMP = "id=fst.songs.section-index-button"
INDEX = "id=fst.songs.section-index"
SHOP_LABELS = ("Leaving Tomorrow", "In Shop", "Not In Shop")


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

    def assert_in_order(self, drive: list[str], order: list[str], msg: str = "") -> None:
        """Each step of ``order`` appears in ``drive``, in that order (searching after the previous match)."""
        at = -1
        for step in order:
            self.assertIn(step, drive[at + 1:], f"{msg}: {step}")
            at = drive.index(step, at + 1)

    def test_open_escape_page_covers_issue_231_focus_and_escape(self):
        """#231/#517: opening focuses the current label; Escape from the index and from Jump, and Ctrl+Minus's index,
        all close back to Jump; the hide/show path (no results) runs first."""
        page = load()["index-open-escape"]
        self.assertIn("--large-catalogue", page.get("fixture", []))
        drive = steps(page)
        close = ["key:esc", f"waitgone:{INDEX}@5", f"assertfocus:{JUMP}@3"]
        self.assert_in_order(drive, [
            "waitfor:name=No Results@10", f"waitgone:{JUMP}@5", f"waitfor:{JUMP}@5",
            f"assertsize:{JUMP}|40x40", f"focus:{JUMP}", "key:enter", "assertfocus:name=#@5",
            f"assertname:{INDEX}|Jump to section", f"assertstate:{INDEX}|type=list", *close,
            f"invoke:{JUMP}", f"focus:{JUMP}", *close,
            "key:ctrl+minus", "assertfocus:name=#@5", *close], "index-open-escape")

    def test_open_escape_page_checks_label_role_invoke_size_and_order(self):
        drive = steps(load()["index-open-escape"])
        self.assertIn("assertstate:name=M&class=GridViewItem|type=listitem", drive)
        self.assertIn("assertstate:name=M&class=GridViewItem|invoke=true", drive)
        self.assertIn("assertsize:name=M&class=GridViewItem|40x40", drive)
        self.assertIn("assertorder:name=#&class=GridViewItem|name=A&class=GridViewItem|name=M&class=GridViewItem"
                      "|name=Z&class=GridViewItem", drive)

    def test_shop_labels_page_catches_trimmed_cells(self):
        """#231: cells were sized from the first label, trimming wider ones. The page opens Jump under Title first (a
        one-letter first cell), then sorts Item Shop descending (narrower "Not In Shop" first), so every bucket label
        must keep at least 180 epx (about 192 measured; trimmed "Leaving Tomorrow" measured 133)."""
        page = load()["index-shop-labels"]
        self.assertEqual(page.get("profile", "").split(":")[0], "fixture-player-1")  # Item Shop sort needs a player
        self.assertNotIn("settings", page)  # the sort change is driven, not preloaded
        drive = steps(page)
        self.assert_in_order(drive, [
            f"invoke:{JUMP}", "waitfor:name=#&class=GridViewItem@5", "key:esc", "select:name=Item Shop@5",
            "select:id=fst.songs.sort.direction.descending", f"focus:{JUMP}", "key:enter", "key:home",
            "assertfocus:name=Not In Shop&class=GridViewItem@3", "key:esc", f"assertfocus:{JUMP}@3"], "index-shop-labels")
        for label in SHOP_LABELS:
            self.assertIn(f"assertsize:name={label}&class=GridViewItem|180x40", drive)

    def test_jump_pages_judge_the_show_hide_fade_trace(self):
        """#517 review (load-transition R6): UIA waits pass whether or not Jump fades, so the pages judge its
        ``fade-show``/``fade-hide`` trace: under ``app-reduced`` the hide and the return must not animate."""
        pages = load()
        self.assertEqual(pages["index-open-escape"].get("fade_trace"), {"JumpButton": ["show", "hide", "show"]})
        self.assertEqual(pages["index-shop-labels"].get("fade_trace"), {"JumpButton": ["show"]})
        self.assertFalse(a11y_matrix.mode_motion("app-reduced"))
        self.assertTrue(any(run.mode == "app-reduced" and run.pages == JOURNEY.name and "index-open-escape" in run.only
                            for run in ui_ci.RUNS))

    def test_jump_pages_judge_every_index_opening(self):
        """#648: UIA reads only the settled index, so the pages judge the ``jump-frame`` trace of every opening their
        drive performs: the index's letters must render once in place, not jump when the zoom-out settles."""
        pages = load()
        for name, opens in (("index-backward-after-scroll", 2), ("index-open-escape", 3), ("index-shop-labels", 2)):
            page = pages[name]
            self.assertEqual(page.get("jump_trace"), opens, name)
            self.assertTrue(a11y_matrix.traced(page), name)
            drive = steps(page)
            self.assertGreaterEqual(sum(s in (f"invoke:{JUMP}", "key:enter", "key:ctrl+minus") for s in drive), opens,
                                    name)

    def test_windows_ui_ci_runs_jump_pages_with_text_scaling_and_reduced_motion(self):
        """#517: the ``windows-ui`` job runs the #231 pages Axe-scanned at 100% (compact and medium), 225% text and
        with the app's Reduce Motion (Jump's fade off)."""
        covered = {(page, size, run.mode) for run in ui_ci.RUNS if run.pages == JOURNEY.name and run.scan
                   for page in (run.only.split(",") if run.only else load()) for size in run.sizes.split(",")}
        for page in ("index-open-escape", "index-shop-labels"):
            for cell in (("compact", "normal"), ("medium", "normal"), ("compact", "text-225"), ("medium", "app-reduced")):
                self.assertIn((page, *cell), covered)


if __name__ == "__main__":
    unittest.main()
