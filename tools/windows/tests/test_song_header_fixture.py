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
            self.assertEqual(journey["preset"], "compact")
            self.assertIn("--no-art", journey["args"])  # a static backdrop: only the marquee can change pixels
            for step in journey["steps"]:
                if step.startswith("assertmarquee:"):
                    parsed = u.parse_step(step)
                    self.assertEqual(parsed["mode"], "static" if reduced else "moving", step)
                    checks.setdefault(parsed["selector"]["value"], set()).add(parsed["mode"])
        expected = {"fst.song-detail.title", "fst.song-detail.artist", "fst.song-detail.pinned-title",
                    "fst.song-detail.pinned-artist", "fst.song-leaderboard.title", "fst.song-leaderboard.artist",
                    "fst.song-band-leaderboard.song-title", "fst.song-band-leaderboard.artist"}
        self.assertEqual(set(checks), expected)
        # The Player History route opens Song Detail at Score History, under its pinned title bar.
        history = [j for j in self.journeys if j["route"].endswith("/history")]
        self.assertEqual(len(history), 2)
        for journey in history:
            self.assertTrue(any(s.startswith("assertmarquee:id=fst.song-detail.pinned-title") for s in journey["steps"]))
        self.assertTrue(all(modes == {"moving", "static"} for modes in checks.values()), checks)


if __name__ == "__main__":
    unittest.main()
