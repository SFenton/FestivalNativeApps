"""Item Shop (shop-offers control) UI journeys on Windows for every reachable state (issue #224).

Starts ``tools/windows/shop_fixture.py`` (the synthetic mock plus switchable Shop/catalogue modes) on a free loopback
port, then for each scenario launches this worktree's app with a throwaway settings file and app-data folder, drives
it by ``fst.*`` AutomationIds and UIA names through ``uiwin.py`` and fails on the first missing (``waitfor:``) or
lingering (``waitgone:``) element. A ``@shop=<mode>&songs=<mode>`` step switches the fixture between phases (e.g.
503 → Retry → offers). Steps use UIA patterns (invoke/toggle/expand/collapse), so they also pass on a locked
console, except ``official-link``, which opens the tile context menu with Shift+F10 (keyboard parity). Official Shop
links are never opened.

States (``contracts/product.json`` shop-offers): hidden, loading, empty, failed, populated, new, leaving, grid, list,
offline, unverified, official-link, song-detail, highlight-disabled, filtered, filter-no-match. Grid/list/New/Leaving,
the context-menu link and Song Detail from Shop are also in ``songs_journey.py --only shop,shop-compact``.

Usage: ``python tools/windows/shop_journey.py [--only NAME[,NAME…]] [--sizes compact,medium,wide] [--shots DIR]
[--exe debug|release|aot|PATH]``
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import journey_exe  # noqa: E402  (sibling module)
import ui_journey  # noqa: E402  (sibling module)

ROOT = Path(__file__).resolve().parents[2]
UIWIN = ROOT / "tools" / "windows" / "uiwin.py"
FIXTURE = ROOT / "tools" / "windows" / "shop_fixture.py"
EXE = journey_exe.DEBUG_EXE
PLAYER = {"FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1"}
ANONYMOUS = {"FST_DEBUG_ANONYMOUS": "1"}
LIST = {"shopViewMode": 1}

# name -> (environment, route, settings overrides, steps, sizes or None for every size).
# {shot:NAME} becomes a screenshot with --shots; @shop=…&songs=… switches the fixture (a new drive phase).
SCENARIOS: dict[str, tuple[dict[str, str], str, dict, list[str], set[str] | None]] = {
    "populated-grid": (
        PLAYER, "/shop", {},
        [
            "waitfor:id=fst.shop.grid@20",
            "waitfor:id=fst.shop.song.fixture-pulse",
            "waitfor:name=Fixture Pulse, Synthetic Quartet · 2026, New",
            "waitfor:name=Fixture Orbit, Synthetic Quartet · 2026, Leaving Tomorrow",
            "waitfor:id=fst.shop.badge.leaving.fixture-orbit",
            "waitfor:name=2 songs",
            "waitfor:id=fst.shop.filter",
            "{shot:shop-grid}",
        ],
        None,
    ),
    "list": (
        PLAYER, "/shop", LIST,
        [
            "waitfor:id=fst.shop.list@20",
            "waitfor:id=fst.shop.badge.leaving.fixture-orbit",
            # Issue #562: like the web list, a New row has no pill; the gold pulse and its name ("..., New") carry it.
            "waitfor:name=Fixture Pulse, Synthetic Quartet · 2026, New",
            "waitgone:id=fst.shop.badge.new.fixture-pulse",
            # Official link: the row's cart button (never invoked: it would open the real Item Shop).
            "waitfor:id=fst.shop.external.fixture-orbit",
            "waitfor:name=Fixture Orbit, Synthetic Quartet, Open Official Item Shop",
            "{shot:shop-list}",
            "invoke:id=fst.shop.view-toggle",
            "waitfor:id=fst.shop.grid@10",
            "waitgone:id=fst.shop.list@5",
        ],
        {"medium", "wide"},
    ),
    "official-link": (
        # Keyboard route to the tile's context menu (Shift+F10); the item is found, then dismissed, never invoked.
        PLAYER, "/shop", {},
        [
            "waitfor:id=fst.shop.song.fixture-pulse@20",
            "focus:id=fst.shop.song.fixture-pulse",
            "key:shift+f10",
            "waitfor:id=fst.shop.external.fixture-pulse@5",
            "waitfor:name=Fixture Pulse, Synthetic Quartet, Open Official Item Shop",
            "{shot:shop-context-menu}",
            "key:esc",
            "waitgone:id=fst.shop.external.fixture-pulse@5",
        ],
        {"medium"},
    ),
    "song-detail": (
        PLAYER, "/shop", {},
        [
            "waitfor:id=fst.shop.song.fixture-orbit@20",
            "invoke:id=fst.shop.song.fixture-orbit",
            "waitfor:id=fst.song-detail.title@15",
            "waitfor:id=fst.song-detail.shop",
            "waitfor:name=Open in Item Shop, Leaving Tomorrow",
            "{shot:shop-song-detail}",
        ],
        None,
    ),
    "loading": (
        # The load starts inside the asserting drive (Retry from the failed state): a read held from launch can outlast
        # the app's 30 s request timeout while the drive queues on the shared desktop lock.
        PLAYER, "/shop", {},
        [
            "@shop=error",
            "waitfor:id=fst.service-status.retry@20",
            "@shop=slow",
            "invoke:id=fst.service-status.retry",
            "waitfor:id=fst.shop.loading@10",
            "waitgone:id=fst.shop.grid",
            "waitgone:id=fst.shop.empty",
            "waitgone:id=fst.service-status.retry",
            "{shot:shop-loading}",
            # Releases the held read.
            "@shop=demo",
            "waitfor:id=fst.shop.grid@30",
        ],
        {"medium"},
    ),
    "empty": (
        PLAYER, "/shop", {},
        [
            "@shop=empty",
            "waitfor:id=fst.shop.empty@20",
            "waitfor:name=No Songs in the Item Shop",
            "waitgone:id=fst.service-status.retry",
            # No offers: neither Filter nor the List/Grid toggle has anything to act on.
            "waitgone:id=fst.shop.filter",
            "waitgone:id=fst.shop.view-toggle",
            "{shot:shop-empty}",
        ],
        None,
    ),
    "failed-retry": (
        PLAYER, "/shop", {},
        [
            "@shop=error",
            "waitfor:id=fst.service-status.retry@20",
            "waitfor:id=fst.service-status.title",
            "waitgone:id=fst.shop.empty",
            "waitgone:id=fst.shop.view-toggle",
            "{shot:shop-failed}",
            "@shop=demo",
            "invoke:id=fst.service-status.retry",
            "waitfor:id=fst.shop.grid@20",
            "waitfor:id=fst.shop.song.fixture-pulse",
            "waitgone:id=fst.service-status.retry",
        ],
        None,
    ),
    "offline": (
        # A closed loopback port: every read fails to connect, which the client reports as offline.
        {**PLAYER, "FST_BASE_URL": "http://127.0.0.1:9/"}, "/shop", {},
        [
            "waitfor:id=fst.service-status.retry@60",
            "waitfor:name=You're offline",
            "waitgone:id=fst.shop.empty",
            "{shot:shop-offline}",
        ],
        {"medium"},
    ),
    "unverified": (
        # The catalogue read fails: offers stay, but no tile can be verified as a catalogue song, so each names (and
        # opens) the official Item Shop instead of Song Detail, under an explicit warning.
        PLAYER, "/shop", {},
        [
            "@songs=error",
            "waitfor:id=fst.shop.song-details-error@30",
            "waitfor:name=Fixture Pulse, Synthetic Quartet, Open Official Item Shop",
            "waitfor:name=Fixture Orbit, Synthetic Quartet, Open Official Item Shop",
            "waitgone:name=Fixture Pulse, Synthetic Quartet · 2026, New",
            "{shot:shop-unverified}",
        ],
        {"medium"},
    ),
    "sort-paused": (
        # catalogue-sort R7 (#379): a saved Duration sort without catalogue lengths shows title order under a notice
        # and keeps the choice (the Sort button still names Duration).
        PLAYER, "/shop", {"shopSort": "Duration", "shopSortAscending": False},
        [
            "@songs=error",
            "waitfor:id=fst.shop.sort-paused@30",
            "waitfor:id=fst.shop.song-details-error",
            "waitfor:name=Duration sort paused until song details load. Showing title order; your choice is saved.",
            "waitfor:id=fst.shop.sort",
            "{shot:shop-sort-paused}",
        ],
        {"medium"},
    ),
    "highlight-disabled": (
        PLAYER, "/shop", {"disableShopHighlighting": True, **LIST},
        [
            "waitfor:id=fst.shop.list@20",
            "waitfor:name=Fixture Orbit, Synthetic Quartet · 2026",
            "waitgone:id=fst.shop.badge.leaving.fixture-orbit",
            "waitgone:id=fst.shop.badge.new.fixture-pulse",
            # Highlighting off keeps the official link.
            "waitfor:id=fst.shop.external.fixture-orbit",
            "{shot:shop-highlight-off}",
            "invoke:id=fst.shop.view-toggle",
            "waitfor:id=fst.shop.grid@10",
            "waitfor:name=Fixture Orbit, Synthetic Quartet · 2026",
            "waitgone:id=fst.shop.badge.leaving.fixture-orbit",
        ],
        {"medium", "wide"},
    ),
    "filter": (
        # Issues #238, #376: include switches that start on (every offer listed, Filter not applied), live apply while
        # the flyout is open, the applied status Narrator reads while a switch is off, state kept on reopen, each group
        # hidden alone, the flyout's Reset and the centred no-match empty state (no Reset button, #377).
        PLAYER, "/shop", {},
        [
            "waitfor:id=fst.shop.song.fixture-pulse@20",
            "waitfor:id=fst.shop.song.fixture-orbit",
            "waitfor:name=2 songs",
            "expand:id=fst.shop.filter",
            "waitfor:id=fst.shop.filter.leaving@5",
            "waitfor:id=fst.shop.filter.title",
            "assertstate:id=fst.shop.filter.new|toggle=on",
            "assertstate:id=fst.shop.filter.available|toggle=on",
            "assertstate:id=fst.shop.filter.leaving|toggle=on",
            "{shot:shop-filter-default}",
            "toggle:id=fst.shop.filter.leaving",
            # Applies at once, before the flyout closes: Leaving Tomorrow off hides the leaving offer.
            "waitgone:id=fst.shop.song.fixture-orbit@10",
            "waitfor:name=1 of 2 songs",
            "{shot:shop-filter-flyout}",
            "collapse:id=fst.shop.filter",
            "waitgone:id=fst.shop.filter.leaving@5",
            "waitfor:id=fst.shop.song.fixture-pulse",
            "assertstatus:id=fst.shop.filter|Filters applied",
            "{shot:shop-filtered}",
            # Reopened: the switches show the applied filter.
            "expand:id=fst.shop.filter",
            "assertstate:id=fst.shop.filter.leaving|toggle=off@5",
            "assertstate:id=fst.shop.filter.new|toggle=on",
            "assertstate:id=fst.shop.filter.available|toggle=on",
            # New off alone.
            "toggle:id=fst.shop.filter.leaving",
            "toggle:id=fst.shop.filter.new",
            "waitfor:id=fst.shop.song.fixture-orbit@10",
            "waitgone:id=fst.shop.song.fixture-pulse@10",
            "waitfor:name=1 of 2 songs",
            # The flyout's Reset turns every switch back on and shows every offer.
            "invoke:id=fst.shop.filter.reset",
            "assertstate:id=fst.shop.filter.new|toggle=on@5",
            "assertstate:id=fst.shop.filter.leaving|toggle=on",
            "waitfor:id=fst.shop.song.fixture-pulse@10",
            "waitfor:name=2 songs@10",
            # Available off with no Available offers hides nothing, but the filter still counts as applied.
            "toggle:id=fst.shop.filter.available",
            "waitfor:name=2 of 2 songs@10",
            "toggle:id=fst.shop.filter.available",
            "waitfor:name=2 songs@10",
            "collapse:id=fst.shop.filter",
            "waitgone:id=fst.shop.filter.reset@5",
            # New and Leaving Tomorrow off hide every fixture offer, so the no-match notice shows.
            "expand:id=fst.shop.filter",
            "waitfor:id=fst.shop.filter.new@5",
            "toggle:id=fst.shop.filter.new",
            "toggle:id=fst.shop.filter.leaving",
            "collapse:id=fst.shop.filter",
            "waitfor:id=fst.shop.filter.empty@10",
            "waitgone:id=fst.shop.empty",
            "waitfor:name=0 of 2 songs",
            "{shot:shop-filter-no-match}",
            # Issue #377: the empty state has no Reset Filters button; the flyout's Reset is the way back.
            "waitgone:name=Reset Filters",
            "expand:id=fst.shop.filter",
            "waitfor:id=fst.shop.filter.reset@5",
            "invoke:id=fst.shop.filter.reset",
            "collapse:id=fst.shop.filter",
            "waitfor:id=fst.shop.song.fixture-pulse@10",
            "waitfor:name=2 songs",
            "waitgone:id=fst.shop.filter.empty",
            # Turning the last switch back on by hand (not Reset) also restores every offer.
            "expand:id=fst.shop.filter",
            "assertstate:id=fst.shop.filter.new|toggle=on@5",
            "toggle:id=fst.shop.filter.new",
            "waitfor:name=1 of 2 songs@10",
            "toggle:id=fst.shop.filter.new",
            "waitfor:name=2 songs@10",
            "collapse:id=fst.shop.filter",
        ],
        None,
    ),
    "hidden": (
        PLAYER, "/shop", {"hideShop": True},
        [
            "waitfor:id=fst.shop.hidden@20",
            "waitgone:id=fst.nav.shop",
            "waitgone:id=fst.shop.view-toggle",
            "waitgone:id=fst.shop.filter",
            "{shot:shop-hidden}",
        ],
        None,
    ),
    "detail-shop-failed": (
        # Song Detail keeps the song but names the failed Shop read (never a success-shaped "not in the Shop").
        ANONYMOUS, "/songs/fixture-orbit", {},
        [
            "@shop=error",
            "waitfor:id=fst.song-detail.title@20",
            "waitfor:id=fst.song-detail.shop-error@20",
            "{shot:detail-shop-failed}",
        ],
        {"medium"},
    ),
}


def uiwin(*args: str) -> None:
    """Runs one uiwin.py command, raising on failure.

    Args:
        args: Command-line arguments after ``uiwin.py``.

    Raises:
        RuntimeError: The command failed.
    """
    result = subprocess.run([sys.executable, str(UIWIN), *args], capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
    if result.returncode != 0:
        raise RuntimeError(f"uiwin {' '.join(args[:2])} failed:\n{result.stdout}\n{result.stderr}")


def phases(steps: list[str], shots: Path | None, size: str) -> list[tuple[str | None, list[str]]]:
    """Splits a scenario into drive phases at ``@`` fixture switches and expands ``{shot:NAME}``.

    Args:
        steps: Scenario steps.
        shots: Screenshot directory, or ``None`` to drop shots.
        size: Window preset used in screenshot names.

    Returns:
        ``(control query or None, drive steps)`` pairs in order; the query is applied before its steps run.
    """
    out: list[tuple[str | None, list[str]]] = [(None, [])]
    for step in steps:
        if step.startswith("@"):
            out.append((step[1:], []))
        elif step.startswith("{shot:"):
            if shots is not None:
                out[-1][1].append(f"shot:{shots / (step[6:-1] + '-' + size + '.png')}")
        else:
            out[-1][1].append(step)
    return [phase for phase in out if phase[0] is not None or phase[1]]


def control(port: int, query: str) -> None:
    """Switches the fixture's Shop/catalogue mode.

    Args:
        port: Fixture port.
        query: ``shop=…&songs=…``.
    """
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/__shop__/mode?{query}", timeout=5) as response:
        response.read()


def run(name: str, port: int, shots: Path | None, size: str) -> None:
    """Launches, drives and closes one scenario with throwaway settings and app data.

    Args:
        name: Scenario key.
        port: Fixture port.
        shots: Screenshot directory, if any.
        size: Window preset.
    """
    env, route, settings, steps, _ = SCENARIOS[name]
    plan = phases(steps, shots, size)
    control(port, "shop=demo&songs=ok")
    # A switch before the first drive step applies before launch (the app reads on its first appearance).
    if plan and plan[0][0] is not None:
        control(port, plan[0][0])
        plan[0] = (None, plan[0][1])
    with tempfile.TemporaryDirectory() as folder:
        settings_path = Path(folder) / "settings.json"
        settings_path.write_text(json.dumps({"version": 1, **settings}), encoding="utf-8")
        args = ["launch", str(EXE), "--timeout", "60", "--wait", "1", "--preset", size,
                "--extra", f"FST_SETTINGS_PATH={settings_path}",
                "--extra", f"FST_DEBUG_DATA_DIR={Path(folder) / 'data'}",
                "--route", route]
        if "FST_BASE_URL" not in env:
            args.append(f"--arg=--base-url=http://127.0.0.1:{port}/")
        for key, value in env.items():
            args += ["--extra", f"{key}={value}"]
        uiwin(*args)
        try:
            for index, (query, drive) in enumerate(plan):
                if query is not None:
                    control(port, query)
                if drive:
                    steps_file = Path(folder) / f"steps-{index}.txt"
                    steps_file.write_text("\n".join(drive), encoding="utf-8")
                    uiwin("drive", "--steps-file", str(steps_file))
            print(f"PASS {name} [{size}]", flush=True)
        finally:
            uiwin("close")


def main() -> int:
    """Runs the selected scenarios.

    Returns:
        Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--shots", type=Path)
    parser.add_argument("--only", help=f"comma-separated scenarios ({', '.join(SCENARIOS)})")
    parser.add_argument("--sizes", default="compact,medium,wide", help="comma-separated window presets")
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
    with tempfile.TemporaryDirectory() as folder:
        server, port = ui_journey.start_mock(Path(folder) / "fixture.log", fixture=FIXTURE)
        try:
            for name in names:
                sizes = SCENARIOS[name][4]
                for size in options.sizes.split(","):
                    if sizes is not None and size not in sizes:
                        continue
                    try:
                        run(name, port, options.shots, size)
                    except RuntimeError as error:
                        failures += 1
                        print(f"FAIL {name} [{size}]: {error}", flush=True)
        finally:
            server.terminate()
            server.wait(timeout=10)
    print(f"{'FAILED' if failures else 'OK'}: {failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
