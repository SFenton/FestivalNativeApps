"""Song header journey tooling: ``song_header_fixture.py`` and ``journeys/song-header-title.json`` (issue #315).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import song_header_fixture as f  # noqa: E402  (sibling module)
import mock_service  # noqa: E402
from tools.windows import uiwin as u  # noqa: E402

JOURNEYS = Path(__file__).resolve().parents[1] / "journeys" / "song-header-title.json"


class FixtureTests(unittest.TestCase):
    """The wrapper renames only the long song and changes the catalogue ETag."""

    def test_install_renames_pulse_only(self):
        with mock.patch.object(mock_service, "DEMO_SONGS", mock_service.DEMO_SONGS), \
                mock.patch.object(mock_service, "SONGS_ETAG", mock_service.SONGS_ETAG):
            original = mock_service.DEMO_SONGS
            f.install()
            songs = {song["songId"]: song for song in mock_service.DEMO_SONGS["songs"]}
            self.assertEqual((songs[f.SONG_ID]["title"], songs[f.SONG_ID]["artist"]), (f.LONG_TITLE, f.LONG_ARTIST))
            self.assertEqual(songs["fixture-orbit"]["title"], "Fixture Orbit")
            self.assertEqual(mock_service.SONGS_ETAG, f.ETAG)
            # The loaded fixture object itself is untouched.
            self.assertEqual(next(s for s in original["songs"] if s["songId"] == f.SONG_ID)["title"], "Fixture Pulse")

    def test_short_artist_keeps_demo_artist(self):
        with mock.patch.object(mock_service, "DEMO_SONGS", mock_service.DEMO_SONGS), \
                mock.patch.object(mock_service, "SONGS_ETAG", mock_service.SONGS_ETAG):
            demo_artist = next(s for s in mock_service.DEMO_SONGS["songs"] if s["songId"] == f.SONG_ID)["artist"]
            f.install(short_artist=True)
            song = next(s for s in mock_service.DEMO_SONGS["songs"] if s["songId"] == f.SONG_ID)
            self.assertEqual((song["title"], song["artist"]), (f.LONG_TITLE, demo_artist))
            self.assertLess(len(demo_artist), 30)
            self.assertEqual(mock_service.SONGS_ETAG, f.SHORT_ARTIST_ETAG)

    def test_main_strips_short_artist_flag(self):
        with mock.patch.object(f, "install") as install, mock.patch.object(f.mock_service, "main") as main, \
                mock.patch.object(sys, "argv", ["song_header_fixture.py", "--port", "0", "--short-artist"]):
            f.main()
            install.assert_called_once_with(True)
            main.assert_called_once()
            self.assertEqual(sys.argv, ["song_header_fixture.py", "--port", "0"])

    def test_long_text_overflows_compact_headers(self):
        # 500 epx window minus page padding and 80-128 epx art: no header column is wider than ~330 epx, and these
        # strings are far wider than that at every header type size.
        self.assertGreater(len(f.LONG_TITLE), 70)
        self.assertGreater(len(f.LONG_ARTIST), 60)


class JourneyTests(unittest.TestCase):
    """Every song header is checked moving with motion on and ellipsized with motion off."""

    def setUp(self):
        self.journeys = json.loads(JOURNEYS.read_text(encoding="utf-8"))

    def test_steps_parse(self):
        for journey in self.journeys:
            for step in journey["steps"]:
                u.parse_step(step.replace("{shots}", "C:\\shots"))

    def test_each_header_line_moving_and_static(self):
        checks: dict[str, set[str]] = {}
        for journey in self.journeys:
            reduced = "--reduce-motion" in journey.get("args", [])
            lone = "--short-artist" in journey.get("fixture", [])
            self.assertEqual(journey["preset"], "compact")
            self.assertIn("--no-art", journey["args"])  # a static backdrop: only the marquee can change pixels
            for step in journey["steps"]:
                if step.startswith("assertmarquee:"):
                    parsed = u.parse_step(step)
                    if lone:
                        # Only the title overflows: it scrolls on its own while the short artist stays still.
                        expected = "fits" if parsed["selector"]["value"].endswith("artist") else "moving"
                        self.assertEqual(parsed["mode"], expected, step)
                        continue
                    self.assertEqual(parsed["mode"], "static" if reduced else "moving", step)
                    checks.setdefault(parsed["selector"]["value"], set()).add(parsed["mode"])
        expected = {"fst.song-detail.title", "fst.song-detail.artist", "fst.song-detail.pinned-title",
                    "fst.song-detail.pinned-artist", "fst.song-leaderboard.title", "fst.song-leaderboard.artist",
                    "fst.song-band-leaderboard.title", "fst.song-band-leaderboard.artist",
                    "fst.history.title", "fst.history.artist"}
        self.assertEqual(set(checks), expected)
        # The Player History route is its own page again (issue #324) with the shared SongLeaderboardHeader.
        history = [j for j in self.journeys if j["route"].endswith("/history")]
        self.assertEqual(len(history), 2)
        for journey in history:
            self.assertTrue(any(s.startswith("assertmarquee:id=fst.history.title") for s in journey["steps"]))
        self.assertTrue(all(modes == {"moving", "static"} for modes in checks.values()), checks)

    def test_two_overflowing_lines_scroll_in_lockstep(self):
        """Every header whose title and artist both scroll checks they move the same pixels (song-header R2)."""
        synced: set[tuple[str, str]] = set()
        for journey in self.journeys:
            moving = "--reduce-motion" not in journey.get("args", []) and "--short-artist" not in journey.get("fixture", [])
            for step in journey["steps"]:
                if step.startswith("assertmarqueesync:"):
                    self.assertTrue(moving, f"{journey['name']}: lockstep needs two moving lines")
                    parsed = u.parse_step(step)
                    synced.add((parsed["selector"]["value"], parsed["other"]["value"]))
        self.assertEqual(synced, {(f"fst.{h}.title", f"fst.{h}.artist") for h in
                                  ("song-detail", "song-leaderboard", "song-band-leaderboard", "history")}
                         | {("fst.song-detail.pinned-title", "fst.song-detail.pinned-artist")})
        lone = [j for j in self.journeys if "--short-artist" in j.get("fixture", [])]
        self.assertEqual({j["route"] for j in lone}, {"/songs/fixture-pulse", "/songs/fixture-pulse/Solo_Guitar"})


if __name__ == "__main__":
    unittest.main()
