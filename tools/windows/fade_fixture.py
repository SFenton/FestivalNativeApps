"""Run tools/mock_service.py with a selected player deep in the fixture-pulse Lead board (Windows fade journey, #323).

The shared mock's ``fixture-player-*`` profiles rank inside Song Detail's top-ten preview, so the "your score" row
eleven (and its jump to the full board with ``navToPlayer``) is unreachable. This wrapper answers
``GET /api/player/fixture-player-17`` with one fixture-pulse Lead score at rank 17, matching the mock board's
``fixture-player-17`` row (``score = 100000 - rank * 100``): Song Detail appends it as row eleven, and invoking it
opens the board's first page and reveals row 17 (index 16), far enough down for the scroll to rush the entrance.
Song Details' all-instrument preview read (``/api/leaderboard/fixture-pulse/all``) answers after
:data:`DETAIL_DELAY_SECONDS`, like the live service: a load that finishes almost at once skips the entrance (web
``useLoadPhase``), so without it a journey opening Song Details from Songs would have no entrance to rush. Every
other route, header and publication stays the mock's.

Usage: ``python tools/windows/fade_fixture.py --port 0 --large-rankings`` (every flag passes to the mock).
"""

from __future__ import annotations

import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

#: The deep selected player.
PLAYER_ID = "fixture-player-17"
#: Its rank on the fixture-pulse Lead board (row eleven needs a rank outside the top ten).
PLAYER_RANK = 17
#: Delay before the Song Details preview read answers (past ``SongDetailReveal.InstantLoad``).
DETAIL_DELAY_SECONDS = 0.8
#: The Song Details all-instrument preview read.
DETAIL_PATH = "/api/leaderboard/fixture-pulse/all"


def profile() -> dict:
    """The deep player's ``/api/player/{accountId}`` body: one fixture-pulse Lead score at :data:`PLAYER_RANK`."""
    return {
        "accountId": PLAYER_ID, "displayName": "Fixture Player 17", "totalScores": 1,
        "scores": [{
            "si": "fixture-pulse", "ins": "01", "sc": 100_000 - PLAYER_RANK * 100, "acc": 980,
            "fc": False, "st": 5, "dif": 3, "sn": 9, "pct": 0.65, "rk": PLAYER_RANK, "te": 26,
        }],
    }


def install() -> None:
    """Patches the mock handler: the deep player's profile read answers :func:`profile`, the preview read waits."""
    handler = mock_service.FixtureHandler
    original_get = handler.do_GET

    def do_GET(self) -> None:  # noqa: N802  (stdlib handler name)
        parsed = urlsplit(self.path)
        if parsed.path == DETAIL_PATH:
            time.sleep(DETAIL_DELAY_SECONDS)
        if parsed.path != f"/api/player/{PLAYER_ID}" or parsed.query or any(
            name.lower().startswith("x-fst-selected-") or name.lower() == "x-api-key" for name in self.headers
        ):
            original_get(self)
            return
        self._json(200, profile())

    handler.do_GET = do_GET


def main() -> None:
    """Installs the deep player, then hands the command line to the mock service."""
    install()
    mock_service.main()


if __name__ == "__main__":
    main()
