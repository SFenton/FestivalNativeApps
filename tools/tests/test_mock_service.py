"""Exercise fixture pinning and prevent accidental live-style mutation."""

import json
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from tools.mock_service import DEMO_SONGS, FixtureHandler, FixtureServer, ROOT, fixture_artwork


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

    def test_paged_leaderboard_and_original_artwork(self):
        """One page of 25 and one page of one share a 26-entry total."""
        with urlopen(self.base + "/api/leaderboard/fixture-pulse/Solo_Guitar?top=25&offset=0") as response:
            first = json.load(response)
        self.assertEqual(first["count"], 25)
        self.assertEqual(first["localEntries"], 26)
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
        with urlopen(self.base + "/__fixture__/art/pulse.png") as response:
            self.assertEqual(response.headers["Content-Type"], "image/png")
            self.assertEqual(response.read()[:8], b"\x89PNG\r\n\x1a\n")
        self.assertNotEqual(fixture_artwork("pulse"), fixture_artwork("orbit"))
        asset = ROOT / "apple/Tests/FestivalUITests/Fixtures/pulse.png"
        self.assertEqual(asset.read_bytes(), fixture_artwork("pulse"))

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


if __name__ == "__main__":
    unittest.main()
