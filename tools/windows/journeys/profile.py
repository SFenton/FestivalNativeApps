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
CRASH_DUMP = REPO / "tools" / "windows" / "crash_dump.py"
#: Folder for fail-fast reports and dumps (``crash_dump.py``); CI sets it inside the uploaded results (#680).
CRASH_DUMPS_VARIABLE = "FST_CRASH_DUMPS"

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
SONG_ROUTE = "/songs/fixture-pulse"
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
    # Song Detail's Score History card: the chart and its top five rows, no sort (issue #324). The tall portrait-tablet
    # window keeps the chart and rows on screen without real scrolling (issue #198).
    Journey(
        name="history",
        launch=["--route", SONG_ROUTE, *_profile("fixture-player-1:Fixture Player 1")],
        preset="portrait-tablet",
        steps=[
            ["waitfor:id=fst.history.chart@15", "waitfor:id=fst.history.bar.0@5", "scrollinto:id=fst.song-detail.history.row.20240101000000@5"],
            ["toggle:id=fst.history.bar.0", "waitfor:id=fst.history.detail@5"],
            ["toggle:id=fst.history.bar.0", "wait:1"],
        ],
        expect=[
            ["Score History", "score history, 2 of 2 scores",
             "id=fst.history.bar.1", "patterns=Toggle", "personal best", "fst.song-detail.history.row.20240105"],
            ["fst.history.detail"],
            ["fst.history.bar.0"],
        ],
        forbid=[["fst.history.detail", "fst.history.view-all", "fst.history.page-back", "fst.history.retry",
                 "fst.history.sort.open"],
                [], ["fst.history.detail"]],
    ),
    # /songs/:id/:instrument/history is the separate Player History page again (issue #324, web PlayerHistoryPage):
    # the song header, the page's Sort and every score as a leaderboard row.
    Journey(
        name="history-page",
        launch=["--route", HISTORY_ROUTE, *_profile("fixture-player-1:Fixture Player 1")],
        steps=[
            ["waitfor:id=fst.history.sort.open@15", "waitfor:id=fst.history.list@5"],
            ["invoke:id=fst.history.sort.open", "waitfor:id=fst.history.sort.mode.date@5",
             "toggle:id=fst.history.sort.mode.date", "wait:1"],
            ["invoke:id=fst.history.sort.open", "waitfor:id=fst.history.sort.direction.ascending@5",
             "toggle:id=fst.history.sort.direction.ascending", "wait:1"],
            ["invoke:id=fst.history.sort.open", "waitfor:id=fst.history.sort.reset@5",
             "invoke:id=fst.history.sort.reset", "wait:1"],
            ["invoke:id=fst.history.song", "waitfor:id=fst.song-detail.title@10", "wait:1"],
        ],
        expect=[
            ["fst.history.title", "fst.history.instrument", "Sort by Score, descending", "personal best", "fst.history.list",
             "fst.history.row.20240105"],
            ["Sort by Date, descending"],
            ["Sort by Date, ascending"],
            ["Sort by Score, descending"],
            ["fst.song-detail.title"],
        ],
        forbid=[["fst.history.chart", "fst.history.instrument.Solo_Guitar", "fst.history.message"],
                [], [], [], ["fst.history.sort.open"]],
    ),
    Journey(
        name="history-paging",
        launch=["--route", SONG_ROUTE, *_profile("fixture-history-multi:History Multi")],
        preset="portrait-tablet",
        steps=[
            ["waitfor:id=fst.history.chart@15", "waitfor:id=fst.history.bar.7@5", "scrollinto:id=fst.history.page-back@5"],
            ["invoke:id=fst.history.entry-back", "waitfor:id=fst.history.bar.2@5"],
            ["invoke:id=fst.history.entry-forward", "waitfor:id=fst.history.bar.7@5"],
            ["reveal:id=fst.history.instrument.Solo_Bass", "toggle:id=fst.history.instrument.Solo_Bass", "wait:1",
             "waitfor:id=fst.history.bar.1@5"],
            ["toggle:id=fst.history.instrument.Solo_Drums", "wait:1", "waitfor:id=fst.history.bar.0@5"],
            ["toggle:id=fst.history.instrument.Solo_Guitar", "wait:1", "waitfor:id=fst.history.bar.7@5",
             "reveal:id=fst.history.view-all", "invoke:id=fst.history.view-all", "waitfor:id=fst.history.sort.open@10",
             "wait:1"],
        ],
        expect=[
            ["fst.history.instrument.Solo_Bass", "fst.history.instrument.Solo_Drums", "5 of 8 scores",
             "fst.history.entry-back", "fst.history.page-forward", "fst.history.view-all", "View All Scores, Lead"],
            ["fst.history.bar.2"],
            ["fst.history.bar.7"],
            ["Bass score history, 2 of 2 scores"],
            ["Drums score history"],
            ["fst.history.sort.open", "610,000"],
        ],
        forbid=[["fst.history.bar.2"], ["fst.history.bar.7"], ["fst.history.bar.2"],
                ["fst.history.entry-back", "fst.history.view-all"], [], ["fst.history.chart", "fst.history.view-all"]],
    ),
    Journey(
        name="history-syncing",
        launch=["--route", SONG_ROUTE, *_profile("fixture-syncing:Syncing Player")],
        steps=[["waitfor:id=fst.history.message@15", "waitfor:id=fst.history.retry@5"],
               ["invoke:id=fst.history.retry", "wait:1", "waitfor:id=fst.history.message@15"]],
        expect=[["still being prepared", "Retry score history"], ["still being prepared"]],
        forbid=[["fst.history.chart", "fst.song-detail.history.row.", "fst.history.error"], ["fst.history.chart"]],
    ),
    Journey(
        name="history-page-syncing",
        launch=["--route", HISTORY_ROUTE, *_profile("fixture-syncing:Syncing Player")],
        steps=[["waitfor:id=fst.history.message@15", "waitfor:id=fst.history.retry@5"],
               ["invoke:id=fst.history.retry", "wait:1", "waitfor:id=fst.history.message@15"]],
        expect=[["Still Syncing", "still being prepared", "Retry score history"], ["still being prepared"]],
        forbid=[["fst.history.list", "fst.history.sort.open"], ["fst.history.list"]],
    ),
    Journey(
        name="history-failed",
        launch=["--route", SONG_ROUTE, *_profile("fixture-history-fail:History Fail")],
        steps=[["waitfor:id=fst.history.error@15", "waitfor:id=fst.history.retry@5"],
               ["invoke:id=fst.history.retry", "wait:1", "waitfor:id=fst.history.error@15"]],
        expect=[["fst.history.retry"], ["fst.history.error"]],
        forbid=[["fst.history.chart", "fst.song-detail.history.row.", "fst.history.message"], ["fst.history.chart"]],
    ),
    Journey(
        name="history-page-failed",
        launch=["--route", HISTORY_ROUTE, *_profile("fixture-history-fail:History Fail")],
        steps=[["waitfor:id=fst.service-status.retry@15"]],
        expect=[["fst.service-status.title", "fst.history.title"]],
        forbid=[["fst.history.list", "fst.history.message"]],
    ),
    # Without a player, a history link opens the page's own no-player state (web PlayerHistoryPage, issue #324): song
    # header, "No Player Selected" + Select Player, no request; the header's song opens Song Detail, which hides the card.
    Journey(
        name="history-anonymous",
        launch=["--route", HISTORY_ROUTE, *ANONYMOUS],
        steps=[["waitfor:id=fst.history.message@15", "waitfor:id=fst.history.select-player@5", "wait:1"],
               ["invoke:id=fst.history.song", "waitfor:id=fst.song-detail.title@15", "wait:3"]],
        expect=[["No Player Selected", "Select a player profile", "fst.history.select-player", "fst.history.title"],
                ["fst.song-detail.title"]],
        forbid=[["fst.history.list", "fst.history.sort.open", "fst.history.retry", "fst.songs.list"],
                ["Score History", "fst.history."]],
    ),
    # An unregistered player (404): Song Detail hides the card; the history page says why (web registered-users copy).
    Journey(
        name="history-unregistered",
        launch=["--route", SONG_ROUTE, *_profile("fixture-player-2:Fixture Player 2")],
        steps=[["waitfor:id=fst.song-detail.title@15", "wait:3"]],
        expect=[["fst.song-detail.title"]],
        forbid=[["Score History", "fst.history."]],
    ),
    Journey(
        name="history-page-unregistered",
        launch=["--route", HISTORY_ROUTE, *_profile("fixture-player-2:Fixture Player 2")],
        steps=[["waitfor:id=fst.history.message@15"]],
        expect=[["History Unavailable", "only available for registered users"]],
        forbid=[["fst.history.list", "fst.history.retry"]],
    ),
    Journey(
        name="history-no-rows",
        launch=["--route", "/songs/fixture-orbit", *_profile("fixture-player-1:Fixture Player 1")],
        steps=[["waitfor:id=fst.song-detail.title@15", "wait:3"]],
        expect=[["fst.song-detail.title"]],
        forbid=[["Score History", "fst.history."]],
    ),
    Journey(
        name="history-page-empty",
        launch=["--route", "/songs/fixture-orbit/Solo_Guitar/history", *_profile("fixture-player-1:Fixture Player 1")],
        steps=[["waitfor:id=fst.history.message@15"]],
        expect=[["No History Yet", "No score history for Lead on this song."]],
        forbid=[["fst.history.list", "fst.history.sort.open", "fst.history.retry"]],
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
        # Issue #600: the Bands scope searches bands (no gate) and drops the player rows.
        steps=[["invoke:id=fst.shell.profile", "waitfor:id=fst.profile.scope.bands@5",
                "select:id=fst.profile.scope.bands", "setvalue:id=fst.profile.search|Fixture",
                "waitfor:id=fst.profile.result.band@10"]],
        expect=[["Search players or bands", "fst.profile.result.band"]],
        forbid=[["fst.profile.retry", "fst.profile.result.fixture-player-1", "Choosing a band as your profile isn"]],
    ),
    # Inline Bands section (issue #312, .agents/pages/player-profile/windows.md): fixture-player-1 has 18 duos,
    # 8 trios and 4 quads, so Duos and Trios show six rows and View All, Quads shows all four and no View All.
    # Each phase fails on the old link-only profile (no group headers, cards or View All buttons). Owner #596: each
    # group is one card of separated rows (no gap between them) ending in the purple View All, and rows drop the pill.
    Journey(
        name="bands-section",
        launch=["--route", "/player/fixture-player-1", *ANONYMOUS],
        preset="portrait-tablet",
        steps=[
            ["waitfor:id=fst.player.overview@15", "reveal:id=fst.player.bands@10",
             "reveal:id=fst.player.bands.header.duos@15", "reveal:id=fst.player-bands.row.fixture-band-1@5",
             "reveal:id=fst.player-bands.row.fixture-pband-duo-2@5",
             "assertgap:id=fst.player-bands.row.fixture-band-1|id=fst.player-bands.row.fixture-pband-duo-2|0",
             "assertread:id=fst.player-bands.row.fixture-band-1|~^View band: (?!.*Duos).*\\. \\d+ appearances?, button",
             "reveal:id=fst.player.bands.view-all.duos@5", "assertname:id=fst.player.bands.view-all.duos|View All Bands (18), Duos",
             "assertgap:id=fst.player-bands.row.fixture-pband-duo-6|id=fst.player.bands.view-all.duos|4",
             "reveal:id=fst.player.bands.header.trios@5", "reveal:id=fst.player.bands.view-all.trios@5",
             "assertname:id=fst.player.bands.view-all.trios|View All Bands (8), Trios",
             # The shared purple CTA inside the card (view-all-cta, owner-approved variant #596), not the frosted card.
             "assertpaint:id=fst.player.bands.view-all.trios|L8,M0=#7C3AED~40",
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
                "reveal:id=fst.player.bands.empty.quads@5"],
               # #533: the page end stays reachable (virtualized sections used to pull 100% back to ~76%), and
               # Narrator reads the groups heading-first, in size order.
               ["scrollto:id=fst.player.available,100", "waitfor:id=fst.player.bands.empty.quads@5",
                "assertorder:id=fst.player.bands|id=fst.player.bands.header.duos|id=fst.player.bands.empty.duos"
                "|id=fst.player.bands.header.trios|id=fst.player.bands.empty.trios"
                "|id=fst.player.bands.header.quads|id=fst.player.bands.empty.quads"]],
        expect=[["Fixture Player 2's Bands", "No Bands Yet", "Band lineups will appear here",
                 "fst.player.bands.header.duos", "fst.player.bands.header.trios", "fst.player.bands.header.quads"],
                ["No Bands Yet", "fst.player.bands.empty.quads"]],
        forbid=[["fst.player.bands.view-all.", "fst.player-bands.row.", "fst.player.bands.retry"], []],
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
             "waitfor:id=fst.quick-links.item.bands@5", "toggle:id=fst.quick-links.item.bands",
             # The menu jumps from a Low-priority dispatch once its flyout closes (#548): wait for the jump to start
             # rather than a fixed settle, which a slow host outruns (issue #663).
             "waitgone:id=fst.quick-links.item.bands@10",
             "assertstate:id=fst.quick-links.open|name=Quick Links, current section Bands@10",
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
    """Launch the app and return its pid.

    The app keeps its data folder (``diagnostics.log`` and seen-state) next to ``settings``, so each journey starts
    from the same state and a failure can attach the app's own crash log (#680).
    """
    out = _uiwin("launch", str(exe), "--arg=--base-url", f"--arg={base}", "--arg=--settings-path",
                 f"--arg={settings}", "--extra", f"FST_DEBUG_DATA_DIR={settings.parent / 'data'}",
                 "--preset", preset, *_app_args(extra)).stdout
    for line in out.splitlines():
        if '"pid"' in line:
            return int(line.split(":")[1].strip().rstrip(","))
    raise RuntimeError(f"no pid in launch output: {out}")


def _kernel32():
    """kernel32 with the process functions the failure report uses."""
    import ctypes
    from ctypes import wintypes

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    kernel32.GetProcessTimes.argtypes = [wintypes.HANDLE, *[ctypes.POINTER(ctypes.c_ulonglong)] * 4]
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    return kernel32


def _hold(pid: int) -> int | None:
    """Open the app process for the journey's lifetime, so its exit code and exit time stay readable after it exits
    (the driver, not this script, started it, so nothing else keeps the process object alive; #680).

    Args:
        pid: App process ID.

    Returns:
        A process handle for :func:`_app_state` and :func:`_release`, or ``None`` when it can't be opened.
    """
    if sys.platform != "win32":
        return None
    return _kernel32().OpenProcess(0x101000, False, pid) or None  # SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION


def _release(handle: int | None) -> None:
    """Close a handle from :func:`_hold`."""
    if handle:
        _kernel32().CloseHandle(handle)


def _watch(pid: int, name: str) -> subprocess.Popen | None:
    """Attach :mod:`crash_dump` to the app when ``FST_CRASH_DUMPS`` names a folder, so a fail-fast that Windows Error
    Reporting doesn't record (hosted runners, #680) still leaves its exception and a dump.

    Args:
        pid: App process ID.
        name: Journey name (the report and dump file prefix).

    Returns:
        The watcher process for :func:`_unwatch`, or ``None`` when dumps are off.
    """
    folder = os.environ.get(CRASH_DUMPS_VARIABLE)
    if not folder or sys.platform != "win32":
        return None
    return subprocess.Popen([sys.executable, str(CRASH_DUMP), str(pid), folder, name],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _unwatch(watcher: subprocess.Popen | None) -> None:
    """Wait for a :func:`_watch` watcher to see the closed app exit (it may still be writing a dump), then stop it."""
    if watcher is None:
        return
    try:
        watcher.wait(timeout=60)
    except subprocess.TimeoutExpired:
        watcher.terminate()
        watcher.wait(timeout=10)


def _crash_reports(name: str) -> str:
    """The :mod:`crash_dump` reports for journey ``name`` (exception code, thread, stowed-exception parameters)."""
    folder = os.environ.get(CRASH_DUMPS_VARIABLE)
    if not folder:
        return ""
    reports = sorted(Path(folder).glob(f"{name}-*.txt"))
    return "\n".join(f"{report.name} (dump {report.with_suffix('.dmp').name}):\n"
                     f"{report.read_text(encoding='utf-8', errors='replace')}" for report in reports)


def _app_state(pid: int, handle: int | None = None) -> str:
    """Describe the app process after a failed phase: exited (with its exit code and how long ago) or running, and
    whether its windows answer messages. A crash or hang leaves no window to screenshot, so this is the evidence that
    remains (#680).

    Args:
        pid: App process ID.
        handle: The process handle :func:`_hold` opened at launch; without it an exited app is just gone.

    Returns:
        For example ``"exited with code 0xC000027B 14.2 s ago"`` or ``"running; window responding"``.
    """
    if sys.platform != "win32":
        return "unknown (not Windows)"
    import ctypes
    from ctypes import wintypes

    kernel32 = _kernel32()
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    own = handle is None
    if own:
        handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
    if not handle:
        return "gone (no process with that pid)"
    try:
        code = wintypes.DWORD()
        if not kernel32.GetExitCodeProcess(handle, ctypes.byref(code)):
            return "unknown (exit code unreadable)"
        if code.value != 259:  # STILL_ACTIVE
            times = [ctypes.c_ulonglong() for _ in range(4)]
            if not kernel32.GetProcessTimes(handle, *[ctypes.byref(t) for t in times]):
                return f"exited with code 0x{code.value:08X}"
            exited = times[1].value / 1e7 - 11644473600  # FILETIME (100 ns since 1601) to Unix time
            return f"exited with code 0x{code.value:08X} {time.time() - exited:.1f} s ago"
    finally:
        if own:
            kernel32.CloseHandle(handle)
    hung: list[bool] = []
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def visit(hwnd, _):
        owner = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid and user32.IsWindowVisible(hwnd):
            hung.append(bool(user32.IsHungAppWindow(hwnd)))
        return True

    user32.EnumWindows(callback_type(visit), 0)
    if not hung:
        return "running; no visible window"
    return "running; window not responding (hung)" if any(hung) else "running; window responding"


def _crash_events(since: float) -> str:
    """Application event log entries about the app since ``since`` (WER ``Application Error`` with the exception code
    and faulting module, ``.NET Runtime`` with the managed stack), newest first; empty when there are none.

    Args:
        since: ``time.time()`` when the journey started.

    Returns:
        The matching events as text.
    """
    if sys.platform != "win32":
        return ""
    window_ms = int((time.time() - since + 60) * 1000)
    query = f"*[System[TimeCreated[timediff(@SystemTime) <= {window_ms}]]]"
    try:
        out = subprocess.run(["wevtutil", "qe", "Application", f"/q:{query}", "/f:text", "/rd:true", "/c:50"],
                             capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired) as error:
        return f"(event log unreadable: {error})"
    events = [e for e in out.split("Event[") if journey_exe.EXE_NAME.lower() in e.lower()]
    return "\n".join("Event[" + e.strip() for e in events)


def _failure_report(pid: int, data: Path, since: float, captures: dict[str, subprocess.CompletedProcess],
                    handle: int | None = None, name: str = "") -> str:
    """Everything known about the app when a phase failed: process state, failed captures, a kept fail-fast, event log
    and the app's own ``diagnostics.log`` (#680: three failures of one step left no screenshot or tree to explain them).

    Args:
        pid: App process ID.
        data: The app's data folder (``FST_DEBUG_DATA_DIR``).
        since: ``time.time()`` when the journey started.
        captures: The failed-phase ``shot`` and ``tree`` results.
        handle: The app's process handle from :func:`_hold`.
        name: Journey name, for the :mod:`crash_dump` reports.

    Returns:
        Report text.
    """
    lines = [f"app: {_app_state(pid, handle)}"]
    for capture_name, capture in captures.items():
        if capture.returncode != 0:
            lines.append(f"{capture_name} failed: {(capture.stderr or capture.stdout).strip()[-2000:]}")
    if name and (kept := _crash_reports(name)):
        lines.append("fatal exception (crash_dump.py):\n" + kept)
    events = _crash_events(since)
    lines.append("application event log:\n" + (events or "(no entries for the app)"))
    log = data / "diagnostics.log"
    lines.append("diagnostics.log:\n" + (log.read_text(encoding="utf-8", errors="replace")[-20000:] if log.exists()
                                          else "(none)"))
    return "\n".join(lines)


def run(journey: Journey, exe: Path, shots: Path | None) -> list[str]:
    """Run one journey and return failure messages (empty when it passed)."""
    failures: list[str] = []
    port = _free_port()
    service = (REPO / "tools" / "windows" / "rivals_fixture.py") if journey.fixture else (REPO / "tools" / "mock_service.py")
    mock = subprocess.Popen([sys.executable, str(service), "--port", str(port), *journey.fixture],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    work = Path(tempfile.mkdtemp(prefix=f"fst-journey-{journey.name}-"))
    settings = work / "settings.json"
    started = time.time()
    pid = None
    handle = None
    watcher = None
    try:
        _wait_for_port(port)
        base = f"http://127.0.0.1:{port}/"
        pid = _launch(exe, base, settings, journey.launch, journey.preset)
        handle = _hold(pid)
        watcher = _watch(pid, journey.name)
        for index, phase in enumerate(journey.steps):
            tree = work / f"tree-{index}.txt"
            steps = [*phase, f"tree:{tree}"]
            if shots is not None:
                steps.append(f"shot:{shots / f'{journey.name}-{index}.png'}")
            result = _uiwin("drive", "--pid", str(pid), "--steps", "; ".join(steps), check=False)
            if result.returncode != 0:
                failures.append(f"phase {index}: {result.stderr.strip() or result.stdout.strip()}")
                captures = {}
                if shots is not None:
                    # Keep what the window showed when the phase failed (phases only shoot on success; #676).
                    captures = {
                        "shot": _uiwin("shot", "--pid", str(pid), str(shots / f"{journey.name}-{index}-failed.png"),
                                       check=False),
                        "tree": _uiwin("tree", "--pid", str(pid), str(shots / f"{journey.name}-{index}-failed.txt"),
                                       check=False),
                    }
                # A crashed or hung app leaves no window to capture; say what happened to it (#680).
                report = _failure_report(pid, work / "data", started, captures, handle, journey.name)
                failures.append(f"phase {index}: {report.splitlines()[0]}")
                if shots is not None:
                    (shots / f"{journey.name}-{index}-failed-app.txt").write_text(report, encoding="utf-8")
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
                _release(handle)
                _unwatch(watcher)
                pid = _launch(exe, base, settings, journey.relaunch_args, journey.preset)
                handle = _hold(pid)
                watcher = _watch(pid, journey.name)
    except RuntimeError as error:
        failures.append(str(error))
    finally:
        if pid is not None:
            _uiwin("close", "--pid", str(pid), check=False)
        _release(handle)
        _unwatch(watcher)
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
