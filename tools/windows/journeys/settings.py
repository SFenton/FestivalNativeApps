#!/usr/bin/env python3
"""Settings page UI journeys for the Windows app, driven through ``tools/windows/uiwin.py``.

Each journey seeds an isolated settings file (no selected player, so anonymous), launches the app on Settings against the loopback
fixture service (``tools/mock_service.py``), runs UIA steps (``waitfor`` steps are assertions),
then checks the UIA tree dumped after each phase with regular expressions (so states such as
``[disabled]`` are asserted per control) and the values the app saved to the isolated
``settings.json``. A journey may relaunch the app on the same settings file to prove persistence.
Nothing touches production or the operator's real settings.

Usage (from the repository root, after ``tools/windows/build.ps1``)::

    python tools/windows/journeys/settings.py                    # all journeys
    python tools/windows/journeys/settings.py reset links        # by name
    python tools/windows/journeys/settings.py --shots out\\dir    # per-phase screenshots

Exit code 0 when every journey passes, 1 otherwise.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import journey_exe  # noqa: E402  (tools/windows module)


def _load_profile_helpers():
    """Load ``profile.py`` by path (its module name shadows the standard library's ``profile``)."""
    spec = importlib.util.spec_from_file_location("fst_profile_journeys", Path(__file__).with_name("profile.py"))
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module  # dataclasses resolve their module through sys.modules
    spec.loader.exec_module(module)
    return module


_helpers = _load_profile_helpers()
REPO = _helpers.REPO

# region Model


@dataclass
class Phase:
    """One ``drive`` call and its checks.

    Attributes:
        steps: Step strings run in one ``drive`` call.
        expect: Regular expressions that must each match a line of the UIA tree dumped after the steps.
        forbid: Regular expressions that must not match any line of that tree.
        saved: Predicates over the saved ``settings.json`` (name → check), evaluated after the steps.
        order: Regular expressions whose first matching tree lines must appear in this order (UIA/Narrator order).
    """

    steps: list[str]
    expect: list[str] = field(default_factory=list)
    forbid: list[str] = field(default_factory=list)
    saved: dict[str, Callable[[dict[str, Any]], bool]] = field(default_factory=dict)
    order: list[str] = field(default_factory=list)


@dataclass
class Journey:
    """One scripted Settings journey.

    Attributes:
        name: Short CLI name.
        phases: Drive phases.
        seed: Settings written before the first launch.
        relaunch: Phase index after which the app is closed and relaunched on the same settings file.
    """

    name: str
    phases: list[Phase]
    seed: dict[str, Any] = field(default_factory=dict)
    relaunch: int | None = None


def _id(automation_id: str) -> str:
    """Tree-line pattern for an AutomationId."""
    return rf"id={re.escape(automation_id)} "


def _disabled(automation_id: str) -> str:
    """Tree-line pattern for a disabled control with this AutomationId."""
    return rf"id={re.escape(automation_id)} .*\[[^\]]*disabled"


READY = "waitfor:id=fst.settings.show-instrument-icons@20"

JOURNEYS = [
    Journey(
        name="visual-order",
        phases=[
            Phase(["scrollinto:id=fst.settings.enable-visual-order", "toggle:id=fst.settings.enable-visual-order",
                   "wait:1", "scrollinto:id=fst.settings.song-row-order"],
                  expect=[_id("fst.settings.song-row-order"), r'"Score, position 1 of \d+"', r'"Move Score up".*\[[^\]]*disabled'],
                  saved={"enableVisualOrder on": lambda s: s.get("enableVisualOrder") is True}),
            Phase(["invoke:name=Move Score down", "wait:1"],
                  expect=[r'"Score, position 2 of \d+"'],
                  saved={"Score moved to second": lambda s: s.get("songRowVisualOrder", [None, None])[1] == "Score"}),
            Phase([READY, "scrollinto:id=fst.settings.song-row-order"],
                  expect=[r'"Score, position 2 of \d+"']),
        ],
        relaunch=1,
    ),
    Journey(
        name="filters",
        phases=[
            Phase(["scrollinto:id=fst.settings.filter-invalid-scores"],
                  forbid=[_id("fst.settings.leeway")]),
            Phase(["toggle:id=fst.settings.filter-invalid-scores", "wait:1", "scrollinto:id=fst.settings.leeway"],
                  expect=[_id("fst.settings.leeway")],
                  saved={"filterInvalidScores on": lambda s: s.get("filterInvalidScores") is True}),
            Phase(["scrollinto:id=fst.settings.hide-shop", "toggle:id=fst.settings.hide-shop", "wait:1"],
                  expect=[_disabled("fst.settings.shop-highlights")],
                  saved={"hideShop on": lambda s: s.get("hideShop") is True}),
            Phase([READY, "scrollinto:id=fst.settings.hide-shop"],
                  expect=[_id("fst.settings.leeway"), _disabled("fst.settings.shop-highlights")]),
        ],
        relaunch=2,
    ),
    Journey(
        name="instruments",
        seed={"visibleInstruments": ["Lead", "Bass"]},
        phases=[
            Phase(["scrollinto:id=fst.settings.hide-shop", "wait:0.5", "scrollinto:id=fst.settings.instrument.Solo_Bass"],
                  forbid=[_disabled("fst.settings.instrument.Solo_Guitar")]),
            Phase(["toggle:id=fst.settings.instrument.Solo_Bass", "wait:1"],
                  expect=[_disabled("fst.settings.instrument.Solo_Guitar")],
                  saved={"only Lead visible": lambda s: s.get("visibleInstruments") == ["Lead"]}),
        ],
    ),
    Journey(
        name="diagnostics",
        phases=[
            Phase(["scrollinto:id=fst.settings.tap-diagnostics"],
                  expect=[_disabled("fst.settings.tap-telemetry")]),
            Phase(["toggle:id=fst.settings.tap-diagnostics", "wait:1"],
                  forbid=[_disabled("fst.settings.tap-telemetry")],
                  saved={"tapDiagnostics on": lambda s: s.get("tapDiagnostics") is True}),
        ],
    ),
    Journey(
        name="reset",
        seed={"reduceMotion": True, "showInstrumentIcons": False, "songSort": "Artist"},
        phases=[
            Phase(["scrollinto:id=fst.settings.reset", "invoke:id=fst.settings.reset",
                   "waitfor:id=fst.settings.reset.dialog@5", "invoke:id=CloseButton",
                   "waitgone:id=fst.settings.reset.dialog@5", "wait:1"],
                  saved={"Cancel keeps settings": lambda s: s.get("reduceMotion") is True and s.get("showInstrumentIcons") is False}),
            Phase(["invoke:id=fst.settings.reset", "waitfor:id=fst.settings.reset.dialog@5", "invoke:id=PrimaryButton",
                   "waitgone:id=fst.settings.reset.dialog@5", "wait:1.5"],
                  saved={"Reset restores defaults": lambda s: s.get("reduceMotion") is False and s.get("showInstrumentIcons") is True,
                         "Reset keeps song sort": lambda s: s.get("songSort") == "Artist"}),
        ],
    ),
    Journey(
        name="links",
        phases=[
            Phase(["scrollinto:id=fst.settings.licenses", "invoke:id=fst.settings.licenses",
                   "waitfor:id=fst.licenses.summary@10"],
                  expect=[r"id=fst\.licenses\.row\."]),
            Phase(["invoke:id=PART_BackButton", "waitfor:id=fst.settings@10", "wait:1", "scrollinto:id=fst.settings.privacy-policy",
                   "invoke:id=fst.settings.privacy-policy", "waitfor:id=fst.privacy-policy.dialog@10"],
                  expect=[_id("fst.privacy-policy.close")]),
            Phase(["invoke:id=fst.privacy-policy.close", "waitgone:id=fst.privacy-policy.dialog@5",
                   "scrollinto:id=fst.settings.whats-new", "invoke:id=fst.settings.whats-new",
                   "waitfor:id=fst.whats-new.dialog@10"]),
            Phase(["key:esc", "waitgone:id=fst.whats-new.dialog@5", "scrollinto:id=fst.settings.feedback.bug",
                   "invoke:id=fst.settings.feedback.bug", "waitfor:id=fst.settings.feedback.cancel@10"]),
            Phase(["invoke:id=fst.settings.feedback.cancel", "waitgone:id=fst.settings.feedback.cancel@5", "waitfor:id=fst.settings.feedback.bug@5"]),
        ],
    ),
    Journey(
        # Issue #43/#243: the App Version row shows the display version plus the stamped build commit (every local,
        # CI and Store build stamps one), selectable, after its label, in UIA order before Build Configuration.
        name="version",
        phases=[
            Phase(["reveal:id=fst.settings.whats-new", "waitfor:id=fst.settings.app-version@5",
                   "assertbelow:id=fst.settings.service-version|id=fst.settings.app-version"],
                  expect=[rf'^\s*Text "\d+(\.\d+)+ · [0-9a-f]{{7}}" {_id("fst.settings.app-version")}'],
                  order=[r'^\s*Text "App Version" ', _id("fst.settings.app-version"), r'^\s*Text "Build Configuration" ',
                         r'^\s*Text "Service Version" ', _id("fst.settings.service-version")],
                  forbid=[rf'Text "[^"]* · [^"]*" {_id("fst.settings.service-version")}']),
        ],
    ),
    Journey(
        name="first-run",
        phases=[
            Phase(["scrollinto:id=fst.settings.licenses", "wait:0.5", "scrollinto:id=fst.settings.first-run.songs", "invoke:id=fst.settings.first-run.songs",
                   "waitfor:id=fst.first-run.dialog@10"],
                  expect=[_id("fst.first-run.slides"), _id("fst.first-run.pips")]),
            Phase(["key:esc", "waitgone:id=fst.first-run.dialog@5", "scrollinto:id=fst.settings.first-run.songs"],
                  forbid=[_id("fst.first-run.dialog")]),
        ],
    ),
]

# endregion

# region Runner


def check_tree(text: str, phase: Phase) -> list[str]:
    """Failures for one phase's tree dump.

    Args:
        text: UIA tree dump (one element per line).
        phase: Phase with ``expect``/``forbid`` patterns.

    Returns:
        Failure messages (empty when the tree matches).
    """
    lines = text.splitlines()
    failures = [f"expected /{p}/ in the UIA tree" for p in phase.expect
                if not any(re.search(p, line) for line in lines)]
    failures += [f"did not expect /{p}/ in the UIA tree" for p in phase.forbid
                 if any(re.search(p, line) for line in lines)]
    positions = [next((i for i, line in enumerate(lines) if re.search(p, line)), -1) for p in phase.order]
    if phase.order and (-1 in positions or positions != sorted(positions)):
        failures.append(f"expected UIA order {phase.order}, found line positions {positions}")
    return failures


def check_saved(path: Path, phase: Phase) -> list[str]:
    """Failures for one phase's saved-settings predicates.

    Args:
        path: The isolated ``settings.json``.
        phase: Phase with ``saved`` predicates.

    Returns:
        Failure messages (empty when every predicate holds or there are none).
    """
    if not phase.saved:
        return []
    try:
        saved = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        return [f"settings.json unreadable: {error}"]
    failures = []
    for name, check in phase.saved.items():
        try:
            ok = check(saved)
        except (IndexError, KeyError, TypeError):
            ok = False
        if not ok:
            failures.append(f"saved settings: {name} failed")
    return failures


def run(journey: Journey, exe: Path, shots: Path | None) -> list[str]:
    """Run one journey and return failure messages (empty when it passed)."""
    failures: list[str] = []
    port = _helpers._free_port()
    mock = subprocess.Popen([sys.executable, str(REPO / "tools" / "mock_service.py"), "--port", str(port)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    work = Path(tempfile.mkdtemp(prefix=f"fst-settings-{journey.name}-"))
    settings = work / "settings.json"
    if journey.seed:
        settings.write_text(json.dumps(journey.seed), encoding="utf-8")
    # No --anonymous: it selects in-memory settings. A fresh isolated file has no selected player.
    launch = ["--tab", "settings"]
    pid = None
    try:
        time.sleep(1.0)
        base = f"http://127.0.0.1:{port}/"
        pid = _helpers._launch(exe, base, settings, launch)
        for index, phase in enumerate(journey.phases):
            tree = work / f"tree-{index}.txt"
            steps = [READY, *phase.steps, f"tree:{tree}"] if index == 0 else [*phase.steps, f"tree:{tree}"]
            if shots is not None:
                steps.append(f"shot:{shots / f'settings-{journey.name}-{index}.png'}")
            result = _helpers._uiwin("drive", "--pid", str(pid), "--steps", "; ".join(steps), check=False)
            if result.returncode != 0:
                detail = "\n".join(s.strip() for s in (result.stderr, result.stdout) if s and s.strip())
                failures.append(f"phase {index}: drive exited {result.returncode}: {detail[-800:]}")
                break
            text = tree.read_text(encoding="utf-8", errors="replace") if tree.exists() else ""
            failures += [f"phase {index}: {f}" for f in check_tree(text, phase) + check_saved(settings, phase)]
            if journey.relaunch == index:
                _helpers._uiwin("close", "--pid", str(pid), check=False)
                pid = _helpers._launch(exe, base, settings, launch)
    except RuntimeError as error:
        failures.append(str(error))
    finally:
        if pid is not None:
            _helpers._uiwin("close", "--pid", str(pid), check=False)
        mock.terminate()
    return failures


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        0 when all selected journeys pass, else 1.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("names", nargs="*", help="journeys to run (default: all)")
    journey_exe.add_argument(parser)
    parser.add_argument("--shots", type=Path, help="directory for per-phase screenshots")
    args = parser.parse_args(argv)
    selected = [j for j in JOURNEYS if not args.names or j.name in args.names]
    if args.shots:
        args.shots.mkdir(parents=True, exist_ok=True)
    failed = 0
    for journey in selected:
        failures = run(journey, args.exe.resolve(), args.shots.resolve() if args.shots else None)
        print(f"{'PASS' if not failures else 'FAIL'} {journey.name}", flush=True)
        for failure in failures:
            print(f"  - {failure}", flush=True)
        failed += bool(failures)
    print(f"{len(selected) - failed}/{len(selected)} journeys passed")
    return 1 if failed else 0

# endregion


if __name__ == "__main__":
    sys.exit(main())
