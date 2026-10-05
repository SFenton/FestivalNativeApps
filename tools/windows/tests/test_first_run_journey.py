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
    'Window "Songs" id=fst.first-run.dialog class=Popup rect=573,1,2694,2012',
    '  Unknown(flip view) "Songs" id=fst.first-run.slides class=FlipView rect=1260,335,1320,1110 patterns=Scroll',
    '    ListItem "Song List" id= class=FlipViewItem rect=1260,335,1320,1110 [focused,focusable,selected] patterns=SelectionItem',
    '  Menu "Pager" id=fst.first-run.pips class=Microsoft.UI.Xaml.Controls.PipsPager rect=1830,1481,180,72',
    '      Button "Page 5" id= class=Button rect=1974,1481,36,72 [focusable] patterns=Invoke',
    '      Button "Page 6" id= class=Button rect=0,0,0,0 [offscreen,focusable] patterns=Invoke',
    '  Button "Next" id=PrimaryButton class=Button rect=1260,1700,424,95 [focusable] patterns=Invoke',
    '  Button "Back" id=SecondaryButton class=Button rect=1708,1700,423,95 [disabled] patterns=Invoke',
    '  Button "Close" id=CloseButton class=Button rect=2155,1700,424,95 [focusable] patterns=Invoke',
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
        self.assertIn("assertstatus:id=fst.first-run.demo.songs-song-list|placeholder", steps)
        self.assertIn(f"assertstatus:id=fst.first-run.demo.songs-song-list|catalogue@{j.SONGS_DELAY + 20}", steps)
        self.assertEqual(j._demo("songs-sort", "catalogue", 5), "assertstatus:id=fst.first-run.demo.songs-sort|catalogue@5")
        self.assertTrue(all(s.fixture == () for s in j.SCENARIOS if s is not late))

    def test_states_covered(self):
        product = json.loads((REPO / "contracts" / "product.json").read_text(encoding="utf-8"))
        states = next(c["states"] for c in product["controls"] if c["id"] == "first-run")
        covered = " ".join(s.state for s in j.SCENARIOS)
        self.assertEqual([s for s in states if s not in covered], [])
        self.assertEqual(len({s.name for s in j.SCENARIOS}), len(j.SCENARIOS))


if __name__ == "__main__":
    unittest.main()
