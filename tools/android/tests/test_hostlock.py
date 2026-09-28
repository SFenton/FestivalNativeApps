"""FIFO ticket ordering, hold clamping and exclusivity of the shared host lock.

Run: ``python -m unittest discover -s tools/android/tests`` from the repo root.
"""

import os
import tempfile
import unittest
from pathlib import Path

from tools.android.hostlock import (
    MAX_HOLD_SECONDS,
    HostLock,
    LockTimeout,
    parse_ticket,
    pid_alive,
    queue_head,
)


class TicketTests(unittest.TestCase):
    """Ticket names encode arrival order and owner pid."""

    def test_parse_valid_ticket(self):
        self.assertEqual(parse_ticket("00000000000000000042-123.ticket"), (42, 123))

    def test_parse_rejects_other_files(self):
        for name in ("x.lock", "12.ticket", "a-1.ticket", "1-b.ticket", "1-2.txt"):
            self.assertIsNone(parse_ticket(name), name)

    def test_queue_head_is_oldest_live_ticket(self):
        names = ["3-30.ticket", "1-10.ticket", "2-20.ticket", "junk.txt"]
        head, stale = queue_head(names, alive=lambda pid: pid != 10)
        self.assertEqual(head, "2-20.ticket")
        self.assertEqual(stale, ["1-10.ticket"])

    def test_queue_head_empty(self):
        self.assertEqual(queue_head([], alive=lambda pid: True), (None, []))


class PidTests(unittest.TestCase):
    """Liveness checks never signal the process (Windows signal 0 is Ctrl+C)."""

    def test_current_process_is_alive(self):
        self.assertTrue(pid_alive(os.getpid()))

    def test_invalid_pids_are_dead(self):
        self.assertFalse(pid_alive(0))
        self.assertFalse(pid_alive(-5))


class HostLockTests(unittest.TestCase):
    """Exclusive acquisition, FIFO respect and hold bounds, in a temp lock dir."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def lock(self, **kw):
        kw.setdefault("wait_seconds", 0.5)
        kw.setdefault("poll_seconds", 0.05)
        return HostLock("test", purpose="unit", lock_dir=self.dir, **kw)

    def test_hold_is_clamped_to_maximum(self):
        self.assertEqual(self.lock(hold_seconds=9999).hold_seconds, MAX_HOLD_SECONDS)
        self.assertEqual(self.lock(hold_seconds=0).hold_seconds, 1.0)

    def test_acquire_writes_holder_and_release_clears_it(self):
        with self.lock() as held:
            self.assertEqual(held.holder()["pid"], os.getpid())
            self.assertGreater(held.remaining(), 250)
            self.assertFalse(any(held.queue_dir.iterdir()), "ticket removed after acquire")
        self.assertIsNone(self.lock().holder())
        self.assertTrue(self.lock().is_free())

    def test_second_holder_times_out_while_held(self):
        with self.lock():
            self.assertFalse(self.lock().is_free())
            with self.assertRaises(LockTimeout):
                self.lock().acquire()
        with self.lock():
            pass  # free again after release

    def test_older_live_ticket_is_served_first(self):
        queue = self.dir / "test.queue"
        queue.mkdir(parents=True)
        # An older ticket owned by this (live) process blocks newer waiters.
        (queue / f"{1:020d}-{os.getpid()}.ticket").write_text("older")
        with self.assertRaises(LockTimeout):
            self.lock().acquire()
        self.assertTrue(self.lock().is_free(), "the OS lock itself was never taken")

    def test_dead_tickets_are_pruned(self):
        queue = self.dir / "test.queue"
        queue.mkdir(parents=True)
        stale = queue / f"{1:020d}-999999.ticket"
        stale.write_text("dead")
        with self.lock():
            self.assertFalse(stale.exists())


if __name__ == "__main__":
    unittest.main()
