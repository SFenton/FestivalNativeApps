"""``rivals_fixture.py``: ``--band-rankings`` scenarios (issue #209) and anonymized names that follow the
requested rival into detail bodies.

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


ms = f.mock_service


class DetailNameTests(unittest.TestCase):
    """``name_detail_bodies`` patches both detail builders and restores cleanly."""

    def setUp(self):
        self.saved = (ms._rival_detail_body, ms._leaderboard_rival_detail_body)

    def tearDown(self):
        ms._rival_detail_body, ms._leaderboard_rival_detail_body = self.saved

    def test_detail_bodies_use_the_requested_rivals_name(self):
        f.name_detail_bodies({"aaa": "Demo Rival 7", "bbb": "Demo Rival 8"})
        self.assertEqual(ms._rival_detail_body("03", "aaa", "demo")["rival"]["displayName"], "Demo Rival 7")
        self.assertEqual(ms._rival_detail_body("03", "bbb", "empty")["rival"]["displayName"], "Demo Rival 8")
        board = ms._leaderboard_rival_detail_body("Solo_Guitar", "totalscore", "bbb", "demo")
        self.assertEqual((board["rival"]["accountId"], board["rival"]["displayName"]), ("bbb", "Demo Rival 8"))

    def test_unknown_rival_keeps_the_mock_name(self):
        expected = self.saved[0]("03", "zzz", "demo")["rival"]
        f.name_detail_bodies({"aaa": "Demo Rival 7"})
        self.assertEqual(ms._rival_detail_body("03", "zzz", "demo")["rival"], expected)

    def test_anonymize_numbers_new_accounts(self):
        names: dict[str, str] = {}
        payload = {"above": [{"accountId": "x", "displayName": "Real"}], "rival": {"accountId": "y", "displayName": "R"}}
        f.anonymize(payload, names)
        self.assertEqual(names, {"x": "Demo Rival 1", "y": "Demo Rival 2"})
        self.assertEqual(payload["rival"]["displayName"], "Demo Rival 2")


if __name__ == "__main__":
    unittest.main()
