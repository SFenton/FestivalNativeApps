"""Pure helpers of the installed-PWA lab (``tools/pwa_ios.py``).

Covers the pieces that turn recordings into measurements and clips, and the
fixture proxy's header filtering, without a simulator, Safari or ``avconvert``.
"""

import sys as _sys
import unittest as _unittest

if _sys.platform == "win32":  # Apple tooling imports the POSIX-only fcntl module.
    raise _unittest.SkipTest("Apple simulator tooling runs only on macOS")

import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.pwa_ios import (
    INSTALL_STEPS,
    MARK_ORIGIN_OFFSET,
    SYNTHETIC_READS,
    clip_plan,
    load_marks,
    motion_segments,
    proxy_headers,
)


class MotionSegmentsTests(unittest.TestCase):
    """Frame differences become transition start/end/peak."""

    def test_groups_runs_and_tolerates_short_gaps(self):
        diffs = [0, 5, 6, 0, 7, 0, 0, 0, 0, 9]
        segments = motion_segments(diffs, fps=10, threshold=1.0, gap=1)
        self.assertEqual(len(segments), 2)
        start, end, peak = segments[0]
        self.assertAlmostEqual(start, 0.1)
        self.assertAlmostEqual(end, 0.5)
        self.assertEqual(peak, 7)
        self.assertAlmostEqual(segments[1][0], 0.9)

    def test_quiet_video_has_no_segments(self):
        self.assertEqual(motion_segments([0.1] * 20, fps=30, threshold=1.0), [])


class MarksAndClipsTests(unittest.TestCase):
    """``mark:`` stamps map onto the video timeline and into clip cuts."""

    def test_marks_are_video_relative(self):
        with TemporaryDirectory() as folder:
            video = str(Path(folder) / "run.mp4")
            Path(video + ".marks.txt").write_text(
                "100.000 recording-start\n105.500 clip:songs\n107.000 end\n", encoding="utf-8")
            marks = load_marks(video)
        self.assertEqual([label for _, label in marks], ["clip:songs", "end"])
        self.assertAlmostEqual(marks[0][0], 5.5 - MARK_ORIGIN_OFFSET)

    def test_missing_marks_file_is_empty(self):
        self.assertEqual(load_marks("/nonexistent/video.mp4"), [])

    def test_clip_runs_to_end_mark_or_next_clip(self):
        marks = [(2.0, "clip:a"), (4.0, "end"), (6.0, "clip:b"), (9.0, "clip:c")]
        plan = clip_plan(marks, duration=10.0, pre=0.5, post=0.5)
        self.assertEqual([name for name, _, _ in plan], ["a", "b", "c"])
        name, start, length = plan[0]
        self.assertAlmostEqual(start, 1.5)
        self.assertAlmostEqual(length, 3.0)
        self.assertAlmostEqual(plan[1][2], 4.0)  # 5.5 -> 9.5
        self.assertAlmostEqual(plan[2][1] + plan[2][2], 10.0)  # clamped to duration


class FixtureProxyTests(unittest.TestCase):
    """The loopback reference origin never forwards identity headers."""

    def test_strips_selected_profile_and_api_key_headers(self):
        kept = proxy_headers([
            ("X-FST-Selected-Player", "p"), ("x-fst-selected-profile-type", "player"),
            ("X-API-Key", "secret"), ("Host", "127.0.0.1"), ("Accept", "application/json"),
            ("X-FST-Publication-Id", "7"),
        ])
        self.assertEqual(kept, {"Accept": "application/json", "X-FST-Publication-Id": "7"})

    def test_service_info_is_synthesized(self):
        self.assertIn("/api/service-info", SYNTHETIC_READS)
        self.assertFalse(SYNTHETIC_READS["/api/service-info"]["publication"]["publicReadsFrozen"])


class InstallStepsTests(unittest.TestCase):
    """Add to Home Screen scripts stay idempotent and popover-safe."""

    def test_every_form_factor_skips_an_existing_icon_first(self):
        for kind, steps in INSTALL_STEPS.items():
            self.assertIn("stopIfExists:{label}", steps, kind)
            self.assertLess(steps.index("stopIfExists:{label}"), steps.index("openURL:{url}"), kind)

    def test_pad_never_swipes_the_share_popover(self):
        self.assertFalse(any(step.startswith(("scrollTo:", "swipe:")) for step in INSTALL_STEPS["pad"]))


if __name__ == "__main__":
    unittest.main()
