"""``suggestions_journey.py``: launch arguments and the desktop-lock retry rule (issue #205).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import suggestions_journey as j  # noqa: E402  (sibling module)


class LockBoundTests(unittest.TestCase):
    """Only a time-bounded state that expired behind the desktop lock is retried."""

    QUEUED = "uiwin drive failed:\nwaiting for host lock 'desktop' (holder: x) ...\nerror: no on-screen element"

    def test_loading_retried_after_lock_wait(self):
        self.assertTrue(j.lock_bound_miss("loading", self.QUEUED))

    def test_loading_failure_without_lock_wait_is_real(self):
        self.assertFalse(j.lock_bound_miss("loading", "error: driver: no on-screen element id=fst.suggestions.loading"))

    def test_other_scenarios_never_retried(self):
        for name in set(j.SCENARIOS) - j.LOCK_BOUND:
            self.assertFalse(j.lock_bound_miss(name, self.QUEUED), name)

    def test_lock_bound_scenarios_exist(self):
        self.assertLessEqual(j.LOCK_BOUND, set(j.SCENARIOS))


class RivalCardTests(unittest.TestCase):
    """Issue #259: spotlight rows draw no name pill but name the rival; mixed-rival rows keep the pill."""

    TREE = "\n".join([
        '  ListItem "Rival Spotlight: Rival B1" id= class=ListViewItem rect=795,337,2970,1163',
        f'    Group "Rival Spotlight: Rival B1" id={j.SPOTLIGHT_CARD} class=NamedContainerAutomationPeer rect=1,1,1,1',
        '      Text "Rival Spotlight: Rival B1" id= class=TextBlock rect=807,337,2922,17 heading=2',
        f'      Button "{j.SPOTLIGHT_ROW_NAME}" id=fst.suggestions.row.s041|Solo_PeripheralGuitar class=Button rect=1',
        '        Text "Track 41" id= class= rect=1038,476,2358,55',
        '        Text "-2" id= class=TextBlock rect=3432,503,42,55',
        '      Button "Track 14, Artist C · 2004, Pro Lead, 9 ranks ahead of Rival B1" id=fst.suggestions.row.s014 rect=1',
        '  ListItem "Climb Past Rival B4" id= class=ListViewItem rect=795,1641,2970,371',
        f'    Group "Climb Past Rival B4" id={j.MIXED_CARD} class=NamedContainerAutomationPeer rect=1,1,1,1',
        f'      Button "{j.MIXED_ROW_NAME}" id=fst.suggestions.row.s034|Solo_Guitar class=Button rect=1',
        '        Text "Rival B4" id= class=TextBlock rect=3231,1854,153,56',
        '        Text "-2" id= class=TextBlock rect=3432,1854,42,56',
        '      Button "Track 40, Artist A · 2004, Pro Lead, rival Rival B2" id=fst.suggestions.row.s040 rect=1',
        '        Text "Rival B2" id= class=TextBlock rect=1,1,1,1',
    ])

    def test_subtree_stops_at_the_next_card(self):
        card = j.card_subtree(self.TREE, j.SPOTLIGHT_CARD)
        self.assertEqual(6, len(card))
        self.assertFalse(any("Climb Past" in line for line in card))

    def test_subtree_skips_offscreen_copies(self):
        tree = f'Group "x" id={j.MIXED_CARD} class=C rect=0,0,0,0 [offscreen]\n  Text "Rival B4" id= rect=0'
        self.assertEqual([], j.card_subtree(tree, j.MIXED_CARD))
        self.assertEqual(["card not on screen"], j.rival_card_problems([], "Rival B4", True))

    def test_spotlight_and_mixed_cards_pass(self):
        for card, rival, pill in ((j.SPOTLIGHT_CARD, "Rival B1", False), (j.MIXED_CARD, "Rival B4", True)):
            self.assertEqual([], j.rival_card_problems(j.card_subtree(self.TREE, card), rival, pill), card)

    def test_spotlight_pill_is_a_failure(self):
        tree = self.TREE.replace('        Text "-2" id= class=TextBlock rect=3432,503,42,55',
                                 '        Text "Rival B1" id= class=TextBlock rect=1\n        Text "-2" id= rect=1', 1)
        problems = j.rival_card_problems(j.card_subtree(tree, j.SPOTLIGHT_CARD), "Rival B1", False)
        self.assertIn("name pill 'Rival B1' still drawn", problems)

    def test_spotlight_row_without_rival_in_name_is_a_failure(self):
        tree = self.TREE.replace("2 ranks behind Rival B1", "behind by 2 ranks")
        problems = j.rival_card_problems(j.card_subtree(tree, j.SPOTLIGHT_CARD), "Rival B1", False)
        self.assertEqual(1, len(problems))
        self.assertIn("row does not name", problems[0])

    def test_mixed_card_without_pill_or_rival_name_fails(self):
        tree = self.TREE.replace('        Text "Rival B4" id= class=TextBlock rect=3231,1854,153,56\n', "")
        tree = tree.replace("rival Rival B4, behind by 2 ranks", "2 ranks behind Rival B4")
        problems = j.rival_card_problems(j.card_subtree(tree, j.MIXED_CARD), "Rival B4", True)
        self.assertEqual(["name pill 'Rival B4' missing", "no row is named 'rival Rival B4'"], problems)

    def test_rows_without_buttons_fail(self):
        self.assertEqual(["card has no rows"], j.rival_card_problems(['Group "x" id=c'], "R", False))

    def test_checks_name_real_scenarios(self):
        self.assertLessEqual(set(j.RIVAL_CHECKS), set(j.SCENARIOS))


if __name__ == "__main__":
    unittest.main()
