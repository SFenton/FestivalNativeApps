"""Navigation-bar and page-tool hit-target journey (``journeys/a11y-hit-targets.json``, issues #72 and #271).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import uiwin as u

_PAGES = json.loads((Path(__file__).resolve().parents[1] / "journeys" / "a11y-hit-targets.json")
                    .read_text(encoding="utf-8"))
_PRESS = json.loads((Path(__file__).resolve().parents[1] / "journeys" / "a11y-hit-targets-press.json")
                    .read_text(encoding="utf-8"))
_MIN_EPX = 40.0
_TOOLS = {
    "fst.global-search.open", "fst.shell.profile", "fst.shell.notifications", "fst.songs.sort", "fst.songs.filter",
    "fst.songs.section-index-button", "fst.suggestions.filter-button", "fst.rankings.rank-by-menu",
    "fst.full-rankings.instrument-menu", "fst.band-rankings.band-type-menu", "fst.band-rankings.rank-by-menu",
    "fst.song-detail.paths", "fst.song-detail.pinned-paths", "fst.history.sort.open", "fst.shop.sort",
    "fst.shop.filter", "fst.quick-links.open",
}
# Sized and probed, but never pressed: it opens the Item Shop in the external browser (Launcher), which a shared
# desktop run must not do.
_NOT_PRESSED = {"fst.song-detail.shop"}
# Live runs press Search only: the bell's flyout and the profile's Statistics view read player-scoped data, so they
# are pressed against the fixture (press-titlebar-transitions) instead.
_LIVE_PRESSED = {"fst.global-search.open"}
# The distinct result each press must assert next (first steps after the press), so a press that lands on the
# window or the title-bar drag region instead of the control fails.
_OUTCOMES = {
    "fst.global-search.open": ("waitfor:id=fst.global-search.field@", "assertfocus:name=Search songs and players@"),
    "fst.shell.profile": ("waitfor:id=fst.profile.search@", "waitfor:id=fst.player.name@"),
    "fst.shell.notifications": ("waitfor:id=fst.notifications.sheet@",),
    "fst.songs.sort": ("waitfor:id=fst.songs.sort.mode@",),
    "fst.songs.filter": ("waitfor:id=fst.songs.filter.reset@",),
    "fst.songs.section-index-button": ("waitfor:id=fst.songs.section-index@",),
    "fst.suggestions.filter-button": ("waitfor:id=fst.suggestions.filter.title@",),
    "fst.rankings.rank-by-menu": ("waitfor:id=fst.rankings.rank-by.",),
    "fst.full-rankings.instrument-menu": ("waitfor:id=fst.full-rankings.instrument.",),
    "fst.band-rankings.band-type-menu": ("waitfor:id=fst.band-rankings.band-type.",),
    "fst.band-rankings.rank-by-menu": ("waitfor:id=fst.band-rankings.rank-by.",),
    "fst.song-detail.paths": ("waitfor:id=fst.paths@",),
    "fst.song-detail.pinned-paths": ("waitfor:id=fst.paths@",),
    "fst.history.sort.open": ("waitfor:id=fst.history.sort.mode.",),
    "fst.shop.sort": ("waitfor:id=fst.shop.sort.mode@",),
    "fst.shop.filter": ("waitfor:id=fst.shop.filter.reset@",),
    "fst.rival-detail.view-profile": ("waitfor:id=fst.player@",),
    "fst.quick-links.open": ("waitfor:id=fst.quick-links.item.",),
}
_PRESSES = ("tapat", "clickat")
# Page tools with a ToolTip: Esc returns keyboard focus to them, which opens the tip, and WinUI always windows tooltips
# (open item 8 in windows-accessibility.md), so a press page whose last press is one of these ends focused elsewhere.
_TOOLTIP_TOOLS = {"fst.songs.section-index-button", "fst.quick-links.open"}


def _steps(page: dict) -> list[str]:
    """A page's ready and after-ready steps, in run order."""
    return [*page.get("ready", []), *page.get("after_ready", [])]


def _id(step: dict) -> str:
    return step["selector"]["value"] if step["selector"]["kind"] == "id" else ""


class HitTargetsJourneyTests(unittest.TestCase):
    """Every step parses, each tool is sized and probed off-glyph, and the matrix covers each window layout."""

    def test_steps_parse(self):
        for page in _PAGES:
            for step in _steps(page):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step)

    def test_sizes_meet_the_fluent_minimum(self):
        for page in _PAGES:
            for raw in _steps(page):
                if raw.startswith("assertsize:"):
                    step = u.parse_step(raw)
                    with self.subTest(page=page["name"], step=raw):
                        self.assertEqual(step["height"], _MIN_EPX)
                        self.assertIn(step["width"], (0.0, _MIN_EPX))

    def test_every_sized_tool_is_probed_above_and_below(self):
        for page in _PAGES:
            parsed = [u.parse_step(s) for s in _steps(page)]
            sized = {_id(s) for s in parsed if s["verb"] == "assertsize"}
            probes = {(_id(s), s["dy"]) for s in parsed if s["verb"] == "assertat"}
            for tool in sized:
                with self.subTest(page=page["name"], tool=tool):
                    self.assertIn((tool, -18.5), probes)
                    self.assertIn((tool, 18.5), probes)

    def test_covers_every_tool_and_layout(self):
        tools = {_id(u.parse_step(s)) for p in _PAGES for s in _steps(p) if s.startswith("assertsize:")}
        self.assertLessEqual(_TOOLS, tools)
        sizes = {size for p in _PAGES for size in p.get("sizes", [])}
        self.assertLessEqual({"compact", "medium", "wide", "maximized", "snap-left", "snap-right"}, sizes)

    def test_titlebar_transitions_recheck_after_each_resize(self):
        page = next(p for p in _PAGES if p["name"] == "hit-titlebar-transitions")
        steps = _steps(page)
        resizes = [i for i, s in enumerate(steps) if s.startswith("resize:")]
        self.assertGreaterEqual(len(resizes), 3)
        for index in resizes:
            with self.subTest(step=steps[index]):
                self.assertTrue(any(s.startswith("assertat:id=fst.global-search.open") for s in steps[index + 1:]))
        notifications = steps.index("waitfor:id=fst.shell.notifications@10")
        self.assertIn("assertat:id=fst.global-search.open|0,-18.5", steps[notifications:])

    def test_live_pages_need_no_fixture(self):
        live = {p["name"] for p in m.live_pages(_PAGES) if p["name"].endswith("-live")}
        self.assertEqual({p["name"] for p in _PAGES if p["name"].endswith("-live")}, live)
        for page in _PAGES:
            if page["name"].endswith("-live"):
                self.assertTrue(page["profile"].endswith(":SFentonX"), page["name"])


def _probes(page: dict, verbs: tuple[str, ...]) -> set[tuple[str, float, float]]:
    """(tool, dx, dy) of every offset step with one of ``verbs``."""
    parsed = [u.parse_step(s) for s in _steps(page)]
    return {(_id(s), s["dx"], s["dy"]) for s in parsed if s["verb"] in verbs}


def _press_page(hit: dict) -> dict:
    return next(p for p in _PRESS if p["name"] == "press-" + hit["name"].removeprefix("hit-"))


class HitTargetPressJourneyTests(unittest.TestCase):
    """``journeys/a11y-hit-targets-press.json`` sends a real press at every off-glyph probe and asserts its result."""

    def test_steps_parse(self):
        for page in _PRESS:
            for step in _steps(page):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step)

    def test_every_probe_is_also_pressed_at_the_same_sizes(self):
        for hit in _PAGES:
            if hit["name"] == "hit-song-detail-live":
                continue  # Paths and pinned Paths are pressed against the fixture (press-song-detail).
            press = _press_page(hit)
            pressed = _probes(press, ("tapat",))
            with self.subTest(page=hit["name"]):
                self.assertEqual(hit.get("sizes"), press.get("sizes"))
                self.assertEqual(hit.get("profile"), press.get("profile"))
            for tool, dx, dy in _probes(hit, ("assertat",)):
                if tool in _NOT_PRESSED or (hit["name"].endswith("-live") and tool not in _LIVE_PRESSED):
                    continue
                with self.subTest(page=hit["name"], tool=tool, dx=dx, dy=dy):
                    self.assertIn((tool, dx, dy), pressed)

    def test_every_sized_tool_is_pressed(self):
        sized = {_id(u.parse_step(s)) for p in _PAGES for s in _steps(p) if s.startswith("assertsize:")}
        pressed = {tool for p in _PRESS for tool, _, _ in _probes(p, _PRESSES)}
        self.assertEqual(sized - _NOT_PRESSED, pressed)
        self.assertLessEqual(_NOT_PRESSED, sized)

    def test_each_press_asserts_its_own_result_then_closes_it(self):
        for page in _PRESS:
            steps = _steps(page)
            for index, raw in enumerate(steps):
                step = u.parse_step(raw)
                if step["verb"] not in _PRESSES:
                    continue
                tool = _id(step)
                outcome = next(s for s in steps[index + 1:] if not s.startswith("wait:"))
                later = [i for i, s in enumerate(steps) if i > index and s.split(":", 1)[0] in _PRESSES]
                between = steps[index + 1:later[0] if later else len(steps)]
                with self.subTest(page=page["name"], step=raw):
                    self.assertTrue(outcome.startswith(_OUTCOMES[tool]), outcome)
                    if outcome.startswith("assertfocus:"):
                        # The press starts from verified focus elsewhere, so it cannot pass on stale focus.
                        self.assertTrue(steps[index - 1].startswith("assertfocus:id="), steps[index - 1])
                    else:
                        self.assertTrue(any(s.startswith(("key:escape", "key:alt+left", "select:id=fst.nav.")) for s in between), between)
                        self.assertTrue(any(s.startswith(("waitgone:", "waitfor:")) for s in between[1:]), between)

    def test_pages_ending_on_a_tooltip_tool_move_focus_off_it_before_the_scan(self):
        ended = set()
        for page in _PRESS:
            steps = _steps(page)
            pressed = [_id(u.parse_step(s)) for s in steps if s.split(":", 1)[0] in _PRESSES]
            if not pressed or pressed[-1] not in _TOOLTIP_TOOLS:
                continue
            ended.add(page["name"])
            focus, check = u.parse_step(steps[-2]), u.parse_step(steps[-1])
            with self.subTest(page=page["name"]):
                self.assertEqual(focus["verb"], "focus")
                self.assertEqual(check["verb"], "assertfocus")
                self.assertEqual(_id(focus), _id(check))
                self.assertNotIn(_id(focus), _TOOLTIP_TOOLS | _TOOLS)
        self.assertLessEqual({"press-songs", "press-quick-links-leaderboards", "press-quick-links-statistics"}, ended)

    def test_titlebar_presses_cover_touch_and_mouse(self):
        for name in ("press-titlebar-button", "press-titlebar-box", "press-titlebar-transitions"):
            page = next(p for p in _PRESS if p["name"] == name)
            for tool in ("fst.global-search.open", "fst.shell.profile"):
                with self.subTest(page=name, tool=tool):
                    self.assertTrue(any(t == tool for t, _, _ in _probes(page, ("tapat",))))
                    if name != "press-titlebar-transitions":
                        self.assertTrue(any(t == tool for t, _, _ in _probes(page, ("clickat",))))

    def test_titlebar_transitions_press_after_each_resize_and_once_the_bell_appears(self):
        page = next(p for p in _PRESS if p["name"] == "press-titlebar-transitions")
        steps = _steps(page)
        resizes = [i for i, s in enumerate(steps) if s.startswith("resize:")]
        self.assertGreaterEqual(len(resizes), 5)
        for position, index in enumerate(resizes):
            end = resizes[position + 1] if position + 1 < len(resizes) else len(steps)
            with self.subTest(step=steps[index]):
                self.assertTrue(any(s.startswith("tapat:id=fst.global-search.open") for s in steps[index + 1:end]))
        bell = steps.index("waitfor:id=fst.shell.notifications@10")
        after = [u.parse_step(s) for s in steps[bell:]]
        for tool in ("fst.global-search.open", "fst.shell.notifications", "fst.shell.profile"):
            with self.subTest(tool=tool):
                self.assertTrue(any(s["verb"] == "tapat" and _id(s) == tool for s in after))
        self.assertIn("waitfor:id=fst.player.name@15", steps[bell:])
        self.assertTrue(any(s.startswith("tapat:id=fst.shell.notifications") for s in steps[resizes[-1]:]))

    def test_live_press_page_presses_search_only(self):
        live = [p for p in _PRESS if p["name"].endswith("-live")]
        self.assertEqual([p["name"] for p in m.live_pages(live)], [p["name"] for p in live])
        for page in live:
            with self.subTest(page=page["name"]):
                self.assertEqual({t for t, _, _ in _probes(page, _PRESSES)}, _LIVE_PRESSED)

    def test_pattern_presses_swap_presses_for_patterns(self):
        steps = ["focus:id=a", "tapat:id=box|0,12", "wait:0.5", "assertfocus:name=Box@3",
                 "clickat:id=menu|0,-18.5", "waitfor:id=menu.item@5", "key:escape", "tapat:id=last|0,0"]
        self.assertEqual(m.pattern_presses(steps),
                         ["focus:id=a", "focus:id=box", "wait:0.5", "assertfocus:name=Box@3",
                          "invoke:id=menu", "waitfor:id=menu.item@5", "key:escape", "invoke:id=last"])
        for page in _PRESS:
            for raw in m.pattern_presses(_steps(page)):
                with self.subTest(page=page["name"], step=raw):
                    self.assertNotIn(u.parse_step(raw)["verb"], _PRESSES)


if __name__ == "__main__":
    unittest.main()
