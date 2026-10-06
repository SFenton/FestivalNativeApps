"""``notifications_fixture.py`` and ``notifications_journey.py``: feed modes, read counting and journey phases (#229).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import notifications_fixture as f  # noqa: E402  (sibling module)
import notifications_journey as j  # noqa: E402  (sibling module)

READ = "/api/player/fixture-player-1/notifications"


class FeedStateTests(unittest.TestCase):
    """Mode switches, request routing and the read counter."""

    def test_routes_reads_controls_and_defers_the_rest(self):
        state = f.FeedState()
        self.assertEqual(state.route(f.CONTROL_PATH), ("control", ""))
        self.assertEqual(state.route(READ), ("rich", "fixture-player-1"))
        self.assertIsNone(state.route("/api/songs"))
        self.assertIsNone(state.route("/api/player/real-account/notifications"))

    def test_account_feeds_apply_only_in_rich_mode(self):
        state = f.FeedState()
        for account, feed in f.ACCOUNT_FEEDS.items():
            self.assertEqual(state.route(f"/api/player/{account}/notifications"), (feed, account))
        state.update({"feed": ["error"]})
        self.assertEqual(state.route("/api/player/fixture-feed-empty/notifications"), ("error", "fixture-feed-empty"))
        state.update({"feed": ["mock"]})
        self.assertIsNone(state.route(READ))

    def test_counts_reads_until_reset(self):
        state = f.FeedState()
        self.assertEqual(state.update({}), {"feed": "rich", "reads": 0})
        state.route(READ)
        state.route(f.CONTROL_PATH)
        state.route("/api/songs")
        state.route("/api/player/fixture-feed-new/notifications")
        self.assertEqual(state.update({"feed": ["empty"]}), {"feed": "empty", "reads": 2})
        self.assertEqual(state.update({"reset": ["1"]}), {"feed": "empty", "reads": 0})

    def test_slow_holds_until_released(self):
        state = f.FeedState(feed="slow", slow_seconds=0.01)
        self.assertFalse(state.released.is_set())
        state.update({"reset": ["1"]})
        self.assertFalse(state.released.is_set())
        state.update({"feed": ["rich"]})
        self.assertTrue(state.released.is_set())
        self.assertTrue(f.FeedState().released.is_set())

    def test_rejects_unknown_keys_and_modes(self):
        state = f.FeedState()
        for query in ({"scenario": ["x"]}, {"feed": ["closed"]}):
            with self.assertRaises(ValueError):
                state.update(query)
        with self.assertRaises(ValueError):
            f.FeedState(feed="nope")


class FeedShapeTests(unittest.TestCase):
    """The synthetic feeds match the wire shape the app validates."""

    def test_rich_feed_rows(self):
        feed = f.rich_feed("fixture-player-1")
        self.assertTrue(feed["notificationsGenerated"])
        guids = [item["notificationGuid"] for item in feed["items"]]
        self.assertEqual(guids, [f"fixture-notif-{row}" for row in j.RICH_ROWS])
        self.assertEqual(sorted({item["eventId"] for item in feed["items"]}), [1, 2, 3, 4, 5])
        days = [item["detectedAt"] for item in feed["items"]]
        self.assertEqual(days, sorted(days, reverse=True))
        shop = feed["items"][-1]
        self.assertIsNone(shop["accountId"])
        self.assertTrue(all(item["accountId"] == "fixture-player-1" for item in feed["items"][:-1]))

    def test_empty_feeds(self):
        self.assertEqual(f.empty_feed(True)["items"], [])
        self.assertTrue(f.empty_feed(True)["notificationsGenerated"])
        self.assertEqual(f.empty_feed(False)["sourceRunId"], None)
        self.assertFalse(f.empty_feed(False)["notificationsGenerated"])

    def test_media_feed_rows(self):
        feed = f.media_feed("fixture-feed-media")
        guids = [item["notificationGuid"] for item in feed["items"]]
        self.assertEqual(guids, [f"fixture-notif-{row}" for row in j.MEDIA_ROWS])
        self.assertEqual(set(j.MEDIA_NAMES), set(j.MEDIA_ROWS))
        self.assertEqual(len({item["eventId"] for item in feed["items"]}), len(guids))
        days = [item["detectedAt"] for item in feed["items"]]
        self.assertEqual(days, sorted(days, reverse=True))
        self.assertTrue(all(item["songId"] and item["accountId"] == "fixture-feed-media" for item in feed["items"]))
        # One multi-chart row (art above an instrument grid) and every remaining song flag kind.
        self.assertEqual(len(feed["items"][0]["payload"]["coalescedInstruments"]), 3)
        self.assertEqual({item["eventKind"] for item in feed["items"]},
                         {"player_score_pb", "player_first_score", "player_stars_improved",
                          "player_gold_stars_achieved", "player_difficulty_bumped"})
        self.assertIn("Affected instruments: Lead, Bass, Drums.", j.MEDIA_NAMES["grid"])
        state = f.FeedState()
        state.update({"feed": ["media"]})
        self.assertEqual(state.route(READ), ("media", "fixture-player-1"))


class NotificationsJourneyPhaseTests(unittest.TestCase):
    """Scenario splitting, fixture checks and screenshot expansion."""

    def test_switches_checks_and_shots(self):
        shots = Path("out")
        got = j.phases(["@feed=empty", "waitfor:id=a", "{shot:x}", "?reads=0", "@feed=rich", "invoke:id=b"],
                       shots, "wide")
        self.assertEqual(got, [("feed=empty", ["waitfor:id=a", f"shot:{shots / 'x-wide.png'}"]),
                               ("?reads=0", []), ("feed=rich", ["invoke:id=b"])])

    def test_drops_shots_without_directory(self):
        self.assertEqual(j.phases(["waitfor:id=a", "{shot:x}"], None, "compact"), [(None, ["waitfor:id=a"])])
        self.assertEqual(j.phases([], None, "compact"), [])

    def test_every_contract_state_has_a_scenario(self):
        for state in ("no-profile", "empty-generated", "empty-not-generated", "unread-section", "older-section",
                      "tap-navigate-song", "tap-navigate-rankings"):
            self.assertIn(state, j.SCENARIOS)
        steps = " ".join(" ".join(s) for _, _, s, _ in j.SCENARIOS.values())
        for marker in ("fst.notifications.empty", "fst.notifications.list", "fst.notifications.retry",
                       "fst.notifications.loading", "fst.song-detail.title", "Rank by: FC Rate", "New notifications",
                       "Older notifications", "?reads=0", "feed=slow", "key:esc"):
            self.assertIn(marker, steps)


if __name__ == "__main__":
    unittest.main()
