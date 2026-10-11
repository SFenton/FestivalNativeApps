"""``FstUia``'s ellipsis detector (``assertmarquee:<sel>|static|…``) on saved captures (issue #529).

The hosted ``windows-ui`` runner draws at 100% scale, where a small line's ellipsis dots are one pixel apart and
anti-aliasing leaves faint ink between them; ``song-header-title``'s pinned artist failed there as "one stroke". The
crops in ``fixtures/`` come from that CI capture (synthetic fixture text, no artwork).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root. Builds ``FstUia`` once (``dotnet``).
"""

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.windows import uiwin as u

_FIXTURES = Path(__file__).resolve().parent / "fixtures"


@unittest.skipUnless(sys.platform == "win32" and shutil.which("dotnet"), "FstUia needs Windows and dotnet")
class EllipsisDetectorTests(unittest.TestCase):
    """Replays ``EndsInEllipsis`` through the offline ``ellipsis`` command."""

    exe: Path

    @classmethod
    def setUpClass(cls):
        cls.exe = u.driver_exe()

    def check(self, image: str) -> dict:
        with tempfile.TemporaryDirectory() as tmp:
            req, resp = Path(tmp) / "req.json", Path(tmp) / "resp.json"
            req.write_text(json.dumps({"command": "ellipsis", "image": str(_FIXTURES / image)}), encoding="utf-8")
            subprocess.run([str(self.exe), "--request", str(req), "--response", str(resp)], timeout=60, check=False)
            data = json.loads(resp.read_text(encoding="utf-8"))
        self.assertTrue(data["ok"], data.get("error"))
        return data["result"]

    def test_dots_one_pixel_apart_are_an_ellipsis(self):
        result = self.check("ellipsis-pinned-artist-100.png")
        self.assertTrue(result["ellipsis"], result["detail"])

    def test_title_ellipsis_at_100_percent(self):
        result = self.check("ellipsis-pinned-title-100.png")
        self.assertTrue(result["ellipsis"], result["detail"])

    def test_clipped_letter_is_not_an_ellipsis(self):
        result = self.check("clipped-pinned-artist-100.png")
        self.assertFalse(result["ellipsis"])
        self.assertIn("last glyph", result["detail"])

    def test_short_fitting_line_is_not_an_ellipsis(self):
        self.assertFalse(self.check("fits-duos-100.png")["ellipsis"])


if __name__ == "__main__":
    unittest.main()
