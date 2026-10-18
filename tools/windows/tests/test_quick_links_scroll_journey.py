"""Quick Links scroll-settle accessibility journey (``journeys/a11y-quick-links-scroll.json``, issues #668 and #671).

Each page sweeps a long page like a scrollbar drag, checks the current section after the settle, and is Axe-scanned at
the end by the ``windows-ui`` runs ``quick-links-scroll`` and ``quick-links-scroll-text-225``. A page whose last checks
put keyboard focus on a control with a tooltip (Quick Links, the Item Shop button) leaves WinUI's always-windowed
tooltip open at the scan, which Axe reports as ``BoundingRectangleCompletelyObscuresContainer`` (windows-accessibility
open item 8, #534): those pages move focus to a tooltip-free control and wait for the tooltip to close first.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import ui_ci

_ROOT = Path(__file__).resolve().parents[3]
_FILE = "a11y-quick-links-scroll.json"
_PAGES = json.loads((_ROOT / "tools" / "windows" / "journeys" / _FILE).read_text(encoding="utf-8"))
# Controls these pages focus that carry a ToolTip (QuickLinksMenuButton, SongDetailPage's Item Shop button).
_TOOLTIP_OWNERS = {"id=fst.quick-links.open", "id=fst.song-detail.pinned-quick-links", "id=fst.song-detail.shop"}


class QuickLinksScrollJourneyTests(unittest.TestCase):
    def test_runs_scan_every_page(self):
        runs = [run for run in ui_ci.RUNS if run.pages == _FILE]
        self.assertEqual({"quick-links-scroll", "quick-links-scroll-text-225"}, {run.name for run in runs})
        self.assertTrue(all(run.scan for run in runs))
        for page in _PAGES:
            self.assertNotIn("axe_allow", page, page["name"])

    def test_scan_never_meets_a_keyboard_tooltip(self):
        for page in _PAGES:
            steps = page["after_ready"]
            focuses = [s for s in steps if s.startswith("focus:")]
            with self.subTest(page=page["name"]):
                self.assertTrue(focuses)
                last = focuses[-1].removeprefix("focus:")
                self.assertNotIn(last, _TOOLTIP_OWNERS)
                tail = steps[steps.index(focuses[-1]):]
                self.assertIn(f"assertfocus:{last}@3", tail)
                if any(s.removeprefix("focus:") in _TOOLTIP_OWNERS for s in focuses):
                    self.assertEqual("waitgone:class=ToolTip@5", steps[-1])

    def test_song_detail_pages_still_check_quick_links_focus(self):
        for name in ("qls-song-detail-menu", "qls-song-detail-menu-text-225"):
            steps = next(p for p in _PAGES if p["name"] == name)["after_ready"]
            with self.subTest(page=name):
                self.assertIn("assertfocus:id=fst.quick-links.open@3", steps)
                self.assertLess(steps.index("assertfocus:id=fst.quick-links.open@3"),
                                steps.index("focus:id=fst.song-detail.paths"))


if __name__ == "__main__":
    unittest.main()
