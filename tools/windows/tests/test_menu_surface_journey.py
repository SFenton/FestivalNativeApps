"""Menu and drop-down surface pages (``journeys/a11y-menu-surface.json``, issue #641).

WinUI 2.x menus paint a transparent presenter that relies on a windowed popup's system backdrop; app popups open
in-window (#534), so menus showed the page through. These pages pin the one app flyout surface (surface-materials R4):
Fluent's dark acrylic (``#2C2C2C``) in normal mode, exactly ``#2C2C2C`` with Windows transparency effects off and the
in-app Less Transparency / Increase Contrast settings, and the system colour under contrast themes, on the Song Detail
Quick Links menu and the Full Rankings Instrument menu. Run: ``python -m unittest discover -s tools/windows/tests``
from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import uiwin as u

_PAGES = json.loads((Path(__file__).resolve().parents[1] / "journeys" / "a11y-menu-surface.json")
                    .read_text(encoding="utf-8"))
_BY_NAME = {p["name"]: p for p in _PAGES}
_MENUS = ("name=Quick Links&class=MenuFlyout", "id=InstrumentMenu")


def _steps(page: dict) -> list[str]:
    """A page's ready and after-ready steps, in run order."""
    return [*page.get("ready", []), *page.get("after_ready", [])]


def _paint(page: dict) -> list[str]:
    """The page's ``assertpaint`` steps."""
    return [s for s in _steps(page) if s.startswith("assertpaint:")]


def _solid(page: dict) -> bool:
    """Whether the page runs under a setting that must make the surface opaque."""
    settings = page.get("settings", {})
    return (settings.get("lessTransparency") or settings.get("moreContrast")
            or any(mode in ("no-transparency", "app-contrast") for mode in page["modes"]))


class MenuSurfaceJourneyTests(unittest.TestCase):
    """The pages parse, use known sizes and modes, and cover every surface state #641 asks for."""

    def test_every_step_parses(self):
        for page in _PAGES:
            for step in _steps(page):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step.replace("{stem}", "x"))

    def test_names_sizes_and_modes_are_known(self):
        self.assertEqual(len(_BY_NAME), len(_PAGES))
        for page in _PAGES:
            with self.subTest(page=page["name"]):
                self.assertTrue(set(page["sizes"]) <= set(u.PRESETS))
                self.assertTrue(set(page["modes"]) <= set(m.MODES))

    def test_every_page_opens_a_menu_and_probes_its_surface(self):
        for page in _PAGES:
            with self.subTest(page=page["name"]):
                steps = _steps(page)
                self.assertTrue(any(s.startswith("expand:") for s in steps))
                paint = _paint(page)
                self.assertTrue(paint)
                self.assertTrue(all(p.split("|")[0].removeprefix("assertpaint:") in _MENUS for p in paint))

    def test_quick_links_menu_is_compact_only(self):
        # Medium and wider windows show Quick Links as a pane, not a menu.
        for page in _PAGES:
            if any("quick-links" in s for s in _steps(page)):
                with self.subTest(page=page["name"]):
                    self.assertEqual(page["sizes"], ["compact"])

    def test_opaque_settings_expect_the_exact_fallback(self):
        solid = [p for p in _PAGES if _solid(p)]
        self.assertTrue(any(p.get("settings", {}).get("lessTransparency") for p in solid))
        self.assertTrue(any(p.get("settings", {}).get("moreContrast") for p in solid))
        self.assertTrue(any("no-transparency" in p["modes"] for p in solid))
        self.assertTrue(any("app-contrast" in p["modes"] for p in solid))
        for page in solid:
            for step in _paint(page):
                with self.subTest(page=page["name"], step=step):
                    for probe in step.split("|")[1:]:
                        self.assertRegex(probe, r"=#2C2C2C~[0-4]$")

    def test_both_reported_menus_have_translucent_and_opaque_pages(self):
        for menu in _MENUS:
            with self.subTest(menu=menu):
                pages = [p for p in _PAGES if any(s.startswith(f"assertpaint:{menu}|") for s in _paint(p))]
                self.assertTrue(any(_solid(p) for p in pages))
                self.assertTrue(any(not _solid(p) and p["modes"] == ["normal"] for p in pages))

    def test_contrast_themes_leave_the_acrylic(self):
        page = _BY_NAME["menu-surface-quick-links-contrast-theme"]
        self.assertTrue(all(mode.startswith("hc-") for mode in page["modes"]))
        self.assertIn("!=#2C2C2C", _paint(page)[0])

    def test_items_keep_their_target_at_large_text(self):
        page = _BY_NAME["menu-surface-instrument-text"]
        self.assertEqual(page["modes"], ["text-225", "text-200"])
        self.assertIn("assertsize:id=fst.full-rankings.instrument.Solo_Bass|0x40", page["after_ready"])


if __name__ == "__main__":
    unittest.main()
