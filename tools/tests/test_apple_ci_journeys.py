"""``apple-ci``'s iPhone simulator journeys: every ``JOURNEYS`` selector names a real XCUITest method.

A selector that matches nothing makes ``xcodebuild`` run no test, so a renamed journey would silently leave CI.
The account-button reading-order journeys (``page-tools-and-nav-chrome`` R17, #394) and the Songs section-title AX5
journey (#91, #441) must stay listed.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "apple-ci.yml"
UITESTS = ROOT / "apple" / "Apps" / "iOSUITests"


def ci_journeys(text: str) -> list[str]:
    """Read the ``JOURNEYS: >-`` folded block from ``apple-ci.yml``.

    Args:
        text: The workflow source.

    Returns:
        The selectors, in order.
    """
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if line.strip() == "JOURNEYS: >-")
    indent = len(lines[start]) - len(lines[start].lstrip())
    selectors = []
    for line in lines[start + 1:]:
        if not line.strip() or len(line) - len(line.lstrip()) <= indent:
            break
        selectors.extend(line.split())
    return selectors


class AppleCIJourneysTests(unittest.TestCase):
    def setUp(self) -> None:
        self.journeys = ci_journeys(WORKFLOW.read_text(encoding="utf-8"))

    def test_reads_the_folded_block(self) -> None:
        sample = "      env:\n        JOURNEYS: >-\n          A/a\n          B/b\n      run: x\n"
        self.assertEqual(ci_journeys(sample), ["A/a", "B/b"])

    def test_every_selector_names_an_existing_test_method(self) -> None:
        self.assertTrue(self.journeys)
        self.assertEqual(len(self.journeys), len(set(self.journeys)), "duplicate journeys")
        for selector in self.journeys:
            cls, _, method = selector.partition("/")
            source = UITESTS / f"{cls}.swift"
            self.assertTrue(source.exists(), f"{selector}: {cls}.swift not in apple/Apps/iOSUITests")
            text = source.read_text(encoding="utf-8")
            self.assertRegex(text, rf"\bclass {re.escape(cls)}\b", selector)
            if method:
                self.assertRegex(text, rf"\bfunc {re.escape(method)}\(\)", selector)

    def test_account_button_reading_order_journeys_run_in_ci(self) -> None:
        for method in (
            "testAccountButtonsReadInProductionChromeOrder",
            "testAccountButtonsReadInProductionChromeOrderOnPushedPage",
            "testChooseProfileReadsAloneInProductionChrome",
            "testAccountButtonsStaySeparateAndLabelledAtLargestTextSize",
        ):
            self.assertIn(f"NavButtonHitRegionJourneyTests/{method}", self.journeys)

    def test_section_title_ax5_journey_runs_in_ci(self) -> None:
        # #91/#441: the only iOS Dynamic Type and audit evidence for Songs' grouped-sort section titles.
        self.assertIn("SongsJourneyTests/testSongsShopSortSectionTitlesAreAccessibleAtAX5", self.journeys)


if __name__ == "__main__":
    unittest.main()
