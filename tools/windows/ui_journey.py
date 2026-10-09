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

``{shots}`` in a step or an ``extra`` value expands to the ``--shots`` directory (Windows path), so journeys can
share a ``FST_DEBUG_DATA_DIR`` across relaunches (e.g. a dismissal persisting); ``{repo}`` in an ``extra`` value
expands to the repository root (e.g. ``FST_DEBUG_WHATS_NEW_FILE`` pointing at a checked-in fixture). An optional
``"extra": {"FST_DEBUG_PROFILE": "fixture-player-1:Name"}`` passes launch environment hooks,
``"args": ["--reduce-motion"]`` extra app arguments, and an optional ``"fixture": ["--band-rankings", "empty"]``
runs that journey against its own fixture service with those flags (``rivals_fixture.py`` unless ``--fixture``).

Usage::

    python tools/windows/ui_journey.py tools/windows/journeys/bands.json [--only NAME] [--shots DIR] [--exe aot] [--large-catalogue]
    python tools/windows/ui_journey.py tools/windows/journeys/star-rating.json --fixture tools/windows/star_rating_fixture.py

``--fixture`` runs a wrapper script (which takes ``mock_service.py`` flags and prints the same ready line) instead of
the plain mock service.
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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import journey_exe  # noqa: E402  (sibling module)

REPO_ROOT = Path(__file__).resolve().parents[2]
UIWIN = REPO_ROOT / "tools" / "windows" / "uiwin.py"
MOCK = REPO_ROOT / "tools" / "mock_service.py"
FIXTURE = REPO_ROOT / "tools" / "windows" / "rivals_fixture.py"
#: App under test (``--exe``: debug, release, aot or a path).
EXE = journey_exe.DEBUG_EXE

# region Fixture service


def journey_fixture(fixture: tuple[str, ...], override: Path | None = None) -> tuple[Path | None, tuple[str, ...]]:
    """The fixture script and flags for a journey's ``fixture`` list (same convention as ``a11y_matrix`` pages).

    A list starting with a ``.py`` name under ``tools/windows`` names its own wrapper (``["rankings_fixture.py",
    "--rankings-delay", "3"]``); otherwise its flags go to ``--fixture`` or :data:`FIXTURE`, and an empty list to the
    plain mock service. Naming the wrapper in the journey lets any runner (CI included) serve it correctly.

    Args:
        fixture: The journey's ``fixture`` list.
        override: ``--fixture`` from the command line, used when the journey names no wrapper.

    Returns:
        Script (``None``: plain mock service) and the flags for it.
    """
    if fixture and fixture[0].endswith(".py"):
        return REPO_ROOT / "tools" / "windows" / fixture[0], tuple(fixture[1:])
    return override or (FIXTURE if fixture else None), tuple(fixture)


def start_mock(log: Path, service_args: tuple[str, ...] = (), fixture: Path | None = None) -> tuple[subprocess.Popen, int]:
    """Start the fixture service on a free loopback port, logging to a file.

    A file (not a pipe) keeps a chatty service from blocking on a full pipe buffer. With a ``fixture`` script (for
    a journey's ``fixture`` flags, the Windows wrapper ``rivals_fixture.py``, which takes ``--band-rankings`` and
    every mock service flag) that script serves instead of the plain mock service.

    Args:
        log: Service output file.
        service_args: Extra ``mock_service.py`` flags (e.g. ``--large-catalogue``) and a journey's ``fixture`` flags.
        fixture: Optional wrapper script around ``mock_service.py`` (it raises the listen backlog itself).

    Returns:
        The process and its port.

    Raises:
        RuntimeError: The service did not report its port within 20 s.
    """
    handle = log.open("w", encoding="utf-8")
    # Python's default listen backlog (5) overflows when the app's artwork burst and page reads arrive together;
    # Windows then resets queued connections (WSAECONNABORTED), which the app correctly reports as offline.
    bootstrap = ("import sys; sys.path.insert(0, sys.argv[1]); import mock_service as m; "
                 "m.FixtureServer.request_queue_size = 128; sys.argv = ['mock_service', '--port', '0', *sys.argv[2:]]; m.main()")
    command = ([sys.executable, "-u", str(fixture), "--port", "0", *service_args] if fixture is not None
               else [sys.executable, "-u", "-c", bootstrap, str(MOCK.parent), *service_args])
    proc = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT)
    for _ in range(600):
        match = re.search(r"127\.0\.0\.1:(\d+)", log.read_text(encoding="utf-8", errors="replace"))
        if match:
            return proc, int(match.group(1))
        time.sleep(0.1)
    proc.kill()
    raise RuntimeError(f"fixture service did not start within 60 s; see {log}")

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


def launch_args(journey: dict, port: int, shots: Path) -> list[str]:
    """``uiwin.py launch`` arguments for one journey.

    Args:
        journey: Journey definition.
        port: Fixture service port.
        shots: Screenshot directory, substituted for ``{shots}`` in ``extra`` values.

    Returns:
        The argument list (after ``launch``).
    """
    return [str(EXE), "--route", journey["route"],
            "--arg=--base-url", f"--arg=http://127.0.0.1:{port}/",
            "--preset", journey.get("preset", "medium"),
            *(f"--arg={arg}" for arg in journey.get("args", [])),
            *(f"--extra={key}={expand(str(value), shots)}" for key, value in journey.get("extra", {}).items())]


def expand(value: str, shots: Path) -> str:
    """Expands ``{shots}`` (the screenshot directory) and ``{repo}`` (the repository root) in a launch hook value.

    Args:
        value: ``extra`` value from a journey.
        shots: Screenshot directory.

    Returns:
        The value with both placeholders replaced.
    """
    return value.replace("{shots}", str(shots)).replace("{repo}", str(REPO_ROOT))


def run_journey(journey: dict, port: int, shots: Path) -> tuple[bool, str]:
    """Launch, drive and close one journey.

    Args:
        journey: Journey definition.
        port: Fixture service port.
        shots: Screenshot directory for ``{shots}``.

    Returns:
        Pass flag and a short failure detail.
    """
    launch = uiwin("launch", *launch_args(journey, port, shots))
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
    journey_exe.add_argument(parser)
    parser.add_argument("--retries", type=int, default=1,
                        help="re-run a failed journey this many times; a later pass is reported as FLAKY")
    parser.add_argument("--large-catalogue", action="store_true",
                        help="also serve mock_service.py's synthetic 108-song catalogue (e.g. a raw-6 chart)")
    parser.add_argument("--fixture", type=Path,
                        help="fixture wrapper script taking mock_service.py flags (e.g. tools/windows/star_rating_fixture.py)")
    args = parser.parse_args(argv)
    global EXE
    EXE = args.exe
    if not EXE.is_file():
        print(f"error: build first (tools/windows/build.ps1); no {EXE}", file=sys.stderr)
        return 1
    args.shots.mkdir(parents=True, exist_ok=True)
    journeys = json.loads(args.journeys.read_text(encoding="utf-8"))
    selected = [j for j in journeys if not args.only or j["name"] in args.only]
    services: dict[tuple[str, ...], tuple[subprocess.Popen, int]] = {}
    base = ("--large-catalogue",) if args.large_catalogue else ()
    failures = 0
    try:
        for journey in selected:
            extra = tuple(journey.get("fixture", ()))
            if extra not in services:
                log = "fixture-service.log" if not services else f"fixture-service-{len(services)}.log"
                script, flags = journey_fixture(extra, args.fixture)
                services[extra] = start_mock(args.shots / log, base + flags, script)
            port = services[extra][1]
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
        for mock, _ in services.values():
            mock.kill()
    print(f"{len(selected) - failures}/{len(selected)} journeys passed; screenshots in {args.shots}")
    return 1 if failures else 0

# endregion


if __name__ == "__main__":
    sys.exit(main())
