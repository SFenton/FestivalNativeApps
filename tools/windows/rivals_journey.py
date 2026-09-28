"""Rivals UI journeys on Windows: state and navigation checks through uiwin.py (FlaUI driver).

Starts ``rivals_fixture.py`` (anonymized mock service) on a private loopback port, then for each scenario
launches the Debug app with an in-memory debug profile, drives it by ``fst.*`` AutomationIds and fails on the
first missing element (``waitfor:``). Scenarios cover every Rivals page state: populated hub (both tabs, Jump
To), Rival Detail -> Rivalry (sort) -> All Rivals navigation, empty lists, a 503 scrape freeze (inline and
page-level status), no selected player and the ``/compete`` deep link. With ``--shots DIR`` it also captures
compact/medium/wide screenshots of the populated journey.

Usage: ``python tools/windows/rivals_journey.py [--port 18743] [--shots DIR] [--only NAME]``
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UIWIN = ROOT / "tools" / "windows" / "uiwin.py"
EXE = ROOT / "windows" / "Festival.App" / "bin" / "x64" / "Debug" / "net9.0-windows10.0.26100.0" / "win-x64" / "FestivalScoreTracker.exe"
RIVAL = "408abb67d81446f0ac714506950ce178"

# name -> (environment, route, steps). {shot:NAME} placeholders become screenshots when --shots is given.
SCENARIOS: dict[str, tuple[dict[str, str], str | None, list[str]]] = {
    "populated": (
        {"FST_DEBUG_PROFILE": "fixture-player-1:Demo Player"},
        "/rivals",
        [
            "waitfor:id=fst.rivals.section.common@20",
            f"waitfor:id=fst.rivals.row.{RIVAL}@10",
            "{shot:hub}",
            "click:id=fst.rivals.jump",
            "waitfor:id=fst.rivals.jump.Solo_Bass",
            "click:id=fst.rivals.jump.Solo_Bass",
            "click:id=fst.rivals.tab.leaderboard",
            "waitfor:id=fst.rivals.section.Solo_Guitar@10",
            "waitfor:name=#2@10",
            "{shot:hub-leaderboard}",
            "click:id=fst.rivals.tab.song",
            "waitfor:id=fst.rivals.section.common@10",
            f"click:id=fst.rivals.row.{RIVAL}",
            "waitfor:id=fst.rival-detail.category.closest_battles@15",
            "waitfor:id=fst.rival-detail.view-profile",
            "{shot:detail}",
            "click:id=fst.rival-detail.see-all",
            "waitfor:id=fst.rivalry.list@15",
            "waitfor:id=fst.rivalry.song.fixture-pulse.Solo_Guitar",
            "expand:id=fst.rivalry.sort",
            "waitfor:name=Your Biggest Leads",
            "click:name=Your Biggest Leads",
            "waitfor:id=fst.rivalry.song.fixture-echo.Solo_Guitar",
            "{shot:rivalry}",
            "key:alt+left",
            "waitfor:id=fst.rival-detail.title@10",
            "key:alt+left",
            "waitfor:id=fst.rivals.see-all@10",
            "click:id=fst.rivals.see-all",
            "waitfor:id=fst.all-rivals.list@15",
            f"waitfor:id=fst.all-rivals.row.{RIVAL}",
            "{shot:all-rivals}",
        ],
    ),
    "empty": (
        {"FST_DEBUG_PROFILE": "fixture-player-empty:Demo Player"},
        "/rivals",
        ["waitfor:id=fst.rivals.empty@20", "{shot:empty}"],
    ),
    "freeze": (
        {"FST_DEBUG_PROFILE": "fixture-player-503:Demo Player"},
        f"/rivals/{RIVAL}?scope=song%3ASolo_Guitar",
        ["waitfor:id=fst.service-status.title@20", "waitfor:id=fst.service-status.countdown", "{shot:freeze}"],
    ),
    "no-player": (
        {"FST_DEBUG_ANONYMOUS": "1"},
        f"/rivals/{RIVAL}",
        ["waitfor:id=fst.rivals.chooseProfile@20", "waitfor:id=fst.rivals.selectPlayer", "{shot:no-player}"],
    ),
    "compete": (
        {"FST_DEBUG_PROFILE": "fixture-player-1:Demo Player"},
        "/compete",
        ["waitfor:id=fst.rivals.title@20", "waitfor:id=fst.rivals.section.common@20"],
    ),
}


def uiwin(*args: str) -> None:
    """Runs one uiwin.py command, raising on failure.

    Args:
        args: Command-line arguments after ``uiwin.py``.
    """
    result = subprocess.run([sys.executable, str(UIWIN), *args], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"uiwin {' '.join(args[:2])} failed:\n{result.stdout}\n{result.stderr}")


def expand(steps: list[str], shots: Path | None, size: str) -> list[str]:
    """Replaces ``{shot:NAME}`` placeholders.

    Args:
        steps: Scenario steps.
        shots: Screenshot directory, or ``None`` to drop shots.
        size: Window preset name used in file names.

    Returns:
        Steps ready for ``uiwin.py drive``.
    """
    out = []
    for step in steps:
        if step.startswith("{shot:"):
            if shots is not None:
                out.append(f"shot:{shots / (step[6:-1] + '-' + size + '.png')}")
            continue
        out.append(step)
    return out


def run(name: str, port: int, shots: Path | None, size: str) -> None:
    """Launches, drives and closes one scenario.

    Args:
        name: Scenario key.
        port: Fixture port.
        shots: Screenshot directory, if any.
        size: Window preset.
    """
    env, route, steps = SCENARIOS[name]
    args = ["launch", str(EXE), "--timeout", "60", "--wait", "1", "--preset", size,
            f"--arg=--base-url=http://127.0.0.1:{port}/"]
    for key, value in env.items():
        args += ["--extra", f"{key}={value}"]
    if route:
        args += ["--route", route]
    uiwin(*args)
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as handle:
            handle.write("\n".join(expand(steps, shots, size)))
        uiwin("drive", "--steps-file", handle.name)
        print(f"PASS {name} [{size}]")
    finally:
        uiwin("close")


def main() -> int:
    """Runs the selected scenarios.

    Returns:
        Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=18743)
    parser.add_argument("--shots", type=Path)
    parser.add_argument("--only", choices=sorted(SCENARIOS))
    parser.add_argument("--sizes", default="medium", help="comma-separated presets for the populated journey")
    options = parser.parse_args()
    server = subprocess.Popen([sys.executable, str(ROOT / "tools" / "windows" / "rivals_fixture.py"), "--port", str(options.port)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    failures = 0
    try:
        for _ in range(50):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{options.port}/api/publication", timeout=1)
                break
            except OSError:
                time.sleep(0.2)
        if options.shots:
            options.shots.mkdir(parents=True, exist_ok=True)
        for name in [options.only] if options.only else list(SCENARIOS):
            sizes = options.sizes.split(",") if name == "populated" else ["medium"]
            for size in sizes:
                try:
                    run(name, options.port, options.shots, size)
                except RuntimeError as error:
                    failures += 1
                    print(f"FAIL {name} [{size}]: {error}")
    finally:
        server.terminate()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
