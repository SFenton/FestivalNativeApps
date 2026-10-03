"""Accessibility tooling: ``uiwin.py`` a11y steps/scan summaries and ``a11y_matrix.py`` pure logic.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

from tools.windows import uiwin as u

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import a11y_matrix as m  # noqa: E402  (imports uiwin as a sibling module)


class A11yStepTests(unittest.TestCase):
    """``tabwalk``, ``assertfocus`` and ``scan`` drive steps."""

    def test_tabwalk(self):
        self.assertEqual(u.parse_step("tabwalk:12")["count"], 12)
        step = u.parse_step("tabwalk:5,shift")
        self.assertEqual((step["count"], step["reverse"]), (5, True))
        self.assertFalse(u.parse_step("tabwalk:3")["reverse"])
        for bad in ("tabwalk:x", "tabwalk:3,alt"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_assertfocus_and_scan(self):
        step = u.parse_step("assertfocus:id=fst.songs.sort@3")
        self.assertEqual((step["selector"]["value"], step["timeout"]), ("fst.songs.sort", 3.0))
        with self.assertRaises(ValueError):
            u.parse_step("assertfocus:10,10")
        scan = u.parse_step("scan:out/axe/songs-compact")
        self.assertTrue(Path(scan["arg"]).is_absolute())
        self.assertEqual(Path(scan["arg"]).name, "songs-compact")

    def test_setvalue(self):
        step = u.parse_step("setvalue:id=fst.songs.search|fix it ")
        self.assertEqual((step["selector"]["value"], step["text"]), ("fst.songs.search", "fix it "))
        self.assertEqual(u.parse_step("setvalue:id=fst.songs.search|")["text"], "")
        self.assertEqual(u.parse_step("setvalue:name=Search|a|b")["text"], "a|b")
        for bad in ("setvalue:id=fst.songs.search", "setvalue:10,10|x"):
            with self.assertRaises(ValueError):
                u.parse_step(bad)

    def test_waitgone(self):
        step = u.parse_step("waitgone:id=fst.songs.row.fixture-pulse@10")
        self.assertEqual((step["verb"], step["selector"]["value"], step["timeout"]), ("waitgone", "fst.songs.row.fixture-pulse", 10.0))
        with self.assertRaises(ValueError):
            u.parse_step("waitgone:10,10")

    def test_scrollinto(self):
        step = u.parse_step("scrollinto:id=fst.songs.filter.percentile@8")
        self.assertEqual((step["verb"], step["selector"]["value"], step["timeout"]), ("scrollinto", "fst.songs.filter.percentile", 8.0))
        with self.assertRaises(ValueError):
            u.parse_step("scrollinto:10,10")

    def test_summarize_scan(self):
        result = {"errors": 2, "findings": [
            {"rule": "NameNotEmpty", "element": {"ControlType": "Button", "Name": "", "AutomationId": "x", "ClassName": "Button"},
             "parents": ["Pane \"\" id= class=Grid"]},
            {"rule": "BoundingRectangleNotNull", "framework_issue": "https://example.test", "element": {}, "parents": []},
        ]}
        lines = u.summarize_scan(result)
        self.assertEqual(len(lines), 2)
        self.assertIn("[framework issue]", lines[0])
        self.assertTrue(lines[1].startswith("NameNotEmpty: Button"))
        self.assertEqual(u.summarize_scan({"errors": 0}), [])

    def test_parser_has_a11y_commands(self):
        parser = u.build_parser()
        self.assertEqual(parser.parse_args(["scan", "out", "--scan-id", "x"]).scan_id, "x")
        args = parser.parse_args(["focus-order", "--count", "7", "--reverse"])
        self.assertEqual((args.count, args.reverse), (7, True))


class MatrixTests(unittest.TestCase):
    """``a11y_matrix.py`` step building and summaries."""

    def test_page_steps(self):
        page = {"name": "songs", "ready": ["waitfor:id=a@5"], "after_ready": ["invoke:id=b"], "teardown": ["key:esc"]}
        steps = m.page_steps(page, "compact", Path("/out"), "-hc-desert", scan=True, tabs=10)
        self.assertEqual(steps[0], "resize:compact")
        self.assertLess(steps.index("waitfor:id=a@5"), steps.index("invoke:id=b"))
        self.assertTrue(any(s.startswith("shot:") and s.endswith("songs-compact-hc-desert.png") for s in steps))
        self.assertTrue(any(s.startswith("scan:") for s in steps))
        self.assertIn("tabwalk:10", steps)
        self.assertEqual(steps[-1], "key:esc")
        quiet = m.page_steps({"name": "x", "tabs": 0}, "wide", Path("/o"), "", scan=False, tabs=30)
        self.assertFalse(any(s.startswith(("scan:", "tabwalk:")) for s in quiet))
        for step in steps:
            u.parse_step(step)

    def test_focus_summary_and_table(self):
        focus = [{"id": "a", "in_window": True}, {"id": "b", "in_window": True}, {"id": "a", "in_window": True, "repeat": True},
                 {"name": "Start", "in_window": False}]
        summary = m.summarize_focus(focus)
        self.assertEqual((summary["stops"], summary["outside"], summary["repeats"], summary["order"]), (2, 1, 1, ["a", "b"]))
        table = m.summary_table([{"page": "songs", "size": "compact", "mode": "normal", "ok": True, "axe_errors": 0, "focus": summary},
                                 {"page": "shop", "size": "wide", "mode": "normal", "ok": False, "error": "timeout"}])
        self.assertIn("| songs | compact | normal | yes | 0 | 2 | 1 | 1 |", table)
        self.assertIn("NO: timeout", table)

    def test_modes_and_restore(self):
        self.assertEqual(m.MODES["hc-desert"]["system"], {"high_contrast": "desert"})
        self.assertTrue(m.MODES["app-reduced"]["app"]["reduceMotion"])
        self.assertEqual(m.MODES["text-200"]["system"], {"text_scale": 200})
        previous = {"high_contrast": "off", "animations": True, "transparency": True, "text_scale": 100}
        self.assertEqual(m.restore_values(previous, {"text_scale": 225}), {"text_scale": 100})
        self.assertEqual(m.restore_values(previous, {}), {})
        self.assertEqual(m.MODES["light-theme"]["system"], {"light_theme": True})
        self.assertEqual(m.MODES["text-200"]["system"], {"text_scale": 200})
        self.assertEqual(m.MODES["scale-150"]["system"], {"display_scale": 150})
        light = {**previous, "light_theme": False}
        self.assertEqual(m.restore_values(light, m.MODES["light-theme"]["system"]), {"light_theme": False})

    def test_pending_restore(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "restore.json"
            self.assertEqual(m.pending_restore(path), {})
            path.write_text('{"high_contrast": "off"}', encoding="utf-8")
            self.assertEqual(m.pending_restore(path), {"high_contrast": "off"})
            path.write_text("[1]", encoding="utf-8")
            self.assertEqual(m.pending_restore(path), {})
            path.write_text("not json", encoding="utf-8")
            self.assertEqual(m.pending_restore(path), {})


if __name__ == "__main__":
    unittest.main()
