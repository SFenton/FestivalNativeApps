"""Quick Links jump accessibility journey (``journeys/a11y-quick-links-jump.json``, issues #46 and #414).

Issue #46 made player-profile Quick Links jumps (Bands, instruments) land and keep the chosen section current. These
checks keep the a11y_matrix page honest: keyboard-only jumps, page-order items, the current section's toggle/selection
state and name, the Narrator announcement, target size, and the landing inset.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import uiwin as u

_PAGES = json.loads((Path(__file__).resolve().parents[1] / "journeys" / "a11y-quick-links-jump.json")
                    .read_text(encoding="utf-8"))
_BY_NAME = {p["name"]: p for p in _PAGES}
_ITEM = "id=fst.quick-links.item."
# Profile sections in page order (fixture-player-1: every instrument visible, then Bands).
_ORDER = ["global", *(f"instrument:{i}" for i in ("Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals",
                                                   "Solo_PeripheralGuitar", "Solo_PeripheralBass",
                                                   "Solo_PeripheralVocals", "Solo_PeripheralCymbals",
                                                   "Solo_PeripheralDrums")), "bands"]


def _steps(page: dict) -> list[str]:
    """A page's setup, ready and after-ready steps, in run order."""
    return [*page.get("setup", []), *page.get("ready", []), *page.get("after_ready", [])]


def _below_chain(steps: list[str]) -> list[str]:
    """Item IDs from ``assertbelow`` steps over Quick Links items, top to bottom."""
    pairs = [s.removeprefix("assertbelow:").split("|") for s in steps
             if s.startswith("assertbelow:" + _ITEM)]
    chain = [pairs[0][1].removeprefix(_ITEM)] if pairs else []
    for lower, upper in pairs:
        if upper.removeprefix(_ITEM) != chain[-1]:
            break
        chain.append(lower.removeprefix(_ITEM))
    return chain


class QuickLinksJumpJourneyTests(unittest.TestCase):
    """The journey parses and covers what #46 changed on the menu and the pane."""

    def test_every_step_parses(self):
        for page in _PAGES:
            for step in _steps(page):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step.replace("{stem}", "x"))

    def test_names_are_unique_and_fixture_only(self):
        self.assertEqual(len(_BY_NAME), len(_PAGES))
        # A fixture player: never driven against the live service.
        self.assertEqual(m.live_pages(_PAGES), [])

    def test_menu_and_pane_sizes_do_not_overlap(self):
        menu, pane = _BY_NAME["qlj-profile-menu"], _BY_NAME["qlj-profile-pane"]
        self.assertFalse({"wide", "maximized"} & set(menu["sizes"]))
        self.assertEqual(set(pane["sizes"]), {"wide", "maximized"})
        self.assertIn("waitgone:id=fst.quick-links.open@3", pane["ready"])

    def test_menu_lists_sections_in_page_order(self):
        self.assertEqual(_below_chain(_steps(_BY_NAME["qlj-profile-menu"])), _ORDER)

    def test_pane_reads_sections_in_page_order(self):
        order = next(s for s in _steps(_BY_NAME["qlj-profile-pane"]) if s.startswith("assertorder:"))
        self.assertEqual([i.removeprefix(_ITEM) for i in order.removeprefix("assertorder:").split("|")], _ORDER)

    def test_menu_jumps_to_bands_by_keyboard_and_keeps_it_current(self):
        steps = _steps(_BY_NAME["qlj-profile-menu"])
        focus = [s.split("@")[0].removeprefix("assertfocus:") for s in steps if s.startswith("assertfocus:")]
        self.assertEqual(focus[:3], [_ITEM + "global", _ITEM + "instrument:Solo_Guitar", _ITEM + "bands"])
        # Down from Global walks every section once to Bands, then Enter jumps.
        first, last = steps.index("assertfocus:" + _ITEM + "global@3"), steps.index("assertfocus:" + _ITEM + "bands@3")
        self.assertEqual(steps[first:last].count("key:down"), len(_ORDER) - 1)
        self.assertEqual(steps[last + 1], "key:enter")
        after = steps[last:]
        current = "assertstate:id=fst.quick-links.open|name=Quick Links, current section Bands"
        self.assertIn("assertannounced:Bands section@5", after)
        # Still current after the jump settles (#46: re-aimed jumps lost the mark).
        self.assertLess(after.index(current + "@5"), after.index("wait:1"))
        self.assertLess(after.index("wait:1"), after.index(current))
        self.assertIn("assertinset:id=fst.player.bands-section|id=fst.player.available|32", after)

    def test_menu_marks_exactly_the_current_section(self):
        steps = _steps(_BY_NAME["qlj-profile-menu"])
        self.assertIn("assertstate:" + _ITEM + "global|toggle=on", steps)
        self.assertIn("assertstate:" + _ITEM + "global|name=Global Statistics, current section", steps)
        self.assertIn("assertstate:" + _ITEM + "bands|toggle=off", steps)
        self.assertIn("assertstate:" + _ITEM + "bands|name=Bands", steps)
        drums = "assertstate:id=fst.quick-links.open|name=Quick Links, current section Drums"
        self.assertIn(drums + "@5", steps)
        self.assertIn(drums, steps)
        self.assertIn("assertannounced:Drums section@5", steps)

    def test_menu_returns_focus_and_meets_target_size(self):
        steps = _steps(_BY_NAME["qlj-profile-menu"])
        self.assertEqual(steps[-4], "assertfocus:id=fst.quick-links.open@3")
        self.assertEqual(steps[-6], "key:esc")
        # Focus back on Quick Links opens its tooltip, which WinUI always windows (open item 8, #534), so the page ends
        # on a tile without one before the final scan.
        self.assertEqual(steps[-2:], ["focus:id=fst.player.stat.overview.songs-played",
                                      "assertfocus:id=fst.player.stat.overview.songs-played@3"])
        self.assertNotIn("axe_allow", _BY_NAME["qlj-profile-menu"])
        self.assertIn("assertsize:id=fst.quick-links.open|40x40", steps)
        # The page is scanned before the menu first opens (WinUI's popup host lingers afterwards, open item 8).
        self.assertLess(steps.index("scan:{stem}-axe/closed"), steps.index("key:enter"))

    def test_pane_jumps_by_keyboard_and_moves_selection(self):
        steps = _steps(_BY_NAME["qlj-profile-pane"])
        for target, other in (("bands", "global"), ("instrument:Solo_Drums", "bands")):
            with self.subTest(target=target):
                start = steps.index("focus:" + _ITEM + target)
                self.assertEqual(steps[start + 2], "key:enter")
                after = steps[start:]
                self.assertIn("assertstate:" + _ITEM + target + "|selected=true@5", after)
                self.assertIn("assertstate:" + _ITEM + target + "|selected=true", after)
                self.assertIn("assertstate:" + _ITEM + other + "|selected=false", after)
        self.assertIn("assertsize:" + _ITEM + "bands|0x40", steps)
        # The pane marks the current row with UIA selection, so names carry no ", current section" suffix.
        self.assertFalse([s for s in steps if "current section" in s])


if __name__ == "__main__":
    unittest.main()
