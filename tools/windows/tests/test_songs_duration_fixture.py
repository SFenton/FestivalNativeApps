"""Songs bucket-heading journey tooling: ``songs_duration_fixture.py`` (issue #282).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import songs_duration_fixture as f  # noqa: E402  (sibling module)
import mock_service  # noqa: E402

JOURNEY = Path(__file__).resolve().parents[1] / "journeys" / "a11y-songs-bucket-headers.json"


def bucket(seconds: int) -> str:
    """The Windows Duration heading for ``seconds`` (``SongQuery`` buckets)."""
    if seconds < 60:
        return "Under 1 Minute"
    if seconds >= 600:
        return "Over 10 Minutes"
    minutes = seconds // 60
    return f"{minutes}–{minutes + 1} Minutes"


class DurationTests(unittest.TestCase):
    """The synthetic durations."""

    def test_every_bucket_covered(self):
        songs = copy.deepcopy(mock_service.LARGE_CATALOGUE_SONGS)
        f.add_durations(songs)
        headings = {bucket(song["durationSeconds"]) for song in songs}
        expected = {"Under 1 Minute", "Over 10 Minutes"} | {f"{m}–{m + 1} Minutes" for m in range(1, 10)}
        self.assertEqual(headings, expected)

    def test_positive_whole_seconds(self):
        for index in range(1, 2000):
            seconds = f.duration_for(index)
            self.assertIsInstance(seconds, int)
            self.assertTrue(30 <= seconds <= 743, seconds)

    def test_in_place_and_stable(self):
        songs = [{"songId": "a"}, {"songId": "b"}]
        f.add_durations(songs)
        self.assertEqual([s["durationSeconds"] for s in songs], [f.duration_for(1), f.duration_for(2)])
        f.add_durations(songs)
        self.assertEqual([s["durationSeconds"] for s in songs], [f.duration_for(1), f.duration_for(2)])

    def test_shared_catalogue_untouched_on_import(self):
        self.assertTrue(all("durationSeconds" not in s for s in mock_service.LARGE_CATALOGUE_SONGS))


class JourneyTests(unittest.TestCase):
    """The bucket-heading journey parses and scrolls every heading through the canonical list."""

    def test_journey_steps_parse(self):
        import uiwin  # noqa: PLC0415  (sibling module; path set above)
        pages = json.loads(JOURNEY.read_text(encoding="utf-8"))
        self.assertGreaterEqual(len(pages), 6)
        for page in pages:
            for step in page.get("ready", []) + page.get("after_ready", []):
                uiwin.parse_step(step)

    def test_live_pages_need_no_fixture(self):
        pages = json.loads(JOURNEY.read_text(encoding="utf-8"))
        live = [p for p in pages if p["name"].endswith("-live")]
        self.assertTrue(live)
        for page in live:
            self.assertNotIn("fixture", page)
            self.assertFalse(page.get("profile", "").startswith("fixture-"))


if __name__ == "__main__":
    unittest.main()
