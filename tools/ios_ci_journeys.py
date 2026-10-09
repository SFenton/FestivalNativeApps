#!/usr/bin/env python3
"""``apple-ci`` simulator step: runs the iPhone XCUITest journeys in :data:`JOURNEYS`.

The hosted ``apple-ci`` job compiles the app and runs ``swift test`` on the macOS host; this script adds the few
XCUITest journeys that only a simulator can prove, such as the production iPhone chrome's accessibility reading order
(issue #394). For each fixture group it serves ``tools/mock_service.py`` on an OS-assigned loopback port (so CI never
calls the live service and a shared Mac's other fixtures keep their ports), exports it to the test runner as
``TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL``, then calls ``tools/ios_sim.py uitest`` with that group's selectors. A
journey listed here must read its fixture origin from ``FST_SONGS_SCROLL_FIXTURE_URL``.

``--create-simulator`` makes a throwaway iPhone simulator on the newest available iOS runtime and deletes it
afterwards. It runs only inside GitHub Actions (``GITHUB_ACTIONS=true``): on a shared Mac, use ``--device`` with one
of ``ios_sim.py``'s product simulators instead, and never create or delete devices by hand.

A journey is in CI only when it has a :data:`JOURNEYS` entry; ``tools/tests/test_ios_ci_journeys.py`` checks them.
Keep the list short: every entry adds simulator time to the required check.

Usage::

    python3 tools/ios_ci_journeys.py --list
    python3 tools/ios_ci_journeys.py --device iphone                 # a Mac's product simulator
    python3 tools/ios_ci_journeys.py --create-simulator              # apple-ci only
"""

from __future__ import annotations

import argparse
import json
import os
import re
import select as _select
import subprocess
import sys
import threading
from collections.abc import Iterator, Sequence
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer"

#: ``xcodebuild`` passes ``TEST_RUNNER_``-prefixed variables to the UI-test runner without the prefix.
FIXTURE_URL_ENV = "TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL"

#: Device types tried, in order, for ``--create-simulator`` (the journeys' reference width first).
DEVICE_TYPES = ("iPhone 17 Pro", "iPhone 16 Pro")

# region Journeys (pure, unit-tested)


@dataclass(frozen=True)
class Journey:
    """One XCUITest selector and the loopback fixture it needs.

    Attributes:
        selector: ``Class/testMethod`` in the ``FestivalMobileUITests`` target.
        reason: Why it runs in CI (issue and what it guards).
        fixture: Extra ``tools/mock_service.py`` flags (empty: the default two-song fixture).
    """

    selector: str
    reason: str
    fixture: tuple[str, ...] = ()


#: Journeys the ``apple-ci`` simulator step runs, in order.
JOURNEYS: tuple[Journey, ...] = (
    # Issue #394 (for #14), page-tools-and-nav-chrome R17: Profile (navigation bar) reads before the bell (tab-bar
    # accessory), each a separate labelled button in its production container.
    Journey("NavButtonHitRegionJourneyTests/testAccountButtonsReadInProductionChromeOrder",
            "#394: Profile then bell in the production iPhone chrome (Songs)"),
    Journey("NavButtonHitRegionJourneyTests/testAccountButtonsReadInProductionChromeOrderOnPushedPage",
            "#394: Back then Profile, then the bell, on a pushed page"),
    Journey("NavButtonHitRegionJourneyTests/testChooseProfileReadsAloneInProductionChrome",
            "#394: anonymous Choose Profile is the bar's last button and no bell shows"),
    Journey("NavButtonHitRegionJourneyTests/testAccountButtonsStaySeparateAndLabelledAtLargestTextSize",
            "#394: labels, 44 pt targets, audit and order at AX XXXL text"),
)


def fixture_groups(journeys: Sequence[Journey]) -> list[tuple[tuple[str, ...], list[str]]]:
    """Group selectors by fixture, keeping first-appearance order, so each fixture is served once.

    Args:
        journeys: Journeys to run.

    Returns:
        ``(fixture flags, selectors)`` pairs.
    """
    groups: dict[tuple[str, ...], list[str]] = {}
    for journey in journeys:
        groups.setdefault(journey.fixture, []).append(journey.selector)
    return list(groups.items())


def choose(journeys: Sequence[Journey], only: Sequence[str] | None) -> list[Journey]:
    """Filter journeys by selector substrings.

    Args:
        journeys: All journeys.
        only: Substrings; a journey runs when its selector contains any of them (``None``: all).

    Returns:
        The chosen journeys, in order.

    Raises:
        ValueError: When a substring matches no journey.
    """
    if not only:
        return list(journeys)
    for needle in only:
        if not any(needle in journey.selector for journey in journeys):
            raise ValueError(f"no CI journey matches {needle!r}")
    return [journey for journey in journeys if any(needle in journey.selector for needle in only)]


def _version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", version))


def pick_runtime(runtimes_json: dict) -> str:
    """Choose the newest available iOS runtime from ``simctl list runtimes -j``.

    Args:
        runtimes_json: Parsed ``simctl list runtimes -j`` output.

    Returns:
        The runtime identifier.

    Raises:
        LookupError: When no iOS runtime is available.
    """
    ios = [
        runtime for runtime in runtimes_json.get("runtimes", [])
        if runtime.get("isAvailable") and runtime.get("platform", runtime.get("name", "")).startswith("iOS")
    ]
    if not ios:
        raise LookupError("no available iOS simulator runtime")
    return max(ios, key=lambda runtime: _version_key(runtime.get("version", "")))["identifier"]


def pick_device_type(runtime: dict | None, devicetypes_json: dict) -> str:
    """Choose the first of :data:`DEVICE_TYPES` the runtime supports.

    Args:
        runtime: The chosen runtime's entry (its ``supportedDeviceTypes`` limit the choice when present).
        devicetypes_json: Parsed ``simctl list devicetypes -j`` output.

    Returns:
        The device type identifier.

    Raises:
        LookupError: When none of :data:`DEVICE_TYPES` is available.
    """
    supported = (runtime or {}).get("supportedDeviceTypes") or devicetypes_json.get("devicetypes", [])
    by_name = {entry.get("name"): entry.get("identifier") for entry in supported}
    for name in DEVICE_TYPES:
        if by_name.get(name):
            return by_name[name]
    raise LookupError(f"none of {DEVICE_TYPES} is available")


def parse_ready_port(line: str) -> int | None:
    """Read the port from ``mock_service.py``'s ready line.

    Args:
        line: One stdout line.

    Returns:
        The port, or ``None`` when the line is not the ready line.
    """
    match = re.search(r"fixture service on 127\.0\.0\.1:(\d+)", line)
    return int(match.group(1)) if match else None

# endregion

# region Runner


def _env() -> dict[str, str]:
    env = dict(os.environ)
    env["DEVELOPER_DIR"] = DEVELOPER_DIR
    return env


def _simctl_json(*args: str) -> dict:
    out = subprocess.run(["xcrun", "simctl", "list", *args, "-j"], env=_env(), check=True,
                         capture_output=True, text=True).stdout
    return json.loads(out)


@contextmanager
def throwaway_simulator() -> Iterator[str]:
    """Create an iPhone simulator for this run and delete it afterwards (GitHub Actions only).

    Yields:
        The new simulator's UDID.
    """
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise SystemExit("--create-simulator runs only in GitHub Actions; pass --device on a shared Mac")
    runtimes = _simctl_json("runtimes")
    runtime_id = pick_runtime(runtimes)
    runtime = next(entry for entry in runtimes["runtimes"] if entry["identifier"] == runtime_id)
    device_type = pick_device_type(runtime, _simctl_json("devicetypes"))
    udid = subprocess.run(["xcrun", "simctl", "create", "FST CI iPhone", device_type, runtime_id], env=_env(),
                          check=True, capture_output=True, text=True).stdout.strip()
    print(f"created simulator {udid} ({device_type}, {runtime_id})", file=sys.stderr, flush=True)
    try:
        yield udid
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", udid], env=_env(), check=False, capture_output=True)
        subprocess.run(["xcrun", "simctl", "delete", udid], env=_env(), check=False, capture_output=True)


@contextmanager
def fixture_service(flags: Sequence[str], port: int = 0, ready_timeout: float = 60.0) -> Iterator[int]:
    """Serve ``tools/mock_service.py`` on loopback for the duration of the block.

    Args:
        flags: Extra fixture flags.
        port: Loopback port (0: OS-assigned).
        ready_timeout: Seconds to wait for the ready line.

    Yields:
        The bound port.
    """
    process = subprocess.Popen(
        [sys.executable, str(REPO_ROOT / "tools" / "mock_service.py"), "--port", str(port), *flags],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    try:
        ready = None
        while ready is None:
            readable, _, _ = _select.select([process.stdout], [], [], ready_timeout)
            line = process.stdout.readline() if readable else ""
            if not line:
                raise SystemExit(f"mock_service.py {' '.join(flags)} did not start")
            ready = parse_ready_port(line)
        # Keep draining its request log so a full pipe never blocks the server.
        threading.Thread(target=lambda: [None for _ in process.stdout], daemon=True).start()
        print(f"fixture service {' '.join(flags) or '(default)'} on 127.0.0.1:{ready}", file=sys.stderr, flush=True)
        yield ready
    finally:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
        process.stdout.close()


def run(journeys: Sequence[Journey], device: str, timeout: float) -> int:
    """Run each fixture group through ``ios_sim.py uitest`` on ``device``.

    Args:
        journeys: Journeys to run.
        device: ``ios_sim.py`` device alias or UDID.
        timeout: Seconds per ``uitest`` batch.

    Returns:
        0 when every group passed, else the last failing exit code.
    """
    code = 0
    for flags, selectors in fixture_groups(journeys):
        with fixture_service(flags) as port:
            env = _env()
            env[FIXTURE_URL_ENV] = f"http://127.0.0.1:{port}"
            cmd = [sys.executable, str(REPO_ROOT / "tools" / "ios_sim.py"), "uitest", "--device", device,
                   "--batch-size", str(len(selectors)), "--timeout", str(timeout)]
            for selector in selectors:
                cmd += ["--only", selector]
            print("+", " ".join(cmd), file=sys.stderr, flush=True)
            result = subprocess.run(cmd, cwd=REPO_ROOT, env=env, check=False)
            code = result.returncode or code
    return code


def main(argv: Sequence[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments (default: ``sys.argv[1:]``).

    Returns:
        Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    target = parser.add_mutually_exclusive_group()
    target.add_argument("--device", help="ios_sim.py device alias or UDID")
    target.add_argument("--create-simulator", action="store_true",
                        help="create (and afterwards delete) a throwaway iPhone simulator; GitHub Actions only")
    parser.add_argument("--only", action="append", help="run journeys whose selector contains this (repeatable)")
    parser.add_argument("--timeout", type=float, default=900.0, help="seconds per uitest batch")
    parser.add_argument("--list", action="store_true", help="print the CI journeys and exit")
    args = parser.parse_args(argv)
    try:
        journeys = choose(JOURNEYS, args.only)
    except ValueError as error:
        parser.error(str(error))
    if args.list:
        for journey in journeys:
            print(f"{journey.selector}  [{' '.join(journey.fixture) or 'default fixture'}]  {journey.reason}")
        return 0
    if args.create_simulator:
        with throwaway_simulator() as udid:
            return run(journeys, udid, args.timeout)
    if not args.device:
        parser.error("pass --device or --create-simulator")
    return run(journeys, args.device, args.timeout)

# endregion


if __name__ == "__main__":
    sys.exit(main())
