"""Songs, Item Shop, Song Detail and Paths UI journeys on Windows through uiwin.py (FlaUI driver).

Starts ``tools/mock_service.py`` (synthetic fixtures) on a private loopback port, then for each scenario launches
the Debug app with a throwaway settings file (``FST_SETTINGS_PATH``) and an in-memory debug profile, drives it by
``fst.*`` AutomationIds and fails on the first missing element (``waitfor:``). Scenarios: selected-player rows
with Shop accents, Item Shop sort and Shop filter drafts, the Item Shop page (grid, list, Song Detail link),
Song Detail with Paths image/text/not-generated states, no selected player, and a hidden Item Shop. Lock-tolerant
Songs states (search match/no results, sort modes, Jump index, General filter empty result, syncing and denied
players, damaged saved filter, service error) and Item Shop states (filter groups, no-match reset, list/grid,
compact-forced grid, failed feed, hidden) use only UIA patterns, so they also pass on a locked console. Official
Shop links are never opened. With ``--shots DIR`` it also captures screenshots of each scenario.

Songs Sort states (issue #218, ``songs-sort-*``): default/changed/reset/applied with a player (Last Played), a
``{relaunch}`` step that restarts the app on the same settings file (relaunch-persisted), the instrument modes, a
loaded and sectioned Item Shop sort (both directions, and one bucket after a search), a hidden Shop, and the one-member,
empty and unavailable Shop feeds. The app sends no fixture ``scenario`` query, so those three run behind a loopback
proxy (``SHOP_FEEDS``) that adds it to ``/api/shop`` only.

Usage: ``python tools/windows/songs_journey.py [--port 18751] [--shots DIR] [--only NAME[,NAME…]] [--sizes compact,medium,wide]``
"""

from __future__ import annotations

import argparse
import http.server
import json
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.parse
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
    # Lock-tolerant Songs states (#194): UIA patterns, Value writes and PrintWindow shots only, no SendInput, so they
    # also pass while the console session is locked.
    "songs-search": (
        PLAYER, "/songs", {},
        [
            "waitfor:id=fst.songs.row.fixture-pulse@20",
            "setvalue:id=fst.songs.search|orbit",
            "waitgone:id=fst.songs.row.fixture-pulse@10",
            "waitfor:id=fst.songs.row.fixture-orbit",
            "{shot:songs-search}",
            "setvalue:id=fst.songs.search|zzzz",
            "waitfor:name=No Results@10",
            "waitgone:id=fst.songs.row.fixture-orbit",
            # Hidden state: no rows, no sections, no Jump (issue #231).
            "waitgone:id=fst.songs.section-index-button@5",
            "{shot:songs-search-empty}",
            "setvalue:id=fst.songs.search|",
            "waitfor:id=fst.songs.row.fixture-pulse@10",
            "waitfor:id=fst.songs.section-index-button@5",
        ],
    ),
    "songs-sort": (
        PLAYER, "/songs", {},
        [
            "waitfor:id=fst.songs.row.fixture-pulse@20",
            "expand:id=fst.songs.sort",
            "waitfor:id=fst.songs.sort.mode@5",
            "select:name=Artist",
            "select:id=fst.songs.sort.direction.descending",
            "{shot:songs-sort-flyout}",
            "collapse:id=fst.songs.sort",
            "waitgone:id=fst.songs.sort.mode@5",
            "waitfor:id=fst.songs.section-index-button@5",
            # The artist state: the index lists artist initials and focuses the topmost one (issue #231).
            "invoke:id=fst.songs.section-index-button",
            "waitfor:id=fst.songs.section-index@5",
            "assertfocus:class=GridViewItem",
            "{shot:songs-jump-artist}",
            "key:esc",
            "waitgone:id=fst.songs.section-index@5",
            # No quick-jump under the Year sort (operator 2026-09-28): decade headers stay, Jump hides.
            "expand:id=fst.songs.sort",
            "select:name=Year@5",
            "collapse:id=fst.songs.sort",
            "waitgone:id=fst.songs.section-index-button@5",
            "waitfor:name=2020s@5",
            "{shot:songs-sort-year}",
            "expand:id=fst.songs.sort",
            "invoke:id=fst.songs.sort.reset@5",
            "collapse:id=fst.songs.sort",
            "waitfor:id=fst.songs.section-index-button@5",
        ],
    ),
    # Songs Sort states (issue #218). The flyout applies every change live (no Cancel/Apply, so no discard-confirm);
    # the button's summary label ("Year ↓") is the applied-state assertion. The player comes from the settings file, not
    # FST_DEBUG_PROFILE: debug profiles keep settings in memory, and this scenario relaunches to read them back.
    "songs-sort-states": (
        {}, "/songs", {"selectedPlayer": {"accountId": "fixture-player-1", "displayName": "Fixture Player 1"}},
        [
            "waitfor:id=fst.songs.row.fixture-pulse@20",
            "waitfor:name=Title ↑",
            "expand:id=fst.songs.sort",
            "waitfor:id=fst.songs.sort.mode@5",
            "waitfor:id=fst.songs.sort.direction",
            "waitfor:id=fst.songs.sort.direction.ascending",
            "waitfor:id=fst.songs.sort.direction.descending",
            "waitfor:id=fst.songs.sort.reset",
            "waitfor:name=Last Played",  # profile: a selected player adds Last Played
            "waitfor:name=Item Shop",
            "waitgone:name=Score",  # instrument modes need a chart filter
            "{shot:songs-sort-default}",
            "select:name=Year",
            "waitfor:name=Year ↑@5",  # changed-mode, applied live
            "select:id=fst.songs.sort.direction.descending",
            "waitfor:name=Year ↓@5",  # changed-direction
            "{shot:songs-sort-changed}",
            "collapse:id=fst.songs.sort",
            "waitgone:id=fst.songs.sort.mode@5",
            "waitfor:name=2020s@5",  # applied: decade sections, no Jump index
            "waitgone:id=fst.songs.section-index-button@5",
            "{relaunch}",
            "waitfor:name=Year ↓@20",  # relaunch-persisted
            "waitfor:name=2020s@10",
            "waitgone:id=fst.songs.section-index-button@5",
            "expand:id=fst.songs.sort",
            "invoke:id=fst.songs.sort.reset@5",
            "waitfor:name=Title ↑@5",  # reset-draft applies the default at once
            "collapse:id=fst.songs.sort",
            "waitfor:id=fst.songs.section-index-button@5",
        ],
    ),
    "songs-sort-anonymous": (
        {"FST_DEBUG_ANONYMOUS": "1"}, "/songs", {},
        [
            "waitfor:id=fst.songs.row.fixture-pulse@20",
            "expand:id=fst.songs.sort",
            "waitfor:id=fst.songs.sort.mode@5",
            "waitfor:name=Has FC",
            "waitgone:name=Last Played",
            "collapse:id=fst.songs.sort",
        ],
    ),
    "songs-sort-instrument": (
        PLAYER, "/songs", {"songFilter": {"Instrument": "Lead"}},
        [
            "waitfor:id=fst.songs.row.fixture-pulse@20",
            "expand:id=fst.songs.sort",
            "waitfor:id=fst.songs.sort.mode@5",
            "waitfor:name=Score",
            "waitfor:name=Percentage",
            "{shot:songs-sort-instrument}",
            "select:name=Score",
            "waitfor:name=Score ↑@5",
            # Nine instrument modes make the form taller than the window: the flyout scrolls (large content).
            "scrollinto:name=Max Score Diff@5",
            "waitfor:name=Max Score Diff",
            "scrollinto:id=fst.songs.sort.reset",
            "invoke:id=fst.songs.sort.reset",
            "waitfor:name=Title ↑@5",
            "collapse:id=fst.songs.sort",
        ],
    ),
    "songs-sort-shop": (
        PLAYER, "/songs", {"songSort": "Shop"},
        [
            "waitfor:name=Item Shop ↑@20",
            # Members first: Leaving Tomorrow (Fixture Orbit) then In Shop (Fixture Pulse). The first section is named by
            # the sticky header (its in-list heading is collapsed), so the later bucket's ID is the assertion.
            "waitfor:id=fst.songs.shop-section.in-shop@10",
            "waitfor:id=fst.songs.section-index-button",
            "waitgone:id=fst.songs.sort-paused",
            "{shot:songs-sort-shop}",
            "expand:id=fst.songs.sort",
            "select:id=fst.songs.sort.direction.descending@5",
            "collapse:id=fst.songs.sort",
            "waitfor:id=fst.songs.shop-section.leaving-tomorrow@10",
            # One bucket: a search leaving only the Leaving Tomorrow row drops headings and the Jump index.
            "setvalue:id=fst.songs.search|orbit",
            "waitgone:id=fst.songs.row.fixture-pulse@10",
            "waitgone:id=fst.songs.shop-section.leaving-tomorrow",
            "waitgone:id=fst.songs.shop-section.in-shop",
            "waitgone:id=fst.songs.section-index-button",
            "{shot:songs-sort-shop-one-bucket}",
            "setvalue:id=fst.songs.search|",
            "waitfor:id=fst.songs.row.fixture-pulse@10",
        ],
    ),
    "songs-sort-shop-single": (
        PLAYER, "/songs", {"songSort": "Shop"},
        [
            "waitfor:name=Item Shop ↑@20",
            "waitfor:id=fst.songs.shop-section.not-in-shop@10",
            "waitgone:id=fst.songs.sort-paused",
        ],
    ),
    "songs-sort-shop-hidden": (
        PLAYER, "/songs", {"songSort": "Shop", "hideShop": True},
        [
            "waitfor:id=fst.songs.sort-paused@20",
            "waitgone:id=fst.songs.shop-section.in-shop",
            "expand:id=fst.songs.sort",
            "waitfor:id=fst.songs.sort.mode@5",
            "waitfor:name=Has FC",
            "waitgone:name=Item Shop",
            "{shot:songs-sort-shop-hidden}",
            "collapse:id=fst.songs.sort",
        ],
    ),
    "songs-sort-shop-empty": (
        PLAYER, "/songs", {"songSort": "Shop"},
        [
            # A known-empty feed still applies: every row is Not In Shop, one unlabeled section, no Jump, no notice.
            "waitfor:name=Item Shop ↑@20",
            "waitfor:id=fst.songs.row.fixture-pulse@10",
            "waitgone:id=fst.songs.shop-section.not-in-shop",
            "waitgone:id=fst.songs.section-index-button",
            "waitgone:id=fst.songs.sort-paused",
        ],
    ),
    "songs-sort-shop-unavailable": (
        PLAYER, "/songs", {"songSort": "Shop"},
        [
            "waitfor:id=fst.songs.sort-paused@20",
            "waitfor:name=Item Shop ↑",  # the saved choice stays; Title order shows until the Shop loads
            "waitfor:id=fst.songs.section-index-button",
            "waitgone:id=fst.songs.shop-section.in-shop",
            "{shot:songs-sort-shop-unavailable}",
        ],
    ),
    "songs-jump": (
        PLAYER, "/songs", {},
        [
            "waitfor:id=fst.songs.row.fixture-pulse@20",
            "assertname:id=fst.songs.section-header|F",
            # Issue #231: opening the index moves focus onto the letter of the section at the top of the list.
            "focus:id=fst.songs.section-index-button",
            "key:enter",
            "waitfor:id=fst.songs.section-index@5",
            "assertfocus:name=F",
            "waitgone:id=fst.songs.row.fixture-pulse@5",
            "{shot:songs-jump}",
            # Escape also closes the index with focus back on the Jump button (not only from inside the letters).
            "focus:id=fst.songs.section-index-button",
            "key:esc",
            "waitgone:id=fst.songs.section-index@5",
            "assertfocus:id=fst.songs.section-index-button",
            "invoke:id=fst.songs.section-index-button",
            "waitfor:id=fst.songs.section-index@5",
            "key:esc",
            "waitgone:id=fst.songs.section-index@5",
            "assertfocus:id=fst.songs.section-index-button",
            "invoke:id=fst.songs.section-index-button",
            "waitfor:id=fst.songs.section-index@5",
            "invoke:name=F",
            "waitfor:id=fst.songs.row.fixture-pulse@5",
            "waitgone:id=fst.songs.section-index@5",
            "assertname:id=fst.songs.section-header|F",
        ],
    ),
    "songs-filter-empty": (
        {"FST_DEBUG_ANONYMOUS": "1"}, "/songs", {},
        [
            "waitfor:id=fst.songs.row.fixture-pulse@20",
            "expand:id=fst.songs.filter",
            "waitfor:id=fst.songs.filter.year@5",
            "waitgone:id=fst.songs.filter.score.global",
            "expand:id=fst.songs.filter.year",
            "toggle:id=fst.songs.filter.year.2020@5",
            "{shot:songs-filter-year}",
            "collapse:id=fst.songs.filter",
            "waitfor:name=No Results@10",
            # Issue #377: no Clear Filters button in the empty state; the flyout's Reset is the way back.
            "waitgone:name=Clear Filters",
            "{shot:songs-filter-empty}",
            "expand:id=fst.songs.filter",
            "waitfor:id=fst.songs.filter.reset@5",
            "invoke:id=fst.songs.filter.reset",
            "collapse:id=fst.songs.filter",
            "waitfor:id=fst.songs.row.fixture-pulse@10",
        ],
    ),
    "songs-syncing": (
        {"FST_DEBUG_PROFILE": "fixture-syncing:Syncing Player"}, "/songs", {},
        [
            "waitfor:id=fst.songs.row.fixture-pulse@20",
            # ItemsRepeater and StackPanel IDs have no UIA peer: find the InfoBar notice and its message text instead.
            "waitfor:class=Microsoft.UI.Xaml.Controls.InfoBar@10",
            "waitfor:name=This player's scores are still syncing. Scores appear once they're published.",
            "waitfor:name=Scores syncing",
            "{shot:songs-syncing}",
        ],
    ),
    "songs-denied": (
        {"FST_DEBUG_PROFILE": "fixture-denied:Denied Player"}, "/songs", {},
        [
            "waitfor:id=fst.songs.row.fixture-pulse@20",
            "waitfor:class=Microsoft.UI.Xaml.Controls.InfoBar@10",
            "waitfor:name=Scores unavailable",
            "{shot:songs-denied}",
        ],
    ),
    "songs-filter-invalid": (
        PLAYER, "/songs", {"songGeneralFilter": {"excludedDecades": [1985]}},
        [
            "waitfor:id=fst.songs.filter-invalid@20",
            "waitgone:id=fst.songs.row.fixture-pulse",
            "{shot:songs-filter-invalid}",
            "invoke:id=fst.songs.filter-reset-invalid",
            "waitfor:id=fst.songs.row.fixture-pulse@10",
        ],
    ),
    "songs-error": (
        # A closed loopback port: the catalogue read fails and Songs shows its retryable service status.
        {**PLAYER, "FST_BASE_URL": "http://127.0.0.1:9/"}, "/songs", {},
        [
            "waitfor:id=fst.service-status.retry@60",
            "waitfor:id=fst.service-status.title",
            "waitgone:id=fst.songs.list",
            "{shot:songs-error}",
        ],
    ),
    # Lock-tolerant Item Shop states (#206): filter groups, no-match reset, both layouts and Song Detail by Invoke.
    # Empty, failed-feed and catalogue-unavailable states need tools/windows/shop_fixture.py (a11y.json shop-* pages).
    "shop-states": (
        PLAYER, "/shop", {},
        [
            "waitfor:id=fst.shop.song.fixture-pulse@20",
            "waitfor:id=fst.shop.badge.leaving.fixture-orbit",
            "waitfor:name=2 songs",
            "waitfor:id=fst.shop.view-toggle",
            # Include switches (#376): turning one off hides that group.
            "expand:id=fst.shop.filter",
            "waitfor:id=fst.shop.filter.new@5",
            "toggle:id=fst.shop.filter.new",
            "collapse:id=fst.shop.filter",
            "waitgone:id=fst.shop.song.fixture-pulse@5",
            "waitfor:id=fst.shop.song.fixture-orbit",
            "waitfor:name=1 of 2 songs",
            "{shot:shop-filter-no-new}",
            "expand:id=fst.shop.filter",
            "toggle:id=fst.shop.filter.new@5",
            "toggle:id=fst.shop.filter.leaving",
            "collapse:id=fst.shop.filter",
            "waitgone:id=fst.shop.song.fixture-orbit@5",
            "waitfor:id=fst.shop.song.fixture-pulse",
            "expand:id=fst.shop.filter",
            "toggle:id=fst.shop.filter.new@5",
            "collapse:id=fst.shop.filter",
            "waitfor:id=fst.shop.filter.empty@5",
            "waitfor:name=0 of 2 songs",
            "{shot:shop-filter-empty}",
            "expand:id=fst.shop.filter",
            "waitfor:id=fst.shop.filter.reset@5",
            "invoke:id=fst.shop.filter.reset",
            "collapse:id=fst.shop.filter",
            "waitfor:id=fst.shop.song.fixture-orbit@5",
            "waitfor:id=fst.shop.song.fixture-pulse",
            "waitfor:name=2 songs",
            "invoke:id=fst.shop.view-toggle",
            "waitfor:id=fst.shop.list@5",
            "waitfor:id=fst.shop.badge.new.fixture-pulse@5",
            "waitfor:id=fst.shop.external.fixture-orbit",
            "{shot:shop-list}",
            "invoke:id=fst.shop.view-toggle",
            "waitfor:id=fst.shop.grid@5",
            "invoke:id=fst.shop.song.fixture-pulse@5",
            "waitfor:id=fst.song-detail.title@15",
        ],
    ),
    "shop-compact-states": (
        PLAYER, "/shop", {"shopViewMode": "List"},
        [
            # Compact forces the grid and hides the toggle, even with the List preference saved.
            "waitfor:id=fst.shop.grid@20",
            "waitfor:id=fst.shop.song.fixture-pulse",
            "waitgone:id=fst.shop.view-toggle",
            "waitgone:id=fst.shop.list",
            "invoke:id=fst.shop.song.fixture-orbit",
            "waitfor:id=fst.song-detail.title@15",
        ],
    ),
    "shop-error": (
        # A closed loopback port: the feed read fails; Filter and the view toggle leave with the offers.
        {**PLAYER, "FST_BASE_URL": "http://127.0.0.1:9/"}, "/shop", {},
        [
            "waitfor:id=fst.service-status.retry@60",
            "waitfor:id=fst.service-status.title",
            "waitgone:id=fst.shop.filter",
            "waitgone:id=fst.shop.view-toggle",
            "waitgone:id=fst.shop.grid",
            "{shot:shop-error}",
        ],
    ),
    "shop-hidden-states": (
        PLAYER, "/shop", {"hideShop": True},
        [
            "waitfor:id=fst.shop.hidden@20",
            "waitgone:id=fst.shop.filter",
            "waitgone:id=fst.shop.view-toggle",
            "waitgone:id=fst.shop.grid",
        ],
    ),
}


# Scenarios that only make sense at some window sizes (compact windows force the Shop grid, without the toggle).
SIZES = {"shop": {"medium", "wide"}, "shop-compact": {"compact"}, "shop-states": {"medium", "wide"},
         "shop-compact-states": {"compact"}}

# Scenarios whose /api/shop read carries a mock_service.py ``scenario`` query (through ShopScenarioProxy).
SHOP_FEEDS = {
    "songs-sort-shop-single": "shop-single",
    "songs-sort-shop-empty": "shop-empty",
    "songs-sort-shop-unavailable": "shop-error",
}

RELAUNCH = "{relaunch}"


def shop_path(path: str, scenario: str) -> str:
    """Adds the fixture ``scenario`` query to an ``/api/shop`` request path; other paths are unchanged.

    Args:
        path: Request path with any query.
        scenario: mock_service.py Shop scenario (``shop-single``, ``shop-empty``, ``shop-error``).

    Returns:
        The path to forward.
    """
    parts = urllib.parse.urlsplit(path)
    if parts.path != "/api/shop":
        return path
    query = [(k, v) for k, v in urllib.parse.parse_qsl(parts.query, keep_blank_values=True) if k != "scenario"]
    query.append(("scenario", scenario))
    return urllib.parse.urlunsplit(("", "", parts.path, urllib.parse.urlencode(query), ""))


def segments(steps: list[str]) -> list[list[str]]:
    """Splits scenario steps at ``{relaunch}`` markers (each segment runs in a fresh app on the same settings file).

    Args:
        steps: Scenario steps.

    Returns:
        One or more step lists.
    """
    out: list[list[str]] = [[]]
    for step in steps:
        if step == RELAUNCH:
            out.append([])
        else:
            out[-1].append(step)
    return out


class ShopScenarioProxy(http.server.ThreadingHTTPServer):
    """Loopback proxy to the fixture service that selects a Shop scenario for ``/api/shop`` (see :func:`shop_path`)."""

    def __init__(self, upstream: int, scenario: str) -> None:
        """Binds an ephemeral loopback port.

        Args:
            upstream: mock_service.py port.
            scenario: Shop scenario for ``/api/shop``.
        """
        self.upstream, self.scenario = upstream, scenario
        super().__init__(("127.0.0.1", 0), _ProxyHandler)

    @property
    def port(self) -> int:
        """The bound port."""
        return self.server_address[1]


class _ProxyHandler(http.server.BaseHTTPRequestHandler):
    """Forwards one request to the fixture service, keeping status, headers and body."""

    server: ShopScenarioProxy
    HOP = {"connection", "keep-alive", "transfer-encoding", "host", "content-length"}

    def _forward(self) -> None:
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        url = f"http://127.0.0.1:{self.server.upstream}{shop_path(self.path, self.server.scenario)}"
        headers = {k: v for k, v in self.headers.items() if k.lower() not in self.HOP}
        request = urllib.request.Request(url, data=body, headers=headers, method=self.command)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                status, reply, payload = response.status, response.headers, response.read()
        except urllib.error.HTTPError as error:
            status, reply, payload = error.code, error.headers, error.read()
        self.send_response(status)
        for key, value in reply.items():
            if key.lower() not in self.HOP:
                self.send_header(key, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(payload)

    do_GET = do_POST = do_HEAD = _forward

    def log_message(self, format: str, *args: object) -> None:  # noqa: A002  (base-class signature)
        """Silences per-request logging."""


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
    proxy = None
    if name in SHOP_FEEDS:
        proxy = ShopScenarioProxy(port, SHOP_FEEDS[name])
        threading.Thread(target=proxy.serve_forever, daemon=True).start()
    origin = proxy.port if proxy else port
    try:
        with tempfile.TemporaryDirectory() as folder:
            settings_path = Path(folder) / "settings.json"
            if settings:
                settings_path.write_text(json.dumps({"version": 1, **settings}), encoding="utf-8")
            args = ["launch", str(EXE), "--timeout", "60", "--wait", "1", "--preset", size,
                    "--extra", f"FST_SETTINGS_PATH={settings_path}"]
            # A scenario's own FST_BASE_URL (e.g. a closed port) replaces the fixture origin; --base-url would override it.
            if "FST_BASE_URL" not in env:
                args.append(f"--arg=--base-url=http://127.0.0.1:{origin}/")
            for key, value in env.items():
                args += ["--extra", f"{key}={value}"]
            if route:
                args += ["--route", route]
            for index, part in enumerate(segments(steps)):
                uiwin(*args)
                try:
                    steps_file = Path(folder) / f"steps-{index}.txt"
                    steps_file.write_text("\n".join(expand(part, shots, size)), encoding="utf-8")
                    uiwin("drive", "--steps-file", str(steps_file))
                finally:
                    uiwin("close")
            print(f"PASS {name} [{size}]")
    finally:
        if proxy:
            proxy.shutdown()
            proxy.server_close()


def main() -> int:
    """Runs the selected scenarios.

    Returns:
        Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=18751)
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
        for name in names:
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
