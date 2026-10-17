"""Unit tests for scroll_probe.py's suite loading and pass evaluation (no app or desktop needed)."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import scroll_probe as probe  # noqa: E402
import ui_journey  # noqa: E402
import uiwin  # noqa: E402

THRESHOLDS = {"max_reversals": 0, "max_stalls": 3, "max_p95_ms": 25, "max_handler_ms": 60, "max_gc2": 3}


def line(label: str, p95: float = 8.6, stalls: int = 0, reversals: int = 0, hidden: str = "0") -> str:
    return (f"12:00:00.000 scroll-probe {label} frames=227 p50=8.3 p95={p95} max=23.4 over33={stalls} moves=179 "
            f"median=9.77 reversals={reversals} worstBack=0.00 extentChanges=0 layouts=213 offset=1761.00 "
            f"hidden={hidden} fg=0")


def cost(label: str, ms: float) -> str:
    return f"scroll-probe cost {label} handlers={ms}ms ql-report=1.0ms/2/max0.5/1KB"


def gc(label: str, gen2: int) -> str:
    return f"scroll-probe gc {label} gc0=1 gc1=0 gc2={gen2}"


class SuiteTests(unittest.TestCase):
    """load_suite merges defaults, and the shipped suite covers every page and modal the issue names."""

    def test_merges_defaults_and_thresholds(self) -> None:
        suite = {"defaults": {"size": "medium", "profile": "p", "fixture": ["--large-catalogue"],
                              "thresholds": THRESHOLDS},
                 "pages": [{"name": "a", "tab": "songs"},
                           {"name": "b", "size": "compact", "target": "dialog", "open": ["click:id=x"],
                            "thresholds": {"max_p95_ms": 40}}]}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "suite.json"
            path.write_text(json.dumps(suite), encoding="utf-8")
            a, b = probe.load_suite(path)
        self.assertEqual((a["size"], a["target"], a["open"], a["fixture"]), ("medium", "page", [], ["--large-catalogue"]))
        self.assertEqual(a["thresholds"], THRESHOLDS)
        self.assertEqual((b["size"], b["target"]), ("compact", "dialog"))
        self.assertEqual(b["thresholds"]["max_p95_ms"], 40)
        self.assertEqual(b["thresholds"]["max_reversals"], 0)

    def test_shipped_suite_is_complete_and_runnable(self) -> None:
        pages = probe.load_suite()
        names = [p["name"] for p in pages]
        self.assertEqual(len(names), len(set(names)), "duplicate entry names")
        for required in ("songs", "song-detail", "song-board", "leaderboards", "rivals", "suggestions", "profile",
                         "statistics", "settings", "item-shop", "paths-modal", "notifications-sheet", "feedback-sheet",
                         "search"):
            self.assertIn(required, names)
        for page in pages:
            with self.subTest(page=page["name"]):
                self.assertIn(page["target"], ("page", "dialog"))
                self.assertIn(page["size"], ("compact", "medium", "wide"))
                self.assertTrue(page.get("tab") or page.get("route"), "entry needs a tab or route")
                self.assertEqual(set(page["thresholds"]) - {"drag"}, set(THRESHOLDS))
                self.assertLessEqual(set(page["thresholds"].get("drag", {})), set(THRESHOLDS) - {"max_gc2"})
                loosened = [key for key, limit in THRESHOLDS.items()
                            if max(page["thresholds"][key], page["thresholds"].get("drag", {}).get(key, 0)) > limit]
                if loosened:
                    self.assertRegex(page.get("known", ""), r"#\d+", f"loosened {loosened} needs a known issue")
                script, _ = ui_journey.journey_fixture(tuple(page["fixture"]))
                if script is not None:
                    self.assertTrue(script.exists(), script)
                for step in page["open"]:
                    uiwin.parse_step(step)
                if page["target"] == "dialog":
                    self.assertTrue(page["open"], "a modal entry must open its dialog")


class ParseTests(unittest.TestCase):
    """parse_passes attaches each cost and gc line to its pass."""

    def test_parses_pass_cost_and_gc(self) -> None:
        passes = probe.parse_passes([line("rest"), line("down", hidden="display-off"), cost("down", 18.2),
                                     gc("down", 1), "unrelated", line("drag-down"), cost("drag-down", 8.4)])
        self.assertEqual([p.label for p in passes], ["rest", "down", "drag-down"])
        down = passes[1]
        self.assertEqual((down.frames, down.p50, down.p95, down.max, down.offset), (227, 8.3, 8.6, 23.4, 1761.0))
        self.assertEqual((down.hidden, down.handler_ms, down.gc2), ("display-off", 18.2, 1))
        self.assertEqual(passes[2].handler_ms, 8.4)
        self.assertTrue(passes[0].line.startswith("scroll-probe rest"))

    def test_cost_for_another_pass_is_ignored(self) -> None:
        passes = probe.parse_passes([line("up"), cost("down", 99)])
        self.assertEqual(passes[0].handler_ms, 0.0)

    def test_older_line_without_hidden_reads_visible(self) -> None:
        passes = probe.parse_passes([line("up").replace(" hidden=0 fg=0", "")])
        self.assertEqual(passes[0].hidden, "0")


class EvaluateTests(unittest.TestCase):
    """evaluate enforces thresholds, separates throttled passes and keeps CI frame checks advisory."""

    def evaluate(self, lines: list[str], **kwargs) -> probe.Verdict:
        return probe.evaluate("page", probe.parse_passes(lines), THRESHOLDS, **kwargs)

    def test_clean_passes(self) -> None:
        verdict = self.evaluate([line("rest"), line("down"), cost("down", 10), line("drag-up"), cost("drag-up", 59)])
        self.assertEqual((verdict.failures, verdict.notes, verdict.hidden), ([], [], []))

    def test_no_moving_pass_fails(self) -> None:
        self.assertEqual(self.evaluate([line("rest")]).failures,
                         ["page: no probe passes (no scrollable content found)"])

    def test_threshold_failures(self) -> None:
        verdict = self.evaluate([line("down", p95=25.1, stalls=4, reversals=1), cost("down", 61)])
        self.assertEqual(len(verdict.failures), 1)
        failure = verdict.failures[0]
        for part in ("reversals 1 > 0", "handlers 61.0 ms > 60", "stalls 4 > 3", "p95 25.1 ms > 25"):
            self.assertIn(part, failure)

    def test_ci_frames_are_advisory_and_handlers_scaled(self) -> None:
        verdict = self.evaluate([line("drag-down", p95=40, stalls=9), cost("drag-down", 170)],
                                frames_enforced=False, handler_scale=3)
        self.assertEqual(verdict.failures, [])
        self.assertEqual(verdict.notes, ["page drag-down: stalls 9 > 3, p95 40.0 ms > 25 (advisory)"])
        verdict = self.evaluate([line("drag-down"), cost("drag-down", 181)], frames_enforced=False, handler_scale=3)
        self.assertIn("handlers 181.0 ms > 180", verdict.failures[0])

    def test_drag_limits_apply_only_to_drag_passes(self) -> None:
        thresholds = {**THRESHOLDS, "drag": {"max_p95_ms": 40, "max_stalls": 8}}
        lines = [line("down", p95=30), line("drag-down", p95=39, stalls=8), line("drag-up", p95=41)]
        verdict = probe.evaluate("page", probe.parse_passes(lines), thresholds)
        self.assertEqual(len(verdict.failures), 2)
        self.assertIn("page down: p95 30.0 ms > 25", verdict.failures[0])
        self.assertIn("page drag-up: p95 41.0 ms > 40", verdict.failures[1])

    def test_hidden_pass_is_reported(self) -> None:
        verdict = self.evaluate([line("rest", hidden="occluded"), line("down")])
        self.assertEqual(verdict.hidden, ["page: rest hidden=occluded"])

    def test_gen2_counts_after_the_first_moving_pass(self) -> None:
        lines = [line("down"), gc("down", 9), line("up"), gc("up", 2), line("drag-down"), gc("drag-down", 1)]
        self.assertEqual(self.evaluate(lines).failures, [])
        lines[-1] = gc("drag-down", 2)
        self.assertEqual(self.evaluate(lines).failures, ["page: 4 gen2 collections after the first pass > 3"])


class RelaunchTests(unittest.TestCase):
    """main relaunches a failing entry once and fails only when the failure reproduces."""

    def run_main(self, attempts: list[list[str]], *args: str) -> tuple[int, int, dict]:
        calls = iter(attempts)
        launches = []

        def fake_run_page(*_args) -> list[str]:
            launches.append(1)
            return next(calls)

        with tempfile.TemporaryDirectory() as out, \
                unittest.mock.patch.object(probe, "run_page", fake_run_page), \
                unittest.mock.patch.object(probe, "start_fixture", lambda *_: (unittest.mock.Mock(), 1)), \
                unittest.mock.patch("sys.stdout", new=__import__("io").StringIO()):
            code = probe.main(["--pages", "settings", "--out", out, *args])
            result = json.loads((Path(out) / "results.json").read_text(encoding="utf-8"))[0]
        return code, len(launches), result

    def test_unreproduced_failure_passes_with_a_note(self) -> None:
        code, launches, result = self.run_main([[line("down", p95=40)], [line("down")]])
        self.assertEqual((code, launches, result["failures"]), (0, 2, []))
        self.assertTrue(result["notes"][0].startswith("not reproduced on relaunch: settings down: p95 40.0 ms"))

    def test_reproduced_failure_fails(self) -> None:
        code, launches, result = self.run_main([[line("down", p95=40)], [line("down", p95=31)]])
        self.assertEqual((code, launches), (1, 2))
        self.assertIn("p95 31.0 ms > 25", result["failures"][0])

    def test_no_confirm_fails_on_the_first_launch(self) -> None:
        code, launches, _ = self.run_main([[line("down", p95=40)]], "--no-confirm")
        self.assertEqual((code, launches), (1, 1))

    def test_throttled_launch_reruns_then_reports_invalid(self) -> None:
        hidden = [line("down", hidden="display-off")]
        code, launches, result = self.run_main([hidden, hidden])
        self.assertEqual((code, launches, result["hidden"]), (2, 2, ["settings: down hidden=display-off"]))


if __name__ == "__main__":
    unittest.main()
