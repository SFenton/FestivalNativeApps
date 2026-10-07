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


class PlayerBandsScenarioTests(unittest.TestCase):
    """``--player-bands fail-once`` (issue #312) fails each distinct player-bands read once."""

    def test_first_read_per_path_fails_and_the_retry_passes(self):
        seen: set[str] = set()
        duos = "/api/player/fixture-player-1/bands?group=duos&page=1&pageSize=6"
        trios = "/api/player/fixture-player-1/bands?group=trios&page=1&pageSize=6"
        self.assertEqual([f.player_bands_failure(p, seen) for p in (duos, trios, duos, trios)], [True, True, False, False])
        for path in ("/api/player/fixture-player-1", "/api/player/fixture-player-1/history", "/api/songs"):
            self.assertFalse(f.player_bands_failure(path, seen), path)

    def test_install_answers_500_then_defers(self):
        original = ms.FixtureHandler.do_GET
        served, answered = [], []
        ms.FixtureHandler.do_GET = lambda handler: served.append(handler.path)
        try:
            f.install_player_bands("fail-once")
            handler = type("H", (), {"_json": lambda self, status, body: answered.append((self.path, status))})
            path = "/api/player/fixture-player-1/bands?group=quads&page=1&pageSize=6"
            for p in (path, path, "/api/songs"):
                ms.FixtureHandler.do_GET(type("H", (handler,), {"path": p})())
        finally:
            ms.FixtureHandler.do_GET = original
        self.assertEqual(answered, [(path, 500)])
        self.assertEqual(served, [path, "/api/songs"])

    def test_take_player_bands(self):
        self.assertEqual(f.take_player_bands(["--port", "0"]), (None, ["--port", "0"]))
        self.assertEqual(f.take_player_bands(["--player-bands", "fail-once", "--port", "0"]), ("fail-once", ["--port", "0"]))
        self.assertEqual(f.take_player_bands(["--player-bands=fail-once"]), ("fail-once", []))
        for bad in (["--player-bands"], ["--player-bands", "empty"], ["--player-bands="]):
            with self.assertRaises(SystemExit):
                f.take_player_bands(bad)


class BoardPagesScenarioTests(unittest.TestCase):
    """``--board-pages flaky`` (issue #283) fails each later board page once per pair of reads."""

    SONG = "/api/leaderboard/fixture-pulse/Solo_Guitar?top=25&offset=25"
    FULL = "/api/rankings/Solo_Guitar?rankBy=totalscore&page=2&pageSize=25"
    BAND = "/api/rankings/bands/Band_Duets?rankBy=totalscore&page=2&pageSize=25"

    def test_only_later_pages_of_paged_boards(self):
        for path in (self.SONG, self.FULL, self.BAND):
            self.assertTrue(f.is_later_board_page(path), path)
        for path in ("/api/leaderboard/fixture-pulse/Solo_Guitar?top=25&offset=0",
                     "/api/leaderboard/fixture-pulse/Solo_Guitar?top=25",
                     "/api/leaderboard/fixture-pulse/all?top=10",
                     "/api/leaderboard/fixture-pulse/bands/Band_Duets?top=25&offset=25",
                     "/api/rankings/Solo_Guitar?rankBy=totalscore&page=1&pageSize=25",
                     "/api/rankings/Solo_Guitar/fixture-player-1",
                     "/api/rankings/bands/Band_Duets?teamKey=fixture-team-1&page=2",
                     "/api/rankings/Solo_Guitar?page=two", "/api/songs"):
            self.assertFalse(f.is_later_board_page(path), path)

    def test_each_page_fails_then_its_retry_passes(self):
        reads: dict[str, int] = {}
        sequence = (self.SONG, self.FULL, self.SONG, self.FULL, self.BAND, self.BAND, self.SONG)
        self.assertEqual([f.board_page_fails(p, reads) for p in sequence], [True, True, False, False, True, False, True])
        self.assertFalse(f.board_page_fails("/api/rankings/Solo_Guitar?page=1", reads))

    def test_install_answers_500_then_defers(self):
        original = ms.FixtureHandler.do_GET
        served, answered = [], []
        ms.FixtureHandler.do_GET = lambda handler: served.append(handler.path)
        try:
            f.install_board_pages("flaky")
            handler = type("H", (), {"_json": lambda self, status, body: answered.append((self.path, status))})
            for p in (self.BAND, self.BAND, "/api/songs"):
                ms.FixtureHandler.do_GET(type("H", (handler,), {"path": p})())
        finally:
            ms.FixtureHandler.do_GET = original
        self.assertEqual(answered, [(self.BAND, 500)])
        self.assertEqual(served, [self.BAND, "/api/songs"])

    def test_take_board_pages(self):
        self.assertEqual(f.take_board_pages(["--port", "0"]), (None, ["--port", "0"]))
        self.assertEqual(f.take_board_pages(["--board-pages", "flaky", "--port", "0"]), ("flaky", ["--port", "0"]))
        self.assertEqual(f.take_board_pages(["--board-pages=flaky"]), ("flaky", []))
        for bad in (["--board-pages"], ["--board-pages", "down"], ["--board-pages="]):
            with self.assertRaises(SystemExit):
                f.take_board_pages(bad)


class SongBandTotalsTests(unittest.TestCase):
    """``--song-band-totals`` flags only per-size song band board reads (issue #317)."""

    def test_flags_only_per_size_band_boards(self):
        for path in ("/api/leaderboard/fixture-pulse/bands/Band_Duets?top=25&offset=0",
                     "/api/leaderboard/fixture-orbit/bands/Band_Quad"):
            self.assertTrue(f.song_band_totals(path, {"entries": []})["showLeaderboardEntryTotals"], path)
        for path in ("/api/leaderboard/fixture-pulse/bands/all", "/api/leaderboard/fixture-pulse/Solo_Guitar",
                     "/api/rankings/bands/Band_Duets"):
            self.assertNotIn("showLeaderboardEntryTotals", f.song_band_totals(path, {"entries": []}), path)
        self.assertIsNone(f.song_band_totals("/api/leaderboard/fixture-pulse/bands/Band_Duets", None))

    def test_install_wraps_each_response(self):
        original = ms.FixtureHandler.do_GET
        sent = []

        class Handler:
            path = "/api/leaderboard/fixture-pulse/bands/Band_Trios?top=25"

            def _json(self, status, payload, *, etag=None):
                sent.append((status, payload, etag))

        ms.FixtureHandler.do_GET = lambda handler: handler._json(200, {"totalEntries": 0}, etag="e")
        try:
            f.install_song_band_totals()
            handler = Handler()
            ms.FixtureHandler.do_GET(handler)
        finally:
            ms.FixtureHandler.do_GET = original
        self.assertEqual(sent, [(200, {"totalEntries": 0, "showLeaderboardEntryTotals": True}, "e")])
        self.assertNotIn("_json", vars(handler))


class SongBandSlowTests(unittest.TestCase):
    """``--song-band-slow`` holds only the chosen size's per-size song band board reads (issue #317 review)."""

    def test_take_song_band_slow(self):
        self.assertEqual(f.take_song_band_slow(["--port", "1", "--song-band-slow", "Band_Quad"]), ("Band_Quad", ["--port", "1"]))
        self.assertEqual(f.take_song_band_slow(["--song-band-slow=Band_Trios", "--x"]), ("Band_Trios", ["--x"]))
        self.assertEqual(f.take_song_band_slow(["--port", "1"]), (None, ["--port", "1"]))
        for bad in (["--song-band-slow"], ["--song-band-slow", "Quads"], ["--song-band-slow="]):
            with self.assertRaises(SystemExit):
                f.take_song_band_slow(bad)

    def test_delay_only_for_the_slowed_size(self):
        slow = f.SLOW_SONG_BAND_SECONDS
        self.assertEqual(f.song_band_delay("/api/leaderboard/fixture-pulse/bands/Band_Quad?top=25&offset=0", "Band_Quad"), slow)
        for path in ("/api/leaderboard/fixture-pulse/bands/Band_Duets", "/api/leaderboard/fixture-pulse/bands/all",
                     "/api/rankings/bands/Band_Quad"):
            self.assertEqual(f.song_band_delay(path, "Band_Quad"), 0.0, path)
        self.assertEqual(f.song_band_delay("/api/leaderboard/fixture-pulse/bands/Band_Quad", None), 0.0)

    def test_install_sleeps_then_serves(self):
        original = ms.FixtureHandler.do_GET
        served, slept = [], []

        class Handler:
            path = "/api/leaderboard/fixture-pulse/bands/Band_Quad"

        ms.FixtureHandler.do_GET = lambda handler: served.append(handler.path)
        sleep = f.time.sleep
        f.time.sleep = slept.append
        try:
            f.install_song_band_slow("Band_Quad")
            ms.FixtureHandler.do_GET(Handler())
            Handler.path = "/api/leaderboard/fixture-pulse/bands/Band_Duets"
            ms.FixtureHandler.do_GET(Handler())
        finally:
            ms.FixtureHandler.do_GET = original
            f.time.sleep = sleep
        self.assertEqual(slept, [f.SLOW_SONG_BAND_SECONDS])
        self.assertEqual(len(served), 2)


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


class RivalDetailStateTests(unittest.TestCase):
    """Rival Detail's loading, flaky, frozen and down accounts (issue #284) touch only song-rival detail reads."""

    RIVAL = "f1c749eb07c32578cfa3e59ec38c03a8"

    def test_state_comes_from_the_viewing_account(self):
        for account, state in (("fixture-player-detail-loading", "slow"), ("fixture-player-detail-flaky", "flaky"),
                               ("fixture-player-detail-frozen", "frozen"), ("fixture-player-detail-down", "down"),
                               ("fixture-player-1", None)):
            path = f"/api/player/{account}/rivals/Solo_Guitar/{self.RIVAL}?limit=0&sort=closest"
            self.assertEqual(f.rival_detail_state(path), state, account)
        for path in ("/api/player/fixture-player-detail-frozen/rivals/Solo_Guitar",
                     "/api/player/fixture-player-detail-frozen/rivals/all",
                     f"/api/player/fixture-player-detail-frozen/leaderboard-rivals/Solo_Guitar/{self.RIVAL}", "/api/songs"):
            self.assertIsNone(f.rival_detail_state(path), path)

    def test_loading_marker_does_not_slow_the_lists(self):
        self.assertEqual(f.rivals_list_delay("/api/player/fixture-player-detail-loading/rivals/Solo_Guitar"), 0.0)
        self.assertTrue(0 < f.SLOW_DETAIL_SECONDS < 30)

    def test_flaky_reads_alternate_per_path(self):
        reads: dict[str, int] = {}
        a, b = "/a", "/b"
        self.assertEqual([f.flaky_detail_fails(p, reads) for p in (a, a, b, a, a, b)], [True, False, True, True, False, False])

    def test_rivals_all_rebuilds_the_demo_detail(self):
        body = f.rivals_all_body("fixture-player-detail-frozen")
        detail = ms.RIVAL_DETAIL_DEMO
        entry = body["combos"][0]["above"][0]
        self.assertEqual((body["accountId"], entry["accountId"]), ("fixture-player-detail-frozen", detail["rival"]["accountId"]))
        self.assertEqual(len(entry["samples"]), len(detail["songs"]))
        for sample, row in zip(entry["samples"], detail["songs"]):
            self.assertEqual((body["songs"][sample["s"]], sample["i"], sample["ur"], sample["rr"]),
                             (row["songId"], row["instrument"], row["userRank"], row["rivalRank"]))
        self.assertEqual(entry["aheadCount"] + entry["behindCount"], entry["sharedSongCount"])

    def test_install_serves_each_state(self):
        original = ms.FixtureHandler.do_GET
        served, answered, statuses, slept = [], [], [], []
        ms.FixtureHandler.do_GET = lambda handler: served.append(handler.path)
        real_sleep = f.time.sleep
        f.time.sleep = slept.append
        f._detail_reads.clear()

        class Handler:
            def _json(self, status, body):
                answered.append((self.path, status, body))

            def send_response(self, status):
                statuses.append((self.path, status))

            def send_header(self, *_):
                pass

            def end_headers(self):
                pass

        detail = f"/rivals/Solo_Guitar/{self.RIVAL}?limit=0&sort=closest"
        try:
            f.install_rival_detail_states()
            for path in (f"/api/player/fixture-player-detail-loading{detail}",
                         f"/api/player/fixture-player-detail-flaky{detail}", f"/api/player/fixture-player-detail-flaky{detail}",
                         f"/api/player/fixture-player-detail-frozen{detail}", "/api/player/fixture-player-detail-frozen/rivals/all",
                         "/api/player/fixture-player-1/rivals/all", f"/api/player/fixture-player-detail-down{detail}",
                         f"/api/player/fixture-player-detail-down{detail}"):
                ms.FixtureHandler.do_GET(type("H", (Handler,), {"path": path})())
        finally:
            ms.FixtureHandler.do_GET = original
            f.time.sleep = real_sleep
        self.assertEqual(slept, [f.SLOW_DETAIL_SECONDS])
        self.assertEqual(served, [f"/api/player/fixture-player-detail-loading{detail}",
                                  f"/api/player/fixture-player-detail-flaky{detail}", "/api/player/fixture-player-1/rivals/all"])
        self.assertEqual([(p, s) for p, s, _ in answered],
                         [(f"/api/player/fixture-player-detail-flaky{detail}", 500),
                          ("/api/player/fixture-player-detail-frozen/rivals/all", 200),
                          (f"/api/player/fixture-player-detail-down{detail}", 500),
                          (f"/api/player/fixture-player-detail-down{detail}", 500)])
        self.assertEqual(statuses, [(f"/api/player/fixture-player-detail-frozen{detail}", 503)])


if __name__ == "__main__":
    unittest.main()
