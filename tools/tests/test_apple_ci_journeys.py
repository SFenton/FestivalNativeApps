"""Checks the iPhone simulator journeys ``apple-ci`` runs (``JOURNEYS`` in ``.github/workflows/apple-ci.yml``).

A misspelt selector would make ``ios_sim.py uitest --fail-on-skip`` fail only on the runner, and a dropped one would
silently stop gating pull requests; see ``.agents/testing/apple/xcuitest.md#ci-journeys``.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UI_TESTS = ROOT / "apple" / "Apps" / "iOSUITests"
WORKFLOW = ROOT / ".github" / "workflows" / "apple-ci.yml"


def ci_journeys(workflow: str) -> list[str]:
    """Selectors in the workflow's ``JOURNEYS: >-`` block.

    Args:
        workflow: ``apple-ci.yml`` text.

    Returns:
        ``Class/testMethod`` selectors in order.
    """
    block = re.search(r"JOURNEYS: >-\n((?:[ ]{12}\S+\n)+)", workflow)
    return block.group(1).split() if block else []


class AppleCiJourneysTests(unittest.TestCase):
    """``apple-ci``'s journey list names real journeys and keeps the accessibility evidence it promises."""

    def setUp(self) -> None:
        self.journeys = ci_journeys(WORKFLOW.read_text(encoding="utf-8"))
        self.sources = {path.stem: path.read_text(encoding="utf-8") for path in UI_TESTS.glob("*.swift")}

    def test_every_journey_names_a_test_method(self) -> None:
        self.assertTrue(self.journeys, "apple-ci.yml has no JOURNEYS block")
        for selector in self.journeys:
            with self.subTest(selector=selector):
                cls, _, method = selector.partition("/")
                self.assertTrue(method.startswith("test"), selector)
                source = next((text for text in self.sources.values()
                               if re.search(rf"\bclass {re.escape(cls)}\b", text)), None)
                self.assertIsNotNone(source, f"no XCTestCase {cls} in apple/Apps/iOSUITests")
                self.assertRegex(source, rf"func {re.escape(method)}\(\)")

    def test_section_title_ax5_journey_gates_pull_requests(self) -> None:
        # #91/#441: the only iOS Dynamic Type and audit evidence for Songs' grouped-sort section titles.
        self.assertIn("SongsJourneyTests/testSongsShopSortSectionTitlesAreAccessibleAtAX5", self.journeys)

    def test_parser_reads_only_the_folded_block(self) -> None:
        text = "        env:\n          JOURNEYS: >-\n            A/testOne\n            B/testTwo\n        run: |\n"
        self.assertEqual(ci_journeys(text), ["A/testOne", "B/testTwo"])


if __name__ == "__main__":
    unittest.main()
