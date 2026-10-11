"""Run the anonymized Windows fixture (``rivals_fixture.py``) with every Full Rankings state reachable.

On top of ``rivals_fixture.py`` (anonymized Rivals names, larger listen backlog, ``Connection: close``) this
wrapper always serves ``--large-rankings`` (1,200 accounts, 48 pages of 25) and adds three rankings scenarios
that the shared mock service does not have:

- rank 13 of every instrument is the production **anonymous row** (empty ``accountId``, no ``displayName``;
  [full-rankings spec](../../.agents/pages/full-rankings/spec.md)), shown as "Unknown User";
- ``GET /api/rankings/Solo_PeripheralCymbals`` is an empty board (``totalAccounts: 0``);
- ``GET /api/rankings/Solo_PeripheralDrums`` fails with HTTP 500 (the page's failure state).

``--rankings-delay SECONDS`` answers every board read (``/api/rankings/{instrument}``, not the selected player's
own-rank read) after that delay, so a journey can assert what a reload shows while the spinner is up (issue #270).
``--bands-delay SECONDS`` does the same for the band boards (``/api/rankings/bands/{type}``,
``/api/leaderboard/{song}/bands/{type}`` and ``/api/player/{id}/bands``, not Song Detail's ``bands/all`` previews or
a band's history/songs reads): their load and reload spinners stay up for accessibility pages (issue #431).

Selected-player spotlight states come from the mock's own accounts: ``fixture-rank-40`` (page 2: the pinned row
jumps there, then opens the profile), ``fixture-rank-fail`` (inline failure) and any other unknown ``fixture-*`` ID (404: not ranked).

Usage: ``python tools/windows/rankings_fixture.py --port 0`` (same flags as ``mock_service.py``), or
``a11y_matrix.py --fixture tools/windows/rankings_fixture.py --pages tools/windows/journeys/full-rankings.json``.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)
import rivals_fixture  # noqa: E402  (sibling wrapper)

#: Rank served as the anonymous production row.
ANONYMOUS_RANK = 13
#: Instrument whose board is empty.
EMPTY_INSTRUMENT = "Solo_PeripheralCymbals"
#: Instrument whose board read fails.
FAILING_INSTRUMENT = "Solo_PeripheralDrums"


def ranking_entry(original):
    """Wrap ``mock_service._ranking_entry`` so :data:`ANONYMOUS_RANK` is the anonymous row.

    Args:
        original: The mock service's row builder.

    Returns:
        A builder with the same signature.
    """
    def build(rank: int, account_id: str, display_name: str) -> dict:
        entry = original(rank, account_id, display_name)
        if rank == ANONYMOUS_RANK:
            entry["accountId"] = ""
            entry.pop("displayName", None)
        return entry
    return build


def board_override(path: str, query: dict[str, list[str]]) -> tuple[int, dict] | None:
    """The empty or failing board response for a rankings path, if it is one of the scenarios.

    Args:
        path: Request path.
        query: Parsed query string.

    Returns:
        ``(status, body)`` for the scenario instruments, else ``None`` (serve the mock's response).
    """
    if path == f"/api/rankings/{EMPTY_INSTRUMENT}":
        return 200, {"instrument": EMPTY_INSTRUMENT, "rankBy": query.get("rankBy", ["totalscore"])[0],
                     "page": int(query.get("page", ["1"])[0]), "pageSize": int(query.get("pageSize", ["25"])[0]),
                     "totalAccounts": 0, "entries": []}
    if path == f"/api/rankings/{FAILING_INSTRUMENT}":
        return 500, {"status": "internal_error"}
    return None


def install() -> None:
    """Patch the mock service in place (row builder and rankings scenarios)."""
    mock_service._ranking_entry = ranking_entry(mock_service._ranking_entry)
    original = mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        parsed = urlsplit(self.path)
        override = board_override(parsed.path, parse_qs(parsed.query))
        forbidden = self.headers.get("X-API-Key") is not None or any(
            name.lower().startswith("x-fst-selected-") for name in self.headers)
        if override is None or forbidden:  # the mock rejects forbidden client headers itself
            original(self)
        else:
            self._json(*override)

    mock_service.FixtureHandler.do_GET = do_get


def is_board_read(path: str) -> bool:
    """Whether a path is a solo board read (delayed by ``--rankings-delay``), not an own-rank or band read.

    Args:
        path: Request path.

    Returns:
        ``True`` for ``/api/rankings/{instrument}``.
    """
    parts = path.split("/")
    return len(parts) == 4 and path.startswith("/api/rankings/") and parts[3] not in ("", "bands")


def is_band_board_read(path: str) -> bool:
    """Whether a path is a band board read (delayed by ``--bands-delay``).

    Args:
        path: Request path.

    Returns:
        ``True`` for ``/api/rankings/bands/{type}``, ``/api/leaderboard/{song}/bands/{type}`` (not ``bands/all``)
        and ``/api/player/{id}/bands``.
    """
    parts = path.split("/")
    if len(parts) == 5 and path.startswith("/api/rankings/bands/"):
        return parts[4] != ""
    if len(parts) == 6 and path.startswith("/api/leaderboard/") and parts[4] == "bands":
        return parts[3] != "" and parts[5] not in ("", "all")
    return len(parts) == 5 and path.startswith("/api/player/") and parts[3] != "" and parts[4] == "bands"


def install_delay(seconds: float, matches=is_board_read) -> None:
    """Answer matching reads only after a delay, keeping a load or reload spinner up long enough to inspect.

    Args:
        seconds: Delay before each matching response.
        matches: Predicate on the request path (default: solo board reads).
    """
    original = mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        if matches(urlsplit(self.path).path):
            time.sleep(seconds)
        original(self)

    mock_service.FixtureHandler.do_GET = do_get


def install_rankings_delay(seconds: float) -> None:
    """Answer solo board reads only after a delay, keeping a reload's spinner up long enough to inspect.

    Args:
        seconds: Delay before each board response.
    """
    install_delay(seconds, is_board_read)


def take_delay(argv: list[str], flag: str) -> tuple[float | None, list[str]]:
    """Split ``<flag> <seconds>`` (or ``<flag>=<seconds>``) from the remaining arguments.

    Args:
        argv: Command-line arguments after the program name.
        flag: The option, e.g. ``--rankings-delay``.

    Returns:
        The delay in seconds (``None`` when absent) and the remaining arguments.

    Raises:
        SystemExit: Missing, non-numeric or negative delay.
    """
    delay, rest, items = None, [], iter(argv)
    for arg in items:
        if arg == flag:
            value = next(items, None)
        elif arg.startswith(f"{flag}="):
            value = arg.split("=", 1)[1]
        else:
            rest.append(arg)
            continue
        try:
            delay = float(value)  # type: ignore[arg-type]
        except (TypeError, ValueError):
            delay = -1.0
        if delay < 0:
            raise SystemExit(f"{flag} needs a non-negative number of seconds")
    return delay, rest


def take_rankings_delay(argv: list[str]) -> tuple[float | None, list[str]]:
    """Split ``--rankings-delay <seconds>`` (or ``=<seconds>``) from the remaining arguments.

    Args:
        argv: Command-line arguments after the program name.

    Returns:
        The delay in seconds (``None`` when absent) and the remaining arguments.

    Raises:
        SystemExit: Missing, non-numeric or negative delay.
    """
    return take_delay(argv, "--rankings-delay")


def main() -> None:
    """Install the scenarios and the optional board delays, force ``--large-rankings`` and hand over to ``rivals_fixture``."""
    install()
    delay, rest = take_rankings_delay(sys.argv[1:])
    bands_delay, rest = take_delay(rest, "--bands-delay")
    sys.argv[1:] = rest
    if delay:
        install_rankings_delay(delay)
    if bands_delay:
        install_delay(bands_delay, is_band_board_read)
    if "--large-rankings" not in sys.argv:
        sys.argv.append("--large-rankings")
    rivals_fixture.main()


if __name__ == "__main__":
    main()
