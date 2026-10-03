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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import journey_exe  # noqa: E402  (sibling module)

ROOT = Path(__file__).resolve().parents[2]
UIWIN = ROOT / "tools" / "windows" / "uiwin.py"
EXE = journey_exe.DEBUG_EXE
RIVAL = "f1c749eb07c32578cfa3e59ec38c03a8"

# name -> (environment, route, steps). {shot:NAME} placeholders become screenshots when --shots is given.
SCENARIOS: dict[str, tuple[dict[str, str], str | None, list[str]]] = {
    "populated": (
        {"FST_DEBUG_PROFILE": "fixture-player-1:Demo Player"},
        "/rivals",
        [
            "waitfor:id=fst.rivals.section.common@20",
            f"waitfor:id=fst.rivals.row.{RIVAL}@10",
            "{shot:hub}",
            "select:id=fst.rivals.tab.leaderboard",
            "waitfor:id=fst.rivals.section.leaderboard.Solo_Guitar@10",
            "waitfor:name=#2@10",
            "{shot:hub-leaderboard}",
            "select:id=fst.rivals.tab.song",
            "waitfor:id=fst.rivals.section.common@10",
            f"click:id=fst.rivals.row.{RIVAL}",
            "waitfor:id=fst.rival-detail.category.closest_battles@15",
            "waitfor:id=fst.rival-detail.view-profile@10",
            "{shot:detail}",
            "click:id=fst.rival-detail.see-all",
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
            "click:id=fst.rivals.see-all",
            "waitfor:id=fst.all-rivals.list@15",
            f"waitfor:id=fst.all-rivals.row.{RIVAL}@10",
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
    "compete": (
        {"FST_DEBUG_PROFILE": "fixture-player-1:Demo Player"},
        "/compete",
        ["waitfor:id=fst.rivals.title@20", "waitfor:id=fst.rivals.section.common@20"],
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
    uiwin(*args)
    try:
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as handle:
            handle.write("\n".join(expand(steps, shots, size)))
        try:
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
    parser.add_argument("--only", choices=sorted(SCENARIOS))
    parser.add_argument("--sizes", default="medium", help="comma-separated presets for the populated journey")
    journey_exe.add_argument(parser)
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
                    run(name, options.port, options.shots, size, options.exe)
                except RuntimeError as error:
                    failures += 1
                    print(f"FAIL {name} [{size}]: {error}")
    finally:
        server.terminate()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
