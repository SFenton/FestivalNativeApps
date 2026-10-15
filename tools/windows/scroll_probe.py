#!/usr/bin/env python3
"""Wheel-like scroll smoothness probe for Windows pages (issue #642).

Launches the app once per page with ``--scroll-probe`` against the fixture service, lets the app scroll the page's
main scroller in animated wheel-notch steps (down then up, three cycles) and prints the per-pass ``scroll-probe`` lines
from the perf log: UI-thread frame intervals, offset smoothness and the UI-thread time of per-scroll handlers.
``reversals`` counts frames whose offset moved against the scroll, ``over33`` frame stalls of 33 ms or more, and
``handlers`` the summed handler time per pass (about two seconds) and ``gc2`` the full collections in a pass. A smooth
page reports no reversals, at most an occasional stall, a few milliseconds of handlers and almost no gen2 collections
once loaded: per-frame WinRT objects (event args, ``TransformToVisual``) add GC memory pressure that induces blocking
gen2 collections of 10-40 ms (#642). Programmatic animated scrolling uses the same ScrollViewer animation path as a
wheel notch, so it works on a locked console where real wheel input is denied.

Usage: python tools/windows/scroll_probe.py [--exe PATH] [--pages songs,song-detail,...] [--max-reversals 0]
       [--max-stalls 3] [--max-handler-ms 60] [--max-gc2 3]
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import uiwin  # noqa: E402  (sibling tool; provides the lock and driver)

ROOT = Path(__file__).resolve().parents[2]
PROFILE = "fixture-player-1:Fixture Player 1"
PAGES = {
    "songs": "/songs",
    "song-detail": "/songs/fixture-pulse",
    "leaderboards": "/leaderboards",
    "statistics": "/statistics",
    "suggestions": "/suggestions",
}
LINE = re.compile(r"scroll-probe (down|up) .*")


def run_page(exe: Path, name: str, route: str, port: int, folder: Path, extra_env: list[str],
             extra_args: list[str]) -> list[str]:
    """Launches one page with the probe and returns its pass lines.

    Args:
        exe: App executable.
        name: Page label.
        route: Route to open.
        port: Fixture service port.
        folder: Scratch folder for settings, data and the perf log.
        extra_env: Additional ``KEY=VALUE`` launch environment entries.
        extra_args: Additional app arguments (e.g. ``--no-art`` for an A/B run).

    Returns:
        The perf log's ``scroll-probe`` lines.
    """
    log = folder / f"probe-{name}.log"
    log.unlink(missing_ok=True)
    env = uiwin.launch_env(None, route, [f"FST_SETTINGS_PATH={folder / 'settings.json'}",
                                         f"FST_DEBUG_DATA_DIR={folder / 'data'}", f"FST_DEBUG_PROFILE={PROFILE}",
                                         *extra_env])
    uiwin.prepare_automation(exe, env)
    args = [f"--perf-log={log}", "--scroll-probe", "--whats-new", "off", f"--base-url=http://127.0.0.1:{port}/",
            *extra_args]
    lock = uiwin.HostLock("desktop", purpose=f"scroll probe {name} [{ROOT.name}]", hold_seconds=180, wait_seconds=1800)
    with lock:
        pid = uiwin.run_driver({"command": "launch", "exe": str(exe), "args": args, "env": env, "timeout": 60},
                               lock)["pid"]
        try:
            uiwin.run_driver({"command": "resize", "pid": pid, "op": uiwin.preset_op("medium")}, lock)
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
                if "scroll-probe done" in text or "scroll-probe none" in text:
                    break
                time.sleep(1)
        finally:
            uiwin.run_driver({"command": "close", "pid": pid}, lock)
    text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
    return [line for line in text.splitlines() if "scroll-probe" in line]


def main() -> int:
    """Runs the probe on the requested pages and fails on reversals, stalls or handler time above the limits."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--exe", type=Path, default=ROOT / "windows" / ".artifacts" / "app" / "Release" / "FestivalScoreTracker.exe")
    parser.add_argument("--pages", default=",".join(PAGES))
    parser.add_argument("--port", type=int, default=18764)
    parser.add_argument("--max-reversals", type=int, default=0)
    parser.add_argument("--max-stalls", type=int, default=3, help="frames of 33 ms or more allowed per pass")
    parser.add_argument("--max-handler-ms", type=float, default=60,
                        help="per-scroll handler time allowed per pass (one gen2 inside a handler adds 10-25 ms)")
    parser.add_argument("--max-gc2", type=int, default=3,
                        help="gen2 collections allowed per page over the moving passes after the first (load settles)")
    parser.add_argument("--env", action="append", default=[], help="extra KEY=VALUE launch environment")
    parser.add_argument("--arg", action="append", default=[], help="extra app argument, e.g. --arg=--no-art")
    options = parser.parse_args()
    server = subprocess.Popen([sys.executable, str(ROOT / "tools" / "mock_service.py"), "--port", str(options.port),
                               "--large-catalogue"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    failures: list[str] = []
    try:
        for _ in range(50):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{options.port}/api/publication", timeout=1)
                break
            except OSError:
                time.sleep(0.2)
        with tempfile.TemporaryDirectory(prefix="fst-scroll-probe-") as scratch:
            for name in options.pages.split(","):
                lines = run_page(options.exe, name, PAGES[name], options.port, Path(scratch), options.env,
                                 options.arg)
                print(f"== {name}")
                for line in lines:
                    print("   " + line[line.index("scroll-probe"):])
                passes = [line for line in lines if LINE.search(line)]
                if not passes:
                    failures.append(f"{name}: no probe passes")
                for line in passes:
                    reversals = int(re.search(r"reversals=(\d+)", line).group(1))
                    stalls = int(re.search(r"over33=(\d+)", line).group(1))
                    if reversals > options.max_reversals or stalls > options.max_stalls:
                        failures.append(f"{name}: {LINE.search(line).group(0)}")
                gc2 = [int(m.group(1)) for line in lines
                       if (m := re.search(r"scroll-probe gc (?:down|up) .*\bgc2=(\d+)", line))]
                if sum(gc2[1:]) > options.max_gc2:
                    failures.append(f"{name}: {sum(gc2[1:])} gen2 collections after the first pass")
                for line in lines:
                    if cost := re.search(r"scroll-probe cost (\w+) handlers=([\d.]+)ms", line):
                        if float(cost.group(2)) > options.max_handler_ms:
                            failures.append(f"{name}: {line[line.index('scroll-probe'):]}")
    finally:
        server.terminate()
    for failure in failures:
        print("FAIL " + failure)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
