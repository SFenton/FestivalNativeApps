"""``suggestions_journey.py``: launch arguments and the desktop-lock retry rule (issue #205).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import suggestions_journey as j  # noqa: E402  (sibling module)


class LockBoundTests(unittest.TestCase):
    """Only a time-bounded state that expired behind the desktop lock is retried."""

    QUEUED = "uiwin drive failed:\nwaiting for host lock 'desktop' (holder: x) ...\nerror: no on-screen element"

    def test_loading_retried_after_lock_wait(self):
        self.assertTrue(j.lock_bound_miss("loading", self.QUEUED))

    def test_loading_failure_without_lock_wait_is_real(self):
        self.assertFalse(j.lock_bound_miss("loading", "error: driver: no on-screen element id=fst.suggestions.loading"))

    def test_other_scenarios_never_retried(self):
        for name in set(j.SCENARIOS) - j.LOCK_BOUND:
            self.assertFalse(j.lock_bound_miss(name, self.QUEUED), name)

    def test_lock_bound_scenarios_exist(self):
        self.assertLessEqual(j.LOCK_BOUND, set(j.SCENARIOS))


if __name__ == "__main__":
    unittest.main()
