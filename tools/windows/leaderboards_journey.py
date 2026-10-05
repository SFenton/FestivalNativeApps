"""Leaderboards overview UI journeys on Windows through uiwin.py (FlaUI driver).

Each scenario starts ``tools/windows/leaderboards_fixture.py`` (the synthetic mock service plus per-board empty and
frozen overrides) on an OS-assigned loopback port, launches the Debug app on ``/leaderboards`` with a throwaway
settings file (``FST_SETTINGS_PATH``) and an in-memory debug profile, drives it by ``fst.*`` AutomationIds and exact
UIA names, and fails on the first missing element. Every step is a UIA pattern (Invoke, Toggle, ScrollItem) or a
PrintWindow shot, with no SendInput, so the journeys also pass while the console session is locked.

Reachable overview states (issue #207): anonymous cards and rows, the selected player highlighted inside the top ten,
pinned below it (outside), not yet ranked and a failed spotlight read with Retry, an empty board, a scrape-frozen
board with its countdown and Retry Now, every card failing (closed port), Rank By, Quick Links, View All to Full and
Band Rankings, a row opening the player or band page, and a long name scrolling in its row (issue #292). With
``--shots DIR`` it also saves screenshots.

Usage: ``python tools/windows/leaderboards_journey.py [--shots DIR] [--only NAME[,NAME…]] [--sizes compact,medium,wide]``
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import journey_exe  # noqa: E402  (sibling module)
from leaderboards_fixture import LONG_NAME  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
UIWIN = ROOT / "tools" / "windows" / "uiwin.py"
FIXTURE = ROOT / "tools" / "windows" / "leaderboards_fixture.py"
EXE = journey_exe.DEBUG_EXE
ANONYMOUS = {"FST_DEBUG_ANONYMOUS": "1"}
PLAYER = {"FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1"}
LEAD = "fst.leaderboards.card.Solo_Guitar"
LONG_ROW_NAME = f"Rank #2, {LONG_NAME}. Total Score 88,000,000, 38 / 50 songs"

def quick_link(section: str) -> list[str]:
    """Steps that open Quick Links and jump to one section (UIA Toggle, not the mouse wheel).

    Args:
        section: Quick Links section ID, e.g. ``band:Band_Duets``.

    Returns:
        Steps for ``uiwin.py drive``.
    """
    # The menu scrolls away with the header after an earlier jump: bring it back through UIA ScrollItem first.
    return ["scrollinto:id=fst.quick-links.open", "invoke:id=fst.quick-links.open", f"waitfor:id=fst.quick-links.item.{section}@5",
            f"toggle:id=fst.quick-links.item.{section}"]


# name -> (environment, fixture flags, steps). {shot:NAME} placeholders become screenshots with --shots.
SCENARIOS: dict[str, tuple[dict[str, str], list[str], list[str]]] = {
    "overview": (
        ANONYMOUS, [],
        [
            f"waitfor:id={LEAD}@30",
            "waitfor:id=fst.rankings.row.fixture-player-1@15",
            "waitfor:id=fst.rankings.row.fixture-rank-3",
            # The View All name starts with its visible label (WCAG 2.5.3), then names the board.
            "waitfor:name=View All Rankings (3), Lead",
            "waitfor:name=Rank by: Total Score",
            "waitgone:name=Loading leaderboards",
            "waitgone:name=Loading your rank",
            "{shot:leaderboards}",
            *quick_link("band:Band_Duets"),
            "waitfor:id=fst.leaderboards.bands-header@10",
            "waitfor:id=fst.band-rankings.row.fixture-team-1@10",
            "waitfor:name=View All Rankings (2), Duos",
            "{shot:leaderboards-bands}",
        ],
    ),
    "selected-top": (
        # Fixture Player 1 is #1 on every board: highlighted in place, no spotlight read or pinned row.
        PLAYER, [],
        [
            "waitfor:id=fst.rankings.row.fixture-player-1@30",
            "waitgone:name=Loading your rank@10",
            "waitgone:name=Not yet ranked on Lead.",
            "{shot:leaderboards-selected}",
        ],
    ),
    "selected-outside": (
        # 1,200 ranked accounts: #50 is outside the top ten, so each card pins its row below the board.
        {"FST_DEBUG_PROFILE": "fixture-rank-50:Fixture Rank 50"}, ["--large-rankings"],
        [
            f"waitfor:id={LEAD}@30",
            # The pinned row sits below the ten board rows, under the fold at medium and compact heights; its Button
            # carries the spotlight ID (issue #208), not the board row's fst.rankings.row.<accountId>.
            f"scrollinto:id={LEAD}.spotlight@20",
            f"waitfor:id={LEAD}.spotlight",
            "scrollinto:name=View All Rankings (1,200), Lead",
            "waitfor:name=View All Rankings (1,200), Lead",
            "waitgone:name=Loading your rank@10",
            "{shot:leaderboards-spotlight}",
        ],
    ),
    "unranked": (
        {"FST_DEBUG_PROFILE": "fixture-rank-unranked:Unranked Player"}, [],
        [
            f"waitfor:id={LEAD}.spotlight.unranked@30",
            "waitfor:name=Not yet ranked on Lead.",
            "{shot:leaderboards-unranked}",
        ],
    ),
    "spotlight-fail": (
        {"FST_DEBUG_PROFILE": "fixture-rank-fail:Failing Player"}, [],
        [
            "waitfor:name=Your rank unavailable@30",
            "waitfor:name=Retry",
            "{shot:leaderboards-spotlight-failed}",
            "invoke:name=Retry",
            "waitfor:name=Your rank unavailable@15",
        ],
    ),
    "empty-frozen": (
        # One empty instrument, one scrape-frozen instrument and one empty band size; the other cards still load.
        ANONYMOUS, ["--empty-board", "Solo_Bass", "--frozen-board", "Solo_Drums", "--empty-board", "Band_Trios"],
        [
            f"waitfor:id={LEAD}.view-all@30",
            "waitfor:name=No ranked Bass players yet.@15",
            "waitgone:id=fst.leaderboards.card.Solo_Bass.view-all",
            *quick_link("instrument:Solo_Drums"),
            "waitfor:name=Scores are updating@15",
            "waitfor:name=Retry Now",
            "waitgone:id=fst.leaderboards.card.Solo_Drums.view-all",
            "{shot:leaderboards-empty-frozen}",
            "invoke:name=Retry Now",
            "waitfor:name=Scores are updating@15",
            *quick_link("band:Band_Trios"),
            "waitfor:name=No ranked trios yet.@10",
            "waitgone:id=fst.leaderboards.band-card.Band_Trios.view-all",
        ],
    ),
    "error": (
        # A closed loopback port: every card shows its own retryable failure and no View All.
        {**ANONYMOUS, "FST_BASE_URL": "http://127.0.0.1:9/"}, [],
        [
            "waitfor:name=Retry@60",
            "waitgone:id=" + LEAD + ".view-all",
            "waitgone:id=fst.rankings.row.fixture-player-1",
            "{shot:leaderboards-error}",
        ],
    ),
    "rank-by": (
        ANONYMOUS, [],
        [
            f"waitfor:id={LEAD}.view-all@30",
            "invoke:id=fst.rankings.rank-by-menu",
            "waitfor:id=fst.rankings.rank-by.fcrate@5",
            "waitfor:id=fst.rankings.rank-by.maxscore",
            # Radio menu items expose only the Toggle pattern; Invoke would fall back to a real click.
            "toggle:id=fst.rankings.rank-by.fcrate",
            "waitfor:name=Rank by: FC Rate@15",
            f"waitfor:id={LEAD}.view-all@15",
            "invoke:id=fst.rankings.rank-by-menu",
            "waitfor:id=fst.rankings.rank-by.totalscore@5",
            "toggle:id=fst.rankings.rank-by.totalscore",
            "waitfor:name=Rank by: Total Score@15",
            f"waitfor:id={LEAD}.view-all@15",
        ],
    ),
    "view-all": (
        ANONYMOUS, [],
        [
            f"waitfor:id={LEAD}.view-all@30",
            f"invoke:id={LEAD}.view-all",
            "waitfor:id=fst.full-rankings.list@15",
            "invoke:id=PART_BackButton",
            f"waitfor:id={LEAD}.view-all@15",
            *quick_link("band:Band_Duets"),
            "waitfor:id=fst.leaderboards.band-card.Band_Duets.view-all@10",
            "invoke:id=fst.leaderboards.band-card.Band_Duets.view-all",
            "waitfor:id=fst.band-rankings.list@15",
            "invoke:id=PART_BackButton",
            "waitfor:id=fst.leaderboards.band-card.Band_Duets.view-all@15",
        ],
    ),
    "long-name": (
        # Issue #292: a name too long for its column scrolls inside it (two shots 2 s apart show it moving) while the
        # songs label, rating and chevron keep their places; Narrator reads the whole name once, here and in Full Rankings.
        ANONYMOUS, ["--long-name"],
        [
            "waitfor:id=fst.rankings.row.fixture-player-2@30",
            f"waitfor:name={LONG_ROW_NAME}",
            "waitgone:name=Loading leaderboards",
            "{shot:leaderboards-long-name-a}",
            "wait:2",
            "{shot:leaderboards-long-name-b}",
            f"invoke:id={LEAD}.view-all",
            "waitfor:id=fst.full-rankings.list@15",
            f"waitfor:name={LONG_ROW_NAME}@15",
            "{shot:full-rankings-long-name}",
            "invoke:id=PART_BackButton",
            f"waitfor:id={LEAD}.view-all@15",
        ],
    ),
    "rows": (
        ANONYMOUS, [],
        [
            "waitfor:id=fst.rankings.row.fixture-player-2@30",
            "invoke:id=fst.rankings.row.fixture-player-2",
            "waitfor:id=fst.player.name@15",
            "invoke:id=PART_BackButton",
            "waitfor:id=fst.rankings.row.fixture-player-2@15",
            *quick_link("band:Band_Duets"),
            "waitfor:id=fst.band-rankings.row.fixture-team-1@10",
            "invoke:id=fst.band-rankings.row.fixture-team-1",
            "waitfor:id=fst.band.title@15",
            "invoke:id=PART_BackButton",
            "waitfor:id=fst.band-rankings.row.fixture-team-1@15",
        ],
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


def ready_port(line: str) -> int | None:
    """Reads the port from the mock service's ready line.

    Args:
        line: One line of the fixture's standard output.

    Returns:
        The bound loopback port, or ``None`` when the line is not the ready line.
    """
    match = re.search(r"on 127\.0\.0\.1:(\d+)", line)
    return int(match.group(1)) if match else None


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


def launch_args(env: dict[str, str], port: int, settings_path: Path, size: str) -> list[str]:
    """Builds the ``uiwin.py launch`` arguments for one scenario.

    Args:
        env: Scenario environment; its own ``FST_BASE_URL`` (e.g. a closed port) replaces the fixture origin.
        port: Fixture port.
        settings_path: Throwaway settings file.
        size: Window preset.

    Returns:
        Arguments after ``uiwin.py``.
    """
    args = ["launch", str(EXE), "--timeout", "60", "--wait", "1", "--preset", size, "--route", "/leaderboards",
            "--arg=--first-run=off", "--extra", f"FST_SETTINGS_PATH={settings_path}"]
    if "FST_BASE_URL" not in env:
        args.append(f"--arg=--base-url=http://127.0.0.1:{port}/")
    for key, value in env.items():
        args += ["--extra", f"{key}={value}"]
    return args


def run(name: str, shots: Path | None, size: str) -> None:
    """Starts the scenario's fixture, then launches, drives and closes the app.

    Args:
        name: Scenario key.
        shots: Screenshot directory, if any.
        size: Window preset.
    """
    env, flags, steps = SCENARIOS[name]
    server = subprocess.Popen([sys.executable, str(FIXTURE), "--port", "0", *flags],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    try:
        port = ready_port(server.stdout.readline() if server.stdout else "")
        if port is None:
            raise RuntimeError("fixture service did not start")
        with tempfile.TemporaryDirectory() as folder:
            settings_path = Path(folder) / "settings.json"
            settings_path.write_text(json.dumps({"version": 1}), encoding="utf-8")
            uiwin(*launch_args(env, port, settings_path, size))
            try:
                steps_file = Path(folder) / "steps.txt"
                steps_file.write_text("\n".join(expand(steps, shots, size)), encoding="utf-8")
                uiwin("drive", "--steps-file", str(steps_file))
                print(f"PASS {name} [{size}]", flush=True)
            finally:
                uiwin("close")
    finally:
        server.terminate()
        server.wait(timeout=10)


def main() -> int:
    """Runs the selected scenarios.

    Returns:
        Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--shots", type=Path)
    parser.add_argument("--only", help=f"comma-separated scenarios ({', '.join(SCENARIOS)})")
    parser.add_argument("--sizes", default="medium", help="comma-separated presets for every scenario")
    journey_exe.add_argument(parser)
    options = parser.parse_args()
    names = options.only.split(",") if options.only else list(SCENARIOS)
    if unknown := [name for name in names if name not in SCENARIOS]:
        parser.error(f"unknown scenario(s): {', '.join(unknown)}")
    global EXE
    EXE = options.exe
    if options.shots:
        options.shots.mkdir(parents=True, exist_ok=True)
    failures = 0
    for name in names:
        for size in options.sizes.split(","):
            try:
                run(name, options.shots, size)
            except RuntimeError as error:
                failures += 1
                print(f"FAIL {name} [{size}]: {error}", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
