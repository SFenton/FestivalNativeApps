"""Song score metadata journey tooling: ``song_metadata_fixture.py`` (issue #228).

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
import song_metadata_fixture as f  # noqa: E402  (sibling module)
import mock_service  # noqa: E402


class DesignTests(unittest.TestCase):
    """The designed profile."""

    def test_designed_accounts(self):
        self.assertEqual(f.designed_account(f"/api/player/{f.ACCOUNT}"), f.ACCOUNT)
        self.assertEqual(f.designed_account(f"/api/player/{f.SLOW_ACCOUNT}?x=1"), f.SLOW_ACCOUNT)
        self.assertIsNone(f.designed_account(f"/api/player/{f.ACCOUNT}/history"))
        self.assertIsNone(f.designed_account("/api/player/fixture-player-1"))

    def test_profile_is_valid_wire(self):
        body = f.profile(f.ACCOUNT)
        self.assertEqual(body["totalScores"], len(body["scores"]))
        for score in body["scores"]:
            self.assertIn(score["ins"], ("01", "02"))
            self.assertGreaterEqual(score["sc"], 0)
            self.assertTrue(0 <= score.get("st", 0) <= 6)
            self.assertTrue(0 <= score.get("acc", 0) <= 1000)
            self.assertIn(score.get("dif", 0), (0, 1, 2, 3))
        # Copies: callers may not mutate the module's design.
        body["scores"][0]["sc"] = -1
        self.assertGreater(f.SCORES[0]["sc"], 0)

    def test_states_designed(self):
        lead = {s["si"]: s for s in f.SCORES if s["ins"] == "01"}
        self.assertTrue(lead["fixture-song-2"]["fc"] and lead["fixture-song-2"]["st"] == 6)
        self.assertTrue(lead["fixture-song-3"]["fc"] and "acc" not in lead["fixture-song-3"])
        self.assertTrue("acc" not in lead["fixture-song-4"] and "rk" not in lead["fixture-song-4"])
        self.assertEqual(lead["fixture-song-7"]["sc"], 0)
        self.assertEqual({lead[f"fixture-song-{n}"]["dif"] for n in range(1, 5)}, {0, 1, 2, 3})
        self.assertTrue(any(s["ins"] == "02" for s in f.SCORES))

    def test_large_catalogue_default(self):
        self.assertEqual(f.with_large_catalogue(["--port", "0"]), ["--port", "0", "--large-catalogue"])
        self.assertEqual(f.with_large_catalogue(["--large-catalogue"]), ["--large-catalogue"])


class StepTests(unittest.TestCase):
    """The ``assertrow`` / ``assertbelow`` geometry steps the journeys use."""

    def test_geometry_pairs(self):
        import uiwin  # noqa: PLC0415  (sibling module; path set above)
        for verb in ("assertrow", "assertbelow"):
            step = uiwin.parse_step(f"{verb}:raw=fst.songs.metadata.score.a|id=b")
            self.assertEqual(step["selector"], {"kind": "raw", "value": "fst.songs.metadata.score.a"})
            self.assertEqual(step["other"], {"kind": "id", "value": "b"})
            for bad in (f"{verb}:raw=a", f"{verb}:raw=a|1,2"):
                with self.assertRaises(ValueError):
                    uiwin.parse_step(bad)


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

    def test_served_profile(self):
        body = self.get(f"/api/player/{f.ACCOUNT}")
        self.assertEqual(body["accountId"], f.ACCOUNT)
        self.assertEqual(len(body["scores"]), len(f.SCORES))

    def test_other_players_unchanged(self):
        body = self.get("/api/player/fixture-player-1")
        self.assertEqual(body["accountId"], "fixture-player-1")
        self.assertNotEqual(len(body["scores"]), len(f.SCORES))


if __name__ == "__main__":
    unittest.main()
