"""Quick Links landing accessibility journey (``journeys/a11y-quick-links-landing.json``, issues #51 and #416).

Issue #51 made Quick Links land a section's top ``QuickLinks.LandingOffset`` (32 epx) below the page top and moved the
current-section line to the same 32 epx, on Settings and Leaderboards. These checks keep the a11y_matrix pages honest:
keyboard-only jumps, the "… section" announcement, a level-2 heading fully below the title bar and read before its
first control, focus moved into the section, the current section kept after the jump settles, 40x40 epx targets (the
launcher, every menu item the keyboard walks and every pane row), text 225% and Esc focus return.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import re
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import uiwin as u

_ROOT = Path(__file__).resolve().parents[3]
_PAGES = json.loads((_ROOT / "tools" / "windows" / "journeys" / "a11y-quick-links-landing.json")
                    .read_text(encoding="utf-8"))
_BY_NAME = {p["name"]: p for p in _PAGES}
_ITEM = "id=fst.quick-links.item."
# Core's landing line (#51) and FSTSectionHeaderStyle's top margin (Settings headings start 8 epx inside the anchor).
_LANDING = float(re.search(r"const double LandingOffset = (\d+(?:\.\d+)?);",
                           (_ROOT / "windows" / "Festival.Core" / "Domain" / "QuickLinks.cs")
                           .read_text(encoding="utf-8")).group(1))
_HEADER_MARGIN = 8.0
# Menu order: the first items of each page's Quick Links menu, in page order.
_SETTINGS_ORDER = ["app-settings", "item-shop", "show-instruments", "show-metadata", "accessibility"]
_LEADERBOARDS_ORDER = ["instrument:Solo_Guitar", "instrument:Solo_Bass", "instrument:Solo_Drums"]


def _steps(page: dict) -> list[str]:
    """A page's setup, ready and after-ready steps, in run order."""
    return [*page.get("setup", []), *page.get("ready", []), *page.get("after_ready", [])]


def _jump(steps: list[str], target: str) -> list[str]:
    """Steps from the menu's focus on ``target`` up to the next menu opening (or the end)."""
    start = steps.index(f"assertfocus:{_ITEM}{target}@3")
    rest = steps[start + 1:]
    end = next((i for i, s in enumerate(rest) if s == "scrollinto:id=fst.quick-links.open@5"), len(rest))
    return rest[:end]


class QuickLinksLandingA11yJourneyTests(unittest.TestCase):
    """The journey parses and covers what #51 changed on Settings and Leaderboards."""

    def test_every_step_parses(self):
        for page in _PAGES:
            for step in _steps(page):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step.replace("{stem}", "x"))

    def test_names_are_unique_and_fixture_only(self):
        self.assertEqual(len(_BY_NAME), len(_PAGES))
        self.assertEqual(set(_BY_NAME), {"qla-settings-menu", "qla-leaderboards-menu", "qla-leaderboards-pane"})
        # Fixture rows and the default fixture service (``"fixture": []``): never driven against the live service.
        self.assertTrue(all(p.get("fixture") == [] for p in _PAGES))
        self.assertEqual(m.live_pages(_PAGES), [])

    def test_menu_pages_run_at_225_percent_text_and_pane_only_scaled(self):
        for name in ("qla-settings-menu", "qla-leaderboards-menu"):
            with self.subTest(page=name):
                self.assertIn(name, [p["name"] for p in m.mode_pages(_PAGES, "text-225")])
                self.assertFalse({"wide", "maximized"} & set(_BY_NAME[name]["sizes"]))
        pane = _BY_NAME["qla-leaderboards-pane"]
        self.assertEqual(pane["sizes"], ["wide"])
        # The side pane needs >= 1150 epx: on a 300% host only display 100%/150% leaves room for it.
        self.assertNotIn(pane, m.mode_pages(_PAGES, "text-225"))
        self.assertIn(pane, m.mode_pages(_PAGES, "scale-150"))
        self.assertIn("waitgone:id=fst.quick-links.open@3", pane["ready"])

    def test_insets_follow_the_core_landing_offset(self):
        self.assertEqual(_LANDING, 32.0)
        expected = {"qla-settings-menu": _LANDING + _HEADER_MARGIN, "qla-leaderboards-menu": _LANDING,
                    "qla-leaderboards-pane": _LANDING}
        for name, inset in expected.items():
            insets = [float(s.rsplit("|", 1)[1]) for s in _steps(_BY_NAME[name]) if s.startswith("assertinset:")]
            with self.subTest(page=name):
                self.assertTrue(insets)
                self.assertEqual(set(insets), {inset})

    def test_menu_jumps_are_keyboard_only_and_land_accessibly(self):
        cases = (
            ("qla-settings-menu", _SETTINGS_ORDER, "show-instruments", "Show Instruments",
             "name=Show Instruments&class=TextBlock", "id=fst.settings.instrument.Solo_Guitar",
             "id=fst.settings.instrument.Solo_Guitar", "Quick Links"),
            ("qla-settings-menu", _SETTINGS_ORDER, "accessibility", "Accessibility",
             "name=Accessibility&class=TextBlock", "id=fst.settings.reduce-motion", "id=fst.settings.reduce-motion",
             "Quick Links"),
            # Every Leaderboards card has a fixture-player-1 row, so reading order pins the card's own button.
            ("qla-leaderboards-menu", _LEADERBOARDS_ORDER, "instrument:Solo_Drums", "Drums",
             "id=fst.leaderboards.card.Solo_Drums", "id=fst.rankings.row.fixture-player-1",
             "id=fst.leaderboards.card.Solo_Drums.view-all", "Leaderboards Quick Links"),
        )
        for name, order, target, title, heading, first, read_after, button in cases:
            with self.subTest(page=name, target=target):
                steps = _steps(_BY_NAME[name])
                # Enter opens on the first item; Down walks the page order to the target.
                opened = max(i for i, s in enumerate(steps[:steps.index(f"assertfocus:{_ITEM}{target}@3")])
                             if s == "key:enter")
                walk = steps[opened:steps.index(f"assertfocus:{_ITEM}{target}@3")]
                self.assertEqual(walk[0:2], ["key:enter", f"waitfor:{_ITEM}{target}@5"])
                self.assertEqual(walk[2], f"assertfocus:{_ITEM}{order[0]}@3")
                self.assertEqual(walk.count("key:down"), order.index(target))
                after = _jump(steps, target)
                self.assertEqual(after[0], "key:enter")
                self.assertIn(f"assertannounced:{title} section@5", after)
                self.assertIn(f"assertstate:{heading}|heading=2", after)
                self.assertIn(f"assertfocus:{first}@3", after)
                self.assertIn(f"assertorder:{heading}|{read_after}", after)
                # Still current once the jump settles (#51: the activation line moved to the landing line).
                current = f"assertstate:id=fst.quick-links.open|name={button}, current section {title}"
                self.assertLess(after.index(current + "@5"), after.index("wait:1"))
                self.assertLess(after.index("wait:1"), after.index(current))
                self.assertTrue([s for s in after if s.startswith("assertinset:")])

    def test_menu_target_size_scan_and_focus_return(self):
        for name in ("qla-settings-menu", "qla-leaderboards-menu"):
            steps = _steps(_BY_NAME[name])
            with self.subTest(page=name):
                self.assertIn("assertsize:id=fst.quick-links.open|40x40", steps)
                # Scanned before the menu first opens (WinUI's popup host lingers afterwards, open item 8).
                self.assertLess(steps.index("scan:{stem}-axe/closed"), steps.index("key:enter"))
                self.assertEqual(steps[-3], "key:esc")
                self.assertEqual(steps[-1], "assertfocus:id=fst.quick-links.open@3")

    def test_every_keyboard_walked_menu_item_is_a_40_epx_target(self):
        # Quick Links R6 / page-tools R10 (#416 review): every item the keyboard walks over or picks is measured at
        # 40x40 epx (both sides) while the menu is open, not only the launcher button.
        cases = (("qla-settings-menu", _SETTINGS_ORDER, ("show-instruments", "accessibility")),
                 ("qla-leaderboards-menu", _LEADERBOARDS_ORDER, ("instrument:Solo_Drums",)))
        for name, order, targets in cases:
            steps = _steps(_BY_NAME[name])
            for target in targets:
                with self.subTest(page=name, target=target):
                    end = steps.index(f"assertfocus:{_ITEM}{target}@3")
                    opened = max(i for i, s in enumerate(steps[:end]) if s == "key:enter")
                    # Measured while this opening's menu is up: after it opens, before the pick's Enter.
                    measured = {s for s in steps[opened:end] if s.startswith("assertsize:")}
                    walked = order[:order.index(target) + 1]
                    required = {f"assertsize:{_ITEM}{item}|40x40" for item in walked}
                    earlier = {s for s in steps[:opened] if s.startswith(f"assertsize:{_ITEM}")}
                    # Items already measured in an earlier opening of the same menu needn't be measured again.
                    self.assertFalse(required - measured - earlier, required - measured - earlier)
            sizes = [s for s in steps if s.startswith(f"assertsize:{_ITEM}")]
            with self.subTest(page=name):
                self.assertTrue(sizes)
                self.assertTrue(all(s.endswith("|40x40") for s in sizes), sizes)

    def test_pane_jump_is_keyboard_only_and_moves_selection(self):
        steps = _steps(_BY_NAME["qla-leaderboards-pane"])
        drums = _ITEM + "instrument:Solo_Drums"
        start = steps.index("focus:" + drums)
        self.assertEqual(steps[start + 1:start + 3], [f"assertfocus:{drums}@3", "key:enter"])
        after = steps[start:]
        self.assertIn("assertannounced:Drums section@5", after)
        self.assertIn("assertstate:id=fst.leaderboards.card.Solo_Drums|heading=2", after)
        self.assertIn("assertfocus:id=fst.rankings.row.fixture-player-1@3", after)
        self.assertLess(after.index(f"assertstate:{drums}|selected=true@5"), after.index("wait:1"))
        self.assertLess(after.index("wait:1"), after.index(f"assertstate:{drums}|selected=true"))
        self.assertIn(f"assertstate:{_ITEM}instrument:Solo_Guitar|selected=false", after)
        # Every pane row the keyboard can reach is a full 40x40 epx target (width too), measured before the jump.
        for item in _LEADERBOARDS_ORDER:
            with self.subTest(row=item):
                self.assertLess(steps.index(f"assertsize:{_ITEM}{item}|40x40"), start)
        self.assertFalse([s for s in steps if s.startswith("assertsize:") and not s.endswith("|40x40")])


if __name__ == "__main__":
    unittest.main()
