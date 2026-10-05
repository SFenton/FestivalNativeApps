#!/usr/bin/env python3
"""First Run carousel UI journeys for the Windows app (issue #232), driven through ``tools/windows/uiwin.py``.

Every reachable ``first-run`` contract state (``contracts/product.json``) runs against the anonymized loopback fixture
(``tools/windows/rivals_fixture.py``) with ``--first-run=on`` (real seen-state behaviour, not ``force``), an isolated
``settings.json`` and an isolated app data folder (``FST_DEBUG_DATA_DIR``) holding ``first-run.json``:

* ``hidden-all-seen``: after every slide was viewed, a relaunch shows no carousel.
* ``new-slides-only``: slides closed unviewed come back alone; a version bump on one seen slide shows only that slide.
* ``gated``: anonymous, selected-player, Shop-hidden and single-slide pages show only their gate-passing slides.
* ``waiting-not-ready``: a page reached while the window is minimized waits, then shows once it is restored.
* ``replay-all``: Settings "Show" plays every slide, ignoring gates and seen-state.
* ``titles``: in a compact window, every page's Settings replay opens a dialog announced with the page's title
  (issue #240) and keeps its Next/Back/Close commands and pips.
* ``late-catalogue``: with ``/api/songs`` delayed (``--songs-delay``), the guide opens over placeholder demo rows and
  its visible demo fills with catalogue songs once they arrive (issue #240).
* ``demo-songs``: every page's Settings replay pages through all 42 slides; each demo reports catalogue songs,
  including Statistics' highest/lowest-rank breakdown (issue #257).
* ``catalogue-unavailable``: with ``/api/songs`` failing (``--songs-unavailable``), the Songs, Statistics, Suggestions
  and Rivals demos keep placeholder rows instead of inventing songs (issue #257).
* ``dismissed``: Close, Esc and Done close the carousel and record only the slides actually viewed.

Each phase is one ``drive`` call (a launching phase runs inside the ``launch`` call's desktop-lock hold) and the UIA
tree dumped after it is checked with regular expressions (pips are named "Page N", so the slide count is asserted
through them) and ``first-run.json`` with predicates. Steps are UIA patterns
(``invoke``/``select``/``waitfor``/``waitgone``) except the ``keyboard`` scenario, which needs an unlocked console.

Usage (from the repository root, after ``tools/windows/build.ps1``)::

    python tools/windows/first_run_journey.py                       # every scenario
    python tools/windows/first_run_journey.py lifecycle replay-all  # by name
    python tools/windows/first_run_journey.py --shots out\\dir       # per-phase screenshots

Exit code 0 when every scenario passes, 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).resolve().parent))
import a11y_matrix  # noqa: E402  (tools/windows module: fixture service)
import journey_exe  # noqa: E402
import uiwin  # noqa: E402

Seen = dict[str, Any]

# region Model


@dataclass
class Phase:
    """One ``drive`` call and its checks.

    Attributes:
        steps: Step strings run in one ``drive`` call.
        expect: Regular expressions that must each match a line of the UIA tree dumped after the steps.
        forbid: Regular expressions that must not match any line of that tree.
        seen: Predicates over the saved ``first-run.json`` (name → check), evaluated after the steps.
        relaunch: Close and relaunch the app (same settings and data folder) before this phase.
        mutate: Rewrites ``first-run.json`` before the relaunch (e.g. an older slide version).
    """

    steps: list[str]
    expect: list[str] = field(default_factory=list)
    forbid: list[str] = field(default_factory=list)
    seen: dict[str, Callable[[Seen], bool]] = field(default_factory=dict)
    relaunch: bool = False
    mutate: Callable[[Seen], Seen] | None = None


@dataclass
class Scenario:
    """One scripted journey.

    Attributes:
        name: Short CLI name.
        state: Contract state(s) it covers.
        phases: Drive phases.
        tab: Launch section.
        settings: Settings written before the first launch.
        profile: ``FST_DEBUG_PROFILE`` (``id:Name``) for a selected player, else anonymous.
        preset: Window preset.
        fixture: Extra fixture-service flags; scenarios sharing flags share one fixture service.
    """

    name: str
    state: str
    phases: list[Phase]
    tab: str = "songs"
    settings: dict[str, Any] = field(default_factory=dict)
    profile: str | None = None
    preset: str = "medium"
    fixture: tuple[str, ...] = ()


DIALOG = "id=fst.first-run.dialog"
# The dialog's native Close command, tagged with the cross-platform test ID (issue #244; Apple/Android share it).
CLOSE = "fst.first-run.close"
OPEN = f"waitfor:{DIALOG}@30"
CLOSED = f"waitgone:{DIALOG}@10"
SONGS_READY = "waitfor:id=fst.songs.sort@30"
SETTINGS_READY = "waitfor:id=fst.settings.show-instrument-icons@30"


def _dialog(title: str) -> str:
    """Tree-line pattern for the carousel dialog titled with a page label."""
    return rf'"{re.escape(title)}" {DIALOG} '


def _pips(count: int) -> list[str]:
    """Patterns asserting exactly ``count`` pips (PipsPager names its buttons "Page N")."""
    return [rf'Button "Page {count}" ']


def _no_pip(count: int) -> str:
    """Pattern for a pip that must not exist."""
    return rf'Button "Page {count}" '


def _button(automation_id: str, name: str, enabled: bool = True) -> str:
    """Tree-line pattern for a dialog command with its name and enabled state."""
    state = r".*\[[^\]]*disabled" if not enabled else r"(?!.*disabled)"
    return rf'Button "{re.escape(name)}" id={automation_id} {state}'


def _slide(title: str) -> str:
    """Tree-line pattern for the selected FlipView slide (its UIA name is the slide title)."""
    return rf'ListItem "{re.escape(title)}" id= class=FlipViewItem .*selected'


def _demo(slide_id: str, status: str, seconds: float = 0) -> str:
    """``assertstatus`` step for a slide's live demo (raw UIA view): ``placeholder`` rows or ``catalogue`` songs."""
    return f"assertstatus:id=fst.first-run.demo.{slide_id}|{status}" + (f"@{seconds:g}" if seconds else "")


#: Seconds the ``late-catalogue`` fixture holds ``/api/songs``: long enough for the guide to open first.
SONGS_DELAY = 12

#: Every page's slides in Settings-replay (catalogue) order: each one has a live demo (issue #257).
PAGE_SLIDES = {
    "songs": ["songs-song-list", "songs-sort", "songs-navigation", "songs-filter", "songs-icons", "songs-metadata",
              "songs-shop-highlight", "songs-new-in-shop", "songs-leaving-tomorrow"],
    "songinfo": ["songinfo-chart", "songinfo-bar-select", "songinfo-view-all", "songinfo-top-scores", "songinfo-paths",
                 "songinfo-shop-button", "songinfo-new-in-shop", "songinfo-leaving-tomorrow"],
    "playerhistory": ["playerhistory-score-list", "playerhistory-sort"],
    "statistics": ["statistics-select-profile", "statistics-drill-down", "statistics-overview",
                   "statistics-instrument-breakdown", "statistics-percentiles", "statistics-top-songs"],
    "suggestions": ["suggestions-category-card", "suggestions-global-filter", "suggestions-instrument-filter",
                    "suggestions-infinite-scroll"],
    "leaderboards": ["leaderboards-overview", "leaderboards-experimental-metrics", "leaderboards-your-rank"],
    "compete": ["compete-hub", "compete-leaderboards", "compete-rivals"],
    "rivals": ["rivals-overview", "rivals-instruments", "rivals-detail"],
    "shop": ["shop-overview", "shop-highlighting", "shop-new-items", "shop-leaving-tomorrow"],
}

#: Seconds the ``catalogue-unavailable`` journey waits before asserting the demos are still placeholders.
UNAVAILABLE_WAIT = 8


def _demo_phases(status: str, pages: list[str] | None = None, settle: float = 0) -> list[Phase]:
    """Settings replay of each page's guide, paging through every slide and asserting each demo's data status.

    ``catalogue`` proves every demo, including Statistics' highest/lowest-rank songs, shows real catalogue songs
    (never invented titles); ``placeholder`` proves the demos stay redacted while the catalogue is unavailable.

    Args:
        status: Expected ``FirstRunDemos.DataStatus`` of every demo.
        pages: Page keys (default: every page).
        settle: Seconds to wait after each guide opens before the first check.

    Returns:
        An open-and-page phase and a close phase per page.
    """
    phases = []
    for index, key in enumerate(pages or list(PAGE_SLIDES)):
        row = f"id=fst.settings.first-run.{key}"
        steps = [SETTINGS_READY, "scrollinto:id=fst.settings.licenses", "wait:0.5"] if index == 0 else []
        steps += [f"scrollinto:{row}", f"invoke:{row}", OPEN, f"wait:{1 + settle:g}"]
        slides = PAGE_SLIDES[key]
        for number, slide in enumerate(slides):
            steps.append(_demo(slide, status, 15))
            if number < len(slides) - 1:
                steps += ["invoke:id=PrimaryButton", "wait:0.6"]
        phases.append(Phase(steps, expect=[_dialog(PAGE_TITLES[key]), _button("PrimaryButton", "Done")]))
        phases.append(Phase([f"invoke:id={CLOSE}", CLOSED, "wait:0.5"], forbid=[DIALOG]))
    return phases


def _older(slide_id: str) -> Callable[[Seen], Seen]:
    """Seen-state rewrite that records ``slide_id`` at version 0, as if the slide's replay version was bumped."""
    def rewrite(seen: Seen) -> Seen:
        seen[slide_id]["version"] = 0
        return seen
    return rewrite


SINGLE = [_button("PrimaryButton", "Done")]
# The dialog's Close, tagged or not; the window title bar's own Close (id=Close) is always in the tree.
NO_PAGING = [r"id=SecondaryButton ", r'Button "Close" id=(CloseButton|fst\.first-run\.close) ', r"id=fst\.first-run\.pips "]

# Settings "First Run Guides" rows (web pageKey → dialog title, the page's nav label; FirstRunPages.Label).
PAGE_TITLES = {
    "songs": "Songs", "songinfo": "Song Info", "playerhistory": "Player History", "statistics": "Statistics",
    "suggestions": "Suggestions", "leaderboards": "Leaderboards", "compete": "Compete", "rivals": "Rivals",
    "shop": "Item Shop",
}


def _title_phases() -> list[Phase]:
    """One Settings replay per page (issue #240): the dialog is announced with the page's title and keeps every command.

    Each phase opens a page's guide from its Settings row, asserts the UIA window name (what Narrator reads on open)
    beside the Next/Back/Close commands and pips, then closes it with the standard Close command.
    """
    phases = []
    for index, (key, title) in enumerate(PAGE_TITLES.items()):
        row = f"id=fst.settings.first-run.{key}"
        steps = [SETTINGS_READY, "scrollinto:id=fst.settings.licenses", "wait:0.5"] if index == 0 else []
        phases.append(Phase(
            [*steps, f"scrollinto:{row}", f"invoke:{row}", OPEN, "wait:1"],
            expect=[_dialog(title), _button("PrimaryButton", "Next"), _button("SecondaryButton", "Back", enabled=False),
                    _button(CLOSE, "Close"), r"id=fst\.first-run\.pips "],
        ))
        phases.append(Phase([f"invoke:id={CLOSE}", CLOSED, "wait:0.5"], forbid=[DIALOG]))
    return phases

SCENARIOS = [
    Scenario(
        name="lifecycle",
        state="dismissed, new-slides-only, hidden-all-seen",
        phases=[
            # Fresh anonymous Songs: six gate-passing slides; Back is present but disabled on slide 1.
            Phase([OPEN, "wait:1"],
                  expect=[_dialog("Songs"), *_pips(6), _slide("Song List"), _button("PrimaryButton", "Next"),
                          _button("SecondaryButton", "Back", enabled=False), _button(CLOSE, "Close")],
                  forbid=[_no_pip(7)]),
            Phase(["invoke:id=PrimaryButton", "wait:1"],
                  expect=[_button("SecondaryButton", "Back"), _button("PrimaryButton", "Next")]),
            # dismissed: Close records only the two slides viewed.
            Phase([f"invoke:id={CLOSE}", CLOSED, "wait:1"],
                  forbid=[DIALOG],
                  seen={"only the two viewed slides are seen": lambda s: len(s) == 2 and "songs-song-list" in s}),
            # new-slides-only: the four unviewed slides return alone on the next launch.
            Phase([OPEN, "wait:1"], relaunch=True,
                  expect=[_dialog("Songs"), *_pips(4)], forbid=[_no_pip(5), _slide("Song List")]),
            Phase(["invoke:id=PrimaryButton", "wait:0.5", "invoke:id=PrimaryButton", "wait:0.5",
                   "invoke:id=PrimaryButton", "wait:1"],
                  expect=[_button("PrimaryButton", "Done")]),
            Phase(["invoke:id=PrimaryButton", CLOSED, "wait:1"],
                  seen={"all six slides are seen": lambda s: len(s) == 6}),
            # hidden-all-seen: nothing shows once every gate-passing slide was viewed.
            Phase([SONGS_READY, "wait:6"], relaunch=True, forbid=[DIALOG]),
            # new-slides-only (version bump): only the bumped slide shows, as a one-slide guide.
            Phase([OPEN, "wait:1"], relaunch=True, mutate=_older("songs-song-list"),
                  expect=[_dialog("Songs"), _slide("Song List"), *SINGLE], forbid=NO_PAGING),
            Phase(["invoke:id=PrimaryButton", CLOSED, "wait:1"],
                  seen={"bumped slide re-recorded at its current version":
                        lambda s: s["songs-song-list"]["version"] >= 1 and len(s) == 6}),
        ],
    ),
    Scenario(
        name="gated-player",
        state="gated",
        profile="fixture-player-1:Demo Player",
        phases=[Phase([OPEN, "wait:1"], expect=[_dialog("Songs"), *_pips(9)], forbid=[_no_pip(10)])],
    ),
    Scenario(
        name="gated-shop-hidden",
        state="gated",
        settings={"hideShop": True},
        phases=[Phase([OPEN, "wait:1"], expect=[_dialog("Songs"), *_pips(3)], forbid=[_no_pip(4)])],
    ),
    Scenario(
        name="gated-single",
        state="gated",
        tab="leaderboards",
        phases=[
            Phase([OPEN, "wait:1"], expect=[_dialog("Leaderboards"), *SINGLE], forbid=NO_PAGING),
            Phase(["invoke:id=PrimaryButton", CLOSED, "wait:1"],
                  seen={"the one slide is seen": lambda s: list(s) == ["leaderboards-overview"]}),
        ],
    ),
    Scenario(
        name="waiting-not-ready",
        state="waiting-not-ready",
        tab="settings",
        phases=[
            Phase([SETTINGS_READY, "wait:1", "resize:minimized", "wait:1", "select:id=fst.nav.songs", "wait:4"],
                  forbid=[DIALOG], seen={"nothing seen while minimized": lambda s: not s}),
            Phase(["resize:restored", OPEN, "wait:1"], expect=[_dialog("Songs"), *_pips(6)]),
        ],
    ),
    Scenario(
        name="replay-all",
        state="replay-all, dismissed",
        tab="settings",
        phases=[
            Phase([SETTINGS_READY, "scrollinto:id=fst.settings.licenses", "wait:0.5", "scrollinto:id=fst.settings.first-run.songs",
                   "invoke:id=fst.settings.first-run.songs",
                   OPEN, "wait:1"],
                  # Anonymous, yet all nine Songs slides (three are player-gated): replay ignores gates.
                  expect=[_dialog("Songs"), *_pips(9), _slide("Song List")], forbid=[_no_pip(10)]),
            Phase(["invoke:id=PrimaryButton", "wait:0.5", "key:esc", CLOSED, "wait:1"],
                  seen={"Esc records only the two viewed slides": lambda s: len(s) == 2 and "songs-song-list" in s}),
            # Closing the replay counts as the page's one carousel this session; the next launch's visit shows only the
            # slides the replay left unviewed (the replay doesn't consume them).
            Phase(["select:id=fst.nav.songs", "wait:4"], forbid=[DIALOG]),
            Phase(["select:id=fst.nav.songs", OPEN, "wait:1"], relaunch=True,
                  expect=[_dialog("Songs"), *_pips(4)], forbid=[_no_pip(5)]),
        ],
    ),
    Scenario(
        name="titles",
        state="replay-all (every page title)",
        tab="settings",
        preset="compact",
        phases=_title_phases(),
    ),
    Scenario(
        name="late-catalogue",
        state="visible (catalogue arrives after the guide opens)",
        fixture=("--songs-delay", str(SONGS_DELAY)),
        phases=[
            # The guide opens before the catalogue: the visible demo shows redacted placeholder rows...
            Phase([OPEN, "wait:1", _demo("songs-song-list", "placeholder")], expect=[_dialog("Songs"), _slide("Song List")]),
            # ...and swaps in catalogue songs once it arrives. WinUI's stale Unloaded used to detach the visible demo
            # from the catalogue so it stayed blank (issue #240).
            Phase([_demo("songs-song-list", "catalogue", SONGS_DELAY + 20)], expect=[_slide("Song List")]),
            Phase(["invoke:id=PrimaryButton", "wait:1", _demo("songs-sort", "catalogue", 5)], expect=[_slide("Sort Songs")]),
        ],
    ),
    Scenario(
        name="demo-songs",
        state="visible (every demo shows catalogue songs)",
        tab="settings",
        phases=_demo_phases("catalogue"),
    ),
    Scenario(
        name="catalogue-unavailable",
        state="visible (catalogue unavailable: placeholder demos)",
        tab="settings",
        fixture=("--songs-unavailable",),
        # Song rows (Songs), highest/lowest-rank songs (Statistics) and the one-line song mentions of the Suggestions
        # card and Rival detail keep redacted placeholders, never invented or untitled songs.
        phases=_demo_phases("placeholder", ["songs", "statistics", "suggestions", "rivals"], settle=UNAVAILABLE_WAIT),
    ),
    Scenario(
        name="keyboard",
        state="dismissed (keyboard)",
        phases=[
            # Enter activates the default Next; Tab reaches Back once enabled; Esc closes.
            Phase([OPEN, "wait:1", "key:enter", "wait:1"],
                  expect=[_button("SecondaryButton", "Back"), _slide("Sort Songs")]),
            Phase(["key:esc", CLOSED, "wait:1"], forbid=[DIALOG],
                  seen={"keyboard close records the two viewed slides": lambda s: len(s) == 2}),
        ],
    ),
]

# endregion

# region Runner


def check_tree(text: str, phase: Phase) -> list[str]:
    """Failures for one phase's tree dump.

    Args:
        text: UIA tree dump (one element per line).
        phase: Phase with ``expect``/``forbid`` patterns.

    Returns:
        Failure messages (empty when the tree matches).
    """
    lines = text.splitlines()
    failures = [f"expected /{p}/ in the UIA tree" for p in phase.expect if not any(re.search(p, line) for line in lines)]
    failures += [f"did not expect /{p}/ in the UIA tree" for p in phase.forbid if any(re.search(p, line) for line in lines)]
    return failures


def load_seen(path: Path) -> Seen:
    """Reads ``first-run.json`` (missing means nothing seen yet)."""
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def check_seen(path: Path, phase: Phase) -> list[str]:
    """Failures for one phase's seen-state predicates.

    Args:
        path: The isolated ``first-run.json``.
        phase: Phase with ``seen`` predicates.

    Returns:
        Failure messages (empty when every predicate holds or there are none).
    """
    if not phase.seen:
        return []
    try:
        seen = load_seen(path)
    except (OSError, ValueError) as error:
        return [f"first-run.json unreadable: {error}"]
    failures = []
    for name, check in phase.seen.items():
        try:
            ok = check(seen)
        except (IndexError, KeyError, TypeError):
            ok = False
        if not ok:
            failures.append(f"seen-state: {name} failed (saved: {sorted(seen)})")
    return failures


def _uiwin(*args: str) -> str:
    """Runs ``uiwin.py`` and returns stdout; raises on failure."""
    import subprocess
    result = subprocess.run([sys.executable, str(Path(uiwin.__file__)), *args], capture_output=True, text=True,
                            encoding="utf-8", env={**__import__("os").environ, "PYTHONIOENCODING": "utf-8",
                                                   "MSYS_NO_PATHCONV": "1"})
    if result.returncode != 0:
        raise RuntimeError(f"uiwin {args[0]} exited {result.returncode}: "
                           f"{(result.stderr.strip() or result.stdout.strip())[-800:]}")
    return result.stdout


def _close_last() -> None:
    """Closes the app this worktree launched last (best effort; nothing may be running)."""
    try:
        _uiwin("close")
    except RuntimeError:
        pass


def launch(exe: Path, port: int, scenario: Scenario, settings: Path, data: Path, steps: list[str]) -> int:
    """Launches the app for a scenario, runs a phase's steps in the same desktop-lock hold and returns its pid.

    Running the launching phase's steps in the launch's hold keeps timing-sensitive first checks (such as the
    ``late-catalogue`` placeholder rows) from queueing behind another lane's lock use.
    """
    extra = ["--extra", f"FST_DEBUG_DATA_DIR={data}"]
    if scenario.profile:
        extra += ["--extra", f"FST_DEBUG_PROFILE={scenario.profile}"]
    out = _uiwin("launch", str(exe), "--arg=--base-url", f"--arg=http://127.0.0.1:{port}/", "--arg=--settings-path",
                 f"--arg={settings}", "--arg=--first-run=on", "--arg=--tab", f"--arg={scenario.tab}",
                 "--preset", scenario.preset, *extra, "--steps", "; ".join(steps))
    match = re.search(r'"pid":\s*(\d+)', out)
    if not match:
        raise RuntimeError(f"no pid in launch output: {out}")
    return int(match.group(1))


def run(scenario: Scenario, exe: Path, port: int, shots: Path | None) -> list[str]:
    """Runs one scenario and returns failure messages (empty when it passed)."""
    failures: list[str] = []
    work = Path(tempfile.mkdtemp(prefix=f"fst-first-run-{scenario.name}-"))
    settings, data = work / "settings.json", work / "data"
    data.mkdir()
    seen_file = data / "first-run.json"
    if scenario.settings:
        settings.write_text(json.dumps(scenario.settings), encoding="utf-8")
    pid = None
    try:
        for index, phase in enumerate(scenario.phases):
            if phase.relaunch and pid is not None:
                _uiwin("close", "--pid", str(pid))
                pid = None
            if phase.mutate is not None:
                seen_file.write_text(json.dumps(phase.mutate(load_seen(seen_file))), encoding="utf-8")
            tree = work / f"tree-{index}.txt"
            steps = [*phase.steps, f"tree:{tree}"]
            if shots is not None:
                steps.append(f"shot:{shots / f'first-run-{scenario.name}-{index}.png'}")
            try:
                if pid is None:
                    try:
                        pid = launch(exe, port, scenario, settings, data, steps)
                    except RuntimeError:
                        # The launch may have succeeded before a step failed: close the worktree's last launch.
                        _close_last()
                        raise
                else:
                    _uiwin("drive", "--pid", str(pid), "--steps", "; ".join(steps))
            except RuntimeError as error:
                failures.append(f"phase {index}: {error}")
                break
            text = tree.read_text(encoding="utf-8", errors="replace") if tree.exists() else ""
            failures += [f"phase {index}: {f}" for f in check_tree(text, phase) + check_seen(seen_file, phase)]
    except RuntimeError as error:
        failures.append(str(error))
    finally:
        if pid is not None:
            try:
                _uiwin("close", "--pid", str(pid))
            except RuntimeError:
                pass
    if not failures:
        shutil.rmtree(work, ignore_errors=True)
    else:
        failures.append(f"artifacts: {work}")
    return failures


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        0 when all selected scenarios pass, else 1.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*", help="scenarios to run (default: all)")
    journey_exe.add_argument(parser)
    parser.add_argument("--shots", type=Path, help="directory for per-phase screenshots")
    args = parser.parse_args(argv)
    selected = [s for s in SCENARIOS if not args.names or s.name in args.names]
    if args.shots:
        args.shots.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="fst-first-run-fixture-"))
    failed = 0
    for group, flags in enumerate(dict.fromkeys(s.fixture for s in selected)):
        fixture, port = a11y_matrix.start_fixture(work / f"fixture-{group}.log", flags)
        try:
            for scenario in (s for s in selected if s.fixture == flags):
                failures = run(scenario, args.exe.resolve(), port, args.shots.resolve() if args.shots else None)
                print(f"{'PASS' if not failures else 'FAIL'} {scenario.name} ({scenario.state})", flush=True)
                for failure in failures:
                    print(f"  - {failure}", flush=True)
                failed += bool(failures)
        finally:
            fixture.kill()
    print(f"{len(selected) - failed}/{len(selected)} scenarios passed")
    return 1 if failed else 0

# endregion


if __name__ == "__main__":
    sys.exit(main())
