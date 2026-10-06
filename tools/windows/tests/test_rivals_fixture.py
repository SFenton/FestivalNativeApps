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


ms = f.mock_service


class SongBandRowsTests(unittest.TestCase):
    """``--song-band-rows``: a song band board long enough to scroll under its pager (issue #305)."""

    def test_pages_through_the_long_board(self):
        first = f.song_band_board_response("/api/leaderboard/fixture-pulse/bands/Band_Duets?top=25&offset=0", 40)
        self.assertEqual((first["totalEntries"], first["localEntries"], first["count"]), (40, 40, 25))
        self.assertEqual([e["rank"] for e in first["entries"]][:2], [1, 2])
        last = f.song_band_board_response("/api/leaderboard/fixture-pulse/bands/Band_Trios?top=25&offset=25", 40)
        self.assertEqual((last["bandType"], last["count"], last["entries"][-1]["rank"]), ("Band_Trios", 15, 40))

    def test_other_requests_defer_to_the_mock_service(self):
        for path in ("/api/leaderboard/fixture-pulse/bands/all", "/api/leaderboard/fixture-pulse/Solo_Guitar",
                     "/api/leaderboard/fixture-pulse/bands/Band_Nope", "/api/leaderboard/real-song/bands/Band_Duets",
                     "/api/leaderboard/fixture-pulse/bands/Band_Duets?top=0",
                     "/api/leaderboard/fixture-pulse/bands/Band_Duets?offset=x"):
            self.assertIsNone(f.song_band_board_response(path, 40), path)

    def test_take_song_band_rows(self):
        self.assertEqual(f.take_song_band_rows(["--port", "0"]), (None, ["--port", "0"]))
        self.assertEqual(f.take_song_band_rows(["--song-band-rows", "40", "--port", "0"]), (40, ["--port", "0"]))
        self.assertEqual(f.take_song_band_rows(["--song-band-rows=60"]), (60, []))
        for bad in (["--song-band-rows"], ["--song-band-rows", "many"], ["--song-band-rows=0"]):
            with self.assertRaises(SystemExit):
                f.take_song_band_rows(bad)

    def test_install_serves_long_boards_and_defers_the_rest(self):
        original = ms.FixtureHandler.do_GET
        served, answered = [], []
        ms.FixtureHandler.do_GET = lambda handler: served.append(handler.path)
        try:
            f.install_song_band_rows(30)
            for path in ("/api/leaderboard/fixture-pulse/bands/Band_Quad", "/api/songs"):
                handler = type("H", (), {"path": path, "_json": lambda self, status, body: answered.append((status, body))})()
                ms.FixtureHandler.do_GET(handler)
        finally:
            ms.FixtureHandler.do_GET = original
        self.assertEqual(served, ["/api/songs"])
        self.assertEqual((answered[0][0], answered[0][1]["totalEntries"]), (200, 30))

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
