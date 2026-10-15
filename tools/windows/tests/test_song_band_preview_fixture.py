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

    def test_far_board_pages_mix_rank_widths(self):
        # Issue #594: page 40 holds #976-#1,000 and page 400 #9,976-#10,000, so one page crosses a rank-width boundary.
        for page, first, last in ((40, 976, 1_000), (400, 9_976, 10_000)):
            body = f.far_board_payload("fixture-pulse", 25, (page - 1) * 25, "fixture-player-1")
            self.assertEqual([e["rank"] for e in body["entries"]], list(range(first, last + 1)))
            self.assertEqual(body["count"], 25)
            self.assertEqual(body["totalEntries"], f.FAR_BOARD_TOTAL)
            self.assertTrue(all(e["bandType"] == "Band_Duets" and len(e["members"]) == 2 for e in body["entries"]))
            self.assertEqual(body["selectedPlayerEntry"]["rank"], 1_234)
        last_page = f.far_board_payload("fixture-pulse", 25, 10_000, None)
        self.assertEqual([e["rank"] for e in last_page["entries"]], list(range(10_001, f.FAR_BOARD_TOTAL + 1)))
        self.assertIsNone(last_page["selectedPlayerEntry"])
        own = f.far_board_payload("fixture-pulse", 25, 1_225, "fixture-player-1")["entries"][8]
        self.assertEqual((own["rank"], own["members"][0]["accountId"]), (1_234, "fixture-player-1"))

    def test_rank_column_journey_guards_the_full_board_rail(self):
        # The full Song Band Leaderboard's rank rail (issue #594) is gated in CI at default and 225% text: each page
        # asserts a mixed-width rank pair's rank cells and member lists line up.
        from tools.windows import ui_ci
        journey = JOURNEY.with_name("a11y-song-band-rank-column.json")
        pages = {p["name"]: p for p in json.loads(journey.read_text(encoding="utf-8"))}
        pairs = {"sbl-rank-column-1000": ("999:999", "1000:1000"), "sbl-rank-column-10000": ("9999:9999", "10000:10000")}
        runs = {(r.mode, name) for r in ui_ci.RUNS if r.pages == journey.name for name in r.only.split(",")}
        for base, (low, high) in pairs.items():
            for name, mode in ((base, "normal"), (base + "-large-text", "text-225")):
                with self.subTest(page=name):
                    page = pages[name]
                    self.assertEqual(page["fixture"], ["song_band_preview_fixture.py", "--bands", "far"])
                    self.assertIn((mode, name), runs)
                    if mode != "normal":
                        # #455: the pinned band row wraps its whole name at large text, so the compact window at 225%
                        # leaves room for one card only; the pair is checked in the medium window.
                        self.assertEqual(page["sizes"], ["medium"])
                    row = "raw=fst.song-band-leaderboard.row.band-fixture-band_duets-"
                    for part in ("rank", "members"):
                        self.assertIn(f"assertaligned:{row}{low}.{part}|{row}{high}.{part}", page["after_ready"])

    def test_surface_pages_pin_the_opaque_bordered_fallback(self):
        # surface-materials R4 (issue #426, for #64): transparency off, in-app Less Transparency or Increase Contrast make
        # every plain band row's FSTCardSurfaceBrush opaque #121826 with a visible rim; with transparency on the fill stays
        # translucent at the same probe point, so the opaque probe is not vacuous. Since the one-card previews (#643,
        # surface-materials R6, leaderboard-row R10) the in-card rows draw no rim: the visible edge is the card's border,
        # 9 epx outside the rows (1 border + 8 padding), probed beside both rows and above the first (#658).
        from tools.windows import a11y_matrix as m
        from tools.windows import uiwin as u
        pages = {p["name"]: p for p in json.loads(JOURNEY.read_text(encoding="utf-8"))}
        opaque = "fill:L6,M0=#121826~1|R6,M0=@fill~0|C0,T4=@fill~0|C0,B4=@fill~0"
        visible = {"Band_Duets.0": "bg:L-15,M0|L-9,M0!=@fill~6|C0,T-9!=@fill~6|R-8,M0!=@fill~6|L-9,M0!=@bg~6|C0,T-9!=@bg~6|R-8,M0!=@bg~6",
                   "Band_Duets.1": "bg:L-15,M0|L-9,M0!=@fill~6|R-8,M0!=@fill~6|L-9,M0!=@bg~6|R-8,M0!=@bg~6"}
        strong = {"Band_Duets.0": "L-9,M0=#84828A~40|C0,T-9=#84828A~40|R-8,M0=#84828A~40",
                  "Band_Duets.1": "L-9,M0=#84828A~40|R-8,M0=#84828A~40"}
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
                    self.assertIn(f"assertpaint:id=fst.song-detail.band-row.{row}|{opaque}|{edge[row]}", steps)
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
        self.state.mode = "far"
        far = json.loads(self.get(path)[2])["bands"]
        self.assertEqual(far[0]["selectedPlayerEntry"]["rank"], 1_234)
        self.assertEqual([e["rank"] for e in far[0]["entries"]], list(range(1, 11)))
        board = "/api/leaderboard/fixture-pulse/bands/Band_Duets?top=25&offset=975&accountId=fixture-player-1"
        status, _, body = self.get(board)
        self.assertEqual(status, 200)
        self.assertEqual([e["rank"] for e in json.loads(body)["entries"]][-2:], [999, 1_000])
        self.state.mode = "full"
        self.assertEqual(json.loads(self.get(board)[2])["totalEntries"], 29)  # Other modes leave the mock's board.
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
