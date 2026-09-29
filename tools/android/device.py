#!/usr/bin/env python3
"""Serialized Android emulator access for parallel lanes on the Windows host.

The Windows host ``sfenton-primary`` runs several lanes at once (Android app,
Windows app, device lab, ...), but only ONE product emulator may run at a time.
Every emulator interaction goes through this tool, which holds the shared
FIFO ``emulator`` host lock (:mod:`hostlock`, ≤300 s per hold) for the whole
boot/install/launch/screenshot sequence. It mirrors ``tools/ios_sim.py`` on
the Mac.

FST emulators always listen on console port ``5580`` (serial
``emulator-5580``) so they never collide with other projects' emulators, and
only AVDs named ``FST_*`` are ever shut down by this tool.

Examples::

    # Create (or re-create) the deterministic FST_ AVD matrix.
    python tools/android/device.py avds --create

    # What is installed, running, and who holds the lock?
    python tools/android/device.py list

    # Boot one AVD headless (shuts down any other FST_ emulator first).
    python tools/android/device.py boot FST_Book_Fold

    # Change the hinge posture (foldables / tri-fold only).
    python tools/android/device.py posture half --avd FST_Book_Fold

    # Install, launch on a debug route, and screenshot in one lock hold.
    python tools/android/device.py install android/app/build/outputs/apk/debug/app-debug.apk
    python tools/android/device.py launch --tab songs --route player:abc
    python tools/android/device.py shot out/phone-songs.png --tab songs

    # Script taps/swipes/screenshots (UIAutomator + adb input).
    python tools/android/device.py drive --steps "tap:text=Settings; wait:1; shot:out/s.png; tree:out/s.xml"

    # Run connected instrumentation tests for a class filter on one AVD.
    python tools/android/device.py test com.festivalscoretracker.android.ShellTest --avd FST_Tablet
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

try:
    from tools.android.hostlock import HostLock, LockTimeout, kill_tree
except ImportError:  # executed as a script: tools/android is sys.path[0]
    from hostlock import HostLock, LockTimeout, kill_tree

# region Configuration

REPO_ROOT = Path(__file__).resolve().parents[2]

#: Package id of the product app (``android/app/build.gradle.kts``).
DEFAULT_PACKAGE = "com.festivalscoretracker.android"

#: Console port reserved for FST emulators; the adb serial follows from it.
FST_PORT = 5580
FST_SERIAL = f"emulator-{FST_PORT}"

#: Only AVDs with this prefix are ever booted or shut down by this tool.
FST_PREFIX = "FST_"

#: Default target when a command does not name an AVD.
DEFAULT_AVD = "FST_Phone"

#: System image for every FST AVD: newest stable x86_64 Google APIs image.
#: API 37.2 ships x86_64 Google APIs only as a 16 KB page-size image.
SYSTEM_IMAGE = "system-images;android-37.2;google_apis_ps16k;x86_64"

#: Extra fallback image (4 KB pages) kept installed for comparison runs.
FALLBACK_IMAGE = "system-images;android-37.0;google_apis;x86_64"

#: Shared per-host state (logs) next to the host locks.
STATE_DIR = Path.home() / ".fst-locks"


@dataclass(frozen=True)
class AvdSpec:
    """One deterministic AVD in the FST device matrix.

    Attributes:
        device: ``avdmanager`` hardware profile id.
        form: Form factor (``phone``, ``book``, ``passport``, ``trifold``,
            ``tablet``, ``resizable``); selects the posture vocabulary.
        config: ``config.ini`` overrides applied after creation.
        note: One-line description for ``list``.
    """

    device: str
    form: str
    config: dict[str, str] = field(default_factory=dict)
    note: str = ""


#: Settings shared by every FST AVD: headless-friendly, no skin/frame,
#: hardware keyboard for ``type`` steps, cold boot for determinism.
COMMON_CONFIG = {
    "hw.keyboard": "yes",
    "hw.audioInput": "no",
    "hw.audioOutput": "no",
    "showDeviceFrame": "no",
    "fastboot.forceColdBoot": "yes",
    "disk.dataPartition.size": "8G",
    "hw.ramSize": "4096",
}

#: Custom tri-fold profile (no official emulator profile exists as of
#: emulator 37.1 / cmdline-tools 23.0). Modeled on a Galaxy Z TriFold-class
#: device: three 720 px × 1584 px panels side by side (10-inch-class 2160 × 1584
#: landscape inner display at 320 dpi) with two vertical physical hinges.
#: Display region 0.1 (720 × 1584) becomes a second, always-on physical
#: display: API 37 images only switch inner/outer displays for known Pixel
#: profiles, so it stands in for the cover screen but never takes over. (The
#: emulator hangs or crashes at boot if the hinge profile has no region.) The
#: app is always launched on logical display 0, the inner screen; folded (one
#: panel, 360 × 792 dp) and partial (two panels) states are emulated there by
#: ``apply_posture`` (see ``TRIFOLD_LAYOUT``).
TRIFOLD_CONFIG = {
    "hw.device.name": "fst_trifold",
    "hw.device.manufacturer": "FST",
    "hw.lcd.width": "2160",
    "hw.lcd.height": "1584",
    "hw.lcd.density": "320",
    "hw.initialOrientation": "landscape",
    "hw.displayRegion.0.1.xOffset": "0",
    "hw.displayRegion.0.1.yOffset": "0",
    "hw.displayRegion.0.1.width": "720",
    "hw.displayRegion.0.1.height": "1584",
    "hw.sensor.hinge": "yes",
    "hw.sensor.hinge.count": "2",
    "hw.sensor.hinge.type": "1",
    "hw.sensor.hinge.sub_type": "1",
    "hw.sensor.hinge.areas": "720-0-0-1584, 1440-0-0-1584",
    "hw.sensor.hinge.ranges": "0-180, 0-180",
    "hw.sensor.hinge.defaults": "180, 180",
    "hw.sensor.posture_list": "1, 3",
    "hw.sensor.hinge_angles_posture_definitions": "0-90, 90-180",
    "hw.sensor.hinge.fold_to_displayRegion.0.1_at_posture": "1",
    "hw.ramSize": "6144",
}

#: The FST AVD matrix. Keep in sync with `.agents/platforms/android.md`.
AVDS: dict[str, AvdSpec] = {
    "FST_Phone": AvdSpec("pixel_9", "phone", note="Pixel 9 phone"),
    "FST_Book_Fold": AvdSpec("pixel_9_pro_fold", "book",
                             note="Pixel 9 Pro Fold (book-style, near-square inner)"),
    "FST_Passport_Fold": AvdSpec("pixel_fold", "passport",
                                 note="Pixel Fold (passport-style, wide landscape inner)"),
    "FST_TriFold": AvdSpec("pixel_9_pro_fold", "trifold", TRIFOLD_CONFIG,
                           note="custom 3-panel tri-fold, two vertical hinges"),
    "FST_Tablet": AvdSpec("pixel_tablet", "tablet", {"hw.ramSize": "6144"},
                          note="Pixel Tablet"),
    "FST_Resizable": AvdSpec("resizable", "resizable",
                             note="Resizable (phone/foldable/tablet/desktop)"),
}

#: Hinge angles (degrees, one per hinge) for each named posture, per form factor.
#: Tri-folds have no half-open/tabletop posture (Android tri-fold guidance).
POSTURES: dict[str, dict[str, tuple[int, ...]]] = {
    "book": {"folded": (0,), "half": (90,), "unfolded": (180,)},
    "passport": {"folded": (0,), "half": (90,), "unfolded": (180,)},
    "trifold": {"folded": (0, 0), "partial": (180, 0), "unfolded": (180, 180)},
}

#: Resizable presets: ``(wm size or None, wm density or None, display_features)``,
#: taken from the resizable profile's ``hw.resizable.configs``. The console's
#: ``resize-display`` is a no-op on emulator 37.1 (headless or windowed) and
#: its ``desktop`` config is ignored, so the tool applies window-manager
#: overrides instead; ``phone`` resets to the physical 1080 × 2400 @ 420.
RESIZE_PRESETS: dict[str, tuple[str | None, str | None, str]] = {
    "phone": (None, None, ""),
    "foldable": ("2208x1840", "420", "fold-[1104,0,1104,1840]-flat"),
    "tablet": ("1920x1200", "240", ""),
    "desktop": ("1920x1080", "160", ""),
}

#: Tri-fold emulation per posture: ``(wm size override or None, display_features)``.
#: API 37 system images drive fold display switching and device states from
#: per-device overlays, so a custom profile's hinge angles move only the hinge
#: sensors. The tool therefore also sets the logical display size and the
#: ``display_features`` global setting, which the on-device WindowManager
#: extensions read in preference to ``config_display_features``.
TRIFOLD_LAYOUT: dict[str, tuple[str | None, str]] = {
    "folded": ("720x1584", ""),
    "partial": ("1440x1584", "fold-[720,0,720,1584]-flat"),
    "unfolded": (None, "fold-[720,0,720,1584]-flat;fold-[1440,0,1440,1584]-flat"),
}

#: Probe APK sources (Gradle-free; see ``tools/android/probe``).
PROBE_DIR = Path(__file__).resolve().parent / "probe"
PROBE_PACKAGE = "com.fst.lab.probe"
PROBE_BUILD_DIR = Path.home() / ".fst-tools" / "probe"

# endregion

# region SDK discovery


def sdk_root() -> Path:
    """Locate the Android SDK.

    Returns:
        ``ANDROID_HOME``/``ANDROID_SDK_ROOT`` or ``%LOCALAPPDATA%/Android/Sdk``.
    """
    for key in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        if os.environ.get(key):
            return Path(os.environ[key])
    return Path(os.environ.get("LOCALAPPDATA", Path.home())) / "Android" / "Sdk"


def _exe(name: str) -> str:
    """Return the platform executable file name (``.exe``/``.bat`` on Windows).

    Args:
        name: Base name such as ``adb`` or ``avdmanager``.

    Returns:
        The file name to execute.
    """
    if os.name != "nt":
        return name
    return f"{name}.bat" if name in ("avdmanager", "sdkmanager") else f"{name}.exe"


def adb_path() -> str:
    """Path to ``adb`` in the SDK."""
    return str(sdk_root() / "platform-tools" / _exe("adb"))


def emulator_path() -> str:
    """Path to the emulator binary in the SDK."""
    return str(sdk_root() / "emulator" / _exe("emulator"))


def avdmanager_path() -> str:
    """Newest side-by-side ``cmdline-tools`` avdmanager (profiles grow per release).

    Returns:
        Path to ``avdmanager``.
    """
    root = sdk_root() / "cmdline-tools"
    versions = sorted(
        (p for p in root.glob("*") if re.fullmatch(r"\d+(\.\d+)*", p.name)),
        key=lambda p: tuple(int(x) for x in p.name.split(".")),
    )
    base = versions[-1] if versions else root / "latest"
    return str(base / "bin" / _exe("avdmanager"))


def avd_home() -> Path:
    """Directory holding ``<name>.avd`` folders."""
    if os.environ.get("ANDROID_AVD_HOME"):
        return Path(os.environ["ANDROID_AVD_HOME"])
    return Path.home() / ".android" / "avd"

# endregion

# region Pure helpers (unit-tested)


def remote_quote(value: str) -> str:
    """Quote one argument for the device's ``/system/bin/sh``.

    Args:
        value: Raw argument.

    Returns:
        A single-quoted shell word.
    """
    return "'" + value.replace("'", "'\\''") + "'"


def parse_extras(pairs: list[str] | None) -> list[tuple[str, str]]:
    """Parse ``KEY=VALUE`` launch extras.

    Args:
        pairs: Raw ``--extra`` values.

    Returns:
        ``(key, value)`` pairs in order.

    Raises:
        ValueError: A pair has no ``=`` or an empty key.
    """
    result = []
    for pair in pairs or []:
        key, sep, value = pair.partition("=")
        if not sep or not key.strip():
            raise ValueError(f"extra must be KEY=VALUE, got {pair!r}")
        result.append((key.strip(), value))
    return result


def launch_extras(tab: str | None, route: str | None,
                  extras: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """Combine ``--tab``/``--route`` with free-form extras.

    The app reads string intent extras with the same names as the Apple debug
    environment (``FST_DEBUG_TAB``, ``FST_DEBUG_ROUTE``, other ``FST_*``).

    Args:
        tab: Value for ``FST_DEBUG_TAB``.
        route: Value for ``FST_DEBUG_ROUTE``.
        extras: Additional ``(key, value)`` pairs.

    Returns:
        Ordered extras to pass with ``--es``.
    """
    result = []
    if tab:
        result.append(("FST_DEBUG_TAB", tab))
    if route:
        result.append(("FST_DEBUG_ROUTE", route))
    return result + list(extras)


def am_start_command(component: str, extras: list[tuple[str, str]]) -> str:
    """Build the device shell command that cold-starts an activity.

    Args:
        component: ``package/.Activity`` component.
        extras: String extras to attach.

    ``-S`` alone is not enough right after ``adb install -r``: the package
    manager's own restart can leave the old task on top, so ``am start``
    delivers the intent to that instance and the ``FST_*`` extras never reach
    ``onCreate``. ``--activity-clear-task`` always recreates the activity.

    Returns:
        A single ``am start`` command line (``-W`` waits, ``-S`` force-stops
        first, ``--activity-clear-task`` recreates the task).
    """
    parts = ["am", "start", "-W", "-S", "--activity-clear-task", "--display", "0",
             "-n", remote_quote(component)]
    for key, value in extras:
        parts += ["--es", remote_quote(key), remote_quote(value)]
    return " ".join(parts)


def reused_instance(am_output: str) -> bool:
    """Whether ``am start`` handed the intent to an already running activity.

    Args:
        am_output: Output of an ``am start -W`` command.

    Returns:
        True when the launch was not a fresh activity (its extras were dropped).
    """
    return "Activity not started" in am_output


def emulator_args(avd: str, *, window: bool = False, gpu: str = "swiftshader_indirect",
                  port: int = FST_PORT) -> list[str]:
    """Arguments for a deterministic emulator launch.

    Args:
        avd: AVD name.
        window: Show the emulator window (needs an interactive desktop session).
        gpu: ``-gpu`` mode; software rendering keeps screenshots deterministic
            and works from the SSH (non-interactive) session.
        port: Console port.

    Returns:
        Emulator argument vector (without the executable).
    """
    args = ["-avd", avd, "-port", str(port), "-no-snapshot", "-no-boot-anim",
            "-no-audio", "-gpu", gpu, "-netdelay", "none", "-netspeed", "full"]
    if not window:
        args.append("-no-window")
    return args


def posture_angles(form: str, posture: str) -> tuple[int, ...]:
    """Resolve a posture name to hinge angles for a form factor.

    Args:
        form: AVD form factor from :class:`AvdSpec`.
        posture: Posture name, or explicit comma-separated angles like ``"180,90"``.

    Returns:
        One angle per hinge.

    Raises:
        ValueError: The form factor has no hinge, or the posture is unknown or
            has the wrong number of angles.
    """
    table = POSTURES.get(form)
    if table is None:
        raise ValueError(f"form factor {form!r} has no hinge; postures apply to "
                         f"{', '.join(sorted(POSTURES))}")
    hinges = len(next(iter(table.values())))
    if re.fullmatch(r"\d+(\s*,\s*\d+)*", posture):
        angles = tuple(int(x) for x in posture.split(","))
    elif posture in table:
        angles = table[posture]
    else:
        raise ValueError(f"unknown posture {posture!r} for {form}; "
                         f"use {', '.join(table)} or explicit angles")
    if len(angles) != hinges:
        raise ValueError(f"{form} has {hinges} hinge(s), got {len(angles)} angle(s)")
    if any(not 0 <= a <= 180 for a in angles):
        raise ValueError("hinge angles must be within 0-180")
    return angles


def config_lines(existing: str, overrides: dict[str, str]) -> str:
    """Apply ``key=value`` overrides to an AVD ``config.ini`` text.

    Existing keys are replaced in place (preserving order); new keys are
    appended in sorted order so output is deterministic.

    Args:
        existing: Current ``config.ini`` contents.
        overrides: Keys to set.

    Returns:
        The new file contents, newline-terminated.
    """
    lines, seen = [], set()
    for line in existing.splitlines():
        key = line.split("=", 1)[0].strip()
        if "=" in line and key in overrides:
            lines.append(f"{key}={overrides[key]}")
            seen.add(key)
        elif line.strip():
            lines.append(line)
    lines += [f"{k}={overrides[k]}" for k in sorted(overrides) if k not in seen]
    return "\n".join(lines) + "\n"


def parse_steps(steps: str | None, steps_file: str | None) -> list[str]:
    """Combine an inline step string and/or a step file into one ordered list.

    File steps come first. Steps are newline- or ``;``-separated; blank lines
    and ``#`` comments are dropped.

    Args:
        steps: Inline ``;``-separated script, or None.
        steps_file: Path to a newline-separated script, or None.

    Returns:
        Non-empty step strings such as ``"tap:text=Settings"``.

    Raises:
        ValueError: Neither source produced any steps.
    """
    raw: list[str] = []
    if steps_file:
        raw.extend(Path(steps_file).read_text(encoding="utf-8").splitlines())
    if steps:
        raw.extend(steps.split(";"))
    parsed = [s.strip() for s in raw]
    parsed = [s for s in parsed if s and not s.startswith("#")]
    if not parsed:
        raise ValueError("no driver steps provided (use --steps and/or --steps-file)")
    return parsed


#: Step verbs understood by ``drive`` and whether each requires an argument.
STEP_VERBS = {
    "tap": True, "longpress": True, "waitfor": True, "swipe": True, "type": True,
    "key": True, "wait": True, "shot": True, "tree": True, "posture": True,
    "rotate": True, "resize": True, "talkback": True, "fontscale": True, "dark": True,
    "record": True, "back": False, "home": False,
}

#: Device path for ``record`` steps; ``screenrecord`` caps a clip at 180 s.
RECORD_REMOTE = "/sdcard/fst-record.mp4"
RECORD_LIMIT_S = 180

#: TalkBack service component on Google APIs images (preinstalled from API 37).
TALKBACK_SERVICE = ("com.google.android.marvin.talkback/"
                    "com.google.android.marvin.talkback.TalkBackService")


def toggle_arg(arg: str) -> bool:
    """Parse an ``on``/``off`` step argument.

    Args:
        arg: ``on``/``off`` (also ``true``/``false``, ``1``/``0``).

    Returns:
        True for on.

    Raises:
        ValueError: Anything else.
    """
    value = arg.strip().lower()
    if value in ("on", "true", "1"):
        return True
    if value in ("off", "false", "0"):
        return False
    raise ValueError(f"expected on/off, got {arg!r}")


def parse_step(step: str) -> tuple[str, str]:
    """Split and validate one ``verb:argument`` step.

    Args:
        step: A step such as ``"tap:id=fst.nav.settings"`` or ``"back"``.

    Returns:
        ``(verb, argument)``.

    Raises:
        ValueError: Unknown verb or a missing required argument.
    """
    verb, _, arg = step.partition(":")
    verb = verb.strip().lower()
    if verb not in STEP_VERBS:
        raise ValueError(f"unknown step verb {verb!r} in {step!r}")
    if STEP_VERBS[verb] and not arg.strip():
        raise ValueError(f"step {verb!r} needs an argument")
    return verb, arg.strip()


def record_command(remote: str = RECORD_REMOTE, limit: int = RECORD_LIMIT_S) -> str:
    """Build the device ``screenrecord`` command line for a ``record`` step.

    Args:
        remote: Output path on the device.
        limit: Maximum clip length in seconds (``screenrecord`` allows ≤180).

    Returns:
        The shell command line.
    """
    return f"screenrecord --time-limit {max(1, min(limit, RECORD_LIMIT_S))} {remote_quote(remote)}"


def parse_selector(text: str) -> tuple[str, str]:
    """Parse a UI selector.

    Forms: ``id=<resource-id or Compose testTag>``, ``text=<exact text>``,
    ``desc=<content-description>``, ``contains=<substring of text/desc>``,
    or ``<x>,<y>`` pixel coordinates.

    Args:
        text: Selector text; an optional ``@<seconds>`` suffix is not part of it.

    Returns:
        ``(kind, value)``, with kind ``id``/``text``/``desc``/``contains``/``xy``.

    Raises:
        ValueError: Unrecognized selector.
    """
    if re.fullmatch(r"\s*\d+\s*,\s*\d+\s*", text):
        return "xy", text.replace(" ", "")
    kind, sep, value = text.partition("=")
    kind = kind.strip().lower()
    if sep and kind in ("id", "text", "desc", "contains") and value:
        return kind, value
    raise ValueError(f"bad selector {text!r}; use id=, text=, desc=, contains= or x,y")


def parse_bounds(bounds: str) -> tuple[int, int, int, int]:
    """Parse a UIAutomator ``bounds`` attribute.

    Args:
        bounds: Text like ``"[0,63][1080,210]"``.

    Returns:
        ``(left, top, right, bottom)``.

    Raises:
        ValueError: Malformed bounds.
    """
    match = re.fullmatch(r"\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]", bounds.strip())
    if not match:
        raise ValueError(f"bad bounds {bounds!r}")
    left, top, right, bottom = (int(g) for g in match.groups())
    return left, top, right, bottom


def node_matches(node: ET.Element, kind: str, value: str) -> bool:
    """Decide whether a UIAutomator node matches a selector.

    ``id`` matches the full resource id or the part after ``:id/`` (Compose
    ``testTag`` values appear as bare resource ids when the app enables
    ``testTagsAsResourceId``).

    Args:
        node: A ``<node>`` element from ``uiautomator dump``.
        kind: Selector kind from :func:`parse_selector` (not ``xy``).
        value: Selector value.

    Returns:
        True on match.
    """
    rid = node.get("resource-id", "")
    if kind == "id":
        return rid == value or rid.split(":id/", 1)[-1] == value
    if kind == "text":
        return node.get("text", "") == value
    if kind == "desc":
        return node.get("content-desc", "") == value
    if kind == "contains":
        return value in node.get("text", "") or value in node.get("content-desc", "")
    return False


def find_center(xml_text: str, kind: str, value: str) -> tuple[int, int] | None:
    """Find the centre of the first visible node matching a selector.

    Args:
        xml_text: ``uiautomator dump`` output.
        kind: Selector kind (not ``xy``).
        value: Selector value.

    Returns:
        ``(x, y)`` centre in device pixels, or None if no visible match.
    """
    root = ET.fromstring(xml_text)
    for node in root.iter("node"):
        if not node_matches(node, kind, value):
            continue
        left, top, right, bottom = parse_bounds(node.get("bounds", "[0,0][0,0]"))
        if right > left and bottom > top:
            return (left + right) // 2, (top + bottom) // 2
    return None


def swipe_vector(arg: str, width: int, height: int) -> tuple[int, int, int, int, int]:
    """Resolve a ``swipe`` step argument to coordinates.

    Directions move the *content* the named way's finger direction: ``up``
    drags the finger from 75 % to 25 % height (scrolls content down the list).

    Args:
        arg: ``up``/``down``/``left``/``right`` or ``x1,y1,x2,y2[,ms]``.
        width: Screen width in pixels.
        height: Screen height in pixels.

    Returns:
        ``(x1, y1, x2, y2, duration_ms)``.

    Raises:
        ValueError: Unrecognized argument.
    """
    cx, cy = width // 2, height // 2
    lo_y, hi_y, lo_x, hi_x = height // 4, height * 3 // 4, width // 5, width * 4 // 5
    named = {
        "up": (cx, hi_y, cx, lo_y), "down": (cx, lo_y, cx, hi_y),
        "left": (hi_x, cy, lo_x, cy), "right": (lo_x, cy, hi_x, cy),
    }
    if arg in named:
        return (*named[arg], 300)
    nums = [int(x) for x in arg.split(",")] if re.fullmatch(r"\d+(,\d+){3,4}", arg) else None
    if not nums:
        raise ValueError(f"bad swipe {arg!r}; use up/down/left/right or x1,y1,x2,y2[,ms]")
    return (*nums[:4], nums[4] if len(nums) == 5 else 300)


def input_text_arg(text: str) -> str:
    """Encode text for ``adb shell input text`` (spaces become ``%s``).

    Args:
        text: Literal text to type.

    Returns:
        A quoted device-shell word.
    """
    return remote_quote(text.replace("%", "\\%").replace(" ", "%s"))


def parse_wm_size(output: str) -> tuple[int, int]:
    """Parse ``wm size`` output, preferring the override size.

    Args:
        output: e.g. ``"Physical size: 1080x2424\\nOverride size: 720x1584"``.

    Returns:
        ``(width, height)``.

    Raises:
        ValueError: No size found.
    """
    sizes = dict(re.findall(r"(Physical|Override) size:\s*(\d+x\d+)", output))
    chosen = sizes.get("Override") or sizes.get("Physical")
    if not chosen:
        raise ValueError(f"no size in {output!r}")
    width, height = chosen.split("x")
    return int(width), int(height)


def gradle_test_args(test_filter: str | None, task: str) -> list[str]:
    """Gradle arguments for a filtered connected-test run.

    Args:
        test_filter: ``pkg.Class``, ``pkg.Class#method`` or ``package:pkg.name``;
            None runs everything.
        task: Connected test task, e.g. ``:app:connectedDebugAndroidTest``.

    Returns:
        Gradle argument vector (without the Gradle executable).
    """
    args = [task, "--console=plain"]
    if test_filter:
        prefix = "-Pandroid.testInstrumentationRunnerArguments."
        if test_filter.startswith("package:"):
            args.append(f"{prefix}package={test_filter[len('package:'):]}")
        else:
            args.append(f"{prefix}class={test_filter}")
    return args

def trifold_layout(angles: tuple[int, ...]) -> tuple[str | None, str]:
    """Map tri-fold hinge angles to the emulated display size and features.

    A hinge counts as open at 90° or more. Panels unfold from the left, so a
    right hinge open while the left one is closed is still treated as folded.

    Args:
        angles: ``(left_hinge, right_hinge)`` angles.

    Returns:
        ``(wm size or None to reset, display_features string)``.
    """
    left, right = (angle >= 90 for angle in angles)
    if left and right:
        return TRIFOLD_LAYOUT["unfolded"]
    if left:
        return TRIFOLD_LAYOUT["partial"]
    return TRIFOLD_LAYOUT["folded"]


def default_physical_display(get_displays: str) -> str | None:
    """Find the physical display id backing logical display 0.

    Args:
        get_displays: Output of ``cmd display get-displays``.

    Returns:
        The ``local:<id>`` number for ``screencap -d``, or None if not found.
    """
    for line in get_displays.splitlines():
        if line.startswith("Display id 0:"):
            match = re.search(r'uniqueId "local:(\d+)"', line)
            return match.group(1) if match else None
    return None


def parse_probe_line(line: str) -> dict | None:
    """Parse one ``FST_PROBE`` logcat line from the probe APK.

    Args:
        line: A logcat line.

    Returns:
        ``{"window": "WxH", "features": [{"type", "state", "bounds"}]}``,
        ``{"error": ...}``, or None for unrelated lines.
    """
    if "FST_PROBE" not in line:
        return None
    if "error=" in line:
        return {"error": line.split("error=", 1)[1].strip()}
    match = re.search(r"window=(\d+x\d+) features=\[(.*)\]", line)
    if not match:
        return None
    features = []
    for item in filter(None, (part.strip() for part in match.group(2).split(";"))):
        found = re.fullmatch(r"(\w+) state=(\w+) bounds=([-\d,]+)", item)
        if not found:
            continue
        kind, state, bounds = found.groups()
        features.append({"type": kind, "state": state,
                         "bounds": [int(v) for v in bounds.split(",")]})
    return {"window": match.group(1), "features": features}

# endregion

# region Device I/O


class DeviceError(RuntimeError):
    """A device command failed in a way the caller should report."""


class Device:
    """adb/emulator operations on the FST serial, bounded by a held lock.

    Args:
        lock: The held ``emulator`` host lock (supplies timeouts).
        serial: adb serial of the FST emulator.
    """

    def __init__(self, lock: HostLock | None, serial: str = FST_SERIAL):
        self.lock = lock
        self.serial = serial
        self.recording: tuple[subprocess.Popen, Path] | None = None

    def _timeout(self, cap: float) -> float:
        return min(cap, self.lock.remaining()) if self.lock else cap

    def adb(self, *args: str, cap: float = 60.0, check: bool = True,
            binary: bool = False, serial: str | None = None) -> subprocess.CompletedProcess:
        """Run ``adb -s <serial> ...`` with a lock-bounded timeout.

        Args:
            *args: adb arguments.
            cap: Maximum seconds for this call.
            check: Raise :class:`DeviceError` on non-zero exit.
            binary: Return raw bytes instead of text.
            serial: Override serial (e.g. to query a foreign emulator).

        Returns:
            The completed process.
        """
        cmd = [adb_path(), "-s", serial or self.serial, *args]
        try:
            result = subprocess.run(cmd, capture_output=True, text=not binary,
                                    timeout=self._timeout(cap))
        except subprocess.TimeoutExpired as exc:
            raise DeviceError(f"timeout: {' '.join(cmd)}") from exc
        if check and result.returncode != 0:
            err = result.stderr if not binary else result.stderr.decode(errors="replace")
            raise DeviceError(f"{' '.join(cmd)} failed: {err.strip()}")
        return result

    def shell(self, command: str, cap: float = 60.0, check: bool = True) -> str:
        """Run a device shell command line and return stdout."""
        return self.adb("shell", command, cap=cap, check=check).stdout

    def emu(self, *args: str, cap: float = 20.0) -> str:
        """Send an emulator console command (``adb emu ...``)."""
        out = self.adb("emu", *args, cap=cap, check=False)
        text = (out.stdout or "") + (out.stderr or "")
        if "KO" in text.split():
            raise DeviceError(f"emu {' '.join(args)}: {text.strip()}")
        return text

    def screen_size(self) -> tuple[int, int]:
        """Current logical screen size in pixels."""
        return parse_wm_size(self.shell("wm size"))

    def screenshot(self, out: Path) -> None:
        """Write a PNG screenshot of the physical display showing logical display 0.

        Foldables have several physical displays (inner and cover); which one
        backs the default display depends on the posture.
        """
        physical = default_physical_display(self.shell("cmd display get-displays", check=False))
        selector = ["-d", physical] if physical else []
        data = self.adb("exec-out", "screencap", "-p", *selector, binary=True, cap=30).stdout
        start = data.find(b"\x89PNG")
        if start < 0:
            raise DeviceError("screencap did not return a PNG")
        data = data[start:]
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)

    def start_recording(self, out: Path) -> None:
        """Start ``adb shell screenrecord`` in the background (stopped by :meth:`stop_recording`).

        Args:
            out: Local ``.mp4`` path the clip is pulled to.
        """
        if self.recording:
            raise DeviceError("record: a recording is already running (use record:stop)")
        self.shell(f"rm -f {remote_quote(RECORD_REMOTE)}", check=False)
        proc = subprocess.Popen([adb_path(), "-s", self.serial, "shell", record_command()],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.recording = (proc, out)
        time.sleep(1)  # screenrecord needs a moment before the first frame

    def stop_recording(self) -> Path | None:
        """Stop the running recording, pull it and delete the device copy.

        Returns:
            The local clip path, or None when nothing was recording.
        """
        if not self.recording:
            return None
        proc, out = self.recording
        self.recording = None
        self.shell("pkill -INT screenrecord", check=False)
        try:
            proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            kill_tree(proc)
        time.sleep(1)  # let the muxer finalize the file
        out.parent.mkdir(parents=True, exist_ok=True)
        self.adb("pull", RECORD_REMOTE, str(out), cap=60)
        self.shell(f"rm -f {remote_quote(RECORD_REMOTE)}", check=False)
        return out

    def dump_tree(self, attempts: int = 3) -> str:
        """Dump the UIAutomator hierarchy XML (retrying transient idle failures)."""
        last = ""
        for _ in range(attempts):
            last = self.shell("uiautomator dump /sdcard/fst-ui.xml", cap=30, check=False)
            if "dumped to" in last:
                return self.adb("exec-out", "cat", "/sdcard/fst-ui.xml", cap=30).stdout
            time.sleep(1)
        raise DeviceError(f"uiautomator dump failed: {last.strip()}")

    def metadata(self, avd: str) -> dict:
        """Collect API level, window size, density, rotation and hinge state."""
        props = {k: self.shell(f"getprop {k}").strip() for k in
                 ("ro.build.version.sdk", "ro.build.version.release", "ro.product.model")}
        hinges = []
        for index in range(len(next(iter(POSTURES.get(AVDS.get(avd, AvdSpec("", "")).form,
                                                      {"x": ()}).values())))):
            hinges.append(self.emu("sensor", "get", f"hinge-angle{index}").strip().splitlines()[0])
        return {
            "avd": avd,
            "api": props["ro.build.version.sdk"],
            "release": props["ro.build.version.release"],
            "model": props["ro.product.model"],
            "wm_size": self.shell("wm size").strip(),
            "wm_density": self.shell("wm density").strip(),
            "rotation": self.shell("settings get system user_rotation", check=False).strip(),
            "device_state": _committed_state(self.shell("dumpsys device_state", check=False)),
            # What Jetpack WindowManager's extensions report as FoldingFeatures.
            "display_features": self.shell(
                "cmd overlay lookup android android:string/config_display_features",
                check=False).strip(),
            "hinges": hinges,
            "captured": time.strftime("%Y-%m-%dT%H:%M:%S"),
        }


def _committed_state(dump: str) -> str:
    """Extract the committed device state line from ``dumpsys device_state``."""
    for line in dump.splitlines():
        if "mCommittedState" in line or "Committed state" in line:
            return line.strip()
    return ""


def running_emulators() -> dict[str, str]:
    """Map every running emulator serial to its AVD name.

    Returns:
        ``{serial: avd_name}`` (name ``"?"`` if the console did not answer).
    """
    out = subprocess.run([adb_path(), "devices"], capture_output=True, text=True,
                         timeout=30).stdout
    result = {}
    for line in out.splitlines()[1:]:
        serial = line.split("\t")[0].strip()
        if not serial.startswith("emulator-"):
            continue
        try:
            name = subprocess.run([adb_path(), "-s", serial, "emu", "avd", "name"],
                                  capture_output=True, text=True, timeout=15).stdout
        except subprocess.TimeoutExpired:
            name = ""  # unresponsive console: treated as foreign, never killed
        result[serial] = (name.strip().splitlines() or ["?"])[0].strip() or "?"
    return result


def fst_process_ids(listing: str) -> list[int]:
    """Pick FST emulator processes out of a ``pid<TAB>command line`` listing.

    Matches only processes launched with an ``FST_`` AVD on the FST console
    port, so other projects' emulators are never selected.

    Args:
        listing: One ``pid\tcommandline`` per line.

    Returns:
        Matching process ids.
    """
    pids = []
    for line in listing.splitlines():
        pid, _, command = line.partition("\t")
        if (pid.strip().isdigit() and re.search(r"-avd\s+FST_\w+", command)
                and re.search(rf"-port\s+{FST_PORT}\b", command)):
            pids.append(int(pid))
    return pids


def _process_listing() -> str:
    """List emulator/qemu processes as ``pid<TAB>command line`` lines."""
    if os.name == "nt":
        script = ("Get-CimInstance Win32_Process -Filter \"Name like 'qemu-system%' or "
                  "Name = 'emulator.exe'\" | ForEach-Object { \"$($_.ProcessId)`t$($_.CommandLine)\" }")
        listing = subprocess.run(["powershell", "-NoProfile", "-Command", script],
                                 capture_output=True, text=True, timeout=60).stdout
    else:
        out = subprocess.run(["ps", "-eo", "pid=,args="], capture_output=True, text=True,
                             timeout=30).stdout
        listing = "\n".join(line.strip().replace(" ", "\t", 1) for line in out.splitlines())
    return listing


def kill_fst_processes() -> list[int]:
    """Kill hung/orphaned FST emulator processes that adb can no longer reach.

    Returns:
        Process ids that were killed.
    """
    pids = fst_process_ids(_process_listing())
    for pid in pids:
        if os.name == "nt":
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True)
        else:
            subprocess.run(["kill", "-9", str(pid)], capture_output=True)
    return pids


def adb_serials() -> dict[str, str]:
    """Map ``adb devices`` serials to their state (``device``, ``offline``, ...)."""
    out = subprocess.run([adb_path(), "devices"], capture_output=True, text=True,
                         timeout=30).stdout
    return dict(line.split("\t", 1) for line in out.splitlines()[1:] if "\t" in line)


def wait_for_exit(serial: str, deadline: float) -> None:
    """Wait until the emulator behind ``serial`` has exited.

    For the FST serial the emulator processes are the source of truth (adb may
    keep listing a dead emulator as ``offline`` for a while).
    """
    while time.monotonic() < deadline:
        if serial == FST_SERIAL:
            if not fst_process_ids(_process_listing()):
                return
        elif serial not in adb_serials():
            return
        time.sleep(1)
    raise DeviceError(f"{serial} did not shut down in time")


def stop_emulator(device: Device, serial: str, lock: HostLock) -> None:
    """Power an emulator off gracefully, killing it only as a fallback.

    ``adb emu kill`` stops qemu immediately and can lose recent ``/data``
    writes (e.g. a just-installed APK), so a clean ``reboot -p`` comes first.

    Args:
        device: Any :class:`Device` (used for its lock-bounded adb).
        serial: Emulator serial to stop.
        lock: Held emulator lock.
    """
    device.adb("shell", "sync", serial=serial, check=False, cap=20)
    device.adb("shell", "reboot -p", serial=serial, check=False, cap=20)
    try:
        wait_for_exit(serial, time.monotonic() + min(40, lock.remaining()))
        return
    except DeviceError:
        pass
    device.adb("emu", "kill", serial=serial, check=False, cap=20)
    try:
        wait_for_exit(serial, time.monotonic() + min(20, lock.remaining()))
    except DeviceError:
        if serial != FST_SERIAL:
            raise
        kill_fst_processes()


def boot_exclusive(lock: HostLock, avd: str, *, window: bool = False, gpu: str,
                   allow_foreign: bool = False, animations: bool = False) -> Device:
    """Ensure ``avd`` (and only it) is running on the FST serial.

    Other ``FST_*`` emulators are shut down; non-FST emulators are never
    touched, and their presence aborts the boot unless ``allow_foreign``.
    Call only while holding the ``emulator`` lock.

    Args:
        lock: Held emulator lock.
        avd: AVD to boot.
        window: Show the emulator window.
        gpu: Emulator ``-gpu`` mode.
        allow_foreign: Boot even if another project's emulator is running.
        animations: Keep system animations (default: scales set to 0).

    Returns:
        A :class:`Device` for the booted emulator.

    Raises:
        DeviceError: Unknown AVD, a foreign emulator, or a boot failure.
    """
    if not avd.startswith(FST_PREFIX):
        raise DeviceError(f"refusing to manage non-FST AVD {avd!r}")
    if not (avd_home() / f"{avd}.avd").exists():
        raise DeviceError(f"AVD {avd} does not exist; run `device.py avds --create`")
    running = running_emulators()
    device = Device(lock)
    if running.get(FST_SERIAL) == avd:
        return device
    # Port 5580 is reserved for FST, so anything there (even unresponsive) is ours.
    running = {s: (n if s != FST_SERIAL or n.startswith(FST_PREFIX) else "FST_?")
               for s, n in running.items()}
    foreign = {s: n for s, n in running.items() if not n.startswith(FST_PREFIX)}
    if foreign and not allow_foreign:
        raise DeviceError(f"another emulator is running ({foreign}); one product emulator per "
                          "host. Stop it via its owner, or pass --allow-foreign.")
    for serial, name in running.items():
        if name.startswith(FST_PREFIX):
            print(f"shutting down {name} ({serial})", file=sys.stderr)
            stop_emulator(device, serial, lock)
    orphans = kill_fst_processes()
    if orphans:
        print(f"killed orphaned FST emulator processes {orphans}", file=sys.stderr)
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    log = open(STATE_DIR / f"emulator-{avd}.log", "w", encoding="utf-8")
    flags = 0
    if os.name == "nt":
        flags = (subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
                 | 0x01000000)  # CREATE_BREAKAWAY_FROM_JOB: outlive the SSH job
    cmd = [emulator_path(), *emulator_args(avd, window=window, gpu=gpu)]
    print("+", " ".join(cmd), file=sys.stderr)
    try:
        proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL, creationflags=flags)
    except OSError:
        flags &= ~0x01000000
        proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL, creationflags=flags)
    start = time.monotonic()
    while True:
        if proc.poll() is not None:
            raise DeviceError(f"emulator exited with {proc.returncode}; see {log.name}")
        state = device.adb("shell", "getprop sys.boot_completed", check=False, cap=10)
        if state.returncode == 0 and state.stdout.strip() == "1":
            break
        if lock.remaining(floor=0) < 5:
            kill_tree(proc)
            kill_fst_processes()
            raise DeviceError(f"{avd} did not boot within the lock hold; see {log.name}")
        time.sleep(2)
    print(f"{avd} booted in {time.monotonic() - start:.0f}s", file=sys.stderr)
    # A first launch right after boot can beat networking; 10.0.2.2 is the host
    # loopback alias, reachable without internet access once the network is up.
    online_by = time.monotonic() + min(30, lock.remaining(floor=0))
    while time.monotonic() < online_by:
        if device.adb("shell", "ping -c 1 -W 1 10.0.2.2", check=False, cap=5).returncode == 0:
            break
        time.sleep(1)
    else:
        print("warning: emulator network not up after boot", file=sys.stderr)
    device.shell("input keyevent KEYCODE_WAKEUP", check=False)
    device.shell("wm dismiss-keyguard", check=False)
    if not animations:
        for key in ("window_animation_scale", "transition_animation_scale",
                    "animator_duration_scale"):
            device.shell(f"settings put global {key} 0", check=False)
    return device


def resolve_launcher(device: Device, package: str) -> str:
    """Find the launcher activity component for ``package``."""
    out = device.shell(f"cmd package resolve-activity --brief "
                       f"-a android.intent.action.MAIN -c android.intent.category.LAUNCHER "
                       f"{remote_quote(package)}")
    lines = [line.strip() for line in out.splitlines() if "/" in line]
    if not lines:
        raise DeviceError(f"{package} is not installed or has no launcher activity")
    return lines[-1]


def apply_pose(device: Device, avd: str, pose: str) -> None:
    """Apply a hinge posture, or a resize preset on the resizable AVD.

    Args:
        device: Booted device.
        avd: AVD name.
        pose: Posture name/angles, or a ``RESIZE_PRESETS`` key for ``FST_Resizable``.
    """
    if AVDS.get(avd, AvdSpec("", "")).form == "resizable":
        apply_resize(device, pose)
    else:
        apply_posture(device, avd, pose)


def apply_posture(device: Device, avd: str, posture: str) -> tuple[int, ...]:
    """Set hinge angles for a named posture on a foldable AVD.

    Args:
        device: Booted device.
        avd: AVD name (selects the form factor).
        posture: Posture name or explicit angles.

    Returns:
        The applied angles.
    """
    spec = AVDS.get(avd)
    if spec is None:
        raise DeviceError(f"{avd} is not in the FST matrix")
    angles = posture_angles(spec.form, posture)
    for index, angle in enumerate(angles):
        device.emu("sensor", "set", f"hinge-angle{index}", str(angle))
    if spec.form == "trifold":
        size, features = trifold_layout(angles)
        device.shell(f"wm size {size or 'reset'}")
        set_display_features(device, features)
    time.sleep(1.5)
    return angles

# endregion

# region Commands


def _lock(args: argparse.Namespace, purpose: str) -> HostLock:
    return HostLock("emulator", purpose=f"{purpose} [{Path.cwd().name}]",
                    hold_seconds=args.hold, wait_seconds=args.wait_timeout)


def _booted(args: argparse.Namespace, lock: HostLock) -> Device:
    return boot_exclusive(lock, args.avd, window=args.window, gpu=args.gpu,
                          allow_foreign=args.allow_foreign, animations=args.animations)


def cmd_list(args: argparse.Namespace) -> int:
    """Print the FST matrix, installed AVDs, running emulators and lock state."""
    installed = {p.stem for p in avd_home().glob("*.avd")}
    print("FST AVD matrix:")
    for name, spec in AVDS.items():
        mark = "installed" if name in installed else "MISSING"
        print(f"  {name:<18} {spec.device:<18} {spec.form:<10} {mark:<9} {spec.note}")
    others = sorted(installed - set(AVDS))
    if others:
        print("Other AVDs (never managed): " + ", ".join(others))
    running = running_emulators()
    print("Running emulators: " + (", ".join(f"{n} ({s})" for s, n in running.items()) or "none"))
    lock = HostLock("emulator")
    holder = lock.holder()
    print("Emulator lock: " + ("free" if lock.is_free() else
                               f"held by pid {holder and holder.get('pid')} "
                               f"({holder and holder.get('purpose')})"))
    waiting = lock.waiting()
    if waiting:
        print(f"Queue: {waiting}")
    return 0


def cmd_avds(args: argparse.Namespace) -> int:
    """Create or re-create the FST AVD matrix deterministically."""
    names = args.only or list(AVDS)
    if not args.create:
        for name in names:
            print(f"{name}: {'exists' if (avd_home() / f'{name}.avd').exists() else 'missing'}")
        return 0
    for name in names:
        spec = AVDS[name]
        path = avd_home() / f"{name}.avd"
        if path.exists() and not args.force:
            print(f"{name}: exists (use --force to re-create)")
            continue
        cmd = [avdmanager_path(), "create", "avd", "-n", name, "-k", SYSTEM_IMAGE,
               "-d", spec.device, "--force"]
        print("+", " ".join(cmd), file=sys.stderr)
        # The .bat wrapper splits ';' unless the argument reaches cmd.exe quoted.
        result = subprocess.run(subprocess.list2cmdline(cmd) if os.name == "nt" else cmd,
                                input="no\n", capture_output=True, text=True, timeout=300)
        if result.returncode != 0:
            print(result.stdout + result.stderr, file=sys.stderr)
            return result.returncode
        config = path / "config.ini"
        overrides = {**COMMON_CONFIG, **spec.config}
        config.write_text(config_lines(config.read_text(encoding="utf-8"), overrides),
                          encoding="utf-8")
        print(f"{name}: created ({spec.device}, {SYSTEM_IMAGE})")
    return 0


def cmd_boot(args: argparse.Namespace) -> int:
    """Boot one AVD exclusively and leave it running."""
    args.avd = args.name
    with _lock(args, f"boot {args.avd}") as lock:
        device = _booted(args, lock)
        print(json.dumps(device.metadata(args.avd), indent=2))
    return 0


def cmd_shutdown(args: argparse.Namespace) -> int:
    """Shut down every running FST emulator (never foreign ones)."""
    with _lock(args, "shutdown") as lock:
        device = Device(lock)
        for serial, name in running_emulators().items():
            if name.startswith(FST_PREFIX) or serial == FST_SERIAL:
                print(f"shutting down {name} ({serial})")
                stop_emulator(device, serial, lock)
        orphans = kill_fst_processes()
        if orphans:
            print(f"killed orphaned FST emulator processes {orphans}")
    return 0


#: A ``display_features`` value that parses to no features. An empty/deleted
#: setting would fall back to the image's ``config_display_features``.
NO_DISPLAY_FEATURES = "none"


def set_display_features(device: Device, features: str) -> None:
    """Override the folding features the WindowManager extensions report.

    Args:
        device: Booted device.
        features: ``fold-[l,t,r,b]-flat;...`` or empty for none.
    """
    value = features or NO_DISPLAY_FEATURES
    device.shell(f"settings put global display_features {remote_quote(value)}")


def apply_resize(device: Device, preset: str) -> None:
    """Apply a resizable-device preset via window-manager overrides.

    Args:
        device: Booted ``FST_Resizable`` device.
        preset: Key of ``RESIZE_PRESETS``.

    Raises:
        DeviceError: Unknown preset.
    """
    if preset not in RESIZE_PRESETS:
        raise DeviceError(f"resizable presets: {', '.join(RESIZE_PRESETS)}")
    size, density, features = RESIZE_PRESETS[preset]
    device.shell(f"wm size {size or 'reset'}")
    device.shell(f"wm density {density or 'reset'}")
    set_display_features(device, features)
    time.sleep(2)


def cmd_posture(args: argparse.Namespace) -> int:
    """Set a fold posture (or resizable preset) on the target AVD."""
    with _lock(args, f"posture {args.posture} {args.avd}") as lock:
        device = _booted(args, lock)
        spec = AVDS[args.avd]
        if spec.form == "resizable":
            apply_resize(device, args.posture)
        else:
            apply_posture(device, args.avd, args.posture)
        print(json.dumps(device.metadata(args.avd), indent=2))
    return 0


def cmd_install(args: argparse.Namespace) -> int:
    """Install (replace) an APK on the target AVD."""
    if not Path(args.apk).is_file():
        raise DeviceError(f"no APK at {args.apk}")
    with _lock(args, f"install {Path(args.apk).name} {args.avd}") as lock:
        _install(_booted(args, lock), args.apk)
    return 0


def _install(device: Device, apk: str) -> None:
    """Install (replace, grant runtime permissions) an APK on the booted device."""
    path = Path(apk)
    if not path.is_file():
        raise DeviceError(f"no APK at {path}")
    print(device.adb("install", "-r", "-t", "-g", str(path), cap=180).stdout.strip(),
          file=sys.stderr)


def _prepare(device: Device, args: argparse.Namespace) -> None:
    """Optional in-hold install and posture before launching."""
    if getattr(args, "apk", None):
        _install(device, args.apk)
    if args.posture:
        apply_pose(device, args.avd, args.posture)


def _launch(device: Device, args: argparse.Namespace) -> None:
    component = args.activity or resolve_launcher(device, args.package)
    if component.startswith("."):
        component = f"{args.package}/{component}"
    extras = launch_extras(args.tab, args.route, parse_extras(args.extra))
    command = am_start_command(component, extras)
    output = device.shell(command, cap=60)
    if reused_instance(output):
        # The previous instance survived (install race): stop it and retry once.
        package = component.split("/", 1)[0]
        device.shell(f"am force-stop {remote_quote(package)}", check=False)
        deadline = time.monotonic() + 10
        while (device.shell(f"pidof {remote_quote(package)}", check=False).strip()
               and time.monotonic() < deadline):
            time.sleep(0.5)
        output = device.shell(command, cap=60)
        if reused_instance(output):
            raise DeviceError(f"launch reused a running instance; extras dropped:\n{output}")
    print(output.strip(), flush=True)


def cmd_launch(args: argparse.Namespace) -> int:
    """Cold-start the app with debug extras."""
    with _lock(args, f"launch {args.avd}") as lock:
        device = _booted(args, lock)
        _prepare(device, args)
        _launch(device, args)
    return 0


def cmd_shot(args: argparse.Namespace) -> int:
    """Optionally launch, then screenshot with a metadata sidecar."""
    with _lock(args, f"shot {args.avd}") as lock:
        device = _booted(args, lock)
        _prepare(device, args)
        if not args.no_launch:
            _launch(device, args)
        for index, out in enumerate(args.out):
            time.sleep(args.wait if index == 0 else args.interval)
            path = Path(out)
            device.screenshot(path)
            path.with_suffix(".json").write_text(
                json.dumps(device.metadata(args.avd), indent=2), encoding="utf-8")
            print(path)
    return 0


def run_step(device: Device, avd: str, verb: str, arg: str) -> None:
    """Execute one driver step on a booted device.

    Args:
        device: Booted device.
        avd: AVD name (for postures and metadata).
        verb: Step verb from :func:`parse_step`.
        arg: Step argument.
    """
    if verb in ("tap", "longpress", "waitfor"):
        selector, _, wait = arg.partition("@")
        kind, value = parse_selector(selector)
        if kind == "xy":
            x, y = (int(v) for v in value.split(","))
        else:
            give_up = time.monotonic() + (float(wait) if wait else 5.0)
            while True:
                point = find_center(device.dump_tree(), kind, value)
                if point or time.monotonic() > give_up:
                    break
                time.sleep(0.5)
            if not point:
                raise DeviceError(f"{verb}: no visible node for {selector}")
            x, y = point
        if verb == "tap":
            device.shell(f"input tap {x} {y}")
        elif verb == "longpress":
            device.shell(f"input swipe {x} {y} {x} {y} 800")
    elif verb == "swipe":
        x1, y1, x2, y2, ms = swipe_vector(arg, *device.screen_size())
        device.shell(f"input swipe {x1} {y1} {x2} {y2} {ms}")
    elif verb == "type":
        device.shell(f"input text {input_text_arg(arg)}")
    elif verb == "key":
        code = arg.upper() if arg.isdigit() or arg.upper().startswith("KEYCODE_") \
            else f"KEYCODE_{arg.upper()}"
        device.shell(f"input keyevent {code}")
    elif verb == "back":
        device.shell("input keyevent KEYCODE_BACK")
    elif verb == "home":
        device.shell("input keyevent KEYCODE_HOME")
    elif verb == "wait":
        time.sleep(float(arg))
    elif verb == "shot":
        device.screenshot(Path(arg))
        Path(arg).with_suffix(".json").write_text(json.dumps(device.metadata(avd), indent=2),
                                                  encoding="utf-8")
    elif verb == "tree":
        Path(arg).parent.mkdir(parents=True, exist_ok=True)
        Path(arg).write_text(device.dump_tree(), encoding="utf-8")
    elif verb == "posture":
        apply_pose(device, avd, arg)
    elif verb == "rotate":
        quarter = {"0": 0, "90": 1, "180": 2, "270": 3}.get(arg)
        if quarter is None:
            raise DeviceError("rotate: use 0, 90, 180 or 270")
        device.shell("settings put system accelerometer_rotation 0")
        device.shell(f"settings put system user_rotation {quarter}")
        time.sleep(1)
    elif verb == "resize":
        apply_resize(device, arg)
    elif verb == "record":
        if arg.lower() == "stop":
            print(device.stop_recording() or "record: nothing recording", file=sys.stderr)
        else:
            device.start_recording(Path(arg))
    elif verb == "talkback":
        enabled = toggle_arg(arg)
        services = TALKBACK_SERVICE if enabled else '""'
        device.shell(f"settings put secure enabled_accessibility_services {services}")
        device.shell(f"settings put secure accessibility_enabled {int(enabled)}")
        time.sleep(2)
    elif verb == "fontscale":
        scale = float(arg)
        if not 0.5 <= scale <= 2.0:
            raise ValueError("fontscale must be within 0.5-2.0")
        device.shell(f"settings put system font_scale {scale}")
        time.sleep(1)
    elif verb == "dark":
        device.shell(f"cmd uimode night {'yes' if toggle_arg(arg) else 'no'}")
        time.sleep(1)
    print(f"ok {verb}:{arg}", file=sys.stderr)


def cmd_drive(args: argparse.Namespace) -> int:
    """Run a scripted step sequence (optionally after a launch)."""
    steps = [parse_step(s) for s in parse_steps(args.steps, args.steps_file)]
    with _lock(args, f"drive {args.avd}") as lock:
        device = _booted(args, lock)
        _prepare(device, args)
        if args.launch:
            _launch(device, args)
            time.sleep(args.wait)
        try:
            for verb, arg in steps:
                run_step(device, args.avd, verb, arg)
        finally:
            clip = device.stop_recording()  # an unstopped record: step ends with the drive
            if clip:
                print(clip, file=sys.stderr)
    return 0


def find_gradle(project: Path) -> list[str]:
    """Locate a Gradle launcher: project wrapper, PATH, then a cached distribution.

    Args:
        project: Android Gradle project directory.

    Returns:
        Command prefix to run Gradle.

    Raises:
        DeviceError: No Gradle found.
    """
    wrapper = project / ("gradlew.bat" if os.name == "nt" else "gradlew")
    if wrapper.exists() and (project / "gradle" / "wrapper" / "gradle-wrapper.jar").exists():
        return [str(wrapper)]
    on_path = shutil.which("gradle")
    if on_path:
        return [on_path]
    name = "gradle.bat" if os.name == "nt" else "gradle"
    cached = sorted((Path.home() / ".gradle" / "wrapper" / "dists").glob(f"gradle-*/*/gradle-*/bin/{name}"))
    if cached:
        return [str(cached[-1])]
    raise DeviceError("no Gradle wrapper, gradle on PATH, or cached distribution")


def cmd_test(args: argparse.Namespace) -> int:
    """Run connected instrumentation tests on one AVD within the lock hold."""
    project = Path(args.project).resolve()
    with _lock(args, f"test {args.filter or 'all'} {args.avd}") as lock:
        device = _booted(args, lock)
        if args.posture:
            # Fold/tri-fold posture or resizable preset for posture-dependent layouts.
            apply_pose(device, args.avd, args.posture)
        cmd = find_gradle(project) + gradle_test_args(args.filter, args.task)
        env = dict(os.environ, ANDROID_SERIAL=FST_SERIAL)
        print("+", " ".join(cmd), file=sys.stderr)
        proc = lock.track(subprocess.Popen(cmd, cwd=project, env=env))
        try:
            return proc.wait(timeout=lock.remaining())
        except subprocess.TimeoutExpired:
            kill_tree(proc)
            print(f"TIMEOUT: tests exceeded the {lock.hold_seconds:.0f}s hold", file=sys.stderr)
            return 124


def build_probe() -> Path:
    """Build the WindowManager probe APK without Gradle (cached by source hash).

    Uses the newest SDK platform/build-tools: ``javac`` → ``d8`` → ``aapt2
    link`` → ``zipalign`` → ``apksigner`` with a lab-only keystore.

    Returns:
        Path to the signed probe APK.
    """
    import hashlib
    import zipfile

    sources = sorted(PROBE_DIR.rglob("*.java")) + [PROBE_DIR / "AndroidManifest.xml"]
    digest = hashlib.sha256(b"".join(f.read_bytes() for f in sources)).hexdigest()[:12]
    out = PROBE_BUILD_DIR / digest
    apk = out / "probe.apk"
    if apk.exists():
        return apk
    sdk = sdk_root()
    platform = max((sdk / "platforms").glob("android-*/android.jar"),
                   key=lambda p: [int(x) for x in re.findall(r"\d+", p.parent.name)])
    tools = max((sdk / "build-tools").iterdir(),
                key=lambda p: [int(x) for x in re.findall(r"\d+", p.name)])
    bat = ".bat" if os.name == "nt" else ""
    exe = ".exe" if os.name == "nt" else ""
    classes, dex = out / "classes", out / "dex"
    classes.mkdir(parents=True, exist_ok=True)
    dex.mkdir(exist_ok=True)

    def run(cmd: list[str]) -> None:
        print("+", " ".join(cmd), file=sys.stderr)
        subprocess.run(cmd, check=True, timeout=180)

    run(["javac", "-source", "11", "-target", "11", "-nowarn", "-classpath", str(platform),
         "-d", str(classes), *[str(f) for f in sources if f.suffix == ".java"]])
    run([str(tools / f"d8{bat}"), "--min-api", "30", "--lib", str(platform),
         "--output", str(dex), *[str(f) for f in classes.rglob("*.class")]])
    unsigned = out / "unsigned.apk"
    run([str(tools / f"aapt2{exe}"), "link", "-o", str(unsigned), "-I", str(platform),
         "--manifest", str(PROBE_DIR / "AndroidManifest.xml"),
         "--min-sdk-version", "30", "--target-sdk-version", "36"])
    with zipfile.ZipFile(unsigned, "a") as archive:
        archive.write(dex / "classes.dex", "classes.dex")
    aligned = out / "aligned.apk"
    run([str(tools / f"zipalign{exe}"), "-f", "-p", "4", str(unsigned), str(aligned)])
    keystore = PROBE_BUILD_DIR / "lab-probe.keystore"
    if not keystore.exists():
        run(["keytool", "-genkeypair", "-keystore", str(keystore), "-storepass", "fstprobe",
             "-keypass", "fstprobe", "-alias", "probe", "-keyalg", "RSA", "-validity", "10000",
             "-dname", "CN=FST Device Lab Probe"])
    run([str(tools / f"apksigner{bat}"), "sign", "--ks", str(keystore), "--ks-pass",
         "pass:fstprobe", "--out", str(apk), str(aligned)])
    return apk


def probe_features(device: Device, settle: float = 3.0) -> dict:
    """Launch the probe and return its latest WindowManager report.

    Args:
        device: Booted device with the probe installed.
        settle: Seconds to wait for layout callbacks.

    Returns:
        Parsed report from :func:`parse_probe_line`.
    """
    device.adb("logcat", "-c", check=False)
    device.shell(am_start_command(f"{PROBE_PACKAGE}/.ProbeActivity", []))
    time.sleep(settle)
    log = device.adb("logcat", "-d", "-s", "FST_PROBE:I", cap=30).stdout
    reports = [r for r in (parse_probe_line(line) for line in log.splitlines()) if r]
    if not reports:
        raise DeviceError("probe produced no FST_PROBE report")
    return reports[-1]


def cmd_features(args: argparse.Namespace) -> int:
    """Report the FoldingFeatures Jetpack WindowManager sees, per posture."""
    apk = build_probe()
    with _lock(args, f"features {args.avd}") as lock:
        device = _booted(args, lock)
        device.adb("install", "-r", "-t", str(apk), cap=120)
        for posture in args.postures or [None]:
            if posture:
                apply_pose(device, args.avd, posture)
            report = probe_features(device)
            report.update(posture=posture or "current", device_state=_committed_state(
                device.shell("dumpsys device_state", check=False)))
            print(json.dumps(report), flush=True)
        device.shell(f"am force-stop {PROBE_PACKAGE}", check=False)
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Build the CLI parser (exposed for unit tests)."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--hold", type=float, default=300.0,
                        help="max seconds to hold the emulator lock (≤300)")
    common.add_argument("--wait-timeout", type=float, default=1800.0,
                        help="max seconds to queue for the lock")
    target = argparse.ArgumentParser(add_help=False, parents=[common])
    target.add_argument("--avd", default=DEFAULT_AVD, choices=sorted(AVDS))
    target.add_argument("--window", action="store_true",
                        help="show the emulator window (interactive session only)")
    target.add_argument("--gpu", default="swiftshader_indirect")
    target.add_argument("--allow-foreign", action="store_true")
    target.add_argument("--animations", action="store_true",
                        help="keep system animations (default: scales 0)")
    app = argparse.ArgumentParser(add_help=False)
    app.add_argument("--package", default=DEFAULT_PACKAGE)
    app.add_argument("--activity", help="component or .Activity (default: launcher)")
    app.add_argument("--tab", help="FST_DEBUG_TAB extra")
    app.add_argument("--route", help="FST_DEBUG_ROUTE extra")
    app.add_argument("--extra", action="append", metavar="KEY=VALUE",
                     help="additional string intent extra (repeatable)")
    app.add_argument("--posture", help="apply a posture before launching")
    app.add_argument("--apk", help="install (replace) this APK first, in the same lock hold")

    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="matrix, running emulators, lock").set_defaults(func=cmd_list)
    avds = sub.add_parser("avds", help="show or create the FST AVD matrix")
    avds.add_argument("--create", action="store_true")
    avds.add_argument("--force", action="store_true", help="re-create existing AVDs")
    avds.add_argument("--only", action="append", choices=sorted(AVDS))
    avds.set_defaults(func=cmd_avds)
    boot = sub.add_parser("boot", parents=[target], help="boot one AVD exclusively")
    boot.add_argument("name", choices=sorted(AVDS))
    boot.set_defaults(func=cmd_boot)
    sub.add_parser("shutdown", parents=[common],
                   help="shut down FST emulators").set_defaults(func=cmd_shutdown)
    posture = sub.add_parser("posture", parents=[target], help="fold posture / resize preset")
    posture.add_argument("posture")
    posture.set_defaults(func=cmd_posture)
    install = sub.add_parser("install", parents=[target], help="install an APK")
    install.add_argument("apk")
    install.set_defaults(func=cmd_install)
    sub.add_parser("launch", parents=[target, app],
                   help="cold-start with debug extras").set_defaults(func=cmd_launch)
    shot = sub.add_parser("shot", parents=[target, app], help="launch + screenshot")
    shot.add_argument("out", nargs="+", help="PNG path(s); a .json sidecar is written")
    shot.add_argument("--wait", type=float, default=3.0)
    shot.add_argument("--interval", type=float, default=1.0)
    shot.add_argument("--no-launch", action="store_true", help="screenshot current screen")
    shot.set_defaults(func=cmd_shot)
    drive = sub.add_parser("drive", parents=[target, app], help="scripted UI steps")
    drive.add_argument("--steps")
    drive.add_argument("--steps-file")
    drive.add_argument("--launch", action="store_true", help="cold-start the app first")
    drive.add_argument("--wait", type=float, default=2.0)
    drive.set_defaults(func=cmd_drive)
    features = sub.add_parser("features", parents=[target],
                              help="FoldingFeatures seen by WindowManager (probe APK)")
    features.add_argument("postures", nargs="*", help="postures to cycle through")
    features.set_defaults(func=cmd_features)
    test = sub.add_parser("test", parents=[target], help="connected tests on one AVD")
    test.add_argument("filter", nargs="?",
                      help="pkg.Class, pkg.Class#method or package:pkg (default: all)")
    test.add_argument("--project", default=str(REPO_ROOT / "android"))
    test.add_argument("--task", default=":app:connectedDebugAndroidTest")
    test.add_argument("--posture", help="apply a posture (or resizable preset) before the tests run")
    test.set_defaults(func=cmd_test)
    return parser


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        Process exit code (2 usage, 3 device error, 124 timeout).
    """
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except (DeviceError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 3
    except LockTimeout as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 124

# endregion


if __name__ == "__main__":
    sys.exit(main())
