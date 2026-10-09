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

    def test_runner_owned_journeys_run_only_through_their_runner(self):
        # search.json needs search_journey.py's delayed queries and isolated settings (issue #530).
        self.assertIn("search.json", ci_ui.runner_journeys())
        names = {task.name for task in ci_ui.candidate_tasks()}
        self.assertNotIn("journey:search", names)
        self.assertIn("runner:search", names)
        self.assertIn("journey:difficulty-meter", names)
        self.assertIn("journey:songs-section-index", names)

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
