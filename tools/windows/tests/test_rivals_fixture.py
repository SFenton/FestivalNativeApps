"""``rivals_fixture.py``: anonymized names follow the requested rival into detail bodies.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import rivals_fixture as f  # noqa: E402  (adds tools/ for mock_service)

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
