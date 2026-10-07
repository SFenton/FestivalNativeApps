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

    def test_unlabeled_states_are_scanned_and_tab_walked(self):
        """Score and a lone Item Shop bucket (one unlabeled section, fixture and live) must fail on any Axe error and
        on any focus stop between the page's last action and the first row, or above the first row by arrow key
        (``SongsPage.ApplyGroupHeaderAccess``; without it Up from the first row lands on an unnamed header Group)."""
        pages = {p["name"]: p for p in json.loads(JOURNEY.read_text(encoding="utf-8"))}
        expected = {"hdr-score-unlabeled": "id=fst.songs.row.fixture-orbit", "hdr-shop-lone": "id=fst.songs.row.fixture-song-1",
                    "hdr-score-live": "class=ListViewItem", "hdr-shop-lone-live": "class=ListViewItem"}
        for name, first_row in expected.items():
            with self.subTest(name):
                page = pages[name]
                self.assertIs(page.get("scan"), True)
                steps = page["after_ready"]
                sequence = ["key:ctrl+f", "assertfocus:name=Search songs", "key:tab", "assertfocus:id=fst.songs.sort",
                            "key:tab", "assertfocus:id=fst.songs.filter", "key:tab", f"assertfocus:{first_row}",
                            "key:up", f"assertfocus:{first_row}", "key:shift+tab", "assertfocus:id=fst.songs.filter"]
                start = steps.index(sequence[0])
                self.assertEqual(steps[start:start + len(sequence)], sequence)
                self.assertLess(steps.index("waitgone:id=fst.songs.section-header@5"), start)
        for name in ("hdr-score-unlabeled", "hdr-shop-lone"):
            with self.subTest(f"{name} scans the top"):
                steps = pages[name]["after_ready"]
                self.assertLess(steps.index("assertfocus:id=fst.songs.filter", steps.index("key:shift+tab")),
                                steps.index("scan:{stem}-top"))
                # The required end-of-page scan runs on a deterministic edge (testing/windows.md, issue #259), after
                # the scrolled-out header is realized again (its recycled container must be re-hidden).
                self.assertEqual(steps[-1], "assertstate:id=fst.songs.list|scroll=0")
        self.assertEqual(pages["hdr-shop-lone"]["settings"]["songShopFilter"], {"available": False, "unavailable": True})


if __name__ == "__main__":
    unittest.main()
