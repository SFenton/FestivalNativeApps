"""Instrument status chip tooling: ``instrument_status_fixture.py`` and the ``journeys/instrument-status.json`` pages.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import threading
import time
import unittest
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import a11y_matrix as m  # noqa: E402  (sibling module)
import instrument_status_fixture as f  # noqa: E402
import mock_service  # noqa: E402
from tools.windows import uiwin  # noqa: E402

PAGES = Path(__file__).resolve().parents[1] / "journeys" / "instrument-status.json"


class RewriteTests(unittest.TestCase):
    """Designed scores and the Keyboard signature replace only their routes."""

    def test_profile_is_replaced(self):
        body = f.rewrite(f"/api/player/{f.PLAYER}", {"accountId": f.PLAYER, "displayName": "P", "scores": [{"si": "x"}]})
        self.assertEqual((body["accountId"], body["displayName"], body["totalScores"]), (f.PLAYER, "P", len(f.SCORES)))
        self.assertEqual(body["scores"], f.SCORES)
        body["scores"][0]["sc"] = -1
        self.assertNotEqual(f.SCORES[0]["sc"], -1, "profile rows are copies")

    def test_keyboard_signature_only_on_orbit(self):
        songs = f.rewrite("/api/songs", {"songs": [{"songId": "fixture-orbit"}, {"songId": "fixture-pulse"}]})["songs"]
        self.assertEqual([s.get("sig") for s in songs], ["Keyboard", None])

    def test_other_payloads_pass_through(self):
        payload = {"scores": []}
        self.assertIs(f.rewrite("/api/player/someone-else", payload), payload)
        self.assertIsNone(f.rewrite("/api/songs", None))
        self.assertEqual(f.rewrite("/api/songs", {"songs": "bad"}), {"songs": "bad"})

    def test_every_chip_state_is_designed(self):
        """FC, scored, zero-score FC (inconsistent), zero score (no score) and an invalid score with a valid fallback."""
        rows = f.SCORES
        self.assertTrue(any(r["sc"] > 0 and r["fc"] for r in rows))
        self.assertTrue(any(r["sc"] > 0 and not r["fc"] for r in rows))
        self.assertTrue(any(r["sc"] == 0 and r["fc"] for r in rows))
        self.assertTrue(any(r["sc"] == 0 and not r["fc"] for r in rows))
        self.assertTrue(any(r.get("ml", 0) > 1 and r["vs"][0]["ml"] <= 1 and r["vs"][0]["fc"] for r in rows))


class FixtureServerTests(unittest.TestCase):
    """The patched handler over a real loopback socket."""

    @classmethod
    def setUpClass(cls):
        cls.original = mock_service.FixtureHandler.do_GET
        cls.original_slow = f.SLOW_SECONDS
        f.SLOW_SECONDS = 0.3
        f.install()
        cls.server = mock_service.FixtureServer(("127.0.0.1", 0), mock_service.FixtureHandler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        mock_service.FixtureHandler.do_GET = cls.original
        f.SLOW_SECONDS = cls.original_slow

    def get(self, path):
        with urllib.request.urlopen(self.base + path, timeout=5) as response:
            return json.loads(response.read())

    def test_player_profile_carries_designed_scores(self):
        body = self.get(f"/api/player/{f.PLAYER}")
        self.assertEqual(len(body["scores"]), len(f.SCORES))
        self.assertIn({"si": "fixture-pulse", "ins": "08", "sc": 0, "fc": True}, body["scores"])

    def test_slow_player_waits_then_answers(self):
        start = time.monotonic()
        body = self.get(f"/api/player/{f.SLOW_PLAYER}")
        self.assertGreaterEqual(time.monotonic() - start, 0.25)
        self.assertEqual((body["displayName"], len(body["scores"])), ("Slow Player", len(f.SCORES)))

    def test_catalogue_marks_orbit_keyboard(self):
        songs = {s["songId"]: s for s in self.get("/api/songs")["songs"]}
        self.assertEqual(songs["fixture-orbit"].get("sig"), "Keyboard")
        self.assertNotEqual(songs["fixture-pulse"].get("sig"), "Keyboard")


class PagesTests(unittest.TestCase):
    """Every page step parses, needs no real mouse input and every listed state has a page."""

    def test_pages_parse(self):
        pages = json.loads(PAGES.read_text(encoding="utf-8"))
        self.assertGreaterEqual({p["name"] for p in pages}, {
            "chips-states", "chips-loading", "chips-syncing", "chips-failed", "chips-empty", "chips-anonymous",
            "chips-instrument-hidden", "chips-chart-filtered", "chips-icons-off", "chips-invalid-scores",
            "chips-filter-damaged", "chips-keyboard", "chips-resize"})
        for page in pages:
            for step in m.page_steps(page, "medium", Path("out"), "", True, 10):
                parsed = uiwin.parse_step(step)
                self.assertNotIn(parsed["verb"], {"click", "rightclick", "hover", "scroll"}, f"{page['name']}: {step}")

    def test_chip_ids_follow_the_test_id_root(self):
        text = PAGES.read_text(encoding="utf-8")
        for page in json.loads(text):
            for step in page["ready"]:
                if "instrument-status" in step:
                    self.assertIn("raw=fst.songs.instrument-status.", step)


class StepTests(unittest.TestCase):
    """``assertbelow`` / ``assertlevel`` take two element selectors."""

    def test_vertical_pairs(self):
        for verb in ("assertbelow", "assertlevel"):
            step = uiwin.parse_step(f"{verb}:raw=a|id=b")
            self.assertEqual((step["verb"], step["selector"]["value"], step["other"]["value"]), (verb, "a", "b"))
            for bad in (f"{verb}:raw=a", f"{verb}:raw=a|1,2"):
                with self.assertRaises(ValueError):
                    uiwin.parse_step(bad)


if __name__ == "__main__":
    unittest.main()
