"""Run tools/mock_service.py with designed scores for the Songs instrument status chip UI tests (issue #227).

The shared mock gives Fixture Player 1 one non-FC Lead score per song, so only the "scored", "no score" and
"not charted" chips are reachable. This wrapper rewrites read-only fixture responses so every chip state shows on the
two demo songs (``.agents/controls/songs-instrument-status-chips/spec.md``):

===============  ==================  ================================================================
Song             Chart               Wire score → chip
===============  ==================  ================================================================
fixture-pulse    Lead                ``sc=99900, fc=true`` → full combo
fixture-pulse    Bass                ``sc=81000, fc=false`` → scored
fixture-pulse    Drums               no row → no score
fixture-pulse    Tap Vocals          ``sc=0, fc=true`` → score missing despite a reported full combo
fixture-pulse    Pro Lead            ``sc=50000, fc=true`` but uncharted → not charted
fixture-orbit    Lead                ``sc=0, fc=false`` → no score
fixture-orbit    Bass                ``sc=70000`` but difficulty 99 → not charted
fixture-orbit    Pro Lead            ``sc=60000, fc=false, ml=3`` → scored; with Filter Invalid Scores (leeway 1) its
                                     ``vs`` fallback ``sc=55000, fc=true, ml=0.5`` → full combo
fixture-orbit    Pro Drums           ``sc=90000, fc=true`` (difficulty 0 is charted) → full combo
===============  ==================  ================================================================

``fixture-orbit`` also gets the ``Keyboard`` Lead signature, so its Lead and Pro Lead chips use the keys icons.
``/api/player/fixture-chips-slow`` answers the same scores after :data:`SLOW_SECONDS`, so the "Loading scores" state is
observable before the chips appear. Every other route is the unchanged mock service. Fixture-only: never point this
at, or capture evidence from, it.

Usage: ``python tools/windows/instrument_status_fixture.py --port 0`` (other flags pass through to mock_service.py).
"""

from __future__ import annotations

import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

PLAYER = "fixture-player-1"
SLOW_PLAYER = "fixture-chips-slow"
#: Seconds the slow player's profile read waits before answering.
SLOW_SECONDS = 6.0
KEYBOARD_SONG = "fixture-orbit"

#: Designed score rows (see the module table). Instrument codes are the service's single-bit hex values.
SCORES: list[dict] = [
    {"si": "fixture-pulse", "ins": "01", "sc": 99900, "acc": 1000, "fc": True, "st": 6, "sn": 9, "rk": 1, "te": 26},
    {"si": "fixture-pulse", "ins": "02", "sc": 81000, "acc": 955, "fc": False, "st": 5, "sn": 9, "rk": 3, "te": 26},
    {"si": "fixture-pulse", "ins": "08", "sc": 0, "fc": True},
    {"si": "fixture-pulse", "ins": "10", "sc": 50000, "acc": 990, "fc": True, "st": 6, "sn": 9, "rk": 1, "te": 4},
    {"si": "fixture-orbit", "ins": "01", "sc": 0, "fc": False},
    {"si": "fixture-orbit", "ins": "02", "sc": 70000, "acc": 900, "fc": False, "st": 4, "sn": 9, "rk": 2, "te": 9},
    {"si": "fixture-orbit", "ins": "10", "sc": 60000, "acc": 960, "fc": False, "st": 5, "sn": 9, "rk": 4, "te": 12,
     "ml": 3.0, "vs": [{"ml": 0.5, "sc": 55000, "acc": 1000, "fc": True, "st": 6}]},
    {"si": "fixture-orbit", "ins": "100", "sc": 90000, "acc": 1000, "fc": True, "st": 6, "sn": 9, "rk": 1, "te": 3},
]


def profile(account_id: str, display_name: str) -> dict:
    """The designed 200 profile for one fixture account.

    Args:
        account_id: Account the app asked for.
        display_name: Display name to report.

    Returns:
        Profile payload.
    """
    return {"accountId": account_id, "displayName": display_name, "totalScores": len(SCORES),
            "scores": [dict(score) for score in SCORES]}


def rewrite(path: str, payload: dict | None) -> dict | None:
    """Return the payload to send for a request path, with this fixture's chip states applied.

    Args:
        path: Request path without the query string.
        payload: The mock's JSON body (``None`` for a bodyless response).

    Returns:
        A rewritten copy for the overridden routes, otherwise the payload unchanged.
    """
    if not isinstance(payload, dict):
        return payload
    if path == "/api/songs" and isinstance(payload.get("songs"), list):
        return {**payload, "songs": [{**song, "sig": "Keyboard"} if song.get("songId") == KEYBOARD_SONG else song
                                     for song in payload["songs"]]}
    if path == f"/api/player/{PLAYER}" and isinstance(payload.get("scores"), list):
        return profile(PLAYER, payload.get("displayName") or "Fixture Player 1")
    return payload


def install() -> None:
    """Patch the mock handler so its JSON responses pass through :func:`rewrite` and the slow player waits."""
    handler = mock_service.FixtureHandler
    original_get = handler.do_GET
    original_json = handler._json

    def do_GET(self) -> None:  # noqa: N802 (stdlib handler name)
        path = urlsplit(self.path).path
        if path == f"/api/player/{SLOW_PLAYER}":
            time.sleep(SLOW_SECONDS)
            original_json(self, 200, profile(SLOW_PLAYER, "Slow Player"))
            return

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
