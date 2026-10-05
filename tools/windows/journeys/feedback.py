#!/usr/bin/env python3
"""Feedback Form UI journeys for the Windows app (issue #236), driven through ``tools/windows/uiwin.py``.

Each journey launches the app on Settings with an isolated settings file against
``tools/windows/feedback_fixture.py`` (loopback mock, nothing is filed anywhere), runs UIA steps and checks the tree
dumped after each phase, plus what the fixture received. Between phases a journey can switch the fixture's modes
(``features``, ``post``, ``status``) to hold the upload or the filing poll, so every reachable
[feedback-form](../../../.agents/controls/feedback-form/spec.md) state is asserted:

``unavailable``, ``editing-empty``, ``editing-dirty``, ``invalid``, ``attachments``, ``discard-confirm``, ``sending``,
``filing``, ``sent`` and ``error`` (send failure and failed filing, each followed by a retry).

Only UIA patterns are used (``invoke``, ``setvalue``, ``waitfor``/``waitgone``, ``assertstate``, ``assertname``),
so the journeys also run while the console session is locked. Attach Media is driven through the system file picker
(``id=1148&class=Edit`` file name, ``id=1&class=Button`` Open) with generated PNG files.

Usage (from the repository root, after ``tools/windows/build.ps1``)::

    python tools/windows/journeys/feedback.py                         # all journeys at medium
    python tools/windows/journeys/feedback.py submit --preset compact # by name and window preset
    python tools/windows/journeys/feedback.py --shots out\\dir         # per-phase screenshots

Exit code 0 when every journey passes, 1 otherwise.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import struct
import subprocess
import sys
import tempfile
import time
import urllib.request
import zlib
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
FIXTURE = REPO / "tools" / "windows" / "feedback_fixture.py"

# region Model


@dataclass
class Phase:
    """One ``drive`` call and its checks.

    Attributes:
        steps: Step strings run in one ``drive`` call (``{media}`` expands to the generated media folder).
        control: Fixture modes set before the steps (e.g. ``{"post": "hold"}``).
        expect: Regular expressions that must each match a line of the UIA tree dumped after the steps.
        forbid: Regular expressions that must not match any line of that tree.
        count: Regular expression → exact number of matching tree lines.
        posted: Predicates over the fixture's snapshot (``posts``, ``reads``, ``last``) after the steps.
    """

    steps: list[str]
    control: dict[str, str] = field(default_factory=dict)
    expect: list[str] = field(default_factory=list)
    forbid: list[str] = field(default_factory=list)
    count: dict[str, int] = field(default_factory=dict)
    posted: dict[str, Callable[[dict[str, Any]], bool]] = field(default_factory=dict)


@dataclass
class Journey:
    """One scripted Feedback Form journey.

    Attributes:
        name: Short CLI name.
        states: Spec states the journey asserts.
        phases: Drive phases.
        fixture: Extra fixture flags at launch (e.g. ``["--features", "off"]``).
    """

    name: str
    states: list[str]
    phases: list[Phase]
    fixture: list[str] = field(default_factory=list)


ROOT = "fst.settings.feedback"
READY = "waitfor:id=fst.settings.show-instrument-icons@20"
SUBMIT = "id=PrimaryButton"


def _id(automation_id: str) -> str:
    """Tree-line pattern for an AutomationId."""
    return rf"id={re.escape(automation_id)} "


def _named(automation_id: str, name: str) -> str:
    """Tree-line pattern for an element with this AutomationId and exact UIA Name."""
    return rf'"{re.escape(name)}" id={re.escape(automation_id)} '


def _open(kind: str) -> list[str]:
    """Steps that open the Bug (``bug``) or Feature (``feature``) form from Settings."""
    return [READY, f"scrollinto:id={ROOT}.{kind}@20", f"invoke:id={ROOT}.{kind}", f"waitfor:id={ROOT}.{kind}.dialog@10",
            f"waitfor:id={ROOT}.title@5"]


def _validation(text: str) -> str:
    """Step asserting the inline reason Submit is disabled."""
    return f"assertname:id={ROOT}.validation|{text}"


def _submit_enabled(enabled: bool) -> str:
    """Step asserting Submit's enabled state."""
    return f"assertstate:{SUBMIT}|enabled={'true' if enabled else 'false'}@5"


def _pick(*names: str) -> list[str]:
    """Steps that pick generated media through the system file picker."""
    quoted = " ".join(f'"{{media}}\\{name}"' for name in names)
    return [f"scrollinto:id={ROOT}.attach@5", f"invoke:id={ROOT}.attach", "waitfor:id=1148&class=Edit@15",
            f"setvalue:id=1148&class=Edit|{quoted}",
            "invoke:id=1&class=Button", "waitgone:id=1148&class=Edit@10", "wait:1"]


ATTACHMENT = _id(f"{ROOT}.attachment")

JOURNEYS = [
    Journey(
        name="unavailable",
        states=["unavailable"],
        fixture=["--features", "off"],
        phases=[
            Phase([READY, "scrollinto:id=fst.settings.licenses@20", "wait:2"],
                  expect=[_id("fst.settings.licenses")],
                  forbid=[_id(f"{ROOT}.bug"), _id(f"{ROOT}.feature")],
                  posted={"no POST": lambda s: s["posts"] == 0}),
        ],
    ),
    Journey(
        name="validation",
        states=["editing-empty", "invalid", "editing-dirty", "discard-confirm"],
        phases=[
            # editing-empty: only the prefix; Submit disabled with the reason; Cancel closes without asking.
            Phase([*_open("bug"), _submit_enabled(False), _validation("Add a title after the prefix.")],
                  expect=[_id(f"{ROOT}.repro"), _id(f"{ROOT}.expected"), _named(f"{ROOT}.cancel", "Cancel"),
                          _named("PrimaryButton", "Submit")]),
            Phase([f"invoke:id={ROOT}.cancel", f"waitgone:id={ROOT}.bug.dialog@5", f"waitfor:id={ROOT}.bug@5"],
                  forbid=[_id(f"{ROOT}.discard-confirm")]),
            # invalid: a title but no description.
            Phase([f"invoke:id={ROOT}.bug", f"waitfor:id={ROOT}.title@10",
                   f"setvalue:id={ROOT}.title|[Bug] Songs list freezes", _validation("Add a description."),
                   _submit_enabled(False)]),
            # editing-dirty: valid; Submit enabled and the reason gone.
            Phase([f"setvalue:id={ROOT}.description|Scrolling stops after the A-Z jump.", _submit_enabled(True),
                   f"waitgone:id={ROOT}.validation@5"]),
            # invalid again once the description is cleared (with text elsewhere still dirty).
            Phase([f"setvalue:id={ROOT}.description|", _validation("Add a description."), _submit_enabled(False),
                   f"scrollinto:id={ROOT}.repro@5", f"setvalue:id={ROOT}.repro|1. Open Songs"]),
            # discard-confirm: Cancel on a dirty form asks first and focuses the safe choice; Keep Editing returns to
            # the title with the input kept.
            Phase([f"invoke:id={ROOT}.cancel", f"waitfor:id={ROOT}.keep-editing@5", "wait:1",
                   f"assertfocus:id={ROOT}.keep-editing"],
                  expect=[_id(f"{ROOT}.discard-confirm"), _named(f"{ROOT}.discard", "Discard"),
                          _named(f"{ROOT}.keep-editing", "Keep Editing"), _id(f"{ROOT}.bug.dialog")]),
            Phase([f"invoke:id={ROOT}.keep-editing", f"waitgone:id={ROOT}.keep-editing@5",
                   _validation("Add a description."), "wait:0.5", f"assertfocus:id={ROOT}.title"],
                  expect=[_id(f"{ROOT}.bug.dialog")]),
            Phase([f"invoke:id={ROOT}.cancel", f"waitfor:id={ROOT}.discard@5", f"invoke:id={ROOT}.discard",
                   f"waitgone:id={ROOT}.bug.dialog@5", f"waitfor:id={ROOT}.bug@5"],
                  posted={"nothing sent": lambda s: s["posts"] == 0}),
        ],
    ),
    Journey(
        name="submit",
        states=["attachments", "sending", "discard-confirm", "filing", "sent"],
        phases=[
            Phase([*_open("bug"), f"setvalue:id={ROOT}.title|[Bug] Shop row badge overlaps",
                   f"setvalue:id={ROOT}.description|The Leaving badge covers the title.",
                   f"scrollinto:id={ROOT}.repro@5", f"setvalue:id={ROOT}.repro|1. Open Songs. 2. Filter by Shop.",
                   f"scrollinto:id={ROOT}.expected@5", f"setvalue:id={ROOT}.expected|The badge sits beside the title.", _submit_enabled(True)]),
            # attachments: five picks keep four with a notice; Attach Media disables at the limit.
            Phase([*_pick("shot-1.png", "shot-2.png", "shot-3.png", "shot-4.png", "shot-5.png"),
                   f"waitfor:id={ROOT}.attachment@10", f"assertstate:id={ROOT}.attach|enabled=false@5"],
                  expect=[_id(f"{ROOT}.attachments"), r'"You can attach up to 4 files\."',
                          r'"Image, shot-1\.png, \d+ (B|KB)" id=fst\.settings\.feedback\.attachment ',
                          r'"Image, shot-4\.png, \d+ (B|KB)" id=fst\.settings\.feedback\.attachment .*\[[^\]]*focused',
                          r'"Remove shot-4\.png" id=fst\.settings\.feedback\.attachment\.remove '],
                  forbid=[r'"Image, shot-5\.png'],
                  count={ATTACHMENT: 4}),
            Phase([f"invoke:name=Remove shot-4.png", "wait:1", f"assertstate:id={ROOT}.attach|enabled=true@5",
                   f"assertfocus:id={ROOT}.attach"],
                  count={ATTACHMENT: 3},
                  forbid=[r'"You can attach up to 4 files\."', r'"Remove shot-4\.png"']),
            # sending: the upload is held; progress shows, Submit is disabled; Cancel asks before discarding.
            Phase(["invoke:id=PrimaryButton", f"waitfor:id={ROOT}.progress@10",
                   f"assertname:id={ROOT}.progress|Sending your report…", _submit_enabled(False),
                   f"invoke:id={ROOT}.cancel", f"waitfor:id={ROOT}.keep-editing@5"],
                  control={"post": "hold", "reset": "1"},
                  expect=[_id(f"{ROOT}.discard-confirm")],
                  posted={"one POST received": lambda s: s["posts"] == 1}),
            Phase([f"invoke:id={ROOT}.keep-editing", f"waitgone:id={ROOT}.keep-editing@5",
                   f"assertname:id={ROOT}.progress|Sending your report…"]),
            # filing: accepted; the status poll is held.
            Phase([f"assertname:id={ROOT}.progress@15|Filing your report on GitHub…", _submit_enabled(False)],
                  control={"post": "ok", "status": "hold"},
                  posted={"bug from Windows": lambda s: s["last"]["kind"] == "bug" and s["last"]["platform"] == "windows",
                          "three media parts": lambda s: s["last"]["media"] == 3,
                          "no privileged or selected-profile header": lambda s: s["last"]["forbidden_header"] is False,
                          "status polled": lambda s: s["reads"] >= 1}),
            # sent: filed as issue #1; only Done remains.
            Phase([f"waitfor:id={ROOT}.sent@15",
                   f"assertname:id={ROOT}.sent|Thanks! Your report was filed as issue #1.",
                   f"assertname:id={ROOT}.cancel|Done"],
                  control={"status": "ok"},
                  forbid=[_id(f"{ROOT}.title"), _id(f"{ROOT}.progress") + r".*rect=(?!0,0,0,0)",
                          _named("PrimaryButton", "Submit") + r".*rect=(?!0,0,0,0)"],
                  posted={"exactly one POST": lambda s: s["posts"] == 1}),
            Phase([f"invoke:id={ROOT}.cancel", f"waitgone:id={ROOT}.bug.dialog@5", f"waitfor:id={ROOT}.bug@5"],
                  forbid=[_id(f"{ROOT}.discard-confirm")]),
        ],
    ),
    Journey(
        name="error",
        states=["error", "editing-dirty", "sent"],
        phases=[
            # Feature form: no bug-only fields.
            Phase([*_open("feature"), _validation("Add a title after the prefix.")],
                  forbid=[_id(f"{ROOT}.repro"), _id(f"{ROOT}.expected")]),
            # error: 503 feedback_busy keeps every field and re-enables Submit for a retry.
            Phase([f"setvalue:id={ROOT}.title|[Feature] fixture-unavailable compare",
                   f"setvalue:id={ROOT}.description|Compare two players.", "invoke:id=PrimaryButton",
                   f"waitfor:name=Feedback is busy right now. Try again in a minute.@15", _submit_enabled(True)],
                  control={"reset": "1"},
                  expect=[_id(f"{ROOT}.error"), _id(f"{ROOT}.title")],
                  posted={"feature POST": lambda s: s["posts"] == 1 and s["last"]["kind"] == "feature"}),
            # Editing clears the error; a failed filing returns to editing with a retry message.
            Phase([f"setvalue:id={ROOT}.title|[Feature] fixture-failed compare",
                   f"waitgone:name=Feedback is busy right now. Try again in a minute.@5", "invoke:id=PrimaryButton",
                   f"waitfor:name=Your request couldn't be filed on GitHub. Try again in a few minutes.@20",
                   _submit_enabled(True)],
                  posted={"second POST": lambda s: s["posts"] == 2}),
            Phase([f"setvalue:id={ROOT}.title|[Feature] Compare two players", "invoke:id=PrimaryButton",
                   f"waitfor:id={ROOT}.sent@20",
                   f"assertname:id={ROOT}.sent|Thanks! Your request was filed as issue #1."],
                  posted={"third POST": lambda s: s["posts"] == 3}),
            Phase([f"invoke:id={ROOT}.cancel", f"waitgone:id={ROOT}.feature.dialog@5"]),
        ],
    ),
]

STATES = ("unavailable", "editing-empty", "editing-dirty", "invalid", "attachments", "discard-confirm", "sending",
          "filing", "sent", "error")

# endregion

# region Runner


def png(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    """A solid-colour PNG (picker fixtures; no third-party artwork).

    Args:
        width: Pixels.
        height: Pixels.
        rgb: Fill colour.

    Returns:
        PNG bytes.
    """
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    row = b"\x00" + bytes(rgb) * width
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(row * height)) + chunk(b"IEND", b""))


def write_media(folder: Path) -> None:
    """Write the five picker fixtures ``shot-1.png`` … ``shot-5.png``."""
    hues = [(37, 99, 235), (124, 58, 237), (5, 150, 105), (217, 119, 6), (220, 38, 38)]
    for index, hue in enumerate(hues, start=1):
        (folder / f"shot-{index}.png").write_bytes(png(320, 200, hue))


def check_tree(text: str, phase: Phase) -> list[str]:
    """Failures for one phase's tree dump.

    Args:
        text: UIA tree dump (one element per line).
        phase: Phase with ``expect``/``forbid``/``count`` patterns.

    Returns:
        Failure messages (empty when the tree matches).
    """
    lines = text.splitlines()
    failures = [f"expected /{p}/ in the UIA tree" for p in phase.expect
                if not any(re.search(p, line) for line in lines)]
    failures += [f"did not expect /{p}/ in the UIA tree" for p in phase.forbid
                 if any(re.search(p, line) for line in lines)]
    for pattern, wanted in phase.count.items():
        seen = sum(bool(re.search(pattern, line)) for line in lines)
        if seen != wanted:
            failures.append(f"expected {wanted} lines matching /{pattern}/, saw {seen}")
    return failures


def check_posted(snapshot: dict[str, Any] | None, phase: Phase) -> list[str]:
    """Failures for one phase's fixture predicates.

    Args:
        snapshot: Fixture control answer (``posts``, ``reads``, ``last``), or ``None`` when unreadable.
        phase: Phase with ``posted`` predicates.

    Returns:
        Failure messages.
    """
    if not phase.posted:
        return []
    if snapshot is None:
        return ["fixture snapshot unreadable"]
    failures = []
    for name, check in phase.posted.items():
        try:
            ok = check(snapshot)
        except (KeyError, TypeError):
            ok = False
        if not ok:
            failures.append(f"fixture: {name} failed ({json.dumps({k: snapshot.get(k) for k in ('posts', 'reads')})})")
    return failures


def expand(steps: list[str], media: Path) -> list[str]:
    """Substitute ``{media}`` in step strings."""
    return [step.replace("{media}", str(media)) for step in steps]


def control(base: str, modes: dict[str, str]) -> dict[str, Any] | None:
    """Set fixture modes (an empty dict just reads the snapshot)."""
    query = "&".join(f"{k}={v}" for k, v in modes.items())
    try:
        with urllib.request.urlopen(f"{base}__feedback__/mode?{query}", timeout=10) as response:
            return json.loads(response.read())
    except (OSError, ValueError):
        return None


def run(journey: Journey, exe: Path, preset: str, shots: Path | None) -> list[str]:
    """Run one journey and return failure messages (empty when it passed)."""
    failures: list[str] = []
    port = _helpers._free_port()
    fixture = subprocess.Popen([sys.executable, str(FIXTURE), "--port", str(port), *journey.fixture],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    work = Path(tempfile.mkdtemp(prefix=f"fst-feedback-{journey.name}-"))
    write_media(work)
    settings = work / "settings.json"
    base = f"http://127.0.0.1:{port}/"
    pid = None
    try:
        for _ in range(50):
            if control(base, {}) is not None:
                break
            time.sleep(0.2)
        else:
            raise RuntimeError("feedback fixture did not start")
        pid = _helpers._launch(exe, base, settings, ["--tab", "settings"], preset=preset)
        for index, phase in enumerate(journey.phases):
            if phase.control and control(base, phase.control) is None:
                failures.append(f"phase {index}: fixture control {phase.control} failed")
                break
            tree = work / f"tree-{index}.txt"
            steps = [*expand(phase.steps, work), f"tree:{tree}"]
            if shots is not None:
                steps.append(f"shot:{shots / f'feedback-{journey.name}-{preset}-{index}.png'}")
            result = _helpers._uiwin("drive", "--pid", str(pid), "--steps", "; ".join(steps), check=False)
            if result.returncode != 0:
                detail = "\n".join(s.strip() for s in (result.stderr, result.stdout) if s and s.strip())
                failures.append(f"phase {index}: drive exited {result.returncode}: {detail[-800:]}")
                failed = work / f"tree-{index}-failed.txt"
                _helpers._uiwin("drive", "--pid", str(pid), "--steps", f"tree:{failed}", check=False)
                if failed.exists():
                    failures.append(f"phase {index}: tree after failure: {failed}")
                failures.append(f"phase {index}: fixture {json.dumps(control(base, {}))[:400]}")
                break
            text = tree.read_text(encoding="utf-8", errors="replace") if tree.exists() else ""
            failures += [f"phase {index}: {f}" for f in check_tree(text, phase) + check_posted(control(base, {}), phase)]
    except RuntimeError as error:
        failures.append(str(error))
    finally:
        if pid is not None:
            _helpers._uiwin("close", "--pid", str(pid), check=False)
        control(base, {"post": "ok", "status": "ok"})
        fixture.terminate()
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
    parser.add_argument("--preset", default="medium", help="window preset (compact, medium, wide, maximized, snap-left…)")
    parser.add_argument("--shots", type=Path, help="directory for per-phase screenshots")
    args = parser.parse_args(argv)
    selected = [j for j in JOURNEYS if not args.names or j.name in args.names]
    if args.shots:
        args.shots.mkdir(parents=True, exist_ok=True)
    failed = 0
    for journey in selected:
        failures = run(journey, args.exe.resolve(), args.preset, args.shots.resolve() if args.shots else None)
        print(f"{'PASS' if not failures else 'FAIL'} {journey.name} [{args.preset}] ({', '.join(journey.states)})", flush=True)
        for failure in failures:
            print(f"  - {failure}", flush=True)
        failed += bool(failures)
    print(f"{len(selected) - failed}/{len(selected)} journeys passed")
    return 1 if failed else 0

# endregion


if __name__ == "__main__":
    sys.exit(main())
