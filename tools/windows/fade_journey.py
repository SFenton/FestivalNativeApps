"""Load-transition journeys on Windows (#323): every scroll during a first-load entrance rushes it, pinned rows included.

Each scenario launches the Debug app against ``fade_fixture.py`` (the mock service plus a selected player ranked 17th on
the fixture-pulse Lead board) with ``--perf-log`` and a 10 s arm window (``FST_DEBUG_FADE_WINDOW_MS``), drives it
through ``uiwin.py`` and judges the ``FadeIn`` lines each phase appended (``fade_trace.py``):

================  ======================================================================================================
Scenario          What the trace must show
================  ======================================================================================================
``song-reveal``   Song Details: a scroll of the page rushes its entrance (header, sections, cards, the reloaded song's
                  arm) with no pending fade keeping its delay. Invoking player 17's preview row opens the Lead board's first page with
                  ``navToPlayer``: the pinned "your score" row enters with the board's rows, the reveal waits for row
                  17's entrance (web ``navToPlayer``), rushes the board and only then scrolls; no row it realizes
                  staggers.
``song-board``    Song leaderboard: the pinned row enters with the rows, and a scroll to the end rushes both.
``band-board``    Song band leaderboard: the same, with the selected band's pinned row.
``full-rankings`` Full Rankings: the same, with the pinned footer.
``profile``       Statistics (Player Profile): a Quick Links jump during the overview entrance rushes its title,
                  heading and grid.
================  ======================================================================================================

A failure means a fade that should have joined the rush (the review's #358 regressions: a pinned row outside its
board's entrance, an overview entrance with no page scope) kept its stagger delay. UIA input is slow (about 1 s a step), so
a scroll can arrive after a short entrance has finished: the rush then reports `rushed=0`, and the checks still
require enrollment before it, a rush rather than a close, and no delayed fade of the entrance after it.

Usage: ``python tools/windows/fade_journey.py [--only NAME]`` (build first with ``tools/windows/build.ps1``).
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import fade_trace  # noqa: E402  (sibling module)
import journey_exe  # noqa: E402  (sibling module)
import ui_journey  # noqa: E402  (sibling module)

ROOT = Path(__file__).resolve().parents[2]
UIWIN = ROOT / "tools" / "windows" / "uiwin.py"
FIXTURE = ROOT / "tools" / "windows" / "fade_fixture.py"
WORK = Path(tempfile.gettempdir()) / "fst-fade-journey"
#: Lengthens the app's 1 s arm window so a scripted scroll lands inside the entrance (see suggestions_journey.py).
FADE_WINDOW_MS = 10000
DEEP = "fixture-player-17:Fixture Player 17"
TOP = "fixture-player-1:Fixture Player 1"
RANKED = "fixture-rank-40:Fixture Rank 40"
"""Ranked 40th in the ``--large-rankings`` account rankings (page 2), so Full Rankings pins the footer on page 1."""
SONG_DETAIL_PARTS = ("FullHeader", "IntensitySection", "HistorySection", "LeaderboardsSection")
PLAYER_ROW = "id=fst.song-detail.preview-row.Solo_Guitar.fixture-player-17"


def board_rush(open_steps: list[str], list_id: str, owner: str, pinned: str) -> list[fade_trace.Phase]:
    """The phase of a board scenario: open the board, then scroll to its end inside the entrance.

    The board opens inside the drive (not at launch), so the scroll follows its load even when the drive first waits
    for the shared desktop lock.

    Args:
        open_steps: Steps that open the board from the launch page.
        list_id: The board list's AutomationId.
        owner: The trace name of the board's list (``RowsRepeater`` or ``Rows``).
        pinned: The trace name of its pinned "your score" row.

    Returns:
        One phase: the pinned row is enrolled in the board's entrance and the scroll rushes every pending fade.
    """
    return [fade_trace.Phase("load-scroll", [*open_steps, f"waitfor:id={list_id}@30", f"scrollto:id={list_id},100"],
                             lambda events: fade_trace.check_entrance_rush(events, owner, [pinned], FADE_WINDOW_MS))]


def from_song_detail(button: str) -> list[str]:
    """Steps that open a board from a Song Details "View Full Leaderboard" button."""
    return [f"scrollinto:id={button}@30", f"invoke:id={button}"]


@dataclass(frozen=True)
class Scenario:
    """One launch of the app and its phases."""

    route: str
    profile: str
    phases: list[fade_trace.Phase]


SCENARIOS = {
    "song-reveal": Scenario("/songs", DEEP, [
        fade_trace.Phase("detail-scroll", ["waitfor:id=fst.songs.row.fixture-pulse@30",
                                           "invoke:id=fst.songs.row.fixture-pulse",
                                           "waitfor:id=fst.song-detail.preview-row.Solo_Guitar.fixture-player-1@30",
                                           "scrollto:id=fst.song-detail,100"],
                         lambda events: fade_trace.check_entrance_rush(events, "Scroller", SONG_DETAIL_PARTS,
                                                                       FADE_WINDOW_MS)),
        fade_trace.Phase("score-to-row", [f"scrollinto:{PLAYER_ROW}@10", f"invoke:{PLAYER_ROW}","waitfor:id=fst.song-leaderboard.list@30",
                                          "waitfor:id=fst.song-leaderboard.row.fixture-player-17@15", "wait:3"],
                         lambda events: fade_trace.check_reveal(events, "RowsRepeater", 16, ["SpotlightPanel"])),
    ]),
    "song-board": Scenario("/songs/fixture-pulse", DEEP, board_rush(
        from_song_detail("fst.song-detail.view-all.Solo_Guitar"), "fst.song-leaderboard.list", "RowsRepeater",
        "SpotlightPanel")),
    "band-board": Scenario("/songs/fixture-pulse", TOP, board_rush(
        from_song_detail("fst.song-detail.band-view-all.Band_Duets"), "fst.song-band-leaderboard.list", "Rows",
        "SpotlightPanel")),
    "full-rankings": Scenario("/leaderboards", RANKED, board_rush(
        ["scrollinto:id=fst.leaderboards.card.Solo_Guitar.view-all@30",
         "invoke:id=fst.leaderboards.card.Solo_Guitar.view-all"],
        "fst.full-rankings.list", "RowsRepeater", "FooterSpotlight")),
    "profile": Scenario("/songs", TOP, [
        fade_trace.Phase("quick-links", ["waitfor:id=fst.nav.statistics@30", "select:id=fst.nav.statistics",
                                         "waitfor:id=fst.player.overview@30", "invoke:id=fst.quick-links.open",
                                         "waitfor:id=fst.quick-links.item.bands@5",
                                         "toggle:id=fst.quick-links.item.bands"],
                         lambda events: fade_trace.check_entrance_rush(
                             events, "Scroller", ["TitleRow", "OverviewHeading", "OverviewGrid"], FADE_WINDOW_MS)),
    ]),
}
"""Scenarios by name."""


def uiwin(*args: str) -> str:
    """Runs one uiwin.py command, raising on failure.

    Args:
        args: Command-line arguments after ``uiwin.py``.

    Returns:
        The command's standard output.

    Raises:
        RuntimeError: The command failed.
    """
    result = subprocess.run([sys.executable, str(UIWIN), *args], capture_output=True, text=True, encoding="utf-8",
                            errors="replace")
    if result.returncode != 0:
        raise RuntimeError(f"uiwin {' '.join(args[:2])} failed:\n{result.stdout}\n{result.stderr}")
    return result.stdout


def drive(steps: list[str]) -> str:
    """Drives the launched app through ``steps``.

    Args:
        steps: ``uiwin.py drive`` steps.

    Returns:
        The driver's output.
    """
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as handle:
        handle.write("\n".join(steps))
    try:
        return uiwin("drive", "--steps-file", handle.name)
    finally:
        Path(handle.name).unlink(missing_ok=True)


def launch_args(name: str, port: int, exe: Path) -> list[str]:
    """Builds the ``uiwin.py launch`` arguments for a scenario.

    Args:
        name: Scenario key.
        port: Fixture port.
        exe: App executable.

    Returns:
        Arguments after ``uiwin.py``.
    """
    scenario = SCENARIOS[name]
    data = WORK / name
    shutil.rmtree(data, ignore_errors=True)
    data.mkdir(parents=True)
    # --first-run=off: the first-run carousel is modal and would swallow the scripted input. Each scenario opens the
    # page under test inside its drive, so the launch's own wait for the desktop lock never outlasts the entrance.
    return ["launch", str(exe), "--timeout", "60", "--wait", "1", "--preset", "medium", "--route", scenario.route,
            f"--arg=--base-url=http://127.0.0.1:{port}/", "--arg=--first-run=off",
            f"--arg=--settings-path={data / 'settings.json'}", "--extra", f"FST_DEBUG_DATA_DIR={data}",
            f"--arg=--profile={scenario.profile}", f"--arg=--perf-log={data / 'perf.log'}",
            "--extra", f"FST_DEBUG_FADE_WINDOW_MS={FADE_WINDOW_MS}"]


def run(name: str, port: int, exe: Path) -> list[str]:
    """Launches, drives and closes one scenario.

    Args:
        name: Scenario key.
        port: Fixture port.
        exe: App executable.

    Returns:
        Failures (a failure screenshot and UIA tree are saved in the scenario's work folder).
    """
    uiwin(*launch_args(name, port, exe))
    try:
        failures = fade_trace.run_phases(drive, WORK / name / "perf.log", SCENARIOS[name].phases)
    except RuntimeError as error:
        failures = [str(error)]
    if failures:
        for command, suffix in (("shot", ".png"), ("tree", ".txt")):
            try:
                uiwin(command, str(WORK / name / f"FAILED{suffix}"))
            except RuntimeError:
                pass
    uiwin("close")
    return failures


def main() -> int:
    """Runs the selected scenarios one app at a time.

    Returns:
        Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--only", choices=sorted(SCENARIOS), action="append")
    journey_exe.add_argument(parser)
    options = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    server, port = ui_journey.start_mock(WORK / "service.log", ("--large-rankings",), FIXTURE)
    failed = 0
    try:
        for name in options.only or list(SCENARIOS):
            failures = run(name, port, options.exe)
            if failures:
                failed += 1
                print(f"FAIL {name}:\n  " + "\n  ".join(failures))
            else:
                print(f"PASS {name}")
    finally:
        server.terminate()
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
