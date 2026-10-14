"""Tests for the page-loading fixture's bounded, read-only delay selection."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import loading_fixture


class LoadingFixtureTests(unittest.TestCase):
    """Only page gates, never Paths, card previews or operational reads, are delayed."""

    def test_page_gates_are_delayed(self):
        for path in ("/api/leaderboard/fixture-pulse/all", "/api/rankings/Solo_Guitar", "/api/rankings/combo"):
            with self.subTest(path=path):
                self.assertTrue(loading_fixture.delayed(path))

    def test_other_reads_are_unchanged(self):
        for path in ("/api/publication", "/api/songs", "/api/leaderboard/fixture-pulse/bands/all",
                     "/api/paths/fixture-pulse/Solo_Guitar/Expert", "/api/rankings/bands/Band_Duets",
                     "/api/rankings/Solo_Guitar/fixture-player-1", "/api/service-info"):
            with self.subTest(path=path):
                self.assertFalse(loading_fixture.delayed(path))

    def test_delay_finishes_before_request_timeout(self):
        self.assertGreater(loading_fixture.DELAY_SECONDS, 10)
        self.assertLess(loading_fixture.DELAY_SECONDS, 30)


if __name__ == "__main__":
    unittest.main()
