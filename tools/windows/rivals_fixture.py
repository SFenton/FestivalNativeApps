"""Run tools/mock_service.py with anonymized Rivals display names.

The shared Rivals fixtures in contracts/fixtures were captured from live shapes and still carry real player
names. Committed Windows screenshots must not show real names, so this wrapper swaps every rival display
name for a deterministic "Demo Rival N" before serving. Everything else (routes, scenarios such as the
``-empty``/``-503`` account suffixes, songs and artwork) is the unchanged mock service.

``--band-rankings empty|unavailable|anonymous`` (Windows UI tests, issue #209) replaces the band rankings
list (``/api/rankings/bands/{bandType}`` without ``teamKey``) with a zero-team board, an HTTP 500, or two rows
whose second has no band identity and blank member names (shown as "Unknown User", not openable).

Usage: ``python tools/windows/rivals_fixture.py --port 8765`` (same flags as mock_service.py), then launch the
app with ``--base-url http://127.0.0.1:8765/`` and ``FST_DEBUG_PROFILE=fixture-player-1:Demo Player``.
"""

from __future__ import annotations

import re
import sys
from http.server import BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)


def anonymize(payload: dict, names: dict[str, str]) -> None:
    """Replace every rival display name in a Rivals payload in place.

    Args:
        payload: A rivals list, leaderboard-rivals list or rival detail body.
        names: Account ID to demo name, extended as new accounts are seen.
    """
    rows = [*payload.get("above", []), *payload.get("below", [])]
    if "rival" in payload:
        rows.append(payload["rival"])
    for row in rows:
        account = row["accountId"]
        names.setdefault(account, f"Demo Rival {len(names) + 1}")
        row["displayName"] = names[account]


# region Band rankings scenarios

#: Band rankings list route (the ``?teamKey=`` detail read and sub-routes are left to the mock service).
BAND_LIST = re.compile(r"^/api/rankings/bands/([A-Za-z_]+)$")
#: Scenarios for ``--band-rankings``.
BAND_SCENARIOS = ("empty", "unavailable", "anonymous")


def band_rankings_response(path: str, scenario: str) -> tuple[int, dict] | None:
    """The scenario's response for a band rankings list read, or ``None`` to defer to the mock service.

    Args:
        path: Request path with query.
        scenario: One of :data:`BAND_SCENARIOS`.

    Returns:
        Status and JSON body, or ``None`` for any other request (including ``?teamKey=`` detail reads).
    """
    parsed = urlsplit(path)
    match = BAND_LIST.fullmatch(parsed.path)
    query = parse_qs(parsed.query)
    if not match or "teamKey" in query:
        return None
    if scenario == "unavailable":
        return 500, {"status": "fixture_unavailable"}
    board = {"bandType": match.group(1), "rankBy": query.get("rankBy", ["totalscore"])[0], "page": 1,
             "pageSize": int(query.get("pageSize", ["25"])[0]), "totalTeams": 0, "entries": []}
    if scenario == "anonymous":
        anonymous = mock_service._band_ranking_entry(2)
        anonymous.update(bandId="", teamKey="", teamMembers=[{"accountId": "", "displayName": None},
                                                             {"accountId": "", "displayName": " "}])
        board.update(totalTeams=2, entries=[mock_service._band_ranking_entry(1), anonymous])
    return 200, board


def install_band_rankings(scenario: str) -> None:
    """Serve a band rankings scenario in front of the mock service's handler.

    Args:
        scenario: One of :data:`BAND_SCENARIOS`.
    """
    original = mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        response = band_rankings_response(self.path, scenario)
        if response is None:
            original(self)
        else:
            self._json(*response)

    mock_service.FixtureHandler.do_GET = do_get


def take_band_rankings(argv: list[str]) -> tuple[str | None, list[str]]:
    """Split ``--band-rankings <scenario>`` (or ``=<scenario>``) from the mock service's own arguments.

    Args:
        argv: Command-line arguments after the program name.

    Returns:
        The scenario (``None`` when absent) and the remaining arguments.

    Raises:
        SystemExit: Missing or unknown scenario.
    """
    scenario, rest, items = None, [], iter(argv)
    for arg in items:
        if arg == "--band-rankings":
            scenario = next(items, None)
        elif arg.startswith("--band-rankings="):
            scenario = arg.split("=", 1)[1]
        else:
            rest.append(arg)
            continue
        if scenario not in BAND_SCENARIOS:
            raise SystemExit(f"--band-rankings must be one of {', '.join(BAND_SCENARIOS)}")
    return scenario, rest

# endregion


def main() -> None:
    """Anonymize the Rivals fixtures, then hand over to the mock service's own CLI."""
    scenario, rest = take_band_rankings(sys.argv[1:])
    sys.argv[1:] = rest
    if scenario:
        install_band_rankings(scenario)
    names: dict[str, str] = {}
    for payload in (
        mock_service.RIVALS_LIST_DEMO,
        mock_service.LEADERBOARD_RIVALS_DEMO,
        mock_service.RIVAL_DETAIL_DEMO,
        mock_service.LEADERBOARD_RIVAL_DETAIL_DEMO,
    ):
        anonymize(payload, names)
    # The app's carousel art plus up to four concurrent Rivals reads overflow socketserver's default backlog
    # of 5, and Windows refuses the excess connections (the app then shows "You're offline").
    mock_service.FixtureServer.request_queue_size = 128
    # The stdlib server answers HTTP/1.0 and closes each socket; without an explicit "Connection: close" .NET's
    # pooled client occasionally reuses a closing socket (WSAECONNABORTED -> the app reports "offline").
    for handler in vars(mock_service).values():
        if isinstance(handler, type) and issubclass(handler, BaseHTTPRequestHandler) and handler is not BaseHTTPRequestHandler:
            original = handler.end_headers

            def end_headers(self, _original=original):  # noqa: ANN001 (stdlib handler signature)
                self.send_header("Connection", "close")
                _original(self)

            handler.end_headers = end_headers
    mock_service.main()


if __name__ == "__main__":
    main()
