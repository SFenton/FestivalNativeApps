"""Run tools/mock_service.py with anonymized Rivals display names.

The shared Rivals fixtures in contracts/fixtures were captured from live shapes and still carry real player
names. Committed Windows screenshots must not show real names, so this wrapper swaps every rival display
name for a deterministic "Demo Rival N" before serving. Everything else (routes, scenarios such as the
``-empty``/``-503`` account suffixes, songs and artwork) is the unchanged mock service.

``--band-rankings empty|unavailable|anonymous`` (Windows UI tests, issue #209) replaces the band rankings
list (``/api/rankings/bands/{bandType}`` without ``teamKey``) with a zero-team board, an HTTP 500, or two rows
whose second has no band identity and blank member names (shown as "Unknown User", not openable).

``--songs-delay SECONDS`` (issue #240) answers ``/api/songs`` only after the delay, so a first-run guide opened at
launch shows its placeholder demo rows before the catalogue arrives. ``--songs-unavailable`` (issue #257) answers
every ``/api/songs`` read with a 503 (no freeze header: a generic outage), so first-run demos must keep their
placeholder rows rather than invent songs.

``--song-leaderboard anonymous`` (issue #263) blanks the account ID and display name of the rank-3 row in every song's
Lead (``Solo_Guitar``) chart read, the production case of a top-ten row with no player to open.

``--song-band-totals`` (issue #317) sets ``showLeaderboardEntryTotals`` on per-size song band board reads
(``/api/leaderboard/{songId}/bands/{bandType}``), so the band board header's entry-total line is reachable.

A selected account containing ``-slow`` (``fixture-player-slow``, ``fixture-player-slow-503``; issue #265) gets its
song and leaderboard rivals lists only after ``SLOW_RIVALS_SECONDS``, so the Rivals hub's per-card loading rings stay
on screen for UIA checks and scans before rows (or the ``-503`` inline freeze) replace them.

Usage: ``python tools/windows/rivals_fixture.py --port 8765`` (same flags as mock_service.py), then launch the
app with ``--base-url http://127.0.0.1:8765/`` and ``FST_DEBUG_PROFILE=fixture-player-1:Demo Player``.
"""

from __future__ import annotations

import re
import sys
import time
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

# region Late catalogue

#: Catalogue route delayed by ``--songs-delay``.
SONGS_PATH = "/api/songs"


def install_songs_delay(seconds: float) -> None:
    """Answer catalogue reads only after a delay, so UI opened at launch sees the catalogue arrive later.

    Args:
        seconds: Delay before each ``/api/songs`` response.
    """
    original = mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        if urlsplit(self.path).path == SONGS_PATH:
            time.sleep(seconds)
        original(self)

    mock_service.FixtureHandler.do_GET = do_get


def take_songs_delay(argv: list[str]) -> tuple[float | None, list[str]]:
    """Split ``--songs-delay <seconds>`` (or ``=<seconds>``) from the remaining arguments.

    Args:
        argv: Command-line arguments after the program name.

    Returns:
        The delay in seconds (``None`` when absent) and the remaining arguments.

    Raises:
        SystemExit: Missing, non-numeric or negative delay.
    """
    delay, rest, items = None, [], iter(argv)
    for arg in items:
        if arg == "--songs-delay":
            value = next(items, None)
        elif arg.startswith("--songs-delay="):
            value = arg.split("=", 1)[1]
        else:
            rest.append(arg)
            continue
        try:
            delay = float(value)  # type: ignore[arg-type]
        except (TypeError, ValueError):
            delay = -1.0
        if delay < 0:
            raise SystemExit("--songs-delay needs a non-negative number of seconds")
    return delay, rest


def install_songs_unavailable() -> None:
    """Answer every catalogue read with a 503 outage, so the catalogue never loads."""
    original = mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        if urlsplit(self.path).path == SONGS_PATH:
            self._json(503, {"status": "fixture_songs_unavailable"})
        else:
            original(self)

    mock_service.FixtureHandler.do_GET = do_get

# endregion

# region Song leaderboard scenarios

#: Per-chart song leaderboard read changed by ``--song-leaderboard`` (Song Detail falls back to it without ``/all``).
SONG_LEAD_BOARD = re.compile(r"^/api/leaderboard/fixture-[a-z0-9-]+/Solo_Guitar$")
#: Scenarios for ``--song-leaderboard``.
SONG_LEADERBOARD_SCENARIOS = ("anonymous",)
#: Rank whose row loses its identity in the ``anonymous`` scenario.
ANONYMOUS_RANK = 3


def anonymize_song_leaderboard(path: str, body: dict | None) -> dict | None:
    """Blank the identity of the :data:`ANONYMOUS_RANK` row in a song's Lead chart read.

    Args:
        path: Request path with query.
        body: Response body the mock service built (``None`` for an empty response).

    Returns:
        The body, with that row's ``accountId`` empty and ``displayName`` null when ``path`` is a Lead chart read.
    """
    if body and SONG_LEAD_BOARD.fullmatch(urlsplit(path).path):
        for entry in body.get("entries", []):
            if entry.get("rank") == ANONYMOUS_RANK:
                entry.update(accountId="", displayName=None)
    return body


def install_song_leaderboard(scenario: str) -> None:
    """Serve a song leaderboard scenario on top of the mock service's chart reads.

    Args:
        scenario: One of :data:`SONG_LEADERBOARD_SCENARIOS`.
    """
    original = mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        send = self._json
        self._json = lambda status, body, *rest, **kw: send(status, anonymize_song_leaderboard(self.path, body), *rest, **kw)
        try:
            original(self)
        finally:
            del self._json

    mock_service.FixtureHandler.do_GET = do_get


def take_song_leaderboard(argv: list[str]) -> tuple[str | None, list[str]]:
    """Split ``--song-leaderboard <scenario>`` (or ``=<scenario>``) from the remaining arguments.

    Args:
        argv: Command-line arguments after the program name.

    Returns:
        The scenario (``None`` when absent) and the remaining arguments.

    Raises:
        SystemExit: Missing or unknown scenario.
    """
    scenario, rest, items = None, [], iter(argv)
    for arg in items:
        if arg == "--song-leaderboard":
            scenario = next(items, None)
        elif arg.startswith("--song-leaderboard="):
            scenario = arg.split("=", 1)[1]
        else:
            rest.append(arg)
            continue
        if scenario not in SONG_LEADERBOARD_SCENARIOS:
            raise SystemExit(f"--song-leaderboard must be one of {', '.join(SONG_LEADERBOARD_SCENARIOS)}")
    return scenario, rest

# endregion

# region Song band board entry totals

#: Per-size song band board read (``/api/leaderboard/{songId}/bands/{bandType}``; not ``/bands/all``).
SONG_BAND_BOARD = re.compile(r"^/api/leaderboard/fixture-[a-z0-9-]+/bands/(?!all$)[A-Za-z_]+$")


def song_band_totals(path: str, body: dict | None) -> dict | None:
    """Turn on ``showLeaderboardEntryTotals`` in a per-size song band board read (``--song-band-totals``, issue #317).

    The mock omits the flag there (the app treats it as false), so only the band-size header line is reachable; with
    it on the header also names the entry total.

    Args:
        path: Request path with query.
        body: Response body the mock service built (``None`` for an empty response).

    Returns:
        The body, flagged when ``path`` is a per-size song band board read.
    """
    if body and SONG_BAND_BOARD.fullmatch(urlsplit(path).path):
        body["showLeaderboardEntryTotals"] = True
    return body


def install_song_band_totals() -> None:
    """Serve per-size song band boards with entry totals on."""
    original = mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        send = self._json
        self._json = lambda status, body, *rest, **kw: send(status, song_band_totals(self.path, body), *rest, **kw)
        try:
            original(self)
        finally:
            del self._json

    mock_service.FixtureHandler.do_GET = do_get

# endregion

# region Slow rivals lists

#: A viewing account ID containing this marker (``fixture-player-slow``, ``fixture-player-slow-503``) gets slow lists.
SLOW_MARKER = "-slow"
#: Delay before a slow account's rivals list answers (issue #265). The app sends four Rivals reads at a time
#: (``FestivalSession.RivalsConcurrency``), so nine charts settle in three waves (12/24/36 s) and Common Rivals, which
#: needs every list, keeps its ring longest. Each read stays under the 30 s request timeout (``RequestGate.DefaultTimeout``).
SLOW_RIVALS_SECONDS = 12.0


def rivals_list_delay(path: str) -> float:
    """Delay for a song or leaderboard rivals list read whose viewing account is a slow fixture player.

    The account's other suffixes still select the mock scenario after the delay (``-503`` freezes).

    Args:
        path: Request path with query.

    Returns:
        :data:`SLOW_RIVALS_SECONDS` for a slow account's list read, else ``0``.
    """
    route = urlsplit(path).path
    for pattern in (mock_service.RIVALS_LIST, mock_service.LEADERBOARD_RIVALS_LIST):
        if (match := pattern.fullmatch(route)) and SLOW_MARKER in match.group(1):
            return SLOW_RIVALS_SECONDS
    return 0.0


def install_slow_rivals() -> None:
    """Hold slow accounts' rivals list reads, so the Rivals hub stays in its per-card loading state."""
    original = mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        if delay := rivals_list_delay(self.path):
            time.sleep(delay)
        original(self)

    mock_service.FixtureHandler.do_GET = do_get

# endregion


def name_detail_bodies(names: dict[str, str]) -> None:
    """Make each rival detail body carry the requested rival's demo name.

    The mock serves one shared detail payload for every rival, so without this every rival opens as the
    first demo name and a journey cannot tell which rival the detail column shows.

    Args:
        names: Account ID to demo name, as built by :func:`anonymize`.
    """
    for builder_name, id_index in (("_rival_detail_body", 1), ("_leaderboard_rival_detail_body", 2)):
        original = getattr(mock_service, builder_name)

        def build(*args, _original=original, _id_index=id_index):  # noqa: ANN002, ANN202 (mirrors the builder)
            body = _original(*args)
            rival_id = args[_id_index]
            if rival_id in names:
                body["rival"] = {**body["rival"], "displayName": names[rival_id]}
            return body

        setattr(mock_service, builder_name, build)


def main() -> None:
    """Anonymize the Rivals fixtures, then hand over to the mock service's own CLI."""
    scenario, rest = take_band_rankings(sys.argv[1:])
    songs_delay, rest = take_songs_delay(rest)
    song_board, rest = take_song_leaderboard(rest)
    songs_unavailable = "--songs-unavailable" in rest
    song_band_totals_on = "--song-band-totals" in rest
    rest = [arg for arg in rest if arg not in ("--songs-unavailable", "--song-band-totals")]
    sys.argv[1:] = rest
    if scenario:
        install_band_rankings(scenario)
    if songs_delay:
        install_songs_delay(songs_delay)
    if song_board:
        install_song_leaderboard(song_board)
    if songs_unavailable:
        install_songs_unavailable()
    if song_band_totals_on:
        install_song_band_totals()
    install_slow_rivals()
    names: dict[str, str] = {}
    for payload in (
        mock_service.RIVALS_LIST_DEMO,
        mock_service.LEADERBOARD_RIVALS_DEMO,
        mock_service.RIVAL_DETAIL_DEMO,
        mock_service.LEADERBOARD_RIVAL_DETAIL_DEMO,
    ):
        anonymize(payload, names)
    name_detail_bodies(names)
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
