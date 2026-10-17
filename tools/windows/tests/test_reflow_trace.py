"""``reflow_trace.py`` / ``reflow_journey.py``: the reflow motion judges (issue #669, pattern ``reflow-motion``).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root (CI: ``native.yml``).
"""

import json
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


class StopTests(unittest.TestCase):
    """``check_stops``: motion turned off mid-reflow stops it at once (R4)."""

    MOVE = "split-move open=1 from=0.000 to=1.000 pane=590.0 duration=3000"

    def test_parses_stop_lines(self):
        events = t.parse(["reflow-stop stopped=4 motion=0 t=81420"])
        self.assertEqual([e.kind for e in events], ["reflow-stop"])
        self.assertEqual(events[0].num("stopped"), 4)

    def test_split_stopped_mid_move_passes(self):
        lines = [self.MOVE, "split-settle open=1 animated=1 motion=0 stopped=1 t=1100 list=590.0",
                 "split-move open=0 from=1.000 to=0.000 pane=590.0 duration=3000",
                 "split-settle open=0 animated=1 motion=0 stopped=1 t=700 list=1180.0"]
        self.assertEqual(t.check_stops(t.parse(lines), {"split": 2}), [])

    def test_split_that_ran_on_fails(self):
        ran_on = [self.MOVE, "split-settle open=1 animated=1 motion=0 stopped=1 t=3050 list=590.0"]
        self.assertTrue(any("ran on" in p for p in t.check_stops(t.parse(ran_on), {"split": 1})))
        completed = [self.MOVE, "split-settle open=1 animated=1 motion=1 stopped=0 t=3050 list=590.0"]
        self.assertTrue(any("expected 1+" in p for p in t.check_stops(t.parse(completed), {"split": 1})))
        motion_on = [self.MOVE, "split-settle open=1 animated=1 motion=1 stopped=1 t=900 list=590.0"]
        self.assertTrue(any("motion off" in p for p in t.check_stops(t.parse(motion_on), {"split": 1})))
        no_move = ["split-settle open=1 animated=1 motion=0 stopped=1 t=900 list=590.0"]
        self.assertTrue(any("without a move" in p for p in t.check_stops(t.parse(no_move), {"split": 1})))

    def test_cards_stopped_after_moving_reflows_pass(self):
        lines = ["reflow-move host=card-grid moved=3 entered=0 motion=1 t=10", "reflow-stop stopped=3 motion=0 t=900",
                 "reflow-move host=card-grid moved=2 entered=1 motion=1 t=3000", "reflow-stop stopped=3 motion=0 t=3600"]
        self.assertEqual(t.check_stops(t.parse(lines), {"cards": 2}), [])

    def test_cards_that_never_stopped_fail(self):
        moved_only = ["reflow-move host=card-grid moved=3 entered=0 motion=1 t=10"]
        self.assertTrue(any("cards: expected 1+" in p for p in t.check_stops(t.parse(moved_only), {"cards": 1})))
        unmoved = ["reflow-move host=card-grid moved=0 entered=0 motion=0 t=10", "reflow-stop stopped=1 motion=0 t=20"]
        self.assertTrue(any("without a moving reflow" in p for p in t.check_stops(t.parse(unmoved), {"cards": 1})))
        empty = ["reflow-move host=card-grid moved=3 entered=0 motion=1 t=10", "reflow-stop stopped=0 motion=0 t=20"]
        self.assertTrue(t.check_stops(t.parse(empty), {"cards": 1}))


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
        self.assertTrue(a11y_matrix.traced({"reflow_stops": {"cards": 1}}))
        self.assertTrue(a11y_matrix.traced_reflow({"reflow_stops": {"cards": 1}}))
        self.assertTrue(a11y_matrix.traced_reflow({"reflow_trace": {"split": 1}}))
        self.assertFalse(a11y_matrix.traced_reflow({"fade_trace": {"min": 1}}))
        self.assertTrue(a11y_matrix.reflow_trace_problems({"reflow_stops": {"split": 1}}, "normal", lines))
        self.assertEqual(a11y_matrix.reflow_trace_problems(
            {"reflow_stops": {"split": 1}}, "normal", ["split-move open=1 from=0 to=1 pane=590 duration=3000",
                                                        "split-settle open=1 animated=1 motion=0 stopped=1 t=900"]), [])
        self.assertEqual(a11y_matrix.reflow_trace_problems({"name": "plain"}, "normal", lines), [])
        self.assertEqual(a11y_matrix.reflow_trace_problems({"reflow_trace": {"split": 1}}, "normal", lines), [])
        self.assertTrue(a11y_matrix.reflow_trace_problems({"reflow_trace": {"split": 1}}, "no-animations", lines))
        self.assertTrue(a11y_matrix.reflow_trace_problems({"reflow_trace": {"split": 1}}, "app-reduced", lines))

    def test_scenarios_cover_every_reflow_with_and_without_motion(self):
        self.assertEqual(set(journey.SCENARIOS), {
            "rivals-split", "suggestions-columns", "statistics-columns", "shop-grid", "rivals-split-reduced",
            "suggestions-reduced", "statistics-reduced", "statistics-setting-reduced", "shop-grid-reduced"})
        for name, scenario in journey.SCENARIOS.items():
            reduced = "--reduce-motion" in scenario.args or scenario.settings.get("reduceMotion") is True
            self.assertEqual(reduced, name.endswith("-reduced"), name)
            self.assertTrue(scenario.phases[0].label == "ready", name)
        setting = journey.SCENARIOS["statistics-setting-reduced"]
        self.assertEqual(setting.args, ())
        self.assertEqual(setting.settings, {"reduceMotion": True})

    def test_statistics_reduced_requires_unmoved_card_grid(self):
        # Issue #669 review: Profile/Statistics under Reduce Motion reports both column changes with nothing moved.
        for name in ("statistics-reduced", "statistics-setting-reduced"):
            narrow = journey.SCENARIOS[name].phases[1].check
            self.assertEqual(narrow(t.parse(["reflow-move host=card-grid moved=0 entered=0 motion=0 t=1"])), [], name)
            self.assertTrue(narrow(t.parse(["reflow-move host=card-grid moved=2 entered=0 motion=1 t=1"])), name)
            self.assertTrue(narrow(t.parse(["reflow-move host=card-grid moved=0 entered=1 motion=0 t=1"])), name)
            self.assertTrue(narrow([]), name)

    def test_settings_seed_is_written_before_launch(self):
        import tempfile
        original = journey.WORK
        journey.WORK = Path(tempfile.mkdtemp())
        try:
            args = journey.launch_args("statistics-setting-reduced", 8765, Path("app.exe"))
            seeded = journey.WORK / "statistics-setting-reduced" / "settings.json"
            self.assertEqual(json.loads(seeded.read_text(encoding="utf-8")), {"reduceMotion": True})
            self.assertIn(f"--arg=--settings-path={seeded}", args)
            self.assertNotIn("--arg=--reduce-motion", args)
            journey.launch_args("statistics-columns", 8765, Path("app.exe"))
            self.assertFalse((journey.WORK / "statistics-columns" / "settings.json").exists())
        finally:
            journey.WORK = original

    def test_column_check_composes_restagger(self):
        check = journey.columns("shop-grid", reduced=False)
        self.assertEqual(check(t.parse(["reflow-move host=shop-grid moved=1 entered=0 motion=1 t=1"])), [])
        self.assertTrue(check(t.parse(["reflow-move host=shop-grid moved=1 entered=0 motion=1 t=1", "fade-arm x=1"])))
        reduced = journey.columns("shop-grid", reduced=True)
        self.assertEqual(reduced(t.parse(["reflow-move host=shop-grid moved=0 entered=0 motion=0 t=1"])), [])


if __name__ == "__main__":
    unittest.main()
