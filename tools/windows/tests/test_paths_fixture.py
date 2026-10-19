"""``paths_fixture.py`` and ``journeys/paths.json``: the CHOpt Paths loading/offline overrides and their journeys.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import paths_fixture as f  # noqa: E402  (sibling module)

JOURNEYS = Path(__file__).resolve().parents[1] / "journeys" / "paths.json"


class PathsFixtureTests(unittest.TestCase):
    """Which path reads are delayed or dropped."""

    def test_image_and_data_reads_follow_the_difficulty(self):
        for suffix in ("", "/data"):
            self.assertEqual(f.path_override(f"/api/paths/fixture-pulse/Solo_Guitar/medium{suffix}", "hard", "medium"),
                             "offline")
            self.assertEqual(f.path_override(f"/api/paths/fixture-pulse/Solo_Guitar/hard{suffix}", "hard", "medium"),
                             "slow")
            self.assertIsNone(f.path_override(f"/api/paths/fixture-pulse/Solo_Guitar/expert{suffix}", "hard", "medium"))

    def test_offline_wins_and_none_disables(self):
        self.assertEqual(f.path_override("/api/paths/fixture-pulse/Solo_Bass/hard", "hard", "hard"), "offline")
        self.assertIsNone(f.path_override("/api/paths/fixture-pulse/Solo_Bass/hard", None, None))

    def test_other_routes_pass_through(self):
        for path in ("/api/songs", "/api/paths/fixture-pulse/Solo_Guitar", "/api/paths/x/Solo_Guitar/hard/extra"):
            self.assertIsNone(f.path_override(path, "hard", "medium"), path)


class PathsJourneyTests(unittest.TestCase):
    """Every reachable Paths state has a page under the dialog route."""

    STATES = ("image-loading", "image", "text-loading", "text", "missing", "offline", "instrument-switch",
              "difficulty-switch", "warning", "zoomed", "column-reorder", "swap-announced", "display-toggle",
              "rapid-switch")

    def test_every_state_has_a_page(self):
        pages = {page["name"] for page in json.loads(JOURNEYS.read_text(encoding="utf-8"))}
        for state in self.STATES:
            self.assertIn(f"paths-{state}", pages)

    def test_swap_journeys_assert_the_announcements_in_both_layouts(self):
        # Issue #269: each swap journey listens and asserts what Narrator hears, narrow and wide.
        pages = {page["name"]: page for page in json.loads(JOURNEYS.read_text(encoding="utf-8"))}
        for state in ("swap-announced", "display-toggle", "rapid-switch", "keyboard-switch"):
            for name, sizes in ((f"paths-{state}", {"compact", "medium", "snap-left"}),
                                (f"paths-{state}-wide", {"wide", "maximized"})):
                ready = pages[name]["ready"]
                self.assertIn("listen:announcements", ready, name)
                self.assertTrue(any(step.startswith("assertannounced:") for step in ready), name)
                self.assertEqual(set(pages[name]["sizes"]), sizes, name)

    def test_pages_open_the_fixture_song(self):
        for page in json.loads(JOURNEYS.read_text(encoding="utf-8")):
            self.assertEqual(page["route"], "/songs/fixture-pulse", page["name"])


class PathsMidLoadScanTests(unittest.TestCase):
    """A11y pages that scan the Paths spinner mid-load hold the read long enough for the scan to finish mid-load."""

    def test_mid_load_scans_hold_the_read_ten_seconds(self):
        # Issue #676: with the default 6 s hold the Hard read answered during a 4 s compact scan on the windows-ui
        # runner; the ring went inactive mid-scan ("Loading path" without WinUI's "Busy" prefix) and Axe flagged it and
        # its LottiePlayer IsControlElementTrueRequired. Same 10 s hold as the load-swap boards (#431 review).
        found = set()
        for path in sorted(JOURNEYS.parent.glob("a11y-*.json")):
            for page in json.loads(path.read_text(encoding="utf-8")):
                fixture = page.get("fixture") or []
                if not fixture or fixture[0] != "paths_fixture.py":
                    continue
                loading = False
                for step in (page.get("ready") or []) + (page.get("after_ready") or []):
                    if step.startswith("waitfor:id=fst.paths.loading"):
                        loading = True
                    elif step.startswith(("waitgone:id=fst.paths.loading", "waitfor:name=Lead Hard CHOpt path")):
                        loading = False
                    elif step.startswith("scan:") and loading:
                        found.add(page["name"])
                        self.assertIn("--slow-seconds", fixture, page["name"])
                        self.assertGreaterEqual(float(fixture[fixture.index("--slow-seconds") + 1]), 10, page["name"])
        self.assertEqual(found, {"paths-swap", "paths-swap-keyboard-wide"})


if __name__ == "__main__":
    unittest.main()
