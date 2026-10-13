#!/usr/bin/env python3
"""Machine-wide device capacity: wait for a simulator, device or build slot.

Every repository and lane on one Mac shares the same simulator, device and
compile capacity. ``devcap`` hands out that capacity FIFO, so parallel lanes
wait their turn instead of booting more simulators (or compiling more apps)
than the machine can carry. It is the one capacity mechanism for
SFenton/FestivalNativeApps and SFenton/Fenton-HASS-Native; the canonical copy
lives in FestivalNativeApps at ``tools/devcap.py`` and other repositories
vendor it byte for byte (see ``VERSION``).

Gates
-----
A *gate* is a named resource with a number of slots:

* **pools** share capacity: ``simulator`` (booted simulators, default from
  RAM), ``build`` (heavy ``xcodebuild``/``swift build`` compiles, default from
  cores), or any other name (default 1 slot);
* **devices** are exclusive: ``device-<UDID>`` has one slot, so two lanes never
  drive the same simulator or physical device.

``--sim UDID`` takes the device gate *and* a ``simulator`` slot; ``--device
UDID`` (a physical device) takes only the device gate.

How waiting works
-----------------
Each gate lives in ``~/.devcap/<gate>/`` (``DEVCAP_DIR`` overrides the root):

1. ``slot-<n>.lock`` files carry an OS lock (``fcntl.flock``, ``msvcrt`` on
   Windows). The OS drops it when the holder exits or crashes, so a dead
   process never keeps a slot.
2. ``queue/<ns>-<pid>.ticket`` files order the waiters. Only the oldest ticket
   whose process is alive may try the slots (first come, first served);
   tickets of dead processes are deleted by whoever looks next.
3. ``slot-<n>.json`` names the holder (pid, purpose, cwd, start time) for the
   waiting message and ``status``. It is informational; the OS lock is the
   truth.

Gates are always taken in one order (devices by UDID, then pools by name) so
two holders never deadlock. A child started by ``devcap run`` inherits
``DEVCAP_HELD``, and any nested ``devcap`` call skips gates its parent already
holds. Every acquire, wait and release is appended to ``~/.devcap/devcap.log``.

Capacity
--------
Slot counts come from, in order: ``DEVCAP_SLOTS_<POOL>`` (e.g.
``DEVCAP_SLOTS_SIMULATOR=2``), ``~/.devcap/config.json`` (``{"simulator": 2}``),
then the defaults in ``default_slots``. Lowering a count takes effect for new
holders; current holders finish normally.

Usage
-----
::

    # Run a command while holding a simulator (device + simulator slot).
    python3 tools/devcap.py run --sim "$UDID" --purpose "uitest iphone" -- \\
        xcodebuild test-without-building ...

    # Compile under a build slot.
    python3 tools/devcap.py run --pool build -- xcodebuild build-for-testing ...

    # Who holds what, and who is waiting.
    python3 tools/devcap.py status

From Python::

    from tools import devcap
    with devcap.hold(sims=[udid], purpose="shot iphone", hold_seconds=None):
        ...
"""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable, Iterator, Sequence

# region Configuration

#: Bump when the on-disk layout or the CLI changes; vendored copies must match.
VERSION = "1.0.0"

#: Exit code when a wait gives up (``EX_TEMPFAIL``).
WAIT_TIMEOUT_EXIT = 75

#: Exit code when a hold overruns its limit (matches coreutils ``timeout``).
HOLD_TIMEOUT_EXIT = 124

#: Default seconds a waiter queues before giving up.
DEFAULT_WAIT_SECONDS = 3600.0

#: Default seconds ``run`` may hold its gates.
DEFAULT_HOLD_SECONDS = 1800.0

#: Longest hold ``run`` accepts.
MAX_HOLD_SECONDS = 7200.0

#: Environment variable listing gates held by an ancestor process.
HELD_ENV = "DEVCAP_HELD"

#: Log size that triggers rotation to ``devcap.log.1``.
LOG_ROTATE_BYTES = 1_000_000

#: Seconds between repeated "still waiting" messages.
REANNOUNCE_SECONDS = 60.0


def lock_root() -> Path:
    """Return the machine-wide state directory (``DEVCAP_DIR`` or ``~/.devcap``)."""
    return Path(os.environ.get("DEVCAP_DIR") or Path.home() / ".devcap")


def _memory_gb() -> float:
    """Physical memory in GB, or 16 when it cannot be read."""
    try:
        return os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES") / 2**30
    except (AttributeError, ValueError, OSError):
        pass
    try:
        out = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True,
                             text=True, check=True, timeout=5).stdout
        return int(out.strip()) / 2**30
    except (OSError, ValueError, subprocess.SubprocessError):
        return 16.0


def default_slots(pool: str, memory_gb: float | None = None, cpus: int | None = None) -> int:
    """Default slot count for a pool on this machine.

    Args:
        pool: Pool name.
        memory_gb: Physical memory override (tests).
        cpus: Core count override (tests).

    Returns:
        ``simulator``: one per 20 GB of RAM, 1–4. ``build``: one per 4 cores,
        1–4. Anything else: 1.
    """
    if pool == "simulator":
        memory_gb = _memory_gb() if memory_gb is None else memory_gb
        return max(1, min(4, int(memory_gb // 20)))
    if pool == "build":
        cpus = (os.cpu_count() or 4) if cpus is None else cpus
        return max(1, min(4, cpus // 4))
    return 1


def env_key(pool: str) -> str:
    """Environment variable overriding a pool's slot count."""
    return "DEVCAP_SLOTS_" + re.sub(r"[^A-Za-z0-9]", "_", pool).upper()


def configured_slots(pool: str, root: Path | None = None) -> int:
    """Slot count for a pool: environment, then ``config.json``, then default.

    Args:
        pool: Pool name. Device gates always have one slot.
        root: State directory (defaults to ``lock_root()``).

    Returns:
        At least 1.
    """
    if pool.startswith("device-"):
        return 1
    raw = os.environ.get(env_key(pool))
    if raw is None:
        try:
            config = json.loads(((root or lock_root()) / "config.json").read_text(encoding="utf-8"))
            raw = config.get(pool)
        except (OSError, ValueError, AttributeError):
            raw = None
    try:
        return max(1, int(raw)) if raw is not None else default_slots(pool)
    except (TypeError, ValueError):
        return default_slots(pool)

# endregion

# region Process helpers


def pid_alive(pid: int) -> bool:
    """Report whether a process id refers to a running process.

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
        handle = kernel32.OpenProcess(0x1000, False, pid)
        if not handle:
            return ctypes.get_last_error() == 5  # access denied: it exists
        try:
            code = wintypes.DWORD()
            return bool(kernel32.GetExitCodeProcess(handle, ctypes.byref(code))) and code.value == 259
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def describe_age(seconds: float) -> str:
    """Format a duration as ``45s``, ``3m`` or ``2h05m``."""
    seconds = max(0, int(seconds))
    if seconds < 60:
        return f"{seconds}s"
    if seconds < 3600:
        return f"{seconds // 60}m"
    return f"{seconds // 3600}h{seconds % 3600 // 60:02d}m"


def log_event(message: str, root: Path | None = None) -> None:
    """Append one line to ``devcap.log``, rotating it past ``LOG_ROTATE_BYTES``."""
    path = (root or lock_root()) / "devcap.log"
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists() and path.stat().st_size > LOG_ROTATE_BYTES:
            path.replace(path.with_name("devcap.log.1"))
        with open(path, "a", encoding="utf-8") as log:
            log.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} pid {os.getpid()} {message}\n")
    except OSError:
        pass

# endregion

# region Ticket queue


def parse_ticket(name: str) -> tuple[int, int] | None:
    """Split a ticket file name into its ordering key and owner pid.

    Args:
        name: File name such as ``"00000001234567890000-4321.ticket"``.

    Returns:
        ``(order, pid)``, or None if the name is not a ticket.
    """
    if not name.endswith(".ticket"):
        return None
    order, sep, pid = name[: -len(".ticket")].partition("-")
    if not sep or not order.isdigit() or not pid.isdigit():
        return None
    return int(order), int(pid)


def queue_order(names: Iterable[str], alive: Callable[[int], bool]) -> tuple[list[str], list[str]]:
    """Order live tickets and list tickets whose owners have exited.

    Args:
        names: File names found in a queue directory.
        alive: Predicate telling whether a pid is still running.

    Returns:
        ``(live, stale)``: live ticket names oldest first, and dead ones.
    """
    parsed = sorted((key, name) for name in names if (key := parse_ticket(name)))
    live, stale = [], []
    for (_, pid), name in parsed:
        (live if alive(pid) else stale).append(name)
    return live, stale

# endregion

# region Gate


@dataclass
class Gate:
    """One named resource with ``slots`` OS-locked slot files and a FIFO queue.

    Attributes:
        name: Gate name (``simulator``, ``build`` or ``device-<UDID>``).
        root: State directory.
        slots: Slot count; read from configuration when None.
    """

    name: str
    root: Path = field(default_factory=lock_root)
    slots: int | None = None
    _handle: object = field(default=None, init=False, repr=False)
    _slot: int | None = field(default=None, init=False, repr=False)

    def __post_init__(self) -> None:
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", self.name):
            raise ValueError(f"invalid gate name {self.name!r}")
        if self.slots is None:
            self.slots = configured_slots(self.name, self.root)

    # MARK: paths

    @property
    def dir(self) -> Path:
        """Directory holding this gate's slots, holders and queue."""
        return self.root / self.name

    @property
    def queue_dir(self) -> Path:
        """Directory of waiter tickets."""
        return self.dir / "queue"

    def slot_lock(self, index: int) -> Path:
        """Path of slot ``index``'s OS-locked file."""
        return self.dir / f"slot-{index}.lock"

    def slot_holder(self, index: int) -> Path:
        """Path of slot ``index``'s informational holder record."""
        return self.dir / f"slot-{index}.json"

    # MARK: OS lock primitives

    @staticmethod
    def _lock(path: Path):
        """Take a non-blocking exclusive OS lock on ``path``.

        Returns:
            The open handle holding the lock, or None if someone else holds it.
        """
        handle = open(path, "a+b")
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
            return None
        return handle

    @staticmethod
    def _unlock(handle) -> None:
        """Release and close a handle returned by ``_lock``."""
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

    def _try_slots(self) -> bool:
        """Try every slot once; keep the first free one."""
        self.dir.mkdir(parents=True, exist_ok=True)
        for index in range(self.slots):
            handle = self._lock(self.slot_lock(index))
            if handle is not None:
                self._handle, self._slot = handle, index
                return True
        return False

    # MARK: inspection

    def holders(self) -> list[dict]:
        """List current holders by probing every slot file in the gate.

        Returns:
            One record per held slot (``slot``, ``pid``, ``purpose``, ``cwd``,
            ``acquired``…); ``pid`` is None when the record is missing.
        """
        held = []
        if not self.dir.exists():
            return held
        indices = sorted(int(m.group(1)) for p in self.dir.iterdir()
                         if (m := re.fullmatch(r"slot-(\d+)\.lock", p.name)))
        for index in indices:
            if index == self._slot:
                continue
            probe = self._lock(self.slot_lock(index))
            if probe is not None:
                self._unlock(probe)
                continue
            try:
                record = json.loads(self.slot_holder(index).read_text(encoding="utf-8"))
            except (OSError, ValueError):
                record = {"pid": None}
            held.append({**record, "slot": index})
        return held

    def waiting(self) -> list[dict]:
        """List live waiters oldest first, each with ``pid`` and ``purpose``."""
        if not self.queue_dir.exists():
            return []
        live, _ = queue_order((p.name for p in self.queue_dir.iterdir()), pid_alive)
        result = []
        for name in live:
            try:
                purpose = (self.queue_dir / name).read_text(encoding="utf-8")
            except OSError:
                purpose = ""
            result.append({"pid": parse_ticket(name)[1], "purpose": purpose})
        return result

    def summary(self) -> str:
        """One line naming who holds this gate, for waiting messages."""
        now = time.time()
        held = self.holders()
        parts = [f"pid {h.get('pid', '?')} '{h.get('purpose', '?')}' in {h.get('cwd', '?')} "
                 f"for {describe_age(now - h.get('acquired_epoch', now))}" for h in held]
        return f"{len(held)}/{self.slots} held" + (": " + "; ".join(parts) if parts else "")

    # MARK: acquire / release

    def acquire(self, purpose: str, wait_seconds: float, poll_seconds: float = 0.5,
                announce: Callable[[str], None] | None = None) -> None:
        """Queue FIFO for a free slot.

        Args:
            purpose: Short description recorded for status and logs.
            wait_seconds: How long to queue before raising ``WaitTimeout``.
            poll_seconds: Polling interval while at the head of the queue;
                waiters further back back off up to 4 s.
            announce: Receives human-readable waiting messages (stderr default).

        Raises:
            WaitTimeout: No slot freed up within ``wait_seconds``.
        """
        announce = announce or (lambda line: print(line, file=sys.stderr, flush=True))
        self.queue_dir.mkdir(parents=True, exist_ok=True)
        ticket = self.queue_dir / f"{time.time_ns():020d}-{os.getpid()}.ticket"
        ticket.write_text(purpose, encoding="utf-8")
        started = time.monotonic()
        next_announce = started
        try:
            while True:
                live, stale = queue_order((p.name for p in self.queue_dir.iterdir()), pid_alive)
                for name in stale:
                    (self.queue_dir / name).unlink(missing_ok=True)
                position = live.index(ticket.name) if ticket.name in live else 0
                if position == 0 and self._try_slots():
                    break
                waited = time.monotonic() - started
                if waited >= wait_seconds:
                    log_event(f"gave up {self.name} after {describe_age(waited)} purpose={purpose!r}", self.root)
                    raise WaitTimeout(f"gave up waiting {describe_age(waited)} for '{self.name}' "
                                      f"({self.summary()})")
                if time.monotonic() >= next_announce:
                    ahead = f", {position} ahead in queue" if position else ""
                    verb = "waiting" if next_announce == started else f"still waiting ({describe_age(waited)})"
                    announce(f"devcap: {verb} for '{self.name}' ({self.summary()}{ahead}) ...")
                    if next_announce == started:
                        log_event(f"wait {self.name} {self.summary()} purpose={purpose!r}", self.root)
                    next_announce = time.monotonic() + REANNOUNCE_SECONDS
                time.sleep(poll_seconds if position == 0 else min(4.0, poll_seconds * (1 + position)))
        finally:
            ticket.unlink(missing_ok=True)
        waited = time.monotonic() - started
        self.slot_holder(self._slot).write_text(json.dumps({
            "pid": os.getpid(),
            "purpose": purpose,
            "cwd": os.getcwd(),
            "acquired": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "acquired_epoch": time.time(),
        }), encoding="utf-8")
        log_event(f"acquire {self.name} slot {self._slot}/{self.slots} after {describe_age(waited)} "
                  f"purpose={purpose!r} cwd={os.getcwd()}", self.root)
        if waited >= 1:
            announce(f"devcap: got '{self.name}' slot {self._slot} after {describe_age(waited)}")

    def release(self) -> None:
        """Release the held slot, if any."""
        if self._handle is None:
            return
        try:
            self.slot_holder(self._slot).unlink(missing_ok=True)
        except OSError:
            pass
        log_event(f"release {self.name} slot {self._slot}", self.root)
        self._unlock(self._handle)
        self._handle, self._slot = None, None

    @property
    def held(self) -> bool:
        """Whether this process currently holds a slot of this gate."""
        return self._handle is not None


class WaitTimeout(RuntimeError):
    """Raised when a waiter's queue time exceeds its wait limit."""

# endregion

# region Holding several gates


def device_gate(udid: str) -> str:
    """Gate name for a simulator or physical device UDID."""
    return "device-" + re.sub(r"[^A-Za-z0-9._-]", "_", udid.strip()).upper()


def gate_names(pools: Sequence[str] = (), sims: Sequence[str] = (), devices: Sequence[str] = ()) -> list[str]:
    """Canonical acquisition order: device gates by UDID, then pools by name.

    Args:
        pools: Pool names, e.g. ``["build"]``.
        sims: Simulator UDIDs; each adds its device gate and the ``simulator`` pool.
        devices: Physical device UDIDs; each adds only its device gate.

    Returns:
        Deduplicated gate names in the one order every caller uses.
    """
    device_names = {device_gate(u) for u in [*sims, *devices]}
    pool_names = set(pools) | ({"simulator"} if sims else set())
    return sorted(device_names) + sorted(pool_names)


def inherited() -> set[str]:
    """Gates an ancestor ``devcap`` process holds for this process."""
    return {name for name in os.environ.get(HELD_ENV, "").split(",") if name}


@dataclass
class Hold:
    """Holds several gates for one block, with an optional hold watchdog.

    Attributes:
        names: Gate names, already in canonical order (``gate_names``).
        purpose: Short description for status and logs.
        wait_seconds: Queue limit per gate.
        hold_seconds: Hard hold limit; None disables the watchdog.
        root: State directory.
        on_overrun: Called when the hold overruns (default: exit 124).
    """

    names: list[str]
    purpose: str = ""
    wait_seconds: float = DEFAULT_WAIT_SECONDS
    hold_seconds: float | None = DEFAULT_HOLD_SECONDS
    root: Path = field(default_factory=lock_root)
    on_overrun: Callable[[], None] | None = None
    gates: list[Gate] = field(default_factory=list, init=False)
    overran: bool = field(default=False, init=False)
    _done: threading.Event = field(default_factory=threading.Event, init=False, repr=False)

    def acquire(self) -> None:
        """Take every gate not already held by an ancestor, in order.

        Raises:
            WaitTimeout: A gate stayed full past ``wait_seconds``; nothing stays held.
        """
        skip = inherited()
        try:
            for name in self.names:
                if name in skip:
                    continue
                gate = Gate(name, self.root)
                gate.acquire(self.purpose, self.wait_seconds)
                self.gates.append(gate)
        except BaseException:
            self.release()
            raise
        if self.hold_seconds is not None:
            self._done.clear()
            threading.Thread(target=self._watchdog, daemon=True).start()

    def release(self) -> None:
        """Release every held gate, newest first."""
        self._done.set()
        for gate in reversed(self.gates):
            gate.release()
        self.gates.clear()

    def environment(self) -> dict[str, str]:
        """Environment for children: ``DEVCAP_HELD`` lists every held gate."""
        held = inherited() | {g.name for g in self.gates}
        return {**os.environ, HELD_ENV: ",".join(sorted(held))}

    def _watchdog(self) -> None:
        if self._done.wait(self.hold_seconds):
            return
        print(f"\ndevcap: HOLD TIMEOUT: held {','.join(self.names)} longer than "
              f"{describe_age(self.hold_seconds)}; releasing.", file=sys.stderr, flush=True)
        log_event(f"hold timeout {','.join(self.names)} purpose={self.purpose!r}", self.root)
        self.overran = True
        if self.on_overrun:
            self.on_overrun()
        self.release()
        os._exit(HOLD_TIMEOUT_EXIT)

    def __enter__(self) -> "Hold":
        self.acquire()
        return self

    def __exit__(self, *exc) -> None:
        self.release()


@contextmanager
def hold(pools: Sequence[str] = (), sims: Sequence[str] = (), devices: Sequence[str] = (),
         purpose: str = "", wait_seconds: float = DEFAULT_WAIT_SECONDS,
         hold_seconds: float | None = DEFAULT_HOLD_SECONDS, root: Path | None = None) -> Iterator[Hold]:
    """Hold capacity for a block; see ``gate_names`` for the arguments.

    While the block runs, ``os.environ[DEVCAP_HELD]`` names the held gates so
    child processes (including other tools that call ``devcap``) reuse them.
    """
    held = Hold(gate_names(pools, sims, devices), purpose, wait_seconds, hold_seconds,
                root or lock_root())
    previous = os.environ.get(HELD_ENV)
    held.acquire()
    try:
        os.environ[HELD_ENV] = held.environment()[HELD_ENV]
        yield held
    finally:
        if previous is None:
            os.environ.pop(HELD_ENV, None)
        else:
            os.environ[HELD_ENV] = previous
        held.release()

# endregion

# region CLI


def run_command(held: Hold, command: list[str]) -> int:
    """Run ``command`` in its own process group while ``held`` is held.

    SIGINT, SIGTERM and SIGHUP are forwarded to the whole group; a hold overrun
    terminates it.

    Returns:
        The command's exit code: 128 + signal number when it was signalled,
        or ``HOLD_TIMEOUT_EXIT`` when the hold overran.
    """
    proc = subprocess.Popen(command, env=held.environment(), start_new_session=os.name != "nt")

    def stop_group(sig=signal.SIGTERM) -> None:
        if proc.poll() is not None:
            return
        try:
            if os.name == "nt":
                proc.kill()
            else:
                os.killpg(proc.pid, sig)
        except OSError:
            pass

    def kill_after_grace() -> None:
        stop_group(signal.SIGTERM)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            stop_group(getattr(signal, "SIGKILL", signal.SIGTERM))

    held.on_overrun = kill_after_grace
    if os.name != "nt":
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, lambda signum, _frame: stop_group(signum))
    code = proc.wait()
    if held.overran:
        return HOLD_TIMEOUT_EXIT
    return 128 - code if code < 0 else code


def cmd_run(args: argparse.Namespace) -> int:
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        print("devcap run: missing command after --", file=sys.stderr)
        return 2
    names = gate_names(args.pool, args.sim, args.device)
    if not names:
        print("devcap run: name at least one --pool, --sim or --device", file=sys.stderr)
        return 2
    hold_seconds = None if args.hold <= 0 else min(args.hold, MAX_HOLD_SECONDS)
    held = Hold(names, args.purpose or " ".join(command)[:120], args.wait, hold_seconds)
    try:
        held.acquire()
    except WaitTimeout as error:
        print(f"devcap: {error}", file=sys.stderr)
        return WAIT_TIMEOUT_EXIT
    try:
        return run_command(held, command)
    finally:
        held.release()


def known_gates(root: Path) -> list[str]:
    """Gate directories present under ``root`` plus the two standard pools."""
    found = {p.name for p in root.iterdir() if p.is_dir()} if root.exists() else set()
    return sorted(found | {"simulator", "build"})


def cmd_status(args: argparse.Namespace) -> int:
    root = lock_root()
    now = time.time()
    report = []
    for name in known_gates(root):
        gate = Gate(name, root)
        report.append({"gate": name, "slots": gate.slots, "holders": gate.holders(),
                       "waiting": gate.waiting()})
    if args.json:
        print(json.dumps(report, indent=2))
        return 0
    for entry in report:
        if entry["gate"].startswith("device-") and not entry["holders"] and not entry["waiting"]:
            continue
        print(f"{entry['gate']}: {len(entry['holders'])}/{entry['slots']} held, "
              f"{len(entry['waiting'])} waiting")
        for h in entry["holders"]:
            age = describe_age(now - h.get("acquired_epoch", now))
            print(f"  slot {h['slot']}: pid {h.get('pid')} for {age}  {h.get('purpose', '')}  ({h.get('cwd', '?')})")
        for index, w in enumerate(entry["waiting"], 1):
            print(f"  queue {index}: pid {w['pid']}  {w['purpose']}")
    return 0


def cmd_slots(args: argparse.Namespace) -> int:
    for pool in args.pool or ["simulator", "build"]:
        print(f"{pool}={configured_slots(pool)}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="devcap", description=__doc__.split("\n\n")[0])
    parser.add_argument("--version", action="version", version=VERSION)
    sub = parser.add_subparsers(dest="cmd", required=True)

    run = sub.add_parser("run", help="wait for capacity, then run a command holding it")
    run.add_argument("--pool", action="append", default=[], help="pool to take a slot in (repeatable)")
    run.add_argument("--sim", action="append", default=[], metavar="UDID",
                     help="simulator: its device gate plus a 'simulator' slot (repeatable)")
    run.add_argument("--device", action="append", default=[], metavar="UDID",
                     help="physical device: its device gate only (repeatable)")
    run.add_argument("--purpose", default="", help="what this hold is for (shown to waiters)")
    run.add_argument("--wait", type=float, default=DEFAULT_WAIT_SECONDS,
                     help=f"seconds to queue before exiting {WAIT_TIMEOUT_EXIT} (default %(default)s)")
    run.add_argument("--hold", type=float, default=DEFAULT_HOLD_SECONDS,
                     help=f"max seconds to hold, ≤{MAX_HOLD_SECONDS:.0f}; 0 = no limit (default %(default)s)")
    run.add_argument("command", nargs=argparse.REMAINDER, help="-- command [args...]")
    run.set_defaults(func=cmd_run)

    status = sub.add_parser("status", help="show holders and waiters for every gate")
    status.add_argument("--json", action="store_true")
    status.set_defaults(func=cmd_status)

    slots = sub.add_parser("slots", help="print configured slot counts")
    slots.add_argument("pool", nargs="*")
    slots.set_defaults(func=cmd_slots)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

# endregion
