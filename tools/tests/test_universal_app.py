"""The iOS app is one universal iPhone + iPad app (operator decision, 2026-10-02).

`apple/project.yml` is the source of the generated Info.plist, so these text checks guard the
App Store-facing keys: device family, per-idiom orientations, the launch screen and the absence
of a separate iPad app target.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "apple/project.yml"


def target_block(source: str, name: str) -> str:
    """Return one top-level target's YAML block (two-space indented key to the next one).

    Args:
        source: Full `project.yml` text.
        name: Target name, e.g. ``FestivalMobile``.

    Returns:
        The block's text, or an empty string when the target is missing.
    """
    match = re.search(rf"^  {re.escape(name)}:\n(.*?)(?=^  \S|^\S|\Z)", source, re.M | re.S)
    return match.group(1) if match else ""


def list_under(block: str, key: str) -> list[str]:
    """Return the ``- item`` entries directly under ``key:`` in a block.

    Args:
        block: A target block from `target_block`.
        key: YAML key whose list to read.

    Returns:
        The list items in order (empty when the key is missing).
    """
    match = re.search(rf"^(\s+){re.escape(key)}:\n((?:\1  - .*\n)+)", block, re.M)
    return re.findall(r"- (\S+)", match.group(2)) if match else []


class UniversalAppTests(unittest.TestCase):
    """FestivalMobile ships iPhone and iPad in one bundle; no FestivalTablet target remains."""

    @classmethod
    def setUpClass(cls):
        cls.source = PROJECT.read_text(encoding="utf-8")
        cls.mobile = target_block(cls.source, "FestivalMobile")

    def test_device_family_is_iphone_and_ipad(self):
        self.assertIn('TARGETED_DEVICE_FAMILY: "1,2"', self.mobile)

    def test_iphone_stays_portrait_only(self):
        self.assertEqual(list_under(self.mobile, "UISupportedInterfaceOrientations"),
                         ["UIInterfaceOrientationPortrait"])

    def test_ipad_supports_every_orientation_for_multitasking(self):
        self.assertEqual(sorted(list_under(self.mobile, "UISupportedInterfaceOrientations~ipad")), sorted([
            "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
            "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
        ]))
        self.assertNotRegex(self.mobile, re.compile(r"^\s+UIRequiresFullScreen[~a-z]*:", re.M), "multitasking needs it unset")

    def test_ipad_supports_multiple_windows(self):
        # iPad windows share one session and keep their own navigation (ipados.md, Windows).
        self.assertIn("UIApplicationSupportsMultipleScenes: true", self.mobile)

    def test_launch_screen_and_icon_are_kept(self):
        self.assertIn("UIColorName: FestivalLaunchBackground", self.mobile)
        self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon", self.mobile)

    def test_no_separate_ipad_app(self):
        self.assertNotIn("FestivalTablet", self.source)
        self.assertNotIn("festivalscoretracker.ipad", self.source)
        ipad_tests = target_block(self.source, "FestivalMobileIPadUITests")
        self.assertIn("TEST_TARGET_NAME: FestivalMobile\n", ipad_tests)


if __name__ == "__main__":
    unittest.main()
