"""Live publication socket tooling (issue #616): ``publication_live_fixture.py`` and its journey.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import base64
import hashlib
import json
import os
import socket
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import mock_service  # noqa: E402
import publication_live_fixture as f  # noqa: E402  (sibling module)

JOURNEY = Path(__file__).resolve().parents[1] / "journeys" / "a11y-songs-publication-refresh.json"


def masked(opcode: int, payload: bytes) -> bytes:
    """Encode a short masked client frame."""
    key = os.urandom(4)
    return bytes([0x80 | opcode, 0x80 | len(payload)]) + key + bytes(b ^ key[i % 4] for i, b in enumerate(payload))


class FrameTests(unittest.TestCase):
    """Flags and RFC 6455 framing."""

    def test_rollover_flag_is_split_from_the_mock_flags(self):
        self.assertEqual(f.take_rollover_after(["--rollover-after", "3", "--port", "0"]), (3.0, ["--port", "0"]))
        self.assertEqual(f.take_rollover_after([]), (5.0, []))
        for bad in ("0", "121"):
            with self.assertRaises(SystemExit):
                f.take_rollover_after(["--rollover-after", bad])

    def test_masked_client_frames_round_trip(self):
        left, right = socket.socketpair()
        with left, right:
            left.sendall(masked(0x1, b'{"type":"subscribe_sync"}') + masked(0x8, b""))
            self.assertEqual(f.read_frame(right), (0x1, b'{"type":"subscribe_sync"}'))
            self.assertEqual(f.read_frame(right), (0x8, b""))
            left.close()
            self.assertIsNone(f.read_frame(right))

    def test_server_text_frames_are_unmasked(self):
        self.assertEqual(f.text_frame("hi"), b"\x81\x02hi")

    def test_only_a_positive_publication_query_is_accepted(self):
        self.assertTrue(f.QUERY.fullmatch("publicationId=7"))
        for bad in ("", "publicationId=0", "publicationId=-1", "publicationId=7&accountId=x", "accountId=x"):
            self.assertIsNone(f.QUERY.fullmatch(bad), bad)


class LiveSocketServerTests(unittest.TestCase):
    """The patched handler over a real loopback socket."""

    @classmethod
    def setUpClass(cls):
        cls.original = mock_service.FixtureHandler.do_GET
        cls.original_state = f.STATE
        f.STATE = f.LiveState(0.3)
        f.install()
        cls.server = mock_service.FixtureServer(("127.0.0.1", 0), mock_service.FixtureHandler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.port = cls.server.server_port

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        mock_service.FixtureHandler.do_GET = cls.original
        f.STATE = cls.original_state

    def upgrade(self, query: str, extra: str = "") -> tuple[socket.socket, bytes]:
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        connection = socket.create_connection(("127.0.0.1", self.port), timeout=10)
        connection.sendall((f"GET /api/ws?{query} HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n"
                            f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n"
                            f"{extra}\r\n").encode("ascii"))
        head = b""
        while b"\r\n\r\n" not in head:
            chunk = connection.recv(1)
            if not chunk:
                break
            head += chunk
        accept = base64.b64encode(hashlib.sha1((key + f.WS_GUID).encode("ascii")).digest())
        if head.startswith(b"HTTP/1.1 101"):
            self.assertIn(b"Sec-WebSocket-Accept: " + accept, head)
        return connection, head

    def test_privileged_or_extra_handshakes_are_refused(self):
        for query, extra in (("publicationId=7", "X-API-Key: k\r\n"),
                             ("publicationId=7", "x-fst-selected-account-id: a\r\n"),
                             ("publicationId=7", "Cookie: c=1\r\n"),
                             ("publicationId=7&accountId=a", "")):
            connection, head = self.upgrade(query, extra)
            connection.close()
            self.assertTrue(head.startswith(b"HTTP/1.0 400"), (query, extra, head[:40]))

    def test_a_player_read_advances_and_pushes_publication_changed(self):
        connection, head = self.upgrade("publicationId=7")
        with connection:
            self.assertTrue(head.startswith(b"HTTP/1.1 101"), head[:40])
            # Ignored message types arrive first, like the service's own snapshots.
            self.assertEqual(json.loads(f.read_frame(connection)[1])["type"], "shop_snapshot")
            with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/api/player/fixture-player-1", timeout=10):
                pass
            opcode, payload = f.read_frame(connection)
            self.assertEqual(opcode, 0x1)
            self.assertEqual(json.loads(payload), {"type": "publication_changed", "publicationId": 8})
            self.assertEqual(self.server.publication_id, 8)
            connection.sendall(masked(0x8, b""))
        with urllib.request.urlopen(f"http://127.0.0.1:{self.port}/__fixture__/live-socket", timeout=10) as reply:
            body = json.loads(reply.read())
        self.assertTrue(body["advanced"])
        self.assertEqual(body["clientDataFrames"], 0)
        self.assertIn("publicationId=7", body["connections"])


class JourneyTests(unittest.TestCase):
    """The Songs refresh journey listens before the rollover and covers motion and text scaling."""

    def test_pages_use_the_live_socket_and_assert_the_announcement(self):
        pages = json.loads(JOURNEY.read_text(encoding="utf-8"))
        modes = {mode for page in pages for mode in page["modes"]}
        self.assertEqual(modes, {"normal", "app-reduced", "text-200"})
        for page in pages:
            self.assertEqual(page["fixture"][0], "publication_live_fixture.py")
            self.assertEqual(page["env"], {"FST_LIVE_PUBLICATION_UPDATES": "1"})
            self.assertEqual(page["ready"][0], "listen:announcements")
            self.assertIn("assertannounced:Loading new scores@45", page["after_ready"])
            self.assertIn("assertannouncedcount:1|Loading new scores", page["after_ready"])
            self.assertIn("waitgone:id=fst.songs.profile-paused@1", page["after_ready"])


if __name__ == "__main__":
    unittest.main()
