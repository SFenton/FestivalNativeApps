"""``suggestions_journey.py``: launch arguments and the desktop-lock retry rule (issue #205).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import suggestions_journey as j  # noqa: E402  (sibling module)

# A named-rival card (Suggestions R1, #656) as a later remix shows it.
CLIMB_CARD = "fst.suggestions.category.song_rival_pct_push.2"
CLIMB_ROW_NAME = "Track 42, Artist B · 2004, Lead, 5 ranks behind Rival B4"


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


class LoadMoreCardTests(unittest.TestCase):
    """Issue #661: load-more and end-of-mix target the cards seed 1 shows after Suggestions R1 (#656)."""

    def test_cards_after_named_rival_mix(self):
        self.assertEqual("id=fst.suggestions.category.song_rival_protect_rival-below-2", j.RIVAL_CARD)
        self.assertEqual("id=fst.suggestions.category.song_rival_dominate_rival-above-2", j.TWELFTH_CARD)

    def test_scenarios_scroll_to_them_after_the_tenth_card(self):
        load_more = j.SCENARIOS["load-more"][2]
        self.assertLess(load_more.index(f"scrollinto:{j.TENTH_CARD}"), load_more.index(f"scrollinto:{j.RIVAL_CARD}@15"))
        self.assertIn(f"waitfor:{j.RIVAL_CARD}@10", load_more)
        end = j.SCENARIOS["end-of-mix"]
        self.assertEqual("12", end[1]["FST_DEBUG_SUGGESTIONS_LIMIT"])
        self.assertLess(end[2].index(f"scrollinto:{j.TENTH_CARD}"), end[2].index(f"scrollinto:{j.TWELFTH_CARD}@15"))


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
        '  ListItem "Stale Songs Your Rivals Are Beating You On" id= class=ListViewItem rect=795,1641,2970,371',
        f'    Group "Stale Songs Your Rivals Are Beating You On" id={j.MIXED_CARD} class=NamedContainerAutomationPeer rect=1',
        f'      Button "{j.MIXED_ROW_NAME}" id=fst.suggestions.row.s034|Solo_Guitar class=Button rect=1',
        '        Text "Rival B4" id= class=TextBlock rect=3231,1854,153,56',
        '        Text "-2" id= class=TextBlock rect=3432,1854,42,56',
        '      Button "Track 40, Artist A · 2004, Pro Lead, rival Rival B2" id=fst.suggestions.row.s040 rect=1',
        '        Text "Rival B2" id= class=TextBlock rect=1,1,1,1',
        '  ListItem "Climb Past Rival B4" id= class=ListViewItem rect=795,2100,2970,371',
        f'    Group "Climb Past Rival B4" id={CLIMB_CARD} class=NamedContainerAutomationPeer rect=1,1,1,1',
        f'      Button "{CLIMB_ROW_NAME}" id=fst.suggestions.row.s042|Solo_Guitar class=Button rect=1',
        '        Text "-5" id= class=TextBlock rect=3432,2200,42,56',
        '      Button "Track 34, Artist O · 1999, Lead, 2 ranks behind Rival B4" id=fst.suggestions.row.s034 rect=1',
    ])

    def test_subtree_stops_at_the_next_card(self):
        card = j.card_subtree(self.TREE, j.SPOTLIGHT_CARD)
        self.assertEqual(6, len(card))
        self.assertFalse(any("Stale Songs" in line for line in card))

    def test_subtree_skips_offscreen_copies(self):
        tree = f'Group "x" id={j.MIXED_CARD} class=C rect=0,0,0,0 [offscreen]\n  Text "Rival B4" id= rect=0'
        self.assertEqual([], j.card_subtree(tree, j.MIXED_CARD))
        self.assertEqual(["card not on screen"], j.rival_card_problems([], "Rival B4", True))

    def test_spotlight_and_mixed_cards_pass(self):
        for card, rival, pill in ((j.SPOTLIGHT_CARD, "Rival B1", False), (j.MIXED_CARD, "Rival B4", True),
                                  (CLIMB_CARD, "Rival B4", False)):
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

    def test_named_card_listing_another_rival_fails(self):
        # Issue #656: "Climb Past Rival B4" must not list a song whose closest rival is someone else.
        tree = self.TREE.replace("5 ranks behind Rival B4", "5 ranks behind Rival B2")
        problems = j.rival_card_problems(j.card_subtree(tree, CLIMB_CARD), "Rival B4", False)
        self.assertEqual(1, len(problems))
        self.assertIn("row does not name 'Rival B4'", problems[0])

    def test_rows_without_buttons_fail(self):
        self.assertEqual(["card has no rows"], j.rival_card_problems(['Group "x" id=c'], "R", False))

    def test_named_sweep_checks_each_card_against_its_title(self):
        checked, problems = j.named_card_problems([self.TREE, self.TREE])
        self.assertEqual(["song_rival_pct_push.2"], checked)
        self.assertEqual([], problems)

    def test_named_sweep_flags_a_row_for_another_rival(self):
        tree = self.TREE.replace("2 ranks behind Rival B4", "2 ranks behind Rival B2")
        checked, problems = j.named_card_problems([tree])
        self.assertEqual(["song_rival_pct_push.2"], checked)
        self.assertEqual(1, len(problems))
        self.assertIn("song_rival_pct_push.2: row does not name 'Rival B4'", problems[0])

    def test_named_sweep_flags_a_pill_and_reads_fc_titles(self):
        tree = "\n".join([
            '  Group "FC These to Beat Rival A1!" id=fst.suggestions.category.song_rival_near_fc.1 class=C rect=1',
            '    Button "Track 9, Artist Z, Drums, 3 ranks behind Rival A1" id=fst.suggestions.row.s009 rect=1',
            '      Text "Rival A1" id= class=TextBlock rect=1',
        ])
        checked, problems = j.named_card_problems([tree])
        self.assertEqual(["song_rival_near_fc.1"], checked)
        self.assertEqual(["song_rival_near_fc.1: name pill 'Rival A1' still drawn"], problems)

    def test_named_sweep_skips_offscreen_cards(self):
        tree = f'Group "Climb Past Rival B4" id={CLIMB_CARD} class=C rect=0,0,0,0 [offscreen]\n  Button "x" rect=0'
        self.assertEqual(([], []), j.named_card_problems([tree]))

    def test_named_sweep_scenarios_load_more(self):
        self.assertLessEqual(j.NAMED_SWEEPS, set(j.SCENARIOS))
        steps = j.SCENARIOS["rival-rows"][2]
        self.assertEqual(j.NAMED_LOADS, sum(step.startswith("tree:{scans}/named-") for step in steps))

    def test_checks_name_real_scenarios(self):
        self.assertLessEqual(set(j.RIVAL_CHECKS), set(j.SCENARIOS))


if __name__ == "__main__":
    unittest.main()
