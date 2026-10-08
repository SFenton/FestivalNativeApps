"""``shop_fixture.py``: the issue #206 extras (``shop-single``, ``--songs-fail``) and the issue #397 ``long-title`` mode
used by ``a11y_matrix.py`` pages.

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

    def test_long_title_routes_and_renames_one_offer(self):
        state = s.ShopState(shop="long-title")
        self.assertEqual(state.route("/api/shop"), "shop-long-title")
        self.assertIsNone(state.route("/api/songs"))
        demo = s.mock_service.SHOP_DEMO
        before = [dict(song) for song in demo["songs"]]
        feed = s.long_title_feed(demo)
        self.assertEqual([song["songId"] for song in feed["songs"]], [song["songId"] for song in demo["songs"]])
        for song, original in zip(feed["songs"], demo["songs"]):
            if song["songId"] == s.LONG_SONG_ID:
                self.assertEqual((song["title"], song["artist"]), (s.LONG_TITLE, s.LONG_ARTIST))
                self.assertEqual({k: v for k, v in song.items() if k not in ("title", "artist")},
                                 {k: v for k, v in original.items() if k not in ("title", "artist")})
            else:
                self.assertEqual(song, original)
        self.assertEqual(demo["songs"], before, "the shared demo feed must not change")
        self.assertGreater(len(s.LONG_TITLE), 90)

    def test_long_title_needs_its_offer(self):
        with self.assertRaises(ValueError):
            s.long_title_feed({"songs": [{"songId": "other", "title": "Other", "artist": "A"}]})


if __name__ == "__main__":
    unittest.main()
