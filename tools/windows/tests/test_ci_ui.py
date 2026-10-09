"""Fixture-only task selection for the GitHub-hosted Windows UI workflow."""

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

    def test_shards_are_complete_and_disjoint(self):
        tasks = ci_ui.all_tasks()
        assigned = [task.name for shard in range(1, 13) for task in ci_ui.shard_tasks(tasks, shard, 12)]
        self.assertCountEqual(assigned, [task.name for task in tasks])
        weights = [sum(ci_ui.task_weight(task) for task in ci_ui.shard_tasks(tasks, shard, 12))
                   for shard in range(1, 13)]
        self.assertLessEqual(max(weights) - min(weights), max(ci_ui.task_weight(task) for task in tasks))


if __name__ == "__main__":
    unittest.main()
