"""``rivals_fixture.py``: ``--band-rankings`` scenarios (issue #209) and anonymized names that follow the
requested rival into detail bodies.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import rivals_fixture as f  # noqa: E402  (sibling module; imports tools/mock_service.py)


class BandRankingsScenarioTests(unittest.TestCase):
    """Scenario responses and argument parsing."""

    def test_other_requests_defer_to_the_mock_service(self):
        for path in ("/api/songs", "/api/rankings/bands/Band_Duets?teamKey=fixture-team-1",
                     "/api/rankings/bands/Band_Duets/fixture-team-1/history"):
            self.assertIsNone(f.band_rankings_response(path, "empty"), path)

    def test_empty_board(self):
        status, body = f.band_rankings_response("/api/rankings/bands/Band_Trios?rankBy=fcrate&page=1&pageSize=25",
                                                "empty")
        self.assertEqual(status, 200)
        self.assertEqual((body["bandType"], body["rankBy"], body["pageSize"]), ("Band_Trios", "fcrate", 25))
        self.assertEqual((body["totalTeams"], body["entries"]), (0, []))

    def test_unavailable(self):
        self.assertEqual(f.band_rankings_response("/api/rankings/bands/Band_Duets", "unavailable")[0], 500)

    def test_anonymous_second_row_has_no_identity(self):
        _, body = f.band_rankings_response("/api/rankings/bands/Band_Duets?page=1&pageSize=25", "anonymous")
        first, second = body["entries"]
        self.assertEqual(body["totalTeams"], 2)
        self.assertEqual(first["teamKey"], "fixture-team-1")
        self.assertEqual((second["bandId"], second["teamKey"]), ("", ""))
        self.assertTrue(all(not (m["displayName"] or "").strip() for m in second["teamMembers"]))

    def test_take_band_rankings(self):
        self.assertEqual(f.take_band_rankings(["--port", "0"]), (None, ["--port", "0"]))
        self.assertEqual(f.take_band_rankings(["--band-rankings", "empty", "--port", "0"]), ("empty", ["--port", "0"]))
        self.assertEqual(f.take_band_rankings(["--band-rankings=anonymous"]), ("anonymous", []))
        for bad in (["--band-rankings"], ["--band-rankings", "nope"], ["--band-rankings="]):
            with self.assertRaises(SystemExit):
                f.take_band_rankings(bad)

    def test_take_songs_delay(self):
        self.assertEqual(f.take_songs_delay(["--port", "0"]), (None, ["--port", "0"]))
        self.assertEqual(f.take_songs_delay(["--songs-delay", "12", "--port", "0"]), (12.0, ["--port", "0"]))
        self.assertEqual(f.take_songs_delay(["--songs-delay=0.5"]), (0.5, []))
        for bad in (["--songs-delay"], ["--songs-delay", "soon"], ["--songs-delay=-1"]):
            with self.assertRaises(SystemExit):
                f.take_songs_delay(bad)

    def test_songs_delay_holds_only_the_catalogue(self):
        original = ms.FixtureHandler.do_GET
        served, slept = [], []
        ms.FixtureHandler.do_GET = lambda handler: served.append(handler.path)
        real_sleep = f.time.sleep
        f.time.sleep = slept.append
        try:
            f.install_songs_delay(3)
            for path in ("/api/songs", "/api/songs?x=1", "/api/shop"):
                ms.FixtureHandler.do_GET(type("H", (), {"path": path})())
        finally:
            ms.FixtureHandler.do_GET = original
            f.time.sleep = real_sleep
        self.assertEqual(served, ["/api/songs", "/api/songs?x=1", "/api/shop"])
        self.assertEqual(slept, [3, 3])

    def test_take_song_leaderboard(self):
        self.assertEqual(f.take_song_leaderboard(["--port", "0"]), (None, ["--port", "0"]))
        self.assertEqual(f.take_song_leaderboard(["--song-leaderboard", "anonymous", "--port", "0"]),
                         ("anonymous", ["--port", "0"]))
        self.assertEqual(f.take_song_leaderboard(["--song-leaderboard=anonymous"]), ("anonymous", []))
        for bad in (["--song-leaderboard"], ["--song-leaderboard", "empty"], ["--song-leaderboard="]):
            with self.assertRaises(SystemExit):
                f.take_song_leaderboard(bad)

    def test_anonymous_song_leaderboard_blanks_only_the_lead_rank_three_row(self):
        def board():
            return {"entries": [{"rank": r, "accountId": f"fixture-player-{r}", "displayName": f"P{r}"} for r in (2, 3, 4)]}

        lead = f.anonymize_song_leaderboard("/api/leaderboard/fixture-pulse/Solo_Guitar?top=10", board())
        self.assertEqual([(e["accountId"], e["displayName"]) for e in lead["entries"]],
                         [("fixture-player-2", "P2"), ("", None), ("fixture-player-4", "P4")])
        for path in ("/api/leaderboard/fixture-pulse/Solo_Drums", "/api/leaderboard/fixture-pulse/all",
                     "/api/leaderboard/fixture-pulse/bands/Band_Duets"):
            self.assertEqual(f.anonymize_song_leaderboard(path, board()), board(), path)
        self.assertIsNone(f.anonymize_song_leaderboard("/api/leaderboard/fixture-pulse/Solo_Guitar", None))

    def test_song_leaderboard_wraps_the_response_of_each_request(self):
        original = ms.FixtureHandler.do_GET
        sent = []

        class Handler:
            path = "/api/leaderboard/fixture-pulse/Solo_Guitar?top=10"

            def _json(self, status, payload, *, etag=None):
                sent.append((status, payload, etag))

        ms.FixtureHandler.do_GET = lambda handler: handler._json(200, {"entries": [{"rank": 3, "accountId": "a"}]}, etag="e")
        try:
            f.install_song_leaderboard("anonymous")
            handler = Handler()
            ms.FixtureHandler.do_GET(handler)
        finally:
            ms.FixtureHandler.do_GET = original
        self.assertEqual(sent, [(200, {"entries": [{"rank": 3, "accountId": "", "displayName": None}]}, "e")])
        self.assertNotIn("_json", vars(handler))

    def test_songs_unavailable_fails_only_the_catalogue(self):
        original = ms.FixtureHandler.do_GET
        served, answered = [], []
        ms.FixtureHandler.do_GET = lambda handler: served.append(handler.path)
        try:
            f.install_songs_unavailable()
            handler = type("H", (), {"_json": lambda self, status, body: answered.append((self.path, status, body))})
            for path in ("/api/songs", "/api/songs?x=1", "/api/shop"):
                ms.FixtureHandler.do_GET(type("H", (handler,), {"path": path})())
        finally:
            ms.FixtureHandler.do_GET = original
        self.assertEqual(served, ["/api/shop"])
        self.assertEqual([(p, s) for p, s, _ in answered], [("/api/songs", 503), ("/api/songs?x=1", 503)])


ms = f.mock_service


class SlowRivalsTests(unittest.TestCase):
    """Slow accounts (issue #265) hold only their rivals list reads."""

    def test_only_slow_accounts_list_reads_are_delayed(self):
        slow = f.SLOW_RIVALS_SECONDS
        for path in ("/api/player/fixture-player-slow/rivals/Solo_Guitar",
                     "/api/player/fixture-player-slow/rivals/03",
                     "/api/player/fixture-player-slow-503/rivals/Solo_Bass",
                     "/api/player/fixture-player-slow/leaderboard-rivals/Solo_Guitar?rankBy=totalscore"):
            self.assertEqual(f.rivals_list_delay(path), slow, path)
        for path in ("/api/player/fixture-player-1/rivals/Solo_Guitar",
                     "/api/player/fixture-player-503/leaderboard-rivals/Solo_Guitar",
                     "/api/player/fixture-player-slow/rivals/Solo_Guitar/f1c749eb07c32578cfa3e59ec38c03a8",
                     "/api/player/fixture-player-slow/leaderboard-rivals/Solo_Guitar/abc",
                     "/api/player/fixture-player-slow", "/api/songs"):
            self.assertEqual(f.rivals_list_delay(path), 0.0, path)

    def test_delay_stays_under_the_app_request_timeout(self):
        self.assertTrue(0 < f.SLOW_RIVALS_SECONDS < 30)

    def test_install_sleeps_then_serves(self):
        original = ms.FixtureHandler.do_GET
        served, slept = [], []
        ms.FixtureHandler.do_GET = lambda handler: served.append(handler.path)
        real_sleep = f.time.sleep
        f.time.sleep = slept.append
        try:
            f.install_slow_rivals()
            for path in ("/api/player/fixture-player-slow/rivals/Solo_Guitar", "/api/player/fixture-player-1/rivals/Solo_Guitar"):
                ms.FixtureHandler.do_GET(type("H", (), {"path": path})())
        finally:
            ms.FixtureHandler.do_GET = original
            f.time.sleep = real_sleep
        self.assertEqual(len(served), 2)
        self.assertEqual(slept, [f.SLOW_RIVALS_SECONDS])


class DetailNameTests(unittest.TestCase):
    """``name_detail_bodies`` patches both detail builders and restores cleanly."""

    def setUp(self):
        self.saved = (ms._rival_detail_body, ms._leaderboard_rival_detail_body)

    def tearDown(self):
        ms._rival_detail_body, ms._leaderboard_rival_detail_body = self.saved

    def test_detail_bodies_use_the_requested_rivals_name(self):
        f.name_detail_bodies({"aaa": "Demo Rival 7", "bbb": "Demo Rival 8"})
        self.assertEqual(ms._rival_detail_body("03", "aaa", "demo")["rival"]["displayName"], "Demo Rival 7")
        self.assertEqual(ms._rival_detail_body("03", "bbb", "empty")["rival"]["displayName"], "Demo Rival 8")
        board = ms._leaderboard_rival_detail_body("Solo_Guitar", "totalscore", "bbb", "demo")
        self.assertEqual((board["rival"]["accountId"], board["rival"]["displayName"]), ("bbb", "Demo Rival 8"))

    def test_unknown_rival_keeps_the_mock_name(self):
        expected = self.saved[0]("03", "zzz", "demo")["rival"]
        f.name_detail_bodies({"aaa": "Demo Rival 7"})
        self.assertEqual(ms._rival_detail_body("03", "zzz", "demo")["rival"], expected)

    def test_anonymize_numbers_new_accounts(self):
        names: dict[str, str] = {}
        payload = {"above": [{"accountId": "x", "displayName": "Real"}], "rival": {"accountId": "y", "displayName": "R"}}
        f.anonymize(payload, names)
        self.assertEqual(names, {"x": "Demo Rival 1", "y": "Demo Rival 2"})
        self.assertEqual(payload["rival"]["displayName"], "Demo Rival 2")


if __name__ == "__main__":
    unittest.main()
