"""``apple-ci``'s simulator journeys: every selector names a real XCUITest method its leg compiles.

A selector that matches nothing makes ``xcodebuild`` run no test, so a renamed journey would silently leave CI.
The account-button reading-order journeys (``page-tools-and-nav-chrome`` R17, #394), the Songs section-title AX5
journey (#91, #441), the What's New AX5 journeys (#434: iPhone portrait, iPad portrait and landscape) and the
pinned caption-icon journeys (``song-header`` R4, #542) must stay listed, and the Songs Filter journeys (#432) must
run on the iPhone, the iPad and the folded iPhone Duo, gated by the required ``apple-ci`` job.
"""

from __future__ import annotations

import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "apple-ci.yml"
UITESTS = ROOT / "apple" / "Apps" / "iOSUITests"
IPAD_UITESTS = ROOT / "apple" / "Apps" / "iPadOSUITests"
PROJECT = ROOT / "apple" / "project.yml"
FILTER_JOURNEYS = (
    "SongsFilterAccessibilityJourneyTests/testNoProfileGeneralFiltersPassAccessibilityAudit",
    "SongsFilterAccessibilityJourneyTests/testDynamicTypeAuditWithShopHidden",
    "SongsFilterAccessibilityJourneyTests/testGeneralFiltersAtLargestText",
)


def folded_blocks(text: str, key: str) -> list[list[str]]:
    """Read every ``<key>: >-`` folded block from ``apple-ci.yml``.

    Args:
        text: The workflow source.
        key: The YAML key, e.g. ``JOURNEYS`` or ``journeys``.

    Returns:
        Each block's selectors, in order.
    """
    lines = text.splitlines()
    blocks = []
    for start, line in enumerate(lines):
        if line.strip() != f"{key}: >-":
            continue
        indent = len(line) - len(line.lstrip())
        selectors = []
        for body in lines[start + 1:]:
            if not body.strip() or len(body) - len(body.lstrip()) <= indent:
                break
            selectors.extend(body.split())
        blocks.append(selectors)
    return blocks


def ci_journey_blocks(text: str) -> list[list[str]]:
    """Read every ``JOURNEYS: >-`` folded block from ``apple-ci.yml`` (the build job's iPhone and iPad steps).

    Args:
        text: The workflow source.

    Returns:
        Each block's selectors, in step order.
    """
    return folded_blocks(text, "JOURNEYS")


def ci_journeys(text: str) -> list[str]:
    """Read the build job's first (iPhone) ``JOURNEYS: >-`` folded block from ``apple-ci.yml``.

    Args:
        text: The workflow source.

    Returns:
        The selectors, in order.
    """
    return folded_blocks(text, "JOURNEYS")[0]


def matrix_legs(text: str) -> dict[str, list[str]]:
    """Read the Songs Filter journey matrix: each ``leg`` with its ``journeys`` block.

    Args:
        text: The workflow source.

    Returns:
        Leg name → selectors.
    """
    legs = re.findall(r"^\s*- leg: (\S+)$", text, flags=re.MULTILINE)
    blocks = folded_blocks(text, "journeys")
    if len(legs) != len(blocks):
        raise ValueError(f"{len(legs)} legs but {len(blocks)} journeys blocks")
    return dict(zip(legs, blocks))


def ipad_target_sources() -> list[Path]:
    """The ``FestivalMobileIPadUITests`` target's source paths from ``apple/project.yml``.

    Returns:
        Absolute paths (a folder or a file).
    """
    text = PROJECT.read_text(encoding="utf-8")
    block = text.split("  FestivalMobileIPadUITests:", 1)[1].split("    dependencies:", 1)[0]
    return [ROOT / "apple" / path for path in re.findall(r"- path: (\S+)", block)]


def source_for(cls: str, roots: list[Path]) -> Path | None:
    """Find ``<cls>.swift`` among source folders and files.

    Args:
        cls: XCTestCase class name.
        roots: Folders or files a target compiles.

    Returns:
        The file, or ``None``.
    """
    for root in roots:
        candidate = root / f"{cls}.swift" if root.is_dir() else root
        if candidate.name == f"{cls}.swift" and candidate.exists():
            return candidate
    return None


class AppleCIJourneysTests(unittest.TestCase):
    def setUp(self) -> None:
        self.text = WORKFLOW.read_text(encoding="utf-8")
        self.journeys = ci_journeys(self.text)
        self.blocks = ci_journey_blocks(self.text)
        self.legs = matrix_legs(self.text)

    def assert_selectors_exist(self, selectors: list[str], roots: list[Path]) -> None:
        self.assertTrue(selectors)
        self.assertEqual(len(selectors), len(set(selectors)), "duplicate journeys")
        for selector in selectors:
            cls, _, method = selector.partition("/")
            source = source_for(cls, roots)
            self.assertIsNotNone(source, f"{selector}: {cls}.swift not compiled by its leg's UI-test target")
            text = source.read_text(encoding="utf-8")
            self.assertRegex(text, rf"\bclass {re.escape(cls)}\b", selector)
            if method:
                self.assertRegex(text, rf"\bfunc {re.escape(method)}\(\)", selector)

    def test_reads_the_folded_block(self) -> None:
        sample = "      env:\n        JOURNEYS: >-\n          A/a\n          B/b\n      run: x\n"
        self.assertEqual(ci_journeys(sample), ["A/a", "B/b"])
        self.assertEqual(ci_journey_blocks(sample + sample.replace("A/a", "C/c")), [["A/a", "B/b"], ["C/c", "B/b"]])

    def test_reads_matrix_legs(self) -> None:
        sample = (
            "          - leg: one\n            journeys: >-\n              A/a\n"
            "          - leg: two\n            journeys: >-\n              B/b\n              C/c\n    steps:\n"
        )
        self.assertEqual(matrix_legs(sample), {"one": ["A/a"], "two": ["B/b", "C/c"]})

    def test_every_selector_names_an_existing_test_method(self) -> None:
        self.assertEqual(len(self.blocks), 2, "one JOURNEYS block per build-job simulator step (iPhone, iPad)")
        for block in self.blocks:
            self.assert_selectors_exist(block, [UITESTS])

    def test_every_leg_selector_names_a_test_its_target_compiles(self) -> None:
        for leg, selectors in self.legs.items():
            with self.subTest(leg=leg):
                roots = ipad_target_sources() if leg == "ipad" else [UITESTS]
                self.assert_selectors_exist(selectors, roots)

    def test_songs_filter_journeys_run_on_every_touch_form_factor(self) -> None:
        self.assertEqual(set(self.legs), {"iphone", "ipad", "duo-folded"})
        for leg, selectors in self.legs.items():
            for journey in FILTER_JOURNEYS:
                self.assertIn(journey, selectors, leg)
        self.assertIn("SongsFilterKeyboardJourneyTests/testCommandPeriodClosesFilter", self.legs["ipad"])
        self.assertRegex(self.text, r"leg: ipad\n\s+device_type: iPad[^\n]*\n\s+uitest_args: --app ipad\n")
        self.assertRegex(self.text, r"leg: duo-folded\n\s+device_type: iPhone Duo\n\s+uitest_args: --pose folded\n")
        self.assertIn("--fail-on-skip", self.text.split("songs-filter-journeys:", 1)[1])

    def test_required_check_needs_every_job(self) -> None:
        required = self.text.split("\n  apple-ci:\n", 1)[1]
        self.assertIn("name: apple-ci\n", required)
        self.assertIn("needs: [changes, build, songs-filter-journeys]", required)
        self.assertIn("if: always()", required)
        job_names = re.findall(r"^    name: (.+)$", self.text, flags=re.MULTILINE)
        self.assertEqual(job_names.count("apple-ci"), 1, "only the gate job is named apple-ci")
        jobs = re.findall(r"^  ([a-z][\w-]*):$", self.text.split("\njobs:\n", 1)[1], flags=re.MULTILINE)
        self.assertEqual(sorted(jobs), sorted(["changes", "build", "songs-filter-journeys", "apple-ci"]),
                         "a new job must join the gate's needs")

    def test_gate_passes_only_when_every_job_passed_or_the_legs_had_nothing_to_test(self) -> None:
        script = self.gate_script()
        cases = {
            ("success", "true", "success", "success"): True,
            ("success", "false", "success", "skipped"): True,
            ("success", "true", "success", "skipped"): False,
            ("success", "true", "success", "failure"): False,
            ("success", "true", "success", "cancelled"): False,
            ("success", "false", "success", "cancelled"): False,
            ("success", "true", "failure", "success"): False,
            ("failure", "", "success", "skipped"): False,
        }
        for (changes, apple, build, journeys), passes in cases.items():
            env = {"CHANGES": changes, "APPLE": apple, "BUILD": build, "JOURNEYS": journeys, "PATH": "/usr/bin:/bin"}
            result = subprocess.run(["bash", "-e", "-c", script], env=env, capture_output=True, check=False)
            self.assertEqual(result.returncode == 0, passes, (changes, apple, build, journeys))

    def test_legs_run_for_apple_changes_and_always_on_master(self) -> None:
        legs = self.text.split("  songs-filter-journeys:", 1)[1].split("    strategy:", 1)[0]
        self.assertIn("needs: changes", legs)
        self.assertIn("if: needs.changes.outputs.apple == 'true'", legs)
        changes = self.text.split("\n  changes:\n", 1)[1].split("\n  songs-filter-journeys:", 1)[0]
        self.assertIn('[ "$EVENT" != pull_request ] ||', changes)
        pattern = re.search(r"PATTERN: '(.+)'", changes).group(1)
        for path in ("apple/Sources/FestivalUI/Features/Songs/SongsFilterSheet.swift",
                     "apple/Apps/iOSUITests/SongsFilterAccessibilityJourneyTests.swift",
                     "contracts/fixtures/songs-demo.json", "tools/ios_sim.py", "tools/mock_service.py",
                     ".github/workflows/apple-ci.yml"):
            self.assertRegex(path, pattern)
        for path in ("windows/App/MainWindow.xaml.cs", "android/app/build.gradle.kts", "PROGRESS.md",
                     "tools/ios_sim.pyc"):
            self.assertNotRegex(path, pattern)

    def gate_script(self) -> str:
        """The gate job's ``run`` script, dedented from its ``run: |`` block."""
        gate = self.text.split("\n  apple-ci:\n", 1)[1]
        block = gate.split("        run: |\n", 1)[1]
        return "\n".join(line[10:] for line in block.splitlines() if line.startswith("          "))

    def test_mac_keyboard_tests_run_alone_and_required(self) -> None:
        step = self.text.split("Mac keyboard navigation tests, alone", 1)[1].split("- name:", 1)[0]
        self.assertIn('FST_REQUIRE_KEYBOARD_NAVIGATION: "1"', step)
        self.assertIn("defaults write -g AppleKeyboardUIMode -int 2", step)
        self.assertIn("--filter SongsFilterKeyboardTests", step)

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

        self.assertIn(f'ci-device --type "{ios_sim.CI_IPAD_DEVICE_TYPE}"', self.text)
        self.assertRegex(self.text, rf"leg: ipad\n\s+device_type: {re.escape(ios_sim.CI_IPAD_DEVICE_TYPE)}\n")

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
