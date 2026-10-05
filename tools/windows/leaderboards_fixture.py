"""Run tools/mock_service.py with per-board Leaderboards overrides for UI tests.

The shared mock serves every rankings board with rows. The Leaderboards overview also has per-card empty and
failed states, so this wrapper can answer chosen top-level boards with an empty page (``--empty-board``) or a
scrape-freeze 503 with ``Retry-After: 30`` (``--frozen-board``). Board names are the service IDs used in the path:
``Solo_Bass`` for ``/api/rankings/Solo_Bass`` and ``Band_Trios`` for ``/api/rankings/bands/Band_Trios``. Player
spotlight reads (``/api/rankings/{instrument}/{accountId}``) and every other route are the unchanged mock service.
``--long-name`` renames every rank-2 player to a name too long for any row, for the name marquee (issue #292).

Usage: ``python tools/windows/leaderboards_fixture.py --port 0 --empty-board Solo_Bass --frozen-board Band_Trios``
(other flags, such as ``--large-rankings``, pass through to mock_service.py).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

BOARD = re.compile(r"^/api/rankings/(?:(bands)/)?([A-Za-z_]+)$")
LONG_NAME = "Fixture Player With An Extraordinarily Long Display Name That Never Fits"
LONG_NAME_RANK = 2


def board_override(path: str, empty: set[str], frozen: set[str]) -> tuple[str, str, bool] | None:
    """Decide whether a request is a top-level board read this wrapper answers.

    Args:
        path: Request path without the query string.
        empty: Board IDs answered with an empty page.
        frozen: Board IDs answered with a scrape-freeze 503.

    Returns:
        ``(kind, board, is_band)`` with kind ``"empty"`` or ``"frozen"``, or ``None`` to defer to the mock.
    """
    match = BOARD.fullmatch(path)
    if match is None:
        return None
    is_band, board = match.group(1) is not None, match.group(2)
    if board in frozen:
        return "frozen", board, is_band
    if board in empty:
        return "empty", board, is_band
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


def install(empty: set[str], frozen: set[str]) -> None:
    """Patch the mock handler so the chosen boards are empty or frozen.

    Args:
        empty: Board IDs answered with an empty page.
        frozen: Board IDs answered with a scrape-freeze 503.
    """
    handler = mock_service.FixtureHandler
    original = handler.do_GET

    def do_GET(self) -> None:  # noqa: N802 (stdlib handler name)
        parsed = urlsplit(self.path)
        override = board_override(parsed.path, empty, frozen)
        if override is None:
            original(self)
            return
        kind, board, is_band = override
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


def install_long_name() -> None:
    """Give every rank-2 rankings entry :data:`LONG_NAME`, for the overflowing-name marquee (issue #292).

    Patches ``mock_service._ranking_entry``, so board pages, Full Rankings pages and the rank-2 player's spotlight
    read agree on the name.
    """
    original = mock_service._ranking_entry

    def entry(rank: int, account_id: str, display_name: str) -> dict:
        return original(rank, account_id, LONG_NAME if rank == LONG_NAME_RANK else display_name)

    mock_service._ranking_entry = entry


def main() -> None:
    """Parse this wrapper's flags, then hand the rest to the mock service's own CLI."""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--empty-board", action="append", default=[])
    parser.add_argument("--frozen-board", action="append", default=[])
    parser.add_argument("--long-name", action="store_true")
    options, rest = parser.parse_known_args()
    install(set(options.empty_board), set(options.frozen_board))
    if options.long_name:
        install_long_name()
    sys.argv = [sys.argv[0], *rest]
    mock_service.main()


if __name__ == "__main__":
    main()
