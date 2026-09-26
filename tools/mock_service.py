#!/usr/bin/env python3
"""Local, read-only Festival API fixture server for native device automation."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
import threading
import zlib
from functools import lru_cache
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parents[1]


def load_fixture(name: str) -> tuple[dict, str]:
    """Decode exactly the fixture bytes whose startup hash is advertised.

    Args:
        name: Allowlisted JSON fixture basename without its extension.

    Returns:
        Parsed object and SHA-256 of the same bytes loaded into this process.

    Raises:
        ValueError: If a fixture is not a JSON object.
    """
    data = (ROOT / "contracts/fixtures" / f"{name}.json").read_bytes()
    value = json.loads(data)
    if not isinstance(value, dict):
        raise ValueError(f"Invalid {name} fixture object")
    return value, hashlib.sha256(data).hexdigest()


PUBLICATION, PUBLICATION_HASH = load_fixture("publication")
EMPTY_SONGS, EMPTY_SONGS_HASH = load_fixture("songs-empty")
DEMO_SONGS, DEMO_SONGS_HASH = load_fixture("songs-demo")
PATH_DEMO, PATH_DEMO_HASH = load_fixture("path-demo")
SOURCE_HASHES = {
    "tools/mock_service.py": hashlib.sha256(Path(__file__).resolve().read_bytes()).hexdigest(),
    "contracts/fixtures/publication.json": PUBLICATION_HASH,
    "contracts/fixtures/songs-empty.json": EMPTY_SONGS_HASH,
    "contracts/fixtures/songs-demo.json": DEMO_SONGS_HASH,
    "contracts/fixtures/path-demo.json": PATH_DEMO_HASH,
}
SONGS_ETAG = '"fst-fixture-songs-v1"'
EMPTY_ETAG = '"fst-fixture-empty-v1"'
LEADERBOARD = re.compile(r"^/api/leaderboard/(fixture-[a-z]+)/([A-Za-z_]+)$")
PATH_ARTIFACT = re.compile(
    r"^/api/paths/(fixture-[a-z]+)/([A-Za-z_]+)/([a-z]+)(/data)?$"
)
INSTRUMENTS = frozenset({
    "Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals",
    "Solo_PeripheralGuitar", "Solo_PeripheralBass", "Solo_PeripheralVocals",
    "Solo_PeripheralCymbals", "Solo_PeripheralDrums",
})


class FixtureServer(ThreadingHTTPServer):
    """Isolate mock publication and query evidence within one loopback listener."""

    def __init__(
        self, address: tuple[str, int], handler: type[BaseHTTPRequestHandler],
        *, unpinned: bool = False, rollover_on_read: int | None = None,
        fail_first_white_catalogue: bool = False,
        stop_after_first_songs: bool = False,
        stop_after_first_score: bool = False
    ) -> None:
        """Create a deterministic, request-count-driven service fixture.

        Args:
            address: Loopback host and port.
            handler: Allowlisted HTTP request handler.
            unpinned: Omit response publication headers like an unfrozen service.
            rollover_on_read: First publication GET that advances generation 7 to 8.
            fail_first_white_catalogue: Fail one white-art catalogue read, then recover.
            stop_after_first_songs: Stop this mock listener after its first successful Songs read.
            stop_after_first_score: Stop after the first successful full 25-row chart read.
        """
        self.unpinned = unpinned
        self.rollover_on_read = rollover_on_read
        self.source_hashes = SOURCE_HASHES.copy()
        self.options = {
            "unpinned": unpinned,
            "rolloverOnRead": rollover_on_read,
            "failFirstWhiteCatalogue": fail_first_white_catalogue,
            "stopAfterFirstSongs": stop_after_first_songs,
            "stopAfterFirstScore": stop_after_first_score,
        }
        self._publication_reads = 0
        self._publication_id = 7
        self._last_score_query: dict | None = None
        self._last_full_score_query: dict | None = None
        self._fail_first_white_catalogue = fail_first_white_catalogue
        self._stop_after_first_songs = stop_after_first_songs
        self._stop_after_first_score = stop_after_first_score
        self._lock = threading.Lock()
        super().__init__(address, handler)

    @property
    def publication_id(self) -> int:
        """Return the fixture generation without advancing the read counter."""
        with self._lock:
            return self._publication_id

    def publication(self) -> dict:
        """Advance on the configured publication GET and return its wire object."""
        with self._lock:
            self._publication_reads += 1
            if self.rollover_on_read and self._publication_reads >= self.rollover_on_read:
                self._publication_id = 8
            identifier = self._publication_id
        return {
            **PUBLICATION,
            "publicationId": identifier,
            "publishedScrapeId": 42 if identifier == 7 else 43,
            "readyForPinning": not self.unpinned,
            "pinningEnabled": not self.unpinned,
        }

    def record_score_query(self, top: int, offset: int, leeway: float | None) -> None:
        """Retain only validated synthetic query numbers, never account identifiers.

        Args:
            top: Bounded page size.
            offset: Nonnegative score-row offset.
            leeway: Optional score tolerance sent by the native Settings control.
        """
        with self._lock:
            self._last_score_query = {"top": top, "offset": offset, "leeway": leeway}
            if top == 25:
                self._last_full_score_query = self._last_score_query

    def last_score_query(self) -> dict | None:
        """Return the last validated mock score request, if any."""
        with self._lock:
            return self._last_score_query

    def last_full_score_query(self) -> dict | None:
        """Return only the most recent full chart query, ignoring ten-row previews."""
        with self._lock:
            return self._last_full_score_query

    def should_fail_white_catalogue(self) -> bool:
        """Consume one configured white-art 503 without advancing publication.

        Returns:
            True exactly once per listener when that synthetic failure is enabled.
        """
        with self._lock:
            should_fail = self._fail_first_white_catalogue
            self._fail_first_white_catalogue = False
            return should_fail

    def should_stop_after_songs(self) -> bool:
        """Consume the configured one-shot simulated connectivity loss.

        Returns:
            True only after the first successful catalogue read on this listener.
        """
        with self._lock:
            should_stop = self._stop_after_first_songs
            self._stop_after_first_songs = False
            return should_stop

    def should_stop_after_score(self, top: int) -> bool:
        """Consume one full page, not a ten-row Detail preview, before disconnecting.

        Args:
            top: Validated number of chart rows requested.

        Returns:
            True only after the first successful 25-row chart on this listener.
        """
        if top != 25:
            return False
        with self._lock:
            should_stop = self._stop_after_first_score
            self._stop_after_first_score = False
            return should_stop


def fixture_png(width: int, height: int, rows: list[bytes]) -> bytes:
    """Encode original synthetic RGBA pixels without writing a file.

    Args:
        width: PNG pixel width.
        height: PNG pixel height.
        rows: Filter-prefixed RGBA rows generated by an allowlisted fixture.

    Returns:
        One complete PNG with ImageIO-compatible dimensions and CRCs.
    """
    def chunk(kind: bytes, data: bytes) -> bytes:
        """Serialize a PNG chunk with its length and CRC.

        Args:
            kind: Four-byte chunk marker.
            data: The chunk's raw bytes.

        Returns:
            Serialized chunk length, marker, payload and checksum.
        """
        return struct.pack(">I", len(data)) + kind + data + struct.pack(
            ">I", zlib.crc32(kind + data) & 0xFFFFFFFF
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(
        b"IDAT", zlib.compress(b"".join(rows), 9)
    ) + chunk(b"IEND", b"")


@lru_cache(maxsize=3)
def fixture_artwork(name: str) -> bytes:
    """Generate original, deterministic PNG artwork without bundled album art.

    Args:
        name: One of the three synthetic fixture artwork identifiers.

    Returns:
        128-by-128 RGBA PNG bytes for a branded motif or a pure-white cover.

    Raises:
        ValueError: For names not in the fixture allowlist.
    """
    if name not in ("pulse", "orbit", "white"):
        raise ValueError(f"Unknown fixture artwork: {name}")
    rows = []
    for y in range(128):
        row = bytearray(b"\x00")
        for x in range(128):
            if name == "white":
                row.extend((255, 255, 255, 255))
            else:
                accent = ((x + y) // 16) % 2 if name == "pulse" else ((x - y) // 18) % 2
                row.extend((26 + 20 * accent, 8 + (x * 55 // 127), 48 + (y * 70 // 127), 255))
        rows.append(bytes(row))

    return fixture_png(128, 128, rows)


@lru_cache(maxsize=2)
def fixture_path_image(difficulty: str) -> bytes:
    """Paint a tall synthetic chart with original lines and activation bands.

    Args:
        difficulty: One of the fixture's two generated path levels.

    Returns:
        A 256-by-960 PNG without licensed album art or note-chart content.

    Raises:
        ValueError: For a path difficulty without a generated fixture.
    """
    if difficulty not in ("hard", "expert"):
        raise ValueError(f"Unknown fixture path difficulty: {difficulty}")
    rows: list[bytes] = []
    for y in range(960):
        row = bytearray(b"\x00")
        for x in range(256):
            active = 270 <= y <= 355 or 630 <= y <= 720
            accent = (x % 44 <= 2 and x < 226) or y % 96 <= 2
            if active and accent:
                pixel = (242, 181, 68, 255)
            elif accent:
                pixel = (69, 137, 231, 255)
            else:
                pixel = (22, 32 if difficulty == "expert" else 44, 56, 255)
            row.extend(pixel)
        rows.append(bytes(row))
    return fixture_png(256, 960, rows)


class FixtureHandler(BaseHTTPRequestHandler):
    """Serve a tiny allowlist, never proxy requests or perform side effects."""

    @property
    def fixture(self) -> FixtureServer:
        """Require the configured loopback server, not a fallback global fixture."""
        if not isinstance(self.server, FixtureServer):
            raise RuntimeError("FixtureHandler requires a FixtureServer")
        return self.server

    def _json(self, status: int, payload: dict | None, *, etag: str | None = None) -> None:
        """Write a bounded JSON response and explicit publication metadata.

        Args:
            status: HTTP response status.
            payload: JSON object to encode, or None for a bodyless 304.
            etag: Entity tag on the synthetic catalogue endpoint.

        Returns:
            None; bytes are written to the local response stream.
        """
        data = json.dumps(payload, separators=(",", ":")).encode() if payload is not None else b""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        if not self.fixture.unpinned:
            self.send_header("X-FST-Publication-Id", str(self.fixture.publication_id))
        if etag:
            self.send_header("ETag", etag)
        self.end_headers()
        if data:
            self.wfile.write(data)

    def _art(self, name: str) -> None:
        """Serve artwork generated in memory without saving a cold-launch cache.

        Args:
            name: Valid fixture artwork identifier.

        Returns:
            None; the PNG response is written to the local socket.
        """
        data = fixture_artwork(name)
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _path_image(self, difficulty: str, etag: str) -> None:
        """Serve one generated path PNG with a publication-aware ETag.

        Args:
            difficulty: Valid generated fixture path difficulty.
            etag: Stable ETag for the selected image URL.
        """
        unchanged = self.headers.get("If-None-Match") == etag
        data = b"" if unchanged else fixture_path_image(difficulty)
        self.send_response(304 if unchanged else 200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        if not self.fixture.unpinned:
            self.send_header("X-FST-Publication-Id", str(self.fixture.publication_id))
        self.send_header("ETag", etag)
        self.end_headers()
        if data:
            self.wfile.write(data)

    # region Public-only endpoint fixtures
    def do_GET(self) -> None:
        """Answer only known read-only fixture endpoints with valid page bounds.

        Returns:
            None; every known outcome produces a complete HTTP response.
        """
        parsed = urlsplit(self.path)
        path = parsed.path
        query = parse_qs(parsed.query, keep_blank_values=True)
        if path == "/__fixture__/health":
            self._json(200, {
                "ready": True, "sourceHashes": self.fixture.source_hashes,
                "options": self.fixture.options,
            })
        elif path == "/__fixture__/last-score-query":
            self._json(200, {"last": self.fixture.last_score_query()})
        elif path == "/__fixture__/last-full-score-query":
            self._json(200, {"last": self.fixture.last_full_score_query()})
        elif path == "/api/publication":
            self._json(200, self.fixture.publication())
        elif path == "/api/features":
            self._json(200, {"appManual": False})
        elif path in (
            "/__fixture__/art/pulse.png", "/__fixture__/art/orbit.png",
            "/__fixture__/art/white.png",
        ):
            self._art(path.split("/")[-1].removesuffix(".png"))
        elif path == "/api/songs":
            scenarios = query.get("scenario", ["demo"])
            if len(scenarios) != 1 or scenarios[0] not in (
                "demo", "empty", "error", "art-error", "art-skip", "art-white"
            ):
                self._json(400, {"status": "unknown_fixture_scenario"})
                return
            if scenarios[0] == "error":
                self._json(503, {"status": "fixture_unavailable"})
                return
            if scenarios[0] == "art-white" and self.fixture.should_fail_white_catalogue():
                self._json(503, {"status": "fixture_initial_white_failure"})
                return
            if scenarios[0] == "empty":
                songs, etag = EMPTY_SONGS, EMPTY_ETAG
            elif scenarios[0] == "art-error":
                songs = {
                    **DEMO_SONGS,
                    "songs": [
                        {**song, "albumArt": f"/__fixture__/art/unavailable-{index}.png"}
                        for index, song in enumerate(DEMO_SONGS["songs"])
                    ],
                }
                etag = '"fst-fixture-art-error-v1"'
            elif scenarios[0] == "art-skip":
                missing = {
                    **DEMO_SONGS["songs"][0],
                    "songId": "fixture-missing",
                    "title": "Fixture Missing",
                    "albumArt": "/__fixture__/art/unavailable-middle.png",
                }
                songs = {
                    **DEMO_SONGS,
                    "count": 3,
                    "songs": [
                        DEMO_SONGS["songs"][0], missing, DEMO_SONGS["songs"][1],
                    ],
                }
                etag = '"fst-fixture-art-skip-v1"'
            elif scenarios[0] == "art-white":
                songs = {
                    **DEMO_SONGS,
                    "count": 1,
                    "songs": [{
                        **DEMO_SONGS["songs"][0],
                        "songId": "fixture-white",
                        "title": "Fixture White",
                        "albumArt": "/__fixture__/art/white.png",
                    }],
                }
                etag = '"fst-fixture-art-white-v1"'
            else:
                songs, etag = DEMO_SONGS, SONGS_ETAG
            pin = self.headers.get("X-FST-Publication-Id")
            if pin is not None and pin != str(self.fixture.publication_id):
                self._json(409, {"status": "publication_changed"})
            elif self.headers.get("If-None-Match") == etag:
                self._json(304, None, etag=etag)
            else:
                self._json(200, songs, etag=etag)
                if self.fixture.should_stop_after_songs():
                    self.fixture.shutdown()
        elif match := PATH_ARTIFACT.fullmatch(path):
            song_id, instrument, difficulty, data_route = match.groups()
            pin = self.headers.get("X-FST-Publication-Id")
            query_pin = query.get("publicationId", [None])
            if pin is not None and pin != str(self.fixture.publication_id):
                self._json(409, {"status": "publication_changed"})
                return
            if (set(query) - {"generationId", "publicationId"}
                    or len(query.get("generationId", ["fixture-path-generation"])) != 1
                    or len(query_pin) != 1
                    or query_pin[0] not in (None, str(self.fixture.publication_id))):
                self._json(400, {"status": "invalid_path_query"})
                return
            if instrument not in INSTRUMENTS or instrument == "Solo_PeripheralVocals":
                self._json(400, {"status": "invalid_path_instrument"})
                return
            if difficulty not in ("easy", "medium", "hard", "expert"):
                self._json(400, {"status": "invalid_path_difficulty"})
                return
            if (song_id != "fixture-pulse"
                    or query.get("generationId", ["fixture-path-generation"])[0]
                        != "fixture-path-generation"
                    or difficulty in ("easy", "medium")
                    or instrument != "Solo_Guitar"):
                self._json(404, {"status": "path_not_generated"})
                return
            etag = f'"fst-fixture-{difficulty}-{"json" if data_route else "png"}-v1"'
            if data_route:
                if self.headers.get("If-None-Match") == etag:
                    self._json(304, None, etag=etag)
                else:
                    self._json(200, {
                        **PATH_DEMO,
                        "difficulty": difficulty,
                        "pathSummary": f"Two synthetic {difficulty.title()} activations",
                    }, etag=etag)
            else:
                self._path_image(difficulty, etag)
        elif match := LEADERBOARD.fullmatch(path):
            song_id, instrument = match.groups()
            pin = self.headers.get("X-FST-Publication-Id")
            if pin is not None and pin != str(self.fixture.publication_id):
                self._json(409, {"status": "publication_changed"})
                return
            if song_id == "fixture-white" and instrument in INSTRUMENTS:
                self._json(503, {"status": "fixture_score_unavailable"})
                return
            if song_id not in ("fixture-pulse", "fixture-orbit") or instrument not in INSTRUMENTS:
                self._json(404, {"status": "unknown_chart"})
                return
            if any(len(query.get(key, [""])) != 1 for key in ("top", "offset", "leeway")):
                self._json(400, {"status": "invalid_query"})
                return
            try:
                top = int(query.get("top", ["25"])[0])
                offset = int(query.get("offset", ["0"])[0])
                leeway = float(query["leeway"][0]) if "leeway" in query else None
            except (ValueError, IndexError):
                self._json(400, {"status": "invalid_pagination"})
                return
            if (top < 1 or top > 100 or offset < 0
                    or (leeway is not None and (not math.isfinite(leeway) or not -5 <= leeway <= 5))):
                self._json(400, {"status": "invalid_pagination"})
                return
            self.fixture.record_score_query(top, offset, leeway)
            ranks = range(offset + 1, min(offset + top, 26) + 1) if instrument == "Solo_Guitar" else ()
            entries = [
                {
                    "accountId": f"fixture-player-{rank}",
                    "displayName": f"Fixture Player {rank}",
                    "score": 100000 - rank * 100,
                    "rank": rank,
                    "accuracy": 980000 - rank,
                    "isFullCombo": rank % 2 == 0,
                    "stars": 5,
                    "season": 9,
                }
                for rank in ranks
            ]
            total = 26 if instrument == "Solo_Guitar" else 0
            self._json(200, {
                "songId": song_id, "instrument": instrument, "count": len(entries),
                "localEntries": total, "totalEntries": total,
                "showLeaderboardEntryTotals": True, "entries": entries,
            })
            if self.fixture.should_stop_after_score(top):
                self.fixture.shutdown()
        else:
            self._json(404, {"status": "not_found"})

    def do_POST(self) -> None:
        """Reject all profile-tracking, refresh and admin mutation attempts.

        Returns:
            None; a 405 JSON error is written to the local response.
        """
        self._json(405, {"status": "mock_is_read_only"})

    def log_message(self, format: str, *args: object) -> None:
        """Avoid logging player identifiers or request URLs in automation output.

        Args:
            format: Server-provided log format (intentionally not printed).
            args: Request data (intentionally not printed).

        Returns:
            None; test responses and exceptions remain observable to callers.
        """

    # endregion


def main() -> None:
    """Bind the fixture server to loopback and serve until explicitly stopped.

    Returns:
        None; the command remains attached to the current development session.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--unpinned", action="store_true")
    parser.add_argument("--rollover-on-read", type=int)
    parser.add_argument("--fail-first-white-catalogue", action="store_true")
    parser.add_argument("--stop-after-first-songs", action="store_true")
    parser.add_argument("--stop-after-first-score", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("port must be between 1 and 65535")
    if args.rollover_on_read is not None and args.rollover_on_read < 2:
        parser.error("rollover-on-read must be at least 2")
    if args.stop_after_first_songs or args.stop_after_first_score:
        if not args.unpinned:
            parser.error("one-shot offline fixtures require --unpinned")
        if args.stop_after_first_songs and args.stop_after_first_score:
            parser.error("choose one endpoint for the one-shot connection loss")
    with FixtureServer(
        ("127.0.0.1", args.port), FixtureHandler,
        unpinned=args.unpinned, rollover_on_read=args.rollover_on_read,
        fail_first_white_catalogue=args.fail_first_white_catalogue,
        stop_after_first_songs=args.stop_after_first_songs,
        stop_after_first_score=args.stop_after_first_score
    ) as server:
        print(f"Read-only fixture service on 127.0.0.1:{server.server_port}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
