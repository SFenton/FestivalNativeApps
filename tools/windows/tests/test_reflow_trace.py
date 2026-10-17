"""``reflow_trace.py`` / ``reflow_journey.py``: the reflow motion judges (issue #669, pattern ``reflow-motion``).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root (CI: ``native.yml``).
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import a11y_matrix  # noqa: E402  (sibling module)
import reflow_journey as journey  # noqa: E402  (sibling module)
import reflow_trace as t  # noqa: E402  (sibling module)


def split(opening: bool, settle_t: float = 320, animated: bool = True, start: float = 0.0) -> list[str]:
    """One split move's lines."""
    want = 1 if opening else 0
    lines = []
    if animated:
        lines.append(f"split-move open={want} from={start if opening else 1 - start:.3f} to={want:.3f} pane=590.0 "
                     "duration=300")
    lines.append(f"split-settle open={want} animated={1 if animated else 0} motion={1 if animated else 0} "
                 f"t={settle_t if animated else 0:.0f} list={590.0 if opening else 1180.0}")
    return lines


class ParseTests(unittest.TestCase):
    def test_reads_reflow_and_fade_lines_only(self):
        events = t.parse(["backdrop-paused=1.0", "reflow-move host=suggestions moved=3 entered=1 motion=1 t=5",
                          "fade-arm id=x", "  split-settle open=1 animated=0 motion=0 t=0 list=1.0"])
        self.assertEqual([e.kind for e in events], ["reflow-move", "fade-arm", "split-settle"])
        self.assertEqual(events[0].values["host"], "suggestions")
        self.assertEqual(events[0].num("moved"), 3)
        self.assertEqual(events[0].num("missing", 7), 7)
        self.assertEqual(events[0].num("host"), 0)


class SplitTests(unittest.TestCase):
    def test_full_open_and_close_pass(self):
        self.assertEqual(t.check_split(t.parse(split(True)), True), [])
        self.assertEqual(t.check_split(t.parse(split(False, 690)), False), [])

    def test_cut_short_or_late_settle_fails(self):
        self.assertIn("cut short", t.check_split(t.parse(split(True, 100)), True)[0])
        self.assertIn("> 700", t.check_split(t.parse(split(True, 900)), True)[0])

    def test_wrong_direction_or_missing_move_fails(self):
        self.assertTrue(t.check_split(t.parse(split(False)), True))
        self.assertIn("expected one split-move", t.check_split(t.parse(split(True, animated=False)), True)[0])
        self.assertIn("expected one split-move", t.check_split(t.parse(split(True) * 2), True)[0])

    def test_unanimated_settle_after_a_move_fails(self):
        lines = split(True)[:1] + ["split-settle open=1 animated=0 motion=1 t=0 list=590"]
        self.assertIn("expected an animated settle", t.check_split(t.parse(lines), True)[0])

    def test_move_without_width_or_distance_fails(self):
        lines = ["split-move open=1 from=1.000 to=1.000 pane=0 duration=300",
                 "split-settle open=1 animated=1 motion=1 t=300 list=590"]
        problems = t.check_split(t.parse(lines), True)
        self.assertTrue(any("nothing to cover" in p for p in problems))
        self.assertTrue(any("no width" in p for p in problems))

    def test_instant_split(self):
        self.assertEqual(t.check_split_instant(t.parse(split(True, animated=False)), True), [])
        self.assertEqual(t.check_split_instant(t.parse(split(False, animated=False)), False), [])
        self.assertTrue(t.check_split_instant(t.parse(split(True)), True))
        self.assertTrue(t.check_split_instant(t.parse(split(True, animated=False)), False))


class ReflowTests(unittest.TestCase):
    def test_glide_needs_motion_and_a_moved_card(self):
        on = t.parse(["reflow-move host=suggestions moved=2 entered=0 motion=1 t=1"])
        self.assertEqual(t.check_reflow(on, "suggestions"), [])
        self.assertTrue(t.check_reflow(on, "suggestions", minimum=3))
        self.assertIn("no reflow-move", t.check_reflow(on, "shop-grid")[0])
        still = t.parse(["reflow-move host=shop-grid moved=0 entered=0 motion=1 t=1"])
        self.assertTrue(t.check_reflow(still, "shop-grid"))

    def test_instant_reflow(self):
        off = t.parse(["reflow-move host=shop-grid moved=0 entered=0 motion=0 t=1"])
        self.assertEqual(t.check_reflow_instant(off, "shop-grid"), [])
        self.assertIn("no reflow-move", t.check_reflow_instant(off, "card-grid")[0])
        moving = t.parse(["reflow-move host=shop-grid moved=1 entered=0 motion=0 t=1"])
        self.assertTrue(t.check_reflow_instant(moving, "shop-grid"))

    def test_restagger(self):
        self.assertEqual(t.check_no_restagger(t.parse(["fade-play id=x motion=0"])), [])
        self.assertTrue(t.check_no_restagger(t.parse(["fade-arm id=x"])))
        self.assertTrue(t.check_no_restagger(t.parse(["fade-play id=x motion=1"])))


class JourneyTests(unittest.TestCase):
    def test_counts_need_every_reflow(self):
        lines = split(True, animated=False) + ["reflow-move host=suggestions moved=0 entered=0 motion=0 t=1"]
        events = t.parse(lines)
        self.assertEqual(t.check_counts(events, {"split": 1, "suggestions": 1}, False), [])
        self.assertIn("expected 2+", t.check_counts(events, {"split": 2}, None)[0])
        self.assertIn("shop-grid: expected 1+", t.check_counts(events, {"shop-grid": 1}, None)[0])

    def test_counts_with_motion_off_fail_on_any_motion(self):
        events = t.parse(split(True) + ["reflow-move host=shop-grid moved=1 entered=0 motion=1 t=1"])
        self.assertEqual(t.check_counts(events, {"split": 1, "shop-grid": 1}, None), [])
        problems = t.check_counts(events, {"split": 1, "shop-grid": 1}, False)
        self.assertTrue(any("split moved" in p for p in problems))
        self.assertTrue(any("settled animated" in p for p in problems))
        self.assertTrue(any("shop-grid: motion off" in p for p in problems))

    def test_matrix_wiring(self):
        lines = split(True)
        self.assertFalse(a11y_matrix.traced({"name": "plain"}))
        self.assertTrue(a11y_matrix.traced({"reflow_trace": {"split": 1}}))
        self.assertEqual(a11y_matrix.reflow_trace_problems({"name": "plain"}, "normal", lines), [])
        self.assertEqual(a11y_matrix.reflow_trace_problems({"reflow_trace": {"split": 1}}, "normal", lines), [])
        self.assertTrue(a11y_matrix.reflow_trace_problems({"reflow_trace": {"split": 1}}, "no-animations", lines))
        self.assertTrue(a11y_matrix.reflow_trace_problems({"reflow_trace": {"split": 1}}, "app-reduced", lines))

    def test_scenarios_cover_every_reflow_with_and_without_motion(self):
        self.assertEqual(set(journey.SCENARIOS), {
            "rivals-split", "suggestions-columns", "statistics-columns", "shop-grid", "rivals-split-reduced",
            "suggestions-reduced", "shop-grid-reduced"})
        for name, scenario in journey.SCENARIOS.items():
            self.assertEqual("--reduce-motion" in scenario.args, name.endswith("-reduced"), name)
            self.assertTrue(scenario.phases[0].label == "ready", name)

    def test_column_check_composes_restagger(self):
        check = journey.columns("shop-grid", reduced=False)
        self.assertEqual(check(t.parse(["reflow-move host=shop-grid moved=1 entered=0 motion=1 t=1"])), [])
        self.assertTrue(check(t.parse(["reflow-move host=shop-grid moved=1 entered=0 motion=1 t=1", "fade-arm x=1"])))
        reduced = journey.columns("shop-grid", reduced=True)
        self.assertEqual(reduced(t.parse(["reflow-move host=shop-grid moved=0 entered=0 motion=0 t=1"])), [])


if __name__ == "__main__":
    unittest.main()
