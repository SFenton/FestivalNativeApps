"""First Run journey tooling: ``first_run_journey.py`` patterns, seen-state checks and contract coverage.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import re
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import first_run_journey as j  # noqa: E402  (sibling module)

REPO = Path(__file__).resolve().parents[3]

# Lines from a real `uiwin.py tree` dump of the Songs carousel (2026-10-04).
TREE = "\n".join([
    '    Button "Close" id=Close class= rect=3123,0,144,144 patterns=Invoke',
    'Window "Songs" id=fst.first-run.dialog class=Popup rect=573,1,2694,2012',
    '  Unknown(flip view) "Songs" id=fst.first-run.slides class=FlipView rect=1260,335,1320,1110 patterns=Scroll',
    '    ListItem "Song List" id= class=FlipViewItem rect=1260,335,1320,1110 [focused,focusable,selected] patterns=SelectionItem',
    '  Menu "Pager" id=fst.first-run.pips class=Microsoft.UI.Xaml.Controls.PipsPager rect=1830,1481,180,72',
    '      Button "Page 5" id= class=Button rect=1974,1481,36,72 [focusable] patterns=Invoke',
    '      Button "Page 6" id= class=Button rect=0,0,0,0 [offscreen,focusable] patterns=Invoke',
    '  Button "Next" id=PrimaryButton class=Button rect=1260,1700,424,95 [focusable] patterns=Invoke',
    '  Button "Back" id=SecondaryButton class=Button rect=1708,1700,423,95 [disabled] patterns=Invoke',
    '  Button "Close" id=fst.first-run.close class=Button rect=2155,1700,424,95 [focusable] patterns=Invoke',
])


class PatternTests(unittest.TestCase):
    """Tree patterns match the driver's line format."""

    def test_dialog_pips_and_slide(self):
        phase = j.Phase([], expect=[j._dialog("Songs"), *j._pips(6), j._slide("Song List")], forbid=[j._no_pip(7)])
        self.assertEqual(j.check_tree(TREE, phase), [])
        self.assertTrue(j.check_tree(TREE, j.Phase([], expect=[j._dialog("Leaderboards")])))
        self.assertTrue(j.check_tree(TREE, j.Phase([], forbid=[j._no_pip(6)])))

    def test_button_enabled_state(self):
        ok = j.Phase([], expect=[j._button("PrimaryButton", "Next"), j._button("SecondaryButton", "Back", enabled=False)])
        self.assertEqual(j.check_tree(TREE, ok), [])
        self.assertTrue(j.check_tree(TREE, j.Phase([], expect=[j._button("SecondaryButton", "Back")])))
        self.assertTrue(j.check_tree(TREE, j.Phase([], expect=[j._button("PrimaryButton", "Done")])))

    def test_single_slide_forbids_paging(self):
        self.assertEqual(len(j.check_tree(TREE, j.Phase([], forbid=j.NO_PAGING))), 3)
        # The title bar's Close is not a dialog command; an untagged dialog Close still is.
        title_bar = TREE.splitlines()[0]
        self.assertEqual(j.check_tree(title_bar, j.Phase([], forbid=j.NO_PAGING)), [])
        untagged = '  Button "Close" id=CloseButton class=Button rect=2155,1700,424,95 [focusable] patterns=Invoke'
        self.assertEqual(len(j.check_tree(untagged, j.Phase([], forbid=j.NO_PAGING))), 1)


class SeenTests(unittest.TestCase):
    """Seen-state predicates and the version-bump rewrite."""

    def test_missing_file_is_empty_and_predicates_report(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "first-run.json"
            self.assertEqual(j.load_seen(path), {})
            self.assertEqual(j.check_seen(path, j.Phase([], seen={"empty": lambda s: not s})), [])
            path.write_text(json.dumps({"songs-song-list": {"version": 2, "hash": "1", "seenAt": "x"}}), encoding="utf-8")
            failures = j.check_seen(path, j.Phase([], seen={"two": lambda s: len(s) == 2, "key": lambda s: s["nope"]}))
            self.assertEqual(len(failures), 2)
            path.write_text("{", encoding="utf-8")
            self.assertIn("unreadable", j.check_seen(path, j.Phase([], seen={"any": lambda s: True}))[0])

    def test_older_rewrites_one_version(self):
        seen = {"a": {"version": 3}, "b": {"version": 2}}
        self.assertEqual(j._older("a")(seen), {"a": {"version": 0}, "b": {"version": 2}})


class ContractTests(unittest.TestCase):
    """Every reachable `first-run` contract state has a scenario."""

    def test_title_phases_cover_every_page(self):
        catalog = (REPO / "windows" / "Festival.Core" / "Domain" / "FirstRunCatalog.cs").read_text(encoding="utf-8")
        self.assertEqual(len(j.PAGE_TITLES), 9)
        self.assertTrue(all(f'"{key}-' in catalog for key in j.PAGE_TITLES))
        phases = j._title_phases()
        self.assertEqual(len(phases), 2 * len(j.PAGE_TITLES))
        for (key, title), opened, closed in zip(j.PAGE_TITLES.items(), phases[::2], phases[1::2]):
            self.assertIn(f"invoke:id=fst.settings.first-run.{key}", opened.steps)
            self.assertIn(j._dialog(title), opened.expect)
            self.assertEqual(closed.forbid, [j.DIALOG])
        self.assertEqual(j.check_tree(TREE, phases[0]), [])
        self.assertTrue(j.check_tree(TREE, phases[2]))

    def test_late_catalogue_asserts_placeholder_then_catalogue(self):
        late = next(s for s in j.SCENARIOS if s.name == "late-catalogue")
        self.assertEqual(late.fixture, ("--songs-delay", str(j.SONGS_DELAY)))
        steps = [step for phase in late.phases for step in phase.steps]
        self.assertIn("assertstatus:id=fst.first-run.demo.songs-song-list|~^placeholder( |$)", steps)
        self.assertIn(f"assertstatus:id=fst.first-run.demo.songs-song-list|~^catalogue( |$)@{j.SONGS_DELAY + 20}", steps)
        self.assertEqual(j._demo("songs-sort", "catalogue", 5), "assertstatus:id=fst.first-run.demo.songs-sort|~^catalogue( |$)@5")
        large = {"rotation", "rotation-reduced", "rotation-background", "top-songs-rotation"}
        self.assertTrue(all(s.fixture == ("--large-catalogue",) for s in j.SCENARIOS if s.name in large))
        others = [s for s in j.SCENARIOS if s is not late and s.name not in large | {"catalogue-unavailable"}]
        self.assertTrue(all(s.fixture == () for s in others))

    def test_rotation_scenarios_cover_running_paused_hidden_and_instant(self):
        rotation = next(s for s in j.SCENARIOS if s.name == "rotation")
        steps = "\n".join(step for phase in rotation.phases for step in phase.steps)
        for token in ("rotation=running", "rotation=not-visible", "swap=fade", "resize:minimized", "resize:restored"):
            self.assertIn(token, steps)
        # Paging away and back within one phase leaves the first tick's single swap unchanged (paused while unselected).
        first = rotation.phases[0].steps
        back = first.index("invoke:id=SecondaryButton")
        self.assertIn("invoke:id=PrimaryButton", first[:back])
        self.assertEqual(first[back + 1], j._rotation("songs-song-list", j.FIRST_TICK_FADE))
        self.assertRegex("catalogue rotation=running swaps=1 swap=fade", j.FIRST_TICK_FADE)
        self.assertNotRegex("catalogue rotation=running swaps=3 swap=fade", j.FIRST_TICK_FADE)
        reduced = next(s for s in j.SCENARIOS if s.name == "rotation-reduced")
        self.assertTrue(reduced.settings["reduceMotion"])
        self.assertIn("swap=instant", reduced.phases[0].steps[1])
        status = "catalogue rotation=running swaps=3 swap=fade"
        self.assertRegex(status, j.SWAPPED_FADE)
        self.assertNotRegex("catalogue rotation=running swaps=0 swap=none", j.SWAPPED_FADE)
        self.assertNotRegex(status, j.SWAPPED_INSTANT)
        # Rotation steps never contain the step separator.
        self.assertNotIn(";", steps)

    def test_rotation_background_holds_while_inactive_and_resumes(self):
        # Issue #258: a visible but deactivated window holds the swap count, and reactivation resumes it.
        scenario = next(s for s in j.SCENARIOS if s.name == "rotation-background")
        steps = scenario.phases[0].steps
        off, on = steps.index("foreground:off"), steps.index("foreground:on")
        self.assertLess(off, on)
        self.assertEqual(steps[off - 1], j._rotation("songs-song-list", j.FIRST_TICK_FADE, j.SWAP_WAIT))
        held = j._rotation("songs-song-list", j.FIRST_TICK_BACKGROUND)
        self.assertEqual(steps[off + 1:on], [held, "wait:12", held])
        self.assertEqual(steps[on + 1], j._rotation("songs-song-list", j.RESUMED_FADE, j.SWAP_WAIT))
        self.assertRegex("catalogue rotation=background swaps=1 swap=fade", j.FIRST_TICK_BACKGROUND)
        self.assertNotRegex("catalogue rotation=running swaps=1 swap=fade", j.FIRST_TICK_BACKGROUND)
        self.assertNotRegex("catalogue rotation=background swaps=3 swap=fade", j.FIRST_TICK_BACKGROUND)
        for resumed in ("catalogue rotation=running swaps=2 swap=fade", "catalogue rotation=running swaps=12 swap=fade"):
            self.assertRegex(resumed, j.RESUMED_FADE)
        self.assertNotRegex("catalogue rotation=running swaps=1 swap=fade", j.RESUMED_FADE)
        self.assertNotRegex("catalogue rotation=background swaps=2 swap=fade", j.RESUMED_FADE)
        for step in steps:
            j.uiwin.parse_step(step)

    def test_top_songs_rotation_asserts_pinned_pills_after_real_swaps(self):
        import uiwin
        rotation = next(s for s in j.SCENARIOS if s.name == "top-songs-rotation")
        self.assertEqual(rotation.fixture, ("--large-catalogue",))
        opened, rotated = rotation.phases
        self.assertEqual(opened.steps.count("invoke:id=PrimaryButton"), 5)
        self.assertEqual(j.TOP_SONG_PILLS, ["Top 1.2%", "Top 3.5%", "Top 7.8%", "Top 14.2%"])
        self.assertFalse(any(s.startswith("assertstatus:raw=") for s in opened.steps))
        for slot, pill in enumerate(j.TOP_SONG_PILLS):
            selector = f"raw=fst.first-run.demo.statistics-top-songs.pill.{slot}"
            self.assertIn(f"assertname:{selector}|{pill}", opened.steps)
            # After the slot's own swap (sticky status, so lock delays can't skip past it), its pill is unchanged.
            status = rotated.steps.index(f"assertstatus:{selector}|rotated@{5 * j.TOP_SONG_TICKS + 20}")
            self.assertEqual(rotated.steps[status + 1], f"assertname:{selector}|{pill}")
        for step in opened.steps + rotated.steps:
            uiwin.parse_step(step)

    def test_page_slides_match_the_catalogue(self):
        catalog = (REPO / "windows" / "Festival.Core" / "Domain" / "FirstRunCatalog.cs").read_text(encoding="utf-8")
        ids = re.findall(r'new\("([a-z]+-[a-z-]+)", \d+,', catalog)
        self.assertEqual(len(ids), 42)
        self.assertEqual(list(j.PAGE_SLIDES), list(j.PAGE_TITLES))
        for key, slides in j.PAGE_SLIDES.items():
            self.assertEqual(slides, [i for i in ids if i.split("-")[0] == key], key)

    def test_demo_phases_assert_every_slide(self):
        demo = next(s for s in j.SCENARIOS if s.name == "demo-songs")
        steps = [step for phase in demo.phases for step in phase.steps]
        for slides in j.PAGE_SLIDES.values():
            for slide in slides:
                self.assertIn(j._demo(slide, "catalogue", 15), steps)
        self.assertEqual(len(demo.phases), 2 * len(j.PAGE_SLIDES))
        top = demo.phases[2 * list(j.PAGE_SLIDES).index("statistics")]
        self.assertEqual(top.steps.count("invoke:id=PrimaryButton"), 5)
        self.assertIn(j._dialog("Statistics"), top.expect)
        down = next(s for s in j.SCENARIOS if s.name == "catalogue-unavailable")
        self.assertEqual(down.fixture, ("--songs-unavailable",))
        down_steps = [step for phase in down.phases for step in phase.steps]
        self.assertIn(j._demo("statistics-top-songs", "placeholder", 15), down_steps)
        self.assertIn(j._demo("suggestions-category-card", "placeholder", 15), down_steps)
        self.assertIn(j._demo("rivals-detail", "placeholder", 15), down_steps)
        self.assertFalse(any("catalogue" in step.partition("|")[2] for step in down_steps))
        self.assertIn(f"wait:{1 + j.UNAVAILABLE_WAIT}", down_steps)

    def test_control_census_covers_every_slide_with_its_production_controls(self):
        # Issue #380: every demo must name the production controls it shows; the census regex needs each one whole.
        import uiwin
        self.assertEqual(sorted(j.DEMO_CONTROLS), sorted(s for slides in j.PAGE_SLIDES.values() for s in slides))
        self.assertIn("SongScoreHistoryChart", j.DEMO_CONTROLS["songinfo-chart"])
        scenario = next(s for s in j.SCENARIOS if s.name == "demo-controls")
        steps = [step for phase in scenario.phases for step in phase.steps]
        for slide in j.DEMO_CONTROLS:
            self.assertIn(j._controls(slide), steps)
        for step in steps:
            uiwin.parse_step(step)
        pattern = uiwin.parse_step(j._controls("songs-sort"))["value"][1:]
        self.assertTrue(re.search(pattern, "controls=Button+DropDownButton+RadioButton+RadioButtons+SongSortForm"))
        # The old replica's slide had no RadioButtons, and a hand-built copy of the flyout has no SongSortForm;
        # RadioButton alone or a longer name must not pass.
        self.assertFalse(re.search(pattern, "controls=DropDownButton+RadioButton+RadioButtons"))
        self.assertFalse(re.search(pattern, "controls=DropDownButton+RadioButton+SongSortForm"))
        self.assertFalse(re.search(pattern, "controls=DropDownButton+RadioButtonsX+SongSortForm"))
        self.assertFalse(re.search(pattern, ""))

    def test_chart_and_scroll_scenarios_assert_the_real_chart_and_scroll_token(self):
        import uiwin
        chart = "\n".join(step for phase in next(s for s in j.SCENARIOS if s.name == "demo-chart").phases
                          for step in phase.steps)
        for token in ("fst.history.chart", "3 of 3 scores", "fst.history.bar.2|toggle=on", "fst.history.bar.0|toggle=on",
                      "fst.history.detail"):
            self.assertIn(token, chart)
        scroll = next(s for s in j.SCENARIOS if s.name == "infinite-scroll")
        held = next(s for s in j.SCENARIOS if s.name == "infinite-scroll-reduced")
        self.assertEqual(held.settings, {"reduceMotion": True})
        steps = "\n".join(scroll.phases[0].steps)
        self.assertIn(r"fade=top\+bottom", steps)
        self.assertIn("wraps=[1-9]", steps)
        self.assertIn(r"scroll=held pos=top wraps=0 fade=bottom$", "\n".join(held.phases[0].steps))
        for scenario in (scroll, held):
            for step in scenario.phases[0].steps:
                uiwin.parse_step(step)
        status = "catalogue scroll=running pos=mid wraps=2 fade=top+bottom"
        self.assertTrue(re.search(r"^catalogue scroll=running pos=(top|mid) wraps=[1-9]\d* fade=(bottom|top\+bottom)$",
                                  status))

    def test_live_demo_pages_parse_and_assert_catalogue_songs(self):
        import a11y_matrix
        import uiwin
        pages = json.loads((REPO / "tools" / "windows" / "journeys" / "first-run-demos.json").read_text(encoding="utf-8"))
        self.assertEqual(a11y_matrix.live_pages(pages), pages)
        for page in pages:
            steps = a11y_matrix.page_steps(page, "medium", Path("out"), "", True, 12)
            for step in steps:
                uiwin.parse_step(step)
            self.assertTrue(any(s.startswith("assertstatus:id=fst.first-run.demo.") and re.match(r"~?\^?catalogue", s.partition("|")[2])
                                for s in steps), page["name"])

    def test_rotating_demo_statuses_are_prefix_matches(self):
        # Issue #258: a rotating demo's ItemStatus appends its rotation state, so an exact status would never match.
        demos = (REPO / "windows" / "Festival.Core" / "Domain" / "FirstRunDemos.cs").read_text(encoding="utf-8")
        block = demos[demos.index("RotatingKinds = new"):]
        rotating = set(re.findall(r'\["([a-z-]+)"\] = FirstRunDemoRotationKind\.', block[:block.index("};")]))
        self.assertEqual(len(rotating), 12)
        journeys = REPO / "tools" / "windows" / "journeys"
        steps = [step for scenario in j.SCENARIOS for phase in scenario.phases for step in phase.steps]
        for name in ("first-run-demos.json", "a11y-first-run-rotation.json"):
            for page in json.loads((journeys / name).read_text(encoding="utf-8")):
                steps += page.get("ready", []) + page.get("after_ready", [])
        for step in steps:
            found = re.match(r"assertstatus:id=fst\.first-run\.demo\.([a-z-]+)\|(.*)", step)
            if found and found.group(1) in rotating:
                self.assertTrue(found.group(2).startswith("~"), step)

    def test_states_covered(self):
        product = json.loads((REPO / "contracts" / "product.json").read_text(encoding="utf-8"))
        states = next(c["states"] for c in product["controls"] if c["id"] == "first-run")
        covered = " ".join(s.state for s in j.SCENARIOS)
        self.assertEqual([s for s in states if s not in covered], [])
        self.assertEqual(len({s.name for s in j.SCENARIOS}), len(j.SCENARIOS))


if __name__ == "__main__":
    unittest.main()
