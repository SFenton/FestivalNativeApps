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

``--player-bands fail-once`` (issue #312) answers the first read of each distinct ``/api/player/{id}/bands`` path and
query with a 500 and passes the identical retry through, so the profile's inline Bands section fails, then recovers.
``--song-band-totals`` (issue #317) sets ``showLeaderboardEntryTotals`` on per-size song band board reads
(``/api/leaderboard/{songId}/bands/{bandType}``), so the band board header's entry-total line is reachable.
``--song-band-slow BANDTYPE`` (issue #317 review) answers that band size's per-size reads only after
``SLOW_SONG_BAND_SECONDS``, so a size switch stays in its load gate long enough for UIA to check the header meanwhile.

A selected account containing ``-slow`` (``fixture-player-slow``, ``fixture-player-slow-503``; issue #265) gets its
song and leaderboard rivals lists only after ``SLOW_RIVALS_SECONDS``, so the Rivals hub's per-card loading rings stay
on screen for UIA checks and scans before rows (or the ``-503`` inline freeze) replace them.

Rival Detail states (issue #284) are selected by the viewing account too, on song-rival detail reads only:
``-detail-loading`` holds them for ``SLOW_DETAIL_SECONDS`` (loading ring), ``-detail-flaky`` fails the first of every
two reads of each path with a generic 500 (Retry recovers, once per launch), ``-detail-down`` fails every one (the error
state stays up for scans across window sizes) and ``-detail-frozen`` answers them with a
scrape-freeze 503 while ``rivals/all`` carries the demo detail as samples, so the page rebuilds from it (issue #95).

``--song-band-rows N`` (issue #305) serves every fixture song's band leaderboards with ``N`` entries, so the band
song board scrolls under its floating pager.

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

# region Long song band board

#: Song band leaderboard route lengthened by ``--song-band-rows``.
SONG_BAND_ROWS_BOARD = re.compile(r"^/api/leaderboard/(fixture-[a-z0-9-]+)/bands/(Band_[A-Za-z]+)$")


def song_band_board_response(path: str, rows: int) -> dict | None:
    """A ``rows``-entry song band leaderboard page, or ``None`` to defer to the mock service.

    Args:
        path: Request path with query (``top``/``offset`` paging).
        rows: Total entries on the board.

    Returns:
        The page body, or ``None`` for any other request or invalid paging (the mock service answers those).
    """
    parsed = urlsplit(path)
    match = SONG_BAND_ROWS_BOARD.fullmatch(parsed.path)
    if not match or match.group(2) not in mock_service.BAND_TYPES:
        return None
    query = parse_qs(parsed.query)
    try:
        top = int(query.get("top", ["25"])[0])
        offset = int(query.get("offset", ["0"])[0])
    except ValueError:
        return None
    if not 1 <= top <= 100 or offset < 0:
        return None
    band_type = match.group(2)
    entries = [mock_service._song_band_leaderboard_entry(rank, band_type)
               for rank in range(offset + 1, min(rows, offset + top) + 1)]
    return {"songId": match.group(1), "bandType": band_type, "count": len(entries),
            "totalEntries": rows, "localEntries": rows, "entries": entries}


def install_song_band_rows(rows: int) -> None:
    """Serve every fixture song's band leaderboards with ``rows`` entries (a board long enough to scroll).

    Args:
        rows: Total entries on each board.
    """
    original = mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        body = song_band_board_response(self.path, rows)
        if body is None:
            original(self)
        else:
            self._json(200, body)

    mock_service.FixtureHandler.do_GET = do_get


def take_song_band_rows(argv: list[str]) -> tuple[int | None, list[str]]:
    """Split ``--song-band-rows <count>`` (or ``=<count>``) from the remaining arguments.

    Args:
        argv: Command-line arguments after the program name.

    Returns:
        The row count (``None`` when absent) and the remaining arguments.

    Raises:
        SystemExit: Missing, non-numeric or non-positive count.
    """
    count, rest, items = None, [], iter(argv)
    for arg in items:
        if arg == "--song-band-rows":
            value = next(items, None)
        elif arg.startswith("--song-band-rows="):
            value = arg.split("=", 1)[1]
        else:
            rest.append(arg)
            continue
        try:
            count = int(value)  # type: ignore[arg-type]
        except (TypeError, ValueError):
            count = 0
        if count < 1:
            raise SystemExit("--song-band-rows needs a positive row count")
    return count, rest

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

# region Player bands scenarios

#: Scenarios for ``--player-bands``.
PLAYER_BANDS_SCENARIOS = ("fail-once",)


def player_bands_failure(path: str, seen: set[str]) -> bool:
    """Whether a player-bands read fails in the ``fail-once`` scenario (issue #312).

    The first read of each distinct path and query answers 500, and the identical retry passes through, so the
    profile's inline Bands section shows its failure with Retry and then recovers.

    Args:
        path: Request path with query.
        seen: Paths already failed once (updated in place).

    Returns:
        ``True`` when this read should answer 500.
    """
    if not mock_service.PLAYER_BANDS.fullmatch(urlsplit(path).path) or path in seen:
        return False
    seen.add(path)
    return True


def install_player_bands(scenario: str) -> None:
    """Serve a player-bands scenario in front of the mock service's handler.

    Args:
        scenario: One of :data:`PLAYER_BANDS_SCENARIOS`.
    """
    original = mock_service.FixtureHandler.do_GET
    seen: set[str] = set()

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        if scenario == "fail-once" and player_bands_failure(self.path, seen):
            self._json(500, {"status": "fixture_player_bands_unavailable"})
        else:
            original(self)

    mock_service.FixtureHandler.do_GET = do_get


def take_player_bands(argv: list[str]) -> tuple[str | None, list[str]]:
    """Split ``--player-bands <scenario>`` (or ``=<scenario>``) from the remaining arguments.

    Args:
        argv: Command-line arguments after the program name.

    Returns:
        The scenario (``None`` when absent) and the remaining arguments.

    Raises:
        SystemExit: Missing or unknown scenario.
    """
    scenario, rest, items = None, [], iter(argv)
    for arg in items:
        if arg == "--player-bands":
            scenario = next(items, None)
        elif arg.startswith("--player-bands="):
            scenario = arg.split("=", 1)[1]
        else:
            rest.append(arg)
            continue
        if scenario not in PLAYER_BANDS_SCENARIOS:
            raise SystemExit(f"--player-bands must be one of {', '.join(PLAYER_BANDS_SCENARIOS)}")
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


#: Delay before a slowed band size's per-size song band board answers (``--song-band-slow``); under the 30 s timeout.
SLOW_SONG_BAND_SECONDS = 5.0


def take_song_band_slow(argv: list[str]) -> tuple[str | None, list[str]]:
    """Split ``--song-band-slow <bandType>`` (or ``=<bandType>``) from the remaining arguments.

    Args:
        argv: Command-line arguments after the program name.

    Returns:
        The slowed band type (``None`` when absent) and the remaining arguments.

    Raises:
        SystemExit: Missing or malformed band type.
    """
    band, rest, items = None, [], iter(argv)
    for arg in items:
        if arg == "--song-band-slow":
            value = next(items, None)
        elif arg.startswith("--song-band-slow="):
            value = arg.split("=", 1)[1]
        else:
            rest.append(arg)
            continue
        if not value or not re.fullmatch(r"Band_[A-Za-z]+", value):
            raise SystemExit("--song-band-slow needs a band type such as Band_Quad")
        band = value
    return band, rest


def song_band_delay(path: str, band: str | None) -> float:
    """Delay for a per-size song band board read of the slowed band size.

    Args:
        path: Request path with query.
        band: Slowed band type, or ``None``.

    Returns:
        :data:`SLOW_SONG_BAND_SECONDS` for a slowed read, else ``0``.
    """
    route = urlsplit(path).path
    if band and SONG_BAND_BOARD.fullmatch(route) and route.rsplit("/", 1)[1] == band:
        return SLOW_SONG_BAND_SECONDS
    return 0.0


def install_song_band_slow(band: str) -> None:
    """Hold one band size's per-size song band board reads (``--song-band-slow``)."""
    original = mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        if delay := song_band_delay(self.path, band):
            time.sleep(delay)
        original(self)

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

# region Rival detail states (issue #284)

#: Viewing-account markers for Rival Detail's own states (song-rival detail reads only; lists stay the demo).
DETAIL_SLOW_MARKER = "-detail-loading"
DETAIL_FLAKY_MARKER = "-detail-flaky"
DETAIL_FROZEN_MARKER = "-detail-frozen"
DETAIL_DOWN_MARKER = "-detail-down"
#: Delay before a ``-detail-loading`` account's detail answers: long enough for UIA to see the loading ring, under the
#: 30 s request timeout.
SLOW_DETAIL_SECONDS = 12.0
#: Per-path read count for ``-detail-flaky`` accounts.
_detail_reads: dict[str, int] = {}
#: ``/api/player/{id}/rivals/all`` (the mock's list pattern would otherwise answer it as a list named "all").
RIVALS_ALL = re.compile(r"^/api/player/(fixture-[a-z0-9-]+)/rivals/all$")


def rival_detail_state(path: str) -> str | None:
    """Which Rival Detail state a song-rival detail read selects from its viewing account.

    Args:
        path: Request path with query.

    Returns:
        ``"slow"``, ``"flaky"``, ``"frozen"`` or ``"down"``, or ``None`` for other reads and accounts.
    """
    match = mock_service.RIVALS_DETAIL.fullmatch(urlsplit(path).path)
    if not match:
        return None
    account = match.group(1)
    for marker, state in ((DETAIL_SLOW_MARKER, "slow"), (DETAIL_FLAKY_MARKER, "flaky"), (DETAIL_FROZEN_MARKER, "frozen"),
                           (DETAIL_DOWN_MARKER, "down")):
        if marker in account:
            return state
    return None


def flaky_detail_fails(path: str, reads: dict[str, int]) -> bool:
    """Whether a ``-detail-flaky`` read fails: the 1st, 3rd, … read of each path answers 500, the next passes.

    Every app launch (one per window size in a run) therefore sees one generic failure, and its Retry recovers.

    Args:
        path: Request path with query.
        reads: Reads so far per path (updated in place).

    Returns:
        ``True`` when this read should answer 500.
    """
    reads[path] = reads.get(path, 0) + 1
    return reads[path] % 2 == 1


def rivals_all_body(account: str) -> dict:
    """A precomputed ``rivals/all`` body whose one rival carries the demo detail's songs as samples.

    It is what the app rebuilds Rival Detail from when every detail read is held by a publication freeze (issue #95).

    Args:
        account: Viewing account ID.

    Returns:
        ``{accountId, songs, combos}`` in the service's precomputed shape.
    """
    detail = mock_service.RIVAL_DETAIL_DEMO
    rows = detail["songs"]
    songs = list(dict.fromkeys(row["songId"] for row in rows))
    samples = [{"s": songs.index(row["songId"]), "i": row["instrument"], "ur": row["userRank"], "rr": row["rivalRank"],
                "us": row.get("userScore"), "rs": row.get("rivalScore")} for row in rows]
    ahead = sum(1 for row in rows if row["rankDelta"] > 0)
    entry = {"accountId": detail["rival"]["accountId"], "displayName": detail["rival"]["displayName"],
             "direction": "above", "sharedSongCount": len(rows), "aheadCount": ahead, "behindCount": len(rows) - ahead,
             "rivalScore": 100.0, "samples": samples}
    return {"accountId": account, "songs": songs, "combos": [{"combo": "01", "above": [entry], "below": []}]}


def install_rival_detail_states() -> None:
    """Serve the ``-detail-loading``, ``-detail-flaky``, ``-detail-frozen`` and ``-detail-down`` accounts' Rival Detail reads."""
    original = mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        route = urlsplit(self.path).path
        state = rival_detail_state(self.path)
        if state == "slow":
            time.sleep(SLOW_DETAIL_SECONDS)
        elif state == "down" or (state == "flaky" and flaky_detail_fails(self.path, _detail_reads)):
            self._json(500, {"status": "fixture_rival_detail_unavailable"})
            return
        elif state == "frozen":
            self.send_response(503)
            self.send_header("Retry-After", "30")
            self.send_header("X-Fst-Public-Read-Freeze-Reason", "scrape")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        elif (match := RIVALS_ALL.fullmatch(route)) and DETAIL_FROZEN_MARKER in match.group(1):
            self._json(200, rivals_all_body(match.group(1)))
            return
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
    song_band_rows, rest = take_song_band_rows(rest)
    player_bands, rest = take_player_bands(rest)
    song_band_slow, rest = take_song_band_slow(rest)
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
    if player_bands:
        install_player_bands(player_bands)
    if songs_unavailable:
        install_songs_unavailable()
    if song_band_rows:
        install_song_band_rows(song_band_rows)
    if song_band_totals_on:
        install_song_band_totals()
    if song_band_slow:
        install_song_band_slow(song_band_slow)
    install_slow_rivals()
    install_rival_detail_states()
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
