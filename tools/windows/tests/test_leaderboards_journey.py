"""Leaderboards journey tooling: ``leaderboards_fixture.py`` overrides and ``leaderboards_journey.py`` helpers.

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
import leaderboards_fixture as f  # noqa: E402  (sibling module)
import leaderboards_journey as j  # noqa: E402
import mock_service  # noqa: E402
from tools.windows import uiwin  # noqa: E402


class BoardOverrideTests(unittest.TestCase):
    """Which requests the wrapper answers itself."""

    def test_top_level_boards_only(self):
        empty, frozen = {"Solo_Bass", "Band_Trios"}, {"Solo_Drums"}
        self.assertEqual(f.board_override("/api/rankings/Solo_Bass", empty, frozen), ("empty", "Solo_Bass", False))
        self.assertEqual(f.board_override("/api/rankings/bands/Band_Trios", empty, frozen), ("empty", "Band_Trios", True))
        self.assertEqual(f.board_override("/api/rankings/Solo_Drums", empty, frozen), ("frozen", "Solo_Drums", False))
        # Spotlight reads, other boards and other routes defer to the mock.
        self.assertIsNone(f.board_override("/api/rankings/Solo_Bass/fixture-player-1", empty, frozen))
        self.assertIsNone(f.board_override("/api/rankings/Solo_Guitar", empty, frozen))
        self.assertIsNone(f.board_override("/api/songs", empty, frozen))

    def test_frozen_wins_over_empty(self):
        self.assertEqual(f.board_override("/api/rankings/Solo_Bass", {"Solo_Bass"}, {"Solo_Bass"})[0], "frozen")

    def test_slow_boards_defer_to_empty_and_frozen(self):
        slow = {"Solo_Bass", "Band_Duets"}
        self.assertEqual(f.board_override("/api/rankings/Solo_Bass", set(), set(), slow), ("slow", "Solo_Bass", False))
        self.assertEqual(f.board_override("/api/rankings/bands/Band_Duets", set(), set(), slow),
                         ("slow", "Band_Duets", True))
        self.assertEqual(f.board_override("/api/rankings/Solo_Bass", {"Solo_Bass"}, set(), slow)[0], "empty")
        self.assertIsNone(f.board_override("/api/rankings/Solo_Bass/fixture-player-1", set(), set(), slow))
        self.assertLess(f.SLOW_SECONDS, 30.0, "a slow board must answer inside the app's 30 s request timeout")

    def test_empty_page_shapes(self):
        query = {"rankBy": ["fcrate"], "page": ["1"], "pageSize": ["10"]}
        account = f.empty_page("Solo_Bass", False, query)
        self.assertEqual((account["instrument"], account["totalAccounts"], account["entries"]), ("Solo_Bass", 0, []))
        self.assertEqual(account["rankBy"], "fcrate")
        band = f.empty_page("Band_Trios", True, {})
        self.assertEqual((band["bandType"], band["totalTeams"], band["pageSize"]), ("Band_Trios", 0, 10))
        self.assertNotIn("totalAccounts", band)


class FixtureServerTests(unittest.TestCase):
    """The patched handler over a real loopback socket."""

    @classmethod
    def setUpClass(cls):
        cls.original = mock_service.FixtureHandler.do_GET
        cls.slow_seconds = f.SLOW_SECONDS
        f.SLOW_SECONDS = 0.2
        f.install({"Solo_Bass"}, {"Solo_Drums"}, {"Solo_Vocals"})
        cls.server = mock_service.FixtureServer(("127.0.0.1", 0), mock_service.FixtureHandler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        mock_service.FixtureHandler.do_GET = cls.original
        f.SLOW_SECONDS = cls.slow_seconds

    def get(self, path):
        with urllib.request.urlopen(self.base + path, timeout=5) as response:
            return response.status, json.loads(response.read())

    def test_empty_frozen_and_untouched_boards(self):
        status, body = self.get("/api/rankings/Solo_Bass?page=1&pageSize=10")
        self.assertEqual((status, body["entries"], body["totalAccounts"]), (200, [], 0))
        with self.assertRaises(urllib.error.HTTPError) as caught:
            self.get("/api/rankings/Solo_Drums?page=1&pageSize=10")
        self.assertEqual(caught.exception.code, 503)
        self.assertEqual(caught.exception.headers["Retry-After"], "30")
        self.assertEqual(caught.exception.headers["X-Fst-Public-Read-Freeze-Reason"], "scrape")
        status, body = self.get("/api/rankings/Solo_Guitar?page=1&pageSize=10")
        self.assertEqual((status, body["totalAccounts"]), (200, 3))

    def test_slow_board_answers_the_normal_page_late(self):
        started = time.monotonic()
        status, body = self.get("/api/rankings/Solo_Vocals?page=1&pageSize=10")
        self.assertGreaterEqual(time.monotonic() - started, 0.2)
        self.assertEqual((status, body["totalAccounts"]), (200, 3))


class JourneyHelperTests(unittest.TestCase):
    """Pure helpers and the scenario table."""

    def test_ready_port(self):
        self.assertEqual(j.ready_port("Local test fixture service on 127.0.0.1:51234\n"), 51234)
        self.assertIsNone(j.ready_port("Traceback (most recent call last):"))

    def test_expand_shots(self):
        steps = ["waitfor:id=a", "{shot:cards}"]
        self.assertEqual(j.expand(steps, None, "wide"), ["waitfor:id=a"])
        expanded = j.expand(steps, Path("out"), "wide")
        self.assertTrue(expanded[1].startswith("shot:") and expanded[1].endswith("cards-wide.png"))

    def test_launch_args_use_fixture_unless_the_scenario_overrides(self):
        args = j.launch_args({"FST_DEBUG_ANONYMOUS": "1"}, 4321, Path("s.json"), "compact")
        self.assertIn("--arg=--base-url=http://127.0.0.1:4321/", args)
        self.assertEqual(args[args.index("--route") + 1], "/leaderboards")
        closed = j.launch_args({"FST_BASE_URL": "http://127.0.0.1:9/"}, 4321, Path("s.json"), "compact")
        self.assertFalse(any(a.startswith("--arg=--base-url") for a in closed))
        self.assertIn("FST_BASE_URL=http://127.0.0.1:9/", closed)

    def test_every_scenario_step_parses_and_is_lock_tolerant(self):
        for name, (_, _, steps) in j.SCENARIOS.items():
            for step in j.expand(steps, Path("out"), "medium"):
                parsed = uiwin.parse_step(step)
                self.assertNotIn(parsed["verb"], {"click", "rightclick", "hover", "key", "scroll", "type", "tabwalk"},
                                 f"{name}: {step} needs real input")


class LongNameTests(unittest.TestCase):
    """``--long-name`` renames only the rank-2 entry (issue #292)."""

    def setUp(self):
        self.original = mock_service._ranking_entry
        self.addCleanup(setattr, mock_service, "_ranking_entry", self.original)

    def test_only_rank_two_gets_the_long_name(self):
        f.install_long_name()
        self.assertEqual(mock_service._ranking_entry(2, "fixture-player-2", "Fixture Player 2")["displayName"], f.LONG_NAME)
        first = mock_service._ranking_entry(1, "fixture-player-1", "Fixture Player 1")
        self.assertEqual((first["displayName"], first["accountId"]), ("Fixture Player 1", "fixture-player-1"))
        # Everything but the name is the mock's usual row.
        renamed = mock_service._ranking_entry(2, "fixture-player-2", "x")
        self.assertEqual({**renamed, "displayName": "x"}, self.original(2, "fixture-player-2", "x"))

    def test_long_name_overflows_any_row_and_is_in_the_journey_name(self):
        self.assertGreater(len(f.LONG_NAME), 60)
        self.assertIn(f.LONG_NAME, j.LONG_ROW_NAME)
        self.assertEqual(j.SCENARIOS["long-name"][1], ["--long-name"])


if __name__ == "__main__":
    unittest.main()
