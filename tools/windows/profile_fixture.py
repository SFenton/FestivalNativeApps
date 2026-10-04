"""Run tools/mock_service.py with the extra profile-selection states for Windows UI tests.

The shared mock already covers most Profile Selection states (``.agents/controls/profile-selection``): account search
results, the empty envelope (``zzz``), 403/429/503 (``blocked``/``rate``/``busy``), demo players, 202 syncing
(``fixture-syncing``). This wrapper adds the states it cannot reach per page, keeping every other route, and answers
every pinned ``/api/`` read of an older generation with ``409 publication_changed`` like the service (some mock routes
skip that check):

==================  =========================================  =================================================
State               Trigger                                    Wire
==================  =========================================  =================================================
debouncing /        account search ``q=Ro…`` (e.g.             ``Rollover Player`` after :data:`SLOW_SECONDS`
loading             ``Rollover``)
publication-changed player read of ``fixture-rollover``        served under the current publication, which then
/ profile-reload                                               advances by one, so the page's next pinned read
                                                               gets ``409 publication_changed`` and the app
                                                               re-reads the publication (and selected scores)
unpinned-profile    ``FST_PROFILE_FIXTURE_UNPINNED=1``          the mock's ``--unpinned`` mode: no publication
                    in the environment                         headers, pinning disabled
==================  =========================================  =================================================

``a11y_matrix.py`` starts a fixture with ``--port 0`` only, so the unpinned mode is chosen by the environment variable
(the matrix's environment is inherited) and the other states by query or account ID.

Usage: ``python tools/windows/profile_fixture.py --port 0`` (other flags pass through to mock_service.py).
"""

from __future__ import annotations

import copy
import os
import sys
import time
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

ROLLOVER_ID = "fixture-rollover"
ROLLOVER_NAME = "Rollover Player"
#: Account searches starting with this prefix (``Ro``, ``Rollover``) are answered after :data:`SLOW_SECONDS`, so
#: "Searching…" can be asserted both during the 250 ms debounce and during the read.
SLOW_PREFIX = "ro"
SLOW_SECONDS = 4.0
UNPINNED_ENV = "FST_PROFILE_FIXTURE_UNPINNED"


def rollover_profile() -> dict:
    """The rollover player's profile: Fixture Player 2's scores under the rollover identity.

    Returns:
        A fresh ``PlayerProfileResponse`` JSON object.
    """
    profile = copy.deepcopy(mock_service.PLAYER_DEMO["profiles"]["fixture-player-2"])
    profile["accountId"] = ROLLOVER_ID
    profile["displayName"] = ROLLOVER_NAME
    return profile


def search_results(term: str, results: list[dict]) -> list[dict]:
    """Adds the rollover player to account-search results it matches.

    Args:
        term: Trimmed query.
        results: The mock's matches.

    Returns:
        The results, with the rollover candidate appended when ``term`` is in its name.
    """
    if term.casefold() in ROLLOVER_NAME.casefold():
        return [*results, {"accountId": ROLLOVER_ID, "displayName": ROLLOVER_NAME}]
    return results


def advance(server) -> int:
    """Moves the fixture's publication forward by one.

    Args:
        server: The running ``FixtureServer``.

    Returns:
        The new publication ID.
    """
    with server._lock:
        server._publication_id += 1
        return server._publication_id


def install() -> None:
    """Patches the mock handler with the slow search, the rollover player and its search result."""
    handler = mock_service.FixtureHandler
    original_json = handler._json

    def _json(self, status: int, payload: dict | None, **kwargs) -> None:
        parsed = urlsplit(self.path)
        pin = self.headers.get("X-FST-Publication-Id")
        if (pin is not None and pin != str(self.fixture.publication_id) and parsed.path.startswith("/api/")
                and status != 409):
            # Like the service, every pinned read of an older generation conflicts (some mock routes skip the check).
            original_json(self, 409, {"status": "publication_changed"}, **kwargs)
            return
        rollover = status == 200 and parsed.path == f"/api/player/{ROLLOVER_ID}"
        if parsed.path == "/api/account/search" and status == 200 and isinstance(payload, dict):
            term = parse_qs(parsed.query).get("q", [""])[0].strip()
            if term.casefold().startswith(SLOW_PREFIX):
                time.sleep(SLOW_SECONDS)
            payload = {**payload, "results": search_results(term, payload.get("results", []))[:10]}
        elif rollover:
            payload = rollover_profile()
        original_json(self, status, payload, **kwargs)
        if rollover:
            print(f"profile-fixture: {ROLLOVER_ID} served; publication now {advance(self.fixture)}", flush=True)
        elif status == 200 and parsed.path.startswith("/api/player/") and parsed.path.count("/") == 3:
            print(f"profile-fixture: {parsed.path} served under publication {self.fixture.publication_id}", flush=True)

    handler._json = _json
    # The player page reads every instrument's ranking at once; socketserver's default backlog of 5 can overflow.
    mock_service.FixtureServer.request_queue_size = 128


def main() -> None:
    """Installs the profile states, then hands the command line to the mock service."""
    install()
    if os.environ.get(UNPINNED_ENV) == "1" and "--unpinned" not in sys.argv:
        sys.argv.append("--unpinned")
    mock_service.main()


if __name__ == "__main__":
    main()
