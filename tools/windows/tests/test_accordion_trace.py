"""``accordion_trace.py`` / ``accordion_journey.py``: the accordion choreography judges (issue #561, load-transition R10).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root (CI: ``native.yml``).
"""

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import accordion_journey as journey  # noqa: E402  (sibling module)
import accordion_trace as t  # noqa: E402  (sibling module)

ROOT = Path(__file__).resolve().parents[3]
ID = "fst.songs.filter.year"
EASE = [0.0, 0.1, 0.3, 0.55, 0.75, 0.88, 0.95, 0.99, 1.0]
"""A 150 ms CSS-ease-like progression sampled every ~17 ms."""


def trace(opening: bool, target: float = 100.0, begin: float = 18, frames: list[tuple[float, float, float]] | None = None,
          settle: bool | None = None) -> list[str]:
    """A move's lines; ``frames`` are ``(t, height, opacity)``, default the sequenced choreography."""
    if frames is None:
        frames = [(9, 0 if opening else target, 0 if opening else 1)]
        for i, p in enumerate(EASE):
            at = begin + i * 17
            frames.append((at, target * p, 0) if opening else (at, target, 1 - p))
        for i, p in enumerate(EASE):
            at = begin + 150 + i * 17
            frames.append((at, target, p) if opening else (at, target * (1 - p), 0))
    lines = [f"accordion-move id={ID} open={int(opening)} from={0 if opening else target} to={target if opening else 0} "
             f"opacity={0 if opening else 1}"]
    lines += [f"accordion-frame id={ID} t={at:.0f} height={h:.1f} opacity={o:.3f}" for at, h, o in frames[:1]]
    lines.append(f"accordion-begin id={ID} t={begin:.0f}")
    lines += [f"accordion-frame id={ID} t={at:.0f} height={h:.1f} opacity={o:.3f}" for at, h, o in frames[1:]]
    final = opening if settle is None else settle
    lines.append(f"accordion-settle id={ID} open={int(final)} animated=1 motion=1 t={begin + 300:.0f}")
    return lines


def check(lines: list[str], opening: bool) -> list[str]:
    return t.check_toggle(t.parse(lines), ID, (opening,))


class ParseTests(unittest.TestCase):
    def test_groups_lines_into_moves(self):
        lines = ["startup=1.0", *trace(True), "accordion-frame id=other t=3 height=1.0 opacity=0.000", *trace(False)]
        moves = t.moves(t.parse(lines), ID)
        self.assertEqual([True, False], [m.opening for m in moves])
        self.assertEqual(19, len(moves[0].frames))
        self.assertEqual(18, moves[0].origin)
        self.assertEqual(100, moves[1].target)
        self.assertIsNotNone(moves[1].settle)


class ChoreographyTests(unittest.TestCase):
    def test_sequenced_open_and_close_pass(self):
        self.assertEqual([], check(trace(True), True))
        self.assertEqual([], check(trace(False), False))

    def test_snap_fails(self):
        snap = [(9, 0, 0), (26, 100, 1)]
        found = " ".join(check(trace(True, frames=snap), True))
        self.assertIn("grow snapped", found)
        self.assertIn("fade-in snapped", found)

    def test_simultaneous_height_and_fade_fails(self):
        together = [(9, 0, 0)] + [(18 + i * 34, 100 * p, p) for i, p in enumerate(EASE)]
        found = check(trace(True, frames=together), True)
        self.assertTrue(any("content visible before the section reached full height" in f for f in found), found)

    def test_close_that_collapses_while_visible_fails(self):
        together = [(9, 100, 1)] + [(18 + i * 34, 100 * (1 - p), 1 - p) for i, p in enumerate(EASE)]
        found = check(trace(False, frames=together), False)
        self.assertTrue(any("content visible before the section reached full height" in f for f in found), found)

    def test_reversed_order_fails(self):
        # Fades in first at zero height, then grows: content is "visible" while the section is still closed.
        reversed_open = [(9, 0, 0)] + [(18 + i * 17, 0, p) for i, p in enumerate(EASE)] + \
                        [(168 + i * 17, 100 * p, 1) for i, p in enumerate(EASE)]
        self.assertNotEqual([], check(trace(True, frames=reversed_open), True))

    def test_stalled_first_frame_jump_fails(self):
        # The pre-fix Settings trace: the storyboard ran through a 56 ms stall and the first frame jumped 87 %.
        stalled = [(56, 0, 0), (61, 68.3, 0), (71, 70.3, 0), (79, 72.7, 0), (120, 78.7, 0), (137, 78.7, 0.026),
                   (170, 78.7, 0.434), (212, 78.7, 0.838), (278, 78.7, 1.0)]
        found = check(trace(True, target=78.7, begin=0, frames=stalled), True)
        self.assertTrue(any("jumped 87%" in f for f in found), found)

    def test_mid_move_stall_step_is_excused(self):
        # A loaded host's Suggestions trace: a 48 ms UI-thread stall during the fade; the sample right after it is
        # stale, so the next one steps 62 %. The order and windows still hold, so it passes.
        fade = [(9, 0, 0), (37, 82.7, 0), (62, 339, 0), (86, 466, 0), (111, 560.7, 0), (136, 612.7, 0),
                (161, 630.7, 0), (169, 632, 0), (177, 632, 0.031), (225, 632, 0.091), (227, 632, 0.710),
                (252, 632, 0.837), (285, 632, 0.963), (318, 632, 1.0)]
        self.assertEqual([], check(trace(True, target=632, begin=14, frames=fade), True))
        unstalled = [(9, 0, 0), (37, 82.7, 0), (62, 339, 0), (86, 466, 0), (111, 560.7, 0), (136, 612.7, 0),
                     (161, 630.7, 0), (169, 632, 0), (177, 632, 0.031), (194, 632, 0.091), (211, 632, 0.710),
                     (252, 632, 0.837), (285, 632, 0.963), (318, 632, 1.0)]
        found = check(trace(True, target=632, begin=14, frames=unstalled), True)
        self.assertTrue(any("opacity jumped 62%" in f for f in found), found)

    def test_late_begin_fails(self):
        found = check(trace(True, begin=400), True)
        self.assertTrue(any("began 400 ms after the toggle" in f for f in found), found)

    def test_phase_outside_its_window_fails(self):
        slow = [(9, 0, 0)] + [(18 + i * 50, 100 * p, 0) for i, p in enumerate(EASE)] + \
               [(470 + i * 17, 100, p) for i, p in enumerate(EASE)]
        found = check(trace(True, frames=slow), True)
        self.assertTrue(any("grow frame outside" in f for f in found), found)
        self.assertTrue(any("fade-in frame outside" in f for f in found), found)

    def test_wrong_settle_or_count_fails(self):
        self.assertTrue(any("not where the move was heading" in f for f in check(trace(True, settle=False), True)))
        self.assertEqual([f"{ID}: expected 1 move(s), traced 2"], check([*trace(True), *trace(False)], True))
        self.assertEqual(["expected an opening move, got a closing one"],
                         t.check_open(t.moves(t.parse(trace(False)), ID)[0]))


class ReduceMotionTests(unittest.TestCase):
    def test_instant_settle_passes(self):
        lines = [f"accordion-settle id={ID} open=1 animated=0 motion=0 t=0"]
        self.assertEqual([], t.check_instant(t.parse(lines), ID, (True,)))

    def test_any_move_fails(self):
        found = t.check_instant(t.parse(trace(True)), ID, (True,))
        self.assertTrue(any("move line under Reduce Motion" in f for f in found), found)
        self.assertTrue(any("animated settle" in f for f in found), found)

    def test_motion_on_fails(self):
        lines = [f"accordion-settle id={ID} open=0 animated=0 motion=1 t=0"]
        self.assertEqual([f"{ID}: motion=1 while Reduce Motion is on"], t.check_instant(t.parse(lines), ID, (False,)))


class JourneyTests(unittest.TestCase):
    def test_every_mover_path_and_reduce_motion_is_driven(self):
        self.assertEqual({"songs-year", "suggestions", "settings-leeway", "songs-year-reduced", "settings-reduced"},
                         set(journey.SCENARIOS))
        for name, scenario in journey.SCENARIOS.items():
            labels = [phase.label for phase in scenario.phases]
            self.assertEqual(["open", "close"], labels[-2:], name)
            self.assertEqual("--reduce-motion" in scenario.args, name.endswith("-reduced"), name)
            self.assertTrue((journey.TOOLS / scenario.fixture[0]).is_file(), name)

    def test_launch_args_carry_perf_log_and_flags(self):
        args = journey.launch_args("songs-year-reduced", 5000, Path("app.exe"))
        self.assertTrue(any(a.startswith("--arg=--perf-log=") for a in args))
        self.assertIn("--arg=--reduce-motion", args)
        self.assertIn("--arg=--base-url=http://127.0.0.1:5000/", args)

    def test_mover_still_traces_and_waits_for_first_frame(self):
        code = (ROOT / "windows" / "Festival.App" / "Controls" / "Accordion.cs").read_text(encoding="utf-8")
        for pattern, why in ((r"TraceMove\(value,", "moves are no longer traced"),
                             (r"CompositionTarget\.Rendering \+= OnStartFrame;", "moves begin before the first frame"),
                             (r"TraceBegin\(\);\s*\n\s*running\.Begin\(\);", "the begin is no longer traced"),
                             (r"TraceSettle\(value, animated\)", "settles are no longer traced"),
                             (r"new AccordionMover\(root, clip, body, body, content, named: expander\)",
                              "Expander moves are no longer named by the Expander's AutomationId")):
            self.assertRegex(code, re.compile(pattern), why)


if __name__ == "__main__":
    unittest.main()
