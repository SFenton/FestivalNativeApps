"""``apple-ci``'s iPhone and iPad simulator journeys: every ``JOURNEYS`` selector names a real XCUITest method.

A selector that matches nothing makes ``xcodebuild`` run no test, so a renamed journey would silently leave CI.
The account-button reading-order journeys (``page-tools-and-nav-chrome`` R17, #394), the Songs section-title AX5
journey (#91, #441), the What's New AX5 journeys (#434: iPhone portrait, iPad portrait and landscape) and the
Rival Detail frozen-state journeys (#444: iPhone, iPad and folded iPhone Duo) must stay listed.
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
        self.assertEqual(
            len(self.blocks), 3, "one JOURNEYS block per simulator step (iPhone, iPad, Rival Detail devices)"
        )
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
        iphone, ipad = self.blocks[:2]
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

    def test_rival_detail_frozen_journeys_run_on_every_touch_form_factor(self) -> None:
        # #444: the only device evidence for Rival Detail's frozen-service state (#95) on iPhone, iPad and Duo.
        sys.path.insert(0, str(ROOT / "tools"))
        import ios_sim

        rivals = self.blocks[2]
        for method in (
            "testFrozenRivalDetailNamesOrdersSizesAndGrowsItsRows",
            "testFrozenRivalDetailWithoutSnapshotOffersRetry",
        ):
            self.assertIn(f"RivalDetailFrozenAccessibilityJourneyTests/{method}", rivals)
        for device in (f'"{ios_sim.CI_IPAD_DEVICE_TYPE}|"', f'"{ios_sim.CI_DEVICE_TYPE}|"', '"iPhone Duo|folded"'):
            self.assertIn(device, self.workflow)

    def test_section_title_ax5_journey_runs_in_ci(self) -> None:
        # #91/#441: the only iOS Dynamic Type and audit evidence for Songs' grouped-sort section titles.
        self.assertIn("SongsJourneyTests/testSongsShopSortSectionTitlesAreAccessibleAtAX5", self.journeys)


if __name__ == "__main__":
    unittest.main()
