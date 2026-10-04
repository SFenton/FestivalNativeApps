"""Run tools/mock_service.py with varied star counts for the Star Rating UI journeys (issue #221).

The shared mock gives every song-leaderboard row five stars and no player an all-gold instrument, so most star-rating
states are unreachable on screen. This wrapper rewrites two read-only fixture responses before they are sent:

- ``/api/leaderboard/fixture-*/Solo_Guitar`` rows get stars by rank (:data:`STARS_BY_RANK`): gold, five, the one-star
  floor, zero (no stars drawn), seven (still five gold), a missing field, and three.
- ``/api/player/fixture-player-1`` scores all get six stars, so its Lead and overall Avg Stars tiles are gold.

Every other route is the unchanged mock service. Fixture-only: never point this at, or capture evidence from, it.

Usage: ``python tools/windows/star_rating_fixture.py --port 0`` (other flags pass through to mock_service.py).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

LEADERBOARD = re.compile(r"^/api/leaderboard/fixture-[a-z0-9-]+/Solo_Guitar$")
#: Rank -> wire stars on the Lead song leaderboard; ``None`` drops the field. Ranks not listed keep the mock's 5.
STARS_BY_RANK: dict[int, int | None] = {1: 6, 2: 5, 3: 1, 4: 0, 5: 7, 6: None, 7: 3}
#: Player whose every score is rewritten to six stars (gold Avg Stars tiles).
GOLD_PLAYER = "fixture-player-1"


def rewrite(path: str, payload: dict | None) -> dict | None:
    """Return the payload to send for a request path, with this fixture's star counts applied.

    Args:
        path: Request path without the query string.
        payload: The mock's JSON body (``None`` for a bodyless response).

    Returns:
        A rewritten copy for the two overridden routes, otherwise the payload unchanged.
    """
    if not isinstance(payload, dict):
        return payload
    if LEADERBOARD.fullmatch(path) and isinstance(payload.get("entries"), list):
        entries = []
        for entry in payload["entries"]:
            entry = dict(entry)
            rank = entry.get("rank")
            if rank in STARS_BY_RANK:
                if (stars := STARS_BY_RANK[rank]) is None:
                    entry.pop("stars", None)
                else:
                    entry["stars"] = stars
            entries.append(entry)
        return {**payload, "entries": entries}
    if path == f"/api/player/{GOLD_PLAYER}" and isinstance(payload.get("scores"), list):
        return {**payload, "scores": [{**score, "st": 6} for score in payload["scores"]]}
    return payload


def install() -> None:
    """Patch the mock handler so its JSON responses pass through :func:`rewrite`."""
    handler = mock_service.FixtureHandler
    original_get = handler.do_GET
    original_json = handler._json

    def do_GET(self) -> None:  # noqa: N802 (stdlib handler name)
        path = urlsplit(self.path).path

        def _json(status: int, payload: dict | None, **kwargs) -> None:
            original_json(self, status, rewrite(path, payload) if status == 200 else payload, **kwargs)

        self._json = _json
        try:
            original_get(self)
        finally:
            del self._json

    handler.do_GET = do_GET
    # Page reads plus artwork can overflow socketserver's default backlog of 5 (see rivals_fixture.py).
    mock_service.FixtureServer.request_queue_size = 128


def main() -> None:
    """Install the rewrite, then hand every flag to the mock service's own CLI."""
    install()
    mock_service.main()


if __name__ == "__main__":
    main()
