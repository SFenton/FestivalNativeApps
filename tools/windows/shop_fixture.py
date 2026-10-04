"""Run tools/mock_service.py with switchable Item Shop states for the Windows Shop UI journeys (issue #224).

The shared mock always answers ``/api/shop`` with the two-offer demo feed (a New and a Leaving Tomorrow offer). The
native app never sends the mock's ``?scenario=`` query, so this wrapper picks the Shop state itself and lets a
journey change it between phases through a loopback control route:

``GET /__shop__/mode?shop=<demo|empty|error|slow>&songs=<ok|error>``

* ``demo``: the unchanged mock feed (ETag/304 included).
* ``empty``: a genuine ``count=0`` feed (the empty-Shop card, never the failure view).
* ``error``: HTTP 503 without a freeze header (generic "unavailable" with Retry).
* ``slow``: holds the demo feed until a control request leaves ``slow`` (at most ``--slow-seconds``), so the loading
  ring stays up however long the journey waits for the shared desktop lock.
* ``songs=error``: ``/api/songs`` answers 503, so Shop keeps its offers with "Song details unavailable" and every
  tile falls back to the official Item Shop action.

Usage: ``python tools/windows/shop_fixture.py --port 0 [--shop empty] [--songs error] [--slow-seconds 300]`` (other
flags pass through to mock_service.py). Loopback only; never production.
"""

from __future__ import annotations

import argparse
import sys
import threading
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

#: Shop states this wrapper can serve.
SHOP_MODES = ("demo", "empty", "error", "slow")
#: Catalogue states this wrapper can serve.
SONGS_MODES = ("ok", "error")
#: Control route a journey calls between phases.
CONTROL_PATH = "/__shop__/mode"


class ShopState:
    """Current Shop and catalogue modes, shared by the server's handler threads."""

    def __init__(self, shop: str = "demo", songs: str = "ok", slow_seconds: float = 300.0) -> None:
        """Create the state.

        Args:
            shop: Initial Shop mode (one of :data:`SHOP_MODES`).
            songs: Initial catalogue mode (one of :data:`SONGS_MODES`).
            slow_seconds: Longest a ``slow`` read is held.
        """
        self._lock = threading.Lock()
        #: Set whenever the Shop mode is not ``slow``; held ``slow`` reads wait on it.
        self.released = threading.Event()
        self.slow_seconds = slow_seconds
        self.shop = "demo"
        self.songs = "ok"
        self.update({"shop": [shop], "songs": [songs]})

    def update(self, query: dict[str, list[str]]) -> dict[str, str]:
        """Apply a control request.

        Args:
            query: Parsed control query (``shop`` and/or ``songs``).

        Returns:
            The modes now in effect.

        Raises:
            ValueError: An unknown key or mode.
        """
        unknown = set(query) - {"shop", "songs"}
        if unknown:
            raise ValueError(f"unknown control key(s): {', '.join(sorted(unknown))}")
        shop = query.get("shop", [None])[-1]
        songs = query.get("songs", [None])[-1]
        if shop is not None and shop not in SHOP_MODES:
            raise ValueError(f"unknown shop mode: {shop}")
        if songs is not None and songs not in SONGS_MODES:
            raise ValueError(f"unknown songs mode: {songs}")
        with self._lock:
            if shop is not None:
                self.shop = shop
                if shop == "slow":
                    self.released.clear()
                else:
                    self.released.set()
            if songs is not None:
                self.songs = songs
            return {"shop": self.shop, "songs": self.songs}

    def route(self, path: str) -> str | None:
        """Decide how this wrapper answers a request.

        Args:
            path: Request path without the query string.

        Returns:
            ``"control"``, ``"shop-empty"``, ``"shop-error"``, ``"shop-slow"`` or ``"songs-error"``; ``None`` defers to
            the mock.
        """
        if path == CONTROL_PATH:
            return "control"
        with self._lock:
            shop, songs = self.shop, self.songs
        if path == "/api/shop" and shop != "demo":
            return f"shop-{shop}"
        if path == "/api/songs" and songs == "error":
            return "songs-error"
        return None


def install(state: ShopState) -> None:
    """Patch the mock handler so Shop and catalogue reads follow ``state``.

    Args:
        state: Shared modes.
    """
    handler = mock_service.FixtureHandler
    original = handler.do_GET

    def do_GET(self) -> None:  # noqa: N802 (stdlib handler name)
        parsed = urlsplit(self.path)
        kind = state.route(parsed.path)
        if kind is None:
            original(self)
        elif kind == "control":
            try:
                self._json(200, state.update(parse_qs(parsed.query)))
            except ValueError as error:
                self._json(400, {"status": str(error)})
        elif kind == "shop-empty":
            self._json(200, {"count": 0, "songs": [], "newSongs": [], "lastUpdated": None})
        elif kind in ("shop-error", "songs-error"):
            self._json(503, {"status": "fixture_unavailable"})
        else:  # shop-slow
            state.released.wait(state.slow_seconds)
            original(self)

    handler.do_GET = do_GET
    # Artwork bursts can overflow socketserver's default backlog of 5 (see rivals_fixture.py).
    mock_service.FixtureServer.request_queue_size = 128


def main() -> None:
    """Parse this wrapper's flags, then hand the rest to the mock service's own CLI."""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--shop", choices=SHOP_MODES, default="demo")
    parser.add_argument("--songs", choices=SONGS_MODES, default="ok")
    parser.add_argument("--slow-seconds", type=float, default=300.0)
    options, rest = parser.parse_known_args()
    install(ShopState(options.shop, options.songs, options.slow_seconds))
    sys.argv = [sys.argv[0], *rest]
    mock_service.main()


if __name__ == "__main__":
    main()
