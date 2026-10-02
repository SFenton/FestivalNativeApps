"""Songs, Item Shop, Song Detail and Paths UI journeys on Windows through uiwin.py (FlaUI driver).

Starts ``tools/mock_service.py`` (synthetic fixtures) on a private loopback port, then for each scenario launches
the Debug app with a throwaway settings file (``FST_SETTINGS_PATH``) and an in-memory debug profile, drives it by
``fst.*`` AutomationIds and fails on the first missing element (``waitfor:``). Scenarios: selected-player rows
with Shop accents, Item Shop sort and Shop filter drafts, the Item Shop page (grid, list, Song Detail link),
Song Detail with Paths image/text/not-generated states, no selected player, and a hidden Item Shop. Official Shop
links are never opened. With ``--shots DIR`` it also captures screenshots of each scenario.

Usage: ``python tools/windows/songs_journey.py [--port 18751] [--shots DIR] [--only NAME] [--sizes compact,medium,wide]``
"""

from __future__ import annotations

import argparse
import json
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
PLAYER = {"FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1"}

# name -> (environment, route, settings overrides, steps). {shot:NAME} placeholders become screenshots with --shots.
SCENARIOS: dict[str, tuple[dict[str, str], str | None, dict, list[str]]] = {
    "songs-player": (
        PLAYER, "/songs", {},
        [
            "waitfor:id=fst.songs.row.fixture-pulse@20",
            "waitfor:id=fst.songs.row.fixture-orbit",
            "waitfor:id=fst.songs.section-index-button",
            "{shot:songs}",
            "click:id=fst.songs.sort",
            "waitfor:id=fst.songs.sort.reset@5",
            "click:name=Item Shop",
            "key:esc",
            "waitfor:name=Leaving Tomorrow@10",
            "waitfor:name=In Shop",
            "{shot:songs-shop-sort}",
            "click:id=fst.songs.filter",
            "waitfor:id=fst.songs.filter.reset@5",
            "waitfor:id=fst.songs.filter.score-sections",
            "scroll:id=fst.songs.filter.score-sections,-15",
            "expand:id=fst.songs.filter.shop@5",
            "toggle:id=fst.songs.filter.shop-unavailable",
            "key:esc",
            "waitfor:id=fst.songs.row.fixture-orbit@10",
            "{shot:songs-leaving-filter}",
            "click:id=fst.songs.filter",
            "waitfor:id=fst.songs.filter.reset@5",
            "click:id=fst.songs.filter.reset",
            "key:esc",
            "waitfor:id=fst.songs.row.fixture-pulse@10",
            "click:id=fst.songs.row.fixture-pulse",
            "waitfor:id=fst.song-detail.title@15",
        ],
    ),
    "shop": (
        PLAYER, "/shop", {},
        [
            "waitfor:id=fst.shop.grid@20",
            "waitfor:id=fst.shop.song.fixture-pulse",
            "waitfor:id=fst.shop.badge.leaving.fixture-orbit",
            "{shot:shop-grid}",
            # The purchase link lives in the tile's context menu (web-style tiles carry no cart button).
            "rightclick:id=fst.shop.song.fixture-pulse",
            "waitfor:id=fst.shop.external.fixture-pulse@5",
            "key:esc",
            "click:id=fst.shop.view-toggle",
            "waitfor:id=fst.shop.list@5",
            "waitfor:id=fst.shop.song.fixture-orbit",
            "{shot:shop-list}",
            "click:id=fst.shop.song.fixture-orbit",
            "waitfor:name=Open in Item Shop, Leaving Tomorrow@15",
            "waitfor:id=fst.song-detail.shop",
        ],
    ),
    "shop-compact": (
        PLAYER, "/shop", {},
        [
            "waitfor:id=fst.shop.grid@20",
            "waitfor:id=fst.shop.badge.leaving.fixture-orbit",
            "waitfor:id=fst.shop.song.fixture-pulse",
            "{shot:shop-grid}",
            "click:id=fst.shop.song.fixture-pulse",
            "waitfor:id=fst.song-detail.shop@15",
        ],
    ),
    "detail-paths": (
        PLAYER, "/songs/fixture-pulse", {"pathUnavailableWarningDismissed": True},
        [
            "waitfor:id=fst.song-detail.title@20",
            "waitfor:id=fst.song-detail.paths",
            "{shot:detail}",
            "click:id=fst.song-detail.paths",
            "waitfor:id=fst.paths.image@15",
            "{shot:paths-image}",
            "click:id=fst.paths.zoom-in",
            # Medium/compact sheets put the pickers in one row of ComboBoxes below the chart (web compact sheet).
            "expand:id=fst.paths.display.compact",
            "select:name=Text@5",
            "waitfor:id=fst.paths.activation.1@15",
            "{shot:paths-text}",
            "expand:id=fst.paths.difficulty.compact",
            "select:name=Easy@5",
            "waitfor:id=fst.paths.empty@15",
            "key:escape",
            "waitfor:id=fst.song-detail.title@5",
        ],
    ),
    "paths-warning": (
        PLAYER, "/songs/fixture-pulse", {},
        [
            "waitfor:id=fst.song-detail.paths@20",
            "click:id=fst.song-detail.paths",
            # The Karaoke notice is its own ContentDialog before the sheet (7f45f884): OK, then the sheet opens.
            "waitfor:id=fst.paths.warning@10",
            "key:enter",
            "waitfor:id=fst.paths@10",
            "key:escape",
        ],
    ),
    "no-player": (
        {"FST_DEBUG_ANONYMOUS": "1"}, "/songs", {"songFilter": {"Instrument": "Lead", "MinDifficulty": 1, "MaxDifficulty": 7}},
        [
            "waitfor:id=fst.songs.row.fixture-pulse@20",
            "{shot:songs-anonymous}",
            "click:id=fst.songs.filter",
            # A v1 settings file (difficulty range) migrates to the v2 bucket filter; the web-order sections show.
            "waitfor:id=fst.songs.filter.general@5",
            "waitfor:id=fst.songs.filter.year",
            "waitfor:id=fst.songs.filter.double-bass",
            "key:escape",
        ],
    ),
    "filter-web": (
        # Web FilterModal order (6.32/7.17): score toggles, Item Shop, Instrument Selector revealing the bucket sections.
        PLAYER, "/songs", {},
        [
            "waitfor:id=fst.songs.row.fixture-pulse@20",
            "click:id=fst.songs.filter",
            "waitfor:id=fst.songs.filter.reset@5",
            "expand:id=fst.songs.filter.score.global",
            "waitfor:id=fst.songs.filter.score.global.missing-scores@5",
            "{shot:songs-filter-score}",
            "collapse:id=fst.songs.filter.score.global",
            # The selector sits below nine per-instrument groups and Item Shop: scroll the form to it.
            "scroll:id=fst.songs.filter.score-sections,-40",
            "invoke:id=fst.songs.filter.instrument.compact@5",
            "waitfor:id=fst.songs.filter.percentile@5",
            "expand:id=fst.songs.filter.percentile",
            "scroll:id=fst.songs.filter.percentile,-3",
            "invoke:id=fst.songs.filter.percentile.clear-all@5",
            "toggle:id=fst.songs.filter.percentile.1",
            "{shot:songs-filter-percentile}",
            "collapse:id=fst.songs.filter.percentile",
            "expand:id=fst.songs.filter.stars",
            "waitfor:id=fst.songs.filter.stars.6@5",
            "{shot:songs-filter-stars}",
            "click:id=fst.songs.filter.reset",
            "key:esc",
            "waitfor:id=fst.songs.row.fixture-orbit@10",
        ],
    ),
    "shop-hidden": (
        PLAYER, "/shop", {"hideShop": True},
        ["waitfor:id=fst.shop.hidden@20", "{shot:shop-hidden}"],
    ),
}


# Scenarios that only make sense at some window sizes (compact windows force the Shop grid, without the toggle).
SIZES = {"shop": {"medium", "wide"}, "shop-compact": {"compact"}}


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


def run(name: str, port: int, shots: Path | None, size: str) -> None:
    """Launches, drives and closes one scenario with a throwaway settings file.

    Args:
        name: Scenario key.
        port: Fixture port.
        shots: Screenshot directory, if any.
        size: Window preset.
    """
    env, route, settings, steps = SCENARIOS[name]
    with tempfile.TemporaryDirectory() as folder:
        settings_path = Path(folder) / "settings.json"
        if settings:
            settings_path.write_text(json.dumps({"version": 1, **settings}), encoding="utf-8")
        args = ["launch", str(EXE), "--timeout", "60", "--wait", "1", "--preset", size,
                f"--arg=--base-url=http://127.0.0.1:{port}/", "--extra", f"FST_SETTINGS_PATH={settings_path}"]
        for key, value in env.items():
            args += ["--extra", f"{key}={value}"]
        if route:
            args += ["--route", route]
        uiwin(*args)
        try:
            steps_file = Path(folder) / "steps.txt"
            steps_file.write_text("\n".join(expand(steps, shots, size)), encoding="utf-8")
            uiwin("drive", "--steps-file", str(steps_file))
            print(f"PASS {name} [{size}]")
        finally:
            uiwin("close")


def main() -> int:
    """Runs the selected scenarios.

    Returns:
        Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=18751)
    parser.add_argument("--shots", type=Path)
    parser.add_argument("--only", choices=sorted(SCENARIOS))
    parser.add_argument("--sizes", default="medium", help="comma-separated presets for every scenario")
    journey_exe.add_argument(parser)
    options = parser.parse_args()
    global EXE
    EXE = options.exe
    server = subprocess.Popen([sys.executable, str(ROOT / "tools" / "mock_service.py"), "--port", str(options.port)],
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
            for size in options.sizes.split(","):
                if name in SIZES and size not in SIZES[name]:
                    continue
                try:
                    run(name, options.port, options.shots, size)
                except RuntimeError as error:
                    failures += 1
                    print(f"FAIL {name} [{size}]: {error}")
    finally:
        server.terminate()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
