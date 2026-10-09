"""Every journey and a11y-matrix page names a fixture that understands its flags.

A journey's ``fixture`` list either names its wrapper first (``["rankings_fixture.py", "--rankings-delay", "3"]``)
or gives flags for the default ``rivals_fixture.py``. Flags only a specific wrapper understands made CI start the
wrong fixture ("fixture service did not start") until journeys named their wrappers (windows-ui CI, 2026-10-09).
"""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

WINDOWS = Path(__file__).resolve().parents[1]
JOURNEYS = WINDOWS / "journeys"
MOCK = WINDOWS.parents[1] / "tools" / "mock_service.py"
DEFAULT = WINDOWS / "rivals_fixture.py"


def _entries():
    for source in sorted(JOURNEYS.glob("*.json")):
        data = json.loads(source.read_text(encoding="utf-8"))
        if not isinstance(data, list):
            continue
        for entry in data:
            if isinstance(entry, dict) and entry.get("fixture"):
                yield source.name, entry.get("name", "?"), list(entry["fixture"])


class JourneyFixtureTests(unittest.TestCase):
    def test_fixture_flags_are_understood_by_the_named_wrapper(self):
        mock = MOCK.read_text(encoding="utf-8")
        problems = []
        for source, name, fixture in _entries():
            script = WINDOWS / fixture[0] if fixture[0].endswith(".py") else DEFAULT
            if not script.exists():
                problems.append(f"{source} {name}: no wrapper {script.name}")
                continue
            text = script.read_text(encoding="utf-8") + mock
            for flag in (f for f in fixture if f.startswith("--")):
                if not re.search(r"""["']""" + re.escape(flag.split("=", 1)[0]) + r"""[="']""", text):
                    problems.append(f"{source} {name}: {flag} is not a {script.name}/mock_service flag; "
                                    "name the wrapper that understands it first in the fixture list")
        self.assertEqual(problems, [])

    def test_named_wrappers_exist(self):
        for source, name, fixture in _entries():
            if fixture[0].endswith(".py"):
                self.assertTrue((WINDOWS / fixture[0]).exists(), f"{source} {name}: {fixture[0]}")

    def test_journey_fixture_resolution(self):
        import sys
        sys.path.insert(0, str(WINDOWS))
        import ui_journey
        self.assertEqual(ui_journey.journey_fixture(("rankings_fixture.py", "--rankings-delay", "3")),
                         (WINDOWS / "rankings_fixture.py", ("--rankings-delay", "3")))
        self.assertEqual(ui_journey.journey_fixture(("--band-rankings", "empty")),
                         (ui_journey.FIXTURE, ("--band-rankings", "empty")))
        override = WINDOWS / "star_rating_fixture.py"
        self.assertEqual(ui_journey.journey_fixture(("--x",), override), (override, ("--x",)))
        self.assertEqual(ui_journey.journey_fixture(()), (None, ()))


if __name__ == "__main__":
    unittest.main()
