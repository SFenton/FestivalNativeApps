"""Modal accessibility matrix (``journeys/a11y-modals.json``, issues #23, #239 and #400).

Every ``FestivalDialog`` caller has a matrix page that asserts its title and body text are on screen, its commands'
Narrator phrase (name, role, state), reading order (title, body, commands, Close last), Close's 40x40 epx target (with hit
probes 18.5 epx from its centre) and keyboard reach, and closes on Esc. ``ui_ci.py`` runs the pages in the ``windows-ui``
CI job at default text and at 225% text; this file only guards the page list's structure.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import re
import unittest
from pathlib import Path

from tools.windows import a11y_matrix as m
from tools.windows import ui_ci as ci
from tools.windows import uiwin as u

_REPO = Path(__file__).resolve().parents[3]
_FILE = _REPO / "tools" / "windows" / "journeys" / "a11y-modals.json"
_PAGES = json.loads(_FILE.read_text(encoding="utf-8"))
_APP = _REPO / "windows" / "Festival.App"
#: ``FestivalDialog.Create`` caller → its matrix pages (keep in step with ``ModalMarkupTests.ModalCallers_AreAllListed``).
_CALLERS = {
    "Controls/FeedbackDialog.cs": ("modal-feedback-bug", "modal-feedback-feature"),
    "Controls/FirstRunCarousel.xaml.cs": ("modal-first-run",),
    "Controls/PlayerProfileView.xaml.cs": ("modal-profile-switch", "modal-profile-deselect"),
    "Controls/PrivacyPolicyDialog.cs": ("modal-privacy-policy",),
    "Controls/SongPathsView.xaml.cs": ("modal-paths", "modal-paths-warning"),
    "MainWindow.WhatsNew.cs": ("modal-whats-new",),
    "Pages/LicensesPage.xaml.cs": ("modal-licenses",),
    "Pages/SettingsPage.xaml.cs": ("modal-settings-reset",),
}
#: The Karaoke notice is an alert with its own two choices and no Close (modal-shell R3 deviation, issue #239).
_ALERTS = {"modal-paths-warning"}
#: Hit probes at the edges of a 40x40 epx target (the hit-target journey's offsets, issue #271).
_PROBES = ("-18.5,0", "18.5,0", "0,-18.5", "0,18.5")


def _steps(page: dict) -> list[str]:
    """A page's steps in run order."""
    return [*page.get("setup", []), *page.get("ready", []), *page.get("after_ready", []), *page.get("teardown", [])]


def _close(page: dict) -> str:
    """The selector of a page's dismissing command (Close, Cancel or Dismiss), from its ``assertname`` step."""
    for step in page["ready"]:
        verb, _, rest = step.partition(":")
        sel, _, text = rest.partition("|")
        if verb == "assertname" and text in ("Close", "Cancel", "Dismiss"):
            return sel
    raise AssertionError(f"{page['name']}: no Close/Cancel/Dismiss assertname")


class ModalJourneyTests(unittest.TestCase):
    """The page list parses, runs in the CI matrix and covers every modal with each accessibility concern."""

    def test_runs_in_the_windows_ui_job(self):
        # ui_ci.RUNS is what the windows-ui workflow runs; every page must run in each of its modes and sizes.
        runs = [run for run in ci.RUNS if run.pages == _FILE.name]
        self.assertEqual({"normal", "text-225"}, {run.mode for run in runs})
        self.assertFalse((_FILE.parent / "modals.json").exists())
        for run in runs:
            self.assertTrue(run.scan and run.tabs >= 1, run.name)
            self.assertEqual(sorted(p["name"] for p in _PAGES), sorted(p["name"] for p in m.mode_pages(_PAGES, run.mode)))
            for page in _PAGES:
                self.assertEqual(run.sizes.split(","), m.page_sizes(page, run.sizes.split(","), run.mode), page["name"])

    def test_every_step_parses(self):
        for page in _PAGES:
            for step in m.page_steps(page, "medium", Path("C:/tmp"), "", True, 30):
                with self.subTest(page=page["name"], step=step):
                    u.parse_step(step)

    def test_text_is_on_screen_first(self):
        # waitfor fails while an element is missing or off screen: at 225% text the title and body must still show.
        for page in _PAGES:
            with self.subTest(page=page["name"]):
                first = page["after_ready"][0]
                self.assertTrue(first.startswith("waitfor:"), first)
                if page["name"] != "modal-whats-new":  # its title is the versioned list name; the section is the text
                    self.assertTrue(first.startswith("waitfor:name="), first)

    def test_every_dialog_caller_has_pages(self):
        callers = sorted(
            path.relative_to(_APP).as_posix() for path in _APP.rglob("*.cs")
            if not path.relative_to(_APP).as_posix().startswith(("bin/", "obj/"))
            and path.name != "FestivalDialog.cs" and re.search(r"FestivalDialog\.Create\(", path.read_text(encoding="utf-8")))
        self.assertEqual(sorted(_CALLERS), callers)
        names = [page["name"] for page in _PAGES]
        self.assertEqual(sorted(name for pages in _CALLERS.values() for name in pages), sorted(names))
        self.assertEqual(len(names), len(set(names)))

    def test_close_is_named_ordered_sized_and_keyboard_reachable(self):
        for page in _PAGES:
            if page["name"] in _ALERTS:
                continue
            with self.subTest(page=page["name"]):
                close, steps = _close(page), _steps(page)
                self.assertTrue(any(s.startswith(f"assertread:{close}|") and s.endswith(", button") for s in steps))
                orders = [s for s in steps if s.startswith("assertorder:")]
                self.assertTrue(orders and all(s.split("|")[-1].split("@")[0] == close for s in orders))
                # Read first: the dialog title (What's New: its list, named like the versioned title).
                self.assertTrue(any(s.startswith(("assertorder:name=", "assertorder:id=fst.whats-new.list|"))
                                    for s in orders))
                self.assertIn(f"assertsize:{close}|40x40", steps)
                self.assertEqual([f"assertat:{close}|{p}" for p in _PROBES], [s for s in steps if s.startswith(f"assertat:{close}|")])
                keyed = max(i for i, s in enumerate(steps) if s.startswith(f"assertfocus:{close}@"))
                self.assertTrue(steps[keyed - 1].startswith("key:tab"))

    def test_alert_choices_are_named_ordered_and_sized(self):
        page = next(p for p in _PAGES if p["name"] == "modal-paths-warning")
        steps = _steps(page)
        for button in ("id=PrimaryButton", "id=SecondaryButton"):
            self.assertTrue(any(s.startswith(f"assertread:{button}|") for s in steps))
            self.assertIn(f"assertsize:{button}|40x40", steps)
            self.assertEqual([f"assertat:{button}|{p}" for p in _PROBES], [s for s in steps if s.startswith(f"assertat:{button}|")])
        self.assertIn("assertorder:name=Some Instruments Unavailable|id=PrimaryButton|id=SecondaryButton", steps)
        self.assertIn("waitgone:id=CloseButton@2", steps)

    def test_esc_closes_and_restores_focus(self):
        for page in _PAGES:
            with self.subTest(page=page["name"]):
                self.assertEqual("key:esc", page["teardown"][0])
                if page["name"] not in ("modal-first-run", "modal-profile-deselect"):
                    self.assertTrue(any(s.startswith("assertfocus:") for s in page["teardown"]))

    def test_first_run_uses_the_shared_close_id(self):
        # Issue #244 gave the First Run Close the Apple/Android test ID; the template's CloseButton ID no longer exists.
        page = next(p for p in _PAGES if p["name"] == "modal-first-run")
        self.assertEqual("id=fst.first-run.close", _close(page))
        self.assertNotIn("assertname:id=CloseButton|Close", page["ready"])


if __name__ == "__main__":
    unittest.main()
