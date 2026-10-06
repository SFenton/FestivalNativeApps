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
        # The multi-chart row carries populated coalescedEvents on three charts (web per-chart clauses and flag groups).
        events = feed["items"][0]["payload"]["coalescedEvents"]
        self.assertGreaterEqual(len(events), 2)
        self.assertEqual({e["instrument"] for e in events}, set(feed["items"][0]["payload"]["coalescedInstruments"]))
        self.assertIn("Lead: New High Score, Rank Up. Bass: Full Combo, Gold Stars. Drums: First Play.", j.MEDIA_NAMES["grid"])
        self.assertTrue(feed["items"][-1]["payload"]["newFullCombo"])
        self.assertIn("New High Score, Full Combo.", j.MEDIA_NAMES["pb"])
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

    def test_media_rows_check_paint_and_bold_for_every_row(self):
        steps = j.SCENARIOS["media-rows"][2]
        for row in j.MEDIA_ROWS:
            paint = next(s for s in steps if s.startswith(f"assertpaint:{j.ROW}fixture-notif-{row}|"))
            bold = next(s for s in steps if s.startswith(f"assertbold:{j.ROW}fixture-notif-{row}|"))
            self.assertIn(f",B18={j.MEDIA_FLAGS[row]}~8", paint)
            self.assertIn(j.UNREAD_DOT, paint)
            self.assertTrue(bold.endswith("|".join(j.MEDIA_BOLD[row])))
        grid, first = j.media_paint("grid")[0], j.media_paint("first")[0]
        self.assertIn("=#FFFFFF~40", grid)
        self.assertIn(f"L122,B18={j.MEDIA_FLAGS['grid']}~8", grid)
        self.assertIn("L100,B18=#FFFFFF~40", grid)
        self.assertIn("!=#FFFFFF~40", first)
        self.assertNotIn(j.CARD_STROKE, grid)
        self.assertIn(j.CARD_STROKE, first)

    def test_media_paint_steps_parse(self):
        import uiwin  # noqa: PLC0415  (sibling module, path set above)
        for row in j.MEDIA_ROWS:
            for step in j.media_paint(row):
                self.assertTrue(uiwin.parse_step(step)["selector"]["value"].endswith(row))

    def test_matrix_paint_pages_cover_themes_text_and_scale(self):
        import json  # noqa: PLC0415
        import uiwin  # noqa: PLC0415
        path = Path(__file__).resolve().parents[1] / "journeys" / "a11y-notifications.json"
        pages = {p["name"]: p for p in json.loads(path.read_text(encoding="utf-8"))}
        exact, text, hc = (pages[f"paint-notifications-media{s}"] for s in ("", "-text", "-hc"))
        self.assertEqual(set(exact["modes"]), {"light-theme", "dark-theme", "scale-150"})
        self.assertEqual(text["modes"], ["text-200"])
        self.assertEqual(set(hc["modes"]), {"hc-night-sky", "hc-desert"})
        for row in ("grid", "first", "stars"):
            for step in j.media_paint(row):
                self.assertIn(step, exact["after_ready"])
        self.assertIn(j.media_paint("grid")[0], text["after_ready"])
        self.assertEqual(sum(s.startswith("assertbold:") for s in text["after_ready"]), 2)
        self.assertEqual(sum(s.startswith("assertpaint:") for s in hc["after_ready"]), 3)
        self.assertFalse(any("#" in s for s in hc["after_ready"] if s.startswith("assertpaint:")))
        for page in (exact, text, hc):
            for step in page["after_ready"]:
                uiwin.parse_step(step)


if __name__ == "__main__":
    unittest.main()
