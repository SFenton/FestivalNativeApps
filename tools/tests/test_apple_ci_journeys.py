"""``apple-ci``'s iPhone and iPad simulator journeys: every selector names a real XCUITest method.

A selector that matches nothing makes ``xcodebuild`` run no test, so a renamed journey would silently leave CI.
The ``JOURNEYS`` blocks (iPhone UI-test bundle, on the iPhone and the iPad) must keep the account-button
reading-order journeys (``page-tools-and-nav-chrome`` R17, #394), the Songs section-title AX5 journey (#91, #441), the
Songs section-push AX XXXL journey (#288, #452), the Songs large-title rest journeys on both scroll-reading paths (#560),
the What's New AX5 journeys (#434: iPhone portrait, iPad portrait and landscape), the pinned caption-icon journeys (``song-header`` R4, #542)
and the drawer's Reduce Motion and closing journeys (#489, iPhone only); ``HISTORY_JOURNEYS``/``HISTORY_IPAD_JOURNEYS``
(iPad bundle, on the iPhone and the iPad) must keep the Score History AX5 journeys (#385, the region #302 changed);
``PLAIN_JOURNEYS`` (iPhone bundle, on the iPhone in the plain-fixture step) must keep the Filter Invalid Scores score-check
journey (#615) and the Songs deselect-reset accessibility journeys (#487, the region #359 changed); ``UNPINNED_JOURNEYS``
(iPhone bundle, on its own unpinned listener) must keep the player profile's pause-notice AX5 journey (#446, the region
#97 changed); ``RIVAL_JOURNEYS`` (iPhone bundle, on an iPad, an iPhone and a folded iPhone Duo) must keep the Rival
Detail frozen-state journeys (#444, the region #95 changed). The Songs Filter journeys (#432) must run on the iPhone,
the iPad and the folded iPhone Duo on release-branch dispatches, gated by the required ``apple-ci`` job.
The scroll-edge fade journeys (#462: the sheet header and every R9 board on the iPhone and the iPad, the Duo windows
on the iPhone; ``SCROLL_EDGE_JOURNEYS``/``SCROLL_EDGE_IPAD_JOURNEYS``) run in their own gated job, likewise, and the
iPad and Rival Detail journeys in the gated ``ipad-journeys`` job beside the build job (#636).
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
    "SCROLL_EDGE_JOURNEYS": UITESTS,
    "SCROLL_EDGE_IPAD_JOURNEYS": UITESTS,
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
        # The folded Duo runs the Filter sheet's methods in a leg of their own (#620: one AX5 method took up to
        # 27 min on the runner) and its bottom-field and scrim journeys in another.
        self.assertEqual(set(self.legs), {"iphone", "ipad", "duo-folded-filter", "duo-folded"})
        for leg in ("iphone", "ipad", "duo-folded-filter"):
            for journey in FILTER_JOURNEYS:
                self.assertIn(journey, self.legs[leg], leg)
        self.assertTrue(self.legs["duo-folded"])
        self.assertTrue(all("Duo" in journey for journey in self.legs["duo-folded"]))
        self.assertIn("SongsFilterKeyboardJourneyTests/testCommandPeriodClosesFilter", self.legs["ipad"])
        self.assertRegex(self.workflow, r"leg: ipad\n\s+device_type: iPad[^\n]*\n\s+uitest_args: --app ipad\n")
        for leg in ("duo-folded-filter", "duo-folded"):
            self.assertRegex(self.workflow, rf"leg: {leg}\n\s+device_type: iPhone Duo\n\s+uitest_args: --pose folded\n")
        self.assertIn("--fail-on-skip", self.workflow.split("songs-filter-journeys:", 1)[1])

    def test_songs_filter_legs_retry_a_failed_batch_once(self) -> None:
        legs = self.workflow.split("songs-filter-journeys:", 1)[1].split("\n  apple-ci:", 1)[0]
        self.assertIn("--retries 1", legs)
        # Every release-suite job retries a failed batch once (2610.12: one flaky journey a day blocked iOS).
        self.assertNotIn("--fail-on-skip --timeout", self.workflow.replace("--fail-on-skip --retries 1", ""),
                         "every --fail-on-skip journey call also passes --retries 1")

    def test_songs_filter_legs_skip_failure_diagnostics(self) -> None:
        # A failure's diagnostics take up to 600 s; the folded Duo leg's runner was lost during its journeys (#620).
        legs = self.workflow.split("songs-filter-journeys:", 1)[1].split("\n  scroll-edge-journeys:", 1)[0]
        self.assertIn("--no-test-diagnostics", legs)

    def test_every_journey_run_reboots_a_wedged_simulator(self) -> None:
        # A hung accessibility server failed 33 later batches before any test ran (#620).
        header = self.workflow.split("\njobs:", 1)[0]
        self.assertIn('FST_UITEST_REBOOT_WEDGED: "1"', header)

    def test_songs_filter_legs_run_only_on_release_dispatch(self) -> None:
        # Release train: pull requests and master run the build and unit tests only.
        legs = self.workflow.split("  songs-filter-journeys:", 1)[1].split("    strategy:", 1)[0]
        self.assertIn("if: github.event_name == 'workflow_dispatch'", legs)

    def test_required_check_needs_every_job(self) -> None:
        required = self.workflow.split("\n  apple-ci:\n", 1)[1]
        self.assertIn("name: apple-ci\n", required)
        self.assertIn("needs: [build, ipad-journeys, songs-filter-journeys, scroll-edge-journeys]", required)
        self.assertIn("if: always()", required)
        job_names = re.findall(r"^    name: (.+)$", self.workflow, flags=re.MULTILINE)
        self.assertEqual(job_names.count("apple-ci"), 1, "only the gate job is named apple-ci")
        jobs = re.findall(r"^  ([a-z][\w-]*):$", self.workflow.split("\njobs:\n", 1)[1], flags=re.MULTILINE)
        self.assertEqual(sorted(jobs), sorted(["build", "ipad-journeys", "songs-filter-journeys", "scroll-edge-journeys",
                                               "apple-ci"]),
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
            # Each journey job alone decides the gate when the others passed or were not due.
            other = "success" if event == "workflow_dispatch" else "skipped"
            for ipad, filter_legs, scroll_edge in (
                (journeys, other, other), (other, journeys, other), (other, other, journeys)
            ):
                env = {"EVENT": event, "BUILD": build, "IPAD": ipad, "JOURNEYS": filter_legs,
                       "SCROLL_EDGE": scroll_edge, "PATH": "/usr/bin:/bin"}
                result = subprocess.run(["bash", "-e", "-c", script], env=env, capture_output=True, check=False)
                self.assertEqual(result.returncode == 0, passes, (event, build, ipad, filter_legs, scroll_edge))

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

        # The build job's plain-fixture and iPad steps, and the scroll-edge job (#462).
        self.assertEqual(self.workflow.count(f'ci-device --type "{ios_sim.CI_IPAD_DEVICE_TYPE}"'), 3)
        self.assertRegex(self.workflow, rf"leg: ipad\n\s+device_type: {re.escape(ios_sim.CI_IPAD_DEVICE_TYPE)}\n")

    def test_score_history_ax5_journeys_run_on_iphone_and_ipad(self) -> None:
        page = "ScoreHistoryAccessibilityJourneyTests/testScoreHistoryPageAtAX5"
        split = "ScoreHistoryAccessibilityJourneyTests/testScoreHistorySplitPaneAtAX5"
        self.assertEqual(self.history["HISTORY_JOURNEYS"], [page], "the iPhone run: the page only (the split skips)")
        # #478: the song board's split-pane title (#342) at AX5 rides the iPad run; it skips on the iPhone.
        board = "SongBoardSplitAccessibilityJourneyTests/testSongBoardSplitTitleAtAX5"
        # #492: Song Detail's Duos link beside its band board (#367) at AX5; iPad only, like the #478 journey.
        band = "SongBandBoardSplitAccessibilityJourneyTests/testSongBandBoardSplitLinkAtAX5"
        # #490: Song Detail's first instrument-card row (#365) needs two card columns, so it rides the iPad run only.
        cards = "SongDetailCardRowAccessibilityJourneyTests/testInstrumentCardRowAtAX5"
        # #480: the split band (#344) under Increase Contrast at AX5; asserted in test_split_band_journey_runs_on_the_ipad.
        split_band = "IPadShellAccessibilityTests/testSplitBandStaysOutOfTheTreeUnderIncreaseContrastAtAX5"
        self.assertEqual(self.history["HISTORY_IPAD_JOURNEYS"], [page, split, board, band, cards, split_band])
        self.assertEqual(self.workflow.count("uitest --app ipad"), 2)
        # iPhone journeys, the unpinned profile-notice run (#446), two Score History runs, the plain-fixture iPhone run
        # (#615), the iPad journeys, the iPad keyboard batches (#473, #442), the Rival Detail device loop (#444), the
        # Songs Filter legs (#432) and the scroll-edge job's iPhone and iPad runs (#462).
        self.assertEqual(self.workflow.count("--fail-on-skip"), 12)

    def test_split_band_journey_runs_on_the_ipad(self) -> None:
        # #480: the iPad's split band (#344) at AX5 under Increase Contrast, with Close's 44 pt hit region.
        journey = "IPadShellAccessibilityTests/testSplitBandStaysOutOfTheTreeUnderIncreaseContrastAtAX5"
        self.assertIn(journey, self.history["HISTORY_IPAD_JOURNEYS"])
        self.assertNotIn(journey, self.history["HISTORY_JOURNEYS"])

    def test_duo_split_band_journeys_run_on_the_landscape_ipad(self) -> None:
        # #480: the iPhone Duo's flat-midpoint and book-hinge bands (#344). A split needs a 720 pt landscape window:
        # the portrait iPhone skips them (--fail-on-skip) and the CI Duo is folded only, so the iPhone bundle runs
        # them on the iPad with the Debug Duo window simulation.
        iphone, ipad = self.blocks
        for method in (
            "testFlatMidpointBandIsAccessibleAtAX5WithMoreContrastDuoUnfolded",
            "testBookHingeBandIsAccessibleAtAX5WithMoreContrastDuoBook",
        ):
            journey = f"DuoSplitBandAccessibilityJourneyTests/{method}"
            self.assertIn(journey, ipad)
            self.assertNotIn(journey, iphone)

    def test_invalid_score_filter_journey_runs_on_the_plain_fixture(self) -> None:
        # #615: the only device evidence for the Filter sheet's score checks under Filter Invalid Scores. It needs
        # `fixture-pulse` and `fixture-orbit` on screen, which the large catalogue pushes below the fold.
        journey = "SongsJourneyTests/testPlayerScoreFilterSettingsPauseAndDeselectScope"
        self.assertEqual(ci_journeys(self.workflow, "PLAIN_JOURNEYS")[0], journey)
        self.assertNotIn(journey, self.journeys)
        self.assertIn('uitest --app phone --device "$iphone"', self.workflow)

    def test_deselect_reset_journeys_run_on_the_plain_fixture(self) -> None:
        # #487: device evidence for Songs' reset tools after a deselect (#359), default and AX5. They read the
        # first rows' order, so they need `fixture-pulse` and `fixture-orbit` on screen like #615's journey.
        expected = [
            "SongsDeselectAccessibilityJourneyTests/testDeselectResetsSongsToolsForVoiceOver",
            "SongsDeselectAccessibilityJourneyTests/testDeselectResetIsReachableAtLargestText",
        ]
        plain = ci_journeys(self.workflow, "PLAIN_JOURNEYS")
        for journey in expected:
            self.assertIn(journey, plain)
            self.assertNotIn(journey, self.journeys)

    def test_search_title_journeys_run_on_the_plain_fixture(self) -> None:
        # #611: the Search tab's no-empty-band title assertions and their AX5 audit. They need `fixture-pulse` and
        # band search from this revision's plain fixture, whose origin they read from `FST_FIXTURE_URL`.
        plain = ci_journeys(self.workflow, "PLAIN_JOURNEYS")
        for journey in (
            "GlobalSearchJourneyTests/testSearchTabFocusesFieldAndCloseReturnsToSongs",
            "GlobalSearchJourneyTests/testSearchTitleSitsInBarRowAtLargestText",
        ):
            self.assertIn(journey, plain)
            self.assertNotIn(journey, self.journeys)
        source = (ROOT / "apple/Apps/iOSUITests/GlobalSearchJourneyTests.swift").read_text()
        self.assertIn('environment["FST_FIXTURE_URL"]', source)

    def test_search_spinner_journey_runs_on_the_plain_fixture(self) -> None:
        # #624: the only iPhone-device evidence that Search's spinner is one named native busy indicator centred in
        # the result region (load-transition R13). It needs the fixture's delayed `slowpoke` account search.
        journey = "GlobalSearchJourneyTests/testSearchingSpinnerIsCentredBelowScopeBar"
        self.assertIn(journey, ci_journeys(self.workflow, "PLAIN_JOURNEYS"))
        self.assertNotIn(journey, self.journeys)

    def test_board_footer_fade_keyboard_journey_runs_in_ci(self) -> None:
        # #473: the iPad hardware-keyboard form needs its own invocation, because --a11y applies to a whole run;
        # #665: its budget is per key press (~120 s each under full keyboard access on the runner).
        self.assertIn(
            "--a11y full-keyboard-access --fail-on-skip --retries 1 \\\n"
            "            --timeout 2400 --only BoardFooterFadeJourneyTests/testBoardKeyboardFocusClearsFooter",
            self.workflow,
        )

    def test_ipad_whats_new_batches_outlast_a_cold_simulator(self) -> None:
        # The first iPad batch runs on a just-created simulator: >900 s on slow runners (runs 37924278904, 37942308616).
        step = self.workflow.split("name: iPad simulator journeys", 1)[1].split("\n      - name:", 1)[0]
        timeout = re.search(r"--batch-size 1 --fail-on-skip --retries 1 --timeout (\d+)", step)
        self.assertIsNotNone(timeout, "iPad step runs one selector per batch with a timeout")
        self.assertGreaterEqual(int(timeout.group(1)), 1500)

    def test_ipad_and_rival_detail_journeys_run_beside_the_build_job(self) -> None:
        # #636: with them the build job needed about 7 h on the runner, past its limit and the hosted 6 h cap.
        build = self.workflow.split("\n  build:\n", 1)[1].split("\n  ipad-journeys:\n", 1)[0]
        ipad = self.workflow.split("\n  ipad-journeys:\n", 1)[1].split("\n  songs-filter-journeys:\n", 1)[0]
        for moved in ("name: iPad simulator journeys", "name: Rival Detail accessibility journeys",
                      "HISTORY_IPAD_JOURNEYS: >-"):
            self.assertNotIn(moved, build)
            self.assertIn(moved, ipad)
        for job in (build, ipad):
            self.assertLessEqual(int(re.search(r"\n    timeout-minutes: (\d+)", job).group(1)), 360)
        # A failure's simulator diagnostics took 600 s of the build job's time in the plain-fixture step (#636).
        for name in ("Plain-fixture journeys, iPhone", "Plain-fixture journeys, iPad"):
            step = self.workflow.split(f"name: {name}", 1)[1].split("\n      - name:", 1)[0]
            self.assertEqual(step.count("--no-test-diagnostics"), step.count("ios_sim.py uitest"), name)

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
        for clause in ("!cancelled()", "steps.project.outcome == 'success'"):
            # An earlier journey step's failure must not skip it, but a failed setup step does.
            self.assertIn(clause, condition.group(1))
        job = self.workflow.split("\n  ipad-journeys:\n", 1)[1].split("\n  songs-filter-journeys:\n", 1)[0]
        # Release-train only, like the other journeys, in the job beside the build job (#636).
        self.assertIn("if: github.event_name == 'workflow_dispatch'", job.split("    steps:", 1)[0])
        self.assertIn("name: Rival Detail accessibility journeys", job)
        self.assertIn("\n        id: project\n", job)

    def test_page_tools_keyboard_journey_runs_in_ci(self) -> None:
        # #442 (for #89): hardware-keyboard focus on Songs' page tools, its own --a11y invocation.
        self.assertIn(
            "--a11y full-keyboard-access --fail-on-skip --retries 1 \\\n"
            "            --timeout 900 --only PageToolsSearchFieldJourneyTests/testPageToolsAreInTheKeyboardFocusGroupAndOperable",
            self.workflow,
        )

    def test_page_tools_journeys_run_on_iphone_duo_and_ipad(self) -> None:
        # #442 (for #89): tools apart from the Filter Songs field and a one-icon Quick Links, at default size and
        # AX5, on iPhone, the simulated folded Duo (iPhone only: it skips on iPad) and iPad.
        iphone, ipad = self.blocks
        journey = "PageToolsSearchFieldJourneyTests/"
        shared = [
            "testSongsToolsSitApartFromTheFilterField",
            "testSongsToolsSitApartFromTheFilterFieldAtAX5",
            "testLeaderboardsQuickLinksIsOneIconButton",
        ]
        duo = [
            "testSongsToolsSitApartFromTheFilterFieldDuoFolded",
            "testSongsToolsSitApartFromTheFilterFieldAtAX5DuoFolded",
            "testLeaderboardsQuickLinksIsOneIconButtonDuoFolded",
        ]
        for method in shared:
            self.assertIn(journey + method, iphone)
            self.assertIn(journey + method, ipad)
        for method in duo:
            self.assertIn(journey + method, iphone)
            self.assertNotIn(journey + method, ipad)

    def test_song_detail_band_columns_ax5_journey_runs_on_ipad_only(self) -> None:
        # #491 (for #366): Duos and Trios pair only in a wide landscape window; the iPhone skips (portrait).
        iphone, ipad = self.blocks
        journey = "SongDetailBandColumnsJourneyTests/testBandPreviewColumnsAreAccessibleAtLargestText"
        self.assertIn(journey, ipad)
        self.assertNotIn(journey, iphone)

    def test_section_title_ax5_journey_runs_in_ci(self) -> None:
        # #91/#441: the only iOS Dynamic Type and audit evidence for Songs' grouped-sort section titles.
        self.assertIn("SongsJourneyTests/testSongsShopSortSectionTitlesAreAccessibleAtAX5", self.journeys)

    def test_scroll_edge_journeys_run_on_iphone_and_ipad(self) -> None:
        # #462: the iOS evidence for scroll-edge R1, R7 and R9 (sheet header and every pager board), in its own job
        # with its own `--large-rankings` fixture on 8766, gated by the required check like the Songs Filter legs.
        job = self.workflow.split("\n  scroll-edge-journeys:\n", 1)[1].split("\n  apple-ci:\n", 1)[0]
        self.assertIn("if: github.event_name == 'workflow_dispatch'", job.split("    steps:", 1)[0])
        self.assertIn("mock_service.py --large-rankings --port 8766", job)
        self.assertIn("--fail-on-skip", job)
        self.assertIn("--retries 1", job)
        self.assertIn('ci-device --type "iPad Pro 11-inch (M5)"', job)
        (iphone,) = ci_journey_blocks(self.workflow, "SCROLL_EDGE_JOURNEYS")
        (ipad,) = ci_journey_blocks(self.workflow, "SCROLL_EDGE_IPAD_JOURNEYS")
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
        # The build job neither runs them nor starts their fixture.
        build = self.workflow.split("\n  build:\n", 1)[1].split("\n  songs-filter-journeys:\n", 1)[0]
        self.assertNotIn(cls, build)
        self.assertNotIn("--port 8766", build)

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

    def test_drawer_motion_journeys_run_on_the_iphone(self) -> None:
        # #489 (for #362): the only iOS evidence that the Reduce Motion drawer audits clean and that closing hands
        # the page back to VoiceOver and touch before the sequence ends. The drawer is phone-only, and the Duo
        # window is simulated on an iPhone, so none runs in the iPad step.
        iphone, ipad = self.blocks
        for method in (
            "testReduceMotionDrawerPassesAccessibilityAudit",
            "testClosingDrawerHandsThePageBackAtOnce",
            "testClosingDrawerHandsThePageBackAtOnceDuoFolded",
        ):
            self.assertIn(f"DrawerAccessibilityJourneyTests/{method}", iphone)
            self.assertNotIn(f"DrawerAccessibilityJourneyTests/{method}", ipad)

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
