"""``apple-ci``'s iPhone and iPad simulator journeys: every selector names a real XCUITest method.

A selector that matches nothing makes ``xcodebuild`` run no test, so a renamed journey would silently leave CI.
The ``JOURNEYS`` blocks (iPhone UI-test bundle, on the iPhone and the iPad) must keep the account-button
reading-order journeys (``page-tools-and-nav-chrome`` R17, #394), the Songs section-title AX5 journey (#91, #441), the
Songs section-push AX XXXL journey (#288, #452), the Songs large-title rest journeys on both scroll-reading paths (#560),
the What's New AX5 journeys (#434: iPhone portrait, iPad portrait and landscape) and the pinned caption-icon journeys (``song-header`` R4, #542); ``HISTORY_JOURNEYS``/``HISTORY_IPAD_JOURNEYS``
(iPad bundle, on the iPhone and the iPad) must keep the Score History AX5 journeys (#385, the region #302 changed);
``PLAIN_JOURNEYS`` (iPhone bundle, on the iPhone in the plain-fixture step) must keep the Filter Invalid Scores score-check
journey (#615); ``UNPINNED_JOURNEYS`` (iPhone bundle, on its own unpinned listener) must keep the player
profile's pause-notice AX5 journey (#446, the region #97 changed); ``RIVAL_JOURNEYS`` (iPhone bundle, on an iPad, an
iPhone and a folded iPhone Duo) must keep the Rival Detail frozen-state journeys (#444, the region #95 changed). The
Songs Filter journeys (#432) must run on the iPhone, the iPad and the folded iPhone Duo on release-branch dispatches,
gated by the required ``apple-ci`` job.
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

#: Folded selector block names in ``apple-ci.yml`` and the UI-test bundle each runs.
BLOCKS = {
    "JOURNEYS": UITESTS,
    "PLAIN_JOURNEYS": UITESTS,
    "HISTORY_JOURNEYS": IPAD_UITESTS,
    "HISTORY_IPAD_JOURNEYS": IPAD_UITESTS,
    "UNPINNED_JOURNEYS": UITESTS,
    "RIVAL_JOURNEYS": UITESTS,
}


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


def matrix_legs(text: str) -> dict[str, list[str]]:
    """Read the Songs Filter journey matrix: each ``leg`` with its ``journeys`` block.

    Args:
        text: The workflow source.

    Returns:
        Leg name → selectors.
    """
    legs = re.findall(r"^\s*- leg: (\S+)$", text, flags=re.MULTILINE)
    blocks = ci_journey_blocks(text, "journeys")
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
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.journeys = ci_journeys(self.workflow)
        self.blocks = ci_journey_blocks(self.workflow)
        self.history = {key: ci_journeys(self.workflow, key) for key in ("HISTORY_JOURNEYS", "HISTORY_IPAD_JOURNEYS")}
        self.legs = matrix_legs(self.workflow)

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
        self.assertEqual(ci_journeys(sample.replace("JOURNEYS", "HISTORY_JOURNEYS"), "HISTORY_JOURNEYS"), ["A/a", "B/b"])

    def test_reads_matrix_legs(self) -> None:
        sample = (
            "          - leg: one\n            journeys: >-\n              A/a\n"
            "          - leg: two\n            journeys: >-\n              B/b\n              C/c\n    steps:\n"
        )
        self.assertEqual(matrix_legs(sample), {"one": ["A/a"], "two": ["B/b", "C/c"]})

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
        self.assertRegex(self.workflow, r"leg: ipad\n\s+device_type: iPad[^\n]*\n\s+uitest_args: --app ipad\n")
        self.assertRegex(self.workflow, r"leg: duo-folded\n\s+device_type: iPhone Duo\n\s+uitest_args: --pose folded\n")
        self.assertIn("--fail-on-skip", self.workflow.split("songs-filter-journeys:", 1)[1])

    def test_songs_filter_legs_retry_a_failed_batch_once(self) -> None:
        legs = self.workflow.split("songs-filter-journeys:", 1)[1].split("\n  apple-ci:", 1)[0]
        self.assertIn("--retries 1", legs)
        self.assertNotIn("--retries", self.workflow.split("songs-filter-journeys:", 1)[0])

    def test_songs_filter_legs_run_only_on_release_dispatch(self) -> None:
        # Release train: pull requests and master run the build and unit tests only.
        legs = self.workflow.split("  songs-filter-journeys:", 1)[1].split("    strategy:", 1)[0]
        self.assertIn("if: github.event_name == 'workflow_dispatch'", legs)

    def test_required_check_needs_every_job(self) -> None:
        required = self.workflow.split("\n  apple-ci:\n", 1)[1]
        self.assertIn("name: apple-ci\n", required)
        self.assertIn("needs: [build, songs-filter-journeys]", required)
        self.assertIn("if: always()", required)
        job_names = re.findall(r"^    name: (.+)$", self.workflow, flags=re.MULTILINE)
        self.assertEqual(job_names.count("apple-ci"), 1, "only the gate job is named apple-ci")
        jobs = re.findall(r"^  ([a-z][\w-]*):$", self.workflow.split("\njobs:\n", 1)[1], flags=re.MULTILINE)
        self.assertEqual(sorted(jobs), sorted(["build", "songs-filter-journeys", "apple-ci"]),
                         "a new job must join the gate's needs")

    def test_gate_passes_only_when_every_job_passed_or_the_legs_are_not_due(self) -> None:
        script = self.gate_script()
        cases = {
            ("workflow_dispatch", "success", "success"): True,
            ("pull_request", "success", "skipped"): True,
            ("push", "success", "skipped"): True,
            ("workflow_dispatch", "success", "skipped"): False,
            ("workflow_dispatch", "success", "failure"): False,
            ("workflow_dispatch", "success", "cancelled"): False,
            ("pull_request", "success", "cancelled"): False,
            ("pull_request", "failure", "skipped"): False,
            ("workflow_dispatch", "failure", "success"): False,
        }
        for (event, build, journeys), passes in cases.items():
            env = {"EVENT": event, "BUILD": build, "JOURNEYS": journeys, "PATH": "/usr/bin:/bin"}
            result = subprocess.run(["bash", "-e", "-c", script], env=env, capture_output=True, check=False)
            self.assertEqual(result.returncode == 0, passes, (event, build, journeys))

    def gate_script(self) -> str:
        """The gate job's ``run`` script, dedented from its ``run: |`` block."""
        gate = self.workflow.split("\n  apple-ci:\n", 1)[1]
        block = gate.split("        run: |\n", 1)[1]
        return "\n".join(line[10:] for line in block.splitlines() if line.startswith("          "))

    def test_mac_keyboard_tests_run_alone_and_required(self) -> None:
        step = self.workflow.split("Mac keyboard navigation tests, alone", 1)[1].split("- name:", 1)[0]
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

    def test_ipad_steps_use_the_ipad_device_type(self) -> None:
        sys.path.insert(0, str(ROOT / "tools"))
        import ios_sim

        self.assertEqual(self.workflow.count(f'ci-device --type "{ios_sim.CI_IPAD_DEVICE_TYPE}"'), 2)
        self.assertRegex(self.workflow, rf"leg: ipad\n\s+device_type: {re.escape(ios_sim.CI_IPAD_DEVICE_TYPE)}\n")

    def test_score_history_ax5_journeys_run_on_iphone_and_ipad(self) -> None:
        page = "ScoreHistoryAccessibilityJourneyTests/testScoreHistoryPageAtAX5"
        split = "ScoreHistoryAccessibilityJourneyTests/testScoreHistorySplitPaneAtAX5"
        self.assertEqual(self.history["HISTORY_JOURNEYS"], [page], "the iPhone run: the page only (the split skips)")
        self.assertEqual(self.history["HISTORY_IPAD_JOURNEYS"], [page, split])
        self.assertEqual(self.workflow.count("uitest --app ipad"), 2)
        # iPhone journeys, the unpinned profile-notice run (#446), two Score History runs, the plain-fixture iPhone run
        # (#615), the iPad journeys and the iPad keyboard batch (#473), the Rival Detail device loop (#444) and the
        # Songs Filter legs (#432).
        self.assertEqual(self.workflow.count("--fail-on-skip"), 9)

    def test_invalid_score_filter_journey_runs_on_the_plain_fixture(self) -> None:
        # #615: the only device evidence for the Filter sheet's score checks under Filter Invalid Scores. It needs
        # `fixture-pulse` and `fixture-orbit` on screen, which the large catalogue pushes below the fold.
        journey = "SongsJourneyTests/testPlayerScoreFilterSettingsPauseAndDeselectScope"
        self.assertEqual(ci_journeys(self.workflow, "PLAIN_JOURNEYS"), [journey])
        self.assertNotIn(journey, self.journeys)
        self.assertIn('uitest --app phone --device "$iphone"', self.workflow)

    def test_board_footer_fade_keyboard_journey_runs_in_ci(self) -> None:
        # #473: the iPad hardware-keyboard form needs its own invocation, because --a11y applies to a whole run.
        self.assertIn(
            "--a11y full-keyboard-access --fail-on-skip \\\n"
            "            --timeout 900 --only BoardFooterFadeJourneyTests/testBoardKeyboardFocusClearsFooter",
            self.workflow,
        )

    def test_ipad_whats_new_batches_outlast_a_cold_simulator(self) -> None:
        # The first iPad batch runs on a just-created simulator: >900 s on slow runners (runs 37924278904, 37942308616).
        step = self.workflow.split("name: iPad simulator journeys", 1)[1].split("\n      - name:", 1)[0]
        timeout = re.search(r"--batch-size 1 --fail-on-skip --timeout (\d+)", step)
        self.assertIsNotNone(timeout, "iPad step runs one selector per batch with a timeout")
        self.assertGreaterEqual(int(timeout.group(1)), 1500)

    def test_rival_detail_frozen_journeys_run_on_every_touch_form_factor(self) -> None:
        # #444: the only device evidence for Rival Detail's frozen-service state (#95) on iPhone, iPad and Duo.
        sys.path.insert(0, str(ROOT / "tools"))
        import ios_sim

        rivals = ci_journeys(self.workflow, "RIVAL_JOURNEYS")
        for method in (
            "testFrozenRivalDetailNamesOrdersSizesAndGrowsItsRows",
            "testFrozenRivalDetailWithoutSnapshotOffersRetry",
        ):
            self.assertIn(f"RivalDetailFrozenAccessibilityJourneyTests/{method}", rivals)
        for device in (f'"{ios_sim.CI_IPAD_DEVICE_TYPE}|"', f'"{ios_sim.CI_DEVICE_TYPE}|"', '"iPhone Duo|folded"'):
            self.assertIn(device, self.workflow)
        step = self.workflow.split("name: Rival Detail accessibility journeys", 1)[1].split("\n      - name:", 1)[0]
        condition = re.search(r"\n        if: (.+)", step)
        self.assertIsNotNone(condition, "the step has a condition")
        for clause in ("github.event_name == 'workflow_dispatch'", "!cancelled()", "steps.unit.outcome == 'success'"):
            # Release-train only, like the other journeys; an earlier journey step's failure must not skip it,
            # but a failed build or unit-test step does.
            self.assertIn(clause, condition.group(1))
        self.assertIn("\n        id: unit\n", self.workflow.split("name: Swift unit tests", 1)[1].split("\n      - name:", 1)[0])

    def test_section_title_ax5_journey_runs_in_ci(self) -> None:
        # #91/#441: the only iOS Dynamic Type and audit evidence for Songs' grouped-sort section titles.
        self.assertIn("SongsJourneyTests/testSongsShopSortSectionTitlesAreAccessibleAtAX5", self.journeys)

    def test_section_push_ax5_journey_runs_in_ci(self) -> None:
        # #288/#452: the only iOS Dynamic Type and audit evidence for the Songs section push.
        self.assertIn("SongsChromeJourneyTests/testSectionPushIsAccessibleAtLargestText", self.journeys)

    def test_section_jump_ax5_journeys_run_in_ci(self) -> None:
        # #451 (for #286): the only iOS Dynamic Type and audit evidence for a Songs index jump's landing.
        iphone, ipad = self.blocks
        for method in ("testSectionJumpIsAccessibleAtLargestText", "testSectionJumpIsAccessibleAtLargestTextDuoFolded"):
            self.assertIn(f"SongsChromeJourneyTests/{method}", iphone)
        # The Duo window is simulated on an iPhone only; its selector skips on an iPad.
        self.assertIn("SongsChromeJourneyTests/testSectionJumpIsAccessibleAtLargestText", ipad)
        self.assertNotIn("SongsChromeJourneyTests/testSectionJumpIsAccessibleAtLargestTextDuoFolded", ipad)

    def test_large_title_rest_journeys_run_in_ci(self) -> None:
        # #560: the only device evidence that a programmatic scroll never rests part-way through the large title,
        # on the current scroll-geometry path and the forced iOS 17 `PlatformScrollObserver` path.
        for method in (
            "testProgrammaticScrollNeverRestsPartWayThroughTheLargeTitle",
            "testProgrammaticScrollNeverRestsPartWayOnTheLegacyScrollPath",
        ):
            self.assertIn(f"SongsChromeJourneyTests/{method}", self.journeys)

    def test_pinned_caption_icon_journeys_run_in_ci(self) -> None:
        for method in (
            "testSongLeaderboardCaptionIconScalesWithText",
            "testPlayerHistoryCaptionIconAtLargestText",
        ):
            self.assertIn(f"SongBarCaptionIconJourneyTests/{method}", self.journeys)

    def test_profile_notice_ax5_journey_runs_on_its_unpinned_listener(self) -> None:
        # #446/#97: the only real Dynamic Type evidence for the profile's pause notice (macOS has none).
        self.assertEqual(
            ci_journey_blocks(self.workflow, "UNPINNED_JOURNEYS"), [["ProfileNoticeTextSizeJourneyTests/testUnverifiedNoticeGrowsAndStaysWholeAtLargestText"]]
        )
        step = self.workflow.split("- name: iPhone unpinned-fixture journeys", 1)[1].split("- name:", 1)[0]
        self.assertIn("tools/mock_service.py --port 18446 --unpinned", step)
        self.assertIn("TEST_RUNNER_FST_PROFILE_NOTICE_FIXTURE_URL: http://127.0.0.1:18446", step)
        self.assertIn("--fail-on-skip", step)
        source = (UITESTS / "ProfileNoticeTextSizeJourneyTests.swift").read_text(encoding="utf-8")
        self.assertIn('?? "http://127.0.0.1:18446"', source)


if __name__ == "__main__":
    unittest.main()
