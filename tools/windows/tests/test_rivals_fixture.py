"""Windows fixture wrapper: ``--band-rankings`` scenarios (issue #209).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import rivals_fixture as f  # noqa: E402  (sibling module; imports tools/mock_service.py)


class BandRankingsScenarioTests(unittest.TestCase):
    """Scenario responses and argument parsing."""

    def test_other_requests_defer_to_the_mock_service(self):
        for path in ("/api/songs", "/api/rankings/bands/Band_Duets?teamKey=fixture-team-1",
                     "/api/rankings/bands/Band_Duets/fixture-team-1/history"):
            self.assertIsNone(f.band_rankings_response(path, "empty"), path)

    def test_empty_board(self):
        status, body = f.band_rankings_response("/api/rankings/bands/Band_Trios?rankBy=fcrate&page=1&pageSize=25",
                                                "empty")
        self.assertEqual(status, 200)
        self.assertEqual((body["bandType"], body["rankBy"], body["pageSize"]), ("Band_Trios", "fcrate", 25))
        self.assertEqual((body["totalTeams"], body["entries"]), (0, []))

    def test_unavailable(self):
        self.assertEqual(f.band_rankings_response("/api/rankings/bands/Band_Duets", "unavailable")[0], 500)

    def test_anonymous_second_row_has_no_identity(self):
        _, body = f.band_rankings_response("/api/rankings/bands/Band_Duets?page=1&pageSize=25", "anonymous")
        first, second = body["entries"]
        self.assertEqual(body["totalTeams"], 2)
        self.assertEqual(first["teamKey"], "fixture-team-1")
        self.assertEqual((second["bandId"], second["teamKey"]), ("", ""))
        self.assertTrue(all(not (m["displayName"] or "").strip() for m in second["teamMembers"]))

    def test_take_band_rankings(self):
        self.assertEqual(f.take_band_rankings(["--port", "0"]), (None, ["--port", "0"]))
        self.assertEqual(f.take_band_rankings(["--band-rankings", "empty", "--port", "0"]), ("empty", ["--port", "0"]))
        self.assertEqual(f.take_band_rankings(["--band-rankings=anonymous"]), ("anonymous", []))
        for bad in (["--band-rankings"], ["--band-rankings", "nope"], ["--band-rankings="]):
            with self.assertRaises(SystemExit):
                f.take_band_rankings(bad)


if __name__ == "__main__":
    unittest.main()
