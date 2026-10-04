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


if __name__ == "__main__":
    unittest.main()
