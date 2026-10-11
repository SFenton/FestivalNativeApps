"""Fixture-only task selection for the GitHub-hosted Windows UI workflow."""

import re
import unittest

from tools.windows import ci_ui


class CiUiTests(unittest.TestCase):
    """The CI dispatcher must never select live-service journey entries."""

    def test_fixture_entries_exclude_live_labels(self):
        source = ci_ui.JOURNEYS / "polish.json"
        entries = ci_ui.fixture_entries(source)
        self.assertTrue(entries)
        self.assertTrue(all("live" not in entry["name"].lower() for entry in entries))

    def test_all_tasks_include_journeys_matrix_and_runners(self):
        kinds = {task.kind for task in ci_ui.all_tasks()}
        self.assertEqual(kinds, {"journey", "runner"})
        names = {task.name for task in ci_ui.all_tasks()}
        self.assertIn("journey:polish", names)
        self.assertFalse(any("a11y" in name for name in names))
        self.assertNotIn("journey:profile-selection", names)
        self.assertIn("runner:search", names)

    def test_runner_owned_journeys_run_only_through_their_runner(self):
        # search.json needs search_journey.py's delayed queries and isolated settings (issue #530).
        self.assertIn("search.json", ci_ui.runner_journeys())
        names = {task.name for task in ci_ui.candidate_tasks()}
        self.assertNotIn("journey:search", names)
        self.assertIn("runner:search", names)
        self.assertIn("journey:difficulty-meter", names)
        self.assertIn("journey:songs-section-index", names)

    def test_issue_530_journeys_are_not_skipped(self):
        names = {task.name for task in ci_ui.all_tasks()}
        self.assertTrue({"journey:difficulty-meter", "journey:songs-section-index", "runner:search"} <= names)

    def test_percent_scroll_landings_pin_a_window_every_host_fits(self):
        """A section a ``scrollto:<sel>,<pct>`` lands on depends on the viewport height (the offset is pct × (extent −
        viewport)). "wide" (1440×900) fits the 1920×1080 CI display but is clamped to a 1280×720-epx host's work area,
        so 88% landed in U on CI and in V locally (issue #530). A journey asserting a name right after a mid-range
        percentage scroll pins an explicit ``<w>x<h>`` preset no taller than 640 epx, which every host shows unclamped.
        """
        checked = 0
        for source in sorted(ci_ui.JOURNEYS.glob("*.json")):
            if source.name.startswith("a11y"):
                continue
            for entry in ci_ui.fixture_entries(source):
                steps = entry.get("steps", [])
                for step, following in zip(steps, steps[1:]):
                    match = re.fullmatch(r"scrollto:.+,(\d+)", step)
                    if not match or int(match.group(1)) in (0, 100) or not following.startswith("assertname:"):
                        continue
                    checked += 1
                    with self.subTest(journey=entry["name"], step=step):
                        size = re.fullmatch(r"(\d+)x(\d+)", entry.get("preset", "medium"))
                        self.assertIsNotNone(size, "use an explicit <w>x<h> preset")
                        self.assertLessEqual(int(size.group(2)), 640)
        self.assertGreater(checked, 0)

    def test_every_skip_names_a_real_task(self):
        names = {task.name for task in ci_ui.candidate_tasks()}
        # matrix:a11y:N entries belong to the ui_ci.py accessibility shards.
        stale = sorted(name for name in ci_ui.skipped_tasks() if name not in names and not name.startswith("matrix:a11y:"))
        self.assertEqual(stale, [], "ci_skip.json lists tasks CI no longer has; remove them")

    def test_shards_are_complete_and_disjoint(self):
        tasks = ci_ui.all_tasks()
        assigned = [task.name for shard in range(1, 13) for task in ci_ui.shard_tasks(tasks, shard, 12)]
        self.assertCountEqual(assigned, [task.name for task in tasks])
        weights = [sum(ci_ui.task_weight(task) for task in ci_ui.shard_tasks(tasks, shard, 12))
                   for shard in range(1, 13)]
        self.assertLessEqual(max(weights) - min(weights), max(ci_ui.task_weight(task) for task in tasks))


if __name__ == "__main__":
    unittest.main()
