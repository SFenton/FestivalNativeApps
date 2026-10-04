"""Suggestions UI journeys on Windows: every reachable page state through uiwin.py (FlaUI driver).

Starts ``suggestions_fixture_server.py`` (synthetic catalogue, no real player data) on a private loopback port, then
for each scenario launches the Debug app with a fixed mix seed, an isolated data folder and a debug profile, drives
it by ``fst.*`` AutomationIds and fails on the first missing element. Scenarios cover the loaded list across
window presets, keyboard navigation (Tab per card, Up/Down per row, Esc focus return), the filter flyout (Axe scan
open), the filtered-empty state and its Reset, incremental loading, the end of a mix and Start New Mix, row ->
Song Detail -> back, the redirect without a selected player, the loading, syncing (202) and denied (403) states and
an unreachable service with Retry. Steps are UIA patterns or posted keys, so the journeys also run while the console
is locked (screenshots are then black: pass ``--shots`` only on an unlocked desktop). Axe scans must report 0 errors.

Usage: ``python tools/windows/suggestions_journey.py [--port 18767] [--shots DIR] [--only NAME] [--sizes compact,medium,wide]``
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import journey_exe  # noqa: E402  (sibling module)

ROOT = Path(__file__).resolve().parents[2]
UIWIN = ROOT / "tools" / "windows" / "uiwin.py"
WORK = Path(tempfile.gettempdir()) / "fst-suggestions-journey"
PROFILE = "fixture-suggest"
ROW = "id=fst.suggestions.row.s044|Solo_PeripheralGuitar"
ROW2 = "id=fst.suggestions.row.s032|Solo_PeripheralGuitar"
LAST_ROW = "id=fst.suggestions.row.s001|Solo_PeripheralGuitar"
CARD = "id=fst.suggestions.category.stale_Solo_PeripheralGuitar_2"
NEXT_CARD_ROW = "id=fst.suggestions.row.s091"
TENTH_CARD = "id=fst.suggestions.category.unplayed_Solo_PeripheralGuitar"
RIVAL_CARD = "id=fst.suggestions.category.song_rival_gap_rival-below-0"
TWELFTH_CARD = RIVAL_CARD
TYPES = ("nearFC", "starProgress", "unplayed", "varietyPack", "artistEssentials", "artistDiscover", "sameName",
         "almostElite", "percentilePush", "stale", "pctImprove", "nearMax", "songRivals")
LOADED = [f"waitfor:{ROW}@30", f"waitfor:{CARD}@5", "waitfor:id=fst.suggestions.filter-button@5"]

# name -> (profile or None for anonymous, extra environment, steps). {shot:NAME} placeholders become screenshots
# with --shots; {port} is the fixture port.
SCENARIOS: dict[str, tuple[str | None, dict[str, str], list[str]]] = {
    "loaded": (PROFILE, {}, [*LOADED, "{shot:loaded}"]),
    "resize": (
        PROFILE,
        {},
        [
            *LOADED,
            # The list, its cards and the header survive every breakpoint, maximized and both snaps.
            *[step for preset in ("compact", "wide", "maximized", "snap-left", "snap-right", "medium")
              for step in (f"resize:{preset}", f"waitfor:{CARD}@10", "waitfor:id=fst.suggestions.filter-button@5",
                           f"{{shot:resize-{preset}}}")],
        ],
    ),
    "keyboard": (
        PROFILE,
        {},
        [
            *LOADED,
            # Rows: Up/Down, also across cards (design/windows.md Collections).
            f"focus:{ROW}", "key:down", f"assertfocus:{ROW2}", "key:up", f"assertfocus:{ROW}",
            f"focus:{LAST_ROW}", "key:down", f"assertfocus:{NEXT_CARD_ROW}", "key:up", f"assertfocus:{LAST_ROW}",
            # Cards: one Tab stop each; Shift+Tab back to the first card, then the Filter button.
            f"focus:{ROW}", "key:tab", f"assertfocus:{NEXT_CARD_ROW}", "key:shift+tab", f"assertfocus:{ROW}",
            "key:shift+tab", "assertfocus:id=fst.suggestions.filter-button",
            # Enter opens the filter; Esc closes it and returns focus to its button.
            "key:enter", "waitfor:id=fst.suggestions.filter.instruments@10", "key:esc",
            "waitgone:id=fst.suggestions.filter.instruments@10", "assertfocus:id=fst.suggestions.filter-button",
        ],
    ),
    "filter": (
        PROFILE,
        {},
        [
            *LOADED,
            "invoke:id=fst.suggestions.filter-button",
            "waitfor:id=fst.suggestions.filter.instruments@10",
            "expand:id=fst.suggestions.filter.instruments",
            "expand:id=fst.suggestions.filter.general",
            "{shot:filter-open}",
            "scan:{scans}/filter-open",
            # Live apply: hiding Pro Lead drops its card; Reset brings it back.
            "toggle:id=fst.suggestions.filter.instrument.Solo_PeripheralGuitar",
            f"waitgone:{CARD}@10",
            "{shot:filter-applied}",
            "invoke:id=fst.suggestions.filter.reset",
            "key:esc",
            "waitgone:id=fst.suggestions.filter.instruments@10",
            f"waitfor:{CARD}@10",
        ],
    ),
    "filtered-empty": (
        PROFILE,
        {},
        [
            *LOADED,
            "invoke:id=fst.suggestions.filter-button",
            "waitfor:id=fst.suggestions.filter.instruments@10",
            # Every suggestion type off (instrument switches alone keep the instrument-free artist cards).
            "expand:id=fst.suggestions.filter.general",
            *[step for kind in TYPES for step in (f"scrollinto:id=fst.suggestions.filter.type.{kind}",
                                                  f"toggle:id=fst.suggestions.filter.type.{kind}")],
            "key:esc",
            "waitgone:id=fst.suggestions.filter.instruments@10",
            "waitfor:id=fst.suggestions.no-results@10",
            "waitfor:id=fst.suggestions.reset-filters@5",
            "{shot:filtered-empty}",
            "scan:{scans}/filtered-empty",
            "invoke:id=fst.suggestions.reset-filters",
            f"waitfor:{CARD}@15",
        ],
    ),
    "load-more": (
        PROFILE,
        {},
        [*LOADED, f"scrollinto:{TENTH_CARD}", f"scrollinto:{RIVAL_CARD}@15", f"waitfor:{RIVAL_CARD}@10",
         "{shot:load-more}"],
    ),
    "end-of-mix": (
        PROFILE,
        {"FST_DEBUG_SUGGESTIONS_LIMIT": "12"},
        [
            *LOADED,
            # Realizing the last of the 12 capped cards asks for more, which hits the cap and shows the footer.
            f"scrollinto:{TENTH_CARD}",
            f"scrollinto:{TWELFTH_CARD}@15",
            "scrollinto:id=fst.suggestions.start-new-mix@15",
            "waitfor:id=fst.suggestions.start-new-mix@15",
            "{shot:end-of-mix}",
            "scan:{scans}/end-of-mix",
            "invoke:id=fst.suggestions.start-new-mix",
            "waitgone:id=fst.suggestions.start-new-mix@15",
            "waitfor:id=fst.suggestions.list@10",
        ],
    ),
    "song-detail": (
        PROFILE,
        {},
        [*LOADED, f"invoke:{ROW}", "waitfor:id=fst.song-detail.title@20", "key:alt+left", f"waitfor:{CARD}@15"],
    ),
    "no-player": (
        None,
        {},
        # Player-only routes redirect to the Songs root without a profile (web RequirePlayer guard), so the page's
        # own "Select a Player" panel is a defensive state the shell never shows.
        ["waitfor:id=fst.songs.list@30", "waitgone:id=fst.suggestions.filter-button@5", "{shot:no-player}"],
    ),
    "loading": (
        f"{PROFILE}-slow",
        {},
        # The slow account answers after 120 s, so the spinner outlasts other lanes' turns on the desktop lock; the
        # loaded transition itself is covered by every other scenario.
        ["waitfor:id=fst.suggestions.loading@30", "waitgone:id=fst.suggestions.filter-button@2", "{shot:loading}",
         "scan:{scans}/loading"],
    ),
    "syncing": (
        f"{PROFILE}-syncing",
        {},
        ["waitfor:id=fst.suggestions.syncing@30", "{shot:syncing}", "scan:{scans}/syncing"],
    ),
    "denied": (
        f"{PROFILE}-denied",
        {},
        ["waitfor:name=Suggestions Unavailable@30", "waitfor:id=fst.service-status.retry@10", "{shot:denied}",
         "scan:{scans}/denied"],
    ),
    "offline": (
        PROFILE,
        {"base-url": "http://127.0.0.1:9/"},
        ["waitfor:name=You're offline@45", "waitfor:id=fst.service-status.retry@10", "{shot:offline}",
         "invoke:id=fst.service-status.retry", "waitfor:name=You're offline@45",
         "waitfor:id=fst.service-status.retry@45"],
    ),
}


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


def expand(steps: list[str], shots: Path | None, size: str, scans: Path) -> list[str]:
    """Replaces ``{shot:NAME}`` and ``{scans}`` placeholders.

    Args:
        steps: Scenario steps.
        shots: Screenshot directory, or ``None`` to drop shots.
        size: Window preset name used in file names.
        scans: Axe scan output directory.

    Returns:
        Steps ready for ``uiwin.py drive``.
    """
    out = []
    for step in steps:
        if step.startswith("{shot:"):
            if shots is not None:
                out.append(f"shot:{shots / (step[6:-1] + '-' + size + '.png')}")
            continue
        out.append(step.replace("{scans}", scans.as_posix()))
    return out


def launch_args(name: str, port: int, size: str, exe: Path) -> list[str]:
    """Builds the ``uiwin.py launch`` arguments for a scenario.

    Args:
        name: Scenario key.
        port: Fixture port.
        size: Window preset.
        exe: App executable.

    Returns:
        Arguments after ``uiwin.py``.
    """
    profile, env, _ = SCENARIOS[name]
    data = WORK / name
    shutil.rmtree(data, ignore_errors=True)
    data.mkdir(parents=True)
    base = env.get("base-url", f"http://127.0.0.1:{port}/")
    # --first-run=off: the first-run carousel is modal and would swallow the scripted input. An isolated data
    # folder gives default settings (all nine charts) and an unfiltered mix on every run.
    args = ["launch", str(exe), "--timeout", "60", "--wait", "1", "--preset", size, "--route", "/suggestions",
            f"--arg=--base-url={base}", "--arg=--first-run=off", f"--arg=--settings-path={data / 'settings.json'}",
            "--extra", f"FST_DEBUG_DATA_DIR={data}", "--extra", "FST_DEBUG_SUGGESTIONS_SEED=1"]
    args += [f"--arg=--profile={profile}:Fixture Player"] if profile else ["--arg=--anonymous"]
    for key, value in env.items():
        if key.startswith("FST_"):
            args += ["--extra", f"{key}={value}"]
    return args


def run(name: str, port: int, shots: Path | None, size: str, exe: Path) -> None:
    """Launches, drives and closes one scenario.

    Args:
        name: Scenario key.
        port: Fixture port.
        shots: Screenshot directory, if any.
        size: Window preset.
        exe: App executable.

    Raises:
        RuntimeError: A step failed (a failure screenshot and UIA tree are saved).
    """
    scans = (shots or WORK) / "axe" / f"{name}-{size}"
    uiwin(*launch_args(name, port, size, exe))
    try:
        steps = expand(SCENARIOS[name][2], shots, size, scans)
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as handle:
            handle.write("\n".join(steps))
        try:
            output = uiwin("drive", "--steps-file", handle.name)
        except RuntimeError:
            evidence = shots or WORK
            for command, suffix in (("shot", ".png"), ("tree", ".txt")):
                try:
                    uiwin(command, str(evidence / f"FAILED-{name}-{size}{suffix}"))
                except RuntimeError:
                    pass
            raise
        finally:
            Path(handle.name).unlink(missing_ok=True)
        if " error(s)" in output and any(line.startswith("scan ") and not line.endswith(" 0 error(s)")
                                         for line in output.splitlines()):
            raise RuntimeError(f"Axe errors:\n{output}")
        print(f"PASS {name} [{size}]")
    finally:
        uiwin("close")


def main() -> int:
    """Runs the selected scenarios.

    Returns:
        Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=18767)
    parser.add_argument("--shots", type=Path)
    parser.add_argument("--only", choices=sorted(SCENARIOS), action="append")
    parser.add_argument("--sizes", default="medium", help="comma-separated presets for the loaded journey")
    journey_exe.add_argument(parser)
    options = parser.parse_args()
    server = subprocess.Popen([sys.executable, str(ROOT / "tools" / "windows" / "suggestions_fixture_server.py"),
                               "--port", str(options.port), "--slow-seconds", "120"],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    failures = 0
    try:
        for _ in range(50):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{options.port}/api/publication", timeout=1)
                break
            except OSError:
                time.sleep(0.2)
        WORK.mkdir(parents=True, exist_ok=True)
        if options.shots:
            options.shots.mkdir(parents=True, exist_ok=True)
        for name in options.only or list(SCENARIOS):
            for size in options.sizes.split(",") if name == "loaded" else ["medium"]:
                try:
                    run(name, options.port, options.shots, size, options.exe)
                except RuntimeError as error:
                    failures += 1
                    print(f"FAIL {name} [{size}]: {error}")
    finally:
        server.terminate()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
