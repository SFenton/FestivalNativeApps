"""Run tools/mock_service.py with a designed selected player for the Songs metadata pills (Windows UI tests).

The shared mock's players score every demo song alike, so the Songs-row metadata control
(``.agents/controls/song-score-metadata/spec.md``) shows one state. Run with ``--large-catalogue``: this wrapper answers
``GET /api/player/fixture-meta`` with one designed score per synthetic song, keeping the mock's catalogue, Shop,
publication headers and every other route (current season 9):

=====================  ==========  ===============================================================================
Row                    Chart       State
=====================  ==========  ===============================================================================
``fixture-song-1``     Lead        graded 99.5%, Top 1% (gold fill), current season S9, 5 white stars, Expert, date
``fixture-song-1``     Bass        100% FC, gold stars (non-Lead chart named when Lead is hidden or Bass filtered)
``fixture-song-2``     Lead        100% FC (gold outline), Top 3% (gold outline), five gold stars, old S4, Easy
``fixture-song-3``     Lead        FC without accuracy (``FC``), 1 star, Top 60%, Medium
``fixture-song-4``     Lead        missing accuracy (no pill), no rank (no percentile), no season, 3 stars, Hard
``fixture-song-5``     Lead        graded 50%, Top 100%, S1, 2 stars, Expert
``fixture-song-6``     Lead        graded 12%, Top 50%, S2, 4 stars, Hard
``fixture-song-7``     Lead        zero score (``No score``)
``fixture-pulse``      Lead        graded 97%, Top 15% on the Item Shop row (bag on the art)
=====================  ==========  ===============================================================================

Every other row has no score (``No score``). ``fixture-meta-slow`` answers the same profile after
:data:`SLOW_SECONDS` so the row's ``Loading scores`` state is observable.

Usage: ``python tools/windows/song_metadata_fixture.py --port 0`` (adds ``--large-catalogue``; other flags pass through).
"""

from __future__ import annotations

import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

#: Designed player account and its delayed twin.
ACCOUNT = "fixture-meta"
SLOW_ACCOUNT = "fixture-meta-slow"
#: Delay before the slow twin answers (long enough for a UIA wait, short of the app's request timeout).
SLOW_SECONDS = 8.0

#: Compact-wire rows (``acc`` is percent × 10; ``ins`` the single-bit hex chart code).
SCORES: list[dict] = [
    {"si": "fixture-song-1", "ins": "01", "sc": 412_345, "acc": 995, "fc": False, "st": 5, "sn": 9, "dif": 3,
     "rk": 1, "te": 500, "lp": "2026-09-28T18:00:00Z"},
    {"si": "fixture-song-1", "ins": "02", "sc": 222_222, "acc": 1000, "fc": True, "st": 6, "sn": 9, "dif": 3,
     "rk": 1, "te": 50},
    {"si": "fixture-song-2", "ins": "01", "sc": 398_000, "acc": 1000, "fc": True, "st": 6, "sn": 4, "dif": 0,
     "rk": 12, "te": 500},
    {"si": "fixture-song-3", "ins": "01", "sc": 250_000, "fc": True, "st": 1, "sn": 9, "dif": 1, "rk": 300, "te": 500},
    {"si": "fixture-song-4", "ins": "01", "sc": 180_000, "fc": False, "st": 3, "dif": 2},
    {"si": "fixture-song-5", "ins": "01", "sc": 150_000, "acc": 500, "fc": False, "st": 2, "sn": 1, "dif": 3,
     "rk": 500, "te": 500},
    {"si": "fixture-song-6", "ins": "01", "sc": 90_000, "acc": 120, "fc": False, "st": 4, "sn": 2, "dif": 2,
     "rk": 250, "te": 500},
    {"si": "fixture-song-7", "ins": "01", "sc": 0, "acc": 0, "fc": False, "st": 0, "sn": 9, "dif": 0,
     "rk": 400, "te": 500},
    {"si": "fixture-pulse", "ins": "01", "sc": 300_000, "acc": 970, "fc": False, "st": 5, "sn": 9, "dif": 3,
     "rk": 3, "te": 26},
]


def profile(account_id: str) -> dict:
    """The designed ``GET /api/player/{accountId}`` body.

    Args:
        account_id: :data:`ACCOUNT` or :data:`SLOW_ACCOUNT`.

    Returns:
        A ``PlayerProfileResponse`` JSON object with :data:`SCORES`.
    """
    return {"accountId": account_id, "displayName": "Metadata Player", "totalScores": len(SCORES),
            "scores": [dict(score) for score in SCORES]}


def designed_account(path: str) -> str | None:
    """The designed account a request path reads, if any.

    Args:
        path: Request path (query included or not).

    Returns:
        :data:`ACCOUNT`, :data:`SLOW_ACCOUNT` or ``None``.
    """
    route = urlsplit(path).path
    for account in (ACCOUNT, SLOW_ACCOUNT):
        if route == f"/api/player/{account}":
            return account
    return None


def install() -> None:
    """Patches the mock handler so the designed accounts answer with :data:`SCORES`."""
    handler = mock_service.FixtureHandler
    original_json = handler._json

    def _json(self, status: int, payload: dict | None, **kwargs) -> None:
        account = designed_account(self.path)
        if status == 200 and account is not None:
            if account == SLOW_ACCOUNT:
                time.sleep(SLOW_SECONDS)
            payload = profile(account)
        original_json(self, status, payload, **kwargs)

    handler._json = _json
    # Songs reads the catalogue, Shop, player and 100+ artwork files at once; socketserver's default backlog of 5 overflows.
    mock_service.FixtureServer.request_queue_size = 128


def with_large_catalogue(argv: list[str]) -> list[str]:
    """Adds ``--large-catalogue`` unless the caller passed it (``a11y_matrix.py`` passes only ``--port``).

    Args:
        argv: Command-line arguments after the script name.

    Returns:
        The arguments with the synthetic catalogue the designed rows name.
    """
    return argv if "--large-catalogue" in argv else [*argv, "--large-catalogue"]


def main() -> None:
    """Installs the designed player, then hands the command line to the mock service."""
    install()
    sys.argv[1:] = with_large_catalogue(sys.argv[1:])
    mock_service.main()


if __name__ == "__main__":
    main()
