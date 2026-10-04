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
              "difficulty-switch", "warning", "zoomed", "column-reorder")

    def test_every_state_has_a_page(self):
        pages = {page["name"] for page in json.loads(JOURNEYS.read_text(encoding="utf-8"))}
        for state in self.STATES:
            self.assertIn(f"paths-{state}", pages)

    def test_pages_open_the_fixture_song(self):
        for page in json.loads(JOURNEYS.read_text(encoding="utf-8")):
            self.assertEqual(page["route"], "/songs/fixture-pulse", page["name"])


if __name__ == "__main__":
    unittest.main()
