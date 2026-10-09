"""``apple-ci``'s simulator journeys: every selector names a real XCUITest method.

A selector that matches nothing makes ``xcodebuild`` run no test, so a renamed journey would silently leave CI.
``JOURNEYS`` (iPhone bundle) must keep the account-button reading-order journeys (``page-tools-and-nav-chrome``
R17, #394); ``HISTORY_JOURNEYS``/``HISTORY_IPAD_JOURNEYS`` (iPad bundle, on the iPhone and the iPad) must keep the
Score History AX5 journeys (#385, the region #302 changed).
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "apple-ci.yml"
UITESTS = ROOT / "apple" / "Apps" / "iOSUITests"
IPAD_UITESTS = ROOT / "apple" / "Apps" / "iPadOSUITests"

#: Folded selector blocks in ``apple-ci.yml`` and the UI-test bundle each runs.
BLOCKS = {"JOURNEYS": UITESTS, "HISTORY_JOURNEYS": IPAD_UITESTS, "HISTORY_IPAD_JOURNEYS": IPAD_UITESTS}


def ci_journeys(text: str, key: str = "JOURNEYS") -> list[str]:
    """Read a ``<key>: >-`` folded selector block from ``apple-ci.yml``.

    Args:
        text: The workflow source.
        key: The block's environment variable.

    Returns:
        The selectors, in order.
    """
    lines = text.splitlines()
    start = next(i for i, line in enumerate(lines) if line.strip() == f"{key}: >-")
    indent = len(lines[start]) - len(lines[start].lstrip())
    selectors = []
    for line in lines[start + 1:]:
        if not line.strip() or len(line) - len(line.lstrip()) <= indent:
            break
        selectors.extend(line.split())
    return selectors


class AppleCIJourneysTests(unittest.TestCase):
    def setUp(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        self.blocks = {key: ci_journeys(text, key) for key in BLOCKS}
        self.journeys = self.blocks["JOURNEYS"]

    def test_reads_the_folded_block(self) -> None:
        sample = "      env:\n        JOURNEYS: >-\n          A/a\n          B/b\n      run: x\n"
        self.assertEqual(ci_journeys(sample), ["A/a", "B/b"])

    def test_every_selector_names_an_existing_test_method(self) -> None:
        for key, folder in BLOCKS.items():
            journeys = self.blocks[key]
            self.assertTrue(journeys, key)
            self.assertEqual(len(journeys), len(set(journeys)), f"duplicate journeys in {key}")
            for selector in journeys:
                cls, _, method = selector.partition("/")
                source = folder / f"{cls}.swift"
                self.assertTrue(source.exists(), f"{key} {selector}: {cls}.swift not in {folder.relative_to(ROOT)}")
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

    def test_score_history_ax5_journeys_run_on_iphone_and_ipad(self) -> None:
        page = "ScoreHistoryAccessibilityJourneyTests/testScoreHistoryPageAtAX5"
        split = "ScoreHistoryAccessibilityJourneyTests/testScoreHistorySplitPaneAtAX5"
        self.assertEqual(self.blocks["HISTORY_JOURNEYS"], [page], "the iPhone run: the page only (the split skips)")
        self.assertEqual(self.blocks["HISTORY_IPAD_JOURNEYS"], [page, split])
        text = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn('ci-device --type "iPad Pro 11-inch (M5)"', text)
        self.assertEqual(text.count("uitest --app ipad"), 2)
        self.assertEqual(text.count("--fail-on-skip"), 3)


if __name__ == "__main__":
    unittest.main()
