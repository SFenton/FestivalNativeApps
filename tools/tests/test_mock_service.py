"""Exercise fixture pinning and prevent accidental live-style mutation."""

import hashlib
import json
import threading
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from tools.mock_service import (
    DEMO_SONGS, FixtureHandler, FixtureServer, ROOT,
    fixture_artwork, fixture_path_image,
    _band_detail, _band_ranking_entry, _ranking_entry, _song_band_leaderboard_entry,
)


class MockServiceTests(unittest.TestCase):
    """Use a dynamic loopback port so tests cannot target the live service."""

    def setUp(self):
        """Start one isolated, read-only fixture listener."""
        self.server = FixtureServer(("127.0.0.1", 0), FixtureHandler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        """Stop the named test server and release its bound port."""
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def test_publication_and_catalogue_etag(self):
        """Catalogue ETags and generation pins reproduce offline-client semantics."""
        with urlopen(self.base + "/__fixture__/health") as response:
            identity = json.load(response)
        self.assertTrue(identity["ready"])
        self.assertEqual(identity["options"], {
            "unpinned": False, "rolloverOnRead": None,
            "rolloverOnCommand": False,
            "mismatchedShopRollover": False,
            "failFirstWhiteCatalogue": False,
            "stopAfterFirstSongs": False,
            "stopAfterFirstScore": False,
            "stopAfterFirstShop": False,
            "metadataEdge": False,
            "largeRankings": False,
            "largeCatalogue": False,
            "longTitles": False,
            "serviceInfoDiscovery": False,
            "songLeaderboardPaging": False,
        })
        self.assertEqual(set(identity["sourceHashes"]), {
            "tools/mock_service.py",
            "contracts/fixtures/publication.json",
            "contracts/fixtures/songs-empty.json",
            "contracts/fixtures/songs-demo.json",
            "contracts/fixtures/path-demo.json",
            "contracts/fixtures/shop-demo.json",
            "contracts/fixtures/player-demo.json",
            "contracts/fixtures/player-rank-history-demo.json",
            "contracts/fixtures/metadata-edge.json",
            "contracts/fixtures/rivals-list-demo.json",
            "contracts/fixtures/leaderboard-rivals-demo.json",
            "contracts/fixtures/rival-detail-demo.json",
            "contracts/fixtures/leaderboard-rival-detail-demo.json",
        })
        for name, digest in identity["sourceHashes"].items():
            self.assertEqual(
                digest, hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
            )
        with urlopen(self.base + "/api/publication") as response:
            self.assertEqual(json.load(response)["publicationId"], 7)
        with urlopen(self.base + "/api/songs") as response:
            catalogue = json.load(response)
            self.assertEqual(catalogue["count"], 2)
            self.assertEqual(catalogue["songs"][0]["songId"], "fixture-pulse")
            etag = response.headers["ETag"]
        request = Request(self.base + "/api/songs", headers={"If-None-Match": etag})
        with self.assertRaises(HTTPError) as error:
            urlopen(request)
        self.assertEqual(error.exception.code, 304)
        self.assertEqual(error.exception.headers["X-FST-Publication-Id"], "7")
        with urlopen(self.base + "/api/songs?scenario=empty") as response:
            self.assertEqual(json.load(response)["count"], 0)

    def test_service_info_and_version_are_idle_operational_reads(self):
        """Settings Service Info reads an idle, unfrozen contract-2 body and a version."""
        with urlopen(self.base + "/api/service-info") as response:
            info = json.load(response)
        self.assertEqual(info["contractVersion"], 2)
        self.assertEqual(info["currentUpdate"]["status"], "idle")
        self.assertFalse(info["publication"]["publicReadsFrozen"])
        self.assertEqual(info["workerStatus"]["status"], "online")
        with urlopen(self.base + "/api/version") as response:
            self.assertEqual(json.load(response), {"version": "fixture"})

    def test_rival_detail_accepts_the_web_query_shape(self):
        """Rival detail takes the web's `limit=0&sort=closest[&allowLiveFallback=true]` (#95)."""
        detail = self.base + "/api/player/fixture-riv/rivals/03/f1c749eb07c32578cfa3e59ec38c03a8"
        for query in ("?limit=0&sort=closest", "?limit=0&sort=closest&allowLiveFallback=true"):
            with urlopen(detail + query) as response:
                self.assertEqual(json.load(response)["combo"], "03")
        for query in ("?limit=0&sort=closest&allowLiveFallback=maybe", "?limit=0&sort=closest&extra=1"):
            with self.assertRaises(HTTPError) as error:
                urlopen(detail + query)
            self.assertEqual(error.exception.code, 400)

    def test_service_info_discovery_fixture_reports_attempt_progress(self):
        """The opt-in discovery body carries the web's schema-1 attempt counts."""
        server = FixtureServer(("127.0.0.1", 0), FixtureHandler, service_info_discovery=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with urlopen(f"http://127.0.0.1:{server.server_port}/api/service-info") as response:
                current = json.load(response)["currentUpdate"]
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        self.assertEqual(current["status"], "updating")
        self.assertEqual(current["phaseId"], "post.registered_player_band_discovery")
        self.assertEqual(current["attemptProgress"], {
            "schemaVersion": 1, "attemptedThisPass": 1310, "retryableUnavailableThisPass": 70,
        })

    def test_ranking_and_band_accuracy_use_the_live_ten_thousandths_scale(self):
        """Accuracy fields match production (`1000000` = 100%), never a 0–1 fraction or per-mille."""
        rows = [
            _ranking_entry(1, "fixture-player-1", "Player"),
            _band_ranking_entry(1), _band_detail("fixture-team-1", 1, "Band_Duets"),
        ]
        values = [row["avgAccuracy"] for row in rows]
        song_row = _song_band_leaderboard_entry(1, "Band_Duets")
        values += [song_row["accuracy"], *(m["accuracy"] for m in song_row["members"])]
        for value in values:
            with self.subTest(value=value):
                self.assertGreaterEqual(value, 500_000)
                self.assertLessEqual(value, 1_000_000)

    def test_song_band_previews_read_every_size_and_append_the_selected_band(self):
        """`/bands/all` is not swallowed by the per-size route and echoes `accountId`."""
        with urlopen(self.base + "/api/leaderboard/fixture-pulse/bands/all?top=10") as response:
            body = json.load(response)
        self.assertEqual(body["songId"], "fixture-pulse")
        self.assertEqual([band["bandType"] for band in body["bands"]],
                         ["Band_Duets", "Band_Trios", "Band_Quad"])
        self.assertEqual(body["bands"][0]["count"], 2)
        self.assertIsNone(body["bands"][0]["selectedPlayerEntry"])
        self.assertEqual(body["bands"][1]["entries"], [])
        with urlopen(self.base + "/api/leaderboard/fixture-pulse/bands/all?top=10"
                     "&accountId=fixture-player-1") as response:
            selected = json.load(response)["bands"][0]["selectedPlayerEntry"]
        self.assertEqual(selected["rank"], 29)
        self.assertEqual(selected["members"][0]["accountId"], "fixture-player-1")
        with self.assertRaises(HTTPError) as error:
            urlopen(self.base + "/api/leaderboard/fixture-pulse/bands/all?top=51")
        self.assertEqual(error.exception.code, 400)

    def test_song_band_board_holds_the_appended_band_at_its_rank(self):
        """The full Duos board lists the rank-29 band Song Detail appends on page 2 and
        returns it as `selectedPlayerEntry` for the pinned footer (issue #307)."""
        board = "/api/leaderboard/fixture-pulse/bands/Band_Duets?top=25"
        with urlopen(self.base + board + "&offset=0") as response:
            first = json.load(response)
        self.assertEqual(first["totalEntries"], 29)
        self.assertEqual([e["rank"] for e in first["entries"]], list(range(1, 26)))
        self.assertIsNone(first["selectedPlayerEntry"])
        with urlopen(self.base + board + "&offset=25&accountId=fixture-player-1") as response:
            second = json.load(response)
        self.assertEqual([e["rank"] for e in second["entries"]], [26, 27, 28, 29])
        self.assertEqual(second["entries"][-1]["bandId"], "fixture-band-fixture-player-1")
        self.assertEqual(second["selectedPlayerEntry"], second["entries"][-1])
        self.assertIsNone(second["selectedBandEntry"])
        with urlopen(self.base + "/api/leaderboard/fixture-pulse/bands/all?top=10"
                     "&accountId=fixture-player-1") as response:
            duets = json.load(response)["bands"][0]
        self.assertEqual(duets["selectedPlayerEntry"], second["entries"][-1])
        with self.assertRaises(HTTPError) as error:
            urlopen(self.base + board + "&offset=0&accountId=a&accountId=b")
        self.assertEqual(error.exception.code, 400)

    def test_song_band_page_returns_the_selected_players_band_for_the_footer(self):
        """`/bands/{bandType}?accountId=` adds the player's band; no player or no rows adds none."""
        path = "/api/leaderboard/fixture-pulse/bands/Band_Duets?top=25&offset=0"
        with urlopen(self.base + path) as response:
            self.assertIsNone(json.load(response)["selectedPlayerEntry"])
        with urlopen(self.base + path + "&accountId=fixture-player-1") as response:
            body = json.load(response)
        selected = body["selectedPlayerEntry"]
        self.assertEqual((selected["rank"], selected["bandType"]), (29, "Band_Duets"))
        self.assertEqual(selected["members"][0]["accountId"], "fixture-player-1")
        self.assertEqual(body["totalEntries"], 29)
        with urlopen(self.base + "/api/leaderboard/fixture-pulse/bands/Band_Trios?top=25&offset=0"
                     "&accountId=fixture-player-1") as response:
            self.assertIsNone(json.load(response)["selectedPlayerEntry"])
        with self.assertRaises(HTTPError) as error:
            urlopen(self.base + path + "&accountId=fixture-player-1&accountId=fixture-player-2")
        self.assertEqual(error.exception.code, 400)

    def test_large_rankings_mode_pages_deep_and_keeps_default_small(self):
        """`--large-rankings` pads rows for pagers; the default roster stays three accounts."""
        with urlopen(self.base + "/api/rankings/Solo_Guitar?page=1&pageSize=25") as response:
            self.assertEqual(json.load(response)["totalAccounts"], 3)
        large = FixtureServer(("127.0.0.1", 0), FixtureHandler, large_rankings=True)
        thread = threading.Thread(target=large.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{large.server_port}"
        try:
            with urlopen(base + "/api/rankings/Solo_Guitar?page=48&pageSize=25") as response:
                body = json.load(response)
            self.assertEqual(body["totalAccounts"], 1_200)
            self.assertEqual(len(body["entries"]), 25)
            self.assertEqual(body["entries"][-1]["accountId"], "fixture-rank-1200")
            self.assertTrue(all(e["totalScore"] > 0 and e["adjustedSkillRating"] > 0 for e in body["entries"]))
            with urlopen(base + "/api/rankings/Solo_Guitar/fixture-rank-600") as response:
                self.assertEqual(json.load(response)["totalScoreRank"], 600)
            with urlopen(base + "/api/rankings/bands/Band_Duets?page=24&pageSize=25") as response:
                bands = json.load(response)
            self.assertEqual(bands["totalTeams"], 600)
            self.assertEqual(len(bands["entries"]), 25)
        finally:
            large.shutdown()
            large.server_close()
            thread.join(timeout=2)

    def test_large_catalogue_mode_adds_every_section_and_serves_their_charts(self):
        """`--large-catalogue` appends synthetic songs across #, A–Z; default stays two songs."""
        with urlopen(self.base + "/api/songs") as response:
            self.assertEqual(json.load(response)["count"], 2)
        large = FixtureServer(("127.0.0.1", 0), FixtureHandler, large_catalogue=True)
        thread = threading.Thread(target=large.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{large.server_port}"
        try:
            with urlopen(base + "/api/songs") as response:
                body = json.load(response)
            self.assertEqual(body["count"], len(body["songs"]))
            self.assertGreaterEqual(body["count"], 100)
            initials = {song["title"][0] for song in body["songs"]}
            self.assertTrue(set("ABCDEFGHIJKLMNOPQRSTUVWXYZ") <= {c.upper() for c in initials})
            self.assertTrue(any(c.isdigit() for c in initials))
            self.assertEqual(len({song["songId"] for song in body["songs"]}), body["count"])
            with urlopen(base + "/api/leaderboard/fixture-song-5/Solo_Guitar?top=10") as response:
                self.assertEqual(len(json.load(response)["entries"]), 10)
        finally:
            large.shutdown()
            large.server_close()
            thread.join(timeout=2)

    def test_long_titles_mode_retitles_only_the_scrollable_song(self):
        """`--long-titles` widens `fixture-pulse`'s title; its boards still scroll."""
        with urlopen(self.base + "/api/songs") as response:
            default = json.load(response)
        server = FixtureServer(("127.0.0.1", 0), FixtureHandler, long_titles=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_port}"
        try:
            with urlopen(base + "/api/songs") as response:
                etag = response.headers["ETag"]
                body = json.load(response)
            self.assertNotEqual(etag, '"fst-fixture-songs-v1"')
            titles = {song["songId"]: song["title"] for song in body["songs"]}
            self.assertGreaterEqual(len(titles["fixture-pulse"]), 90)
            for song in default["songs"]:
                if song["songId"] != "fixture-pulse":
                    self.assertEqual(titles[song["songId"]], song["title"])
            with urlopen(base + "/api/leaderboard/fixture-pulse/Solo_Guitar?top=25") as response:
                self.assertGreaterEqual(len(json.load(response)["entries"]), 20)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_song_leaderboard_paging_mode_slows_later_pages_and_fails_the_last(self):
        """`--song-leaderboard-paging`: four Lead pages, later ones slow, page 4 fails (#316)."""
        from tools import mock_service
        with urlopen(self.base + "/api/leaderboard/fixture-pulse/Solo_Guitar?top=25") as response:
            self.assertEqual(json.load(response)["totalEntries"], 26)
        paging = FixtureServer(("127.0.0.1", 0), FixtureHandler, song_leaderboard_paging=True)
        thread = threading.Thread(target=paging.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{paging.server_port}/api/leaderboard/fixture-pulse/Solo_Guitar"
        try:
            with patch.object(mock_service.time, "sleep") as sleep:
                with urlopen(base + "?top=25") as response:
                    first = json.load(response)
                sleep.assert_not_called()
                self.assertEqual(first["totalEntries"], 100)
                self.assertEqual(len(first["entries"]), 25)
                with urlopen(base + "?top=25&offset=50") as response:
                    third = json.load(response)
                self.assertEqual([e["rank"] for e in third["entries"]][:1], [51])
                sleep.assert_called_with(mock_service.SLOW_SONG_LEADERBOARD_PAGE_SECONDS)
                with self.assertRaises(HTTPError) as failure:
                    urlopen(base + "?top=25&offset=75")
                self.assertEqual(failure.exception.code, 500)
            with urlopen(f"http://127.0.0.1:{paging.server_port}"
                         "/api/leaderboard/fixture-pulse/Solo_Bass?top=25") as response:
                self.assertEqual(json.load(response)["totalEntries"], 0)
        finally:
            paging.shutdown()
            paging.server_close()
            thread.join(timeout=2)

    def test_multi_instrument_song_history_feeds_instrument_switching(self):
        """`fixture-history-multi` has Lead (pages), Bass (one page) and gold Drums rows."""
        with urlopen(self.base + "/api/player/fixture-history-multi/history?songId=fixture-pulse") as response:
            body = json.load(response)
        counts = {}
        for row in body["history"]:
            counts[row["instrument"]] = counts.get(row["instrument"], 0) + 1
            self.assertEqual(row["songId"], "fixture-pulse")
            self.assertLessEqual(row["accuracy"], 1000000)
        self.assertEqual(counts, {"Solo_Guitar": 8, "Solo_Bass": 2, "Solo_Drums": 3})
        self.assertEqual(body["count"], 13)
        self.assertTrue(any(row["isFullCombo"] and row["accuracy"] == 1000000 for row in body["history"]))

    def test_player_rank_history_is_a_bounded_pure_read(self):
        """Demo players get the committed 7-day series; others are unranked, not 404."""
        route = "/api/rankings/Solo_Guitar/fixture-player-1/history?days=30"
        with urlopen(self.base + route) as response:
            body = json.load(response)
        self.assertEqual(body["instrument"], "Solo_Guitar")
        self.assertEqual(body["accountId"], "fixture-player-1")
        self.assertEqual(len(body["history"]), 7)
        with urlopen(self.base + "/api/rankings/Solo_Bass/fixture-empty/history") as response:
            self.assertEqual(json.load(response)["history"], [])
        for bad in (
            "/api/rankings/Nope/fixture-player-1/history",
            "/api/rankings/Solo_Guitar/fixture-player-1/history?unexpected=1",
        ):
            with self.subTest(route=bad), self.assertRaises(HTTPError) as failure:
                urlopen(self.base + bad)
            self.assertIn(failure.exception.code, {400, 404})

    def test_paged_leaderboard_and_original_artwork(self):
        """One page of 25 and one page of one share a 26-entry total."""
        with urlopen(self.base + "/api/leaderboard/fixture-pulse/Solo_Guitar?top=25&offset=0") as response:
            first = json.load(response)
        self.assertEqual(first["count"], 25)
        self.assertEqual(first["localEntries"], 26)
        self.assertEqual(first["entries"][0]["accuracy"], 979_999)
        self.assertFalse(first["entries"][0]["isFullCombo"])
        self.assertNotIn("accuracy", first["entries"][2])
        self.assertFalse(first["entries"][2]["isFullCombo"])
        self.assertNotIn("accuracy", first["entries"][3])
        self.assertTrue(first["entries"][3]["isFullCombo"])
        self.assertEqual(first["entries"][25 - 1]["rank"], 25)
        with urlopen(self.base + "/api/leaderboard/fixture-pulse/Solo_Guitar?top=25&offset=25") as response:
            second = json.load(response)
        self.assertEqual(second["count"], 1)
        self.assertEqual(second["entries"][0]["rank"], 26)
        with urlopen(self.base + "/__fixture__/last-score-query") as response:
            self.assertEqual(json.load(response)["last"], {
                "top": 25, "offset": 25, "leeway": None,
            })
        with urlopen(
            self.base + "/api/leaderboard/fixture-pulse/Solo_Guitar?leeway=1.5"
        ):
            pass
        with urlopen(self.base + "/__fixture__/last-score-query") as response:
            self.assertEqual(json.load(response)["last"]["leeway"], 1.5)
        with urlopen(
            self.base + "/api/leaderboard/fixture-pulse/Solo_Guitar?top=10&offset=0"
        ):
            pass
        with urlopen(self.base + "/__fixture__/last-score-query") as response:
            self.assertEqual(json.load(response)["last"]["top"], 10)
        with urlopen(self.base + "/__fixture__/last-full-score-query") as response:
            self.assertEqual(json.load(response)["last"], {
                "top": 25, "offset": 0, "leeway": 1.5,
            })
        with urlopen(self.base + "/__fixture__/art/pulse.png") as response:
            self.assertEqual(response.headers["Content-Type"], "image/png")
            self.assertEqual(response.read()[:8], b"\x89PNG\r\n\x1a\n")
        self.assertNotEqual(fixture_artwork("pulse"), fixture_artwork("orbit"))
        asset = ROOT / "apple/Tests/FestivalUITests/Fixtures/pulse.png"
        self.assertEqual(asset.read_bytes(), fixture_artwork("pulse"))

    def test_account_search_is_bounded_and_does_not_accept_selected_headers(self):
        """Player search returns only synthetic names and distinguishes a 403 from empty."""
        with urlopen(self.base + "/api/account/search?q=Fixture%20Player&limit=10") as response:
            players = json.load(response)["results"]
        self.assertEqual([player["accountId"] for player in players], [
            "fixture-player-1", "fixture-player-2",
        ])
        with urlopen(self.base + "/api/account/search?q=Fixture&limit=1") as response:
            self.assertEqual(len(json.load(response)["results"]), 1)
        with urlopen(self.base + "/api/account/search?q=missing&limit=10") as response:
            self.assertEqual(json.load(response), {"results": []})
        with urlopen(self.base + "/api/account/search?q=C%2B%2B&limit=10") as response:
            self.assertEqual(
                [player["accountId"] for player in json.load(response)["results"]],
                ["fixture-cpp"],
            )
        with self.assertRaises(HTTPError) as lost_plus:
            urlopen(self.base + "/api/account/search?q=C++&limit=10")
        self.assertEqual(lost_plus.exception.code, 400)
        with urlopen(self.base + "/api/account/search?q=Fi&limit=10") as response:
            self.assertEqual(len(json.load(response)["results"]), 2)
        with urlopen(self.base + "/api/account/search?q=Pl&limit=10") as response:
            self.assertEqual(json.load(response), {"results": []})
        with patch("tools.mock_service.SLOW_ACCOUNT_SEARCH_SECONDS", 0), \
                urlopen(self.base + "/api/account/search?q=slowpoke&limit=10") as response:
            self.assertEqual(json.load(response), {"results": []})
        for route, expected in (
            ("/api/account/search?q=blocked&limit=10", 403),
            ("/api/account/search?q=busy&limit=10", 503),
            ("/api/account/search?q=rate&limit=10", 429),
            ("/api/account/search?q=Fi&limit=0", 400),
            ("/api/account/search?q=Fi&limit=11", 400),
            ("/api/account/search?q=Fi&limit=x", 400),
            ("/api/account/search?q=F&limit=10", 400),
            ("/api/account/search?q=Fi&q=other&limit=10", 400),
            ("/api/bands/search?q=fixture", 404),
        ):
            with self.subTest(route=route), self.assertRaises(HTTPError) as failure:
                urlopen(self.base + route)
            self.assertEqual(failure.exception.code, expected)
        for header in ("X-FST-Selected-Player", "X-FST-Selected-Band-Id", "X-API-Key"):
            with self.subTest(header=header), self.assertRaises(HTTPError) as failure:
                urlopen(Request(
                    self.base + "/api/account/search?q=Fixture&limit=10",
                    headers={header: "synthetic"},
                ))
            self.assertEqual(failure.exception.code, 400)

    def test_player_profiles_keep_available_syncing_empty_and_denied_distinct(self):
        """Two original accounts use compact score keys without mutation-shaped GETs."""
        with urlopen(Request(
            self.base + "/api/player/fixture-player-1",
            headers={"X-FST-Publication-Id": "7"},
        )) as response:
            first = json.load(response)
            self.assertEqual(response.headers["X-FST-Publication-Id"], "7")
        self.assertEqual(first["totalScores"], 2)
        self.assertEqual(first["scores"][0]["si"], "fixture-pulse")
        self.assertEqual(first["scores"][0]["ins"], "01")
        self.assertEqual(first["scores"][0]["acc"], 979)
        self.assertFalse(first["scores"][0]["fc"])
        self.assertTrue(all(row["ins"] == "01" for row in first["scores"]))
        with urlopen(self.base + "/api/player/fixture-player-2") as response:
            second = json.load(response)
        self.assertEqual(second["totalScores"], 3)
        self.assertTrue(second["scores"][0]["fc"])
        self.assertNotEqual(second["scores"][0]["sc"], first["scores"][0]["sc"])
        self.assertEqual(second["scores"][-1]["ins"], "04")
        self.assertGreater(second["scores"][-1]["sc"], 0)
        with urlopen(self.base + "/api/player/fixture-empty") as response:
            empty = json.load(response)
        self.assertEqual(empty["totalScores"], 0)
        self.assertEqual(empty["scores"], [])
        with urlopen(self.base + "/api/player/fixture-syncing") as response:
            syncing = json.load(response)
            self.assertEqual(response.status, 202)
        self.assertEqual(syncing["status"], "syncing")
        self.assertTrue(syncing["notYetPublished"])
        self.assertEqual(syncing["scores"], [])
        for route, expected in (
            ("/api/player/fixture-denied", 403),
            ("/api/player/fixture-player-1?leeway=1", 400),
        ):
            with self.subTest(route=route), self.assertRaises(HTTPError) as error:
                urlopen(self.base + route)
            self.assertEqual(error.exception.code, expected)
        with urlopen(self.base + "/api/player/fixture-missing") as response:
            unknown = json.load(response)
        self.assertEqual(unknown["accountId"], "fixture-missing")
        self.assertEqual(unknown["scores"], [])
        self.assertIsNone(unknown["displayName"])
        stale = Request(
            self.base + "/api/player/fixture-player-1",
            headers={"X-FST-Publication-Id": "6"},
        )
        with self.assertRaises(HTTPError) as error:
            urlopen(stale)
        self.assertEqual(error.exception.code, 409)
        selected = Request(
            self.base + "/api/player/fixture-player-1",
            headers={"X-FST-Selected-Player": "fixture-player-1"},
        )
        with self.assertRaises(HTTPError) as error:
            urlopen(selected)
        self.assertEqual(error.exception.code, 400)
        tracking = Request(
            self.base + "/api/player/fixture-player-1/track", data=b"{}", method="POST"
        )
        with self.assertRaises(HTTPError) as error:
            urlopen(tracking)
        self.assertEqual(error.exception.code, 405)

    def test_feedback_fixture_follows_the_service_contract(self):
        """The feedback fixture queues jobs, reports their status and refuses keys (issue #78)."""
        def post(title: str, headers: dict, fields=("kind", "platform", "description")) -> Request:
            values = {"kind": "bug", "platform": "ios", "description": "d", "title": title}
            parts = "".join(
                f"--B\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{values[name]}\r\n"
                for name in (*fields, "title")
            )
            return Request(
                self.base + "/api/feedback", data=(parts + "--B--\r\n").encode(), method="POST",
                headers={"Content-Type": "multipart/form-data; boundary=B", **headers},
            )

        with urlopen(self.base + "/api/features") as response:
            self.assertTrue(json.load(response)["feedback"])
        with urlopen(post("[Bug] ok", {})) as response:
            self.assertEqual(response.status, 202)
            accepted = json.load(response)
        self.assertEqual(accepted["status"], "queued")
        self.assertRegex(accepted["id"], r"^[0-9a-f]{32}$")
        with urlopen(self.base + "/api/feedback/" + accepted["id"]) as response:
            status = json.load(response)
        self.assertEqual((status["status"], status["issueNumber"]), ("submitted", 1))

        with urlopen(post("[Bug] fixture-failed", {})) as response:
            failed_id = json.load(response)["id"]
        with urlopen(self.base + "/api/feedback/" + failed_id) as response:
            self.assertEqual(json.load(response)["status"], "failed")
        with self.assertRaises(HTTPError) as error:
            urlopen(self.base + "/api/feedback/" + "a" * 32)
        self.assertEqual(error.exception.code, 404)

        for title, headers, fields, code, error_code in [
            ("[Bug] fixture-unavailable", {}, ("kind", "platform", "description"), 503, "feedback_busy"),
            ("[Bug] ok", {}, ("kind", "platform"), 400, "description_required"),
            ("[Bug] ok", {"X-API-Key": "x"}, ("kind", "platform", "description"), 400, "invalid_form"),
            ("[Bug] ok", {"X-FST-Selected-Player": "p"}, ("kind", "platform", "description"), 400, "invalid_form"),
        ]:
            with self.subTest(title=title, headers=headers):
                with self.assertRaises(HTTPError) as error:
                    urlopen(post(title, headers, fields))
                self.assertEqual(error.exception.code, code)
                self.assertEqual(json.load(error.exception)["code"], error_code)
                if code == 503:
                    self.assertEqual(error.exception.headers["Retry-After"], "60")

    def test_shared_player_rows_match_both_song_leaderboards(self):
        """Never prove selection with a profile that contradicts the chart fixture."""
        with urlopen(self.base + "/api/account/search?q=Fixture%20Player&limit=10") as response:
            discovered = {player["accountId"]: player for player in json.load(response)["results"]}
        for song in ("fixture-pulse", "fixture-orbit"):
            with urlopen(
                self.base + f"/api/leaderboard/{song}/Solo_Guitar?top=2&offset=0"
            ) as response:
                chart = json.load(response)
            for entry in chart["entries"]:
                with self.subTest(song=song, account=entry["accountId"]):
                    account_id = entry["accountId"]
                    with urlopen(self.base + f"/api/player/{account_id}") as response:
                        profile = json.load(response)
                    score = next(
                        row for row in profile["scores"]
                        if row["si"] == song and row["ins"] == "01"
                    )
                    self.assertEqual(discovered[account_id]["displayName"], entry["displayName"])
                    self.assertEqual(profile["displayName"], entry["displayName"])
                    self.assertEqual(score["sc"], entry["score"])
                    self.assertEqual(score["fc"], entry["isFullCombo"])
                    self.assertEqual(score["rk"], entry["rank"])
                    self.assertEqual(score["st"], entry["stars"])
                    self.assertEqual(score["sn"], entry["season"])
                    self.assertEqual(score["acc"], entry["accuracy"] // 1000)
                    self.assertAlmostEqual(score["pct"], entry["rank"] / chart["totalEntries"])

        with urlopen(
            self.base + "/api/leaderboard/fixture-pulse/Solo_Drums?top=25&offset=0"
        ) as response:
            drums = json.load(response)
        self.assertEqual(drums["count"], 1)
        self.assertEqual(drums["totalEntries"], 1)
        with urlopen(self.base + "/api/player/fixture-player-2") as response:
            second = json.load(response)
        drum = next(
            row for row in second["scores"]
            if row["si"] == "fixture-pulse" and row["ins"] == "04"
        )
        published = drums["entries"][0]
        self.assertEqual(published["accountId"], second["accountId"])
        self.assertEqual(published["displayName"], second["displayName"])
        for profile_field, chart_field in (
            ("sc", "score"), ("rk", "rank"), ("fc", "isFullCombo"),
            ("st", "stars"), ("sn", "season"),
        ):
            self.assertEqual(drum[profile_field], published[chart_field])
        self.assertEqual(drum["acc"], published["accuracy"] // 1_000)
        self.assertEqual(drum["te"], drums["totalEntries"])
        self.assertAlmostEqual(drum["pct"], drum["rk"] / drums["totalEntries"])
        for song in ("fixture-pulse", "fixture-orbit"):
            with urlopen(
                self.base + f"/api/leaderboard/{song}/Solo_Bass?top=25&offset=0"
            ) as response:
                bass = json.load(response)
            self.assertEqual(bass["count"], 0)
            self.assertEqual(bass["totalEntries"], 0)

    def test_isolated_metadata_edge_keeps_song_profile_shop_and_chart_coherent(self):
        """Long-title and seven-digit device proof never poisons the shared Bass fixture."""
        with FixtureServer(
            ("127.0.0.1", 0), FixtureHandler, metadata_edge=True
        ) as edge:
            worker = threading.Thread(target=edge.serve_forever, daemon=True)
            worker.start()
            root = f"http://127.0.0.1:{edge.server_port}"
            try:
                with urlopen(root + "/__fixture__/health") as response:
                    health = json.load(response)
                self.assertTrue(health["options"]["metadataEdge"])
                self.assertFalse(health["options"]["unpinned"])
                self.assertEqual(
                    health["sourceHashes"]["contracts/fixtures/metadata-edge.json"],
                    hashlib.sha256(
                        (ROOT / "contracts/fixtures/metadata-edge.json").read_bytes()
                    ).hexdigest(),
                )
                with urlopen(root + "/api/songs") as response:
                    songs = json.load(response)
                    etag = response.headers["ETag"]
                self.assertEqual(songs["count"], 1)
                song = songs["songs"][0]
                self.assertEqual(song["songId"], "fixture-marathon")
                self.assertGreater(len(song["title"]), 40)
                self.assertEqual(song["durationSeconds"], 366)
                cached = Request(root + "/api/songs", headers={"If-None-Match": etag})
                with self.assertRaises(HTTPError) as not_modified:
                    urlopen(cached)
                self.assertEqual(not_modified.exception.code, 304)

                with urlopen(root + "/api/account/search?q=Fixture%20Edge&limit=10") as response:
                    results = json.load(response)["results"]
                self.assertEqual([player["accountId"] for player in results], ["fixture-edge"])
                profile_request = Request(
                    root + "/api/player/fixture-edge",
                    headers={"X-FST-Publication-Id": "7"},
                )
                with urlopen(profile_request) as response:
                    profile = json.load(response)
                self.assertEqual(profile["totalScores"], 1)
                score = profile["scores"][0]
                self.assertEqual(score["si"], song["songId"])
                self.assertEqual(score["sc"], 1_234_567)
                self.assertEqual(score["vlp"], "2026-09-20T12:34:56.1234567Z")
                with urlopen(
                    root + "/api/leaderboard/fixture-marathon/Solo_Guitar?top=10"
                ) as response:
                    chart = json.load(response)
                entry = chart["entries"][0]
                self.assertEqual(chart["count"], 1)
                self.assertEqual(chart["totalEntries"], score["te"])
                self.assertEqual(entry["accountId"], profile["accountId"])
                self.assertEqual(entry["score"], score["sc"])
                self.assertEqual(entry["accuracy"], score["acc"] * 1_000)
                self.assertEqual(entry["isFullCombo"], score["fc"])
                with urlopen(root + "/api/shop") as response:
                    shop = json.load(response)
                self.assertEqual(shop["count"], 1)
                self.assertEqual(shop["newSongs"], [song["songId"]])
                self.assertEqual(shop["songs"][0]["songId"], song["songId"])
                self.assertTrue(shop["songs"][0]["shopUrl"].startswith(
                    "https://www.fortnite.com/item-shop/jam-tracks/"
                ))
                for route in (
                    "/api/player/fixture-player-1",
                    "/api/leaderboard/fixture-pulse/Solo_Guitar",
                    "/api/leaderboard/fixture-marathon/Solo_Bass",
                ):
                    with self.subTest(route=route), self.assertRaises(HTTPError) as failure:
                        urlopen(root + route)
                    self.assertEqual(failure.exception.code, 404)
                selected = Request(
                    root + "/api/player/fixture-edge",
                    headers={"X-FST-Selected-Player": "fixture-edge"},
                )
                with self.assertRaises(HTTPError) as unsafe:
                    urlopen(selected)
                self.assertEqual(unsafe.exception.code, 400)
                with self.assertRaises(HTTPError) as post:
                    urlopen(Request(
                        root + "/api/player/fixture-edge/track", data=b"{}", method="POST"
                    ))
                self.assertEqual(post.exception.code, 405)
                with self.assertRaises(HTTPError) as ordinary:
                    urlopen(self.base + "/api/leaderboard/fixture-marathon/Solo_Guitar")
                self.assertEqual(ordinary.exception.code, 404)
            finally:
                edge.shutdown()
                worker.join(timeout=2)

    def test_public_path_artifacts_have_generation_etags_and_no_mutations(self):
        """Original JSON/PNG fixtures expose valid paths without a live service."""
        base = "/api/paths/fixture-pulse/Solo_Guitar/expert"
        with urlopen(self.base + base + "/data?generationId=fixture-path-generation") as response:
            path = json.load(response)
            text_etag = response.headers["ETag"]
            self.assertEqual(response.headers["X-FST-Publication-Id"], "7")
        self.assertEqual(path["schemaVersion"], 2)
        self.assertEqual(path["difficulty"], "expert")
        self.assertEqual(len(path["activations"]), 2)
        self.assertEqual(path["pathSummary"], "Two synthetic Expert activations")
        with urlopen(self.base + base + "?generationId=fixture-path-generation") as response:
            image = response.read()
            image_etag = response.headers["ETag"]
            self.assertEqual(response.headers["Content-Type"], "image/png")
        self.assertEqual(image, fixture_path_image("expert"))
        self.assertEqual(image[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(image[16:24], bytes.fromhex("00000100000003c0"))
        self.assertNotEqual(fixture_path_image("hard"), image)
        for route, etag in ((base + "/data", text_etag), (base, image_etag)):
            request = Request(self.base + route, headers={"If-None-Match": etag})
            with self.assertRaises(HTTPError) as cached:
                urlopen(request)
            self.assertEqual(cached.exception.code, 304)
        stale = Request(self.base + base, headers={"X-FST-Publication-Id": "6"})
        with self.assertRaises(HTTPError) as conflict:
            urlopen(stale)
        self.assertEqual(conflict.exception.code, 409)
        for route, expected in (
            (base + "/data?generationId=wrong", 404),
            ("/api/paths/fixture-orbit/Solo_Guitar/expert", 404),
            ("/api/paths/fixture-pulse/Solo_Guitar/medium/data", 404),
            ("/api/paths/fixture-pulse/Solo_PeripheralVocals/expert", 400),
            (base + "/data?generationId=fixture-path-generation&generationId=other", 400),
        ):
            with self.subTest(route=route), self.assertRaises(HTTPError) as failure:
                urlopen(self.base + route)
            self.assertEqual(failure.exception.code, expected)

    def test_public_shop_feed_is_synthetic_pinned_and_explicit_on_errors(self):
        """Shop badge states and every failure are distinct from an empty feed."""
        with urlopen(self.base + "/api/shop") as response:
            shop = json.load(response)
            etag = response.headers["ETag"]
            self.assertEqual(response.headers["X-FST-Publication-Id"], "7")
        self.assertEqual(shop["count"], 2)
        self.assertEqual(sum(song["isNew"] for song in shop["songs"]), 1)
        self.assertEqual(sum(song["leavingTomorrow"] for song in shop["songs"]), 1)
        self.assertTrue(all(
            song["shopUrl"].startswith("https://www.fortnite.com/item-shop/jam-tracks/")
            for song in shop["songs"]
        ))
        request = Request(self.base + "/api/shop", headers={"If-None-Match": etag})
        with self.assertRaises(HTTPError) as cached:
            urlopen(request)
        self.assertEqual(cached.exception.code, 304)
        self.assertEqual(cached.exception.headers["X-FST-Publication-Id"], "7")
        request = Request(self.base + "/api/shop", headers={"X-FST-Publication-Id": "6"})
        with self.assertRaises(HTTPError) as stale:
            urlopen(request)
        self.assertEqual(stale.exception.code, 409)
        with urlopen(self.base + "/api/shop?scenario=empty") as response:
            self.assertEqual(json.load(response)["count"], 0)
        with urlopen(self.base + "/api/songs?scenario=shop-empty") as response:
            self.assertEqual(json.load(response)["count"], 2)
        with urlopen(self.base + "/api/shop?scenario=shop-empty") as response:
            self.assertEqual(json.load(response)["count"], 0)
        with urlopen(self.base + "/api/songs?scenario=shop-error") as response:
            self.assertEqual(json.load(response)["count"], 2)
        with urlopen(self.base + "/api/songs?scenario=shop-single") as response:
            self.assertEqual(json.load(response)["count"], 2)
        with urlopen(self.base + "/api/shop?scenario=shop-single") as response:
            single = json.load(response)
            self.assertEqual(single["count"], 1)
            self.assertEqual(single["songs"][0]["songId"], "fixture-pulse")
        with urlopen(self.base + "/api/shop?scenario=art-white") as response:
            self.assertEqual(
                json.load(response)["songs"][0]["albumArt"],
                "/__fixture__/art/white.png"
            )
        for route, expected in (
            ("/api/shop?scenario=error", 503),
            ("/api/shop?scenario=shop-error", 503),
            ("/api/shop?scenario=unknown", 400),
            ("/api/shop?scenario=empty&scenario=demo", 400),
        ):
            with self.subTest(route=route), self.assertRaises(HTTPError) as failure:
                urlopen(self.base + route)
            self.assertEqual(failure.exception.code, expected)

    def test_conflict_and_mutations_are_rejected(self):
        """Stale readers retry; no POST can change a real profile or fixture."""
        request = Request(
            self.base + "/api/songs", headers={"X-FST-Publication-Id": "6"}
        )
        with self.assertRaises(HTTPError) as error:
            urlopen(request)
        self.assertEqual(error.exception.code, 409)
        self.assertEqual(json.load(error.exception)["status"], "publication_changed")
        stale_chart = Request(
            self.base + "/api/leaderboard/fixture-pulse/Solo_Guitar?top=25&offset=0",
            headers={"X-FST-Publication-Id": "6"},
        )
        with self.assertRaises(HTTPError) as error:
            urlopen(stale_chart)
        self.assertEqual(error.exception.code, 409)
        post = Request(self.base + "/api/player/test/track", data=b"{}", method="POST")
        with self.assertRaises(HTTPError) as error:
            urlopen(post)
        self.assertEqual(error.exception.code, 405)
        for path, expected in (
            ("/api/songs?scenario=unknown", 400),
            ("/api/songs?scenario=error", 503),
            ("/api/leaderboard/fixture-pulse/Solo_Guitar?top=0", 400),
            ("/api/leaderboard/fixture-pulse/Solo_Guitar?top=2&top=3", 400),
            ("/api/leaderboard/fixture-pulse/Solo_Guitar?leeway=nan", 400),
            ("/api/leaderboard/fixture-pulse/UnknownChart", 404),
        ):
            with self.subTest(path=path), self.assertRaises(HTTPError) as response:
                urlopen(self.base + path)
            self.assertEqual(response.exception.code, expected)

    def test_unpinned_rollover_retains_headerless_response_provenance(self):
        """A separate listener reproduces the deployed template's unpinned mode."""
        with FixtureServer(
            ("127.0.0.1", 0), FixtureHandler, unpinned=True, rollover_on_read=2
        ) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            base = f"http://127.0.0.1:{server.server_port}"
            try:
                with urlopen(base + "/api/publication") as response:
                    self.assertEqual(json.load(response)["publicationId"], 7)
                    self.assertIsNone(response.headers.get("X-FST-Publication-Id"))
                with urlopen(base + "/api/songs") as response:
                    self.assertEqual(json.load(response)["count"], 2)
                    self.assertIsNone(response.headers.get("X-FST-Publication-Id"))
                with urlopen(base + "/api/publication") as response:
                    self.assertEqual(json.load(response)["publicationId"], 8)
                with urlopen(base + "/api/songs") as response:
                    self.assertEqual(json.load(response)["count"], 2)
                    self.assertIsNone(response.headers.get("X-FST-Publication-Id"))
            finally:
                server.shutdown()
                thread.join(timeout=2)

    def test_explicit_rollover_waits_for_loaded_detail_and_changes_only_once(self):
        """Concurrent bootstrap reads cannot consume a later user-triggered change."""
        with FixtureServer(
            ("127.0.0.1", 0), FixtureHandler,
            unpinned=True, rollover_on_command=True,
        ) as server:
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            root = f"http://127.0.0.1:{server.server_port}"
            try:
                with urlopen(root + "/__fixture__/health") as response:
                    options = json.load(response)["options"]
                self.assertTrue(options["unpinned"])
                self.assertTrue(options["rolloverOnCommand"])
                self.assertIsNone(options["rolloverOnRead"])
                for _ in range(4):
                    with urlopen(root + "/api/publication") as response:
                        self.assertEqual(json.load(response)["publicationId"], 7)
                    with urlopen(root + "/api/songs") as response:
                        self.assertEqual(json.load(response)["count"], 2)
                        self.assertIsNone(response.headers.get("X-FST-Publication-Id"))
                unsafe = Request(
                    root + "/__fixture__/advance-publication",
                    headers={"X-FST-Selected-Player": "fixture-player-1"},
                )
                with self.assertRaises(HTTPError) as blocked:
                    urlopen(unsafe)
                self.assertEqual(blocked.exception.code, 400)
                with urlopen(root + "/api/publication") as response:
                    self.assertEqual(json.load(response)["publicationId"], 7)
                with urlopen(root + "/__fixture__/advance-publication") as response:
                    self.assertEqual(json.load(response), {"publicationId": 8})
                with urlopen(root + "/api/publication") as response:
                    self.assertEqual(json.load(response)["publicationId"], 8)
                with urlopen(root + "/api/songs") as response:
                    self.assertEqual(json.load(response)["count"], 2)
                    self.assertIsNone(response.headers.get("X-FST-Publication-Id"))
                with self.assertRaises(HTTPError) as repeated:
                    urlopen(root + "/__fixture__/advance-publication")
                self.assertEqual(repeated.exception.code, 409)
                with self.assertRaises(HTTPError) as ordinary:
                    urlopen(self.base + "/__fixture__/advance-publication")
                self.assertEqual(ordinary.exception.code, 404)
            finally:
                server.shutdown()
                worker.join(timeout=2)

    def test_pinned_join_rollover_keeps_shop_player_and_failed_songs_distinct(self):
        """New pinned Shop/profile succeed while all new Songs reads fail explicitly."""
        with FixtureServer(
            ("127.0.0.1", 0), FixtureHandler,
            rollover_on_command=True, mismatched_shop_rollover=True,
        ) as server:
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            root = f"http://127.0.0.1:{server.server_port}"
            try:
                with urlopen(root + "/__fixture__/health") as response:
                    options = json.load(response)["options"]
                self.assertFalse(options["unpinned"])
                self.assertTrue(options["rolloverOnCommand"])
                self.assertTrue(options["mismatchedShopRollover"])
                with urlopen(root + "/api/publication") as response:
                    self.assertEqual(json.load(response)["publicationId"], 7)
                    self.assertEqual(response.headers["X-FST-Publication-Id"], "7")
                with urlopen(root + "/api/songs") as response:
                    self.assertEqual(json.load(response)["count"], 2)
                    old_etag = response.headers["ETag"]
                with urlopen(root + "/api/shop") as response:
                    self.assertEqual(json.load(response)["count"], 2)
                    self.assertEqual(response.headers["X-FST-Publication-Id"], "7")
                    old_shop_etag = response.headers["ETag"]
                with urlopen(root + "/api/player/fixture-player-2") as response:
                    first_profile = json.load(response)
                    self.assertEqual(first_profile["totalScores"], 3)
                    self.assertEqual(
                        next(score["sc"] for score in first_profile["scores"]
                             if score["si"] == "fixture-pulse" and score["ins"] == "01"),
                        99_800,
                    )
                with urlopen(
                    root + "/api/leaderboard/fixture-pulse/Solo_Guitar?top=2&offset=0"
                ) as response:
                    self.assertEqual(
                        [entry["score"] for entry in json.load(response)["entries"]],
                        [99_900, 99_800],
                    )
                with self.assertRaises(HTTPError) as selected_header:
                    urlopen(Request(
                        root + "/__fixture__/advance-publication",
                        headers={"X-FST-Selected-Player": "fixture-player-2"},
                    ))
                self.assertEqual(selected_header.exception.code, 400)
                with self.assertRaises(HTTPError) as unsupported:
                    urlopen(root + "/api/shop?scenario=shop-empty")
                self.assertEqual(unsupported.exception.code, 400)
                with urlopen(root + "/api/publication") as response:
                    self.assertEqual(json.load(response)["publicationId"], 7)
                with urlopen(root + "/__fixture__/advance-publication") as response:
                    self.assertEqual(json.load(response), {"publicationId": 8})
                with urlopen(root + "/api/publication") as response:
                    self.assertEqual(json.load(response)["publicationId"], 8)
                    self.assertEqual(response.headers["X-FST-Publication-Id"], "8")
                with self.assertRaises(HTTPError) as stale:
                    urlopen(Request(
                        root + "/api/shop", headers={"X-FST-Publication-Id": "7"}
                    ))
                self.assertEqual(stale.exception.code, 409)
                with urlopen(Request(
                    root + "/api/shop", headers={"X-FST-Publication-Id": "8"}
                )) as response:
                    shop = json.load(response)
                    self.assertEqual(response.headers["X-FST-Publication-Id"], "8")
                    self.assertNotEqual(response.headers["ETag"], old_shop_etag)
                self.assertEqual(shop["count"], 1)
                self.assertEqual(
                    [offer["songId"] for offer in shop["songs"]], ["fixture-pulse"]
                )
                with urlopen(Request(
                    root + "/api/player/fixture-player-2",
                    headers={"X-FST-Publication-Id": "8"},
                )) as response:
                    self.assertEqual(response.headers["X-FST-Publication-Id"], "8")
                    new_profile = json.load(response)
                    self.assertEqual(new_profile["totalScores"], 3)
                    self.assertEqual(
                        next(score["sc"] for score in new_profile["scores"]
                             if score["si"] == "fixture-pulse" and score["ins"] == "01"),
                        99_850,
                    )
                    self.assertEqual(
                        next(score["sc"] for score in new_profile["scores"]
                             if score["si"] == "fixture-pulse" and score["ins"] == "04"),
                        88_800,
                    )
                with urlopen(Request(
                    root + "/api/leaderboard/fixture-pulse/Solo_Guitar?top=2&offset=0",
                    headers={"X-FST-Publication-Id": "8"},
                )) as response:
                    self.assertEqual(response.headers["X-FST-Publication-Id"], "8")
                    self.assertEqual(
                        [(entry["rank"], entry["score"])
                         for entry in json.load(response)["entries"]],
                        [(1, 99_900), (2, 99_850)],
                    )
                with self.assertRaises(HTTPError) as missing:
                    urlopen(Request(
                        root + "/api/songs",
                        headers={
                            "X-FST-Publication-Id": "8",
                            "If-None-Match": old_etag,
                        },
                    ))
                self.assertEqual(missing.exception.code, 503)
                self.assertEqual(
                    missing.exception.headers["X-FST-Publication-Id"], "8"
                )
                with urlopen(root + "/__fixture__/publication-join-reads") as response:
                    self.assertEqual(json.load(response), {
                        "shop": 8, "player": 8, "failedSongs": 8,
                    })
                with self.assertRaises(HTTPError) as repeated:
                    urlopen(root + "/__fixture__/advance-publication")
                self.assertEqual(repeated.exception.code, 409)
            finally:
                server.shutdown()
                worker.join(timeout=2)
        with self.assertRaises(HTTPError) as ordinary:
            urlopen(self.base + "/__fixture__/publication-join-reads")
        self.assertEqual(ordinary.exception.code, 404)
        with self.assertRaisesRegex(ValueError, "explicit command"):
            FixtureServer(
                ("127.0.0.1", 0), FixtureHandler,
                mismatched_shop_rollover=True,
            )
        with self.assertRaisesRegex(ValueError, "persistent fixture mode"):
            FixtureServer(
                ("127.0.0.1", 0), FixtureHandler, unpinned=True,
                rollover_on_command=True, mismatched_shop_rollover=True,
            )

    def test_artwork_failure_fixtures_are_isolated_and_bounded(self):
        """Unavailable art is synthetic; ordinary song fixture remains unchanged."""
        for scenario, expected_count in (("art-error", 2), ("art-skip", 3)):
            with self.subTest(scenario=scenario):
                with urlopen(self.base + "/api/songs?scenario=" + scenario) as response:
                    catalogue = json.load(response)
                self.assertEqual(catalogue["count"], expected_count)
                self.assertTrue(any(
                    "/unavailable-" in song.get("albumArt", "")
                    for song in catalogue["songs"]
                ))
        with self.assertRaises(HTTPError) as missing:
            urlopen(self.base + "/__fixture__/art/unavailable-middle.png")
        self.assertEqual(missing.exception.code, 404)
        self.assertEqual(DEMO_SONGS["count"], 2)

    def test_white_cover_fixture_exposes_score_failure_only_for_white_song(self):
        """A worst-case white cover and failed chart are isolated to one scenario."""
        with urlopen(self.base + "/api/songs?scenario=art-white") as response:
            catalogue = json.load(response)
        self.assertEqual(catalogue["count"], 1)
        self.assertEqual(catalogue["songs"][0]["songId"], "fixture-white")
        self.assertEqual(
            catalogue["songs"][0]["albumArt"], "/__fixture__/art/white.png"
        )
        with urlopen(self.base + "/__fixture__/art/white.png") as response:
            self.assertEqual(response.read(), fixture_artwork("white"))
        self.assertNotEqual(fixture_artwork("white"), fixture_artwork("pulse"))
        with self.assertRaises(HTTPError) as failed:
            urlopen(self.base + "/api/leaderboard/fixture-white/Solo_Guitar?top=25&offset=0")
        self.assertEqual(failed.exception.code, 503)
        with urlopen(self.base + "/api/songs") as response:
            self.assertEqual(json.load(response)["count"], 2)

    def test_initial_white_failure_recovers_without_changing_publication(self):
        """First-run catalogue 503 must not hide the next same-generation white art."""
        with FixtureServer(
            ("127.0.0.1", 0), FixtureHandler, fail_first_white_catalogue=True
        ) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            base = f"http://127.0.0.1:{server.server_port}"
            try:
                with urlopen(base + "/api/publication") as response:
                    self.assertEqual(json.load(response)["publicationId"], 7)
                with self.assertRaises(HTTPError) as failed:
                    urlopen(base + "/api/songs?scenario=art-white")
                self.assertEqual(failed.exception.code, 503)
                with urlopen(base + "/api/songs?scenario=art-white") as response:
                    catalogue = json.load(response)
                self.assertEqual(catalogue["songs"][0]["songId"], "fixture-white")
                self.assertEqual(server.publication_id, 7)
                with urlopen(base + "/api/songs?scenario=art-white") as response:
                    self.assertEqual(json.load(response)["count"], 1)
            finally:
                server.shutdown()
                thread.join(timeout=2)

    def test_unpinned_one_shot_listener_exits_after_first_valid_catalogue(self):
        """A true loopback connection failure follows one typed headerless read."""
        with FixtureServer(
            ("127.0.0.1", 0), FixtureHandler,
            unpinned=True, stop_after_first_songs=True,
        ) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            base = f"http://127.0.0.1:{server.server_port}"
            with urlopen(base + "/api/publication") as response:
                self.assertFalse(json.load(response)["pinningEnabled"])
            with urlopen(base + "/api/songs") as response:
                self.assertEqual(json.load(response)["count"], 2)
                self.assertIsNone(response.headers.get("X-FST-Publication-Id"))
            thread.join(timeout=3)
            self.assertFalse(thread.is_alive(), "The fixture did not close its listener")
        with self.assertRaises(URLError):
            urlopen(base + "/api/songs", timeout=2)

    def test_unpinned_one_shot_chart_stops_only_after_valid_full_page(self):
        """A Detail preview must not use up the first full-page offline fixture."""
        with FixtureServer(
            ("127.0.0.1", 0), FixtureHandler,
            unpinned=True, stop_after_first_score=True,
        ) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            base = f"http://127.0.0.1:{server.server_port}"
            with urlopen(base + "/api/publication") as response:
                self.assertFalse(json.load(response)["pinningEnabled"])
            with urlopen(base + "/api/songs") as response:
                self.assertEqual(json.load(response)["count"], 2)
            with urlopen(base + "/__fixture__/health") as response:
                self.assertTrue(json.load(response)["ready"])
            with urlopen(
                base + "/api/leaderboard/fixture-pulse/Solo_Guitar?top=10&offset=0"
            ) as response:
                self.assertEqual(json.load(response)["count"], 10)
            with urlopen(base + "/__fixture__/health") as response:
                self.assertTrue(json.load(response)["ready"])
            with urlopen(
                base + "/api/leaderboard/fixture-pulse/Solo_Guitar?top=25&offset=0"
            ) as response:
                self.assertEqual(json.load(response)["count"], 25)
                self.assertIsNone(response.headers.get("X-FST-Publication-Id"))
            thread.join(timeout=3)
            self.assertFalse(thread.is_alive(), "Chart fixture did not stop after its response")
        with self.assertRaises(URLError):
            urlopen(base + "/api/leaderboard/fixture-pulse/Solo_Guitar", timeout=2)

    def test_unpinned_one_shot_shop_stops_after_valid_feed_only(self):
        """A Shop-only listener must leave Songs and invalid queries usable first."""
        with FixtureServer(
            ("127.0.0.1", 0), FixtureHandler,
            unpinned=True, stop_after_first_shop=True,
        ) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            base = f"http://127.0.0.1:{server.server_port}"
            with urlopen(base + "/api/publication") as response:
                self.assertFalse(json.load(response)["pinningEnabled"])
            with urlopen(base + "/api/songs") as response:
                self.assertEqual(json.load(response)["count"], 2)
            with self.assertRaises(HTTPError) as invalid:
                urlopen(base + "/api/shop?scenario=unknown")
            self.assertEqual(invalid.exception.code, 400)
            with self.assertRaises(HTTPError) as unarmed:
                urlopen(base + "/__fixture__/shop-visible")
            self.assertEqual(unarmed.exception.code, 409)
            with urlopen(base + "/__fixture__/health") as response:
                self.assertTrue(json.load(response)["ready"])
            with urlopen(base + "/api/shop") as response:
                self.assertEqual(json.load(response)["count"], 2)
                self.assertIsNone(response.headers.get("X-FST-Publication-Id"))
            with urlopen(base + "/__fixture__/health") as response:
                self.assertTrue(json.load(response)["ready"])
            with urlopen(base + "/__fixture__/art/pulse.png") as response:
                self.assertEqual(response.read()[:8], b"\x89PNG\r\n\x1a\n")
            with urlopen(base + "/__fixture__/health") as response:
                self.assertTrue(json.load(response)["ready"])
            with urlopen(base + "/__fixture__/art/orbit.png") as response:
                self.assertEqual(response.read()[:8], b"\x89PNG\r\n\x1a\n")
            with urlopen(base + "/__fixture__/shop-visible") as response:
                self.assertTrue(json.load(response)["stopping"])
            thread.join(timeout=3)
            self.assertFalse(thread.is_alive(), "The Shop listener stayed online")
        with self.assertRaises(URLError):
            urlopen(base + "/api/shop", timeout=2)


if __name__ == "__main__":
    unittest.main()
