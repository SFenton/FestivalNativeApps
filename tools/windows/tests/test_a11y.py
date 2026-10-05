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

    def test_page_steps_stem_placeholder(self):
        page = {"name": "settings", "after_ready": ["scrollinto:id=c", "shot:{stem}-footer.png"]}
        steps = m.page_steps(page, "wide", Path("/out"), "-text-200", scan=False, tabs=0)
        self.assertIn(f"shot:{Path('/out') / 'settings-wide-text-200'}-footer.png", steps)
        self.assertFalse(any("{stem}" in s for s in steps))

    def test_page_steps_repo_placeholder(self):
        page = {"name": "feedback", "after_ready": ['setvalue:id=1148&class=Edit|"{repo}\\a.png"']}
        steps = m.page_steps(page, "wide", Path("/out"), "", scan=False, tabs=0)
        self.assertIn(f'setvalue:id=1148&class=Edit|"{m.REPO_ROOT}\\a.png"', steps)

    def test_page_env(self):
        anon = m.page_env({"name": "lab", "route": "/songs", "env": {"FST_DEBUG_CONTROL_LAB": "instrument-selector"}},
                          Path("/data"))
        self.assertEqual(anon["FST_DEBUG_ANONYMOUS"], "1")
        self.assertEqual(anon["FST_DEBUG_CONTROL_LAB"], "instrument-selector")
        self.assertEqual(anon["FST_DEBUG_DATA_DIR"], str(Path("/data")))
        player = m.page_env({"name": "p", "tab": "songs", "profile": "id:Name"}, Path("/d"))
        self.assertEqual(player["FST_DEBUG_PROFILE"], "id:Name")
        self.assertNotIn("FST_DEBUG_ANONYMOUS", player)
        self.assertNotIn("FST_DEBUG_CONTROL_LAB", player)

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
        self.assertEqual(m.MODES["text-200"]["system"], {"text_scale": 200})
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

    def test_launch_args_and_live_pages(self):
        page = {"name": "shop", "first_run": "on"}
        fixture = m.launch_args(8765, page, Path("/s.json"))
        self.assertEqual(fixture[:2], ["--base-url", "http://127.0.0.1:8765/"])
        self.assertIn("--first-run=on", fixture)
        live = m.launch_args(None, {"name": "shop"}, Path("/s.json"))
        self.assertFalse(any(a.startswith("--base-url") or "127.0.0.1" in a for a in live))
        self.assertIn("--first-run=off", live)
        pages = [{"name": "shop"}, {"name": "shop-empty", "fixture": ["shop_fixture.py", "--shop", "empty"]},
                 {"name": "songs-selected", "profile": "fixture-player-1:Demo Player"},
                 {"name": "real", "profile": "abc:Real Player"}]
        self.assertEqual([p["name"] for p in m.live_pages(pages)], ["shop", "real"])
        scrolled = m.launch_args(None, {"name": "s", "args": ["--auto-scroll-span", "500"]}, Path("/s.json"))
        self.assertEqual(scrolled[-2:], ["--auto-scroll-span", "500"])

    def test_songs_scroll_pages(self):
        import json
        pages = {p["name"]: p for p in json.loads((m.PAGES.parent / "songs-scroll.json").read_text(encoding="utf-8"))}
        # Issue #245 (#45 on Windows): wheel, UIA-pattern and auto-scroll ping-pong round trips near the top, fixture
        # (large catalogue) and live variants; each fixture page ends back at the top with "#" pinned.
        for name in ("songs-scroll", "songs-scroll-uia"):
            self.assertEqual(pages[name]["fixture"], ["--large-catalogue"])
            self.assertEqual(pages[name]["after_ready"][-3], "assertname:id=fst.songs.section-header|#")
        self.assertEqual(sorted(p["name"] for p in m.live_pages(list(pages.values()))),
                         ["songs-pingpong-frames-live", "songs-pingpong-live", "songs-scroll-live",
                          "songs-scroll-resize-live", "songs-scroll-uia-live"])
        resize = pages["songs-scroll-resize-live"]["after_ready"]
        self.assertEqual([s for s in resize if s.startswith("resize:")],
                         ["resize:compact", "resize:wide", "resize:maximized", "resize:snap-left", "resize:medium"])
        self.assertEqual(resize[-2], "assertname:id=fst.songs.section-header|#")
        self.assertIn("--auto-scroll-span", pages["songs-pingpong"]["args"])
        for page in pages.values():
            for step in m.page_steps(page, "medium", Path("out"), "", scan=False, tabs=0):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step)

    def test_pane_corner_pages(self):
        import json
        pages = {p["name"]: p for p in json.loads((m.PAGES.parent / "a11y-pane-corners.json").read_text(encoding="utf-8"))}
        # Issue #255 (#55 on Windows): every pane state whose corners meet the window's (closed/rail, light-dismiss
        # overlay, inline expanded, collapsed to the rail), all anonymous so live evidence runs keep every page.
        self.assertEqual(sorted(pages), ["pane-closed", "pane-collapsed", "pane-inline", "pane-overlay"])
        self.assertEqual(m.live_pages(list(pages.values())), list(pages.values()))
        overlay = pages["pane-overlay"]
        self.assertEqual(overlay["after_ready"][:2], ["invoke:id=PART_PaneToggleButton", "waitfor:id=LightDismiss@5"])
        self.assertEqual(overlay["teardown"][-1], "waitgone:id=LightDismiss@5")
        self.assertIn("waitgone:id=LightDismiss@2", pages["pane-collapsed"]["after_ready"])
        for page in pages.values():
            for size in page.get("sizes", []):
                self.assertIn(size, u.PRESETS, page["name"])
            for step in m.page_steps(page, "compact", Path("out"), "", scan=True, tabs=4):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step)

    def test_page_fixtures_exist(self):
        import json
        for name in ("a11y.json", "a11y-keyboard.json"):
            for page in json.loads((m.PAGES.parent / name).read_text(encoding="utf-8")):
                if "fixture" in page:
                    script, _ = m.page_fixture(page)
                    self.assertTrue(script.is_file(), page["name"])

    def test_page_steps_parse(self):
        import json
        for name in ("a11y.json", "a11y-keyboard.json"):
            for page in json.loads((m.PAGES.parent / name).read_text(encoding="utf-8")):
                for step in m.page_steps(page, "medium", Path("out"), "", scan=True, tabs=4):
                    with self.subTest(file=name, page=page["name"], step=step):
                        u.parse_step(step)

    def test_first_run_later_states(self):
        import json
        pages = {p["name"]: p for p in json.loads(m.PAGES.read_text(encoding="utf-8"))}
        self.assertIn("assertstate:id=SecondaryButton|enabled=true", pages["first-run-back"]["after_ready"])
        done = pages["first-run-done"]["after_ready"]
        self.assertEqual(done.count("invoke:id=PrimaryButton"), 5)
        self.assertIn("assertstate:id=PrimaryButton|name=Done", done)
        self.assertEqual(m.live_pages([pages["first-run-back"], pages["first-run-done"]]),
                         [pages["first-run-back"], pages["first-run-done"]])

    def test_search_state_pages(self):
        import json
        from tools.windows import uiwin as u
        pages = json.loads((m.PAGES.parent / "a11y-search.json").read_text(encoding="utf-8"))
        names = {page["name"] for page in pages}
        # Every reachable Global Search state (issue #234): closed, open-hint, loading, results-all/-scoped, empty,
        # error, bands-unavailable and navigated, plus the title-bar suggestion popup.
        self.assertLessEqual({"search-closed", "search-suggestions", "search-open-hint", "search-loading",
                              "search-results-all", "search-results-songs", "search-results-players", "search-empty",
                              "search-error", "search-bands-unavailable", "search-navigated"}, names)
        for page in pages:
            for size in page.get("sizes", []):
                self.assertIn(size, u.PRESETS, page["name"])
            for step in [*page.get("ready", []), *page.get("after_ready", []), *page.get("teardown", [])]:
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step.replace("{stem}", "out"))

    def test_page_fixture(self):
        self.assertEqual(m.page_fixture({"name": "shop"}), (m.FIXTURE, ()))
        self.assertEqual(m.page_fixture({"fixture": ["--band-rankings", "empty"]}),
                         (m.FIXTURE, ("--band-rankings", "empty")))
        self.assertEqual(m.page_fixture({"fixture": ["shop_fixture.py", "--shop", "empty"]}),
                         (m.REPO_ROOT / "tools" / "windows" / "shop_fixture.py", ("--shop", "empty")))

    def test_mode_spec_combines(self):
        self.assertEqual(m.mode_spec("normal"), {})
        self.assertEqual(m.mode_spec("hc-desert"), {"system": {"high_contrast": "desert"}})
        self.assertEqual(m.mode_spec("hc-desert+scale-150"),
                         {"system": {"high_contrast": "desert", "display_scale": 150}})
        self.assertEqual(m.mode_spec("text-200+app-contrast")["app"], {"moreContrast": True, "lessTransparency": True})
        self.assertEqual(m.mode_spec("scale-100+scale-150"), {"system": {"display_scale": 150}})
        with self.assertRaises(ValueError):
            m.mode_spec("hc-desert+bogus")

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
