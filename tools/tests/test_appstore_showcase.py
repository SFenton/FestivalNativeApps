"""Tests for the App Store showcase overlay (synthetic catalogue only; no network)."""

from __future__ import annotations

import json
import threading
import unittest
import urllib.error
import urllib.request

from tools import appstore_showcase as showcase

INSTRUMENT_KEYS = (
    "Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals", "Solo_PeripheralGuitar",
    "Solo_PeripheralBass", "Solo_PeripheralCymbals", "Solo_PeripheralDrums",
)


def synthetic_catalogue() -> dict:
    """Build a tiny public-catalogue envelope with Epic, non-Epic and excluded rows.

    Returns:
        A ``/api/songs``-shaped payload that includes a fat ``populationTiers`` field.
    """
    songs = []

    def row(index: int, title: str, artist: str) -> dict:
        """Create one catalogue row with every chart charted."""
        return {
            "songId": f"song-{index}", "title": title, "artist": artist, "year": 2020 + index % 5,
            "tempo": 120, "sig": "Guitar", "durationSeconds": 180,
            "albumArt": f"art{index}-512x512-abc.jpg", "doubleBassSupported": False,
            "difficulty": {key: 1 + index % 5 for key in (
                "guitar", "bass", "vocals", "drums", "proGuitar", "proBass", "proDrums", "proCymbals")},
            "maxScores": {key: 100_000 + 7_000 * index for key in INSTRUMENT_KEYS},
            "populationTiers": {"huge": list(range(50))}, "pathGuitar": "x",
        }

    for index in range(14):
        songs.append(row(index, f"Epic Song {index}", "Epic Games"))
    songs.append(row(20, "Collab", "Epic Games ft. Somebody"))
    songs.append(row(21, "Where My Wookiees At?", "Epic Games"))
    songs.append(row(22, "Gwenpool's Multiverse", "Epic Games"))
    songs.append(row(23, "For Latveria", "Epic Games"))
    songs.append(row(24, "Other Band Song", "Other Band"))
    return {"count": len(songs), "currentSeason": 15, "songs": songs}


class CatalogueTests(unittest.TestCase):
    """Verify Epic-only filtering and field handling."""

    def test_exact_artist_and_exclusions(self) -> None:
        """Only exact Epic Games rows survive, minus licensed-franchise titles."""
        result = showcase.filter_catalogue(synthetic_catalogue())
        titles = {song["title"] for song in result["songs"]}
        self.assertEqual(titles, {f"Epic Song {i}" for i in range(14)})
        self.assertEqual(result["count"], len(result["songs"]))
        self.assertTrue(showcase.EXCLUDED_TITLES.isdisjoint(titles))

    def test_art_preserved_and_bulk_fields_dropped(self) -> None:
        """The CDN-relative filename is untouched and population/path fields are removed."""
        result = showcase.filter_catalogue(synthetic_catalogue())
        first = result["songs"][0]
        self.assertEqual(first["albumArt"], "art0-512x512-abc.jpg")
        self.assertNotIn("populationTiers", first)
        self.assertNotIn("pathGuitar", first)
        self.assertEqual(result["currentSeason"], 15)

    def test_filter_is_idempotent(self) -> None:
        """Filtering an already-filtered payload changes nothing."""
        once = showcase.filter_catalogue(synthetic_catalogue())
        self.assertEqual(showcase.filter_catalogue(once), once)


class OverlayTests(unittest.TestCase):
    """Verify determinism, score validity and reference integrity."""

    @classmethod
    def setUpClass(cls) -> None:
        """Build one overlay shared by the read-only tests."""
        cls.overlay = showcase.Showcase(synthetic_catalogue())

    def test_deterministic(self) -> None:
        """Two independent builds serialise identically."""
        other = showcase.Showcase(synthetic_catalogue())

        def dump(overlay: showcase.Showcase) -> str:
            """Serialise a representative cross-section of payloads."""
            return json.dumps([
                overlay.profile(showcase.PLAYER_ID), overlay.rivals_all(),
                overlay.rankings_page("Solo_Guitar", "totalscore", 1, 10),
                overlay.rank_history("Solo_Guitar", 30), overlay.shop(), overlay.notifications(50),
            ], sort_keys=True)

        self.assertEqual(dump(self.overlay), dump(other))

    def test_scores_are_valid(self) -> None:
        """Scores respect maxima, rank/population, accuracy, stars, season and uniqueness."""
        profile = self.overlay.profile(showcase.PLAYER_ID)
        self.assertEqual(profile["totalScores"], len(profile["scores"]))
        self.assertGreater(len(profile["scores"]), 20)
        seen = set()
        codes = {spec.code: spec.key for spec in showcase.INSTRUMENT_SPECS}
        for score in profile["scores"]:
            pair = (score["si"], score["ins"])
            self.assertNotIn(pair, seen)
            seen.add(pair)
            self.assertLessEqual(score["sc"], self.overlay.max_score[(score["si"], codes[score["ins"]])])
            self.assertGreaterEqual(score["rk"], 1)
            self.assertLessEqual(score["rk"], score["te"])
            self.assertAlmostEqual(score["pct"], score["rk"] / score["te"], places=5)
            self.assertTrue(0 <= score["acc"] <= 1000)
            self.assertTrue(3 <= score["st"] <= 6)
            self.assertTrue(1 <= score["sn"] <= 15)
        leads = [s for s in profile["scores"] if s["ins"] == "01"]
        self.assertGreaterEqual(len(leads), 10)

    def test_no_dangling_references(self) -> None:
        """Every referenced song id exists, and removal of a song is detected."""
        self.assertEqual(self.overlay.dangling_references(), [])
        broken = showcase.Showcase(synthetic_catalogue())
        victim = next(iter(broken.player_scores))[0]
        broken.songs_payload["songs"] = [
            song for song in broken.songs_payload["songs"] if song["songId"] != victim
        ]
        self.assertIn(victim, broken.dangling_references())

    def test_only_epic_songs_everywhere(self) -> None:
        """Rival rows and the shop only name catalogue songs."""
        ids = set(self.overlay.by_id)
        for rival_id in self.overlay.rivals:
            detail = self.overlay.rival_detail("Solo_Guitar", rival_id, "closest", 0, 0)
            self.assertTrue({row["songId"] for row in detail["songs"]} <= ids)
        self.assertTrue({s["songId"] for s in self.overlay.shop()["songs"]} <= ids)

    def test_rankings_place_player_flatteringly(self) -> None:
        """The player sits in the top 15 on every instrument and rank history improves."""
        for spec in showcase.INSTRUMENT_SPECS:
            entry = self.overlay.player_ranking(spec.key)
            self.assertIsNotNone(entry)
            self.assertLessEqual(entry["totalScoreRank"], 15)
            self.assertEqual(entry["displayName"], showcase.PLAYER_NAME)
            history = self.overlay.rank_history(spec.key, 30)["history"]
            ranks = [item["totalScoreRank"] for item in history]
            self.assertEqual(len(ranks), 30)
            self.assertGreater(ranks[0], ranks[-1])
            self.assertEqual(ranks, sorted(ranks, reverse=True))
        page = self.overlay.rankings_page("Solo_Guitar", "totalscore", 1, 5)
        self.assertEqual(len(page["entries"]), 5)
        names = {entry["displayName"] for entry in page["entries"]}
        self.assertEqual(len(names), 5)

    def test_top_ranks_are_consistent_everywhere(self) -> None:
        """Five #1 charts (mostly Lead, FC) and a top-10 share agree with leaderboards and rivals."""
        scores = self.overlay.player_scores
        firsts = [key for key, score in scores.items() if score["rk"] == 1]
        self.assertEqual(len(firsts), showcase.TOP_RANK_SLOTS)
        self.assertGreaterEqual(sum(1 for key in firsts if key[1] == "Solo_Guitar"), 3)
        for key in firsts:
            score = scores[key]
            self.assertTrue(score["fc"])
            self.assertEqual(score["st"], 6)
            self.assertGreaterEqual(score["sc"], self.overlay.max_score[key] * 0.99)
        top_ten = [score for score in scores.values() if score["rk"] <= 10]
        self.assertGreaterEqual(len(top_ten), len(scores) * 0.15)
        for key, score in scores.items():
            if score["rk"] > 10:
                continue
            board = self.overlay.leaderboard(key[0], key[1], 10, 0)
            row = board["entries"][score["rk"] - 1]
            self.assertEqual((row["accountId"], row["rank"], row["score"]),
                             (showcase.PLAYER_ID, score["rk"], score["sc"]))
            for rival in self.overlay.rivals.values():
                self.assertNotEqual(rival.charts.get(key), score["rk"])
        rank_by_chart = {}
        for rival_id in self.overlay.rivals:
            for row in self.overlay.rival_detail("Solo_Guitar", rival_id, "closest", 0, 0)["songs"]:
                rank_by_chart[(row["songId"], rival_id)] = row
        for (song_id, _), row in rank_by_chart.items():
            mine = scores[(song_id, "Solo_Guitar")]
            self.assertEqual(row["userRank"], mine["rk"])

    def test_rival_counts_match_rows(self) -> None:
        """List counters equal the ahead/behind tallies in the detail rows."""
        listing = self.overlay.rivals_list("Solo_Guitar")
        rival = (listing["above"] + listing["below"])[0]
        detail = self.overlay.rival_detail("Solo_Guitar", rival["accountId"], "closest", 0, 0)
        rows = detail["songs"]
        self.assertEqual(rival["sharedSongCount"], len(rows))
        self.assertEqual(rival["aheadCount"], sum(1 for r in rows if r["rankDelta"] < 0))
        self.assertEqual(rival["behindCount"], sum(1 for r in rows if r["rankDelta"] > 0))

    def test_scope_tokens(self) -> None:
        """Instrument, combo and pro-drums tokens decode; junk does not."""
        self.assertEqual(showcase.Showcase.scope_instruments("0f"), list(INSTRUMENT_KEYS[:4]))
        self.assertEqual(showcase.Showcase.scope_instruments("Solo_Bass"), ["Solo_Bass"])
        self.assertEqual(len(showcase.Showcase.scope_instruments("pro_drums")), 2)
        self.assertIsNone(showcase.Showcase.scope_instruments("nonsense"))


class ServerTests(unittest.TestCase):
    """HTTP smoke tests against a loopback showcase server on a free port."""

    @classmethod
    def setUpClass(cls) -> None:
        """Start the server in a daemon thread."""
        cls.server = showcase.build_server(synthetic_catalogue(), 0)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls) -> None:
        """Stop the server."""
        cls.server.shutdown()
        cls.server.server_close()

    def get(self, path: str, headers: dict | None = None) -> tuple[int, dict | None, dict]:
        """Fetch a path, returning status, decoded JSON (if any) and headers.

        Args:
            path: Request path and query.
            headers: Optional request headers.

        Returns:
            ``(status, body, response headers)``.
        """
        request = urllib.request.Request(self.base + path, headers=headers or {})
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                raw, status, out = response.read(), response.status, dict(response.headers)
        except urllib.error.HTTPError as error:
            raw, status, out = error.read(), error.code, dict(error.headers)
        return status, json.loads(raw) if raw else None, out

    def test_catalogue_and_etag(self) -> None:
        """Songs are Epic-only under the showcase ETag, and conditional reads return 304."""
        status, body, headers = self.get("/api/songs")
        self.assertEqual(status, 200)
        self.assertEqual(headers["ETag"], showcase.SHOWCASE_ETAG)
        self.assertEqual(body["count"], 14)
        self.assertTrue(all(song["artist"] == "Epic Games" for song in body["songs"]))
        self.assertEqual(self.get("/api/songs", {"If-None-Match": showcase.SHOWCASE_ETAG})[0], 304)

    def test_player_rankings_rivals_leaderboard(self) -> None:
        """Profile, rankings, rivals and leaderboards return showcase content."""
        status, profile, _ = self.get("/api/player/showcase-player-1")
        self.assertEqual((status, profile["displayName"]), (200, "StageDiver"))
        self.assertEqual(profile["totalScores"], len(profile["scores"]))
        status, ranking, _ = self.get("/api/rankings/Solo_Guitar?rankBy=totalscore&page=1&pageSize=5")
        self.assertEqual(status, 200)
        self.assertIn("StageDiver", {entry["displayName"] for entry in ranking["entries"]})
        status, mine, _ = self.get("/api/rankings/Solo_Guitar/showcase-player-1")
        self.assertEqual((status, mine["totalScoreRank"]), (200, 3))
        status, history, _ = self.get("/api/rankings/Solo_Guitar/showcase-player-1/history?days=30")
        self.assertEqual((status, len(history["history"])), (200, 30))
        status, rivals, _ = self.get("/api/player/showcase-player-1/rivals/Solo_Guitar")
        self.assertEqual(status, 200)
        names = {r["displayName"] for r in rivals["above"] + rivals["below"]}
        self.assertTrue(names)
        self.assertTrue(names <= {rival.name for rival in showcase.RIVALS})
        rival_id = (rivals["above"] + rivals["below"])[0]["accountId"]
        status, detail, _ = self.get(f"/api/player/showcase-player-1/rivals/Solo_Guitar/{rival_id}")
        self.assertEqual((status, detail["rival"]["accountId"]), (200, rival_id))
        status, everything, _ = self.get("/api/player/showcase-player-1/rivals/all")
        self.assertEqual((status, everything["accountId"]), (200, "showcase-player-1"))
        status, board, _ = self.get("/api/player/showcase-player-1/leaderboard-rivals/Solo_Guitar")
        self.assertEqual((status, board["userRank"]), (200, 3))
        song_id = profile["scores"][0]["si"]
        ins = {s.code: s.key for s in showcase.INSTRUMENT_SPECS}[profile["scores"][0]["ins"]]
        status, leaderboard, _ = self.get(f"/api/leaderboard/{song_id}/{ins}?top=100")
        self.assertEqual(status, 200)
        own = [e for e in leaderboard["entries"] if e["accountId"] == "showcase-player-1"]
        rank = profile["scores"][0]["rk"]
        if rank <= 100:
            self.assertEqual(own[0]["rank"], rank)

    def test_shop_notifications_bands(self) -> None:
        """Shop, notifications and bands serve valid showcase or empty bodies."""
        status, shop, _ = self.get("/api/shop")
        self.assertEqual((status, shop["count"]), (200, len(shop["songs"])))
        status, notes, _ = self.get("/api/player/showcase-player-1/notifications")
        self.assertTrue(status == 200 and notes["notificationsGenerated"])
        status, bands, _ = self.get("/api/player/showcase-player-1/bands")
        self.assertEqual((status, bands["totalCount"]), (200, 0))
        self.assertEqual(self.get("/api/rankings/Solo_PeripheralVocals/showcase-player-1")[0], 404)

    def test_safety_and_pinning(self) -> None:
        """Wrong publication pins get 409; keys, profile headers and unknown routes are refused."""
        _, _, headers = self.get("/api/songs")
        self.assertEqual(self.get("/api/songs", {"X-FST-Publication-Id": "999"})[0], 409)
        self.assertEqual(
            self.get("/api/songs", {"X-FST-Publication-Id": headers["X-FST-Publication-Id"]})[0], 200)
        self.assertEqual(self.get("/api/songs", {"X-API-Key": "nope"})[0], 400)
        self.assertEqual(self.get("/api/songs", {"X-FST-Selected-Profile": "x"})[0], 400)
        self.assertEqual(self.get("/api/songs?scenario=empty")[0], 400)
        self.assertEqual(self.get("/api/unknown")[0], 404)
        self.assertEqual(self.get("/api/publication")[0], 200)


if __name__ == "__main__":
    unittest.main()


class ShootTests(unittest.TestCase):
    """The capture plan drives ios_sim.py against a live loopback overlay."""

    def test_shoot_captures_every_page_against_live_server(self) -> None:
        """Each page gets one shot argv with the showcase profile and a reachable server."""
        from pathlib import Path
        from tempfile import TemporaryDirectory
        from types import SimpleNamespace

        seen: list[tuple[list[str], int]] = []

        def fake_run(argv: list[str]) -> SimpleNamespace:
            base = argv[argv.index(next(a for a in argv if a.startswith("FST_API_BASE_URL=")))].split("=", 1)[1]
            with urllib.request.urlopen(f"{base}/api/songs", timeout=5) as response:
                seen.append((argv, response.status))
            return SimpleNamespace(returncode=0)

        with TemporaryDirectory() as tmp:
            code = showcase.shoot(synthetic_catalogue(), Path(tmp) / "out", "promax", 1.0, run=fake_run)
        self.assertEqual(code, 0)
        self.assertEqual([s[1] for s in seen], [200] * len(showcase.SHOTS))
        stems = [Path(a[a.index("--out") + 1]).stem for a, _ in seen]
        self.assertEqual(stems, [stem for stem, _, _ in showcase.SHOTS])
        rivals = seen[-1][0]
        self.assertEqual(rivals[rivals.index("--route") + 1], "rivals")
        for argv, _ in seen:
            self.assertIn("--clean-status-bar", argv)
            self.assertIn(f"FST_DEBUG_PROFILE={showcase.PLAYER_ID}:{showcase.PLAYER_NAME}", argv)

    def test_shoot_stops_on_first_failure(self) -> None:
        """A failing capture returns its exit code without running later pages."""
        from pathlib import Path
        from tempfile import TemporaryDirectory
        from types import SimpleNamespace

        calls: list[list[str]] = []

        def failing(argv: list[str]) -> SimpleNamespace:
            calls.append(argv)
            return SimpleNamespace(returncode=3)

        with TemporaryDirectory() as tmp:
            self.assertEqual(showcase.shoot(synthetic_catalogue(), Path(tmp), "promax", 1.0, run=failing), 3)
        self.assertEqual(len(calls), 1)
