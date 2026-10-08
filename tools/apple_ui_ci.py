#!/usr/bin/env python3
"""``apple-ci`` iPhone journeys: runs the XCUITest accessibility journeys in :data:`RUNS` on an iPhone simulator.

The macOS hosted tests (``swift test``) cannot exercise iOS Dynamic Type, iOS rendering or
``performAccessibilityAudit``. This is the one registry of iPhone XCUITest journeys that gate pull requests: a journey
is in CI only when it has a :data:`RUNS` entry. ``.github/workflows/apple-ci.yml`` calls it with
``--create-simulator`` on the hosted runner, which creates a runner-local iPhone simulator (the newest iOS runtime
that supports :data:`PREFERRED_DEVICE`) and deletes it afterwards. Each run serves its own loopback
``tools/mock_service.py`` on a free port and passes the origin to the journey as ``TEST_RUNNER_<fixture_env>``, so CI
makes no service calls. Journeys run through ``tools/ios_sim.py uitest`` (serialized under its simulator lock).

On a shared Mac leave out ``--create-simulator``: ``--device`` (default ``iphone``) names an existing ``ios_sim.py``
alias, and this tool never creates, erases or deletes it. ``tests/test_apple_ui_ci.py`` checks the entries, that each
selector names a journey method in ``apple/Apps/iOSUITests`` that reads its fixture variable, and that the #441
section-title AX5 journey is registered.

Usage::

    python3 tools/apple_ui_ci.py --create-simulator             # CI: every run on a fresh runner-local simulator
    python3 tools/apple_ui_ci.py --device iphone27               # local: an existing ios_sim.py alias
    python3 tools/apple_ui_ci.py --only songs-section-titles-ax5
    python3 tools/apple_ui_ci.py --list
"""

from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

REPO_ROOT = Path(__file__).resolve().parent.parent
IOS_SIM = REPO_ROOT / "tools" / "ios_sim.py"
MOCK_SERVICE = REPO_ROOT / "tools" / "mock_service.py"
DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer"

#: Device type the journeys are written against (the ``iphone`` alias in ``tools/ios_sim.py``).
PREFERRED_DEVICE = "iPhone 17 Pro"

#: Name of the simulator ``--create-simulator`` makes (and deletes) on a CI runner.
CI_SIMULATOR_NAME = "FST apple-ci iPhone"

#: ``mock_service.py``'s ready line, which names the port it bound.
READY_LINE = re.compile(r"Local test fixture service on 127\.0\.0\.1:(\d+)")

# region Runs (pure, unit-tested)


@dataclass(frozen=True)
class Run:
    """One ``ios_sim.py uitest`` invocation against its own loopback fixture service.

    Attributes:
        name: Run name (``--only`` value).
        selectors: ``Class/testMethod`` XCUITest selectors in ``FestivalMobileUITests``.
        fixture_env: Variable the journeys read the fixture origin from (exported as ``TEST_RUNNER_<name>``).
        fixture_args: Extra ``mock_service.py`` flags.
        a11y: ``ios_sim.py uitest --a11y`` simulator settings for the batch.
        timeout: Seconds per ``ios_sim.py`` batch (the cold first launch on a fresh runner is slow).
    """

    name: str
    selectors: tuple[str, ...]
    fixture_env: str = "FST_FIXTURE_URL"
    fixture_args: tuple[str, ...] = ()
    a11y: tuple[str, ...] = ()
    timeout: float = 600.0

    def uitest_argv(self, device: str) -> list[str]:
        """``ios_sim.py uitest`` arguments for this run.

        Args:
            device: ``ios_sim.py`` alias or simulator UDID.

        Returns:
            Argument vector, starting with the Python interpreter.
        """
        argv = [sys.executable, str(IOS_SIM), "uitest", "--device", device, "--timeout", f"{self.timeout:g}",
                "--batch-size", str(len(self.selectors))]
        for selector in self.selectors:
            argv += ["--only", selector]
        for setting in self.a11y:
            argv += ["--a11y", setting]
        return argv


#: Journeys the ``apple-ci`` job runs on an iPhone simulator, in order.
RUNS: tuple[Run, ...] = (
    # Songs grouped-sort section titles (issues #91, #441): at AX5 each Item Shop title grows to the line, is a heading
    # named as shown, reads above its own song after the previous section's, keeps 4.5:1 rendered contrast with no
    # backing, and the page passes performAccessibilityAudit. Every sort's order/semantics: the hosted
    # SongsSectionTitleAccessibilityTests.
    Run("songs-section-titles-ax5", ("SongsJourneyTests/testSongsShopSortSectionTitlesAreAccessibleAtAX5",)),
)


def select(runs: tuple[Run, ...], only: str | None) -> list[Run]:
    """Runs named by ``--only`` (all when empty).

    Args:
        runs: Candidate runs.
        only: Comma-separated run names, or ``None``.

    Returns:
        The selected runs, in :data:`RUNS` order.

    Raises:
        ValueError: A name matches no run.
    """
    if not only:
        return list(runs)
    wanted = {name for name in only.split(",") if name}
    unknown = wanted - {run.name for run in runs}
    if unknown:
        raise ValueError(f"unknown run(s): {', '.join(sorted(unknown))}")
    return [run for run in runs if run.name in wanted]


def _version(text: str) -> tuple[int, ...]:
    """Numeric version key (``"27.1"`` -> ``(27, 1)``)."""
    return tuple(int(part) for part in re.findall(r"\d+", text))


def pick_runtime(runtimes: dict, device: str = PREFERRED_DEVICE) -> tuple[str, str]:
    """Choose the newest available iOS runtime that supports ``device``.

    Args:
        runtimes: ``xcrun simctl list runtimes -j`` output.
        device: Device type name the runtime must support.

    Returns:
        ``(runtime identifier, device type identifier)``.

    Raises:
        LookupError: No available iOS runtime supports ``device``.
    """
    candidates = []
    for runtime in runtimes.get("runtimes", []):
        if runtime.get("platform") != "iOS" or not runtime.get("isAvailable"):
            continue
        for device_type in runtime.get("supportedDeviceTypes", []):
            if device_type.get("name") == device:
                candidates.append((_version(runtime.get("version", "")), runtime["identifier"],
                                   device_type["identifier"]))
    if not candidates:
        raise LookupError(f"no available iOS simulator runtime supports {device!r}")
    _, runtime_id, device_type_id = max(candidates)
    return runtime_id, device_type_id


def ready_port(line: str) -> int | None:
    """Port named by a ``mock_service.py`` ready line, or ``None`` for any other line."""
    match = READY_LINE.search(line)
    return int(match.group(1)) if match else None

# endregion

# region Side effects


def _xcrun(*args: str) -> str:
    """Run ``xcrun`` with Xcode pinned and return its stdout."""
    env = dict(os.environ, DEVELOPER_DIR=DEVELOPER_DIR)
    return subprocess.run(["xcrun", *args], env=env, check=True, capture_output=True, text=True).stdout


@contextmanager
def ci_simulator() -> Iterator[str]:
    """Create a runner-local iPhone simulator for the block and delete it afterwards (CI runners only).

    Yields:
        The new simulator's UDID.
    """
    runtime_id, device_type_id = pick_runtime(json.loads(_xcrun("simctl", "list", "runtimes", "-j")))
    udid = _xcrun("simctl", "create", CI_SIMULATOR_NAME, device_type_id, runtime_id).strip()
    print(f"created {CI_SIMULATOR_NAME} {udid} ({device_type_id}, {runtime_id})", flush=True)
    try:
        yield udid
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", udid], env=dict(os.environ, DEVELOPER_DIR=DEVELOPER_DIR),
                       check=False, capture_output=True)
        subprocess.run(["xcrun", "simctl", "delete", udid], env=dict(os.environ, DEVELOPER_DIR=DEVELOPER_DIR),
                       check=False, capture_output=True)


@contextmanager
def fixture_service(args: tuple[str, ...], timeout: float = 90.0) -> Iterator[str]:
    """Serve ``mock_service.py`` on a free loopback port for the block.

    Its output goes to a log file (never an undrained pipe, which would block a chatty server) and is echoed
    when the block fails; a service that never gets ready is aborted first, so the log holds its stack.

    Args:
        args: Extra ``mock_service.py`` flags.
        timeout: Seconds to wait for the ready line.

    Yields:
        The fixture origin (``http://127.0.0.1:<port>``).

    Raises:
        RuntimeError: The service exited, or printed no ready line in time.
    """
    with tempfile.NamedTemporaryFile("w+", prefix="fst-apple-ui-ci-fixture-", suffix=".log", delete=False) as log:
        log_path = Path(log.name)
        proc = subprocess.Popen([sys.executable, "-u", "-X", "faulthandler", str(MOCK_SERVICE), "--port", "0", *args],
                                stdout=log, stderr=subprocess.STDOUT, text=True)
    succeeded = False
    try:
        deadline = time.monotonic() + timeout
        port = None
        while port is None:
            port = next(filter(None, map(ready_port, log_path.read_text(errors="replace").splitlines())), None)
            if port is None and (proc.poll() is not None or time.monotonic() > deadline):
                if proc.poll() is None:
                    # faulthandler writes every thread's stack to the log: where the start stalled.
                    proc.send_signal(signal.SIGABRT)
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        pass
                raise RuntimeError(f"mock_service.py not ready (exit {proc.poll()}); log {log_path}")
            if port is None:
                time.sleep(0.1)
        yield f"http://127.0.0.1:{port}"
        succeeded = True
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()
        if succeeded:
            log_path.unlink(missing_ok=True)
        else:
            print(f"fixture log {log_path}:\n" + "\n".join(log_path.read_text(errors="replace").splitlines()[-40:]),
                  file=sys.stderr)


def run_one(run: Run, device: str) -> int:
    """Run one journey batch against its own fixture service.

    Args:
        run: The run.
        device: ``ios_sim.py`` alias or simulator UDID.

    Returns:
        ``ios_sim.py``'s exit code.
    """
    with fixture_service(run.fixture_args) as origin:
        env = dict(os.environ)
        env[f"TEST_RUNNER_{run.fixture_env}"] = origin
        print(f"== {run.name} (fixture {origin})", flush=True)
        return subprocess.run(run.uitest_argv(device), cwd=REPO_ROOT, env=env, check=False).returncode

# endregion


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        0 when every run passed, 1 otherwise.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--only", help="comma-separated run names")
    parser.add_argument("--device", default="iphone", help="existing ios_sim.py alias or UDID (default: iphone)")
    parser.add_argument("--create-simulator", action="store_true",
                        help=f"CI runners only: create (and delete) a {PREFERRED_DEVICE} simulator for the runs")
    parser.add_argument("--list", action="store_true", help="print the runs and exit")
    args = parser.parse_args(argv)
    try:
        runs = select(RUNS, args.only)
    except ValueError as error:
        parser.error(str(error))
    if args.list:
        for run in runs:
            a11y = f" a11y={','.join(run.a11y)}" if run.a11y else ""
            print(f"{run.name}: {' '.join(run.selectors)} fixture={run.fixture_env}{a11y}")
        return 0

    def run_all(device: str) -> list[str]:
        return [run.name for run in runs if run_one(run, device) != 0]

    if args.create_simulator:
        with ci_simulator() as udid:
            failed = run_all(udid)
    else:
        failed = run_all(args.device)
    print(f"apple-ci journeys: {len(runs) - len(failed)}/{len(runs)} run(s) passed"
          + (f"; failed: {', '.join(failed)}" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
