"""``apple-ci``'s iPhone and iPad simulator journeys: every selector names a real XCUITest method.

A selector that matches nothing makes ``xcodebuild`` run no test, so a renamed journey would silently leave CI.
The ``JOURNEYS`` blocks (iPhone UI-test bundle, on the iPhone and the iPad) must keep the account-button
reading-order journeys (``page-tools-and-nav-chrome`` R17, #394), the Songs section-title AX5 journey (#91, #441), the
What's New AX5 journeys (#434: iPhone portrait, iPad portrait and landscape) and the pinned caption-icon journeys
(``song-header`` R4, #542); ``HISTORY_JOURNEYS``/``HISTORY_IPAD_JOURNEYS`` (iPad bundle, on the iPhone and the iPad)
must keep the Score History AX5 journeys (#385, the region #302 changed).
"""

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "apple-ci.yml"
UITESTS = ROOT / "apple" / "Apps" / "iOSUITests"
IPAD_UITESTS = ROOT / "apple" / "Apps" / "iPadOSUITests"

#: Folded selector block names in ``apple-ci.yml`` and the UI-test bundle each runs.
BLOCKS = {"JOURNEYS": UITESTS, "HISTORY_JOURNEYS": IPAD_UITESTS, "HISTORY_IPAD_JOURNEYS": IPAD_UITESTS}


def ci_journey_blocks(text: str, key: str = "JOURNEYS") -> list[list[str]]:
    """Read every ``<key>: >-`` folded selector block from ``apple-ci.yml`` (one per simulator step).

    Args:
        text: The workflow source.
        key: The blocks' environment variable.

    Returns:
        Each block's selectors, in step order.
    """
    lines = text.splitlines()
    blocks = []
    for start, header in enumerate(lines):
        if header.strip() != f"{key}: >-":
            continue
        indent = len(header) - len(header.lstrip())
        selectors = []
        for line in lines[start + 1:]:
            if not line.strip() or len(line) - len(line.lstrip()) <= indent:
                break
            selectors.extend(line.split())
        blocks.append(selectors)
    return blocks


def ci_journeys(text: str, key: str = "JOURNEYS") -> list[str]:
    """Read the first ``<key>: >-`` folded selector block from ``apple-ci.yml`` (for ``JOURNEYS``, the iPhone's).

    Args:
        text: The workflow source.
        key: The block's environment variable.

    Returns:
        The selectors, in order.
    """
    return ci_journey_blocks(text, key)[0]


class AppleCIJourneysTests(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.journeys = ci_journeys(self.workflow)
        self.blocks = ci_journey_blocks(self.workflow)
        self.history = {key: ci_journeys(self.workflow, key) for key in ("HISTORY_JOURNEYS", "HISTORY_IPAD_JOURNEYS")}

    def test_reads_the_folded_block(self) -> None:
        sample = "      env:\n        JOURNEYS: >-\n          A/a\n          B/b\n      run: x\n"
        self.assertEqual(ci_journeys(sample), ["A/a", "B/b"])
        self.assertEqual(ci_journey_blocks(sample + sample.replace("A/a", "C/c")), [["A/a", "B/b"], ["C/c", "B/b"]])
        self.assertEqual(ci_journeys(sample.replace("JOURNEYS", "HISTORY_JOURNEYS"), "HISTORY_JOURNEYS"), ["A/a", "B/b"])

    def test_every_selector_names_an_existing_test_method(self) -> None:
        self.assertEqual(len(self.blocks), 2, "one JOURNEYS block per simulator step (iPhone, iPad)")
        for key, folder in BLOCKS.items():
            blocks = ci_journey_blocks(self.workflow, key)
            self.assertTrue(blocks, key)
            for block in blocks:
                self.assertTrue(block, key)
                self.assertEqual(len(block), len(set(block)), f"duplicate journeys in {key}")
                for selector in block:
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

    def test_whats_new_ax5_journeys_run_on_iphone_and_ipad(self) -> None:
        iphone, ipad = self.blocks
        journey = "WhatsNewAccessibilityJourneyTests/testWhatsNewIsReadableAtAX5"
        # iPhone is portrait-only, so its landscape journey skips and would fail --fail-on-skip.
        self.assertIn(f"{journey}Portrait", iphone)
        self.assertNotIn(f"{journey}Landscape", iphone)
        self.assertIn(f"{journey}Portrait", ipad)
        self.assertIn(f"{journey}Landscape", ipad)

    def test_ipad_steps_use_the_ipad_device_type(self) -> None:
        sys.path.insert(0, str(ROOT / "tools"))
        import ios_sim

        self.assertEqual(self.workflow.count(f'ci-device --type "{ios_sim.CI_IPAD_DEVICE_TYPE}"'), 2)

    def test_score_history_ax5_journeys_run_on_iphone_and_ipad(self) -> None:
        page = "ScoreHistoryAccessibilityJourneyTests/testScoreHistoryPageAtAX5"
        split = "ScoreHistoryAccessibilityJourneyTests/testScoreHistorySplitPaneAtAX5"
        self.assertEqual(self.history["HISTORY_JOURNEYS"], [page], "the iPhone run: the page only (the split skips)")
        self.assertEqual(self.history["HISTORY_IPAD_JOURNEYS"], [page, split])
        self.assertEqual(self.workflow.count("uitest --app ipad"), 2)
        self.assertEqual(self.workflow.count("--fail-on-skip"), 4)

    def test_section_title_ax5_journey_runs_in_ci(self) -> None:
        # #91/#441: the only iOS Dynamic Type and audit evidence for Songs' grouped-sort section titles.
        self.assertIn("SongsJourneyTests/testSongsShopSortSectionTitlesAreAccessibleAtAX5", self.journeys)

    def test_pinned_caption_icon_journeys_run_in_ci(self) -> None:
        for method in (
            "testSongLeaderboardCaptionIconScalesWithText",
            "testPlayerHistoryCaptionIconAtLargestText",
        ):
            self.assertIn(f"SongBarCaptionIconJourneyTests/{method}", self.journeys)


if __name__ == "__main__":
    unittest.main()
