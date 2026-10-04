"""What's New journeys (``journeys/whats-new.json``, ``whats-new-pointer.json``, ``a11y-whats-new.json``) and
``ui_journey`` launch args.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import unittest
from pathlib import Path

from tools.windows import ui_journey as j
from tools.windows import uiwin as u

_JOURNEYS = Path(__file__).resolve().parents[1] / "journeys"


def _load(name: str) -> list[dict]:
    """Reads a journey/page list.

    Args:
        name: File name under ``tools/windows/journeys``.

    Returns:
        The decoded list.
    """
    return json.loads((_JOURNEYS / name).read_text(encoding="utf-8"))


class WhatsNewJourneyTests(unittest.TestCase):
    """Journey files parse, cover every reachable state and share the data folder across the relaunch."""

    def test_every_step_parses(self):
        for journey in [*_load("whats-new.json"), *_load("whats-new-pointer.json")]:
            self.assertIn(journey["preset"], u.PRESETS, journey["name"])
            for step in journey["steps"]:
                with self.subTest(journey=journey["name"], step=step):
                    u.parse_step(step.replace("{shots}", "C:/tmp"))
        for page in _load("a11y-whats-new.json"):
            for step in [*page.get("ready", []), *page.get("after_ready", []), *page.get("teardown", [])]:
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step)

    def test_covers_every_reachable_state(self):
        names = [journey["name"] for journey in _load("whats-new.json")]
        # waiting-for-first-run + presented, presented + dismissed, hidden-seen (after the relaunch), replay.
        for name in ("launch-order-carousel-then-whats-new", "presented-dismiss-records",
                     "dismissed-relaunch-hidden-seen", "replay-from-settings-keyboard"):
            self.assertIn(name, names)
        # The relaunch must follow the dismissal and read the same seen-state file.
        self.assertLess(names.index("presented-dismiss-records"), names.index("dismissed-relaunch-hidden-seen"))
        by_name = {journey["name"]: journey for journey in _load("whats-new.json")}
        first = by_name["presented-dismiss-records"]["extra"]
        second = by_name["dismissed-relaunch-hidden-seen"]["extra"]
        self.assertEqual(first["FST_DEBUG_DATA_DIR"], second["FST_DEBUG_DATA_DIR"])
        self.assertEqual(first["FST_DEBUG_WHATS_NEW"], "fresh")
        self.assertEqual(second["FST_DEBUG_WHATS_NEW"], "on")

    def test_state_journeys_need_no_real_pointer(self):
        # A locked console drops or refuses real mouse input; the state journeys use UIA patterns and posted keys only.
        for journey in _load("whats-new.json"):
            for step in journey["steps"]:
                parsed = u.parse_step(step.replace("{shots}", "C:/tmp"))
                self.assertNotEqual(parsed.get("selector", {}).get("kind"), "xy", f"{journey['name']}: {step}")
        pointer = {journey["name"]: journey for journey in _load("whats-new-pointer.json")}
        for name, dialog in (("outside-click-dismisses-whats-new", "fst.whats-new.dialog"),
                             ("outside-click-dismisses-first-run", "fst.first-run.dialog")):
            self.assertIn(f"waitgone:id={dialog}@5", pointer[name]["steps"])

    def test_launch_args_expand_shots_in_extra(self):
        journey = {"route": "/songs", "preset": "compact", "args": ["--reduce-motion"],
                   "extra": {"FST_DEBUG_DATA_DIR": "{shots}/data", "FST_DEBUG_WHATS_NEW": "on"}}
        args = j.launch_args(journey, 8123, Path("C:/shots"))
        self.assertIn("--arg=http://127.0.0.1:8123/", args)
        self.assertIn("--arg=--reduce-motion", args)
        self.assertIn(f"--extra=FST_DEBUG_DATA_DIR={Path('C:/shots')}/data", args)
        self.assertIn("--extra=FST_DEBUG_WHATS_NEW=on", args)
        self.assertEqual(args[args.index("--preset") + 1], "compact")

    def test_launch_args_default_preset(self):
        args = j.launch_args({"route": "/settings"}, 1, Path("."))
        self.assertEqual(args[args.index("--preset") + 1], "medium")
        self.assertFalse(any(a.startswith("--extra=") for a in args))


if __name__ == "__main__":
    unittest.main()
