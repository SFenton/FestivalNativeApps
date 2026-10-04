"""Run tools/mock_service.py with CHOpt Paths overrides so every Paths state is reachable in UI tests.

The shared mock serves ``fixture-pulse`` Lead (``Solo_Guitar``) paths for Hard and Expert and answers every other
chart or difficulty with 404 (the "not generated" state). This wrapper adds the two states a fast local fixture
cannot show:

- **Loading** (``--slow-difficulty``, default ``hard``): the image and ``/data`` reads for that difficulty wait
  ``--slow-seconds`` (default 6) before the mock answers, so the spinner can be captured and asserted.
- **Offline** (``--offline-difficulty``, default ``medium``): the connection is reset without a response, the same
  failure as a dropped network, so the dialog shows the service-status view with Retry.

Every other route is the unchanged mock service. Usage:
``python tools/windows/paths_fixture.py --port 0 [--slow-seconds 6] [--slow-difficulty hard] [--offline-difficulty medium]``
(other flags pass through to mock_service.py).
"""

from __future__ import annotations

import argparse
import re
import socket
import struct
import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

PATH = re.compile(r"^/api/paths/([A-Za-z0-9-]+)/([A-Za-z_]+)/([a-z]+)(/data)?$")


def path_override(path: str, slow: str | None, offline: str | None) -> str | None:
    """Decide how this wrapper answers a request.

    Args:
        path: Request path without the query string.
        slow: Difficulty whose path reads are delayed, or ``None``.
        offline: Difficulty whose path reads drop the connection, or ``None``.

    Returns:
        ``"offline"``, ``"slow"`` or ``None`` (answer with the mock unchanged).
    """
    match = PATH.fullmatch(path)
    if match is None:
        return None
    difficulty = match.group(3)
    if offline is not None and difficulty == offline:
        return "offline"
    if slow is not None and difficulty == slow:
        return "slow"
    return None


def install(slow: str | None, slow_seconds: float, offline: str | None) -> None:
    """Patch the mock handler with the slow and offline path overrides.

    Args:
        slow: Difficulty whose path reads are delayed.
        slow_seconds: Delay before the mock answers a slow read.
        offline: Difficulty whose path reads reset the connection.
    """
    handler = mock_service.FixtureHandler
    original = handler.do_GET

    def do_GET(self) -> None:  # noqa: N802 (stdlib handler name)
        kind = path_override(urlsplit(self.path).path, slow, offline)
        if kind == "offline":
            # RST instead of FIN: the client sees a reset connection, never a partial response.
            self.connection.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
            self.close_connection = True
            self.connection.close()
            return
        if kind == "slow":
            time.sleep(slow_seconds)
        original(self)

    handler.do_GET = do_GET
    mock_service.FixtureServer.request_queue_size = 128


def main() -> None:
    """Parse this wrapper's flags, then hand the rest to the mock service's own CLI."""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--slow-difficulty", default="hard")
    parser.add_argument("--slow-seconds", type=float, default=6.0)
    parser.add_argument("--offline-difficulty", default="medium")
    options, rest = parser.parse_known_args()
    install(options.slow_difficulty or None, options.slow_seconds, options.offline_difficulty or None)
    sys.argv = [sys.argv[0], *rest]
    mock_service.main()


if __name__ == "__main__":
    main()
