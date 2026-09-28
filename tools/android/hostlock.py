#!/usr/bin/env python3
"""FIFO, crash-safe, time-bounded host locks shared by every lane on one machine.

Several lanes run in parallel worktrees on the Windows host ``sfenton-primary``.
Two resources must be used by only one lane at a time:

* ``emulator``: the single running Android product emulator (``tools/android/device.py``);
* ``desktop``: the interactive Windows desktop that ``tools/windows/uiwin.py`` drives.

A :class:`HostLock` combines three mechanisms:

1. **An OS byte-range lock** (``msvcrt.locking`` on Windows, ``fcntl.flock``
   elsewhere) on ``~/.fst-locks/<name>.lock``. The OS releases it when the
   holder exits or crashes, so a dead lane can never wedge the host.
2. **A ticket queue** in ``~/.fst-locks/<name>.queue/``. Each waiter writes a
   ``<monotonic-ns>-<pid>.ticket`` file; only the oldest ticket whose process is
   still alive may try the OS lock, so waiters are served first come, first
   served. Tickets of dead processes are pruned by whoever looks next.
3. **A hard hold timeout** (default and maximum 300 s, the Mac simulator rule).
   A watchdog thread kills every child process registered with
   :meth:`HostLock.track`, releases the lock and exits the process with code
   124 if the hold overruns. Commands should also pass
   :meth:`HostLock.remaining` as ``subprocess`` timeouts so they fail cleanly
   before the watchdog fires.

``~/.fst-locks/<name>.holder.json`` describes the current holder for ``status``
output; it is informational only (the OS lock is the source of truth).
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

# region Configuration

#: Directory holding every host lock, queue and holder file.
LOCK_DIR = Path.home() / ".fst-locks"

#: Longest any lane may hold a host lock (seconds), mirroring the Mac rule.
MAX_HOLD_SECONDS = 300.0

#: Default time a waiter queues before giving up (seconds).
DEFAULT_WAIT_SECONDS = 1800.0

#: Exit code used when the hold watchdog fires (matches coreutils ``timeout``).
HOLD_TIMEOUT_EXIT = 124

# endregion

# region Process helpers


def pid_alive(pid: int) -> bool:
    """Report whether a process id refers to a running process.

    On Windows this uses ``OpenProcess``/``GetExitCodeProcess``; never use
    ``os.kill(pid, 0)`` there, because signal 0 is ``CTRL_C_EVENT``.

    Args:
        pid: Process id to test.

    Returns:
        True if the process exists and has not exited.
    """
    if pid <= 0:
        return False
    if os.name == "nt":
        import ctypes
        from ctypes import wintypes

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel32.OpenProcess.restype = wintypes.HANDLE
        process_query_limited_information = 0x1000
        still_active = 259
        error_access_denied = 5
        handle = kernel32.OpenProcess(process_query_limited_information, False, pid)
        if not handle:
            # Access denied still means the process exists.
            return ctypes.get_last_error() == error_access_denied
        try:
            code = wintypes.DWORD()
            if not kernel32.GetExitCodeProcess(handle, ctypes.byref(code)):
                return False
            return code.value == still_active
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def kill_tree(proc: subprocess.Popen) -> None:
    """Terminate a child process and, on Windows, all of its descendants.

    Args:
        proc: A process started by this tool.
    """
    if proc.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)],
                       capture_output=True, check=False)
    else:
        proc.kill()

# endregion

# region Ticket queue


def parse_ticket(name: str) -> tuple[int, int] | None:
    """Split a ticket file name into its ordering key and owner pid.

    Args:
        name: File name such as ``"000001234567890-4321.ticket"``.

    Returns:
        ``(order, pid)``, or None if the name is not a ticket.
    """
    if not name.endswith(".ticket"):
        return None
    stem = name[: -len(".ticket")]
    order, sep, pid = stem.partition("-")
    if not sep or not order.isdigit() or not pid.isdigit():
        return None
    return int(order), int(pid)


def queue_head(names: list[str], alive: Callable[[int], bool]) -> tuple[str | None, list[str]]:
    """Pick the ticket allowed to try the lock and list tickets of dead owners.

    Args:
        names: File names found in the queue directory.
        alive: Predicate telling whether a pid is still running.

    Returns:
        ``(head, stale)``: the oldest live ticket name (or None if the queue is
        empty) and the ticket names whose owners have exited.
    """
    parsed = sorted((key, name) for name in names if (key := parse_ticket(name)))
    stale = [name for (_, pid), name in parsed if not alive(pid)]
    live = [name for (_, pid), name in parsed if name not in stale]
    return (live[0] if live else None), stale

# endregion

# region Lock


class LockTimeout(RuntimeError):
    """Raised when a waiter's queue time exceeds its wait timeout."""


@dataclass
class HostLock:
    """An exclusive, FIFO, hold-bounded lock on a named host resource.

    Use as a context manager::

        with HostLock("emulator", purpose="shot FST_Phone") as lock:
            subprocess.run([...], timeout=lock.remaining())

    Attributes:
        name: Resource name (``"emulator"`` or ``"desktop"``).
        purpose: Short description recorded in the holder file.
        hold_seconds: Hard hold limit; clamped to ``MAX_HOLD_SECONDS``.
        wait_seconds: How long to queue before raising :class:`LockTimeout`.
        lock_dir: Directory for lock artifacts (tests use a temp dir).
        poll_seconds: Queue polling interval.
    """

    name: str
    purpose: str = ""
    hold_seconds: float = MAX_HOLD_SECONDS
    wait_seconds: float = DEFAULT_WAIT_SECONDS
    lock_dir: Path = LOCK_DIR
    poll_seconds: float = 0.5
    _handle: object = field(default=None, init=False, repr=False)
    _deadline: float = field(default=0.0, init=False, repr=False)
    _children: list = field(default_factory=list, init=False, repr=False)
    _done: threading.Event = field(default_factory=threading.Event, init=False, repr=False)

    def __post_init__(self) -> None:
        self.hold_seconds = min(max(self.hold_seconds, 1.0), MAX_HOLD_SECONDS)

    # MARK: paths

    @property
    def lock_path(self) -> Path:
        """The OS-locked file."""
        return self.lock_dir / f"{self.name}.lock"

    @property
    def queue_dir(self) -> Path:
        """Directory of waiter tickets."""
        return self.lock_dir / f"{self.name}.queue"

    @property
    def holder_path(self) -> Path:
        """Informational JSON describing the current holder."""
        return self.lock_dir / f"{self.name}.holder.json"

    # MARK: OS lock primitives

    def _try_os_lock(self) -> bool:
        """Attempt the non-blocking OS lock.

        Returns:
            True when this process now holds the lock.
        """
        self.lock_dir.mkdir(parents=True, exist_ok=True)
        handle = open(self.lock_path, "a+b")
        try:
            if os.name == "nt":
                import msvcrt

                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl

                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            handle.close()
            return False
        self._handle = handle
        return True

    def _release_os_lock(self) -> None:
        """Release and close the OS lock if held."""
        handle, self._handle = self._handle, None
        if handle is None:
            return
        try:
            if os.name == "nt":
                import msvcrt

                handle.seek(0)
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                import fcntl

                fcntl.flock(handle, fcntl.LOCK_UN)
        except OSError:
            pass
        handle.close()

    # MARK: public API

    def is_free(self) -> bool:
        """Probe whether the lock is currently free (without queueing).

        Returns:
            True if nobody holds the OS lock at this instant.
        """
        if self._try_os_lock():
            self._release_os_lock()
            return True
        return False

    def holder(self) -> dict | None:
        """Read the informational holder record.

        Returns:
            The last holder's JSON record, or None if absent/unreadable.
        """
        try:
            return json.loads(self.holder_path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None

    def waiting(self) -> list[int]:
        """List pids currently queued, oldest first.

        Returns:
            Live waiter pids in service order.
        """
        if not self.queue_dir.exists():
            return []
        names = [p.name for p in self.queue_dir.iterdir()]
        parsed = sorted(key for name in names if (key := parse_ticket(name)))
        return [pid for _, pid in parsed if pid_alive(pid)]

    def acquire(self) -> None:
        """Queue FIFO for the lock, then start the hold watchdog.

        Raises:
            LockTimeout: The wait exceeded ``wait_seconds``.
        """
        self.queue_dir.mkdir(parents=True, exist_ok=True)
        ticket = self.queue_dir / f"{time.time_ns():020d}-{os.getpid()}.ticket"
        ticket.write_text(self.purpose, encoding="utf-8")
        give_up = time.monotonic() + self.wait_seconds
        announced = False
        try:
            while True:
                names = [p.name for p in self.queue_dir.iterdir()]
                head, stale = queue_head(names, pid_alive)
                for name in stale:
                    (self.queue_dir / name).unlink(missing_ok=True)
                if head == ticket.name and self._try_os_lock():
                    break
                if not announced:
                    info = self.holder() or {}
                    print(f"waiting for host lock '{self.name}' "
                          f"(holder: {info.get('purpose', '?')} pid {info.get('pid', '?')}) ...",
                          file=sys.stderr)
                    announced = True
                if time.monotonic() > give_up:
                    raise LockTimeout(f"gave up waiting {self.wait_seconds:.0f}s for '{self.name}'")
                time.sleep(self.poll_seconds)
        finally:
            ticket.unlink(missing_ok=True)
        self._deadline = time.monotonic() + self.hold_seconds
        self.holder_path.write_text(json.dumps({
            "pid": os.getpid(),
            "purpose": self.purpose,
            "cwd": os.getcwd(),
            "acquired": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "hold_seconds": self.hold_seconds,
        }), encoding="utf-8")
        self._done.clear()
        threading.Thread(target=self._watchdog, daemon=True).start()

    def release(self) -> None:
        """Stop the watchdog and release the lock."""
        self._done.set()
        try:
            if (self.holder() or {}).get("pid") == os.getpid():
                self.holder_path.unlink(missing_ok=True)
        except OSError:
            pass
        self._release_os_lock()

    def remaining(self, floor: float = 1.0) -> float:
        """Seconds left in this hold, for use as a subprocess timeout.

        Args:
            floor: Smallest value returned, so callers never pass 0.

        Returns:
            Remaining hold time in seconds.
        """
        return max(self._deadline - time.monotonic(), floor)

    def track(self, proc: subprocess.Popen) -> subprocess.Popen:
        """Register a child so the watchdog kills it on hold overrun.

        Args:
            proc: A child started while holding the lock.

        Returns:
            ``proc``, for chaining.
        """
        self._children.append(proc)
        return proc

    def _watchdog(self) -> None:
        """Enforce the hard hold limit by killing children and exiting."""
        if self._done.wait(self.hold_seconds):
            return
        print(f"\nHOLD TIMEOUT: '{self.name}' held longer than {self.hold_seconds:.0f}s; "
              "killing children and releasing the lock.", file=sys.stderr)
        for proc in self._children:
            kill_tree(proc)
        self.release()
        os._exit(HOLD_TIMEOUT_EXIT)

    def __enter__(self) -> "HostLock":
        self.acquire()
        return self

    def __exit__(self, *exc) -> None:
        self.release()

# endregion
