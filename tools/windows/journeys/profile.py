#!/usr/bin/env python3
"""Profile UI journeys for the Windows app, driven through ``tools/windows/uiwin.py``.

Each journey launches the app against the loopback fixture service (``tools/mock_service.py``)
with an isolated settings file, runs UIA steps (``waitfor`` steps are the assertions) and checks
UIA tree dumps for required/forbidden AutomationIds or names. Nothing touches production or the
operator's real settings.

Usage (from the repository root, after ``tools/windows/build.ps1``)::

    python tools/windows/journeys/profile.py                 # all journeys
    python tools/windows/journeys/profile.py select history  # by name
    python tools/windows/journeys/profile.py --exe path\\to\\FestivalScoreTracker.exe --shots out\\dir

Exit code 0 when every journey passes, 1 otherwise.
"""

from __future__ import annotations

import argparse
import os
import socket
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
UIWIN = REPO / "tools" / "windows" / "uiwin.py"
DEFAULT_EXE = (REPO / "windows" / "Festival.App" / "bin" / "x64" / "Debug" / "net9.0-windows10.0.26100.0"
               / "win-x64" / "FestivalScoreTracker.exe")

# region Model


@dataclass
class Journey:
    """One scripted journey.

    Attributes:
        name: Short CLI name.
        launch: Extra ``uiwin.py launch`` arguments (route, tab, profile).
        steps: Drive phases; each is a list of step strings run in one ``drive`` call.
        expect: Per phase, substrings that must appear in the tree dumped after it.
        forbid: Per phase, substrings that must not appear in that tree.
        relaunch: Phase index after which the app is closed and relaunched with ``relaunch_args``.
        relaunch_args: Launch arguments for the relaunch.
    """

    name: str
    launch: list[str]
    steps: list[list[str]]
    expect: list[list[str]] = field(default_factory=list)
    forbid: list[list[str]] = field(default_factory=list)
    relaunch: int | None = None
    relaunch_args: list[str] = field(default_factory=list)


def _profile(value: str) -> list[str]:
    """Launch arguments selecting a fixture player in memory only."""
    return ["--arg=--profile", f"--arg={value}"]


ANONYMOUS = ["--arg=--anonymous"]

JOURNEYS = [
    Journey(
        name="select",
        launch=["--tab", "songs", *ANONYMOUS],
        steps=[
            ["invoke:id=fst.shell.profile", "waitfor:id=fst.profile.search@5", "type:Fixture",
             "waitfor:name=Fixture Player 2@10", "click:name=Fixture Player 2",
             "waitfor:id=fst.player.name@15", "waitfor:id=fst.player.select@10"],
            ["invoke:id=fst.player.select", "waitfor:id=fst.player.deselect@10", "waitfor:id=fst.nav.statistics@10"],
            ["click:id=fst.nav.statistics", "waitfor:id=fst.statistics@10", "waitfor:id=fst.player.deselect@15",
             "waitfor:id=fst.player.overview@15", "wait:5"],
            ["invoke:id=fst.player.deselect", "waitfor:id=PrimaryButton@10", "invoke:id=PrimaryButton", "wait:2"],
        ],
        expect=[
            ["fst.player.select", "Public Profile", "fst.player.bands-link"],
            ["This Is Me", "fst.nav.statistics", "fst.nav.rivals"],
            ["fst.statistics", "fst.player.overview", "fst.player.instrument.Solo_Guitar",
             "fst.player.rank-history.Solo_Guitar", "fst.player.percentiles.Solo_Guitar"],
            ["fst.nav.songs"],
        ],
        forbid=[[], ["fst.player.select"], [], ["fst.nav.statistics", "fst.nav.rivals"]],
    ),
    Journey(
        name="restart",
        launch=["--route", "/player/fixture-player-1"],
        steps=[
            ["waitfor:id=fst.player.select@15", "invoke:id=fst.player.select", "waitfor:id=fst.player.deselect@10"],
            ["waitfor:id=fst.nav.statistics@15", "click:id=fst.nav.statistics", "waitfor:id=fst.player.deselect@15"],
        ],
        expect=[["This Is Me"], ["Fixture Player 1", "This Is Me"]],
        relaunch=0,
        relaunch_args=["--tab", "statistics"],
    ),
    Journey(
        name="history",
        launch=["--route", "/songs/fixture-pulse/Solo_Guitar/history", *_profile("fixture-player-1:Fixture Player 1")],
        steps=[
            ["waitfor:id=fst.history.rows@15", "waitfor:id=fst.history.chart@5"],
            ["invoke:id=fst.history.sort.open", "waitfor:id=fst.history.sort.mode.date@5",
             "invoke:id=fst.history.sort.mode.date", "wait:1"],
        ],
        expect=[["Sort by Score, descending", "personal best"], ["Sort by Date, descending"]],
    ),
    Journey(
        name="history-syncing",
        launch=["--route", "/songs/fixture-pulse/Solo_Guitar/history", *_profile("fixture-syncing:Syncing Player")],
        steps=[["waitfor:id=fst.history.message@15"]],
        expect=[["Still Syncing"]],
        forbid=[["fst.history.rows"]],
    ),
    Journey(
        name="history-anonymous",
        launch=["--route", "/songs/fixture-pulse/Solo_Guitar/history", *ANONYMOUS],
        steps=[["waitfor:id=fst.history.message@15"]],
        expect=[["No Player Selected"]],
    ),
    Journey(
        name="syncing",
        launch=["--route", "/player/fixture-syncing", *ANONYMOUS],
        steps=[["waitfor:id=fst.player.syncing@15"]],
        expect=[["Scores Are Syncing"]],
        forbid=[["fst.player.select"]],
    ),
    Journey(
        name="bands-scope",
        launch=["--tab", "songs", *ANONYMOUS],
        steps=[["invoke:id=fst.shell.profile", "waitfor:id=fst.profile.scope.bands@5",
                "click:id=fst.profile.scope.bands", "wait:1"]],
        expect=[["Find Band", "Band search isn"]],
        forbid=[["fst.profile.retry"]],
    ),
]

# endregion

# region Runner


def _uiwin(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    """Run ``uiwin.py`` and return the completed process."""
    env = {**os.environ, "PYTHONIOENCODING": "utf-8", "MSYS_NO_PATHCONV": "1"}
    result = subprocess.run([sys.executable, str(UIWIN), *args], capture_output=True, text=True,
                            encoding="utf-8", env=env)
    if check and result.returncode != 0:
        raise RuntimeError(f"uiwin {args[0]} failed: {result.stderr.strip() or result.stdout.strip()}")
    return result


def _free_port() -> int:
    """Pick a free loopback port for the fixture service."""
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def _app_args(extra: list[str]) -> list[str]:
    """Turn ``--route``/``--tab`` into app arguments (Release/AOT builds ignore the FST_DEBUG_* environment)."""
    result: list[str] = []
    items = iter(extra)
    for item in items:
        if item in ("--route", "--tab"):
            result += [f"--arg={item}", f"--arg={next(items)}"]
        else:
            result.append(item)
    return result


def _launch(exe: Path, base: str, settings: Path, extra: list[str]) -> int:
    """Launch the app and return its pid."""
    out = _uiwin("launch", str(exe), "--arg=--base-url", f"--arg={base}", "--arg=--settings-path",
                 f"--arg={settings}", "--preset", "medium", *_app_args(extra)).stdout
    for line in out.splitlines():
        if '"pid"' in line:
            return int(line.split(":")[1].strip().rstrip(","))
    raise RuntimeError(f"no pid in launch output: {out}")


def run(journey: Journey, exe: Path, shots: Path | None) -> list[str]:
    """Run one journey and return failure messages (empty when it passed)."""
    failures: list[str] = []
    port = _free_port()
    mock = subprocess.Popen([sys.executable, str(REPO / "tools" / "mock_service.py"), "--port", str(port)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    work = Path(tempfile.mkdtemp(prefix=f"fst-journey-{journey.name}-"))
    settings = work / "settings.json"
    pid = None
    try:
        time.sleep(1.0)
        base = f"http://127.0.0.1:{port}/"
        pid = _launch(exe, base, settings, journey.launch)
        for index, phase in enumerate(journey.steps):
            tree = work / f"tree-{index}.txt"
            steps = [*phase, f"tree:{tree}"]
            if shots is not None:
                steps.append(f"shot:{shots / f'{journey.name}-{index}.png'}")
            result = _uiwin("drive", "--pid", str(pid), "--steps", "; ".join(steps), check=False)
            if result.returncode != 0:
                failures.append(f"phase {index}: {result.stderr.strip() or result.stdout.strip()}")
                break
            text = tree.read_text(encoding="utf-8", errors="replace") if tree.exists() else ""
            for needle in journey.expect[index] if index < len(journey.expect) else []:
                if needle not in text:
                    failures.append(f"phase {index}: expected {needle!r} in the UIA tree")
            for needle in journey.forbid[index] if index < len(journey.forbid) else []:
                if needle in text:
                    failures.append(f"phase {index}: did not expect {needle!r} in the UIA tree")
            if journey.relaunch == index:
                _uiwin("close", "--pid", str(pid), check=False)
                pid = _launch(exe, base, settings, journey.relaunch_args)
    except RuntimeError as error:
        failures.append(str(error))
    finally:
        if pid is not None:
            _uiwin("close", "--pid", str(pid), check=False)
        mock.terminate()
    return failures


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        0 when all selected journeys pass, else 1.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*", help="journeys to run (default: all)")
    parser.add_argument("--exe", type=Path, default=DEFAULT_EXE)
    parser.add_argument("--shots", type=Path, help="directory for per-phase screenshots")
    args = parser.parse_args(argv)
    selected = [j for j in JOURNEYS if not args.names or j.name in args.names]
    if args.shots:
        args.shots.mkdir(parents=True, exist_ok=True)
    failed = 0
    for journey in selected:
        failures = run(journey, args.exe.resolve(), args.shots.resolve() if args.shots else None)
        print(f"{'PASS' if not failures else 'FAIL'} {journey.name}")
        for failure in failures:
            print(f"  - {failure}")
        failed += bool(failures)
    print(f"{len(selected) - failed}/{len(selected)} journeys passed")
    return 1 if failed else 0

# endregion


if __name__ == "__main__":
    sys.exit(main())
