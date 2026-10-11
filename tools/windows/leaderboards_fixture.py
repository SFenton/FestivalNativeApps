"""Run tools/mock_service.py with per-board Leaderboards overrides for UI tests.

The shared mock serves every rankings board with rows. The Leaderboards overview also has per-card empty and
failed states, so this wrapper can answer chosen top-level boards with an empty page (``--empty-board``) or a
scrape-freeze 503 with ``Retry-After: 30`` (``--frozen-board``). Board names are the service IDs used in the path:
``Solo_Bass`` for ``/api/rankings/Solo_Bass`` and ``Band_Trios`` for ``/api/rankings/bands/Band_Trios``. Player
spotlight reads (``/api/rankings/{instrument}/{accountId}``) and every other route are the unchanged mock service.
``--long-name`` renames every rank-2 player (rankings and solo song boards) to a name too long for any row, for the
name marquee (issue #292) and the song board's trimmed-name tool tip (issue #197).
``--slow-board`` answers a chosen board normally after :data:`SLOW_SECONDS`, so its card's loading rows stay on screen
next to loaded cards (issue #281: placeholder rows as tall as loaded rows).
``--slow-song-board <songId>/<instrument>`` answers that song board's first page (``offset`` 0) after
:data:`SLOW_SONG_BOARD_SECONDS`, so its first-load spinner stays up while the selected player's score index (and the
board's pinned row) is already loaded (issue #295: the pinned row stays hidden until the rows reveal). With
``--slow-leeway-only`` only reads carrying ``leeway`` are delayed, so the first load is quick and the reload after a
Filter Invalid Scores change keeps its spinner (and the gated pinned row) up.

Usage: ``python tools/windows/leaderboards_fixture.py --port 0 --empty-board Solo_Bass --frozen-board Band_Trios``
(other flags, such as ``--large-rankings``, pass through to mock_service.py).
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

BOARD = re.compile(r"^/api/rankings/(?:(bands)/)?([A-Za-z_]+)$")
LONG_NAME = "Fixture Player With An Extraordinarily Long Display Name That Never Fits"
LONG_NAME_RANK = 2
#: Delay before a ``--slow-board`` read is answered.
SLOW_SECONDS = 25.0
SONG_BOARD = re.compile(r"^/api/leaderboard/([a-z0-9-]+)/([A-Za-z_]+)$")
#: Delay before a ``--slow-song-board`` first page is answered.
SLOW_SONG_BOARD_SECONDS = 15.0


def slow_song_board(path: str, query: dict[str, list[str]], slow: set[str], leeway_only: bool = False) -> bool:
    """Whether a request is the first page of a ``--slow-song-board`` song board.

    Args:
        path: Request path without the query string.
        query: Parsed query string.
        slow: ``<songId>/<instrument>`` boards whose first page is slow.
        leeway_only: Delay only reads that carry a ``leeway`` query (a Filter Invalid Scores reload).

    Returns:
        ``True`` for an ``offset`` 0 (or offset-less) read of a chosen board (with ``leeway`` when ``leeway_only``);
        later pages are never delayed here.
    """
    match = SONG_BOARD.fullmatch(path)
    return (match is not None and f"{match.group(1)}/{match.group(2)}" in slow
            and query.get("offset", ["0"]) == ["0"] and (not leeway_only or "leeway" in query))


def board_override(path: str, empty: set[str], frozen: set[str],
                   slow: set[str] = frozenset()) -> tuple[str, str, bool] | None:
    """Decide whether a request is a top-level board read this wrapper answers.

    Args:
        path: Request path without the query string.
        empty: Board IDs answered with an empty page.
        frozen: Board IDs answered with a scrape-freeze 503.
        slow: Board IDs answered by the mock after :data:`SLOW_SECONDS`.

    Returns:
        ``(kind, board, is_band)`` with kind ``"empty"``, ``"frozen"`` or ``"slow"``, or ``None`` to defer to the mock.
    """
    match = BOARD.fullmatch(path)
    if match is None:
        return None
    is_band, board = match.group(1) is not None, match.group(2)
    if board in frozen:
        return "frozen", board, is_band
    if board in empty:
        return "empty", board, is_band
    if board in slow:
        return "slow", board, is_band
    return None


def empty_page(board: str, is_band: bool, query: dict[str, list[str]]) -> dict:
    """Build an empty rankings page with the same shape as the mock's populated one.

    Args:
        board: Instrument or band-type service ID.
        is_band: Whether this is a band board.
        query: Parsed query string.

    Returns:
        JSON body with no entries and a zero total.
    """
    page = {
        "rankBy": query.get("rankBy", ["totalscore"])[0],
        "page": int(query.get("page", ["1"])[0]),
        "pageSize": int(query.get("pageSize", ["10"])[0]),
        "entries": [],
    }
    return {"bandType": board, **page, "totalTeams": 0} if is_band else {"instrument": board, **page, "totalAccounts": 0}


def install(empty: set[str], frozen: set[str], slow: set[str] = frozenset(),
            slow_song: set[str] = frozenset(), slow_leeway_only: bool = False) -> None:
    """Patch the mock handler so the chosen boards are empty, frozen or slow.

    Args:
        empty: Board IDs answered with an empty page.
        frozen: Board IDs answered with a scrape-freeze 503.
        slow: Board IDs answered by the mock after :data:`SLOW_SECONDS` (the server is threaded).
        slow_song: ``<songId>/<instrument>`` song boards whose first page the mock answers after
            :data:`SLOW_SONG_BOARD_SECONDS`.
        slow_leeway_only: Delay only ``slow_song`` reads that carry a ``leeway`` query.
    """
    handler = mock_service.FixtureHandler
    original = handler.do_GET

    def do_GET(self) -> None:  # noqa: N802 (stdlib handler name)
        parsed = urlsplit(self.path)
        if slow_song and slow_song_board(parsed.path, parse_qs(parsed.query, keep_blank_values=True), slow_song,
                                        slow_leeway_only):
            time.sleep(SLOW_SONG_BOARD_SECONDS)
            original(self)
            return
        override = board_override(parsed.path, empty, frozen, slow)
        if override is None:
            original(self)
            return
        kind, board, is_band = override
        if kind == "slow":
            time.sleep(SLOW_SECONDS)
            original(self)
            return
        if kind == "frozen":
            self.send_response(503)
            self.send_header("Retry-After", "30")
            self.send_header("X-Fst-Public-Read-Freeze-Reason", "scrape")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        self._json(200, empty_page(board, is_band, parse_qs(parsed.query, keep_blank_values=True)))

    handler.do_GET = do_GET
    # Card reads plus artwork can overflow socketserver's default backlog of 5 (see rivals_fixture.py).
    mock_service.FixtureServer.request_queue_size = 128


def long_song_board_names(payload: dict | None) -> dict | None:
    """Rename the rank-2 entry of a song board page (``/api/leaderboard/{songId}/{instrument}``) to :data:`LONG_NAME`.

    Args:
        payload: A response body about to be written.

    Returns:
        A copy with the rank-2 entry renamed when ``payload`` is a solo song board page (``songId``, ``instrument``
        and ``entries``), else ``payload`` unchanged.
    """
    if not (isinstance(payload, dict) and "songId" in payload and "instrument" in payload
            and isinstance(payload.get("entries"), list)):
        return payload
    entries = [{**entry, "displayName": LONG_NAME} if entry.get("rank") == LONG_NAME_RANK else entry
               for entry in payload["entries"]]
    return {**payload, "entries": entries}


def install_long_name() -> None:
    """Give every rank-2 rankings and song board entry :data:`LONG_NAME`, for the overflowing-name marquee (issue #292)
    and the song board's trimmed-name tooltip (issue #197).

    Patches ``mock_service._ranking_entry``, so board pages, Full Rankings pages and the rank-2 player's spotlight
    read agree on the name, and the handler's JSON writer for song board pages.
    """
    original = mock_service._ranking_entry

    def entry(rank: int, account_id: str, display_name: str) -> dict:
        return original(rank, account_id, LONG_NAME if rank == LONG_NAME_RANK else display_name)

    mock_service._ranking_entry = entry
    handler = mock_service.FixtureHandler
    write = handler._json

    def _json(self, status: int, payload: dict | None, **kwargs) -> None:
        write(self, status, long_song_board_names(payload), **kwargs)

    handler._json = _json


def main() -> None:
    """Parse this wrapper's flags, then hand the rest to the mock service's own CLI."""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--empty-board", action="append", default=[])
    parser.add_argument("--frozen-board", action="append", default=[])
    parser.add_argument("--long-name", action="store_true")
    parser.add_argument("--slow-board", action="append", default=[])
    parser.add_argument("--slow-song-board", action="append", default=[])
    parser.add_argument("--slow-leeway-only", action="store_true")
    options, rest = parser.parse_known_args()
    install(set(options.empty_board), set(options.frozen_board), set(options.slow_board), set(options.slow_song_board),
            options.slow_leeway_only)
    if options.long_name:
        install_long_name()
    sys.argv = [sys.argv[0], *rest]
    mock_service.main()


if __name__ == "__main__":
    main()
