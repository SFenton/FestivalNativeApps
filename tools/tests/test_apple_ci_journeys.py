"""``apple-ci``'s iPhone and iPad simulator journeys: every ``JOURNEYS`` selector names a real XCUITest method.

A selector that matches nothing makes ``xcodebuild`` run no test, so a renamed journey would silently leave CI.
The account-button reading-order journeys (``page-tools-and-nav-chrome`` R17, #394), the Songs section-title AX5
journey (#91, #441), the What's New AX5 journeys (#434: iPhone portrait, iPad portrait and landscape) and the
scroll-edge fade journeys (#462: sheet header and every R9 board on iPhone and iPad, Duo windows on iPhone) must
stay listed.
"""

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "apple-ci.yml"
UITESTS = ROOT / "apple" / "Apps" / "iOSUITests"


def ci_journey_blocks(text: str) -> list[list[str]]:
    """Read every ``JOURNEYS: >-`` folded block from ``apple-ci.yml`` (one per simulator step).

    Args:
        text: The workflow source.

    Returns:
        Each block's selectors, in step order.
    """
    lines = text.splitlines()
    blocks = []
    for start, header in enumerate(lines):
        if header.strip() != "JOURNEYS: >-":
            continue
        indent = len(header) - len(header.lstrip())
        selectors = []
        for line in lines[start + 1:]:
            if not line.strip() or len(line) - len(line.lstrip()) <= indent:
                break
            selectors.extend(line.split())
        blocks.append(selectors)
    return blocks


def ci_journeys(text: str) -> list[str]:
    """Read the first (iPhone) ``JOURNEYS: >-`` folded block from ``apple-ci.yml``.

    Args:
        text: The workflow source.

    Returns:
        The selectors, in order.
    """
    return ci_journey_blocks(text)[0]


class AppleCIJourneysTests(unittest.TestCase):
    def setUp(self) -> None:
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.journeys = ci_journeys(self.workflow)
        self.blocks = ci_journey_blocks(self.workflow)

    def test_reads_the_folded_block(self) -> None:
        sample = "      env:\n        JOURNEYS: >-\n          A/a\n          B/b\n      run: x\n"
        self.assertEqual(ci_journeys(sample), ["A/a", "B/b"])
        self.assertEqual(ci_journey_blocks(sample + sample.replace("A/a", "C/c")), [["A/a", "B/b"], ["C/c", "B/b"]])

    def test_every_selector_names_an_existing_test_method(self) -> None:
        self.assertEqual(len(self.blocks), 2, "one JOURNEYS block per simulator step (iPhone, iPad)")
        for block in self.blocks:
            self.assertTrue(block)
            self.assertEqual(len(block), len(set(block)), "duplicate journeys")
        for selector in (selector for block in self.blocks for selector in block):
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

    def test_whats_new_ax5_journeys_run_on_iphone_and_ipad(self) -> None:
        iphone, ipad = self.blocks
        journey = "WhatsNewAccessibilityJourneyTests/testWhatsNewIsReadableAtAX5"
        # iPhone is portrait-only, so its landscape journey skips and would fail --fail-on-skip.
        self.assertIn(f"{journey}Portrait", iphone)
        self.assertNotIn(f"{journey}Landscape", iphone)
        self.assertIn(f"{journey}Portrait", ipad)
        self.assertIn(f"{journey}Landscape", ipad)

    def test_ipad_step_uses_the_ipad_device_type(self) -> None:
        sys.path.insert(0, str(ROOT / "tools"))
        import ios_sim

        self.assertIn(f'ci-device --type "{ios_sim.CI_IPAD_DEVICE_TYPE}"', self.workflow)

    def test_section_title_ax5_journey_runs_in_ci(self) -> None:
        # #91/#441: the only iOS Dynamic Type and audit evidence for Songs' grouped-sort section titles.
        self.assertIn("SongsJourneyTests/testSongsShopSortSectionTitlesAreAccessibleAtAX5", self.journeys)

    def test_scroll_edge_journeys_run_on_iphone_and_ipad(self) -> None:
        # #462: the iOS evidence for scroll-edge R1, R7 and R9 (sheet header and every pager board).
        iphone, ipad = self.blocks
        cls = "ScrollEdgeFadeAccessibilityJourneyTests"
        boards = [
            f"{cls}/test{board}FadeKeepsRowsAndPagerAccessible"
            for board in ("SongLeaderboard", "FullRankings", "BandRankings", "SongBandLeaderboard", "PlayerBands")
        ]
        for journey in boards + [f"{cls}/testNotificationsSheetAtLargestTextWithHardEdge"]:
            self.assertIn(journey, iphone)
            self.assertIn(journey, ipad)
        self.assertIn(f"{cls}/testNotificationsSheetHeaderAndPinnedTitlesAreAccessible", iphone)
        # The Duo window journeys skip on iPad, which would fail --fail-on-skip.
        for duo in ("testBoardFadesInDuoWindows", "testNotificationsSheetInDuoWindows"):
            self.assertIn(f"{cls}/{duo}", iphone)
            self.assertNotIn(f"{cls}/{duo}", ipad)
        self.assertIn("mock_service.py --large-rankings --port 8766", self.workflow)


if __name__ == "__main__":
    unittest.main()
