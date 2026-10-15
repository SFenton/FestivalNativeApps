"""Songs Jump index opening judge: ``jump_trace.py`` and its ``a11y_matrix`` wiring (issue #648).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import a11y_matrix  # noqa: E402  (sibling module)
import jump_trace  # noqa: E402  (sibling module)

#: Medium window after the fix: the index keeps the list region's height from its first frame.
STABLE = "jump-frame t={t} height=454.7 width=814.0 cells=27 cell=76.0 first=27.0,140.3 last=483.0,249.7 offset=0.0"
#: Before #648 the pinned header collapsed at the end of the zoom-out, so the index grew and its letters moved down.
GROWN = "jump-frame t={t} height=489.3 width=814.0 cells=27 cell=76.0 first=27.0,157.7 last=483.0,267.0 offset=0.0"


def opening(*frames: str, done: bool = True) -> list[str]:
    """Perf-log lines for one traced opening."""
    return ["jump-open", *frames, *(["jump-done frames=%d" % len(frames)] if done else [])]


class JumpTraceTests(unittest.TestCase):
    """The judge passes a settled opening and catches #648's re-layout."""

    def test_parse_groups_frames_by_opening_and_ignores_other_lines(self):
        lines = ["fade-show JumpButton", *opening(STABLE.format(t=4)), "other", *opening(STABLE.format(t=3), done=False)]
        openings = jump_trace.parse(lines)
        self.assertEqual(len(openings), 2)
        self.assertTrue(openings[0].done)
        self.assertFalse(openings[1].done)
        frame = openings[0].frames[0]
        self.assertEqual((frame.t, frame.cells), (4, 27))
        self.assertEqual(frame.values["first"], (27.0, 140.3))
        self.assertEqual(frame.values["height"], (454.7,))

    def test_stable_opening_passes(self):
        lines = opening(*(STABLE.format(t=t) for t in (4, 20, 120, 240, 900)))
        self.assertEqual(jump_trace.check_opens(jump_trace.parse(lines)), [])

    def test_issue_648_regrowth_fails(self):
        """The pre-fix trace: 454.7 epx tall until the zoom-out ends, then 489.3 with the letters 17 epx lower."""
        lines = opening(STABLE.format(t=9), STABLE.format(t=200), GROWN.format(t=235), GROWN.format(t=500))
        problems = jump_trace.check_opens(jump_trace.parse(lines))
        self.assertEqual(len(problems), 1)
        self.assertIn("t=235 ms", problems[0])
        self.assertIn("height 454.7→489.3", problems[0])
        self.assertIn("first 27.0,140.3→27.0,157.7", problems[0])

    def test_frames_before_the_cells_render_are_ignored(self):
        empty = "jump-frame t=1 height=0.0 width=0.0 cells=0 cell=NaN first=- last=- offset=0.0"
        lines = opening(empty, STABLE.format(t=6), STABLE.format(t=300))
        self.assertEqual(jump_trace.check_opens(jump_trace.parse(lines)), [])

    def test_subpixel_rounding_is_tolerated(self):
        nudged = STABLE.replace("140.3", "140.7").format(t=30)
        self.assertEqual(jump_trace.check_opens(jump_trace.parse(opening(STABLE.format(t=5), nudged))), [])

    def test_cell_count_scroll_and_cell_width_changes_fail(self):
        for changed in (STABLE.replace("cells=27", "cells=3"), STABLE.replace("offset=0.0", "offset=40.0"),
                        STABLE.replace("cell=76.0", "cell=196.0")):
            with self.subTest(changed=changed):
                lines = opening(STABLE.format(t=5), changed.format(t=50))
                self.assertEqual(len(jump_trace.check_opens(jump_trace.parse(lines))), 1)

    def test_missing_cells_done_line_and_openings_fail(self):
        self.assertIn("no frame rendered", jump_trace.check_opens(jump_trace.parse(opening()))[0])
        self.assertIn("no jump-done", jump_trace.check_opens(jump_trace.parse(opening(STABLE.format(t=5),
                                                                                      done=False)))[0])
        self.assertIn("at least 2", jump_trace.check_opens(jump_trace.parse(opening(STABLE.format(t=5))), 2)[0])

    def test_matrix_judges_only_pages_with_a_jump_trace(self):
        lines = opening(STABLE.format(t=5), GROWN.format(t=235))
        self.assertEqual(a11y_matrix.jump_trace_problems({"name": "plain"}, lines), [])
        self.assertEqual(len(a11y_matrix.jump_trace_problems({"jump_trace": 1}, lines)), 1)
        self.assertEqual(len(a11y_matrix.jump_trace_problems({"jump_trace": 2}, opening(STABLE.format(t=5)))), 1)
        self.assertFalse(a11y_matrix.traced({"name": "plain"}))
        self.assertTrue(a11y_matrix.traced({"jump_trace": 1}))
        self.assertTrue(a11y_matrix.traced({"fade_trace": {"JumpButton": ["show"]}}))


if __name__ == "__main__":
    unittest.main()
