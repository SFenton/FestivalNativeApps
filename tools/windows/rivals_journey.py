"""Rivals UI journeys on Windows: state and navigation checks through uiwin.py (FlaUI driver).

Starts ``rivals_fixture.py`` (anonymized mock service) on a private loopback port, then for each scenario
launches the Debug app with an in-memory debug profile, drives it by ``fst.*`` AutomationIds and fails on the
first missing element (``waitfor:``). Scenarios cover every Rivals page state: populated hub (both tabs, Jump
To), Rival Detail -> Rivalry (sort) -> All Rivals navigation, empty lists, a 503 scrape freeze (inline and
page-level status), no selected player and the ``/compete`` deep link, the per-card loading rings and their
replacement by rows or the inline freeze (a slow fixture account), plus the Rivalry page's own states
(deep link with the labelled sort, keyboard row activation to Song Detail and back, unknown category, empty,
freeze and no player). With ``--shots DIR`` it also captures compact/medium/wide screenshots of the populated
journey.

Usage: ``python tools/windows/rivals_journey.py [--port 18743] [--shots DIR] [--only NAME[,NAME...]]``
"""

from __future__ import annotations

import argparse
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
EXE = journey_exe.DEBUG_EXE
RIVAL = "f1c749eb07c32578cfa3e59ec38c03a8"
LEADERBOARD_RIVAL = "f1c71052e0052ae7143f3b3c750f2f49"  # rank 2 in contracts/fixtures/leaderboard-rivals-demo.json
# Narrator name of RIVAL's row (rivals-list-demo.json, renamed by rivals_fixture.py): ahead/behind, never a shared count (#67, #267).
RIVAL_NAME = "Demo Rival 1, ahead of you, 128 songs ahead, 243 songs behind"

# name -> (environment, route, steps). {shot:NAME} placeholders become screenshots when --shots is given.
SCENARIOS: dict[str, tuple[dict[str, str], str | None, list[str]]] = {
    "populated": (
        {"FST_DEBUG_PROFILE": "fixture-player-1:Demo Player"},
        "/rivals",
        [
            "waitfor:id=fst.rivals.section.common@20",
            f"waitfor:id=fst.rivals.row.{RIVAL}@10",
            f"assertname:id=fst.rivals.row.{RIVAL}|{RIVAL_NAME}",
            "{shot:hub}",
            "select:id=fst.rivals.tab.leaderboard",
            "waitfor:id=fst.rivals.section.leaderboard.Solo_Guitar@10",
            # The row is one Narrator stop ("<name>, rank 2, …"); its "#2" text part is Raw (issue #200).
            f"waitfor:id=fst.rivals.row.{LEADERBOARD_RIVAL}@10",
            "{shot:hub-leaderboard}",
            "select:id=fst.rivals.tab.song",
            "waitfor:id=fst.rivals.section.common@10",
            f"invoke:id=fst.rivals.row.{RIVAL}",
            "waitfor:id=fst.rival-detail.category.closest_battles@15",
            "waitfor:id=fst.rival-detail.view-profile@10",
            "{shot:detail}",
            "invoke:id=fst.rival-detail.see-all",
            "waitfor:id=fst.rivalry.list@15",
            "waitfor:id=fst.rivalry.song.fixture-pulse.Solo_Guitar@10",
            "expand:id=fst.rivalry.sort",
            "waitfor:name=Your Biggest Leads@10",
            "click:name=Your Biggest Leads",
            "waitfor:id=fst.rivalry.song.fixture-echo.Solo_Guitar@10",
            "{shot:rivalry}",
            "key:alt+left",
            "waitfor:id=fst.rival-detail.title@10",
            "key:alt+left",
            "waitfor:id=fst.rivals.see-all@10",
            "invoke:id=fst.rivals.see-all",
            "waitfor:id=fst.all-rivals.list@15",
            f"waitfor:id=fst.all-rivals.row.{RIVAL}@10",
            f"assertname:id=fst.all-rivals.row.{RIVAL}|{RIVAL_NAME}",
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
        ["waitfor:id=fst.service-status.title@20", "waitfor:id=fst.service-status.countdown@10", "{shot:freeze}"],
    ),
    "no-player": (
        {"FST_DEBUG_ANONYMOUS": "1"},
        f"/rivals/{RIVAL}",
        # Player-only routes redirect to the Songs root without a profile (web RequirePlayer guards).
        ["waitfor:id=fst.songs.search@20", "waitfor:id=fst.songs.list@20", "{shot:no-player}"],
    ),
    "quick-links": (
        {"FST_DEBUG_PROFILE": "fixture-player-1:Demo Player"},
        "/rivals",
        [
            # Menu below 1150 epx of page area, persistent pane from it (.agents/controls/quick-links/windows.md).
            "resize:medium",
            "waitfor:id=fst.rivals.section.common@20",
            "invoke:id=fst.quick-links.open",
            "waitfor:id=fst.quick-links.item.Solo_Bass@10",
            "invoke:id=fst.quick-links.item.Solo_Bass",
            "wait:1",
            "{shot:quick-links-medium}",
            "resize:wide",
            "waitfor:id=fst.quick-links.list@10",
            "click:id=fst.quick-links.item.common",
            "wait:1",
            "{shot:quick-links-wide}",
        ],
    ),
    # View All Rivals is the shared accent View all button (issue #268): a UIA Button whose name starts with its visible
    # label, one per card with its own ID, on both tabs; it opens All Rivals for the card's scope and Back returns.
    "view-all": (
        {"FST_DEBUG_PROFILE": "fixture-player-1:Demo Player"},
        "/rivals",
        [
            "waitfor:id=fst.rivals.section.common@20",
            "scrollinto:id=fst.rivals.section.common.view-all@10",
            "assertstate:id=fst.rivals.section.common.view-all|type=button",
            "assertstate:id=fst.rivals.section.common.view-all|name=View All Rivals, Common Rivals",
            "assertstate:id=fst.rivals.section.common.view-all|invoke=true",
            "assertstate:id=fst.rivals.section.common.view-all|focusable=true",
            "scrollinto:id=fst.rivals.section.Solo_Guitar.view-all@10",
            "assertstate:id=fst.rivals.section.Solo_Guitar.view-all|name=View All Rivals, Lead Rivals",
            "{shot:view-all}",
            "invoke:id=fst.rivals.section.Solo_Guitar.view-all",
            "waitfor:id=fst.all-rivals.list@15",
            f"waitfor:id=fst.all-rivals.row.{RIVAL}@10",
            "key:alt+left",
            "waitfor:id=fst.rivals.section.Solo_Guitar.view-all@10",
            "select:id=fst.rivals.tab.leaderboard",
            "scrollinto:id=fst.rivals.section.leaderboard.Solo_Guitar.view-all@10",
            "assertstate:id=fst.rivals.section.leaderboard.Solo_Guitar.view-all|name=View All Rivals, Lead Rivals",
            "{shot:view-all-leaderboard}",
            "invoke:id=fst.rivals.section.leaderboard.Solo_Guitar.view-all",
            "waitfor:id=fst.all-rivals.list@15",
            "waitfor:name=Ranked by Total Score · You are #1@10",
        ],
    ),
    "compete": (
        {"FST_DEBUG_PROFILE": "fixture-player-1:Demo Player"},
        "/compete",
        [
            "waitfor:id=fst.rivals.title@20",
            "waitfor:id=fst.rivals.section.common@20",
            f"waitfor:id=fst.rivals.row.{RIVAL}@10",
            # Masonry rows share a top: the first card of the row is current, not its right-hand neighbour (#213).
            "waitfor:name=Quick Links, current section Common Rivals@10",
            "{shot:compete}",
        ],
    ),
    # Per-card loading (issues #65/#265): the slow account holds every list read for SLOW_RIVALS_SECONDS, so each
    # card shows its named ProgressRing (UIA ProgressBar; WinUI prefixes "Busy" to an active ring's name) until rows
    # replace it, on both tabs.
    "loading": (
        {"FST_DEBUG_PROFILE": "fixture-player-slow:Demo Player"},
        "/compete",
        [
            "waitfor:id=fst.rivals.section.common.loading@20",
            "waitfor:id=fst.rivals.section.Solo_Guitar.loading@5",
            "assertstate:id=fst.rivals.section.common.loading|name=Busy Loading Common Rivals",
            "assertstate:id=fst.rivals.section.Solo_Guitar.loading|type=progressbar",
            "assertstate:id=fst.rivals.section.Solo_Guitar.loading|focusable=false",
            "assertstate:id=fst.rivals.section.Solo_Guitar.loading|name=Busy Loading Lead Rivals",
            # assertstate also reads cards scrolled out of view.
            "assertstate:id=fst.rivals.section.Solo_PeripheralDrums.loading|name=Busy Loading Pro Drums Rivals",
            "waitgone:id=fst.rivals.section.common.view-all@2",
            "{shot:loading}",
            # Four reads run at a time, so Lead (first wave) settles while Common Rivals, which needs every list,
            # keeps its ring: sections load independently.
            "waitgone:id=fst.rivals.section.Solo_Guitar.loading@30",
            f"waitfor:id=fst.rivals.row.{RIVAL}@5",
            "waitfor:id=fst.rivals.section.common.loading@2",
            "waitgone:id=fst.rivals.section.common.loading@45",
            "waitgone:id=fst.service-status.inline@2",
            "select:id=fst.rivals.tab.leaderboard",
            "waitfor:id=fst.rivals.section.leaderboard.Solo_Guitar.loading@10",
            "assertstate:id=fst.rivals.section.leaderboard.Solo_Guitar.loading|name=Busy Loading Lead Rivals",
            "waitgone:id=fst.rivals.section.leaderboard.Solo_Guitar.loading@30",
            f"waitfor:id=fst.rivals.row.{LEADERBOARD_RIVAL}@5",
        ],
    ),
    # The ring gives way to the inline freeze status when the slow read finally answers 503.
    "loading-freeze": (
        {"FST_DEBUG_PROFILE": "fixture-player-slow-503:Demo Player"},
        "/rivals",
        [
            "waitfor:id=fst.rivals.section.common.loading@20",
            "waitgone:id=fst.service-status.inline@2",
            "waitfor:name=Lead Rivals Unavailable@45",
            "waitgone:id=fst.rivals.section.Solo_Guitar.loading@3",
            "waitfor:name=Common Rivals Unavailable@45",
            "waitgone:id=fst.rivals.section.common.loading@3",
            "{shot:loading-freeze}",
        ],
    ),
    "compete-no-player": (
        {"FST_DEBUG_ANONYMOUS": "1"},
        "/compete",
        # Like /rivals, the player-only /compete route lands on the Songs root without a profile.
        ["waitfor:id=fst.songs.search@20", "waitfor:id=fst.songs.list@20", "{shot:compete-no-player}"],
    ),
    # Rival Detail's own states and edges (issue #202): no shared songs, then every way off the page.
    "detail-empty": (
        {"FST_DEBUG_PROFILE": "fixture-player-empty:Demo Player"},
        f"/rivals/{RIVAL}?scope=song%3ASolo_Guitar",
        ["waitfor:id=fst.rivals.page-empty@20", "waitgone:id=fst.rival-detail.summary@5", "{shot:detail-empty}"],
    ),
    "detail-nav": (
        {"FST_DEBUG_PROFILE": "fixture-player-1:Demo Player"},
        f"/rivals/{RIVAL}",
        [
            # Compact: header stacks and Quick Links is a menu (the web offers it on mobile only).
            "resize:compact",
            "waitfor:id=fst.rival-detail.summary@20",
            "waitfor:id=fst.rival-detail.category.closest_battles@10",
            "invoke:id=fst.quick-links.open",
            "waitfor:id=fst.quick-links.item.rival-category:pulling_forward@10",
            # Toggle, as Narrator's default action does: radio menu items expose no Invoke pattern.
            "toggle:id=fst.quick-links.item.rival-category:pulling_forward",
            "waitfor:id=fst.rival-detail.category.pulling_forward@10",
            "{shot:detail-quick-links}",
            # Song row -> Song Detail on the compared chart, Back returns to the detail.
            "scrollinto:id=fst.rivalry.song.fixture-echo.Solo_Guitar@10",
            "invoke:id=fst.rivalry.song.fixture-echo.Solo_Guitar",
            # The rivals fixture serves no song catalogue, so Song Detail opens in its "Song unavailable" state.
            "waitfor:name=Song unavailable@15",
            "key:alt+left",
            "waitfor:id=fst.rival-detail.title@10",
            # View Profile -> the rival's player page.
            "scrollinto:id=fst.rival-detail.view-profile@10",
            "invoke:id=fst.rival-detail.view-profile",
            # Nor player profiles: the Player page opens in its "Profile unavailable" state.
            "waitfor:id=fst.player@20",
            "waitfor:name=Profile unavailable@10",
            "key:alt+left",
            "waitfor:id=fst.rival-detail.title@10",
        ],
    ),
    # Rivalry page states (issue #203): deep link, labelled sort, keyboard row activation and back.
    "rivalry": (
        {"FST_DEBUG_PROFILE": "fixture-player-1:Demo Player"},
        f"/rivals/{RIVAL}/rivalry?mode=closest_battles",
        [
            "waitfor:id=fst.rivalry.title@20",
            "waitfor:id=fst.rivalry.song.fixture-pulse.Solo_Guitar@15",
            "waitfor:name=Sort By@10",
            "waitfor:id=fst.rivalry.view-profile@10",
            "expand:id=fst.rivalry.sort",
            "waitfor:name=Their Biggest Leads@10",
            "click:name=Their Biggest Leads",
            "waitfor:id=fst.rivalry.song.fixture-echo.Solo_Guitar@10",
            "{shot:rivalry-sorted}",
            "focus:id=fst.rivalry.song.fixture-echo.Solo_Guitar",
            "assertfocus:id=fst.rivalry.song.fixture-echo.Solo_Guitar",
            "key:enter",
            # Song Detail opens; the rivals fixture serves no song endpoints, so it shows its unavailable state.
            "waitgone:id=fst.rivalry.list@15",
            "waitfor:name=Song unavailable@15",
            "key:alt+left",
            "waitfor:id=fst.rivalry.list@10",
        ],
    ),
    "rivalry-unknown-mode": (
        {"FST_DEBUG_PROFILE": "fixture-player-1:Demo Player"},
        f"/rivals/{RIVAL}/rivalry?mode=not_a_category",
        # Unknown categories show the raw key and the web's empty copy; the sort hides with no rows.
        ["waitfor:id=fst.rivals.page-empty@20", "waitfor:name=not_a_category@5", "waitgone:id=fst.rivalry.sort@5",
         "waitfor:id=fst.rivalry.view-profile@5", "{shot:rivalry-unknown}"],
    ),
    "rivalry-empty": (
        {"FST_DEBUG_PROFILE": "fixture-player-empty:Demo Player"},
        f"/rivals/{RIVAL}/rivalry?mode=closest_battles",
        ["waitfor:id=fst.rivals.page-empty@20", "waitfor:name=No song data for this rival.@5", "waitgone:id=fst.rivalry.list@5",
         "{shot:rivalry-empty}"],
    ),
    "rivalry-freeze": (
        {"FST_DEBUG_PROFILE": "fixture-player-503:Demo Player"},
        f"/rivals/{RIVAL}/rivalry?mode=closest_battles",
        ["waitfor:id=fst.service-status.title@20", "waitfor:id=fst.service-status.countdown@10", "waitgone:id=fst.rivalry.sort@5",
         "{shot:rivalry-freeze}"],
    ),
    "rivalry-no-player": (
        {"FST_DEBUG_ANONYMOUS": "1"},
        f"/rivals/{RIVAL}/rivalry?mode=closest_battles",
        ["waitfor:id=fst.songs.search@20", "waitgone:id=fst.rivalry.title@5"],
    ),
}

#: Timing-sensitive scenarios: their steps run in the launch's own desktop-lock hold, so another lane's queued GUI
#: work can't outlast the slow fixture's loading window between launch and drive.
IN_LAUNCH_HOLD = frozenset({"loading", "loading-freeze"})


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


def run(name: str, port: int, shots: Path | None, size: str, exe: Path = EXE) -> None:
    """Launches, drives and closes one scenario.

    Args:
        name: Scenario key.
        port: Fixture port.
        shots: Screenshot directory, if any.
        size: Window preset.
        exe: App executable (Debug build by default; pass the NativeAOT publish to check the ship build).
    """
    env, route, steps = SCENARIOS[name]
    # --first-run=off: the first-run carousel is modal and would swallow the scripted clicks.
    args = ["launch", str(exe), "--timeout", "60", "--wait", "1", "--preset", size,
            f"--arg=--base-url=http://127.0.0.1:{port}/", "--arg=--first-run=off"]
    # An absent settings file gives defaults (all nine charts), independent of the operator's saved settings.
    # Passed as app arguments (not FST_DEBUG_* variables), which Release/NativeAOT builds also honour.
    isolated = Path(tempfile.gettempdir()) / "fst-rivals-journey" / "settings.json"
    flags = {"FST_DEBUG_PROFILE": "--profile", "FST_DEBUG_ANONYMOUS": "--anonymous"}
    for key, value in env.items():
        args += [f"--arg={flags[key]}={value}"] if key == "FST_DEBUG_PROFILE" else [f"--arg={flags[key]}"]
    args.append(f"--arg=--settings-path={isolated}")
    if route:
        args.append(f"--arg=--route={route}")
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as handle:
        handle.write("\n".join(expand(steps, shots, size)))
    try:
        try:
            if name in IN_LAUNCH_HOLD:
                uiwin(*args, "--steps-file", handle.name)
            else:
                uiwin(*args)
                uiwin("drive", "--steps-file", handle.name)
        except RuntimeError:
            evidence = shots or Path(tempfile.gettempdir())
            for command, suffix in (("shot", ".png"), ("tree", ".txt")):
                try:
                    uiwin(command, str(evidence / f"FAILED-{name}-{size}{suffix}"))
                except RuntimeError:
                    pass
            raise
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
    parser.add_argument("--only", help=f"comma-separated scenarios ({', '.join(SCENARIOS)})")
    parser.add_argument("--sizes", default="medium", help="comma-separated presets for the populated and view-all journeys")
    journey_exe.add_argument(parser)
    options = parser.parse_args()
    names = options.only.split(",") if options.only else list(SCENARIOS)
    if unknown := [n for n in names if n not in SCENARIOS]:
        parser.error(f"unknown scenario(s): {', '.join(unknown)}")
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
        for name in names:
            sizes = options.sizes.split(",") if name in ("populated", "view-all") else ["medium"]
            for size in sizes:
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
