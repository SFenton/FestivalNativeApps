"""Profile-selection tooling: ``profile_fixture.py`` states and the ``journeys/profile-selection*.json`` pages.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import a11y_matrix as m  # noqa: E402  (sibling module)
import mock_service  # noqa: E402
import profile_fixture as f  # noqa: E402
from tools.windows import uiwin  # noqa: E402

JOURNEYS = Path(__file__).resolve().parents[1] / "journeys"
#: Every reachable state in contracts/product.json for the profile-selection control.
STATES = {"anonymous", "debouncing", "loading", "results", "empty-envelope", "http-error", "viewed", "syncing",
          "selected-syncing-retry", "unpinned-profile", "selected-player", "switch-confirm", "deselect-confirm",
          "band-blocked", "profile-reload", "publication-changed", "large-text"}


class PureTests(unittest.TestCase):
    """Search results and the rollover profile."""

    def test_rollover_joins_matching_searches_only(self):
        self.assertEqual(f.search_results("zzz", []), [])
        self.assertEqual([r["accountId"] for r in f.search_results("Roll", [])], [f.ROLLOVER_ID])
        self.assertEqual(len(f.search_results("player", [{"accountId": "a", "displayName": "A Player"}])), 2)

    def test_rollover_profile_takes_its_own_identity(self):
        profile = f.rollover_profile()
        self.assertEqual((profile["accountId"], profile["displayName"]), (f.ROLLOVER_ID, f.ROLLOVER_NAME))
        self.assertTrue(profile["scores"])
        self.assertEqual(mock_service.PLAYER_DEMO["profiles"]["fixture-player-2"]["accountId"], "fixture-player-2")


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

    def get(self, path, pin=None):
        request = urllib.request.Request(self.base + path)
        if pin is not None:
            request.add_header("X-FST-Publication-Id", str(pin))
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return response.status, response.headers.get("X-FST-Publication-Id"), json.loads(response.read())
        except urllib.error.HTTPError as error:
            return error.code, error.headers.get("X-FST-Publication-Id"), json.loads(error.read())

    def test_slow_search_returns_the_rollover_player(self):
        started = time.monotonic()
        status, _, body = self.get("/api/account/search?q=Rollover&limit=10")
        self.assertGreaterEqual(time.monotonic() - started, f.SLOW_SECONDS - 0.1)
        self.assertEqual((status, [r["accountId"] for r in body["results"]]), (200, [f.ROLLOVER_ID]))

    def test_other_searches_are_untouched(self):
        status, _, body = self.get("/api/account/search?q=Fixture&limit=10")
        self.assertEqual((status, [r["accountId"] for r in body["results"]]), (200, ["fixture-player-1", "fixture-player-2"]))
        self.assertEqual(self.get("/api/account/search?q=busy&limit=10")[0], 503)

    def test_rollover_read_advances_and_stale_pins_conflict(self):
        before = self.server.publication_id
        status, served, body = self.get(f"/api/player/{f.ROLLOVER_ID}", pin=before)
        self.assertEqual((status, served, body["accountId"]), (200, str(before), f.ROLLOVER_ID))
        self.assertEqual(self.server.publication_id, before + 1)
        # A route the mock serves without a pin check still conflicts for the older generation.
        self.assertEqual(self.get("/api/rankings/Solo_Guitar/fixture-player-1/history?days=30", pin=before)[0], 409)
        self.assertEqual(self.get("/api/player/fixture-player-1", pin=before + 1)[0], 200)
        self.assertEqual(self.get("/api/publication")[2]["publicationId"], before + 1)


class PagesTests(unittest.TestCase):
    """Every page parses, needs no real mouse input and every reachable state has a page or a mode."""

    def pages(self):
        return [p for name in ("profile-selection.json", "profile-selection-unpinned.json")
                for p in json.loads((JOURNEYS / name).read_text(encoding="utf-8"))]

    def test_pages_parse(self):
        # With a player the avatar opens Statistics (issue #290); its picker shortcut is a window accelerator that needs
        # no pointer or focused element (posted on a locked console), so it is the one key step these pages may use.
        allowed_keys = {"key:ctrl+shift+p"}
        for page in self.pages():
            for step in m.page_steps(page, "medium", Path("out"), "", True, 10):
                if step in allowed_keys:
                    continue
                parsed = uiwin.parse_step(step)
                self.assertNotIn(parsed["verb"], {"click", "rightclick", "hover", "scroll", "type", "key"},
                                 f"{page['name']}: {step}")

    def test_every_state_is_covered(self):
        names = {p["name"].removeprefix("profile-") for p in self.pages()}
        aliases = {"unpinned": "unpinned-profile", "reload": "profile-reload"}
        covered = {aliases.get(n, n) for n in names} | {"large-text"}  # large-text: every page with --mode text-200
        self.assertLessEqual(STATES, covered)
        self.assertIn("text-200", m.MODES)


if __name__ == "__main__":
    unittest.main()
