"""Player profile title-row journey (``journeys/a11y-profile-title.json``, issues #97, #285 and #446).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import uiwin as u

_PAGES = json.loads((Path(__file__).resolve().parents[1] / "journeys" / "a11y-profile-title.json")
                    .read_text(encoding="utf-8"))
_BY_NAME = {p["name"]: p for p in _PAGES}
_SFENTONX = "195e93ef108143b2975ee46662d4d0e1"
# Every reachable title-row identity state: Switch (another player selected), Select (none selected), Deselect (the
# selected player), the paused-selection notice (no action) and the live views.
_STATES = {"pt-switch": "fst.player.select", "pt-anonymous": "fst.player.select", "pt-selected": "fst.player.deselect",
           "pt-notice": "fst.player.identity-notice", "pt-live-anonymous": "fst.player.select",
           "pt-live-selected": "fst.player.deselect"}


def _steps(page: dict) -> list[str]:
    """A page's ready and after-ready steps, in run order."""
    return [*page.get("ready", []), *page.get("after_ready", [])]


class ProfileTitleJourneyTests(unittest.TestCase):
    """The journey file stays parseable and covers every title-row state, with no card and the H1 first."""

    def test_every_step_parses(self):
        for page in _PAGES:
            for step in _steps(page):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step.replace("{stem}", "x"))

    def test_names_are_unique(self):
        self.assertEqual(len(_BY_NAME), len(_PAGES))

    def test_each_state_orders_name_then_action_then_overview(self):
        for name, action in _STATES.items():
            with self.subTest(page=name):
                order = next(s for s in _steps(_BY_NAME[name]) if s.startswith("assertorder:"))
                ids = order.removeprefix("assertorder:").split("|")
                self.assertEqual(ids[0], "id=fst.player.name")
                self.assertEqual(ids[1], "id=" + action)
                self.assertIn("id=fst.player.overview", ids[2:])
                self.assertIn("assertinset:id=fst.player.name|id=fst.player.available|12", _steps(_BY_NAME[name]))

    def test_each_state_checks_the_title_is_a_plain_heading_without_avatar(self):
        # Issue #446 (#97): the name is a plain, non-focusable Level 1 heading with no PersonPicture card, and the
        # row's action keeps the 40 epx minimum height.
        for name, action in _STATES.items():
            with self.subTest(page=name):
                steps = _steps(_BY_NAME[name])
                for check in ("heading=1", "type=text", "focusable=false"):
                    self.assertIn(f"assertstate:id=fst.player.name|{check}", steps)
                self.assertIn("waitgone:class=PersonPicture@1", steps)
                title = next(s for s in steps if s.startswith("assertname:id=fst.player.name|")).split("|", 1)[1]
                self.assertIn(f"assertread:id=fst.player.name|{title}, text", steps)
                if action != "fst.player.identity-notice":
                    self.assertIn(f"assertsize:id={action}|0x40", steps)

    def test_actions_wrap_only_at_large_text(self):
        row, wrap = _BY_NAME["pt-actions-row"], _BY_NAME["pt-actions-wrap"]
        self.assertEqual(m.mode_pages([row], "text-225"), [])
        self.assertEqual(m.mode_pages([row], "normal"), [row])
        self.assertEqual(m.mode_pages([wrap], "normal"), [])
        self.assertEqual(m.mode_pages([wrap], "hc-desert+text-225"), [wrap])
        self.assertIn("assertlevel:id=fst.quick-links.open|id=fst.player.select", _steps(row))
        self.assertIn("assertbelow:id=fst.quick-links.open|id=fst.player.select", _steps(wrap))
        # The Quick Links menu yields to the side pane at wide widths, so it is only asserted where it shows.
        for page in (row, wrap):
            self.assertNotIn("wide", page["sizes"])
            self.assertNotIn("maximized", page["sizes"])

    def test_keyboard_pages_walk_title_actions_in_order(self):
        for name, action in (("pt-keyboard-switch", "fst.player.select"),
                             ("pt-keyboard-selected", "fst.player.deselect")):
            with self.subTest(page=name):
                focus = [s.split("@")[0].removeprefix("assertfocus:id=") for s in _steps(_BY_NAME[name])
                         if s.startswith("assertfocus:")]
                self.assertEqual(focus[:3], [action, "fst.quick-links.open", "fst.player.stat.overview.songs-played"])
                # Each dialog or menu opened from the row hands focus back to the button that opened it.
                self.assertEqual(focus[-1], action)
                self.assertEqual(_BY_NAME[name]["tabs"], 0)

    def test_live_pages_use_the_public_player_only(self):
        live = [p["name"] for p in m.live_pages(_PAGES) if p["name"].startswith("pt-live")]
        self.assertEqual(live, ["pt-live-anonymous", "pt-live-selected"])
        self.assertNotIn("pt-notice", [p["name"] for p in m.live_pages(_PAGES)])
        self.assertIn(_SFENTONX, _BY_NAME["pt-live-anonymous"]["route"])
        self.assertTrue(_BY_NAME["pt-live-selected"]["profile"].startswith(_SFENTONX + ":"))


if __name__ == "__main__":
    unittest.main()
