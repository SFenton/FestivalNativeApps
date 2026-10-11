"""Run tools/mock_service.py with Song Detail band-preview states (Windows UI tests, issue #264).

The shared mock answers ``GET /api/leaderboard/{songId}/bands/all`` with two Duos rows and empty Trios and Quads, so
only the anonymous, appended-selected and empty states of the [song-detail](../../.agents/pages/song-detail/windows.md)
band previews are reachable. ``--bands MODE`` swaps that one route (every other route, header and publication stays
the mock's):

==============  ===================================================================================================
Mode            ``/bands/all`` answer
==============  ===================================================================================================
``demo``        The mock's answer (default)
``full``        Ten rows per size with two, three and four members, ``showLeaderboardEntryTotals`` on. With a
                ``fixture-player-*`` ``accountId``: Duos appends the player's rank-14 band, Trios highlights rank 3
                in place (``selectedBandEntry``), Quads has no selection
``far``         ``full`` with the player's appended Duos band at rank 1,234 (one shared rank rail, issue #594); the
                full ``fixture-pulse`` Duos board (``/bands/Band_Duets``) also runs to rank :data:`FAR_BOARD_TOTAL`, so
                page 40 (ranks 976–1,000) and page 400 (9,976–10,000) mix rank widths on one page
``slow``        The mock's answer after :data:`SLOW_SECONDS` (each section's loading ring)
``error``       HTTP 500 on odd-numbered reads, the mock's answer on even ones (failed state, then Retry recovers)
``frozen``      503 + ``Retry-After: 30`` + ``X-FST-Public-Read-Freeze-Reason: scrape`` (scores updating countdown)
``invalid``     200 with another song's ID (a response that fails validation is a failure, never an empty board)
==============  ===================================================================================================

Only ``far`` answers a second route: the full Song Band Leaderboard's ``fixture-pulse`` Duos board.

Usage: ``python tools/windows/song_band_preview_fixture.py --port 0 --bands full`` (other flags pass through).
"""

from __future__ import annotations

import argparse
import itertools
import sys
import threading
import time
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

#: ``--bands`` values.
MODES = ("demo", "full", "far", "slow", "error", "frozen", "invalid")
#: Rank of the appended selected Duos band in each mode that has one.
SELECTED_DUOS_RANK = {"full": 14, "far": 1_234}
#: Delay before ``slow`` answers: long enough for a UIA wait and a scan, short of the app's 30 s request timeout.
SLOW_SECONDS = 20.0
#: Ranks past this score and accuracy like it.
MAX_RANK_STEP = 60
#: Bands on ``far``'s full ``fixture-pulse`` Duos board: past both the 1,000 and the 10,000 rank-width boundaries.
FAR_BOARD_TOTAL = 10_025
#: Instruments cycled through a band's members.
INSTRUMENTS = ("Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals")
#: Band sizes in service order with their member counts.
SIZES = (("Band_Duets", 2), ("Band_Trios", 3), ("Band_Quad", 4))


def entry(band_type: str, members: int, rank: int, account_id: str | None = None) -> dict:
    """One ``SongBandLeaderboardEntry`` with ``members`` players.

    Args:
        band_type: Band size service ID.
        members: Member count (2–4).
        rank: 1-based rank; also names the band and its members.
        account_id: Selected player placed as the first member, if any.

    Returns:
        A JSON-ready row.
    """
    step = min(rank, MAX_RANK_STEP)  # Scores and accuracy stay plausible for far ranks (``far``).
    team = f"fixture-{band_type.lower()}-{rank}" if account_id is None else f"fixture-team-{account_id}-{band_type}"
    rows = [{
        "accountId": f"{team}-{i}", "displayName": f"{band_type[5:]} {rank} Member {chr(65 + i)}",
        "instruments": [INSTRUMENTS[i % len(INSTRUMENTS)]], "score": 90_000 - step * 400,
        "accuracy": 990_000 - step * 2_000, "isFullCombo": rank == 1, "stars": 6 if rank == 1 else 5,
        "difficulty": 3, "season": 10,
    } for i in range(members)]
    if account_id is not None:
        rows[0]["accountId"] = account_id
        rows[0]["displayName"] = mock_service.RIVAL_DISPLAY_NAMES.get(account_id, account_id)
    return {
        "bandId": f"band-{team}", "bandType": band_type, "teamKey": team, "comboId": None, "members": rows,
        "score": members * 90_000 - step * 1_000, "rank": rank, "accuracy": 985_000 - step * 2_000,
        "isFullCombo": rank == 1, "stars": 6 if rank == 1 else 5, "season": 10, "difficulty": 3,
        "percentile": 0.01 * step, "endTime": None,
    }


def full_payload(song_id: str, top: int, account_id: str | None, selected_rank: int = 14) -> dict:
    """The ``full`` (and ``far``) mode's ``/bands/all`` body.

    Args:
        song_id: Requested song, echoed back.
        top: Rows per size.
        account_id: Selected player from the ``accountId`` query.
        selected_rank: Rank of the player's appended Duos band.

    Returns:
        A ``{songId, showLeaderboardEntryTotals, bands}`` object.
    """
    selected = account_id if account_id and account_id.startswith("fixture-player-") else None
    bands = []
    for band_type, members in SIZES:
        rows = [entry(band_type, members, rank) for rank in range(1, top + 1)]
        player_entry = band_entry = None
        if selected and band_type == "Band_Duets":
            player_entry = entry(band_type, members, selected_rank, selected)
        elif selected and band_type == "Band_Trios" and len(rows) >= 3:
            band_entry = rows[2]
        bands.append({
            "bandType": band_type, "count": len(rows), "totalEntries": 1_234 * members,
            "localEntries": 1_234 * members, "entries": rows,
            "selectedPlayerEntry": player_entry, "selectedBandEntry": band_entry,
        })
    return {"songId": song_id, "showLeaderboardEntryTotals": True, "bands": bands}


def far_board_payload(song_id: str, top: int, offset: int, account_id: str | None) -> dict:
    """The ``far`` mode's full Duos board page (``GET /api/leaderboard/{songId}/bands/Band_Duets``).

    Args:
        song_id: Requested song, echoed back.
        top: Rows per page.
        offset: Rows skipped (``(page - 1) * top``).
        account_id: Selected player from the ``accountId`` query; a ``fixture-player-*`` one owns rank 1,234 and is
            the pinned ``selectedPlayerEntry``.

    Returns:
        A ``SongBandLeaderboardResponse`` object.
    """
    selected = account_id if account_id and account_id.startswith("fixture-player-") else None
    rank_of_selected = SELECTED_DUOS_RANK["far"]
    ranks = range(offset + 1, min(offset + top, FAR_BOARD_TOTAL) + 1)
    rows = [entry("Band_Duets", 2, rank, selected if rank == rank_of_selected else None) for rank in ranks]
    return {
        "songId": song_id, "bandType": "Band_Duets", "showLeaderboardEntryTotals": True, "count": len(rows),
        "totalEntries": FAR_BOARD_TOTAL, "localEntries": FAR_BOARD_TOTAL, "entries": rows,
        "selectedPlayerEntry": entry("Band_Duets", 2, rank_of_selected, selected) if selected else None,
        "selectedBandEntry": None,
    }


class BandsMode:
    """The fixture's ``--bands`` mode and its read counter (``error`` alternates failure and success)."""

    def __init__(self, mode: str) -> None:
        """Stores the mode.

        Args:
            mode: One of :data:`MODES`.
        """
        self.mode = mode
        self._reads = itertools.count(1)
        self._lock = threading.Lock()

    def next_read(self) -> int:
        """Numbers the next ``/bands/all`` read (1-based)."""
        with self._lock:
            return next(self._reads)


def install(state: BandsMode) -> None:
    """Patches the mock handler so ``/bands/all`` (and ``far``'s full Duos board) answers per ``state``.

    Args:
        state: Mode and read counter shared by the handler threads.
    """
    handler = mock_service.FixtureHandler
    original_get = handler.do_GET

    def do_GET(self) -> None:  # noqa: N802  (stdlib handler name)
        parsed = urlsplit(self.path)
        unsafe = any(name.lower().startswith("x-fst-selected-") or name.lower() == "x-api-key" for name in self.headers)
        board = mock_service.SONG_BAND_LEADERBOARD.fullmatch(parsed.path)
        if state.mode == "far" and not unsafe and board and board.groups() == ("fixture-pulse", "Band_Duets"):
            query = parse_qs(parsed.query)
            top = int(query.get("top", ["25"])[0])
            offset = int(query.get("offset", ["0"])[0])
            self._json(200, far_board_payload("fixture-pulse", top, offset, query.get("accountId", [None])[0]))
            return
        match = mock_service.SONG_BAND_LEADERBOARDS_ALL.fullmatch(parsed.path)
        if match is None or state.mode == "demo" or unsafe:
            original_get(self)
            return
        read = state.next_read()
        if state.mode == "slow":
            time.sleep(SLOW_SECONDS)
            original_get(self)
        elif state.mode == "error" and read % 2 == 0:
            original_get(self)
        elif state.mode == "error":
            self._json(500, {"status": "fixture_failure"})
        elif state.mode == "frozen":
            self.send_response(503)
            self.send_header("Retry-After", "30")
            self.send_header("X-Fst-Public-Read-Freeze-Reason", "scrape")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", "0")
            self.end_headers()
        elif state.mode == "invalid":
            self._json(200, {"songId": "fixture-other-song", "showLeaderboardEntryTotals": False, "bands": []})
        else:
            query = parse_qs(parsed.query)
            top = int(query.get("top", ["10"])[0])
            account = query.get("accountId", [None])[0]
            self._json(200, full_payload(match.group(1), top, account, SELECTED_DUOS_RANK[state.mode]))

    handler.do_GET = do_GET


def split_args(argv: list[str]) -> tuple[str, list[str]]:
    """Takes ``--bands MODE`` out of the command line.

    Args:
        argv: Arguments after the script name.

    Returns:
        The mode and the arguments for ``mock_service``.
    """
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--bands", choices=MODES, default="demo")
    known, rest = parser.parse_known_args(argv)
    return known.bands, rest


def main() -> None:
    """Installs the band-preview mode, then hands the remaining command line to the mock service."""
    mode, rest = split_args(sys.argv[1:])
    install(BandsMode(mode))
    sys.argv[1:] = rest
    mock_service.main()


if __name__ == "__main__":
    main()
