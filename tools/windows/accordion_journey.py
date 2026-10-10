"""Accordion choreography journeys on Windows (issue #561, pattern ``load-transition`` R10).

Each scenario launches the Debug app against a loopback fixture with ``--perf-log``, drives it through ``uiwin.py``
and judges the ``accordion-*`` lines each phase appended (``accordion_trace.py``): every rendered frame of a move
must show the owner's sequence, opening = grow with the content hidden, then fade in at full height; closing = fade
out at full height, then collapse; each 150 ms phase with frames inside it. The ``*-reduced`` scenarios launch with
``--reduce-motion`` and require an instant settle with no move or frame.

=====================  =================================================================================================
Scenario               Accordion (mover path)
=====================  =================================================================================================
``songs-year``         Songs Filter, Year (the implicit ``Expander`` style's ``Accordion.Sequenced``)
``suggestions``        Suggestions Filter, Instrument-Specific (``InstrumentSelector`` details)
``settings-leeway``    Settings, Filter Invalid Scores → leeway slider (``Accordion.Open`` panel)
``songs-year-reduced`` Songs Filter, Year under Reduce Motion
``settings-reduced``   Settings leeway panel under Reduce Motion
=====================  =================================================================================================

The UIA state, reading order and target-size checks for the same accordions live in
``tools/windows/journeys/a11y-accordion.json`` (``a11y_matrix.py``).

Usage: ``python tools/windows/accordion_journey.py [--only NAME]`` (build first with ``tools/windows/build.ps1``).
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

import accordion_trace  # noqa: E402  (sibling module)
import journey_exe  # noqa: E402  (sibling module)
import ui_journey  # noqa: E402  (sibling module)

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools" / "windows"
UIWIN = TOOLS / "uiwin.py"
WORK = Path(tempfile.gettempdir()) / "fst-accordion-journey"
SETTLE_STEP = "wait:1"
"""Appended to each phase: a move lasts 300 ms, so its frames and settle are logged by then."""
QUIET = "wait:0.8"
"""Follows each toggle before any UIA poll: a cross-process tree walk (``waitfor``/``waitgone``) blocks the app's UI
thread for 50-65 ms, which drops frames mid-move and makes the trace step."""

YEAR = "fst.songs.filter.year"
SUGGESTIONS_PICKER = "fst.suggestions.filter.instrument-picker"
# AccordionMover traces the selector by its x:Name (no AutomationId on the selector itself).
SUGGESTIONS_TRACE = "InstrumentPicker"
LEEWAY = "LeewayInline"
"""The Settings leeway panel's trace id: its ``Accordion.Open`` border's named parent."""

Check = Callable[[list[accordion_trace.Event]], list[str]]


@dataclass(frozen=True)
class Phase:
    """One drive and the check of the accordion lines it appended."""

    label: str
    steps: list[str]
    check: Check = lambda events: []


@dataclass(frozen=True)
class Scenario:
    """One launch of the app and its phases."""

    fixture: tuple[str, ...]
    phases: list[Phase]
    route: str | None = None
    tab: str | None = None
    profile: str | None = None
    args: tuple[str, ...] = ()
    env: dict[str, str] = field(default_factory=dict)


def toggled(accordion: str, opening: bool) -> Check:
    """A full animated move of ``accordion`` in the owner's sequence."""
    return lambda events: accordion_trace.check_toggle(events, accordion, (opening,))


def instant(accordion: str, opening: bool) -> Check:
    """An instant Reduce Motion settle of ``accordion``."""
    return lambda events: accordion_trace.check_instant(events, accordion, (opening,))


SONGS_FIXTURE = ("songs_filter_fixture.py", "--shop", "demo")
OPEN_SONGS_FILTER = ["waitfor:id=fst.songs.row.fixture-pulse@30", "invoke:id=fst.songs.filter",
                     "waitfor:id=fst.songs.filter.reset@10", f"scrollinto:id={YEAR}@5", "wait:0.5"]
OPEN_SUGGESTIONS_FILTER = ["waitfor:id=fst.suggestions.list@30", "wait:1.5", "invoke:id=fst.suggestions.filter-button",
                           "waitfor:id=fst.suggestions.filter.title@10",
                           f"waitfor:id={SUGGESTIONS_PICKER}.compact@10",
                           f"invoke:id={SUGGESTIONS_PICKER}.next", "wait:0.5"]
SETTINGS_READY = ["waitfor:id=fst.settings.show-instrument-icons@30", "scrollinto:id=fst.settings.feedback.feature@20",
                  "scrollto:id=fst.settings,0", "scrollinto:id=fst.settings.filter-invalid-scores@10", "wait:0.5"]
TOGGLE_LEEWAY = "toggle:id=fst.settings.filter-invalid-scores"


def songs(reduced: bool) -> Scenario:
    """Songs Filter Year accordion (the Expander path)."""
    check = instant if reduced else toggled
    return Scenario(SONGS_FIXTURE, [
        Phase("open-filter", OPEN_SONGS_FILTER),
        Phase("open", [f"expand:id={YEAR}", QUIET, f"waitfor:id={YEAR}.select-all@5"], check(YEAR, True)),
        Phase("close", [f"collapse:id={YEAR}", QUIET, f"waitgone:id={YEAR}.select-all@5"], check(YEAR, False)),
    ], tab="songs", args=("--reduce-motion",) if reduced else ())


def settings(reduced: bool) -> Scenario:
    """Settings leeway panel (the ``Accordion.Open`` path)."""
    check = instant if reduced else toggled
    return Scenario(("rivals_fixture.py",), [
        Phase("ready", SETTINGS_READY),
        Phase("open", [TOGGLE_LEEWAY, QUIET, "scrollinto:id=fst.settings.leeway@5"], check(LEEWAY, True)),
        Phase("close", ["scrollinto:id=fst.settings.filter-invalid-scores@5", TOGGLE_LEEWAY, QUIET,
                        "waitgone:id=fst.settings.leeway@5"], check(LEEWAY, False)),
    ], tab="settings", args=("--reduce-motion",) if reduced else ())


SCENARIOS = {
    "songs-year": songs(reduced=False),
    "suggestions": Scenario(("rivals_fixture.py",), [
        Phase("open-filter", OPEN_SUGGESTIONS_FILTER),
        Phase("open", [f"toggle:id={SUGGESTIONS_PICKER}.compact", QUIET,
                       "waitfor:id=fst.suggestions.filter.type.Solo_Bass.nearFC@5"], toggled(SUGGESTIONS_TRACE, True)),
        Phase("close", [f"toggle:id={SUGGESTIONS_PICKER}.compact", QUIET,
                        "waitgone:id=fst.suggestions.filter.type.Solo_Bass.nearFC@5"], toggled(SUGGESTIONS_TRACE, False)),
    ], route="/suggestions", profile="fixture-player-1:Fixture Player", env={"FST_DEBUG_SUGGESTIONS_SEED": "7"}),
    "settings-leeway": settings(reduced=False),
    "songs-year-reduced": songs(reduced=True),
    "settings-reduced": settings(reduced=True),
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
    """Drive each phase and judge the accordion lines it appended (printed with each phase)."""
    failures: list[str] = []
    mark = len(read_lines(log))
    for phase in phases:
        drive([*phase.steps, SETTLE_STEP])
        lines = read_lines(log)
        events = accordion_trace.parse(lines[mark:])
        mark = len(lines)
        found = phase.check(events)
        print(f"  {phase.label}: {len(events)} accordion line(s)")
        for event in events:
            print(f"    {event.kind} {event.id} {event.values}")
        failures += [f"{phase.label}: {failure}" for failure in found]
    return failures


def launch_args(name: str, port: int, exe: Path) -> list[str]:
    """Builds the ``uiwin.py launch`` arguments for a scenario."""
    scenario = SCENARIOS[name]
    data = WORK / name
    shutil.rmtree(data, ignore_errors=True)
    data.mkdir(parents=True)
    args = ["launch", str(exe), "--timeout", "60", "--wait", "1", "--preset", "medium",
            f"--arg=--base-url=http://127.0.0.1:{port}/", "--arg=--first-run=off",
            f"--arg=--settings-path={data / 'settings.json'}", "--extra", f"FST_DEBUG_DATA_DIR={data}",
            f"--arg=--perf-log={data / 'perf.log'}"]
    if scenario.route:
        args += ["--route", scenario.route]
    if scenario.tab:
        args += ["--tab", scenario.tab]
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


def main() -> int:
    """Runs the selected scenarios one app at a time."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", choices=sorted(SCENARIOS), action="append")
    journey_exe.add_argument(parser)
    options = parser.parse_args()
    failed = 0
    for name in options.only or list(SCENARIOS):
        print(f"{name}:")
        failures = run(name, options.exe)
        if failures:
            failed += 1
            print(f"FAIL {name}:\n  " + "\n  ".join(failures))
        else:
            print(f"PASS {name}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
