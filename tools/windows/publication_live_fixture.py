"""Run tools/mock_service.py with a receive-only ``/api/ws`` that announces one publication change.

The service's public socket (``wss://…/api/ws?publicationId=N``, ``.agents/platforms/service-safety.md``) sends
``{"type":"publication_changed"}`` when a new generation publishes; the web's ``useAppWebSocket`` and the native live
connections then re-read ``/api/publication`` and refresh in place (issue #616, load-transition R9). This wrapper serves
that socket on loopback: a few seconds after the first selected-player score read (the Songs list has its scores by
then), the fixture advances from generation 7 to 8 and every open socket receives ``publication_changed``. Every other
read is the unchanged mock service, so the app re-reads Songs, Shop and scores for generation 8.

The socket stays anonymous and receive-only, like production: a handshake carrying ``X-API-Key``, a selected-profile
header or a cookie, or a query other than ``publicationId=<positive>``, is refused with 400. A data frame from the client
(``subscribe_sync`` or anything else) is logged as ``client data frame`` and counted in ``/__fixture__/live-socket``.
Each connection is logged (``live socket open ?publicationId=7``).

Usage: ``python tools/windows/publication_live_fixture.py [--rollover-after 5] [mock_service.py flags]``, then launch
the app with ``--base-url http://127.0.0.1:<port>/`` and ``FST_LIVE_PUBLICATION_UPDATES=1`` (a loopback origin keeps
the socket off unless opted in).
"""

from __future__ import annotations

import base64
import hashlib
import json
import re
import socket
import struct
import sys
import threading
import time
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

#: RFC 6455 handshake GUID.
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

#: The only accepted socket query.
QUERY = re.compile(r"publicationId=[1-9][0-9]{0,17}")

#: The first selected-player score read (``/api/player/<accountId>``), after which the rollover is scheduled.
PLAYER = re.compile(r"/api/player/[^/]+")


class LiveState:
    """Rollover timing and socket diagnostics shared by every handler thread."""

    def __init__(self, rollover_after: float) -> None:
        """Create the state.

        Args:
            rollover_after: Seconds between the first player read and the publication change.
        """
        self.rollover_after = rollover_after
        self.changed = threading.Event()
        self.lock = threading.Lock()
        self.scheduled = False
        self.connections: list[str] = []
        self.client_data_frames = 0

    def schedule(self, server: mock_service.FixtureServer) -> None:
        """Start the one rollover timer.

        Args:
            server: The fixture listener whose generation advances.
        """
        with self.lock:
            if self.scheduled:
                return
            self.scheduled = True

        def advance() -> None:
            with server._lock:  # noqa: SLF001  (the fixture's own generation lock)
                server._publication_id = 8  # noqa: SLF001
            print(f"{stamp()} publication advanced to 8", flush=True)
            self.changed.set()

        timer = threading.Timer(self.rollover_after, advance)
        timer.daemon = True
        timer.start()


STATE = LiveState(5.0)


def stamp() -> str:
    """Return a wall-clock log prefix (HH:MM:SS.mmm) for lining fixture events up with the driver."""
    now = time.time()
    return time.strftime("%H:%M:%S", time.localtime(now)) + f".{int(now % 1 * 1000):03d}"


def take_rollover_after(argv: list[str]) -> tuple[float, list[str]]:
    """Split ``--rollover-after <seconds>`` from the mock service's own flags.

    Args:
        argv: Command-line arguments after the program name.

    Returns:
        The delay (default 5 s) and the remaining arguments.
    """
    delay, rest, items = 5.0, [], iter(argv)
    for item in items:
        if item == "--rollover-after":
            delay = float(next(items))
            if not 0 < delay <= 120:
                raise SystemExit("--rollover-after must be in (0, 120]")
        else:
            rest.append(item)
    return delay, rest


def read_frame(connection: socket.socket) -> tuple[int, bytes] | None:
    """Read one client frame (always masked).

    Args:
        connection: The upgraded socket.

    Returns:
        ``(opcode, payload)``, or ``None`` when the client went away.
    """
    def exactly(count: int) -> bytes | None:
        data = b""
        while len(data) < count:
            chunk = connection.recv(count - len(data))
            if not chunk:
                return None
            data += chunk
        return data

    head = exactly(2)
    if head is None:
        return None
    opcode, length = head[0] & 0x0F, head[1] & 0x7F
    if length == 126:
        extended = exactly(2)
        if extended is None:
            return None
        length = struct.unpack("!H", extended)[0]
    elif length == 127:
        extended = exactly(8)
        if extended is None:
            return None
        length = struct.unpack("!Q", extended)[0]
    mask = exactly(4) if head[1] & 0x80 else b"\0\0\0\0"
    payload = exactly(length) if length else b""
    if mask is None or payload is None:
        return None
    return opcode, bytes(b ^ mask[i % 4] for i, b in enumerate(payload))


def text_frame(text: str) -> bytes:
    """Encode an unmasked server text frame.

    Args:
        text: UTF-8 text (under 126 bytes here).

    Returns:
        Frame bytes.
    """
    payload = text.encode("utf-8")
    return bytes([0x81, len(payload)]) + payload


def serve_socket(handler: mock_service.FixtureHandler) -> None:
    """Upgrade an allowed ``/api/ws`` request and push ``publication_changed`` once the generation advances.

    Args:
        handler: The request handler.
    """
    query = urlsplit(handler.path).query
    headers = {name.lower(): value for name, value in handler.headers.items()}
    key = headers.get("sec-websocket-key")
    forbidden = "x-api-key" in headers or "cookie" in headers or "authorization" in headers or any(
        name.startswith("x-fst-selected-") for name in headers)
    if (forbidden or not QUERY.fullmatch(query) or key is None
            or headers.get("upgrade", "").lower() != "websocket"):
        handler._json(400, {"status": "invalid_socket_request"})  # noqa: SLF001
        return
    accept = base64.b64encode(hashlib.sha1((key + WS_GUID).encode("ascii")).digest()).decode("ascii")
    # Raw HTTP/1.1 status line: the mock's handler speaks HTTP/1.0, which a WebSocket upgrade can't use.
    handler.wfile.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                         f"Sec-WebSocket-Accept: {accept}\r\n\r\n").encode("ascii"))
    handler.wfile.flush()
    handler.close_connection = True
    with STATE.lock:
        STATE.connections.append(query)
    print(f"{stamp()} live socket open ?{query}", flush=True)
    connection = handler.connection
    connection.sendall(text_frame(json.dumps({"type": "shop_snapshot", "songs": []}, separators=(",", ":"))))
    opened_on = int(query.split("=", 1)[1])
    if opened_on < 8:
        # Wait for the rollover, unless the client leaves first (its close frame or EOF ends the read thread).
        gone = threading.Event()

        def drain() -> None:
            while True:
                frame = read_frame(connection)
                if frame is None or frame[0] == 0x8:
                    gone.set()
                    return
                if frame[0] in (0x1, 0x2):
                    with STATE.lock:
                        STATE.client_data_frames += 1
                    print("client data frame", flush=True)

        threading.Thread(target=drain, daemon=True).start()
        while not gone.is_set() and not STATE.changed.wait(0.2):
            pass
        if gone.is_set():
            return
        connection.sendall(text_frame('{"type":"publication_changed","publicationId":8}'))
        print(f"{stamp()} sent publication_changed", flush=True)
        gone.wait(30)
        return
    # The current generation: hold the socket open until the client closes it.
    while True:
        frame = read_frame(connection)
        if frame is None or frame[0] == 0x8:
            return
        if frame[0] in (0x1, 0x2):
            with STATE.lock:
                STATE.client_data_frames += 1
            print("client data frame", flush=True)


def install() -> None:
    """Route ``/api/ws`` and the diagnostics path, and schedule the rollover after the first player read."""
    original = mock_service.FixtureHandler.do_GET

    def do_get(self: mock_service.FixtureHandler) -> None:
        path = urlsplit(self.path).path
        if path == "/api/ws":
            serve_socket(self)
            return
        if path == "/__fixture__/live-socket":
            with STATE.lock:
                body = {"connections": list(STATE.connections), "clientDataFrames": STATE.client_data_frames,
                        "advanced": STATE.changed.is_set()}
            self._json(200, body)  # noqa: SLF001
            return
        original(self)
        if PLAYER.fullmatch(path):
            print(f"{stamp()} player read {path}", flush=True)
            STATE.schedule(self.fixture)

    mock_service.FixtureHandler.do_GET = do_get


def main() -> None:
    """Install the socket, then hand over to the mock service's own CLI."""
    STATE.rollover_after, sys.argv[1:] = take_rollover_after(sys.argv[1:])
    install()
    # Songs, Shop, artwork and score reads arrive together; socketserver's default backlog of 5 refuses the excess.
    mock_service.FixtureServer.request_queue_size = 128
    mock_service.main()


if __name__ == "__main__":
    main()
