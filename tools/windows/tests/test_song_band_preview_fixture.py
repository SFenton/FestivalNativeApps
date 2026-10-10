"""Song Detail band-preview journey tooling: ``song_band_preview_fixture.py`` (issue #264).

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
import song_band_preview_fixture as f  # noqa: E402  (sibling module)
import mock_service  # noqa: E402

JOURNEY = Path(__file__).resolve().parents[1] / "journeys" / "a11y-song-band-preview.json"


class PayloadTests(unittest.TestCase):
    """The ``full`` mode's designed body."""

    def test_split_args(self):
        self.assertEqual(f.split_args(["--port", "0"]), ("demo", ["--port", "0"]))
        self.assertEqual(f.split_args(["--bands", "full", "--port", "0"]), ("full", ["--port", "0"]))
        with self.assertRaises(SystemExit):
            f.split_args(["--bands", "nope"])

    def test_anonymous_full_board(self):
        body = f.full_payload("fixture-pulse", 10, None)
        self.assertEqual(body["songId"], "fixture-pulse")
        self.assertTrue(body["showLeaderboardEntryTotals"])
        self.assertEqual([b["bandType"] for b in body["bands"]], ["Band_Duets", "Band_Trios", "Band_Quad"])
        for band, members in zip(body["bands"], (2, 3, 4)):
            self.assertEqual(band["count"], 10)
            self.assertEqual(len(band["entries"]), 10)
            self.assertEqual(band["totalEntries"], 1_234 * members)
            self.assertEqual([e["rank"] for e in band["entries"]], list(range(1, 11)))
            self.assertTrue(all(len(e["members"]) == members for e in band["entries"]))
            self.assertTrue(all(e["bandType"] == band["bandType"] for e in band["entries"]))
            self.assertIsNone(band["selectedPlayerEntry"])
            self.assertIsNone(band["selectedBandEntry"])
        self.assertEqual(len({e["teamKey"] for b in body["bands"] for e in b["entries"]}), 30)

    def test_player_selection_per_size(self):
        duos, trios, quads = f.full_payload("fixture-pulse", 10, "fixture-player-1")["bands"]
        self.assertEqual(duos["selectedPlayerEntry"]["rank"], 14)
        self.assertEqual(duos["selectedPlayerEntry"]["members"][0]["accountId"], "fixture-player-1")
        self.assertIs(trios["selectedBandEntry"], trios["entries"][2])
        self.assertIsNone(quads["selectedPlayerEntry"])
        self.assertIsNone(quads["selectedBandEntry"])
        # Only fixture players are designed; a real-looking ID gets the anonymous board.
        self.assertIsNone(f.full_payload("fixture-pulse", 10, "195e93ef")["bands"][0]["selectedPlayerEntry"])

    def test_journey_covers_every_mode(self):
        pages = json.loads(JOURNEY.read_text(encoding="utf-8"))
        pages = pages["pages"] if isinstance(pages, dict) else pages
        modes = {p["fixture"][p["fixture"].index("--bands") + 1] for p in pages if "fixture" in p}
        self.assertEqual(modes, set(f.MODES))
        self.assertTrue(any("fixture" not in p and not str(p.get("profile", "")).startswith("fixture-") for p in pages))

    def test_surface_pages_pin_the_opaque_bordered_fallback(self):
        # surface-materials R4 (issue #426, for #64): transparency off, in-app Less Transparency or Increase Contrast make
        # every plain band row's FSTCardSurfaceBrush opaque #121826 with a visible rim; with transparency on the fill stays
        # translucent at the same probe point, so the opaque probe is not vacuous.
        from tools.windows import a11y_matrix as m
        from tools.windows import uiwin as u
        pages = {p["name"]: p for p in json.loads(JOURNEY.read_text(encoding="utf-8"))}
        opaque = "fill:L6,M0=#121826~1|R6,M0=@fill~0|C0,T4=@fill~0|C0,B4=@fill~0"
        visible = "bg:L-6,M0|L0,M0!=@fill~6|C0,T0!=@fill~6|C0,B1!=@fill~6|L0,M0!=@bg~6|C0,T0!=@bg~6|C0,B1!=@bg~6"
        strong = "L0,M0=#84828A~40|C0,T0=#84828A~40|C0,B1=#84828A~40"
        rows = ("Band_Duets.0", "Band_Duets.1")
        cases = {
            "bp-a11y-surface-no-transparency": ("no-transparency", {}, visible),
            "bp-a11y-surface-less-transparency": ("normal", {"lessTransparency": True}, visible),
            "bp-a11y-surface-more-contrast": ("normal", {"moreContrast": True}, strong),
            "bp-a11y-surface-app-contrast": ("app-contrast", {}, strong),
        }
        for name, (mode, settings, edge) in cases.items():
            with self.subTest(page=name):
                page = pages[name]
                self.assertEqual(page["modes"], [mode])
                self.assertEqual(m.mode_pages([page], mode), [page])
                self.assertEqual(page["settings"] if settings else page.get("settings", {}), settings)
                # Anonymous: no selected band, so every probed row is the plain card surface, not the player purple.
                self.assertNotIn("profile", page)
                steps = [*page["ready"], *page["after_ready"]]
                for step in steps:
                    u.parse_step(step.replace("{stem}", "x"))
                for row in rows:
                    self.assertIn(f"assertpaint:id=fst.song-detail.band-row.{row}|{opaque}|{edge}", steps)
        translucent = pages["bp-a11y-surface-translucent"]
        self.assertEqual(translucent["modes"], ["normal"])
        self.assertNotIn("settings", translucent)
        for row in rows:
            self.assertIn(f"assertpaint:id=fst.song-detail.band-row.{row}|L6,M0!=#121826~1|C0,B4!=#121826~1",
                          translucent["after_ready"])
        # windows-ui's generated runs pick every surface page up in its declared mode.
        from tools.windows import ui_ci
        runs = {(r.mode, page) for r in ui_ci.RUNS if r.pages == JOURNEY.name for page in (r.only or "").split(",")}
        for name, (mode, _, _) in cases.items():
            self.assertIn((mode, name), runs)
        self.assertIn(("normal", "bp-a11y-surface-translucent"), runs)


class FixtureServerTests(unittest.TestCase):
    """The patched handler over a real loopback socket."""

    @classmethod
    def setUpClass(cls):
        cls.original = mock_service.FixtureHandler.do_GET
        cls.state = f.BandsMode("demo")
        f.install(cls.state)
        cls.server = mock_service.FixtureServer(("127.0.0.1", 0), mock_service.FixtureHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        mock_service.FixtureHandler.do_GET = cls.original

    def get(self, path: str) -> tuple[int, dict, bytes]:
        try:
            with urllib.request.urlopen(self.base + path, timeout=10) as response:
                return response.status, dict(response.headers), response.read()
        except urllib.error.HTTPError as error:
            return error.code, dict(error.headers), error.read()

    def test_modes(self):
        path = "/api/leaderboard/fixture-pulse/bands/all?top=10&accountId=fixture-player-1"
        self.state.mode = "full"
        status, _, body = self.get(path)
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body)["bands"][0]["selectedPlayerEntry"]["rank"], 14)
        self.state.mode = "invalid"
        self.assertEqual(json.loads(self.get(path)[2])["songId"], "fixture-other-song")
        self.state.mode = "frozen"
        status, headers, _ = self.get(path)
        self.assertEqual((status, headers["Retry-After"]), (503, "30"))
        self.state.mode = "error"
        first, second = self.get(path)[0], self.get(path)[0]
        self.assertEqual(sorted((first, second)), [200, 500])
        self.state.mode = "demo"
        self.assertEqual(json.loads(self.get(path)[2])["songId"], "fixture-pulse")

    def test_other_routes_unchanged(self):
        self.state.mode = "error"
        try:
            status, _, _ = self.get("/api/songs")
            self.assertEqual(status, 200)
        finally:
            self.state.mode = "demo"


if __name__ == "__main__":
    unittest.main()
