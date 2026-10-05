"""Unit tests for songs_scroll_stress.py's pure helpers (no app or desktop needed)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import songs_scroll_stress as stress  # noqa: E402
import uiwin  # noqa: E402

FRAMES = "ui-frames count=600 p50=8.33 p95=16.67 p99={p99} max={max} over33={over}"


def frames(max_ms: float = 40.0, p99: float = 20.0, over: int = 1) -> str:
    return FRAMES.format(max=max_ms, p99=p99, over=over)


class FrameWindowsTests(unittest.TestCase):
    """frame_windows parses only ui-frames summaries."""

    def test_parses_values(self) -> None:
        windows = stress.frame_windows(["navigate=12.0", frames(95.5), "songs-sections=30.1"])
        self.assertEqual(windows, [{"count": 600.0, "p50": 8.33, "p95": 16.67, "p99": 20.0, "max": 95.5,
                                    "over33": 1.0}])

    def test_skips_empty_values_and_other_lines(self) -> None:
        self.assertEqual(stress.frame_windows(["ui-frames count=3 max=", "ui-framesx count=1"]), [{"count": 3.0}])
        self.assertEqual(stress.frame_windows([]), [])


class SectionsEventsTests(unittest.TestCase):
    """sections_events counts one event per Songs pipeline run."""

    def test_counts_prefix_only(self) -> None:
        lines = ["songs-sections=1.0", "songs-sections=2.0", "songs-sections-x", "first-row=3.0"]
        self.assertEqual(stress.sections_events(lines), 2)


class EvaluateTests(unittest.TestCase):
    """evaluate judges rebuilds, continuity and the stall limit."""

    def test_passes_clean_phase(self) -> None:
        metrics, failures = stress.evaluate([frames(60), frames(95, 36, 4), frames(30)], 16, 250)
        self.assertEqual(failures, [])
        self.assertEqual(metrics, {"rebuilds": 0, "frame_windows": 3, "frames": 1800, "max_ms": 95.0,
                                   "p99_ms": 36.0, "over33": 6})

    def test_flags_rebuild(self) -> None:
        _, failures = stress.evaluate([frames(), "songs-sections=4.0", frames()], 10, 250)
        self.assertEqual(failures, ["1 Songs list rebuild(s)/re-sort(s) while only scrolling"])

    def test_flags_stall_over_limit_only(self) -> None:
        self.assertEqual(stress.evaluate([frames(250)], 5, 250)[1], [])
        _, failures = stress.evaluate([frames(251)], 5, 250)
        self.assertEqual(failures, ["UI-thread stall of 251 ms (limit 250 ms)"])

    def test_flags_missing_frame_summaries(self) -> None:
        _, failures = stress.evaluate([frames()], 20, 250)
        self.assertEqual(failures, ["UI thread stopped reporting frames (1 of 3 expected 5 s summaries)"])
        _, failures = stress.evaluate([], 2, 250)
        self.assertIn("UI thread stopped reporting frames (0 of 1 expected 5 s summaries)", failures)

    def test_flags_summaries_without_max(self) -> None:
        _, failures = stress.evaluate(["ui-frames count=10 p99=12"], 5, 250)
        self.assertEqual(failures, ["frame summaries lack max= (app predates issue #247)"])


class SettledTests(unittest.TestCase):
    """settled needs built rows, frame stats and a quiet period."""

    LINES = ["songs-sections=1.0", frames()]

    def test_settles_after_quiet_period(self) -> None:
        self.assertTrue(stress.settled(self.LINES, 1, 2.0, 10.0, 12.0))

    def test_not_settled_while_quiet_too_short_or_count_changed(self) -> None:
        self.assertFalse(stress.settled(self.LINES, 1, 2.0, 10.0, 11.9))
        self.assertFalse(stress.settled(self.LINES, 0, 2.0, 10.0, 20.0))

    def test_needs_rows_and_frames(self) -> None:
        self.assertFalse(stress.settled([frames()], 0, 0.0, 0.0, 9.0))
        self.assertFalse(stress.settled(["songs-sections=1.0"], 1, 0.0, 0.0, 9.0))


class StickyMismatchTests(unittest.TestCase):
    """sticky_mismatch compares the pinned header with the first on-screen rows' sections."""

    HEADER = '    Text "{0}" id=fst.songs.section-header class=TextBlock rect=789,545,2442,80 heading=2'
    GROUP = '      Group "{0}" id= class=ListViewHeaderItem rect=0,0,0,0 [offscreen,focusable] patterns=Invoke'
    ROW = '        ListItem "{0}, Artist" id=fst.songs.row.{0} class=ListViewItem rect={1} [{2}] patterns=Invoke'

    def tree(self, header: str, *items: tuple[str, ...]) -> list[str]:
        lines = [self.HEADER.format(header), '    List "Songs" id=fst.songs.list class=ListView rect=1,2,3,4 patterns=Scroll']
        for item in items:
            if item[0] in ("group", "ongroup"):
                line = self.GROUP.format(item[1])
                lines.append(line.replace("rect=0,0,0,0 [offscreen,focusable]", "rect=1,2,3,4 [focusable]")
                             if item[0] == "ongroup" else line)
            else:
                on_screen = item[0] == "on"
                lines.append(self.ROW.format(item[1], "789,649,2406,92" if on_screen else "0,0,0,0",
                                             "focusable" if on_screen else "offscreen,focusable"))
                lines.append(f'          Text "{item[1]}" id=TitleText class= rect=0,0,0,0 [offscreen]')
        return lines

    def test_flags_stale_header_after_jump(self) -> None:
        tree = self.tree("#", ("group", "K"), ("off", "k1"), ("group", "L"), ("on", "l1"), ("on", "l2"))
        self.assertEqual(stress.sticky_mismatch(tree), "section header reads '#' over rows of section 'L'")

    def test_matches_first_or_second_row_section(self) -> None:
        tree = self.tree("L", ("group", "L"), ("off", "l0"), ("on", "l1"), ("on", "l2"))
        self.assertIsNone(stress.sticky_mismatch(tree))
        tree = self.tree("M", ("group", "L"), ("on", "l9"), ("group", "M"), ("on", "m1"), ("group", "X"), ("on", "x"))
        self.assertIsNone(stress.sticky_mismatch(tree))

    def test_only_first_two_rows_count(self) -> None:
        tree = self.tree("N", ("group", "L"), ("on", "l1"), ("on", "l2"), ("group", "N"), ("on", "n1"))
        self.assertEqual(stress.sticky_mismatch(tree), "section header reads 'N' over rows of section 'L'")

    def test_previous_section_while_own_title_on_screen(self) -> None:
        tree = self.tree("S", ("group", "S"), ("off", "s9"), ("ongroup", "T"), ("on", "t1"), ("on", "t2"))
        self.assertIsNone(stress.sticky_mismatch(tree))
        tree = self.tree("S", ("group", "S"), ("off", "s9"), ("group", "T"), ("on", "t1"), ("on", "t2"))
        self.assertEqual(stress.sticky_mismatch(tree), "section header reads 'S' over rows of section 'T'")
        tree = self.tree("F", ("group", "S"), ("ongroup", "T"), ("on", "t1"))
        self.assertEqual(stress.sticky_mismatch(tree), "section header reads 'F' over rows of section 'T'")

    def test_inconclusive_without_header_or_rows(self) -> None:
        self.assertIsNone(stress.sticky_mismatch(self.tree("#", ("group", "L"), ("off", "l1"))))
        self.assertIsNone(stress.sticky_mismatch(self.tree("#")[1:] + [self.ROW.format("a", "1,1,1,1", "")]))
        self.assertIsNone(stress.sticky_mismatch(["garbage", ""]))


class HeaderStepsTests(unittest.TestCase):
    """header_steps visits each position and dumps a tree there."""

    def test_steps(self) -> None:
        folder = Path("out")
        steps = stress.header_steps(folder, (50, 0))
        self.assertEqual(steps, ["scrollto:id=fst.songs.list,50", "wait:1", f"tree:{folder / 'tree-50.txt'}",
                                 "scrollto:id=fst.songs.list,0", "wait:1", f"tree:{folder / 'tree-0.txt'}"])
        for step in stress.header_steps(folder):
            uiwin.parse_step(step)


class FlingStepsTests(unittest.TestCase):
    """fling_steps builds parseable drive steps that end at the top."""

    def test_shape_without_wheel(self) -> None:
        steps = stress.fling_steps(2, 1, False)
        self.assertEqual(steps[0], "waitfor:id=fst.songs.list@30")
        self.assertEqual(steps[1:5], ["scrollto:id=fst.songs.list,2", "scrollto:id=fst.songs.list,0",
                                      "scrollto:id=fst.songs.list,3", "scrollto:id=fst.songs.list,0"])
        self.assertIn("scrollto:id=fst.songs.list,100", steps)
        self.assertIn("key:home", steps)
        self.assertFalse(any(step.startswith("scroll:") for step in steps))
        self.assertEqual(steps[-2:], ["assertstate:id=fst.songs.list|scroll=0@10", "waitfor:id=fst.songs.list@5"])

    def test_wheel_adds_bursts_and_cycles(self) -> None:
        steps = stress.fling_steps(3, 2, True)
        self.assertEqual(sum(step.startswith("scroll:") for step in steps), 3 * 2 + 2 * 2)
        self.assertEqual(steps.count("key:end"), 2)

    def test_every_step_parses(self) -> None:
        for step in stress.fling_steps(4, 2, True):
            uiwin.parse_step(step)


class CloseFailureTests(unittest.TestCase):
    """close_failure flags shutdown crashes and kills (issue #247's auto-scroll close crash)."""

    def test_clean_exit_passes(self) -> None:
        self.assertIsNone(stress.close_failure({"pid": 1, "closed": True, "killed": False, "exitCode": 0}))

    def test_older_driver_without_exit_code_passes(self) -> None:
        self.assertIsNone(stress.close_failure({"pid": 1, "closed": True}))

    def test_stowed_exception_fails(self) -> None:
        message = stress.close_failure({"killed": False, "exitCode": -1073741189})
        self.assertIn("0xc000027b", message)

    def test_kill_fails(self) -> None:
        self.assertIn("killed", stress.close_failure({"killed": True, "exitCode": -1}))


if __name__ == "__main__":
    unittest.main()
