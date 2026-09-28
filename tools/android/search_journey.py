#!/usr/bin/env python3
"""Global search + adaptive shell journeys on the FST emulator matrix (fixture mode).

Starts ``tools/mock_service.py`` on a free loopback port with a request-*path* log (no
query strings, so no search text), then runs one ``device.py drive`` hold per journey:
install the debug APK, cold-start against ``FST_ORIGIN=http://10.0.2.2:<port>`` (the
emulator's alias for the host loopback), and step through search on that form factor
and posture, screenshotting each state. Afterwards the path log must contain at least
one ``/api/account/search`` and **no** ``/api/bands/search`` (the service's band search
GET can write; see ``.agents/platforms/service-safety.md``).

Usage::

    python tools/android/search_journey.py                      # every journey
    python tools/android/search_journey.py phone book-fold      # a subset
    python tools/android/search_journey.py --list
    python tools/android/search_journey.py --out <dir> --apk <app-debug.apk>

Fixture screenshots contain only synthetic data (``contracts/fixtures``), so small ones
may be committed under ``android/reports/screenshots/``.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DEVICE = REPO / "tools" / "android" / "device.py"
MOCK_DIR = REPO / "tools"
DEFAULT_APK = REPO / "android" / "app" / "build" / "outputs" / "apk" / "debug" / "app-debug.apk"
DEFAULT_OUT = Path.home() / "workspace" / "showcase" / "and-shell-search" / "fixture"
ACCOUNT_SEARCH = "/api/account/search"
BAND_SEARCH = "/api/bands/search"

# region Journeys


@dataclass(frozen=True)
class Journey:
    """One emulator hold.

    Attributes:
        name: CLI name and screenshot prefix.
        avd: FST AVD.
        steps: ``device.py drive`` steps; ``{out}`` expands to the screenshot prefix.
        posture: Posture applied before launch.
        extras: Additional ``KEY=VALUE`` launch extras.
    """

    name: str
    avd: str
    steps: str
    posture: str | None = None
    extras: tuple[str, ...] = ()


OPEN = "tap:id=fst.global-search.open; waitfor:id=fst.global-search.field@10"
SONGS = "waitfor:id=fst.songs.list@40"

JOURNEYS = [
    Journey("phone", "FST_Phone", f"""
        {SONGS}; wait:2; shot:{{out}}-songs.png
        {OPEN}; wait:1; shot:{{out}}-search-hint.png
        type:fixture; wait:3; shot:{{out}}-search-results.png
        tap:id=fst.global-search.scope.players; wait:1; shot:{{out}}-search-players.png
        tap:id=fst.global-search.scope.bands; wait:1; shot:{{out}}-search-bands.png
        tap:id=fst.global-search.scope.bands; wait:1
        tap:id=fst.global-search.result.song; waitfor:id=fst.song-detail.intensity@20; wait:1; shot:{{out}}-song-detail.png
        {OPEN}; type:busy; wait:3; shot:{{out}}-search-players-error.png
        back; wait:1; back; wait:1; shot:{{out}}-back.png
        tap:id=fst.nav.drawer; wait:1; shot:{{out}}-drawer.png
    """),
    Journey("book-fold", "FST_Book_Fold", f"""
        {SONGS}; wait:2; shot:{{out}}-unfolded.png
        {OPEN}; type:fixture; wait:3; shot:{{out}}-unfolded-search.png
        posture:half; wait:3; shot:{{out}}-book-search.png
        rotate:90; wait:4; shot:{{out}}-tabletop-search.png
        rotate:0; wait:3; posture:folded; wait:4; shot:{{out}}-folded-search.png
        back; wait:1; shot:{{out}}-folded.png
    """, posture="unfolded"),
    Journey("passport-fold", "FST_Passport_Fold", f"""
        {SONGS}; wait:2; shot:{{out}}-unfolded.png
        {OPEN}; type:fixture; wait:3; shot:{{out}}-unfolded-search.png
        posture:folded; wait:4; shot:{{out}}-folded-search.png
        back; wait:1; shot:{{out}}-folded.png
    """, posture="unfolded"),
    Journey("trifold", "FST_TriFold", f"""
        {SONGS}; wait:2; shot:{{out}}-folded.png
        {OPEN}; type:fixture; wait:3; shot:{{out}}-folded-search.png
        posture:partial; wait:4; shot:{{out}}-partial-search.png
        posture:unfolded; wait:4; shot:{{out}}-unfolded-search.png
        back; wait:1; shot:{{out}}-unfolded.png
    """, posture="folded"),
    Journey("tablet", "FST_Tablet", f"""
        {SONGS}; wait:2; shot:{{out}}-landscape.png
        {OPEN}; type:fixture; wait:3; shot:{{out}}-landscape-search.png
        rotate:90; wait:4; shot:{{out}}-portrait-search.png
        back; wait:1; shot:{{out}}-portrait.png
    """),
    Journey("resizable", "FST_Resizable", f"""
        {SONGS}; wait:2; shot:{{out}}-phone.png
        {OPEN}; type:fixture; wait:3; shot:{{out}}-phone-search.png
        resize:tablet; wait:4; shot:{{out}}-tablet-search.png
        resize:desktop; wait:4; shot:{{out}}-desktop-search.png
        back; wait:1; shot:{{out}}-desktop.png
        resize:phone; wait:3
    """),
    Journey("profile", "FST_Phone", f"""
        {SONGS}; wait:2; shot:{{out}}-tabs.png
        {OPEN}; type:fixture; wait:3; shot:{{out}}-search.png
    """, extras=("FST_DEBUG_PROFILE=00000000000000000000000000000f01:FixturePlayer",)),
]

# endregion

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
        # The shared fixture's account IDs (`fixture-player-1`) are not 32-hex Epic IDs, which the
        # Android client rejects; remap search rows to synthetic hex IDs for these journeys only.
        "original_json = m.FixtureHandler._json\n"
        "def hex_json(self, status, payload, *a, **k):\n"
        "    if self.path.startswith('/api/account/search') and isinstance(payload, dict):\n"
        "        for i, row in enumerate(payload.get('results', [])):\n"
        "            row['accountId'] = format(0xf00 + i + 1, '032x')\n"
        "    return original_json(self, status, payload, *a, **k)\n"
        "m.FixtureHandler._json = hex_json\n"
        "m.FixtureHandler.log_request = log_request; m.FixtureServer.request_queue_size = 128; "
        "sys.argv = ['mock_service', '--port', '0']; m.main()")
    proc = subprocess.Popen([sys.executable, "-u", "-c", bootstrap, str(MOCK_DIR), str(paths)],
                            stdout=handle, stderr=subprocess.STDOUT)
    for _ in range(200):
        match = re.search(r"127\.0\.0\.1:(\d+)", log.read_text(encoding="utf-8", errors="replace"))
        if match:
            return proc, int(match.group(1))
        time.sleep(0.1)
    proc.kill()
    raise RuntimeError(f"fixture service did not start; see {log}")


def check_paths(paths: Path) -> list[str]:
    """Check the request-path log.

    Args:
        paths: Path log.

    Returns:
        Problems (empty when the log proves the safety rule).
    """
    seen = paths.read_text(encoding="utf-8").splitlines()
    problems = []
    if BAND_SEARCH in seen or any(p.startswith(BAND_SEARCH) for p in seen):
        problems.append(f"{BAND_SEARCH} was requested")
    if ACCOUNT_SEARCH not in seen:
        problems.append(f"no {ACCOUNT_SEARCH} request was logged (the log proves nothing)")
    print(f"fixture paths: {len(seen)} requests, {seen.count(ACCOUNT_SEARCH)} account searches, "
          f"{sum(p.startswith(BAND_SEARCH) for p in seen)} band searches")
    return problems

# endregion

# region Runner


def steps_for(journey: Journey, out: Path) -> str:
    """Expand a journey's steps.

    Args:
        journey: Journey.
        out: Screenshot directory.

    Returns:
        ``;``-separated drive steps.
    """
    prefix = (out / journey.name).as_posix()
    lines = [line.strip() for line in journey.steps.format(out=prefix).splitlines()]
    return "; ".join(line for line in lines if line)


def run(journey: Journey, out: Path, apk: Path, port: int) -> int:
    """Run one journey in one lock hold.

    Args:
        journey: Journey.
        out: Screenshot directory.
        apk: Debug APK.
        port: Fixture port.

    Returns:
        ``device.py`` exit code.
    """
    cmd = [sys.executable, str(DEVICE), "drive", "--avd", journey.avd, "--apk", str(apk), "--launch", "--wait", "3",
           "--extra", f"FST_ORIGIN=http://10.0.2.2:{port}", "--extra", "FST_DEBUG_STILL_BACKGROUND=1",
           "--steps", steps_for(journey, out)]
    for extra in journey.extras:
        cmd += ["--extra", extra]
    if journey.posture:
        cmd += ["--posture", journey.posture]
    print(f"== {journey.name} ({journey.avd})", flush=True)
    return subprocess.call(cmd)


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments.

    Returns:
        0 when every journey passed and the path log proves no band search.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("journeys", nargs="*", help="journey names (default: all)")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--apk", type=Path, default=DEFAULT_APK)
    args = parser.parse_args(argv)
    if args.list:
        for journey in JOURNEYS:
            print(f"{journey.name:14} {journey.avd}")
        return 0
    names = {j.name for j in JOURNEYS}
    unknown = [n for n in args.journeys if n not in names]
    if unknown:
        parser.error(f"unknown journeys: {', '.join(unknown)}")
    selected = [j for j in JOURNEYS if not args.journeys or j.name in args.journeys]
    args.out.mkdir(parents=True, exist_ok=True)
    paths = args.out / "fixture-paths.log"
    mock, port = start_logging_mock(args.out / "fixture-service.log", paths)
    failures = 0
    try:
        for journey in selected:
            if run(journey, args.out, args.apk, port) != 0:
                failures += 1
                print(f"FAILED: {journey.name}", flush=True)
    finally:
        mock.terminate()
    problems = check_paths(paths)
    for problem in problems:
        print(f"SAFETY: {problem}")
    print(f"{len(selected) - failures}/{len(selected)} journeys passed; screenshots and path log in {args.out}")
    return 1 if failures or problems else 0


if __name__ == "__main__":
    sys.exit(main())

# endregion
