"""Score-accuracy tooling: ``score_accuracy_fixture.py`` designed rows and the ``journeys/score-accuracy.json`` pages.

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
import a11y_matrix as m  # noqa: E402  (sibling module)
import mock_service  # noqa: E402
import score_accuracy_fixture as f  # noqa: E402
from tools.windows import uiwin  # noqa: E402

PAGES = Path(__file__).resolve().parents[1] / "journeys" / "score-accuracy.json"


class DesignTests(unittest.TestCase):
    """The designed ranks replace the mock's values; other ranks pass through."""

    def test_design_rewrites_only_designed_ranks(self):
        body = {"entries": [
            {"rank": 1, "accuracy": 979999, "isFullCombo": False},
            {"rank": 3, "accuracy": 979997, "isFullCombo": False},
            {"rank": 4, "isFullCombo": False},
            {"rank": 9, "accuracy": 979991, "isFullCombo": False},
        ]}
        entries = f.design(body)["entries"]
        self.assertEqual((entries[0]["accuracy"], entries[0]["isFullCombo"]), (995_000, False))
        self.assertNotIn("accuracy", entries[1])
        self.assertEqual((entries[2].get("accuracy"), entries[2]["isFullCombo"]), (None, True))
        self.assertEqual((entries[3]["accuracy"], entries[3]["isFullCombo"]), (979991, False))

    def test_every_wire_state_is_designed(self):
        states = set(f.DESIGNED.values())
        self.assertIn((None, False), states)
        self.assertIn((None, True), states)
        self.assertIn((1_000_000, True), states)
        self.assertTrue(any(a is not None and a > 1_000_000 for a, _ in states))


class FixtureServerTests(unittest.TestCase):
    """The patched handler over a real loopback socket."""

    @classmethod
    def setUpClass(cls):
        cls.original = mock_service.FixtureHandler._json
        f.install()
        cls.server = mock_service.FixtureServer(("127.0.0.1", 0), mock_service.FixtureHandler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        mock_service.FixtureHandler._json = cls.original

    def get(self, path):
        with urllib.request.urlopen(self.base + path, timeout=5) as response:
            return json.loads(response.read())

    def test_lead_chart_carries_designed_rows(self):
        entries = {e["rank"]: e for e in self.get("/api/leaderboard/fixture-pulse/Solo_Guitar?top=10")["entries"]}
        self.assertEqual(entries[6]["accuracy"], 120_000)
        self.assertEqual(entries[7]["accuracy"], 1_050_000)
        self.assertNotIn("accuracy", entries[4])
        self.assertTrue(entries[4]["isFullCombo"])

    def test_other_routes_are_untouched(self):
        self.assertIn("songs", self.get("/api/songs"))


class PagesTests(unittest.TestCase):
    """Every page step parses and needs no real mouse input."""

    def test_pages_parse(self):
        pages = json.loads(PAGES.read_text(encoding="utf-8"))
        self.assertEqual({p["name"] for p in pages} >= {"score-accuracy-chart", "score-accuracy-preview"}, True)
        for page in pages:
            for step in m.page_steps(page, "medium", Path("out"), "", True, 10):
                parsed = uiwin.parse_step(step)
                self.assertNotIn(parsed["verb"], {"click", "rightclick", "hover", "scroll"}, f"{page['name']}: {step}")


class StepTests(unittest.TestCase):
    """``raw=`` selectors and the ``assertname`` / ``assertaligned`` steps."""

    def test_raw_selector(self):
        self.assertEqual(uiwin.parse_selector("raw=fst.score.accuracy.a"), {"kind": "raw", "value": "fst.score.accuracy.a"})

    def test_assertname(self):
        step = uiwin.parse_step("assertname:raw=fst.score.accuracy.a@8|98.5%")
        self.assertEqual((step["selector"]["kind"], step["timeout"], step["text"]), ("raw", 8.0, "98.5%"))
        self.assertEqual(uiwin.parse_step("assertname:id=x|a|b")["text"], "a|b")
        for bad in ("assertname:id=x", "assertname:10,10|x"):
            with self.assertRaises(ValueError):
                uiwin.parse_step(bad)

    def test_assertaligned(self):
        step = uiwin.parse_step("assertaligned:raw=a|id=b")
        self.assertEqual((step["selector"]["value"], step["other"]["value"]), ("a", "b"))
        for bad in ("assertaligned:raw=a", "assertaligned:raw=a|1,2"):
            with self.assertRaises(ValueError):
                uiwin.parse_step(bad)


if __name__ == "__main__":
    unittest.main()
