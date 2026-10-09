"""Item Shop list-row accessibility pages (``journeys/a11y-shop-list-row.json``, issue #397).

The Shop list reuses the shared Songs ``SongRowCard`` (tracker #18, PR #45). These pages pin what that row exposes:
names, roles and state, reading order, the 44 epx cart target, text scaling, the marquee/pulse under Reduce Motion
and system "Animation effects" off, and the card's opaque, bordered fallback (surface-materials R4) with Windows
transparency effects off and the in-app Less Transparency / Increase Contrast settings. Run:
``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import uiwin as u

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import shop_fixture as s  # noqa: E402  (sibling tool)

_PAGES = json.loads((Path(__file__).resolve().parents[1] / "journeys" / "a11y-shop-list-row.json")
                    .read_text(encoding="utf-8"))
_BY_NAME = {p["name"]: p for p in _PAGES}
_ROWS = ("fixture-orbit", "fixture-pulse")


def _steps(page: dict) -> list[str]:
    """A page's ready and after-ready steps, in run order."""
    return [*page.get("ready", []), *page.get("after_ready", [])]


class ShopListRowJourneyTests(unittest.TestCase):
    """The pages parse, show the list (never compact) and cover every row requirement #397 asks for."""

    def test_every_step_parses(self):
        for page in _PAGES:
            for step in _steps(page):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step.replace("{stem}", "x"))

    def test_names_are_unique_and_pages_show_the_list(self):
        self.assertEqual(len(_BY_NAME), len(_PAGES))
        for page in _PAGES:
            with self.subTest(page=page["name"]):
                self.assertEqual(page["route"], "/shop")
                self.assertEqual(page["settings"]["shopViewMode"], "List")
                # Compact windows always show the grid, so a list page there would test tiles instead.
                self.assertNotIn("compact", page["sizes"])

    def test_read_page_covers_labels_order_and_targets(self):
        steps = _steps(_BY_NAME["shop-row-read"])
        self.assertTrue(_BY_NAME["shop-row-read"]["scan"])
        for row in _ROWS:
            self.assertTrue(any(st.startswith(f"assertread:id=fst.shop.song.{row}|") and st.endswith(", list item")
                                for st in steps), row)
            self.assertTrue(any(st.startswith(f"assertread:id=fst.shop.external.{row}|")
                                and st.endswith(", Open Official Item Shop, button") for st in steps), row)
        self.assertIn("assertstate:id=fst.shop.song.fixture-orbit|invoke=true", steps)
        self.assertIn("assertorder:id=fst.shop.view-toggle|id=fst.shop.song.fixture-orbit|id=fst.shop.song.fixture-pulse",
                      steps)
        self.assertIn("assertsize:id=fst.shop.external.fixture-orbit|40x40", steps)
        self.assertEqual(sum(st.startswith("assertat:id=fst.shop.external.fixture-orbit|") for st in steps), 4)

    def test_text_page_runs_only_at_large_text(self):
        page = _BY_NAME["shop-row-text"]
        self.assertEqual(m.mode_pages([page], "normal"), [])
        for mode in ("text-150", "text-200", "text-225", "hc-desert+text-225"):
            self.assertEqual(m.mode_pages([page], mode), [page], mode)
        self.assertIn("assertsize:id=fst.shop.external.fixture-orbit|40x40", _steps(page))
        # The long title stays one marquee line at every large text size (two lines at 150% are ~52 epx).
        marquee = _BY_NAME["shop-row-text-marquee"]
        self.assertEqual(m.mode_pages([marquee], "normal"), [])
        self.assertEqual(m.mode_pages([marquee], "text-225"), [marquee])
        self.assertIn(f"assertmarquee:name={s.LONG_TITLE}|moving|48", _steps(marquee))

    def test_motion_pages_scroll_or_hold(self):
        title = f"name={s.LONG_TITLE}"
        moving = _steps(_BY_NAME["shop-row-motion"])
        self.assertTrue(any(st.startswith(f"assertmarquee:{title}|moving|") for st in moving))
        self.assertIn("assertmotion:id=fst.shop.song.fixture-orbit|moving", moving)
        self.assertNotIn("reduceMotion", _BY_NAME["shop-row-motion"]["settings"])
        self.assertTrue(_BY_NAME["shop-row-motion-reduced"]["settings"]["reduceMotion"])
        for name in ("shop-row-motion-reduced", "shop-row-motion-system"):
            with self.subTest(page=name):
                steps = _steps(_BY_NAME[name])
                self.assertTrue(any(st.startswith(f"assertmarquee:{title}|static|") for st in steps))
                for row in _ROWS:
                    self.assertIn(f"assertmotion:id=fst.shop.song.{row}|still", steps)
        for name in ("shop-row-text-marquee", "shop-row-motion", "shop-row-motion-reduced", "shop-row-motion-system"):
            self.assertEqual(_BY_NAME[name]["fixture"], ["shop_fixture.py", "--shop", "long-title"])
        system = _BY_NAME["shop-row-motion-system"]
        self.assertEqual(m.mode_pages([system], "normal"), [])
        self.assertEqual(m.mode_pages([system], "no-animations"), [system])
        self.assertEqual(m.mode_pages([_BY_NAME["shop-row-motion"]], "no-animations"), [])

    def test_surface_pages_pin_the_opaque_bordered_fallback(self):
        # surface-materials R4: transparency off, in-app Less Transparency or Increase Contrast make the row card opaque
        # (#121826) with a visible edge; with transparency on it stays translucent, so the opaque probe is not vacuous.
        opaque = "fill:C0,M0=#121826~1|C-40,M0=@fill~0|C40,M0=@fill~0|L60,B6=@fill~0"
        visible = "bg:L-6,M0|L0,M0!=@fill~6|C0,T0!=@fill~6|C0,B1!=@fill~6|L0,M0!=@bg~6|C0,T0!=@bg~6|C0,B1!=@bg~6"
        strong = "L0,M0=#84828A~40|C0,T0=#84828A~40|C0,B1=#84828A~40"
        cases = {
            "shop-row-surface-no-transparency": ("no-transparency", {}, visible),
            "shop-row-surface-less-transparency": ("normal", {"lessTransparency": True}, visible),
            "shop-row-surface-more-contrast": ("normal", {"moreContrast": True}, strong),
            "shop-row-surface-app-contrast": ("app-contrast", {}, strong),
        }
        for name, (mode, settings, edge) in cases.items():
            with self.subTest(page=name):
                page = _BY_NAME[name]
                self.assertEqual(page["modes"], [mode])
                self.assertEqual(m.mode_pages([page], mode), [page])
                self.assertEqual(m.mode_pages([page], "hc-desert"), [])
                for key, value in settings.items():
                    self.assertIs(page["settings"][key], value)
                steps = _steps(page)
                for row in _ROWS:
                    self.assertIn(f"assertpaint:id=fst.shop.song.{row}|{opaque}|{edge}", steps)
        self.assertEqual(m.mode_spec("no-transparency")["system"], {"transparency": False})
        self.assertEqual(m.mode_spec("app-contrast")["app"], {"moreContrast": True, "lessTransparency": True})
        translucent = _BY_NAME["shop-row-surface-translucent"]
        self.assertEqual(translucent["modes"], ["normal"])
        self.assertFalse({"lessTransparency", "moreContrast"} & set(translucent["settings"]))
        for row in _ROWS:
            self.assertIn(f"assertpaint:id=fst.shop.song.{row}|C0,M0!=#121826~1|C40,M0!=#121826~1", _steps(translucent))

    def test_fixture_pages_stay_off_live_runs(self):
        live = {p["name"] for p in m.live_pages(_PAGES)}
        self.assertFalse(live & {"shop-row-text-marquee", "shop-row-motion", "shop-row-motion-reduced",
                                 "shop-row-motion-system"})


if __name__ == "__main__":
    unittest.main()
