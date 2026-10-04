"""Star Rating journey tooling: ``star_rating_fixture.py`` rewrites (issue #221).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import threading
import unittest
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import star_rating_fixture as f  # noqa: E402  (sibling module)
import mock_service  # noqa: E402


class RewriteTests(unittest.TestCase):
    """Which payloads the wrapper changes."""

    def test_lead_board_stars_by_rank(self):
        payload = {"entries": [{"rank": rank, "stars": 5} for rank in range(1, 10)], "count": 9}
        out = f.rewrite("/api/leaderboard/fixture-pulse/Solo_Guitar", payload)
        by_rank = {entry["rank"]: entry.get("stars", "missing") for entry in out["entries"]}
        self.assertEqual(by_rank, {1: 6, 2: 5, 3: 1, 4: 0, 5: 7, 6: "missing", 7: 3, 8: 5, 9: 5})
        self.assertEqual(out["count"], 9)
        # The mock's own payload is not mutated (it is shared module state).
        self.assertTrue(all(entry["stars"] == 5 for entry in payload["entries"]))

    def test_gold_player_scores(self):
        payload = {"accountId": f.GOLD_PLAYER, "scores": [{"si": "a", "st": 5}, {"si": "b", "st": 3}]}
        out = f.rewrite(f"/api/player/{f.GOLD_PLAYER}", payload)
        self.assertEqual([score["st"] for score in out["scores"]], [6, 6])
        self.assertEqual([score["st"] for score in payload["scores"]], [5, 3])

    def test_other_routes_unchanged(self):
        payload = {"entries": [{"rank": 1, "stars": 5}]}
        self.assertIs(f.rewrite("/api/leaderboard/fixture-pulse/Solo_Bass", payload), payload)
        self.assertIs(f.rewrite("/api/player/fixture-player-2", payload), payload)
        self.assertIsNone(f.rewrite("/api/songs", None))


class FixtureServerTests(unittest.TestCase):
    """The patched handler over a real loopback socket."""

    @classmethod
    def setUpClass(cls):
        f.install()
        cls.server = mock_service.FixtureServer(("127.0.0.1", 0), mock_service.FixtureHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def get(self, path: str) -> dict:
        with urllib.request.urlopen(self.base + path, timeout=10) as response:
            return json.loads(response.read())

    def test_served_board_and_player(self):
        entries = self.get("/api/leaderboard/fixture-pulse/Solo_Guitar?top=7")["entries"]
        self.assertEqual([entry.get("stars") for entry in entries], [6, 5, 1, 0, 7, None, 3])
        scores = self.get(f"/api/player/{f.GOLD_PLAYER}")["scores"]
        self.assertTrue(scores and all(score["st"] == 6 for score in scores))


if __name__ == "__main__":
    unittest.main()
