"""Unit tests for songs_journey.py's pure helpers and its Shop-scenario proxy (no app or desktop needed)."""

from __future__ import annotations

import http.server
import sys
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import songs_journey  # noqa: E402


class ShopPathTests(unittest.TestCase):
    """shop_path adds the fixture scenario to /api/shop only."""

    def test_adds_scenario_to_shop(self) -> None:
        self.assertEqual(songs_journey.shop_path("/api/shop", "shop-empty"), "/api/shop?scenario=shop-empty")

    def test_replaces_existing_scenario_and_keeps_other_query(self) -> None:
        self.assertEqual(songs_journey.shop_path("/api/shop?x=1&scenario=demo", "shop-error"),
                         "/api/shop?x=1&scenario=shop-error")

    def test_leaves_other_paths(self) -> None:
        for path in ("/api/songs", "/api/shop/extra", "/api/publication?x=1"):
            self.assertEqual(songs_journey.shop_path(path, "shop-single"), path)


class SegmentsTests(unittest.TestCase):
    """segments splits at {relaunch}."""

    def test_no_marker_is_one_segment(self) -> None:
        self.assertEqual(songs_journey.segments(["a", "b"]), [["a", "b"]])

    def test_splits_at_markers(self) -> None:
        self.assertEqual(songs_journey.segments(["a", "{relaunch}", "b", "{relaunch}", "c"]), [["a"], ["b"], ["c"]])


class ScenarioTableTests(unittest.TestCase):
    """Every Shop-feed scenario exists and every sort scenario uses the cross-platform IDs."""

    def test_shop_feeds_name_scenarios(self) -> None:
        for name, feed in songs_journey.SHOP_FEEDS.items():
            self.assertIn(name, songs_journey.SCENARIOS)
            self.assertIn(feed, ("shop-single", "shop-empty", "shop-error"))

    def test_sort_scenarios_parse(self) -> None:
        sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
        import uiwin  # noqa: PLC0415

        for name, (_, _, _, steps) in songs_journey.SCENARIOS.items():
            for part in songs_journey.segments(steps):
                for step in songs_journey.expand(part, None, "medium"):
                    with self.subTest(name=name, step=step):
                        uiwin.parse_step(step)


class _Upstream(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        status = 503 if "scenario=shop-error" in self.path else 200
        body = self.path.encode()
        self.send_response(status)
        self.send_header("ETag", '"x"')
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:  # noqa: A002
        pass


class ProxyTests(unittest.TestCase):
    """The proxy forwards status, headers and body, rewriting only /api/shop."""

    def setUp(self) -> None:
        self.upstream = http.server.ThreadingHTTPServer(("127.0.0.1", 0), _Upstream)
        threading.Thread(target=self.upstream.serve_forever, daemon=True).start()

    def tearDown(self) -> None:
        self.upstream.shutdown()
        self.upstream.server_close()

    def _proxy(self, scenario: str) -> songs_journey.ShopScenarioProxy:
        proxy = songs_journey.ShopScenarioProxy(self.upstream.server_address[1], scenario)
        threading.Thread(target=proxy.serve_forever, daemon=True).start()
        self.addCleanup(proxy.server_close)
        self.addCleanup(proxy.shutdown)
        return proxy

    def test_rewrites_shop_and_keeps_headers(self) -> None:
        proxy = self._proxy("shop-single")
        with urllib.request.urlopen(f"http://127.0.0.1:{proxy.port}/api/shop", timeout=5) as response:
            self.assertEqual(response.read(), b"/api/shop?scenario=shop-single")
            self.assertEqual(response.headers["ETag"], '"x"')
        with urllib.request.urlopen(f"http://127.0.0.1:{proxy.port}/api/songs", timeout=5) as response:
            self.assertEqual(response.read(), b"/api/songs")

    def test_forwards_error_status(self) -> None:
        proxy = self._proxy("shop-error")
        with self.assertRaises(urllib.error.HTTPError) as caught:
            urllib.request.urlopen(f"http://127.0.0.1:{proxy.port}/api/shop", timeout=5)
        self.assertEqual(caught.exception.code, 503)


if __name__ == "__main__":
    unittest.main()
