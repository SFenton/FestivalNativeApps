"""``artwork_fixture.py``: every album-art read fails, so the backdrop's ``no-art`` state is reachable.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import artwork_fixture as f  # noqa: E402  (sibling module)


class ArtworkFixtureTests(unittest.TestCase):
    """Album-art route matching."""

    def test_art_paths(self):
        for path in ("/__fixture__/art/pulse.png", "/__fixture__/art/orbit.png", "/__fixture__/art/white.png",
                     "/__fixture__/art/unavailable-1.png"):
            self.assertTrue(f.is_art(path), path)

    def test_other_paths_pass_through(self):
        for path in ("/api/songs", "/api/shop", "/__fixture__/health", "/__fixture__/artwork", "/art/pulse.png"):
            self.assertFalse(f.is_art(path), path)


if __name__ == "__main__":
    unittest.main()
