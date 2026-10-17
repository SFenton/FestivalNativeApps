"""Reflow motion journeys on Windows (issue #669, pattern ``reflow-motion``).

Each scenario launches the Debug app against a loopback fixture with ``--perf-log``, drives it through ``uiwin.py``
and judges the ``split-*`` and ``reflow-move`` lines each phase appended (``reflow_trace.py``). Opening a split pane
must narrow the list frame by frame while the pane fades in, and closing must widen it while the pane fades out
(``OnDemandSplitHost``); resizing across a column threshold must glide the loaded cards to their new places
(``ReflowMotion``) without replaying a load stagger. The ``*-reduced`` scenarios launch with ``--reduce-motion`` and
require the same changes to happen instantly.

=========================  ==========================================================================================
Scenario                   Reflow
=========================  ==========================================================================================
``rivals-split``           Rivals: open a rival in the split pane, then close it (Close button)
``suggestions-columns``    Suggestions: wide (two columns) → medium (one) → wide
``statistics-columns``     Profile instrument sections (``LeaderboardsCardGridLayout``): wide → medium → wide
``shop-grid``              Item Shop grid: wide → medium → wide
``rivals-split-reduced``   Rivals split under Reduce Motion
``suggestions-reduced``    Suggestions columns under Reduce Motion
``shop-grid-reduced``      Item Shop grid under Reduce Motion
=========================  ==========================================================================================

Focus, reading order and target sizes for the same surfaces live in ``tools/windows/journeys/a11y-reflow.json``
(``a11y_matrix.py``).

Usage: ``python tools/windows/reflow_journey.py [--only NAME]`` (build first with ``tools/windows/build.ps1``).
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))

import journey_exe  # noqa: E402  (sibling module)
import reflow_trace  # noqa: E402  (sibling module)
import ui_journey  # noqa: E402  (sibling module)

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools" / "windows"
UIWIN = TOOLS / "uiwin.py"
WORK = Path(tempfile.gettempdir()) / "fst-reflow-journey"
SETTLE_STEP = "wait:1"
"""Appended to each phase: a move lasts 300 ms, so its frames and settle are logged by then."""
QUIET = "wait:0.8"
"""Follows each trigger before any UIA poll: a cross-process tree walk blocks the app's UI thread for 50-65 ms,
which drops frames mid-move and makes the trace step."""

Check = Callable[[list[reflow_trace.Event]], list[str]]


@dataclass(frozen=True)
class Phase:
    """One drive and the check of the reflow lines it appended."""

    label: str
    steps: list[str]
    check: Check = lambda events: []


@dataclass(frozen=True)
class Scenario:
    """One launch of the app and its phases."""

    fixture: tuple[str, ...]
    phases: list[Phase]
    route: str | None = None
    profile: str | None = None
    preset: str = "wide"
    args: tuple[str, ...] = ()
    env: dict[str, str] = field(default_factory=dict)


def both(*checks: Check) -> Check:
    """All of ``checks``."""
    return lambda events: [problem for check in checks for problem in check(events)]


def split(opening: bool, reduced: bool) -> Check:
    """An animated (or, reduced, instant) split open or close."""
    if reduced:
        return lambda events: reflow_trace.check_split_instant(events, opening)
    return lambda events: reflow_trace.check_split(events, opening)


def columns(host: str, reduced: bool) -> Check:
    """A column change of ``host`` that glides (or, reduced, snaps) and replays no load stagger."""
    moved = (lambda events: reflow_trace.check_reflow_instant(events, host)) if reduced \
        else (lambda events: reflow_trace.check_reflow(events, host))
    return both(moved, reflow_trace.check_no_restagger)


RIVAL = "fst.rivals.row.f1c749eb07c32578cfa3e59ec38c03a8"
SUGGESTIONS_READY = ["waitfor:id=fst.suggestions.row.s044|Solo_PeripheralGuitar@30", "wait:1.5"]
STATISTICS_READY = ["waitfor:id=fst.player.stat.overview.songs-played@30",
                    "scrollinto:id=fst.player.instrument.Solo_Guitar@20", "wait:1.5"]
SHOP_READY = ["waitfor:id=fst.shop.song.fixture-pulse@20", "wait:2"]


def rivals(reduced: bool) -> Scenario:
    """Rivals split pane open and close."""
    return Scenario(("rivals_fixture.py",), [
        Phase("ready", [f"waitfor:id={RIVAL}@20", "wait:1"]),
        Phase("open", [f"invoke:id={RIVAL}", QUIET, "waitfor:id=fst.rival-detail.title@20",
                       "waitfor:id=fst.rivals.title@5"], split(True, reduced)),
        Phase("close", ["invoke:id=fst.split.close", QUIET, "waitgone:id=fst.split.pane@5",
                        "waitfor:id=fst.rivals.title@5", f"assertfocus:id={RIVAL}@3"], split(False, reduced)),
    ], route="/rivals", profile="fixture-player-1:Demo Player", args=("--reduce-motion",) if reduced else ())


def resized(host: str, ready: list[str], reduced: bool, back: list[str]) -> list[Phase]:
    """Wide → medium → wide, each a column change of ``host``; ``back`` re-checks the wide content."""
    return [
        Phase("ready", ready),
        Phase("narrow", ["resize:medium", QUIET], columns(host, reduced)),
        Phase("widen", ["resize:wide", QUIET, *back], columns(host, reduced)),
    ]


def suggestions(reduced: bool) -> Scenario:
    """Suggestions cards between two columns and one."""
    return Scenario(("suggestions_fixture_server.py",), resized("suggestions", SUGGESTIONS_READY, reduced, [
        "waitfor:id=fst.suggestions.row.s044|Solo_PeripheralGuitar@10"]),
        route="/suggestions", profile="fixture-suggest:Fixture Player", env={"FST_DEBUG_SUGGESTIONS_SEED": "1"},
        args=("--reduce-motion",) if reduced else ())


def shop(reduced: bool) -> Scenario:
    """Item Shop grid between five columns and fewer."""
    return Scenario(("rivals_fixture.py",), resized("shop-grid", SHOP_READY, reduced, [
        "waitfor:id=fst.shop.song.fixture-pulse@10"]), route="/shop", args=("--reduce-motion",) if reduced else ())


SCENARIOS = {
    "rivals-split": rivals(reduced=False),
    "suggestions-columns": suggestions(reduced=False),
    "statistics-columns": Scenario(("rivals_fixture.py",), resized("card-grid", STATISTICS_READY, False, [
        "waitfor:id=fst.player.instrument.Solo_Guitar@10"]), route="/statistics",
        profile="fixture-player-1:Demo Player"),
    "shop-grid": shop(reduced=False),
    "rivals-split-reduced": rivals(reduced=True),
    "suggestions-reduced": suggestions(reduced=True),
    "shop-grid-reduced": shop(reduced=True),
}
"""Scenarios by name."""


def uiwin(*args: str) -> str:
    """Runs one uiwin.py command, raising on failure."""
    result = subprocess.run([sys.executable, str(UIWIN), *args], capture_output=True, text=True, encoding="utf-8",
                            errors="replace")
    if result.returncode != 0:
        raise RuntimeError(f"uiwin {' '.join(args[:2])} failed:\n{result.stdout}\n{result.stderr}")
    return result.stdout


def drive(steps: list[str]) -> str:
    """Drives the launched app through ``steps``."""
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as handle:
        handle.write("\n".join(steps))
    try:
        return uiwin("drive", "--steps-file", handle.name)
    finally:
        Path(handle.name).unlink(missing_ok=True)


def read_lines(log: Path) -> list[str]:
    """The perf log's lines (none when the app has not written it yet)."""
    try:
        return log.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return []


def run_phases(log: Path, phases: list[Phase]) -> list[str]:
    """Drive each phase and judge the reflow lines it appended (printed with each phase)."""
    failures: list[str] = []
    mark = len(read_lines(log))
    for phase in phases:
        drive([*phase.steps, SETTLE_STEP])
        lines = read_lines(log)
        events = reflow_trace.parse(lines[mark:])
        mark = len(lines)
        found = phase.check(events)
        print(f"  {phase.label}: {len(events)} reflow line(s)")
        for event in events:
            print(f"    {event.kind} {event.values}")
        failures += [f"{phase.label}: {failure}" for failure in found]
    return failures


def launch_args(name: str, port: int, exe: Path) -> list[str]:
    """Builds the ``uiwin.py launch`` arguments for a scenario."""
    scenario = SCENARIOS[name]
    data = WORK / name
    shutil.rmtree(data, ignore_errors=True)
    data.mkdir(parents=True)
    args = ["launch", str(exe), "--timeout", "60", "--wait", "1", "--preset", scenario.preset,
            f"--arg=--base-url=http://127.0.0.1:{port}/", "--arg=--first-run=off",
            f"--arg=--settings-path={data / 'settings.json'}", "--extra", f"FST_DEBUG_DATA_DIR={data}",
            f"--arg=--perf-log={data / 'perf.log'}"]
    if scenario.route:
        args += ["--route", scenario.route]
    if scenario.profile:
        args.append(f"--arg=--profile={scenario.profile}")
    args += [f"--arg={arg}" for arg in scenario.args]
    for key, value in scenario.env.items():
        args += ["--extra", f"{key}={value}"]
    return args


def run(name: str, exe: Path) -> list[str]:
    """Starts the scenario's fixture, then launches, drives and closes the app."""
    scenario = SCENARIOS[name]
    WORK.mkdir(parents=True, exist_ok=True)
    script, *flags = scenario.fixture
    server, port = ui_journey.start_mock(WORK / f"{name}-service.log", tuple(flags), TOOLS / script)
    try:
        uiwin(*launch_args(name, port, exe))
        try:
            failures = run_phases(WORK / name / "perf.log", scenario.phases)
        except RuntimeError as error:
            failures = [str(error)]
        if failures:
            for command, suffix in (("shot", ".png"), ("tree", ".txt")):
                try:
                    uiwin(command, str(WORK / name / f"FAILED{suffix}"))
                except RuntimeError:
                    pass
        uiwin("close")
    finally:
        server.terminate()
    return failures


def run_with_retries(name: str, exe: Path, retries: int) -> list[str]:
    """Runs a scenario, relaunching it after a failure up to ``retries`` times; returns the last attempt's failures.

    Same policy as ``accordion_journey.py``: a hosted runner occasionally stalls the UI thread mid-move. Each attempt
    is judged in full, so a real regression still fails every attempt.
    """
    failures = run(name, exe)
    for attempt in range(1, retries + 1):
        if not failures:
            break
        print(f"RETRY {name} ({attempt}/{retries}) after:\n  " + "\n  ".join(failures))
        failures = run(name, exe)
    return failures


def main() -> int:
    """Runs the selected scenarios one app at a time."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", choices=sorted(SCENARIOS), action="append")
    parser.add_argument("--retries", type=int, default=0,
                        help="relaunch a failed scenario up to this many times (ci_ui.py passes its --retries)")
    journey_exe.add_argument(parser)
    options = parser.parse_args()
    failed = 0
    for name in options.only or list(SCENARIOS):
        print(f"{name}:")
        failures = run_with_retries(name, options.exe, options.retries)
        if failures:
            failed += 1
            print(f"FAIL {name}:\n  " + "\n  ".join(failures))
        else:
            print(f"PASS {name}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
