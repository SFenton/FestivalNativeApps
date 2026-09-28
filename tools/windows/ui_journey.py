#!/usr/bin/env python3
"""Run scripted Windows UI journeys against the fixture service.

A journey file (JSON) lists journeys, each launching this worktree's Debug build on
a route at a window preset and running ``uiwin.py drive`` steps. ``waitfor:`` steps
are the assertions: a missing element fails the driver (exit 3) and the journey.
The loopback fixture service (``tools/mock_service.py``) is started on a free port
and stopped afterwards; journeys never touch production.

Journey file shape::

    [{"name": "player-bands", "route": "/bands/player/fixture-player-1",
      "preset": "medium", "steps": ["waitfor:id=fst.player-bands.title@10", "..."]}]

``{shots}`` in a step expands to the ``--shots`` directory (Windows path).

Usage::

    python tools/windows/ui_journey.py tools/windows/journeys/bands.json [--only NAME] [--shots DIR]
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
UIWIN = REPO_ROOT / "tools" / "windows" / "uiwin.py"
MOCK = REPO_ROOT / "tools" / "mock_service.py"
EXE = (REPO_ROOT / "windows" / "Festival.App" / "bin" / "x64" / "Debug" /
       "net9.0-windows10.0.26100.0" / "win-x64" / "FestivalScoreTracker.exe")

# region Fixture service


def start_mock(log: Path) -> tuple[subprocess.Popen, int]:
    """Start the fixture service on a free loopback port, logging to a file.

    A file (not a pipe) keeps a chatty service from blocking on a full pipe buffer.

    Args:
        log: Service output file.

    Returns:
        The process and its port.

    Raises:
        RuntimeError: The service did not report its port within 20 s.
    """
    handle = log.open("w", encoding="utf-8")
    # Python's default listen backlog (5) overflows when the app's artwork burst and page reads arrive together;
    # Windows then resets queued connections (WSAECONNABORTED), which the app correctly reports as offline.
    bootstrap = ("import sys; sys.path.insert(0, sys.argv[1]); import mock_service as m; "
                 "m.FixtureServer.request_queue_size = 128; sys.argv = ['mock_service', '--port', '0']; m.main()")
    proc = subprocess.Popen([sys.executable, "-u", "-c", bootstrap, str(MOCK.parent)], stdout=handle, stderr=subprocess.STDOUT)
    for _ in range(200):
        match = re.search(r"127\.0\.0\.1:(\d+)", log.read_text(encoding="utf-8", errors="replace"))
        if match:
            return proc, int(match.group(1))
        time.sleep(0.1)
    proc.kill()
    raise RuntimeError(f"fixture service did not start; see {log}")

# endregion

# region Journeys


def uiwin(*args: str) -> subprocess.CompletedProcess:
    """Run ``uiwin.py`` with the given arguments.

    Args:
        *args: CLI arguments.

    Returns:
        The completed process (output captured).
    """
    return subprocess.run([sys.executable, str(UIWIN), *args], capture_output=True, text=True)


def run_journey(journey: dict, port: int, shots: Path) -> tuple[bool, str]:
    """Launch, drive and close one journey.

    Args:
        journey: Journey definition.
        port: Fixture service port.
        shots: Screenshot directory for ``{shots}``.

    Returns:
        Pass flag and a short failure detail.
    """
    launch = uiwin("launch", str(EXE), "--route", journey["route"],
                   "--arg=--base-url", f"--arg=http://127.0.0.1:{port}/",
                   "--preset", journey.get("preset", "medium"))
    if launch.returncode != 0:
        return False, "launch: " + launch.stderr.strip()
    steps = [s.replace("{shots}", str(shots)) for s in journey["steps"]]
    with tempfile.NamedTemporaryFile("w", suffix=".steps", delete=False, encoding="utf-8") as handle:
        handle.write("\n".join(steps))
    try:
        drive = uiwin("drive", "--steps-file", handle.name)
        if drive.returncode != 0:
            uiwin("shot", str(shots / f"{journey['name']}-failure.png"))
    finally:
        Path(handle.name).unlink(missing_ok=True)
        uiwin("close")
    if drive.returncode != 0:
        return False, drive.stderr.strip().splitlines()[-1] + f" (see {journey['name']}-failure.png)"
    return True, ""


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        0 when every journey passed, 1 otherwise.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("journeys", type=Path)
    parser.add_argument("--only", action="append", help="run only these journey names")
    parser.add_argument("--shots", type=Path, default=Path(tempfile.gettempdir()) / "fst-journeys")
    parser.add_argument("--retries", type=int, default=1,
                        help="re-run a failed journey this many times; a later pass is reported as FLAKY")
    args = parser.parse_args(argv)
    if not EXE.is_file():
        print(f"error: build first (tools/windows/build.ps1); no {EXE}", file=sys.stderr)
        return 1
    args.shots.mkdir(parents=True, exist_ok=True)
    journeys = json.loads(args.journeys.read_text(encoding="utf-8"))
    selected = [j for j in journeys if not args.only or j["name"] in args.only]
    mock, port = start_mock(args.shots / "fixture-service.log")
    failures = 0
    try:
        for journey in selected:
            ok, detail = run_journey(journey, port, args.shots.resolve())
            attempts = 1
            while not ok and attempts <= args.retries:
                print(f"RETRY {journey['name']}: {detail}", flush=True)
                ok, _ = run_journey(journey, port, args.shots.resolve())
                attempts += 1
            failures += not ok
            verdict = "FAIL" if not ok else "FLAKY" if attempts > 1 else "PASS"
            print(f"{verdict} {journey['name']}" + (f": {detail}" if not ok else ""), flush=True)
    finally:
        mock.kill()
    print(f"{len(selected) - failures}/{len(selected)} journeys passed; screenshots in {args.shots}")
    return 1 if failures else 0

# endregion


if __name__ == "__main__":
    sys.exit(main())
