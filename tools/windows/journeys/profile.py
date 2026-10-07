#!/usr/bin/env python3
"""Profile UI journeys for the Windows app, driven through ``tools/windows/uiwin.py``.

Each journey launches the app against the loopback fixture service (``tools/mock_service.py``)
with an isolated settings file, runs UIA steps (``waitfor`` steps are the assertions) and checks
UIA tree dumps for required/forbidden AutomationIds or names. Nothing touches production or the
operator's real settings.

Usage (from the repository root, after ``tools/windows/build.ps1``)::

    python tools/windows/journeys/profile.py                 # all journeys
    python tools/windows/journeys/profile.py select history  # by name
    python tools/windows/journeys/profile.py --exe path\\to\\FestivalScoreTracker.exe --shots out\\dir

Exit code 0 when every journey passes, 1 otherwise.
"""

from __future__ import annotations

import argparse
import os
import socket
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import journey_exe  # noqa: E402  (tools/windows module)

REPO = Path(__file__).resolve().parents[3]
UIWIN = REPO / "tools" / "windows" / "uiwin.py"

# region Model


@dataclass
class Journey:
    """One scripted journey.

    Attributes:
        name: Short CLI name.
        launch: Extra ``uiwin.py launch`` arguments (route, tab, profile).
        steps: Drive phases; each is a list of step strings run in one ``drive`` call.
        expect: Per phase, substrings that must appear in the tree dumped after it.
        forbid: Per phase, substrings that must not appear in that tree.
        relaunch: Phase index after which the app is closed and relaunched with ``relaunch_args``.
        relaunch_args: Launch arguments for the relaunch.
        preset: ``uiwin.py`` window preset (a tall one keeps more of a long page on screen).
        fixture: ``rivals_fixture.py`` flags (e.g. ``["--player-bands", "fail-once"]``); empty serves the plain
            ``mock_service.py``.
    """

    name: str
    launch: list[str]
    steps: list[list[str]]
    expect: list[list[str]] = field(default_factory=list)
    forbid: list[list[str]] = field(default_factory=list)
    relaunch: int | None = None
    relaunch_args: list[str] = field(default_factory=list)
    preset: str = "medium"
    fixture: list[str] = field(default_factory=list)


def _profile(value: str) -> list[str]:
    """Launch arguments selecting a fixture player in memory only."""
    return ["--arg=--profile", f"--arg={value}"]


ANONYMOUS = ["--arg=--anonymous"]
HISTORY_ROUTE = "/songs/fixture-pulse/Solo_Guitar/history"

JOURNEYS = [
    Journey(
        name="select",
        # Opened by route rather than typed profile search: UIA patterns only, so it also runs on a locked console.
        launch=["--route", "/player/fixture-player-2", *ANONYMOUS],
        steps=[
            ["waitfor:id=fst.player.name@15", "waitfor:id=fst.player.select@10"],
            ["invoke:id=fst.player.select", "waitfor:id=fst.player.deselect@10", "waitfor:id=fst.nav.statistics@10"],
            ["invoke:id=fst.nav.statistics", "waitfor:id=fst.player.deselect@15",
             "waitfor:id=fst.player.overview@15", "wait:5"],
            ["invoke:id=fst.player.deselect", "waitfor:id=PrimaryButton@10", "invoke:id=PrimaryButton", "wait:2"],
        ],
        expect=[
            ["fst.player.select", "fst.player.bands-section", "fst.player.bands-link"],
            ["fst.player.deselect", "fst.nav.statistics", "fst.nav.rivals"],
            ["Fixture Player 2", "fst.player.overview", "fst.player.instrument.Solo_Guitar",
             "fst.player.rank-history.Solo_Guitar", "fst.player.percentiles.Solo_Guitar"],
            ["fst.nav.songs"],
        ],
        forbid=[[], ["fst.player.select"], [], ["fst.nav.statistics", "fst.nav.rivals"]],
    ),
    Journey(
        name="restart",
        launch=["--route", "/player/fixture-player-1"],
        steps=[
            ["waitfor:id=fst.player.select@15", "invoke:id=fst.player.select", "waitfor:id=fst.player.deselect@10"],
            ["waitfor:id=fst.nav.statistics@15", "invoke:id=fst.nav.statistics", "waitfor:id=fst.player.deselect@15"],
        ],
        expect=[["fst.player.deselect"], ["Fixture Player 1", "fst.player.deselect"]],
        relaunch=0,
        relaunch_args=["--tab", "statistics"],
    ),
    Journey(
        name="links",
        launch=["--route", "/player/fixture-player-1", *ANONYMOUS],
        steps=[
            ["waitfor:id=fst.player.stat.overview.songs-played@15", "waitfor:id=fst.player.stat.overview.best-rank@5"],
            ["invoke:id=fst.player.stat.overview.songs-played", "waitfor:id=fst.songs.filter@10", "wait:2"],
        ],
        expect=[["fst.player.stat.overview.full-combos", "fst.player.select"], ["fst.songs.filter", "fst.nav.statistics"]],
        forbid=[[], ["fst.player.select"]],
    ),
    # Player History is Song Detail's Score History section (operator 6.39); the route scrolls to it. The tall
    # portrait-tablet window keeps the chart, sort button and rows on screen without real scrolling (issue #198).
    Journey(
        name="history",
        launch=["--route", HISTORY_ROUTE, *_profile("fixture-player-1:Fixture Player 1")],
        preset="portrait-tablet",
        steps=[
            ["waitfor:id=fst.history.chart@15", "waitfor:id=fst.history.bar.0@5", "waitfor:id=fst.history.sort.open@5"],
            ["toggle:id=fst.history.bar.0", "waitfor:id=fst.history.detail@5"],
            ["toggle:id=fst.history.bar.0", "wait:1"],
            ["invoke:id=fst.history.sort.open", "waitfor:id=fst.history.sort.mode.date@5",
             "toggle:id=fst.history.sort.mode.date", "wait:1"],
            ["invoke:id=fst.history.sort.open", "waitfor:id=fst.history.sort.direction.ascending@5",
             "toggle:id=fst.history.sort.direction.ascending", "wait:1"],
            ["invoke:id=fst.history.sort.open", "waitfor:id=fst.history.sort.reset@5",
             "invoke:id=fst.history.sort.reset", "wait:1"],
        ],
        expect=[
            ["Score History", "score history, 2 of 2 scores",
             "id=fst.history.bar.1", "patterns=Toggle", "Sort scores by Score, descending", "personal best",
             "fst.song-detail.history.row.20240105"],
            ["fst.history.detail"],
            ["fst.history.bar.0"],
            ["Sort scores by Date, descending"],
            ["Sort scores by Date, ascending"],
            ["Sort scores by Score, descending"],
        ],
        forbid=[["fst.history.detail", "fst.history.view-all", "fst.history.page-back", "fst.history.retry"],
                [], ["fst.history.detail"]],
    ),
    Journey(
        name="history-paging",
        launch=["--route", HISTORY_ROUTE, *_profile("fixture-history-multi:History Multi")],
        preset="portrait-tablet",
        steps=[
            ["waitfor:id=fst.history.chart@15", "waitfor:id=fst.history.bar.7@5", "waitfor:id=fst.history.page-back@5"],
            ["invoke:id=fst.history.entry-back", "waitfor:id=fst.history.bar.2@5"],
            ["invoke:id=fst.history.entry-forward", "waitfor:id=fst.history.bar.7@5"],
            ["reveal:id=fst.history.view-all", "invoke:id=fst.history.view-all", "wait:1"],
            ["reveal:id=fst.history.instrument.Solo_Bass", "toggle:id=fst.history.instrument.Solo_Bass", "wait:1",
             "waitfor:id=fst.history.bar.1@5"],
            ["toggle:id=fst.history.instrument.Solo_Drums", "wait:1", "waitfor:id=fst.history.bar.0@5"],
        ],
        expect=[
            ["fst.history.instrument.Solo_Bass", "fst.history.instrument.Solo_Drums", "5 of 8 scores",
             "fst.history.entry-back", "fst.history.page-forward", "fst.history.view-all", "View All Scores, Lead"],
            ["fst.history.bar.2"],
            ["fst.history.bar.7"],
            ["610,000"],
            ["Bass score history, 2 of 2 scores"],
            ["Drums score history"],
        ],
        forbid=[["fst.history.bar.2"], ["fst.history.bar.7"], ["fst.history.bar.2"], ["fst.history.view-all"],
                ["fst.history.entry-back", "fst.history.view-all"]],
    ),
    Journey(
        name="history-syncing",
        launch=["--route", HISTORY_ROUTE, *_profile("fixture-syncing:Syncing Player")],
        steps=[["waitfor:id=fst.history.message@15", "waitfor:id=fst.history.retry@5"],
               ["invoke:id=fst.history.retry", "wait:1", "waitfor:id=fst.history.message@15"]],
        expect=[["still being prepared", "Retry score history"], ["still being prepared"]],
        forbid=[["fst.history.chart", "fst.history.rows", "fst.history.error"], ["fst.history.chart"]],
    ),
    Journey(
        name="history-failed",
        launch=["--route", HISTORY_ROUTE, *_profile("fixture-history-fail:History Fail")],
        steps=[["waitfor:id=fst.history.error@15", "waitfor:id=fst.history.retry@5"],
               ["invoke:id=fst.history.retry", "wait:1", "waitfor:id=fst.history.error@15"]],
        expect=[["fst.history.retry"], ["fst.history.error"]],
        forbid=[["fst.history.chart", "fst.history.rows", "fst.history.message"], ["fst.history.chart"]],
    ),
    # No player, an unregistered player (404) and a song without rows all hide the section (web: no chart, no message).
    # A history link without a player is a player-only route and opens Songs (AppRouteParser.RequiresPlayer).
    Journey(
        name="history-anonymous",
        launch=["--route", HISTORY_ROUTE, *ANONYMOUS],
        steps=[["waitfor:id=fst.songs.list@15", "wait:2"],
               ["invoke:id=fst.songs.row.fixture-pulse", "waitfor:id=fst.song-detail.title@15", "wait:3"]],
        expect=[["fst.songs.list"], ["fst.song-detail.title"]],
        forbid=[["Score History", "fst.history."], ["Score History", "fst.history."]],
    ),
    Journey(
        name="history-unregistered",
        launch=["--route", HISTORY_ROUTE, *_profile("fixture-player-2:Fixture Player 2")],
        steps=[["waitfor:id=fst.song-detail.title@15", "wait:3"]],
        expect=[["fst.song-detail.title"]],
        forbid=[["Score History", "fst.history."]],
    ),
    Journey(
        name="history-no-rows",
        launch=["--route", "/songs/fixture-orbit/Solo_Guitar/history", *_profile("fixture-player-1:Fixture Player 1")],
        steps=[["waitfor:id=fst.song-detail.title@15", "wait:3"]],
        expect=[["fst.song-detail.title"]],
        forbid=[["Score History", "fst.history."]],
    ),
    Journey(
        name="rank-history",
        launch=["--route", "/player/fixture-player-1", *ANONYMOUS],
        steps=[
            ["waitfor:id=fst.player.overview@15", "reveal:id=fst.player.rank-history.Solo_Guitar.older@5"],
            ["invoke:id=fst.player.rank-history.Solo_Guitar.older", "wait:1"],
            ["invoke:id=fst.player.rank-history.Solo_Guitar.newer", "wait:1"],
        ],
        # The fixture's committed 7-day series pages 6 bars at the default launch size: Older reveals Sep 21.
        expect=[["Rank history, Sep 22, 2026"], ["Rank history, Sep 21, 2026"], ["Rank history, Sep 22, 2026"]],
        forbid=[["Rank history, Sep 21, 2026"], ["Rank history, Sep 22, 2026"], ["Rank history, Sep 21, 2026"]],
    ),
    Journey(
        name="instrument-links",
        launch=["--route", "/player/fixture-player-1", *ANONYMOUS],
        steps=[
            ["waitfor:id=fst.player.overview@15", "reveal:id=fst.player.percentile.Solo_Guitar.4@5"],
            ["invoke:id=fst.player.percentile.Solo_Guitar.4", "waitfor:id=fst.songs.filter@10", "wait:2"],
        ],
        expect=[["Top 4%: 2 songs", "Global Rank: #1", "Opens Lead songs in the Top 4%"], ["fst.songs.filter"]],
        forbid=[[], ["fst.player.select"]],
    ),
    Journey(
        name="syncing",
        launch=["--route", "/player/fixture-syncing", *ANONYMOUS],
        steps=[["waitfor:id=fst.player.syncing@15"]],
        expect=[["Scores Are Syncing"]],
        forbid=[["fst.player.select"]],
    ),
    Journey(
        name="bands-scope",
        launch=["--tab", "songs", *ANONYMOUS],
        steps=[["invoke:id=fst.shell.profile", "waitfor:id=fst.profile.scope.bands@5",
                "select:id=fst.profile.scope.bands", "wait:1"]],
        expect=[["Find Band", "Band search isn"]],
        forbid=[["fst.profile.retry"]],
    ),
    # Inline Bands section (issue #312, .agents/pages/player-profile/windows.md): fixture-player-1 has 18 duos,
    # 8 trios and 4 quads, so Duos and Trios show six cards and View All, Quads shows all four and no View All.
    # Each phase fails on the old link-only profile (no group headers, cards or View All buttons).
    Journey(
        name="bands-section",
        launch=["--route", "/player/fixture-player-1", *ANONYMOUS],
        preset="portrait-tablet",
        steps=[
            ["waitfor:id=fst.player.overview@15", "reveal:id=fst.player.bands@10",
             "reveal:id=fst.player.bands.header.duos@15", "reveal:id=fst.player-bands.row.fixture-band-1@5",
             "reveal:id=fst.player.bands.view-all.duos@5", "assertname:id=fst.player.bands.view-all.duos|View All Bands (18), Duos",
             "reveal:id=fst.player.bands.header.trios@5", "reveal:id=fst.player.bands.view-all.trios@5",
             "assertname:id=fst.player.bands.view-all.trios|View All Bands (8), Trios",
             # Frosted card, not the purple CTA (surface-materials R7): no brand-purple fill, and the white in-card
             # chevron sits right of the centred label (label ends ~C47, chevron ~C59-64 at default text size).
             "assertpaint:id=fst.player.bands.view-all.trios|L8,M0!=#7C3AED~48|C53,T10,C76,B10=#FFFFFF~64",
             "reveal:id=fst.player.bands.header.quads@5", "reveal:id=fst.player-bands.row.fixture-pband-quad-4@5"],
            ["reveal:id=fst.player.bands.view-all.duos@10", "invoke:id=fst.player.bands.view-all.duos",
             "waitfor:id=fst.player-bands.title@10",
             "assertstate:id=fst.player-bands.group.duos|selected=true@5",
             "assertname:id=fst.player-bands.title|Fixture Player 1's Bands", "waitfor:name=Duos · 18 bands@10"],
            ["invoke:id=PART_BackButton", "waitfor:id=fst.player.overview@10", "reveal:id=fst.player.bands-link@10",
             "invoke:id=fst.player.bands-link", "waitfor:id=fst.player-bands.title@10",
             "assertstate:id=fst.player-bands.group.all|selected=true@5", "waitfor:name=All Bands · 30 bands@10"],
            ["invoke:id=PART_BackButton", "waitfor:id=fst.player.overview@10",
             "reveal:id=fst.player-bands.row.fixture-band-1@15", "invoke:id=fst.player-bands.row.fixture-band-1",
             "waitfor:id=fst.band.title@10", "waitfor:id=fst.band.member.fixture-band-1-a@10"],
        ],
        expect=[
            ["Fixture Player 1's Bands", "View All, Fixture Player 1's Bands", "fst.player.bands.header.quads",
             "fst.player-bands.row.fixture-pband-quad-1", "fst.player-bands.row.fixture-pband-quad-4"],
            ["fst.player-bands.row.fixture-band-1"],
            ["fst.player-bands.row.fixture-pband-trio-1"],
            ["fst.band.title"],
        ],
        # Six-card previews: the seventh duo and trio stay on Player Bands; four quads need no View All.
        forbid=[["fst.player-bands.row.fixture-pband-duo-7", "fst.player-bands.row.fixture-pband-trio-7",
                 "fst.player.bands.view-all.quads", "fst.player.bands.empty.", "fst.player.bands.retry",
                 "fst.player.bands.loading"], [], [], []],
    ),
    Journey(
        name="bands-empty",
        launch=["--route", "/player/fixture-player-2", *ANONYMOUS],
        preset="portrait-tablet",
        steps=[["waitfor:id=fst.player.overview@15", "reveal:id=fst.player.bands@10",
                "reveal:id=fst.player.bands.empty.duos@15", "reveal:id=fst.player.bands.empty.trios@5",
                "reveal:id=fst.player.bands.empty.quads@5"]],
        expect=[["Fixture Player 2's Bands", "No Bands Yet", "Band lineups will appear here",
                 "fst.player.bands.header.duos", "fst.player.bands.header.trios", "fst.player.bands.header.quads"]],
        forbid=[["fst.player.bands.view-all.", "fst.player-bands.row.", "fst.player.bands.retry"]],
    ),
    # Every group read answers 500 once (rivals_fixture.py --player-bands fail-once): the section shows Retry while
    # the rest of the profile stays, and Retry loads the groups.
    Journey(
        name="bands-retry",
        launch=["--route", "/player/fixture-player-1", *ANONYMOUS],
        preset="portrait-tablet",
        fixture=["--player-bands", "fail-once"],
        steps=[
            ["waitfor:id=fst.player.overview@15", "reveal:id=fst.player.bands.retry@15"],
            ["invoke:id=fst.player.bands.retry", "reveal:id=fst.player.bands.header.duos@15",
             "reveal:id=fst.player-bands.row.fixture-band-1@5", "waitgone:id=fst.player.bands.retry@5"],
        ],
        # The page around the failed section stays (the overview tiles virtualize once scrolled away, so the
        # non-virtualized title and section headings stand for it).
        expect=[["Fixture Player 1's Bands", "fst.player.name", "fst.player.overview", "fst.player.instrument.Solo_Guitar",
                 "fst.player.bands-link"],
                ["fst.player.bands.header.duos", "fst.player-bands.row.fixture-band-1"]],
        forbid=[["fst.player.bands.header.", "fst.player-bands.row."], ["fst.player.bands.retry"]],
    ),
    # Statistics (.agents/pages/statistics/windows.md): every state reachable with fixtures. Rank-history read failures
    # have no fixture; Festival.Core.Tests covers that state (PlayerViewModelTests).
    Journey(
        name="statistics-content",
        launch=["--tab", "statistics", *_profile("fixture-player-1:Fixture Player 1")],
        steps=[
            ["waitfor:id=fst.statistics@15", "waitfor:id=fst.player.overview@15",
             "waitfor:id=fst.player.rank-history.Solo_Guitar@15"],
            ["scrollinto:id=fst.player.rank-history.Solo_Guitar.older@5", "invoke:id=fst.player.rank-history.Solo_Guitar.older",
             "wait:1"],
            ["invoke:id=fst.player.rank-history.Solo_Guitar.newer", "wait:1"],
        ],
        expect=[
            ["fst.statistics", "fst.player.deselect", "fst.player.stat.overview.songs-played",
             "fst.player.instrument.Solo_Guitar", "fst.player.stat.Solo_Guitar.global-rank",
             "fst.player.rank-history.Solo_Guitar", "fst.player.percentiles.Solo_Guitar", "fst.player.bands-section",
             "fst.player.bands-link", "fst.quick-links.open"],
            ["fst.player.rank-history.Solo_Guitar.newer"],
            ["fst.player.rank-history.Solo_Guitar.older"],
        ],
        forbid=[["fst.player.select", "fst.player.syncing", "fst.service-status.title"], [], []],
    ),
    Journey(
        name="statistics-quick-links",
        launch=["--tab", "statistics", *_profile("fixture-player-1:Fixture Player 1")],
        # One phase: the menu flyout light-dismisses between phases, so its items are asserted with waitfor.
        steps=[
            ["waitfor:id=fst.player.overview@15", "invoke:id=fst.quick-links.open",
             "waitfor:id=fst.quick-links.item.global@5", "waitfor:id=fst.quick-links.item.instrument:Solo_Guitar@5",
             "waitfor:id=fst.quick-links.item.bands@5", "toggle:id=fst.quick-links.item.bands", "wait:1.5",
             # Lands the inline section (issue #312) on the shared 32 epx line (section-jump-landing R2).
             "assertinset:id=fst.player.bands-section|id=fst.player.available|32", "waitfor:id=fst.player.bands@3"],
        ],
        expect=[["current section Bands", "Fixture Player 1's Bands"]],
        forbid=[["fst.quick-links.item.global"]],
    ),
    Journey(
        name="statistics-link",
        launch=["--tab", "statistics", *_profile("fixture-player-1:Fixture Player 1")],
        steps=[["waitfor:id=fst.player.overview@15", "scrollinto:id=fst.player.stat.Solo_Guitar.songs-played@10", "wait:1",
                "invoke:id=fst.player.stat.Solo_Guitar.songs-played@5", "waitfor:id=fst.songs.filter@10", "wait:2"]],
        expect=[["fst.songs.filter", "fst.nav.statistics"]],
        forbid=[["fst.statistics"]],
    ),
    Journey(
        name="statistics-syncing",
        launch=["--tab", "statistics", *_profile("fixture-syncing:Syncing Player")],
        steps=[["waitfor:id=fst.player.syncing@15"]],
        expect=[["Scores Are Syncing", "Retry"]],
        forbid=[["fst.player.overview", "fst.service-status.title"]],
    ),
    Journey(
        name="statistics-denied",
        launch=["--tab", "statistics", *_profile("fixture-denied:Denied Player")],
        steps=[["waitfor:id=fst.service-status.title@15"]],
        expect=[["fst.service-status.retry"]],
        forbid=[["fst.player.overview", "fst.player.syncing"]],
    ),
    Journey(
        name="statistics-empty",
        launch=["--tab", "statistics", *_profile("fixture-empty:Empty Player")],
        steps=[["waitfor:id=fst.player.overview@15", "wait:2"]],
        expect=[["fst.statistics", "fst.player.deselect"]],
        forbid=[["fst.player.rank-history.", "fst.player.percentiles.", "fst.service-status.title"]],
    ),
    Journey(
        name="statistics-unranked",
        launch=["--tab", "statistics", *_profile("fixture-rank-unranked:Fixture Rank Unranked")],
        steps=[["waitfor:id=fst.player.stat.Solo_Guitar.global-rank@15", "wait:2"]],
        expect=[["Unranked"]],
        forbid=[["Global rank unavailable", "fst.player.rank-history.Solo_Guitar"]],
    ),
    Journey(
        name="statistics-rank-fail",
        launch=["--tab", "statistics", *_profile("fixture-rank-fail:Fixture Rank Fail")],
        steps=[["waitfor:id=fst.player.instrument.Solo_Guitar@15", "waitfor:name=Retry@10", "wait:1"]],
        expect=[["Global rank unavailable", "Retry"]],
        forbid=[["fst.service-status.title"]],
    ),
]

# endregion

# region Runner


def _uiwin(*args: str, check: bool = True) -> subprocess.CompletedProcess:
    """Run ``uiwin.py`` and return the completed process."""
    env = {**os.environ, "PYTHONIOENCODING": "utf-8", "MSYS_NO_PATHCONV": "1"}
    result = subprocess.run([sys.executable, str(UIWIN), *args], capture_output=True, text=True,
                            encoding="utf-8", env=env)
    if check and result.returncode != 0:
        raise RuntimeError(f"uiwin {args[0]} failed: {result.stderr.strip() or result.stdout.strip()}")
    return result


def _free_port() -> int:
    """Pick a free loopback port for the fixture service."""
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def _wait_for_port(port: int, timeout: float = 15.0) -> None:
    """Wait until the fixture service accepts connections (a wrapper imports the mock service first)."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return
        except OSError:
            time.sleep(0.2)
    raise RuntimeError(f"fixture service did not listen on {port}")


def _app_args(extra: list[str]) -> list[str]:
    """Turn ``--route``/``--tab`` into app arguments (Release/AOT builds ignore the FST_DEBUG_* environment)."""
    result: list[str] = []
    items = iter(extra)
    for item in items:
        if item in ("--route", "--tab"):
            result += [f"--arg={item}", f"--arg={next(items)}"]
        else:
            result.append(item)
    return result


def _launch(exe: Path, base: str, settings: Path, extra: list[str], preset: str = "medium") -> int:
    """Launch the app and return its pid."""
    out = _uiwin("launch", str(exe), "--arg=--base-url", f"--arg={base}", "--arg=--settings-path",
                 f"--arg={settings}", "--preset", preset, *_app_args(extra)).stdout
    for line in out.splitlines():
        if '"pid"' in line:
            return int(line.split(":")[1].strip().rstrip(","))
    raise RuntimeError(f"no pid in launch output: {out}")


def run(journey: Journey, exe: Path, shots: Path | None) -> list[str]:
    """Run one journey and return failure messages (empty when it passed)."""
    failures: list[str] = []
    port = _free_port()
    service = (REPO / "tools" / "windows" / "rivals_fixture.py") if journey.fixture else (REPO / "tools" / "mock_service.py")
    mock = subprocess.Popen([sys.executable, str(service), "--port", str(port), *journey.fixture],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    work = Path(tempfile.mkdtemp(prefix=f"fst-journey-{journey.name}-"))
    settings = work / "settings.json"
    pid = None
    try:
        _wait_for_port(port)
        base = f"http://127.0.0.1:{port}/"
        pid = _launch(exe, base, settings, journey.launch, journey.preset)
        for index, phase in enumerate(journey.steps):
            tree = work / f"tree-{index}.txt"
            steps = [*phase, f"tree:{tree}"]
            if shots is not None:
                steps.append(f"shot:{shots / f'{journey.name}-{index}.png'}")
            result = _uiwin("drive", "--pid", str(pid), "--steps", "; ".join(steps), check=False)
            if result.returncode != 0:
                failures.append(f"phase {index}: {result.stderr.strip() or result.stdout.strip()}")
                break
            text = tree.read_text(encoding="utf-8", errors="replace") if tree.exists() else ""
            for needle in journey.expect[index] if index < len(journey.expect) else []:
                if needle not in text:
                    failures.append(f"phase {index}: expected {needle!r} in the UIA tree")
            for needle in journey.forbid[index] if index < len(journey.forbid) else []:
                if needle in text:
                    failures.append(f"phase {index}: did not expect {needle!r} in the UIA tree")
            if journey.relaunch == index:
                _uiwin("close", "--pid", str(pid), check=False)
                pid = _launch(exe, base, settings, journey.relaunch_args, journey.preset)
    except RuntimeError as error:
        failures.append(str(error))
    finally:
        if pid is not None:
            _uiwin("close", "--pid", str(pid), check=False)
        mock.terminate()
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
    selected = [j for j in JOURNEYS if not args.names or j.name in args.names]
    if args.shots:
        args.shots.mkdir(parents=True, exist_ok=True)
    failed = 0
    for journey in selected:
        failures = run(journey, args.exe.resolve(), args.shots.resolve() if args.shots else None)
        print(f"{'PASS' if not failures else 'FAIL'} {journey.name}")
        for failure in failures:
            print(f"  - {failure}")
        failed += bool(failures)
    print(f"{len(selected) - failed}/{len(selected)} journeys passed")
    return 1 if failed else 0

# endregion


if __name__ == "__main__":
    sys.exit(main())
