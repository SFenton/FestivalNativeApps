"""Run tools/mock_service.py with a scrape freeze on Band Detail's band-scoped reads (issue #554).

While the service scrapes and publishes it answers a band read that misses its published route cache with a stamped
503 (``Retry-After``, ``X-Fst-Public-Read-Freeze-Reason: scrape``). The client must then keep showing the body it
already verified for the same publication ([empty-error-states](../../.agents/patterns/empty-error-states.md) R9) and
only a cold read shows "Scores are updating". This wrapper reaches both states without any timing or request counting:

- **Warm band** :data:`WARM_TEAM`: the band row (``/api/rankings/bands/{type}?teamKey=``), ``…/history`` and
  ``…/songs`` answer normally with an entity tag; a *conditional* read of them (``If-None-Match``, which the client
  sends only when it holds a verified body for this publication) answers the freeze 503 instead of a 304. So the first
  visit loads, and every revisit or refresh in the same app run is frozen, in every app launch.
- **Cold band** :data:`COLD_TEAM`: ``…/songs`` always answers the freeze 503 (no verified body yet), so the Best and
  Worst Songs card shows the inline "Scores are updating" status, never "No ranked band songs yet."

Everything else is the unchanged mock service.

Usage: ``python tools/windows/band_freeze_fixture.py --port 0`` (same flags as ``mock_service.py``), or a journey's
``"fixture": ["band_freeze_fixture.py"]``.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

#: Team whose band reads load once, then freeze on every conditional reread.
WARM_TEAM = "fixture-team-1"
#: Team whose best/worst read is frozen before the client ever verified it.
COLD_TEAM = "fixture-team-2"
#: Entity tag on the warm band reads (the client keys its cache by URL, so one tag serves all three).
ETAG = '"fst-fixture-band-freeze-v1"'
#: The service's scrape-lifecycle freeze stamp.
FREEZE_REASON = "scrape"

_BAND_ROW = re.compile(r"^/api/rankings/bands/[A-Za-z_]+$")
_BAND_SCOPED = re.compile(r"^/api/rankings/bands/[A-Za-z_]+/([a-z0-9-]+)/(history|songs)$")


def band_read(path: str, query: dict[str, list[str]]) -> tuple[str, str] | None:
    """The team and section of a band-scoped Band Detail read.

    Args:
        path: Request path.
        query: Parsed query string.

    Returns:
        ``(teamKey, "row" | "history" | "songs")``, or ``None`` for any other read (boards, player bands, songs).
    """
    if _BAND_ROW.fullmatch(path):
        team = query.get("teamKey", [""])[0]
        return (team, "row") if team else None
    if match := _BAND_SCOPED.fullmatch(path):
        return match.group(1), match.group(2)
    return None


def outcome(path: str, query: dict[str, list[str]], conditional: bool) -> str:
    """What the fixture answers for one request.

    Args:
        path: Request path.
        query: Parsed query string.
        conditional: Whether the request carries ``If-None-Match`` (the client holds a verified body).

    Returns:
        ``"freeze"`` (stamped 503), ``"tag"`` (the mock's response plus :data:`ETAG`) or ``"pass"`` (unchanged).
    """
    read = band_read(path, query)
    if read is None:
        return "pass"
    team, section = read
    if team == COLD_TEAM and section == "songs":
        return "freeze"
    if team == WARM_TEAM:
        return "freeze" if conditional else "tag"
    return "pass"


def install() -> None:
    """Patch the mock handler with :func:`outcome` (freeze 503s and tagged warm reads)."""
    handler = mock_service.FixtureHandler
    original_get = handler.do_GET
    original_json = handler._json

    def do_GET(self) -> None:  # noqa: N802 (stdlib handler name)
        parsed = urlsplit(self.path)
        forbidden = self.headers.get("X-API-Key") is not None or any(
            name.lower().startswith("x-fst-selected-") for name in self.headers)
        decision = "pass" if forbidden else outcome(
            parsed.path, parse_qs(parsed.query), self.headers.get("If-None-Match") is not None)
        if decision == "freeze":
            self.send_response(503)
            self.send_header("Retry-After", "30")
            self.send_header("X-Fst-Public-Read-Freeze-Reason", FREEZE_REASON)
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if decision == "pass":
            original_get(self)
            return

        def _json(status: int, payload: dict | None, **kwargs) -> None:
            original_json(self, status, payload, **({**kwargs, "etag": ETAG} if status == 200 else kwargs))

        self._json = _json
        try:
            original_get(self)
        finally:
            del self._json

    handler.do_GET = do_GET
    # Band Detail reads its row, history, songs, catalogue and artwork together; socketserver's default backlog is 5.
    mock_service.FixtureServer.request_queue_size = 128


def main() -> None:
    """Install the freeze, then hand every flag to the mock service's own CLI."""
    install()
    mock_service.main()


if __name__ == "__main__":
    main()
