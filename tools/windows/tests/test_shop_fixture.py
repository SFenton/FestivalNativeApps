"""``shop_fixture.py``: forced Item Shop scenarios for launched builds.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import shop_fixture as s  # noqa: E402  (sibling tool)


class ShopFixtureTests(unittest.TestCase):
    """Flag parsing and request rewriting."""

    def test_take_options(self):
        self.assertEqual(s.take_options(["--port", "0"]), ("demo", False, ["--port", "0"]))
        self.assertEqual(s.take_options(["--shop", "empty", "--port", "0"]), ("empty", False, ["--port", "0"]))
        self.assertEqual(s.take_options(["--shop=error", "--songs-fail"]), ("error", True, []))
        with self.assertRaises(SystemExit):
            s.take_options(["--shop", "bogus"])
        with self.assertRaises(SystemExit):
            s.take_options(["--shop"])

    def test_rewrite(self):
        self.assertEqual(s.rewrite("/api/shop", "empty", False), "/api/shop?scenario=empty")
        self.assertEqual(s.rewrite("/api/shop?x=1", "error", False), "/api/shop?scenario=error")
        self.assertEqual(s.rewrite("/api/shop", "demo", False), "/api/shop")
        self.assertIsNone(s.rewrite("/api/songs", "demo", True))
        self.assertEqual(s.rewrite("/api/songs", "empty", False), "/api/songs")
        self.assertEqual(s.rewrite("/api/shop-art/x.jpg", "empty", True), "/api/shop-art/x.jpg")

    def test_install_patches_handler(self):
        handler = s.mock_service.FixtureHandler
        original = handler.do_GET
        try:
            s.install("empty", True)
            self.assertIsNot(handler.do_GET, original)
        finally:
            handler.do_GET = original


if __name__ == "__main__":
    unittest.main()
