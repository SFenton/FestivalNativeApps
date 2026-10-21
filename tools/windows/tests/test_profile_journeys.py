"""Profile journeys (``journeys/profile.py``): step syntax, a Quick Links pick waits for its jump (issue #663), and a
failed phase records what happened to the app (issue #680).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root (CI: ``native.yml``).
"""

import importlib.util
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fade_journey  # noqa: E402  (sibling module)
import uiwin  # noqa: E402  (sibling module)

_PATH = Path(__file__).resolve().parents[1] / "journeys" / "profile.py"
_SPEC = importlib.util.spec_from_file_location("fst_profile_journeys", _PATH)
p = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = p
_SPEC.loader.exec_module(p)

MENU_PICK = re.compile(r"^toggle:id=(fst\.quick-links\.item\.[^@|]+)$")
TIMED = re.compile(r"@\d+(\.\d+)?$")


def quick_link_pick_errors(steps: list[str]) -> list[str]:
    """Returns why each Quick Links menu pick in ``steps`` isn't awaited by state.

    The menu jumps from a Low-priority dispatch after its flyout closes (#548), so the toggle returns before anything
    scrolls. A pick must be followed by ``waitgone`` on the picked item, then a timed ``assertstate`` that the button
    reports the new current section, never by a fixed ``wait:`` (``.agents/testing/windows.md``).
    """
    errors = []
    for i, step in enumerate(steps):
        match = MENU_PICK.match(step)
        if not match:
            continue
        after = steps[i + 1:i + 3]
        gone = f"waitgone:id={match.group(1)}@"
        if len(after) < 2 or not after[0].startswith(gone) or not TIMED.search(after[0]):
            errors.append(f"{step}: next step must be a timed {gone}N, got {after[:1]}")
        elif not (after[1].startswith("assertstate:id=fst.quick-links.open|name=")
                  and "current section " in after[1] and TIMED.search(after[1])):
            errors.append(f"{step}: must then assert the button's current section with @N, got {after[1]}")
    return errors


class ProfileJourneyStepTests(unittest.TestCase):
    def test_every_step_parses(self):
        for journey in p.JOURNEYS:
            for phase in journey.steps:
                for step in phase:
                    with self.subTest(journey=journey.name, step=step):
                        uiwin.parse_step(step)

    def test_quick_links_picks_wait_for_the_jump(self):
        picks = 0
        phases = [(j.name, phase) for j in p.JOURNEYS for phase in j.steps]
        phases += [(name, phase.steps) for name, s in fade_journey.SCENARIOS.items() for phase in s.phases]
        for name, phase in phases:
            picks += sum(1 for step in phase if MENU_PICK.match(step))
            with self.subTest(journey=name):
                self.assertEqual([], quick_link_pick_errors(phase))
        self.assertGreaterEqual(picks, 2)

    def test_statistics_quick_links_asserts_the_landing_after_the_jump_without_a_fixed_wait(self):
        steps = next(j for j in p.JOURNEYS if j.name == "statistics-quick-links").steps[0]
        toggle = steps.index("toggle:id=fst.quick-links.item.bands")
        landing = steps.index("assertinset:id=fst.player.bands-section|id=fst.player.available|32")
        self.assertEqual(["waitgone:id=fst.quick-links.item.bands@10",
                          "assertstate:id=fst.quick-links.open|name=Quick Links, current section Bands@10"],
                         steps[toggle + 1:landing])

    def test_the_guard_rejects_a_fixed_settle_wait(self):
        self.assertTrue(quick_link_pick_errors(["toggle:id=fst.quick-links.item.bands", "wait:1.5",
                                                "assertinset:id=a|id=b|32"]))
        self.assertTrue(quick_link_pick_errors(["toggle:id=fst.quick-links.item.bands",
                                                "waitgone:id=fst.quick-links.item.bands@10", "wait:1"]))
        self.assertEqual([], quick_link_pick_errors(
            ["toggle:id=fst.quick-links.item.bands", *fade_journey.QUICK_LINK_JUMPED]))


class ProfileJourneyFailureCaptureTests(unittest.TestCase):
    """A failed phase keeps a screenshot and UIA tree of the window as it failed (#676), and what happened to the app:
    exit code or hang, event-log crash records and its own ``diagnostics.log`` (#680)."""

    def run_failing(self, shots, work, state="exited with code 0xC000027B", events="", capture_code=0):
        calls = []

        def fake_uiwin(*args, check=True):
            calls.append(args)
            out = '{\n  "pid": 4242,\n}' if args[0] == "launch" else ""
            code = 1 if args[0] == "drive" else capture_code if args[0] in ("shot", "tree") else 0
            return p.subprocess.CompletedProcess(args, code, stdout=out, stderr="error: no on-screen element")

        journey = next(j for j in p.JOURNEYS if j.name == "history-anonymous")
        with mock.patch.object(p, "_uiwin", fake_uiwin), mock.patch.object(p, "_wait_for_port"), \
                mock.patch.object(p.subprocess, "Popen"), mock.patch.object(p.tempfile, "mkdtemp", return_value=str(work)), \
                mock.patch.object(p, "_hold", return_value=77) as hold, mock.patch.object(p, "_release") as release, \
                mock.patch.object(p, "_app_state", return_value=state) as app_state, \
                mock.patch.object(p, "_crash_events", return_value=events):
            failures = p.run(journey, Path("app.exe"), shots)
        hold.assert_called_once_with(4242)
        app_state.assert_called_with(4242, 77)
        release.assert_called_once_with(77)
        return failures, calls

    def test_a_failed_phase_captures_the_window(self):
        with tempfile.TemporaryDirectory() as tmp:
            shots = Path(tmp)
            failures, calls = self.run_failing(shots, shots / "work")
        self.assertEqual(["phase 0: error: no on-screen element", "phase 0: app: exited with code 0xC000027B"], failures)
        verbs = [c[0] for c in calls]
        self.assertEqual(["launch", "drive", "shot", "tree", "close"], verbs)
        self.assertEqual(("shot", "--pid", "4242", str(shots / "history-anonymous-0-failed.png")), calls[2])
        self.assertEqual(("tree", "--pid", "4242", str(shots / "history-anonymous-0-failed.txt")), calls[3])

    def test_without_shots_nothing_is_captured(self):
        with tempfile.TemporaryDirectory() as tmp:
            failures, calls = self.run_failing(None, Path(tmp), state="running; window not responding (hung)")
        self.assertEqual(["launch", "drive", "close"], [c[0] for c in calls])
        self.assertEqual("phase 0: app: running; window not responding (hung)", failures[-1])

    def test_the_app_keeps_its_data_beside_the_settings(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            _, calls = self.run_failing(None, work)
        launch = calls[0]
        self.assertEqual(f"FST_DEBUG_DATA_DIR={work / 'data'}", launch[launch.index("--extra") + 1])
        self.assertIn(f"--arg={work / 'settings.json'}", launch)

    def test_the_failure_report_keeps_the_crash_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            shots, work = Path(tmp) / "shots", Path(tmp) / "work"
            shots.mkdir()
            (work / "data").mkdir(parents=True)
            (work / "data" / "diagnostics.log").write_text("2026-10-19T14:49:44Z Catastrophic failure\nCOMException",
                                                           encoding="utf-8")
            self.run_failing(shots, work, events="Event[0]:\n  Source: Application Error\n  FestivalScoreTracker.exe",
                             capture_code=1)
            report = (shots / "history-anonymous-0-failed-app.txt").read_text(encoding="utf-8")
        self.assertTrue(report.startswith("app: exited with code 0xC000027B\n"))
        self.assertIn("shot failed: error: no on-screen element", report)
        self.assertIn("tree failed: error: no on-screen element", report)
        self.assertIn("Source: Application Error", report)
        self.assertIn("diagnostics.log:\n2026-10-19T14:49:44Z Catastrophic failure\nCOMException", report)

    def test_the_failure_report_says_when_nothing_was_recorded(self):
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(p, "_app_state", return_value="running; window responding"), \
                    mock.patch.object(p, "_crash_events", return_value=""):
                report = p._failure_report(4242, Path(tmp), 0.0, {})
        self.assertEqual("app: running; window responding\napplication event log:\n(no entries for the app)\n"
                         "diagnostics.log:\n(none)", report)


class ProfileJourneyCrashEventTests(unittest.TestCase):
    """The failure report keeps only the app's own event-log records (#680)."""

    def test_only_the_apps_events_are_kept(self):
        out = ("Event[0]:\n  Source: Application Error\n  Faulting application name: FestivalScoreTracker.exe\n"
               "Event[1]:\n  Source: Other\n  Description: something else\n")
        with mock.patch.object(p.sys, "platform", "win32"), \
                mock.patch.object(p.subprocess, "run", return_value=p.subprocess.CompletedProcess([], 0, stdout=out)) as run:
            events = p._crash_events(p.time.time() - 30)
        self.assertEqual("Event[0]:\n  Source: Application Error\n  Faulting application name: FestivalScoreTracker.exe",
                         events)
        command = run.call_args.args[0]
        self.assertEqual(["wevtutil", "qe", "Application"], command[:3])
        self.assertTrue(any(a.startswith("/q:*[System[TimeCreated[timediff(@SystemTime) <= ") for a in command))

    @unittest.skipUnless(sys.platform == "win32", "Windows process APIs")
    def test_a_missing_process_is_reported_gone(self):
        self.assertEqual("gone (no process with that pid)", p._app_state(0x7FFFFFFC))

    @unittest.skipUnless(sys.platform == "win32", "Windows process APIs")
    def test_a_held_process_keeps_its_exit_code_and_time(self):
        child = p.subprocess.Popen([sys.executable, "-c", "import ctypes; ctypes.windll.kernel32.ExitProcess(0xC000027B)"])
        handle = p._hold(child.pid)
        try:
            self.assertIsNotNone(handle)
            child.wait(timeout=30)
            state = p._app_state(child.pid, handle)
        finally:
            p._release(handle)
        self.assertRegex(state, r"^exited with code 0xC000027B \d+\.\d s ago$")


if __name__ == "__main__":
    unittest.main()
