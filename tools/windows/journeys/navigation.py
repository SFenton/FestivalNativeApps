#!/usr/bin/env python3
"""App Navigation (``fst.nav.*``) UI journeys for the Windows shell, driven through ``tools/windows/uiwin.py``.

One journey per reachable state of ``.agents/controls/app-navigation/spec.md`` (``songs``, ``leaderboards``,
``settings``, ``player``, ``band``, ``reselect``) plus the ``/compete`` deep link (no Compete section or Leaderboards
Overview button, issue #266), the minimal-pane (compact width) and keyboard paths.
Each launches this worktree's build against the anonymized loopback fixture (``tools/windows/rivals_fixture.py``)
with isolated settings, runs UIA step phases (``waitfor`` steps are the assertions) and checks the UIA tree
dumped after each phase with regular expressions: required, forbidden and in-order patterns. Pane selection is
read from the tree line's ``selected`` flag, accelerators from ``accel=``/``access=``. Nothing touches
production or the operator's settings. Pane items are chosen with UIA SelectionItem ``select:`` (an assistive
technology's activation; WinUI raises ItemInvoked for it) and keys are posted, so the journeys also run on a
locked console.

Usage (from the repository root, after ``tools/windows/build.ps1``)::

    python tools/windows/journeys/navigation.py                    # all journeys
    python tools/windows/journeys/navigation.py band reselect      # by name
    python tools/windows/journeys/navigation.py --shots out\\nav   # per-phase screenshots

Exit code 0 when every journey passes, 1 otherwise.
"""

from __future__ import annotations

import argparse
import importlib.util
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import journey_exe  # noqa: E402  (tools/windows module)


def _load_profile_journeys():
    """Load the sibling ``profile.py`` by path (``import profile`` would resolve to the stdlib profiler)."""
    spec = importlib.util.spec_from_file_location("fst_profile_journeys", Path(__file__).with_name("profile.py"))
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module  # dataclasses resolve their module through sys.modules
    spec.loader.exec_module(module)
    return module


_PROFILE = _load_profile_journeys()
ANONYMOUS, _app_args, _free_port, _profile, _uiwin = (
    _PROFILE.ANONYMOUS, _PROFILE._app_args, _PROFILE._free_port, _PROFILE._profile, _PROFILE._uiwin)

REPO = Path(__file__).resolve().parents[3]
FIXTURE = REPO / "tools" / "windows" / "rivals_fixture.py"

# region Model


@dataclass
class Phase:
    """One drive call and the checks on the UIA tree dumped after it.

    Attributes:
        steps: ``uiwin.py drive`` steps.
        expect: Regular expressions that must match the tree.
        forbid: Regular expressions that must not match the tree.
        order: Literal substrings that must appear in this order (e.g. pane items top to bottom).
    """

    steps: list[str]
    expect: list[str] = field(default_factory=list)
    forbid: list[str] = field(default_factory=list)
    order: list[str] = field(default_factory=list)


@dataclass
class Journey:
    """One scripted navigation journey.

    Attributes:
        name: Short CLI name (the spec state it covers, or the path).
        launch: Extra ``uiwin.py launch`` arguments (tab, route, profile).
        phases: Phases run in order; the journey stops at the first failing drive.
        preset: Launch window preset (``compact`` < 641 epx is LeftMinimal, ``medium`` LeftCompact, ``wide`` Expanded).
    """

    name: str
    launch: list[str]
    phases: list[Phase]
    preset: str = "wide"


def selected(automation_id: str) -> str:
    """Tree-line pattern for a selected element with this AutomationId."""
    return rf"id={re.escape(automation_id)} [^\n]*\[[^\]\n]*selected"


def present(automation_id: str) -> str:
    """Tree-line pattern for an element with exactly this AutomationId."""
    return rf"id={re.escape(automation_id)} "


ANONYMOUS_PANE = ["fst.nav.songs", "fst.nav.leaderboards", "fst.nav.shop", "fst.nav.settings"]
PLAYER_PANE = ["fst.nav.songs", "fst.nav.suggestions", "fst.nav.statistics", "fst.nav.rivals",
               "fst.nav.leaderboards", "fst.nav.shop", "fst.nav.settings"]
PLAYER_ONLY = ["fst.nav.suggestions", "fst.nav.statistics", "fst.nav.rivals"]
SONGS_READY = "waitfor:id=fst.songs.row.fixture-pulse@20"
BOARDS_READY = "waitfor:id=fst.leaderboards.card.Solo_Guitar@20"
FIXTURE_PLAYER = _profile("fixture-player-1:Demo Player")
#: Any element named like a Compete-style "Leaderboards Overview" button (issues #66, #266: the web has none).
NO_OVERVIEW = r'(?i)"[^"\n]*leaderboards? overview[^"\n]*" id='
#: Expanded pane (window >= 1008 epx) with a page under Band Rankings' 1100 epx split width
#: (``LeaderboardsBandRankingsPage.SplitWidth``), so the ``band`` state is the pushed band page on every display: the
#: ``wide`` preset splits on a 100% 1920x1080 desktop (issue #533) but not where the display clamps the window.
BELOW_SPLIT = "1200x800"

JOURNEYS = [
    Journey(
        name="songs",
        launch=["--tab", "songs", *ANONYMOUS],
        phases=[Phase(
            steps=[SONGS_READY],
            expect=[selected("fst.nav.songs"), r'"Songs" id=fst\.nav\.songs [^\n]*accel=Control\+1 access=Alt, S',
                    r'"Leaderboards" id=fst\.nav\.leaderboards [^\n]*accel=Control\+2 access=Alt, L',
                    r'"Item Shop" id=fst\.nav\.shop [^\n]*accel=Control\+3 access=Alt, I',
                    r'"Settings" id=fst\.nav\.settings [^\n]*accel=Control\+Comma access=Alt, E',
                    r'id=fst\.shell\.profile [^\n]*access=Alt, P', r'"Page content" id=FrameHost [^\n]*landmark=main'],
            forbid=[present(i) for i in PLAYER_ONLY] + [selected("fst.nav.leaderboards"), present("fst.shell.notifications")],
            order=ANONYMOUS_PANE,
        )],
    ),
    Journey(
        name="leaderboards",
        launch=["--tab", "songs", *ANONYMOUS],
        phases=[
            Phase(steps=[SONGS_READY, "select:id=fst.nav.leaderboards", BOARDS_READY],
                  expect=[selected("fst.nav.leaderboards")], forbid=[selected("fst.nav.songs")]),
            # Push Full Rankings inside the section: Back appears, the pane keeps Leaderboards selected.
            Phase(steps=["invoke:id=fst.leaderboards.card.Solo_Guitar.view-all", "waitfor:id=fst.full-rankings.list@20",
                         "waitfor:name=Back@5"],
                  expect=[selected("fst.nav.leaderboards"), present("fst.full-rankings.title")]),
            # Another section and back restores the nested route (per-section history).
            Phase(steps=["key:ctrl+1", SONGS_READY, "key:ctrl+2", "waitfor:id=fst.full-rankings.list@15"],
                  expect=[selected("fst.nav.leaderboards"), present("fst.full-rankings.title")]),
            # Re-invoking the current section returns to its root.
            Phase(steps=["select:id=fst.nav.leaderboards", BOARDS_READY, "waitgone:id=fst.full-rankings.list@10"],
                  expect=[selected("fst.nav.leaderboards")], forbid=[present("fst.full-rankings.title")]),
        ],
    ),
    Journey(
        name="settings",
        launch=["--tab", "songs", *ANONYMOUS],
        phases=[
            Phase(steps=[SONGS_READY, "key:ctrl+comma", "waitfor:id=fst.settings.show-instrument-icons@15"],
                  expect=[selected("fst.nav.settings")], forbid=[selected("fst.nav.songs"), r'"Back" id=']),
            Phase(steps=["key:ctrl+1", SONGS_READY, "select:id=fst.nav.settings",
                         "waitfor:id=fst.settings.show-instrument-icons@15"],
                  expect=[selected("fst.nav.settings")], forbid=[selected("fst.nav.songs")]),
        ],
    ),
    Journey(
        name="player",
        launch=["--tab", "songs", *FIXTURE_PLAYER],
        phases=[
            Phase(steps=[SONGS_READY, "waitfor:id=fst.nav.statistics@15"],
                  expect=[selected("fst.nav.songs"), r'"Statistics" id=fst\.nav\.statistics [^\n]*accel=Control\+3 access=Alt, T',
                          r'"Leaderboards" id=fst\.nav\.leaderboards [^\n]*accel=Control\+5',
                          r'"Item Shop" id=fst\.nav\.shop [^\n]*accel=Control\+6', present("fst.shell.notifications")],
                  order=PLAYER_PANE),
            Phase(steps=["select:id=fst.nav.statistics", "waitfor:id=fst.player.name@20"],
                  expect=[selected("fst.nav.statistics")]),
            Phase(steps=["key:ctrl+2", "waitfor:id=fst.suggestions.list@25"], expect=[selected("fst.nav.suggestions")]),
            Phase(steps=["key:ctrl+4", "waitfor:id=fst.rivals.title@20"], expect=[selected("fst.nav.rivals")]),
        ],
    ),
    Journey(
        name="band",
        launch=["--tab", "leaderboards", *ANONYMOUS],
        phases=[
            # Below the split width the row pushes the band page; the side-by-side variant is split-panes.json's.
            Phase(steps=[BOARDS_READY, "scrollinto:id=fst.leaderboards.band-card.Band_Duets.view-all@10",
                         "invoke:id=fst.leaderboards.band-card.Band_Duets.view-all",
                         "waitfor:id=fst.band-rankings.row.fixture-team-1@20",
                         "waitgone:id=fst.band-rankings.detail-pane@5",
                         "invoke:id=fst.band-rankings.row.fixture-team-1", "waitfor:id=fst.band.title@20",
                         "waitfor:name=Back@5"],
                  expect=[selected("fst.nav.leaderboards"), present("fst.band.title")],
                  forbid=[present(i) for i in PLAYER_ONLY]),
            # Back leaves the band page, then a re-invoke pops the section to its root.
            Phase(steps=["key:alt+left", "waitfor:id=fst.band-rankings.list@10", "select:id=fst.nav.leaderboards",
                         "waitgone:id=fst.band-rankings.list@10", "waitfor:id=fst.leaderboards@10"],
                  expect=[selected("fst.nav.leaderboards")], forbid=[present("fst.band.title"), r'"Back" id=']),
        ],
        preset=BELOW_SPLIT,
    ),
    Journey(
        name="reselect",
        launch=["--tab", "songs", *FIXTURE_PLAYER],
        phases=[
            Phase(steps=[SONGS_READY, "key:ctrl+3", "waitfor:id=fst.player.deselect@20"],
                  expect=[selected("fst.nav.statistics")], order=PLAYER_PANE),
            # Deselecting on a player-only section lands on Songs and removes the player-only items.
            Phase(steps=["invoke:id=fst.player.deselect", "waitfor:id=PrimaryButton@10", "invoke:id=PrimaryButton",
                         "waitgone:id=fst.nav.statistics@10", SONGS_READY],
                  expect=[selected("fst.nav.songs")], forbid=[present(i) for i in PLAYER_ONLY], order=ANONYMOUS_PANE),
            # Selecting again restores them in place without moving the selected section.
            Phase(steps=["invoke:id=fst.shell.profile", "waitfor:id=fst.profile.search@5", "type:Fixture",
                         "waitfor:name=Fixture Player 2@10", "invoke:name=Fixture Player 2",
                         "waitfor:id=fst.player.select@15", "invoke:id=fst.player.select",
                         "waitfor:id=fst.nav.statistics@10"],
                  expect=[selected("fst.nav.songs"), present("fst.player.deselect")], order=PLAYER_PANE),
            # Issue #290: back on Songs, the profile button opens the selected player's Statistics, not the picker.
            Phase(steps=["key:ctrl+1", SONGS_READY, "invoke:id=fst.shell.profile", "waitfor:id=fst.statistics@10",
                         "waitfor:id=fst.player.deselect@15"],
                  expect=[selected("fst.nav.statistics")], forbid=[present("fst.profile.search")], order=PLAYER_PANE),
        ],
    ),
    Journey(
        # Issues #66/#266: Windows has no Compete section, so /compete opens the Rivals root with no leaderboard cards
        # and no "Leaderboards Overview" button; Leaderboards stays its own pane item and each board's View All opens
        # Full Rankings (web CompetePage "View Full Leaderboards" per section).
        name="compete",
        launch=["--route", "/compete", *FIXTURE_PLAYER],
        phases=[
            Phase(steps=["waitfor:id=fst.rivals.section.common@20"],
                  expect=[selected("fst.nav.rivals"), present("fst.rivals.title")],
                  forbid=[present("fst.nav.compete"), NO_OVERVIEW, r"id=fst\.leaderboards[. ]"], order=PLAYER_PANE),
            Phase(steps=["select:id=fst.nav.leaderboards", BOARDS_READY,
                         "waitfor:id=fst.leaderboards.card.Solo_Guitar.view-all@15"],
                  expect=[selected("fst.nav.leaderboards"), present("fst.leaderboards.card.Solo_Guitar.view-all")],
                  forbid=[NO_OVERVIEW]),
            Phase(steps=["invoke:id=fst.leaderboards.card.Solo_Guitar.view-all", "waitfor:id=fst.full-rankings.list@20"],
                  expect=[selected("fst.nav.leaderboards"), present("fst.full-rankings.title")]),
        ],
    ),
    Journey(
        name="compact",
        launch=["--tab", "songs", *ANONYMOUS],
        preset="compact",
        phases=[
            # LeftMinimal: the pane is closed until the title bar's toggle opens it.
            Phase(steps=[SONGS_READY, "waitgone:id=fst.nav.leaderboards@5", "invoke:id=PART_PaneToggleButton",
                         "waitfor:id=fst.nav.leaderboards@5"],
                  expect=[selected("fst.nav.songs")], order=ANONYMOUS_PANE),
            # Keyboard: Enter on the toggle opens the overlay with focus on the selected item (not the first); Esc
            # light-dismisses it and focus returns to the toggle (the open pane is a light-dismiss surface, so Tab stays
            # inside it). The closed minimal pane has no items in the tree, so the focus assertions carry this phase.
            Phase(steps=["key:ctrl+2", BOARDS_READY, "key:esc", "wait:0.5", "waitgone:id=fst.nav.leaderboards@5",
                         "focus:id=PART_PaneToggleButton", "key:enter", "waitfor:id=fst.nav.leaderboards@5",
                         "assertfocus:id=fst.nav.leaderboards@3", "key:esc", "waitgone:id=fst.nav.leaderboards@5",
                         "assertfocus:id=PART_PaneToggleButton@3"]),
            # Choosing a section closes the light-dismiss pane. Another lane's window taking the foreground between
            # drive calls may already have dismissed it, so Esc first normalises to closed, then the toggle reopens it.
            Phase(steps=["key:esc", "wait:0.5", "invoke:id=PART_PaneToggleButton", "waitfor:id=fst.nav.songs@5",
                         "select:id=fst.nav.songs", SONGS_READY, "waitgone:id=fst.nav.songs@5"]),
            Phase(steps=["resize:wide", "waitfor:id=fst.nav.songs@5"], expect=[selected("fst.nav.songs")]),
        ],
    ),
    Journey(
        name="keyboard",
        launch=["--tab", "songs", *FIXTURE_PLAYER],
        preset="medium",
        phases=[
            Phase(steps=[SONGS_READY, "key:ctrl+5", BOARDS_READY, "key:ctrl+6", "waitfor:id=fst.shop.count@20",
                         "key:ctrl+comma", "waitfor:id=fst.settings.show-instrument-icons@15", "key:ctrl+1", SONGS_READY],
                  expect=[selected("fst.nav.songs")]),
            # Alt+Left walks the pushed page back within the section.
            Phase(steps=["key:ctrl+5", BOARDS_READY, "invoke:id=fst.leaderboards.card.Solo_Guitar.view-all",
                         "waitfor:id=fst.full-rankings.list@20", "key:alt+left", BOARDS_READY,
                         "waitgone:id=fst.full-rankings.list@10"],
                  expect=[selected("fst.nav.leaderboards")]),
            # Tab order: title-bar toggle → search → bell → profile → pane, landing on the selected section
            # (Leaderboards) as NavigationView does for Tab within itself; arrows move within the pane and Enter invokes.
            Phase(steps=["focus:id=PART_PaneToggleButton", "assertfocus:id=PART_PaneToggleButton@3", "key:tab",
                         "assertfocus:name=Search songs, players and bands@3", "key:tab",
                         "assertfocus:id=fst.shell.notifications@3", "key:tab", "assertfocus:id=fst.shell.profile@3",
                         "key:tab", "assertfocus:id=fst.nav.leaderboards@3", "key:down", "assertfocus:id=fst.nav.shop@3",
                         "key:enter", "waitfor:id=fst.shop.count@20"],
                  expect=[selected("fst.nav.shop")]),
        ],
    ),
]

# endregion

# region Checks (pure, unit-tested)


def check(phase: Phase, tree: str) -> list[str]:
    """Check one phase's tree dump.

    Args:
        phase: The phase with its expectations.
        tree: The UIA tree text dumped after the phase.

    Returns:
        Failure messages; empty when every check passed.
    """
    failures = [f"expected /{p}/" for p in phase.expect if not re.search(p, tree)]
    failures += [f"did not expect /{p}/" for p in phase.forbid if re.search(p, tree)]
    position = -1
    for needle in phase.order:
        found = tree.find(f"id={needle} ", position + 1)
        if found < 0:
            failures.append(f"expected {needle!r} after position {position} (order {phase.order})")
            break
        position = found
    return failures

# endregion

# region Runner


def _launch(exe: Path, base: str, settings: Path, journey: Journey) -> int:
    """Launch the app at the journey's preset and return its pid."""
    out = _uiwin("launch", str(exe), "--arg=--base-url", f"--arg={base}", "--arg=--settings-path",
                 f"--arg={settings}", "--arg=--first-run=off", "--preset", journey.preset,
                 *_app_args(journey.launch)).stdout
    for line in out.splitlines():
        if '"pid"' in line:
            return int(line.split(":")[1].strip().rstrip(","))
    raise RuntimeError(f"no pid in launch output: {out}")


def run(journey: Journey, exe: Path, shots: Path | None) -> list[str]:
    """Run one journey and return failure messages (empty when it passed)."""
    failures: list[str] = []
    port = _free_port()
    fixture = subprocess.Popen([sys.executable, str(FIXTURE), "--port", str(port)],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    work = Path(tempfile.mkdtemp(prefix=f"fst-nav-{journey.name}-"))
    pid = None
    try:
        time.sleep(1.0)
        pid = _launch(exe, f"http://127.0.0.1:{port}/", work / "settings.json", journey)
        for index, phase in enumerate(journey.phases):
            tree = work / f"tree-{index}.txt"
            steps = [*phase.steps, "wait:0.5", f"tree:{tree}"]
            if shots is not None:
                steps.append(f"shot:{shots / f'{journey.name}-{index}.png'}")
            result = _uiwin("drive", "--pid", str(pid), "--steps", "; ".join(steps), check=False)
            if result.returncode != 0:
                failures.append(f"phase {index}: {result.stderr.strip()[-600:] or result.stdout.strip()[-600:]}")
                break
            text = tree.read_text(encoding="utf-8", errors="replace") if tree.exists() else ""
            failures += [f"phase {index}: {message}" for message in check(phase, text)]
    except RuntimeError as error:
        failures.append(str(error))
    finally:
        if pid is not None:
            _uiwin("close", "--pid", str(pid), check=False)
        fixture.terminate()
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
    journey_exe.add_argument(parser)
    parser.add_argument("--shots", type=Path, help="directory for per-phase screenshots")
    args = parser.parse_args(argv)
    selected_journeys = [j for j in JOURNEYS if not args.names or j.name in args.names]
    if args.shots:
        args.shots.mkdir(parents=True, exist_ok=True)
    failed = 0
    for journey in selected_journeys:
        failures = run(journey, args.exe.resolve(), args.shots.resolve() if args.shots else None)
        print(f"{'PASS' if not failures else 'FAIL'} {journey.name}", flush=True)
        for failure in failures:
            print(f"  - {failure}", flush=True)
        failed += bool(failures)
    print(f"{len(selected_journeys) - failed}/{len(selected_journeys)} journeys passed")
    return 1 if failed else 0

# endregion


if __name__ == "__main__":
    sys.exit(main())
