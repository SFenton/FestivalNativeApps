"""Run the anonymized Windows fixture (``rivals_fixture.py``) with every Full Rankings state reachable.

On top of ``rivals_fixture.py`` (anonymized Rivals names, larger listen backlog, ``Connection: close``) this
wrapper always serves ``--large-rankings`` (1,200 accounts, 48 pages of 25) and adds three rankings scenarios
that the shared mock service does not have:

- rank 13 of every instrument is the production **anonymous row** (empty ``accountId``, no ``displayName``;
  [full-rankings spec](../../.agents/pages/full-rankings/spec.md)), shown as "Unknown User";
- ``GET /api/rankings/Solo_PeripheralCymbals`` is an empty board (``totalAccounts: 0``);
- ``GET /api/rankings/Solo_PeripheralDrums`` fails with HTTP 500 (the page's failure state).

Selected-player spotlight states come from the mock's own accounts: ``fixture-rank-40`` (page 2: pinned row and
Your Page), ``fixture-rank-fail`` (inline failure) and any other unknown ``fixture-*`` ID (404: not ranked).

Usage: ``python tools/windows/rankings_fixture.py --port 0`` (same flags as ``mock_service.py``), or
``a11y_matrix.py --fixture tools/windows/rankings_fixture.py --pages tools/windows/journeys/full-rankings.json``.
"""

from __future__ import annotations

import sys
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


def main() -> None:
    """Install the scenarios, force ``--large-rankings`` and hand over to ``rivals_fixture``."""
    install()
    if "--large-rankings" not in sys.argv:
        sys.argv.append("--large-rankings")
    rivals_fixture.main()


if __name__ == "__main__":
    main()
