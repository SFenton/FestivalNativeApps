"""The CI task guard ends a hung or memory-starving task's whole process tree and keeps its evidence (issue #700)."""

import shutil
import sys
import tempfile
import time
import unittest
from pathlib import Path

from tools.windows import ci_guard

#: A task that starts a grandchild (like the FstUia driver starting the app), prints its pid, then waits ``{wait}`` s.
SPAWNER = ("import subprocess, sys, time; "
           "child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(120)']); "
           "print('grandchild', child.pid, flush=True); time.sleep({wait})")


def grandchild(log: Path) -> int:
    """The grandchild pid a :data:`SPAWNER` task printed."""
    return int(next(line for line in log.read_text(encoding="utf-8").splitlines() if line.startswith("grandchild"))
               .split()[1])


def gone(pid: int, seconds: float = 10.0) -> bool:
    """Whether ``pid`` has exited within ``seconds``."""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if ci_guard.process_info(pid) is None:
            return True
        time.sleep(0.2)
    return False


@unittest.skipUnless(sys.platform == "win32", "job objects are Windows-only")
class CiGuardTests(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp(prefix="fst-ci-guard-"))
        self.addCleanup(shutil.rmtree, self.folder, ignore_errors=True)
        self.log = self.folder / "command.log"

    def run_spawner(self, wait: float, timeout: float, **kwargs) -> ci_guard.TaskResult:
        command = [sys.executable, "-c", SPAWNER.format(wait=wait)]
        return ci_guard.run_task(command, self.folder, self.log, self.folder, timeout, 0, **kwargs)

    def test_a_hung_task_fails_with_its_tree_ended_and_its_evidence_logged(self):
        started = time.monotonic()
        result = self.run_spawner(wait=120, timeout=3)
        self.assertEqual(result.returncode, 124)
        self.assertLess(time.monotonic() - started, 90)
        self.assertTrue(result.stopped.startswith("timed out after"), result.stopped)
        self.assertTrue(gone(grandchild(self.log)), "the task's grandchild outlived the timeout")
        log = self.log.read_text(encoding="utf-8")
        self.assertIn("ci_guard: timed out", log)
        self.assertIn("task processes:", log)
        self.assertIn("python", log.lower())  # the task and its grandchild are listed with their memory
        self.assertIn("runner's largest processes:", log)
        self.assertIn("screenshot:", log)

    def test_a_memory_starved_runner_ends_the_task(self):
        result = ci_guard.run_task([sys.executable, "-c", "import time; time.sleep(120)"], self.folder, self.log,
                                   self.folder, 600, 1024, memory=lambda: 512)
        self.assertEqual(result.returncode, 124)
        self.assertEqual(result.stopped, "runner memory low: 512 MB available (floor 1024 MB)")

    def test_processes_a_finished_task_leaves_behind_are_reported_and_ended(self):
        result = self.run_spawner(wait=0, timeout=600)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stopped, "")
        self.assertIn("left processes running", result.report[0])
        self.assertTrue(gone(grandchild(self.log)), "a leaked process survived the task")

    def test_a_task_that_passes_keeps_its_exit_code_and_output(self):
        result = ci_guard.run_task([sys.executable, "-c", "print('ok'); raise SystemExit(3)"], self.folder, self.log,
                                   self.folder, 600, 0)
        self.assertEqual((result.returncode, result.stopped, result.report), (3, "", []))
        self.assertEqual(self.log.read_text(encoding="utf-8").strip(), "ok")
        self.assertGreater(result.peak_mb, 0)


if __name__ == "__main__":
    unittest.main()
