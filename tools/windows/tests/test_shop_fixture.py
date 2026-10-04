"""``shop_fixture.py``: the issue #206 extras (``shop-single``, ``--songs-fail``) used by ``a11y_matrix.py`` pages.

Mode switching and the control route are covered in ``test_shop_journey.py`` (issue #224).
Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import shop_fixture as s  # noqa: E402  (sibling tool)


class ShopFixtureTests(unittest.TestCase):
    """Flag parsing, the one-offer mode and handler patching."""

    def test_parse_options(self):
        options, rest = s.parse_options(["--port", "0"])
        self.assertEqual((options.shop, options.songs, rest), ("demo", "ok", ["--port", "0"]))
        options, rest = s.parse_options(["--shop", "empty", "--port", "0"])
        self.assertEqual((options.shop, options.songs, rest), ("empty", "ok", ["--port", "0"]))
        options, rest = s.parse_options(["--shop=error", "--songs-fail"])
        self.assertEqual((options.shop, options.songs, rest), ("error", "error", []))
        options, _ = s.parse_options(["--songs", "error"])
        self.assertEqual(options.songs, "error")
        with self.assertRaises(SystemExit):
            s.parse_options(["--shop", "bogus"])
        with self.assertRaises(SystemExit):
            s.parse_options(["--shop"])

    def test_shop_single_routes_to_mock_scenario(self):
        state = s.ShopState(shop="shop-single")
        self.assertEqual(state.route("/api/shop"), "shop-shop-single")
        self.assertIsNone(state.route("/api/songs"))
        self.assertIsNone(state.route("/api/shop-art/x.jpg"))
        self.assertTrue(state.released.is_set())

    def test_install_patches_handler(self):
        handler = s.mock_service.FixtureHandler
        original = handler.do_GET
        try:
            s.install(s.ShopState(shop="empty", songs="error"))
            self.assertIsNot(handler.do_GET, original)
        finally:
            handler.do_GET = original


if __name__ == "__main__":
    unittest.main()
