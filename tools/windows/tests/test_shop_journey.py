"""``shop_fixture.py`` and ``shop_journey.py``: Item Shop fixture modes and journey phases (issue #224).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import shop_fixture as f  # noqa: E402  (sibling module)
import shop_journey as j  # noqa: E402  (sibling module)


class ShopStateTests(unittest.TestCase):
    """Mode switches and request routing."""

    def test_defaults_defer_to_mock(self):
        state = f.ShopState()
        self.assertIsNone(state.route("/api/shop"))
        self.assertIsNone(state.route("/api/songs"))
        self.assertEqual(state.route(f.CONTROL_PATH), "control")

    def test_modes_route_shop_and_catalogue(self):
        state = f.ShopState(shop="empty")
        self.assertEqual(state.route("/api/shop"), "shop-empty")
        for mode in ("error", "slow"):
            self.assertEqual(state.update({"shop": [mode]}), {"shop": mode, "songs": "ok"})
            self.assertEqual(state.route("/api/shop"), f"shop-{mode}")
        self.assertEqual(state.update({"shop": ["demo"], "songs": ["error"]}), {"shop": "demo", "songs": "error"})
        self.assertIsNone(state.route("/api/shop"))
        self.assertEqual(state.route("/api/songs"), "songs-error")
        self.assertIsNone(state.route("/api/publication"))

    def test_update_keeps_unnamed_mode_and_last_value_wins(self):
        state = f.ShopState(songs="error")
        self.assertEqual(state.update({"shop": ["empty", "error"]}), {"shop": "error", "songs": "error"})

    def test_slow_holds_until_released(self):
        state = f.ShopState(shop="slow", slow_seconds=0.01)
        self.assertFalse(state.released.is_set())
        self.assertFalse(state.released.wait(0.01))
        state.update({"songs": ["error"]})
        self.assertFalse(state.released.is_set())
        state.update({"shop": ["demo"]})
        self.assertTrue(state.released.is_set())
        state.update({"shop": ["slow"]})
        self.assertFalse(state.released.is_set())
        self.assertTrue(f.ShopState().released.is_set())

    def test_rejects_unknown_keys_and_modes(self):
        state = f.ShopState()
        for query in ({"scenario": ["x"]}, {"shop": ["closed"]}, {"songs": ["slow"]}):
            with self.assertRaises(ValueError):
                state.update(query)
        self.assertEqual(state.update({}), {"shop": "demo", "songs": "ok"})
        with self.assertRaises(ValueError):
            f.ShopState(shop="nope")


class ShopJourneyPhaseTests(unittest.TestCase):
    """Scenario splitting and screenshot expansion."""

    def test_leading_switch_and_shots(self):
        shots = Path("out")
        got = j.phases(["@shop=error", "waitfor:id=a", "{shot:x}", "@shop=demo", "invoke:id=b"], shots, "wide")
        self.assertEqual(got, [("shop=error", ["waitfor:id=a", f"shot:{shots / 'x-wide.png'}"]),
                               ("shop=demo", ["invoke:id=b"])])

    def test_drops_shots_without_directory(self):
        self.assertEqual(j.phases(["waitfor:id=a", "{shot:x}"], None, "compact"), [(None, ["waitfor:id=a"])])
        self.assertEqual(j.phases([], None, "compact"), [])

    def test_every_contract_state_has_a_scenario(self):
        steps = " ".join(" ".join(s) for _, _, _, s, *_ in j.SCENARIOS.values())
        for marker in ("fst.shop.hidden", "fst.shop.empty", "fst.service-status.retry", "fst.shop.list",
                       "fst.shop.grid", "fst.shop.badge.new", "fst.shop.badge.leaving", "fst.shop.external",
                       "fst.song-detail.shop", "fst.shop.song-details-error", "fst.shop.filter.empty",
                       "fst.shop.filter.empty-reset", "fst.shop.sort-paused", "shop=slow", "You're offline"):
            self.assertIn(marker, steps)


if __name__ == "__main__":
    unittest.main()
