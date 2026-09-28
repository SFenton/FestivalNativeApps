#!/usr/bin/env python3
"""Run the global-search UI journeys and prove no band search reached the fixture service.

Wraps ``ui_journey.py``: the loopback fixture service additionally records each request
*path* (no query string, so no search text) to ``<shots>/fixture-paths.log``, every journey
gets a fresh isolated settings file (``--settings-path``) so selecting a player never
touches real settings, and after the run the path log must contain at least one
``/api/account/search`` and no ``/api/bands/search``. ``--axe`` also opens the Search page
with results and runs an Axe.Windows scan (``tools/windows/axe_scan.ps1``) into ``<shots>/axe``.

Usage::

    python tools/windows/search_journey.py [--only NAME] [--shots DIR] [--retries N] [--axe] [--exe PATH]
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
import ui_journey  # noqa: E402  (sibling module)

JOURNEYS = Path(__file__).resolve().parent / "journeys" / "search.json"
BAND_SEARCH = "/api/bands/search"
#: App under test; ``--exe`` replaces it (e.g. the NativeAOT Release build). Routes go as app arguments,
#: which Release builds honour (they ignore ``FST_DEBUG_*``).
EXE = ui_journey.EXE
ACCOUNT_SEARCH = "/api/account/search"

# region Fixture service


def start_logging_mock(log: Path, paths: Path) -> tuple[subprocess.Popen, int]:
    """Start the fixture service with a request-path log.

    Args:
        log: Service output file.
        paths: File receiving one request path per line.

    Returns:
        The process and its port.

    Raises:
        RuntimeError: The service did not report its port within 20 s.
    """
    paths.write_text("", encoding="utf-8")
    handle = log.open("w", encoding="utf-8")
    bootstrap = (
        "import sys, threading; sys.path.insert(0, sys.argv[1]); import mock_service as m; "
        "lock = threading.Lock(); target = sys.argv[2]\n"
        "def log_request(self, code='-', size='-'):\n"
        "    with lock, open(target, 'a', encoding='utf-8') as f: f.write(self.path.split('?')[0] + '\\n')\n"
        "m.FixtureHandler.log_request = log_request; m.FixtureServer.request_queue_size = 128; "
        "sys.argv = ['mock_service', '--port', '0']; m.main()")
    proc = subprocess.Popen([sys.executable, "-u", "-c", bootstrap, str(ui_journey.MOCK.parent), str(paths)],
                            stdout=handle, stderr=subprocess.STDOUT)
    for _ in range(200):
        match = re.search(r"127\.0\.0\.1:(\d+)", log.read_text(encoding="utf-8", errors="replace"))
        if match:
            return proc, int(match.group(1))
        time.sleep(0.1)
    proc.kill()
    raise RuntimeError(f"fixture service did not start; see {log}")

# endregion

# region Journeys


def run_journey(journey: dict, port: int, shots: Path) -> tuple[bool, str]:
    """Launch with isolated settings, drive and close one journey.

    Args:
        journey: Journey definition (``name``, ``route``, ``preset``, ``steps``).
        port: Fixture service port.
        shots: Screenshot directory for ``{shots}``.

    Returns:
        Pass flag and a short failure detail.
    """
    settings = Path(tempfile.gettempdir()) / f"fst-search-settings-{journey['name']}.json"
    settings.unlink(missing_ok=True)
    launch = ui_journey.uiwin("launch", str(EXE), f"--arg=--route={journey['route']}",
                              "--arg=--base-url", f"--arg=http://127.0.0.1:{port}/",
                              "--arg=--settings-path", f"--arg={settings}",
                              # The first-run carousel is modal and would swallow the scripted input.
                              "--arg=--first-run=off",
                              "--preset", journey.get("preset", "medium"))
    if launch.returncode != 0:
        return False, "launch: " + launch.stderr.strip()
    steps = [s.replace("{shots}", str(shots)) for s in journey["steps"]]
    with tempfile.NamedTemporaryFile("w", suffix=".steps", delete=False, encoding="utf-8") as handle:
        handle.write("\n".join(steps))
    try:
        drive = ui_journey.uiwin("drive", "--steps-file", handle.name)
        if drive.returncode != 0:
            ui_journey.uiwin("shot", str(shots / f"{journey['name']}-failure.png"), "--mode", "screen")
            ui_journey.uiwin("tree", str(shots / f"{journey['name']}-failure.txt"))
    finally:
        Path(handle.name).unlink(missing_ok=True)
        ui_journey.uiwin("close")
        settings.unlink(missing_ok=True)
    if drive.returncode != 0:
        lines = (drive.stderr.strip() or drive.stdout.strip() or "driver failed").splitlines()
        return False, lines[-1] + f" (see {journey['name']}-failure.png)"
    return True, ""


def axe_scan(port: int, shots: Path) -> bool:
    """Open the Search page with results and scan it with Axe.Windows.

    Args:
        port: Fixture service port.
        shots: Output root (results go to ``axe/``).

    Returns:
        Whether the scan reported no errors.
    """
    launch = ui_journey.uiwin("launch", str(EXE), "--arg=--route=/search?q=fixture",
                              "--arg=--base-url", f"--arg=http://127.0.0.1:{port}/", "--arg=--first-run=off", "--preset", "medium")
    if launch.returncode != 0:
        print("axe: launch failed: " + launch.stderr.strip())
        return False
    try:
        pid = json.loads(launch.stdout)["pid"]
        with tempfile.NamedTemporaryFile("w", suffix=".steps", delete=False, encoding="utf-8") as handle:
            handle.write("waitfor:id=fst.global-search.result.player@15")
        ready = ui_journey.uiwin("drive", "--steps-file", handle.name)
        Path(handle.name).unlink(missing_ok=True)
        if ready.returncode != 0:
            print("axe: Search page did not load results")
            return False
        scan = subprocess.run(["pwsh", "-NoProfile", "-File", str(Path(__file__).resolve().parent / "axe_scan.ps1"),
                               "-ProcessId", str(pid), "-OutputDirectory", str(shots / "axe"), "-ScanId", "search-page"],
                              capture_output=True, text=True)
        print("axe: " + " ".join(scan.stdout.split()))
        return scan.returncode == 0
    finally:
        ui_journey.uiwin("close")


def check_paths(paths: Path) -> list[str]:
    """Checks the request-path log.

    Args:
        paths: Path log.

    Returns:
        Problems (empty when the log proves the safety rule).
    """
    seen = paths.read_text(encoding="utf-8").splitlines()
    problems = []
    if any(p.startswith(BAND_SEARCH) for p in seen):
        problems.append(f"{BAND_SEARCH} was requested")
    if ACCOUNT_SEARCH not in seen:
        problems.append(f"no {ACCOUNT_SEARCH} request was logged (the log proves nothing)")
    print(f"fixture paths: {len(seen)} requests, {seen.count(ACCOUNT_SEARCH)} account searches, "
          f"{sum(p.startswith(BAND_SEARCH) for p in seen)} band searches")
    return problems


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        0 when every journey passed and no band search was requested, 1 otherwise.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--journeys", type=Path, default=JOURNEYS)
    parser.add_argument("--only", action="append", help="run only these journey names")
    parser.add_argument("--shots", type=Path, default=Path(tempfile.gettempdir()) / "fst-search-journeys")
    parser.add_argument("--retries", type=int, default=1)
    parser.add_argument("--axe", action="store_true", help="also run an Axe.Windows scan of the Search page")
    journey_exe.add_argument(parser)
    args = parser.parse_args(argv)
    global EXE
    EXE = args.exe
    if not EXE.is_file():
        print(f"error: build first (tools/windows/build.ps1); no {EXE}", file=sys.stderr)
        return 1
    args.shots.mkdir(parents=True, exist_ok=True)
    shots = args.shots.resolve()
    journeys = json.loads(args.journeys.read_text(encoding="utf-8"))
    selected = [j for j in journeys if not args.only or j["name"] in args.only]
    paths = shots / "fixture-paths.log"
    mock, port = start_logging_mock(shots / "fixture-service.log", paths)
    failures = 0
    try:
        for journey in selected:
            ok, detail = run_journey(journey, port, shots)
            attempts = 1
            while not ok and attempts <= args.retries:
                print(f"RETRY {journey['name']}: {detail}", flush=True)
                ok, detail = run_journey(journey, port, shots)
                attempts += 1
            failures += not ok
            verdict = "FAIL" if not ok else "FLAKY" if attempts > 1 else "PASS"
            print(f"{verdict} {journey['name']}" + (f": {detail}" if not ok else ""), flush=True)
        if args.axe and not axe_scan(port, shots):
            failures += 1
    finally:
        mock.kill()
    problems = check_paths(paths)
    for problem in problems:
        print(f"FAIL safety: {problem}")
    print(f"{len(selected) - failures}/{len(selected)} journeys passed; screenshots and path log in {shots}")
    return 1 if failures or problems else 0

# endregion


if __name__ == "__main__":
    sys.exit(main())
