"""Band Detail scrape-freeze tooling (issue #554): ``band_freeze_fixture.py`` and its journeys.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import a11y_matrix as m  # noqa: E402  (sibling module)
import band_freeze_fixture as f  # noqa: E402
import mock_service  # noqa: E402
from tools.windows import uiwin  # noqa: E402

JOURNEYS = Path(__file__).resolve().parents[1] / "journeys"
WARM = f"/api/rankings/bands/Band_Duets/{f.WARM_TEAM}"
COLD = f"/api/rankings/bands/Band_Duets/{f.COLD_TEAM}"


class OutcomeTests(unittest.TestCase):
    """Only Band Detail's band-scoped reads are touched."""

    def test_band_read_sections(self):
        self.assertEqual(f.band_read("/api/rankings/bands/Band_Duets", {"teamKey": ["t"]}), ("t", "row"))
        self.assertIsNone(f.band_read("/api/rankings/bands/Band_Duets", {}))
        self.assertEqual(f.band_read(f"{WARM}/history", {}), (f.WARM_TEAM, "history"))
        self.assertEqual(f.band_read(f"{WARM}/songs", {"limit": ["5"]}), (f.WARM_TEAM, "songs"))
        self.assertIsNone(f.band_read("/api/songs", {}))
        self.assertIsNone(f.band_read(f"{WARM}/song-rows", {}))

    def test_warm_band_freezes_only_conditional_reads(self):
        for path, query in ((f"{WARM}/songs", {}), (f"{WARM}/history", {}),
                            ("/api/rankings/bands/Band_Duets", {"teamKey": [f.WARM_TEAM]})):
            self.assertEqual(f.outcome(path, query, False), "tag", path)
            self.assertEqual(f.outcome(path, query, True), "freeze", path)

    def test_cold_band_freezes_only_songs(self):
        self.assertEqual(f.outcome(f"{COLD}/songs", {}, False), "freeze")
        self.assertEqual(f.outcome(f"{COLD}/history", {}, False), "pass")
        self.assertEqual(f.outcome("/api/rankings/bands/Band_Duets", {"teamKey": [f.COLD_TEAM]}, False), "pass")

    def test_other_reads_pass(self):
        self.assertEqual(f.outcome("/api/songs", {}, True), "pass")
        self.assertEqual(f.outcome("/api/rankings/bands/Band_Duets/other-team/songs", {}, True), "pass")


class FixtureServerTests(unittest.TestCase):
    """The patched handler over a real loopback socket."""

    @classmethod
    def setUpClass(cls):
        cls.original = mock_service.FixtureHandler.do_GET
        cls.original_queue = mock_service.FixtureServer.request_queue_size
        f.install()
        cls.server = mock_service.FixtureServer(("127.0.0.1", 0), mock_service.FixtureHandler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        mock_service.FixtureHandler.do_GET = cls.original
        mock_service.FixtureServer.request_queue_size = cls.original_queue

    def get(self, path, headers=None):
        request = urllib.request.Request(self.base + path, headers=headers or {})
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                return response.status, response.headers, response.read()
        except urllib.error.HTTPError as error:
            return error.code, error.headers, error.read()

    def test_warm_read_is_tagged_then_frozen(self):
        status, headers, body = self.get(f"{WARM}/songs?limit=5")
        self.assertEqual((status, headers.get("ETag")), (200, f.ETAG))
        self.assertTrue(json.loads(body))
        status, headers, body = self.get(f"{WARM}/songs?limit=5", {"If-None-Match": f.ETAG})
        self.assertEqual((status, headers.get("Retry-After"), headers.get("X-Fst-Public-Read-Freeze-Reason")),
                         (503, "30", f.FREEZE_REASON))
        self.assertEqual((headers.get("Cache-Control"), body), ("no-store", b""))

    def test_cold_songs_frozen_without_cache(self):
        status, headers, _ = self.get(f"{COLD}/songs?limit=5")
        self.assertEqual((status, headers.get("X-Fst-Public-Read-Freeze-Reason")), (503, f.FREEZE_REASON))

    def test_untouched_reads_have_no_fixture_tag(self):
        status, headers, _ = self.get("/api/songs")
        self.assertEqual(status, 200)
        self.assertNotEqual(headers.get("ETag"), f.ETAG)

    def test_selected_profile_header_still_rejected(self):
        status, _, _ = self.get(f"{WARM}/songs", {"X-FST-Selected-Player": "x"})
        self.assertEqual(status, 400)


class JourneyTests(unittest.TestCase):
    """The hosted journeys use the fixture, parse and assert retained rows without the inline status."""

    def test_bands_journeys(self):
        entries = {e["name"]: e for e in json.loads((JOURNEYS / "bands.json").read_text(encoding="utf-8"))}
        warm = entries["band-detail-scrape-freeze-keeps-sections"]
        cold = entries["band-detail-scrape-freeze-cold-songs"]
        for entry in (warm, cold):
            self.assertEqual(entry["fixture"], ["band_freeze_fixture.py"])
            for step in entry["steps"]:
                uiwin.parse_step(step)
        steps = warm["steps"]
        back = steps.index("key:alt+left")
        after = steps[back:]
        for needle in ("fst.band.song-row.fixture-pulse", "fst.band.song-row.fixture-ghost-song",
                       "fst.band.history-row.2024-01-03", "waitgone:id=fst.service-status.inline"):
            self.assertTrue(any(needle in s for s in after), needle)
        self.assertTrue(any(s.startswith("assertorder:") for s in after))

    def test_a11y_pages_parse(self):
        pages = json.loads((JOURNEYS / "a11y-band-freeze.json").read_text(encoding="utf-8"))
        self.assertEqual({p["name"] for p in pages}, {"band-freeze-revisit", "band-freeze-cold-songs"})
        for page in pages:
            self.assertEqual(page["fixture"], ["band_freeze_fixture.py"])
            for step in m.page_steps(page, "medium", Path("out"), "", True, 10):
                parsed = uiwin.parse_step(step)
                self.assertNotIn(parsed["verb"], {"click", "rightclick", "hover", "scroll"}, f"{page['name']}: {step}")


if __name__ == "__main__":
    unittest.main()
