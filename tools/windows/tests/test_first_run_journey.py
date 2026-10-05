"""First Run journey tooling: ``first_run_journey.py`` patterns, seen-state checks and contract coverage.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
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
        rotating = {"rotation", "rotation-reduced", "rotation-background"}
        self.assertTrue(all(s.fixture == ("--large-catalogue",) for s in j.SCENARIOS if s.name in rotating))
        self.assertTrue(all(s.fixture == () for s in j.SCENARIOS if s is not late and s.name not in rotating))

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

    def test_states_covered(self):
        product = json.loads((REPO / "contracts" / "product.json").read_text(encoding="utf-8"))
        states = next(c["states"] for c in product["controls"] if c["id"] == "first-run")
        covered = " ".join(s.state for s in j.SCENARIOS)
        self.assertEqual([s for s in states if s not in covered], [])
        self.assertEqual(len({s.name for s in j.SCENARIOS}), len(j.SCENARIOS))


if __name__ == "__main__":
    unittest.main()
