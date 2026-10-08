"""Run tools/mock_service.py with switchable Item Shop states for the Windows Shop UI journeys (issue #224).

The shared mock always answers ``/api/shop`` with the two-offer demo feed (a New and a Leaving Tomorrow offer). The
native app never sends the mock's ``?scenario=`` query, so this wrapper picks the Shop state itself and lets a
journey change it between phases through a loopback control route:

``GET /__shop__/mode?shop=<demo|empty|error|slow|shop-single|long-title>&songs=<ok|error>``

* ``demo``: the unchanged mock feed (ETag/304 included).
* ``empty``: a genuine ``count=0`` feed (the empty-Shop card, never the failure view).
* ``error``: HTTP 503 without a freeze header (generic "unavailable" with Retry).
* ``slow``: holds the demo feed until a control request leaves ``slow`` (at most ``--slow-seconds``), so the loading
  ring stays up however long the journey waits for the shared desktop lock.
* ``shop-single``: the mock's one-offer ``?scenario=shop-single`` feed.
* ``long-title``: the demo feed with ``fixture-pulse`` renamed to :data:`LONG_TITLE` by :data:`LONG_ARTIST`, too long
  for any Item Shop list row, so the shared Song Row's marquee scrolls (motion) or ellipsizes (Reduce Motion) (issue #397).
* ``songs=error``: ``/api/songs`` answers 503, so Shop keeps its offers with "Song details unavailable" and every
  tile falls back to the official Item Shop action.

Usage: ``python tools/windows/shop_fixture.py --port 0 [--shop empty] [--songs error|--songs-fail]
[--slow-seconds 300]`` (other flags pass through to mock_service.py). The mock runs through ``rivals_fixture.py``
(anonymized names, larger accept backlog, ``Connection: close``), so ``a11y_matrix.py`` pages can name this wrapper
as their fixture (issue #206). Loopback only; never production.
"""

from __future__ import annotations

import argparse
import sys
import threading
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)
import rivals_fixture  # noqa: E402  (sibling wrapper)

#: Shop states this wrapper can serve.
SHOP_MODES = ("demo", "empty", "error", "slow", "shop-single", "long-title")
#: Catalogue states this wrapper can serve.
SONGS_MODES = ("ok", "error")
#: Control route a journey calls between phases.
CONTROL_PATH = "/__shop__/mode"
#: ``long-title`` offer: wider than the list row's title column at the medium and wide presets.
LONG_SONG_ID = "fixture-pulse"
LONG_TITLE = "Fixture Pulse and the Extraordinarily Long Item Shop Song Title That Never Fits on One Row of the List"
LONG_ARTIST = "Synthetic Quartet featuring the Extraordinarily Long Guest Ensemble Name"
LONG_ETAG = '"fst-fixture-shop-long-title-v1"'


def long_title_feed(feed: dict) -> dict:
    """The Shop feed with :data:`LONG_SONG_ID` renamed to :data:`LONG_TITLE` by :data:`LONG_ARTIST`.

    Args:
        feed: Demo Shop feed (unchanged).

    Returns:
        A copy with the one offer renamed.

    Raises:
        ValueError: The demo feed no longer has :data:`LONG_SONG_ID`.
    """
    if not any(song["songId"] == LONG_SONG_ID for song in feed["songs"]):
        raise ValueError(f"{LONG_SONG_ID} is missing from the demo Shop feed")
    songs = [{**song, "title": LONG_TITLE, "artist": LONG_ARTIST} if song["songId"] == LONG_SONG_ID else song
             for song in feed["songs"]]
    return {**feed, "songs": songs}


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
            ``"control"``, ``"shop-empty"``, ``"shop-error"``, ``"shop-slow"``, ``"shop-shop-single"``,
            ``"shop-long-title"`` or ``"songs-error"``; ``None`` defers to the mock.
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
        elif kind == "shop-shop-single":
            self.path = "/api/shop?scenario=shop-single"
            original(self)
        elif kind == "shop-long-title":
            pin = self.headers.get("X-FST-Publication-Id")
            if pin is not None and pin != str(self.fixture.publication_id):
                self._json(409, {"status": "publication_changed"})
            elif self.headers.get("If-None-Match") == LONG_ETAG:
                self._json(304, None, etag=LONG_ETAG)
            else:
                self._json(200, long_title_feed(mock_service.SHOP_DEMO), etag=LONG_ETAG)
        else:  # shop-slow
            state.released.wait(state.slow_seconds)
            original(self)

    handler.do_GET = do_GET
    # Artwork bursts can overflow socketserver's default backlog of 5 (see rivals_fixture.py).
    mock_service.FixtureServer.request_queue_size = 128


def parse_options(argv: list[str]) -> tuple[argparse.Namespace, list[str]]:
    """Split this wrapper's flags from the mock service's.

    Args:
        argv: Arguments after the script name.

    Returns:
        This wrapper's options (``--songs-fail`` folded into ``songs="error"``) and the remaining arguments.
    """
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--shop", choices=SHOP_MODES, default="demo")
    parser.add_argument("--songs", choices=SONGS_MODES, default="ok")
    parser.add_argument("--songs-fail", action="store_true")
    parser.add_argument("--slow-seconds", type=float, default=300.0)
    options, rest = parser.parse_known_args(argv)
    if options.songs_fail:
        options.songs = "error"
    return options, rest


def main() -> None:
    """Parse this wrapper's flags, then hand the rest to the anonymized mock's own CLI."""
    options, rest = parse_options(sys.argv[1:])
    install(ShopState(options.shop, options.songs, options.slow_seconds))
    sys.argv = [sys.argv[0], *rest]
    rivals_fixture.main()


if __name__ == "__main__":
    main()
