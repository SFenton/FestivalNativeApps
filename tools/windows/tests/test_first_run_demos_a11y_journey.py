"""First-run demo accessibility journey (``journeys/a11y-first-run-demos.json``, issues #57 and #420).

Issue #57 made every first-run song demo show real catalogue songs (Songs, Statistics' "Highest and Lowest Rank
Breakdown", Item Shop) and muted redacted placeholders while the catalogue loads or is unavailable. These checks keep
the a11y_matrix page honest: both data states on each changed demo, the demo kept out of the UIA control view (Narrator
reads the slide, never placeholder bars or song names), the slide's name/role/state, reading order, keyboard operation,
Tab containment, Axe, and the demo frame clear of the slide title at large text sizes. Issue #420 found the dialog body
clipped (pips and description cut off) at 200-225% text in a short window: the order checks now scroll the pips into
view in the carousel's own body scroller, and Tab to the pips must bring them on screen.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import re
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import uiwin as u

_REPO = Path(__file__).resolve().parents[3]
_PAGES = json.loads((_REPO / "tools" / "windows" / "journeys" / "a11y-first-run-demos.json").read_text(encoding="utf-8"))
_BY_NAME = {p["name"]: p for p in _PAGES}
# Demo slide → slide title (FirstRunCatalog.cs) for the song demos #57 changed.
_DEMOS = {"songs": ("songs-song-list", "Song List"),
          "top-songs": ("statistics-top-songs", "Highest and Lowest Rank Breakdown"),
          "shop": ("shop-overview", "Item Shop")}
_STATES = ("placeholder", "catalogue")


def _steps(page: dict) -> list[str]:
    """A page's setup, ready, after-ready and teardown steps, in run order."""
    return [*page.get("setup", []), *page.get("ready", []), *page.get("after_ready", []), *page.get("teardown", [])]


def _slide(title: str) -> str:
    """The selected FlipView item's selector for a slide title."""
    return f"name={title}&class=FlipViewItem"


class FirstRunDemosA11yJourneyTests(unittest.TestCase):
    """The journey parses and covers what #57 changed in the first-run demos."""

    def test_every_step_parses(self):
        for page in _PAGES:
            for step in m.page_steps(page, "medium", Path("out"), "", True, 0):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step)

    def test_slide_titles_match_the_catalogue(self):
        catalog = (_REPO / "windows" / "Festival.Core" / "Domain" / "FirstRunCatalog.cs").read_text(encoding="utf-8")
        for slide, title in _DEMOS.values():
            with self.subTest(slide=slide):
                self.assertRegex(catalog, rf'new\("{re.escape(slide)}", \d+, "{re.escape(title)}"')

    def test_every_changed_demo_has_both_data_states(self):
        self.assertEqual(set(_BY_NAME), {f"frd-{demo}-{state}" for demo in _DEMOS for state in _STATES})
        for demo, (slide, _) in _DEMOS.items():
            for state in _STATES:
                with self.subTest(demo=demo, state=state):
                    page = _BY_NAME[f"frd-{demo}-{state}"]
                    # Prefix match: rotating demos append their rotation and pulse tokens (issues #258, #277).
                    self.assertIn(f"assertstatus:id=fst.first-run.demo.{slide}|~^{state}( |$)",
                                  [s.rsplit("@", 1)[0] for s in _steps(page)])
                    # The catalogue being down is a fixture-only state; the catalogue pages also run live.
                    self.assertEqual(page.get("fixture"), ["--songs-unavailable"] if state == "placeholder" else None)
        self.assertEqual(m.live_pages(_PAGES), [p for p in _PAGES if p["name"].endswith("-catalogue")])

    def test_demo_stays_decorative_and_the_slide_reads_by_title(self):
        for name, page in _BY_NAME.items():
            demo = name.removeprefix("frd-").rsplit("-", 1)[0]
            slide, title = _DEMOS[demo]
            with self.subTest(page=name):
                steps = _steps(page)
                # Raw view only: an id= selector searches the control view, so the demo must not be found there.
                self.assertIn(f"waitgone:id=fst.first-run.demo.{slide}@1", steps)
                self.assertIn(f"assertread:{_slide(title)}|{title}, list item, selected", steps)
                order = next(s for s in steps if s.startswith(f"assertorder:{_slide(title)}|"))
                self.assertEqual(order.removeprefix("assertorder:").split("|"),
                                 [_slide(title), "id=fst.first-run.pips", "id=PrimaryButton", "id=SecondaryButton",
                                  "id=fst.first-run.close"])
                # Checked after the data state settles, not before.
                status = next(i for i, s in enumerate(steps) if s.startswith(f"assertstatus:id=fst.first-run.demo.{slide}|"))
                self.assertLess(status, steps.index(f"waitgone:id=fst.first-run.demo.{slide}@1"))

    def test_order_is_checked_with_the_pips_scrolled_into_view(self):
        # Issue #420: at 200-225% text in a short window the body scrolls (fst.first-run.body; ContentDialog's own
        # scroller never does), so the pips sit below the fold until scrolled to. The title/demo check runs first,
        # while the slide is still at the top.
        for name, page in _BY_NAME.items():
            with self.subTest(page=name):
                steps = page["after_ready"]
                scroll = steps.index("scrollinto:id=fst.first-run.pips")
                self.assertTrue(steps[scroll + 1].startswith("assertorder:"))
                for i, step in enumerate(steps):
                    if step.startswith("assertapart:"):
                        self.assertLess(i, scroll)
        xaml = (_REPO / "windows" / "Festival.App" / "Controls" / "FirstRunCarousel.xaml").read_text(encoding="utf-8")
        self.assertRegex(xaml, r'<ScrollViewer x:Name="Body"[^>]*VerticalScrollBarVisibility="Auto"[^>]*'
                               r'AutomationId="fst.first-run.body"')
        self.assertIn('GotFocus="OnPipsGotFocus"', xaml)

    def test_tab_to_the_pips_brings_them_on_screen(self):
        # Issue #420: before the fix Tab focused "Page 1" below the fold at 225% text in the compact window.
        steps = _BY_NAME["frd-songs-placeholder"]["after_ready"]
        tab = steps.index("key:tab")
        self.assertEqual(steps[tab - 1], f"focus:{_slide('Song List')}")
        self.assertEqual(steps[tab + 1:tab + 3], ["assertfocus:name=Page 1&class=Button@3",
                                                  "assertorder:name=Page 1&class=Button|id=PrimaryButton"])
        self.assertLess(tab, steps.index("scrollinto:id=fst.first-run.pips"))

    def test_axe_and_tab_containment_on_every_page(self):
        for page in _PAGES:
            with self.subTest(page=page["name"]):
                self.assertTrue(page.get("scan"))
                # Keyboard-driven replays assert focus explicitly instead of a Tab walk.
                self.assertTrue(page.get("tabs") or any(s.startswith("assertfocus:") for s in _steps(page)))

    def test_demo_frame_clears_the_slide_title(self):
        # Text scaling: the demo fits its frame (FirstRunDemoFit) and never runs into the title, run with --mode text-225.
        for demo in ("songs", "top-songs"):
            slide, title = _DEMOS[demo]
            for state in _STATES:
                with self.subTest(demo=demo, state=state):
                    self.assertIn(f"assertapart:raw=fst.first-run.demo.{slide}|name={title}&class=TextBlock",
                                  _steps(_BY_NAME[f"frd-{demo}-{state}"]))

    def test_keyboard_reaches_the_top_songs_demo_and_returns_focus(self):
        for state in _STATES:
            with self.subTest(state=state):
                steps = _steps(_BY_NAME[f"frd-top-songs-{state}"])
                opened = steps.index("key:enter")
                self.assertEqual(steps[opened - 1], "focus:id=fst.settings.first-run.statistics")
                self.assertIn("assertfocus:name=Select Player Profile&class=FlipViewItem@5", steps)
                # Enter invokes the default Next through all five slides until it reads Done.
                done = steps.index("assertstate:id=PrimaryButton|name=Done")
                self.assertEqual(steps[opened:done].count("key:enter"), 6)
                self.assertEqual(steps[-3:], ["key:esc", "waitgone:id=fst.first-run.dialog@5",
                                              "assertfocus:id=fst.settings.first-run.statistics@3"])

    def test_keyboard_pages_on_while_placeholders_show(self):
        steps = _steps(_BY_NAME["frd-songs-placeholder"])
        start = steps.index("assertfocus:name=Song List&class=FlipViewItem@3")
        self.assertEqual(steps[start + 1], "key:enter")
        after = steps[start:]
        self.assertIn("assertstatus:id=fst.first-run.demo.songs-sort|~^placeholder( |$)@5", after)
        self.assertIn("waitgone:id=fst.first-run.demo.songs-sort@1", after)
        self.assertEqual(after[-2:], ["key:esc", "waitgone:id=fst.first-run.dialog@5"])


if __name__ == "__main__":
    unittest.main()
