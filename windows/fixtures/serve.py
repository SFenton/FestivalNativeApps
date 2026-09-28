"""Serve only the checked-in songs fixture on a loopback GET endpoint."""

from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

SONGS = (Path(__file__).parent / "songs.json").read_bytes()
PUBLICATION = "fixture-publication-001"
ETAG = '"fixture-etag"'


class FixtureHandler(BaseHTTPRequestHandler):
    """Read-only handler for the single provisional songs route."""

    def do_GET(self):
        """Return the snapshot or a conditional publication response."""
        if self.path != "/api/songs":
            self.send_error(404)
            return
        if self.headers.get("X-Publication-Id", PUBLICATION) != PUBLICATION:
            self.send_error(409, "Fixture publication changed")
            return
        if self.headers.get("If-None-Match") == ETAG:
            self.send_response(304)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(SONGS)))
        self.send_header("ETag", ETAG)
        self.end_headers()
        self.wfile.write(SONGS)

    def do_POST(self):
        """Reject mutations rather than pretending a fixture accepted them."""
        self.send_error(405)


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 8765), FixtureHandler).serve_forever()
