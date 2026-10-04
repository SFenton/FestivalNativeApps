"""Loopback fixture service for Windows Suggestions screenshots and UI tests.

Serves the synthetic Suggestions parity fixture (windows/Festival.Core.Tests/Fixtures/suggestions-parity.json)
in the public wire formats the app reads: GET /api/publication, /api/songs, /api/player/fixture-suggest
(compact scores) and /api/player/fixture-suggest/rivals/all, plus generated abstract artwork. No real
player names, album art or production data.

Launch the app with ``--base-url http://127.0.0.1:8766/`` and ``FST_DEBUG_PROFILE=fixture-suggest:Fixture Player``
(Debug only; in-memory settings) and optionally ``FST_DEBUG_SUGGESTIONS_SEED=1`` for a deterministic mix.

State accounts for UI journeys (``tools/windows/suggestions_journey.py``): ``fixture-suggest-syncing`` answers 202,
``fixture-suggest-denied`` 403 and ``fixture-suggest-slow`` the normal profile after ``--slow-seconds`` (loading state).

Usage: python tools/windows/suggestions_fixture_server.py [--port 8766] [--syncing] [--no-rivals] [--slow-seconds 8]
"""

import argparse
import colorsys
import json
import re
import sys
import time
from functools import lru_cache
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from mock_service import fixture_png  # noqa: E402  (shared PNG encoder)

FIXTURE = ROOT / "windows" / "Festival.Core.Tests" / "Fixtures" / "suggestions-parity.json"
ACCOUNT = "fixture-suggest"
PUBLICATION = {"contractVersion": 1, "publicationId": 7, "previousPublicationId": None, "publishedScrapeId": 42,
               "publishedAt": "2026-01-01T00:00:00Z", "readyForPinning": True, "pinningEnabled": True, "unreadySurfaces": []}
ACCOUNTS = {ACCOUNT, f"{ACCOUNT}-syncing", f"{ACCOUNT}-denied", f"{ACCOUNT}-slow"}
PLAYER = re.compile(r"/api/player/([A-Za-z0-9-]+)(/rivals/all)?")
INSTRUMENTS = ["Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals", "Solo_PeripheralGuitar",
               "Solo_PeripheralBass", "Solo_PeripheralVocals", "Solo_PeripheralCymbals", "Solo_PeripheralDrums"]


def load() -> dict:
    """Read the parity fixture."""
    return json.loads(FIXTURE.read_text(encoding="utf-8"))


def songs_body(fixture: dict) -> dict:
    """Catalogue envelope with generated artwork references."""
    songs = [dict(song, albumArt=f"/__fixture__/art/{song['songId']}.png", durationSeconds=180 + i)
             for i, song in enumerate(fixture["songs"])]
    return {"count": len(songs), "currentSeason": 12, "songs": songs}


def player_body(fixture: dict, account: str = ACCOUNT) -> dict:
    """Compact public profile (si/ins/sc/acc/fc/st/sn/rk/te) for a fixture account."""
    scores = []
    for row in fixture["scores"]:
        compact = {"si": row["songId"], "ins": f"{1 << INSTRUMENTS.index(row['instrument']):02x}", "sc": row["score"],
                   "acc": row["accuracy"] / 1000, "fc": row["fullCombo"], "sn": row["season"]}
        if "stars" in row:
            compact["st"] = row["stars"]
        if "rank" in row:
            compact["rk"] = row["rank"]
            compact["te"] = row["totalEntries"]
        scores.append(compact)
    return {"accountId": account, "displayName": "Fixture Player", "totalScores": len(scores), "scores": scores}


@lru_cache(maxsize=256)
def artwork(song_id: str) -> bytes:
    """Deterministic abstract 96x96 cover: a diagonal two-tone gradient hued by the song ID."""
    hue = (sum(song_id.encode()) * 37 % 360) / 360
    rows = []
    for y in range(96):
        row = bytearray(b"\x00")
        for x in range(96):
            band = ((x + y) // 24) % 2
            r, g, b = colorsys.hsv_to_rgb((hue + 0.08 * band) % 1, 0.55, 0.35 + 0.5 * (x + y) / 190)
            row.extend((int(r * 255), int(g * 255), int(b * 255), 255))
        rows.append(bytes(row))
    return fixture_png(96, 96, rows)


class Handler(BaseHTTPRequestHandler):
    """Routes the four reads the Suggestions page needs; everything else is 404."""

    protocol_version = "HTTP/1.1"  # keep-alive, like the real service (HttpClient pools connections)
    fixture: dict = {}
    syncing = False
    rivals = True
    slow_seconds = 8.0

    def log_message(self, fmt: str, *args) -> None:  # noqa: D102 - quiet server
        return

    def _send(self, status: int, body: bytes, content_type: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-FST-Publication-Id", str(PUBLICATION["publicationId"]))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, status: int, payload: dict) -> None:
        self._send(status, json.dumps(payload, separators=(",", ":")).encode())

    def do_GET(self) -> None:  # noqa: N802 - http.server API
        """Serve one fixture read."""
        path = self.path.split("?")[0]
        if path == "/api/publication":
            self._json(200, PUBLICATION)
        elif path == "/api/songs":
            self._json(200, songs_body(self.fixture))
        elif (match := PLAYER.fullmatch(path)) and match.group(1) in ACCOUNTS:
            self._player(match.group(1), match.group(2))
        elif path.startswith("/__fixture__/art/") and path.endswith(".png"):
            self._send(200, artwork(path.rsplit("/", 1)[-1][:-4]), "image/png")
        else:
            self._json(404, {"error": "not found"})


    def _player(self, account: str, sub: str | None) -> None:
        """Serve a fixture account's profile or rivals/all in its scripted state."""
        if sub == "/rivals/all":
            if self.rivals and account in (ACCOUNT, f"{ACCOUNT}-slow"):
                self._json(200, dict(self.fixture["rivalsAll"], accountId=account))
            else:
                self._json(404, {"error": "not found"})
            return
        if account == f"{ACCOUNT}-denied":
            self._json(403, {"status": "player_profile_denied"})
        elif self.syncing or account == f"{ACCOUNT}-syncing":
            self._json(202, {"accountId": account, "displayName": "Fixture Player", "totalScores": 0, "scores": [],
                             "status": "syncing", "notYetPublished": True})
        else:
            if account == f"{ACCOUNT}-slow":
                time.sleep(self.slow_seconds)
            self._json(200, player_body(self.fixture, account))


def main() -> None:
    """Run the server until interrupted."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--syncing", action="store_true", help="answer the player read with HTTP 202 syncing")
    parser.add_argument("--no-rivals", action="store_true", help="404 the rivals/all read")
    parser.add_argument("--slow-seconds", type=float, default=8.0, help="profile delay for fixture-suggest-slow")
    args = parser.parse_args()
    Handler.fixture = load()
    Handler.syncing = args.syncing
    Handler.rivals = not args.no_rivals
    Handler.slow_seconds = args.slow_seconds
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
