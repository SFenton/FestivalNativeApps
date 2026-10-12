"""``rankings_fixture.py``: the Full Rankings scenarios layered on the mock service.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import rankings_fixture as f  # noqa: E402  (sibling module)


class RankingsFixtureTests(unittest.TestCase):
    """Anonymous row and board overrides."""

    def test_anonymous_rank_drops_identity(self):
        build = f.ranking_entry(lambda rank, account, name: {"rank": rank, "accountId": account, "displayName": name})
        anonymous = build(f.ANONYMOUS_RANK, "fixture-rank-13", "Thirteen")
        self.assertEqual(anonymous["accountId"], "")
        self.assertNotIn("displayName", anonymous)
        self.assertEqual(build(12, "fixture-rank-12", "Twelve"),
                         {"rank": 12, "accountId": "fixture-rank-12", "displayName": "Twelve"})

    def test_empty_board_echoes_paging(self):
        status, body = f.board_override(f"/api/rankings/{f.EMPTY_INSTRUMENT}",
                                        {"rankBy": ["fcrate"], "page": ["3"], "pageSize": ["25"]})
        self.assertEqual(status, 200)
        self.assertEqual((body["rankBy"], body["page"], body["pageSize"], body["totalAccounts"], body["entries"]),
                         ("fcrate", 3, 25, 0, []))
        _, defaults = f.board_override(f"/api/rankings/{f.EMPTY_INSTRUMENT}", {})
        self.assertEqual((defaults["rankBy"], defaults["page"], defaults["pageSize"]), ("totalscore", 1, 25))

    def test_failing_board_and_passthrough(self):
        self.assertEqual(f.board_override(f"/api/rankings/{f.FAILING_INSTRUMENT}", {})[0], 500)
        self.assertIsNone(f.board_override("/api/rankings/Solo_Guitar", {}))
        self.assertIsNone(f.board_override("/api/songs", {}))

    def test_rankings_delay_applies_to_solo_board_reads_only(self):
        self.assertTrue(f.is_board_read("/api/rankings/Solo_Guitar"))
        self.assertFalse(f.is_board_read("/api/rankings/Solo_Guitar/fixture-rank-40"))
        self.assertFalse(f.is_board_read("/api/rankings/bands/Band_Duets"))
        self.assertFalse(f.is_board_read("/api/rankings/"))
        self.assertFalse(f.is_board_read("/api/songs"))

    def test_take_rankings_delay(self):
        self.assertEqual(f.take_rankings_delay(["--port", "0", "--rankings-delay", "3"]), (3.0, ["--port", "0"]))
        self.assertEqual(f.take_rankings_delay(["--rankings-delay=1.5"]), (1.5, []))
        self.assertEqual(f.take_rankings_delay(["--port", "0"]), (None, ["--port", "0"]))
        for bad in (["--rankings-delay"], ["--rankings-delay", "x"], ["--rankings-delay=-1"]):
            with self.assertRaises(SystemExit):
                f.take_rankings_delay(bad)

    def test_bands_delay_applies_to_band_board_reads_only(self):
        for path in ("/api/rankings/bands/Band_Duets", "/api/leaderboard/fixture-pulse/bands/Band_Duets",
                     "/api/player/fixture-player-1/bands"):
            self.assertTrue(f.is_band_board_read(path), path)
        for path in ("/api/rankings/bands/", "/api/rankings/bands/Band_Duets/fixture-band-1/history",
                     "/api/leaderboard/fixture-pulse/bands/all", "/api/leaderboard/fixture-pulse/Solo_Guitar",
                     "/api/player/fixture-player-1", "/api/player//bands", "/api/rankings/Solo_Guitar", "/api/songs"):
            self.assertFalse(f.is_band_board_read(path), path)

    def test_rank_delay_applies_to_own_rank_reads_only(self):
        """#527: only the selected player's own-rank read waits, so the boards load and the spotlight stays loading."""
        self.assertTrue(f.is_own_rank_read("/api/rankings/Solo_Guitar/fixture-rank-40"))
        for path in ("/api/rankings/Solo_Guitar", "/api/rankings/Solo_Guitar/fixture-rank-40/history",
                     "/api/rankings/bands/Band_Duets", "/api/rankings/combo/fixture-rank-40",
                     "/api/rankings/Solo_Guitar/", "/api/rankings//fixture-rank-40", "/api/songs"):
            self.assertFalse(f.is_own_rank_read(path), path)
        self.assertEqual(f.take_delay(["--port", "0", "--rank-delay", "20"], "--rank-delay"), (20.0, ["--port", "0"]))

    def test_rank_delay_instrument_limits_the_delay_to_one_card(self):
        """#527: the overview reveals its first cards after their spotlights, so only a later card's read waits."""
        self.assertTrue(f.is_own_rank_read("/api/rankings/Solo_Vocals/fixture-rank-40", "Solo_Vocals"))
        self.assertFalse(f.is_own_rank_read("/api/rankings/Solo_Guitar/fixture-rank-40", "Solo_Vocals"))
        self.assertFalse(f.is_own_rank_read("/api/rankings/Solo_Vocals", "Solo_Vocals"))
        argv = ["--port", "0", "--rank-delay-instrument", "Solo_Vocals", "--rank-delay", "25"]
        instrument, rest = f.take_option(argv, "--rank-delay-instrument")
        self.assertEqual((instrument, rest), ("Solo_Vocals", ["--port", "0", "--rank-delay", "25"]))
        self.assertEqual(f.take_option(["--rank-delay-instrument=Solo_Bass"], "--rank-delay-instrument"),
                         ("Solo_Bass", []))
        self.assertEqual(f.take_option(["--port", "0"], "--rank-delay-instrument"), (None, ["--port", "0"]))
        with self.assertRaises(SystemExit):
            f.take_option(["--rank-delay-instrument"], "--rank-delay-instrument")

    def test_take_bands_delay_leaves_the_rankings_delay(self):
        argv = ["--port", "0", "--rankings-delay", "3", "--bands-delay=2"]
        delay, rest = f.take_rankings_delay(argv)
        self.assertEqual(f.take_delay(rest, "--bands-delay"), (2.0, ["--port", "0"]))
        self.assertEqual(delay, 3.0)
        self.assertEqual(f.take_delay(["--port", "0"], "--bands-delay"), (None, ["--port", "0"]))
        with self.assertRaisesRegex(SystemExit, "--bands-delay"):
            f.take_delay(["--bands-delay", "-2"], "--bands-delay")


if __name__ == "__main__":
    unittest.main()
