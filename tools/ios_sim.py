#!/usr/bin/env python3
"""Serialized iOS simulator access for parallel agent lanes.

Many lanes build in parallel (each in its own git worktree and DerivedData),
but only ONE product simulator may run at a time on this Mac. Every simulator
interaction goes through this tool, which holds an exclusive ``flock`` on
``~/.fst-sim.lock`` for the whole install/launch/screenshot sequence.

Every local ``xcodebuild`` invocation (``build``, and ``drive``'s
``build-for-testing``) is separately serialized on ``~/.fst-build.lock`` —
several lanes compiling at once has driven load average far past this Mac's
core count. The build lock and the simulator lock are never held together:
a build fully finishes and releases ``~/.fst-build.lock`` before ``drive``
requests ``~/.fst-sim.lock`` for the actual device interaction. This mirrors
``tools/lane_integrate.sh``, which wraps its own ``swift build`` in the same
``~/.fst-build.lock`` (via ``lockf``) and calls ``ios_sim.py build`` after
releasing it, so this module never re-enters that lock from a child process.

Examples::

    # Build the iOS app from the current worktree (no lock needed).
    python3 tools/ios_sim.py build

    # Install, launch on a debug route, and screenshot (takes the lock).
    python3 tools/ios_sim.py shot --out /tmp/lb.png --tab leaderboards
    python3 tools/ios_sim.py shot --out /tmp/p.png --route player:195e93ef108143b2975ee46662d4d0e1

    # Several screenshots in one lock hold, e.g. per tab.
    python3 tools/ios_sim.py shot --out /tmp/songs.png --out /tmp/songs2.png --wait 4

    # Script taps/swipes/screenshots (builds the UI-test bundle once, then
    # reuses it; still serialized under the same simulator lock).
    python3 tools/ios_sim.py drive --tab settings \
        --steps "tap:fst.shell.drawer.open; shot:/tmp/drawer.png; tree:/tmp/drawer.tree.txt"

    # Run real XCUITest journey classes (batched into one simulator-lock hold).
    python3 tools/ios_sim.py uitest \
        --only ShellJourneyTests --only LeaderboardsJourneyTests

    # apple-ci only: a throwaway runner simulator, and fail when a journey skips.
    python3 tools/ios_sim.py uitest --device "$(python3 tools/ios_sim.py ci-device)" \
        --fail-on-skip --only SongsChromeJourneyTests/testSectionBarHeadingAtLargestText

Devices are named by alias (see ``DEVICES``) or UDID. The default is the
iPhone 17 Pro on iOS 26.5 (Liquid Glass).
"""

from __future__ import annotations

import argparse
import fcntl
import signal
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from dataclasses import dataclass
from typing import Iterable, Iterator

# region Configuration

DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer"
BUNDLE_ID = "com.sfenton.festivalscoretracker.native"
LOCK_PATH = Path.home() / ".fst-sim.lock"
BUILD_LOCK_PATH = Path.home() / ".fst-build.lock"
REPO_ROOT = Path(__file__).resolve().parent.parent
APPLE_DIR = REPO_ROOT / "apple"

#: Alias -> simulator UDID. Keep in sync with `.agents/platforms/apple/simulators.md`.
DEVICES = {
    "iphone": "4E9F2A49-127D-40BC-A909-08AF3D4BE6A5",  # FST iOS 26.5 iPhone 17 Pro
    "iphone27": "32DF9891-BCDB-46FB-9317-35EC1239267E",  # FST iOS 27 Fresh iPhone 17 Pro
    "ipad": "11E2F7B2-DE32-4466-8A97-04B37F559086",  # FST Native iPad Pro 11 (26.5)
    "duo": "BC8A530D-805F-45FD-9D32-71B838C7A05F",  # iPhone Duo (FST), iOS 27.1
    "promax": "F397FB0A-7466-4D40-95BD-2E4EF91C4224",  # FST App Store iPhone 17 Pro Max (26.5), 6.9" shots
}

#: App Store marketing status bar (``simctl status_bar override`` flags): 9:41, full signal, charged.
CLEAN_STATUS_BAR = (
    "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
    "--cellularMode", "active", "--cellularBars", "4", "--operatorName", "",
    "--batteryState", "charged", "--batteryLevel", "100",
)

#: Source trees that, if changed, require rebuilding the driver's UI-test bundle.
DRIVER_HASH_ROOTS = ("Sources", "Apps/iOS", "Apps/iOSUITests", "Apps/iPadOSUITests", "project.yml")


@dataclass(frozen=True)
class AppProduct:
    """One installable iOS app target and its UI-test bundle.

    Attributes:
        scheme: Xcode scheme building the app and its UI tests.
        app_name: Built ``.app`` name (without the extension).
        bundle_id: Bundle identifier used by ``simctl launch``/``terminate``.
        uitest_target: UI-test target name for ``-only-testing:``.
        driver_dir: DerivedData folder (under ``apple/DerivedData``) for the UI-test build.
    """

    scheme: str
    app_name: str
    bundle_id: str
    uitest_target: str
    driver_dir: str


#: One universal app (iPhone + iPad, operator 2026-10-02) with two UI-test bundles: the
#: iPhone journeys (scheme FestivalMobile) and the iPad journeys (scheme FestivalMobileIPad).
PRODUCTS = {
    "phone": AppProduct(
        "FestivalMobile", "FestivalMobile", BUNDLE_ID, "FestivalMobileUITests", "lane-driver"
    ),
    "ipad": AppProduct(
        "FestivalMobileIPad", "FestivalMobile", BUNDLE_ID, "FestivalMobileIPadUITests", "lane-driver-ipad"
    ),
}

#: Device aliases that run the iPad UI-test bundle by default (``--app`` overrides).
DEVICE_PRODUCTS = {"ipad": "ipad"}

#: Product the current command targets; set once by ``main()``.
_product = PRODUCTS["phone"]


def product() -> AppProduct:
    """Return the app product the current command targets.

    Returns:
        The selected ``AppProduct`` (the iPhone journeys unless ``--app``/``--device`` chose iPad).
    """
    return _product


def select_product(app: str | None, device: str | None) -> AppProduct:
    """Choose the app product for a command.

    Args:
        app: Explicit ``--app`` value (``phone``/``ipad``), if given.
        device: ``--device`` alias or UDID, if the command takes one.

    Returns:
        The explicit product, else the device alias's default, else the iPhone app.
    """
    global _product
    key = app or DEVICE_PRODUCTS.get(device or "", "phone")
    _product = PRODUCTS[key]
    return _product

# endregion

# region Helpers


def _env() -> dict[str, str]:
    """Return the process environment with Xcode pinned.

    Returns:
        A copy of ``os.environ`` with ``DEVELOPER_DIR`` set.
    """
    env = dict(os.environ)
    env["DEVELOPER_DIR"] = DEVELOPER_DIR
    return env


def _run(cmd: list[str], check: bool = True, **kw) -> subprocess.CompletedProcess:
    """Run a command with Xcode pinned, echoing it to stderr.

    Args:
        cmd: Argument vector.
        check: Raise on non-zero exit.
        **kw: Extra ``subprocess.run`` keyword arguments.

    Returns:
        The completed process.
    """
    print("+", " ".join(cmd), file=sys.stderr)
    return subprocess.run(cmd, check=check, env=kw.pop("env", _env()), **kw)


@contextmanager
def build_lock():
    """Hold the exclusive cross-lane compile lock for one heavy ``xcodebuild`` call.

    Several lanes build in parallel worktrees on the same Mac; without this,
    enough concurrent ``xcodebuild`` processes can push load average far past
    the core count. Scope this as tightly as possible around the actual
    compile step (not ``xcodegen generate`` or simulator work), and never
    acquire ``LOCK_PATH`` (the simulator lock) while holding this one, or vice
    versa: a build must fully release this lock before ``drive`` requests the
    simulator lock. ``tools/lane_integrate.sh`` takes the same
    ``~/.fst-build.lock`` around its own ``swift build`` via ``lockf``, so
    this must not be held across a call out to that script either.

    Yields:
        Nothing; the lock is released when the ``with`` block exits.
    """
    BUILD_LOCK_PATH.touch(exist_ok=True)
    with open(BUILD_LOCK_PATH, "w") as lock:
        print(f"waiting for build lock {BUILD_LOCK_PATH} ...", file=sys.stderr)
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            lock.write(f"{os.getpid()} {REPO_ROOT}\n")
            lock.flush()
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def derived_data() -> Path:
    """Per-worktree DerivedData so parallel lanes never share build state.

    Returns:
        ``apple/DerivedData/lane`` inside the current worktree.
    """
    return APPLE_DIR / "DerivedData" / "lane"


def app_path() -> Path:
    """Locate the built simulator app for this worktree.

    Returns:
        Path to the selected product's ``.app`` (``FestivalMobile.app`` by default).

    Raises:
        SystemExit: If the app has not been built yet.
    """
    path = derived_data() / f"Build/Products/Debug-iphonesimulator/{product().app_name}.app"
    if not path.exists():
        sys.exit(f"No build at {path}; run `python3 tools/ios_sim.py build` first.")
    return path


def resolve_device(name: str) -> str:
    """Map an alias to a UDID.

    Args:
        name: Alias from ``DEVICES`` or a raw UDID.

    Returns:
        Simulator UDID.
    """
    return DEVICES.get(name, name)

# endregion

# region Driver steps


def parse_steps(steps: str | None, steps_file: str | None) -> list[str]:
    """Combine an inline step string and/or a step file into one ordered list.

    Both sources may be given (file contents first, then the inline string).
    Steps are newline- or ``;``-separated; blank lines and ``#`` comments are
    dropped.

    Args:
        steps: Inline ``;``-separated step script, or ``None``.
        steps_file: Path to a newline-separated step script, or ``None``.

    Returns:
        Ordered, non-empty step strings such as ``"tap:fst.nav.settings"``.

    Raises:
        ValueError: Neither source produced any steps.
    """
    raw: list[str] = []
    if steps_file:
        raw.extend(Path(steps_file).read_text(encoding="utf-8").splitlines())
    if steps:
        raw.extend(steps.split(";"))
    parsed = [item.strip() for item in raw]
    parsed = [item for item in parsed if item and not item.startswith("#")]
    if not parsed:
        raise ValueError("no driver steps provided (use --steps and/or --steps-file)")
    return parsed


def output_paths(steps: list[str]) -> list[str]:
    """Collect the host paths a ``shot:``/``tree:``/``audit:`` step will write.

    Args:
        steps: Parsed step strings.

    Returns:
        Requested output paths, in step order.
    """
    paths = []
    for step in steps:
        verb, _, arg = step.partition(":")
        if verb in ("shot", "tree", "audit", "systemTree", "windowFrame") and arg:
            paths.append(arg)
        elif verb == "appTree" and "|" in arg:
            paths.append(arg.split("|", 1)[1])
        elif verb == "host":
            try:
                command, values = parse_host_command(arg)
            except ValueError:
                continue
            if command == "capture":
                paths.append(values[1])
    return paths


#: ``host:`` driver-step commands and their argument counts (see ``run_host_command``).
HOST_COMMANDS = {"pose": 1, "capture": 2, "menu": 1, "control": 1}


def parse_host_command(text: str) -> tuple[str, list[str]]:
    """Parse a ``host:`` step's command (``pose unfolded``, ``capture inner /tmp/a.png``,
    ``menu Device/Keyboard/Toggle Software Keyboard``, ``control Capture Keyboard``).

    The last argument keeps its spaces (paths and menu titles may contain them).

    Args:
        text: The text after ``host:``.

    Returns:
        ``(command, arguments)``.

    Raises:
        ValueError: Unknown command or invalid arguments.
    """
    command, _, rest = text.strip().partition(" ")
    if command not in HOST_COMMANDS:
        raise ValueError(f"unknown host command {command!r}; choose from {sorted(HOST_COMMANDS)}")
    count = HOST_COMMANDS[command]
    values = rest.strip().split(None, count - 1) if rest.strip() else []
    if len(values) != count:
        raise ValueError(f"host command {command!r} takes {count} argument(s): {text!r}")
    if command == "pose" and values[0] not in POSE_ACTIONS:
        raise ValueError(f"host pose must be one of {POSE_ACTIONS}: {text!r}")
    if command == "capture" and (values[0] not in (*DUO_PANELS, "auto") or not values[1].startswith("/")):
        raise ValueError(f"host capture needs outer|inner|auto and an absolute path: {text!r}")
    return command, values


def driver_derived_data() -> Path:
    """Separate DerivedData for the UI-test bundle so `build`/`shot` are untouched.

    Returns:
        ``apple/DerivedData/lane-driver`` inside the current worktree.
    """
    return APPLE_DIR / "DerivedData" / product().driver_dir


def _iter_source_files(roots: Iterable[Path]) -> Iterator[Path]:
    """Yield every regular file under the given files/directories, sorted.

    Args:
        roots: Files or directories to walk.

    Yields:
        Regular files in deterministic order.
    """
    for root in roots:
        if root.is_file():
            yield root
        elif root.is_dir():
            yield from sorted(f for f in root.rglob("*") if f.is_file())


def source_hash(roots: Iterable[Path] | None = None) -> str:
    """Hash source file identity (path, size, mtime) to detect staleness cheaply.

    This is not a content hash: it is fast and sufficient to decide whether the
    UI-test bundle needs rebuilding, at the cost of missing a touch-only no-op
    edit that restores identical bytes but a new mtime (harmless: it just
    triggers one extra rebuild).

    Args:
        roots: Files/directories to hash; defaults to ``DRIVER_HASH_ROOTS``
            resolved under ``apple/``.

    Returns:
        Hex SHA-256 digest.
    """
    if roots is None:
        roots = [APPLE_DIR / name for name in DRIVER_HASH_ROOTS]
    digest = hashlib.sha256()
    for file in _iter_source_files(roots):
        stat = file.stat()
        digest.update(str(file).encode("utf-8"))
        digest.update(str(stat.st_size).encode("ascii"))
        digest.update(str(stat.st_mtime_ns).encode("ascii"))
    return digest.hexdigest()


def driver_build_stale(derived: Path, current_hash: str) -> bool:
    """Decide whether the cached UI-test build can be reused.

    Args:
        derived: The driver's DerivedData directory.
        current_hash: Fresh ``source_hash()`` of the worktree.

    Returns:
        True if a rebuild is needed (missing product, missing/mismatched marker).
    """
    runner = (
        derived / "Build/Products/Debug-iphonesimulator"
        / f"{product().uitest_target}-Runner.app"
    )
    marker = derived / ".driver-source-hash"
    if not runner.exists() or not marker.exists():
        return True
    return marker.read_text(encoding="utf-8").strip() != current_hash


def write_driver_hash(derived: Path, value: str) -> None:
    """Record the source hash a successful driver build was built from.

    Args:
        derived: The driver's DerivedData directory.
        value: ``source_hash()`` at build time.
    """
    derived.mkdir(parents=True, exist_ok=True)
    (derived / ".driver-source-hash").write_text(value, encoding="utf-8")



def boot_exclusive(udid: str) -> None:
    """Boot ``udid`` after shutting down every *other* FST product simulator.

    The operator rule is one product simulator running at a time. Only devices in
    ``DEVICES`` are ever shut down; other projects' simulators are never touched.
    Call this only while holding the simulator lock.

    Args:
        udid: Simulator to boot.
    """
    for other in set(DEVICES.values()) - {udid}:
        state = _run(["xcrun", "simctl", "list", "devices", other], check=False,
                     capture_output=True, text=True)
        if "(Booted)" in (state.stdout or ""):
            _run(["xcrun", "simctl", "shutdown", other], check=False, capture_output=True)
    _run(["xcrun", "simctl", "boot", udid], check=False, capture_output=True)

# endregion

# region iPhone Duo panels and pose

#: iPhone Duo panels as ``simctl io --display`` device names (the device type's
#: ``capabilities.plist`` ``displays``): outer 1398x2034 px, inner 2007x2853 px.
DUO_PANELS = {"outer": "primary", "inner": "primary-1"}

#: Pose implied by which panel is lit. Only Device Hub can *change* the pose (no
#: simctl/XCTest hinge control in Xcode 27.1); this tool can only verify it.
POSE_PANEL = {"folded": "outer", "unfolded": "inner"}


def bmp_is_dark(data: bytes, threshold: int = 8) -> bool:
    """Decide whether an uncompressed BMP screenshot is (near) black.

    An unlit Duo panel screenshots as pure black, so this identifies which panel
    the system is driving without any image library.

    Args:
        data: A 24- or 32-bit BMP (``simctl io screenshot --type=bmp``).
        threshold: Largest colour byte still considered black.

    Returns:
        True if no colour channel exceeds ``threshold``.

    Raises:
        ValueError: Not a 24/32-bit uncompressed BMP.
    """
    if data[:2] != b"BM" or len(data) < 54:
        raise ValueError("not a BMP")
    offset = int.from_bytes(data[10:14], "little")
    step = int.from_bytes(data[28:30], "little") // 8
    if step not in (3, 4):
        raise ValueError(f"unsupported BMP depth {step * 8}")
    pixels = data[offset:]
    # 24-bit rows are zero-padded (dark), so every byte may be checked; 32-bit skips alpha.
    channels = range(step) if step == 3 else range(3)
    return all(max(pixels[channel::step], default=0) <= threshold for channel in channels)


def classify_pose(outer_dark: bool, inner_dark: bool) -> str:
    """Map lit panels to a pose name.

    Args:
        outer_dark: The outer (cover) panel screenshot is black.
        inner_dark: The inner (unfolding) panel screenshot is black.

    Returns:
        ``"folded"``, ``"unfolded"`` or ``"unknown"`` (both or neither lit).
    """
    if not outer_dark and inner_dark:
        return "folded"
    if outer_dark and not inner_dark:
        return "unfolded"
    return "unknown"


def screenshot_panel(udid: str, display: str, path: Path, attempts: int = 3,
                     timeout: float = 120.0, pause: float = 10.0) -> bool:
    """Screenshot one Duo panel as BMP, retrying. Call under the simulator lock.

    The first screenshot after a fresh boot can fail or stall, above all on the
    slow CI runner just after it installed a new runtime (apple-ci run
    37913520235), so each failed attempt is logged with its reason and retried.

    Args:
        udid: A booted iPhone Duo simulator.
        display: ``simctl io --display`` name (a ``DUO_PANELS`` value).
        path: Where to write the BMP.
        attempts: Screenshots to try.
        timeout: Seconds one attempt may take.
        pause: Seconds between attempts.

    Returns:
        Whether a screenshot was written.
    """
    for attempt in range(1, attempts + 1):
        try:
            result = _run(["xcrun", "simctl", "io", udid, "screenshot", "--type=bmp",
                           f"--display={display}", str(path)], check=False, capture_output=True,
                          timeout=timeout)
        except subprocess.TimeoutExpired:
            reason = f"timed out after {timeout:.0f}s"
        else:
            if not result.returncode and path.exists():
                return True
            stderr = result.stderr.decode(errors="replace") if isinstance(result.stderr, bytes) else result.stderr
            reason = (stderr or "").strip()[-300:] or f"exit {result.returncode}"
        print(f"duo pose: {display} screenshot failed ({reason}), attempt {attempt}/{attempts}",
              file=sys.stderr)
        if attempt < attempts:
            time.sleep(pause)
    return False


def detect_pose(udid: str) -> str:
    """Screenshot both Duo panels and report the pose. Call under the simulator lock.

    Args:
        udid: A booted iPhone Duo simulator.

    Returns:
        ``"folded"``, ``"unfolded"`` or ``"unknown"`` (also for non-Duo devices).
    """
    dark = {}
    with tempfile.TemporaryDirectory() as folder:
        for panel, display in DUO_PANELS.items():
            path = Path(folder) / f"{panel}.bmp"
            if not screenshot_panel(udid, display, path):
                return "unknown"
            dark[panel] = bmp_is_dark(path.read_bytes())
    return classify_pose(dark["outer"], dark["inner"])


def settled_pose(udid: str, attempts: int = 4, pause: float = 15.0) -> str:
    """Detect the Duo pose, re-checking while it reads ``unknown``. Call under the simulator lock.

    Just after a fresh boot (above all on the CI runner) neither panel, or a
    stale frame on both, may be lit yet, so an ``unknown`` result is re-detected
    a few times before it counts. A definite pose returns at once.

    Args:
        udid: A booted iPhone Duo simulator.
        attempts: Detections to try.
        pause: Seconds between detections.

    Returns:
        ``"folded"``, ``"unfolded"`` or ``"unknown"`` after every attempt.
    """
    actual = "unknown"
    for attempt in range(1, attempts + 1):
        actual = detect_pose(udid)
        if actual != "unknown":
            break
        print(f"duo pose: unknown, attempt {attempt}/{attempts}", file=sys.stderr)
        if attempt < attempts:
            time.sleep(pause)
    return actual


def require_pose(udid: str, pose: str | None, set_pose: bool = False) -> str | None:
    """Verify (and optionally set) the Duo pose before a capture. Call under the simulator lock.

    Args:
        udid: Booted simulator.
        pose: Required pose (``folded``/``unfolded``/``half``), or None to skip the check.
            ``half`` (partially open) runs on the inner panel, so it verifies like ``unfolded``.
        set_pose: On a mismatch, press Device Hub's pose control via UI scripting
            (needs the Accessibility permission; see ``set_duo_pose``).

    Returns:
        None when satisfied, otherwise a message telling the operator how to fix it.
    """
    if pose is None:
        return None
    expected = POSE_EXPECTED_CLASS[pose]
    actual = settled_pose(udid)
    print(f"duo pose: {actual}", file=sys.stderr)
    if actual == expected and not (set_pose and pose != "folded"):
        return None
    if set_pose:
        try:
            set_duo_pose(udid, pose)
            return None
        except DeviceHubError as error:
            return str(error)
    return (f"iPhone Duo is {actual}, not {pose}. Change it in Device Hub "
            "(Xcode > Open Developer Tool > Device Hub; the pose buttons under the device, "
            "Option-click for the hinge slider), or pass --set-pose / run "
            f"`python3 tools/ios_sim.py pose --set {pose}` (UI scripting; needs the Accessibility "
            "permission), then re-run. simctl/XCTest cannot fold the device.")


def screenshot_display(args: argparse.Namespace, udid: str) -> str | None:
    """Resolve ``--display`` to a ``simctl io --display`` value.

    Args:
        args: Parsed ``shot`` arguments (``display``).
        udid: Booted simulator (used by ``auto`` to find the lit panel).

    Returns:
        A display device name, or None for simctl's default (the first display).
    """
    if args.display in DUO_PANELS:
        return DUO_PANELS[args.display]
    if args.display == "auto":
        return DUO_PANELS[POSE_PANEL.get(detect_pose(udid), "outer")]
    return None


#: Simulator accessibility settings ``shot --a11y`` / ``uitest --a11y`` can switch on for
#: one capture or test batch. Each maps to (enable argv tail, restore argv tail) after
#: ``xcrun simctl``. ``increase-contrast`` uses ``simctl ui``; ``reduce-transparency`` and
#: ``bold-text`` write the Accessibility preferences the system reads at app launch (no
#: ``simctl ui`` option; keys from the runtime's ``libAccessibility``).
A11Y_SETTINGS: dict[str, tuple[tuple[str, ...], tuple[str, ...]]] = {
    "increase-contrast": (("ui", "{udid}", "increase_contrast", "enabled"),
                          ("ui", "{udid}", "increase_contrast", "disabled")),
    "reduce-transparency": (
        ("spawn", "{udid}", "defaults", "write", "com.apple.Accessibility",
         "EnhancedBackgroundContrastEnabled", "-bool", "true"),
        ("spawn", "{udid}", "defaults", "delete", "com.apple.Accessibility",
         "EnhancedBackgroundContrastEnabled"),
    ),
    "bold-text": (
        ("spawn", "{udid}", "defaults", "write", "com.apple.Accessibility",
         "EnhancedTextLegibilityEnabled", "-bool", "true"),
        ("spawn", "{udid}", "defaults", "delete", "com.apple.Accessibility",
         "EnhancedTextLegibilityEnabled"),
    ),
}


def a11y_commands(udid: str, settings: list[str] | None) -> tuple[list[list[str]], list[list[str]]]:
    """Build the ``simctl`` calls that switch accessibility settings on, then back off.

    Args:
        udid: Simulator to configure.
        settings: Keys of ``A11Y_SETTINGS`` (repeatable ``--a11y``), or None.

    Returns:
        ``(enable, restore)`` argv lists; restore runs in reverse order.

    Raises:
        ValueError: For an unknown setting.
    """
    enable: list[list[str]] = []
    restore: list[list[str]] = []
    for name in settings or []:
        if name not in A11Y_SETTINGS:
            raise ValueError(f"unknown --a11y setting {name!r}; choose from {sorted(A11Y_SETTINGS)}")
        on, off = A11Y_SETTINGS[name]
        enable.append(["xcrun", "simctl", *(part.format(udid=udid) for part in on)])
        restore.insert(0, ["xcrun", "simctl", *(part.format(udid=udid) for part in off)])
    return enable, restore


@contextmanager
def simulator_accessibility(udid: str, settings: list[str] | None):
    """Switch simulator accessibility settings on for a block, restoring them after.

    Use only while holding the simulator lock, before the app launches (apps read
    these settings at launch).

    Args:
        udid: Booted simulator.
        settings: Keys of ``A11Y_SETTINGS``, or None to do nothing.
    """
    enable, restore = a11y_commands(udid, settings)
    try:
        for cmd in enable:
            _run(cmd, capture_output=True)
        yield
    finally:
        for cmd in restore:
            _run(cmd, check=False, capture_output=True)



class ScreenRecording:
    """Record the simulator screen to an H.264 MP4 while a block runs.

    Use only while holding the simulator lock. ``simctl io recordVideo`` stops and
    finalizes the file on SIGINT, so the context manager interrupts it on exit.

    Args:
        udid: Booted simulator to record.
        out: Destination ``.mp4`` path, or None to do nothing.
        display: iPhone Duo panel (``outer``/``inner``), or None for simctl's first display.
    """

    def __init__(self, udid: str, out: str | None, display: str | None = None):
        self.udid = udid
        self.out = out
        self.display = display
        self.process: subprocess.Popen | None = None

    def __enter__(self) -> "ScreenRecording":
        if self.out:
            Path(self.out).parent.mkdir(parents=True, exist_ok=True)
            selector = [f"--display={DUO_PANELS[self.display]}"] if self.display in DUO_PANELS else []
            self.process = subprocess.Popen(
                ["xcrun", "simctl", "io", self.udid, "recordVideo", "--codec=h264", "--force",
                 *selector, self.out],
                env=_env(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            )
            time.sleep(1.0)  # recordVideo needs a moment before frames flow
        return self

    def __exit__(self, *exc) -> None:
        if self.process:
            self.process.send_signal(signal.SIGINT)
            try:
                self.process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                self.process.kill()
            print(f"video: {self.out}")

# endregion

# region iPhone Duo pose scripting (Device Hub UI scripting)

#: Device Hub (Xcode 27.1) owns the only fold/unfold/rotate controls for the Duo.
DEVICE_HUB_APP = Path(DEVELOPER_DIR).parent / "Applications" / "DeviceHub.app"
DEVICE_HUB_BUNDLE_ID = "com.apple.dt.Devices"

#: ``pose --set`` actions. ``half`` is Device Hub's partially-open pose.
POSE_ACTIONS = ("folded", "unfolded", "half", "rotate-left", "rotate-right")

#: Panel classification (``detect_pose``) each pose action must end in. Partially
#: open runs on the inner panel, so it classifies like ``unfolded``; rotations keep
#: whatever pose the device was in.
POSE_EXPECTED_CLASS = {"folded": "folded", "unfolded": "unfolded", "half": "unfolded"}

#: Exit codes for ``pose --set`` / ``shot --set-pose`` / ``--rotate``.
EXIT_POSE_MISMATCH = 3
EXIT_NO_ACCESSIBILITY = 4
EXIT_NO_CONTROL = 5

#: Compiled accessibility helper (System Events reports DeviceHub with pid 0 and no
#: windows on macOS 27, so JXA cannot see it; the AX API addressed by pid can).
DEVICE_HUB_HELPER_SOURCE = REPO_ROOT / "tools" / "device_hub_ax.swift"
DEVICE_HUB_HELPER = APPLE_DIR / "DerivedData" / "sim-tool" / "device_hub_ax"
DEVICE_HUB_EXECUTABLE = DEVICE_HUB_APP / "Contents" / "MacOS" / "DeviceHub"
XCODE_APP = Path(DEVELOPER_DIR).parent.parent
XCODE_EXECUTABLE = XCODE_APP / "Contents" / "MacOS" / "Xcode"

#: Menu paths: Xcode's entry to Device Hub, and Device Hub's new-window command.
XCODE_DEVICE_HUB_MENU = ("Xcode", "Open Developer Tool", "Device Hub")
DEVICE_HUB_NEW_WINDOW_MENU = ("File", "New Window")

#: Device Hub shows a simulator by its name (window title ``<name> – iOS 27.1`` and the
#: sidebar row ``TableRow.Device.<UDID>``). Only product simulators are listed.
HUB_DEVICE_NAMES = {DEVICES["duo"]: "iPhone Duo (FST)"}

#: Seconds allowed for each Device Hub opening step.
HUB_OPEN_TIMEOUT = 45.0

#: Words that identify each action's control in Device Hub's accessibility text
#: (title, description, help or identifier). Calibrated 2026-10-04 against Device Hub
#: (Xcode 27.1): the device window's buttons are described "Closed", "Book", "Open" and
#: "Rotate Right" (no Rotate Left; see ``pose_presses``). ``pose --list-controls`` prints
#: the real tree.
_POSE_KEYWORDS: dict[str, tuple[str, ...]] = {
    "rotate-left": ("rotate left", "rotate.device.left", "rotateleft", "rotate-left", "counterclockwise"),
    "rotate-right": ("rotate right", "rotate.device.right", "rotateright", "rotate-right"),
    "half": ("partially", "partial", "half", "tent", "book", "laptop"),
    "unfolded": ("unfold", "fully open", "open device", "flat"),
    "folded": ("fold", "closed", "close device"),
}

#: Words that disqualify a candidate for an action (other poses and unrelated UI).
_POSE_EXCLUDE: dict[str, tuple[str, ...]] = {
    "rotate-left": ("rotate right",),
    "rotate-right": ("rotate left", "counterclockwise", "rotate.device.left"),
    "half": ("unfold", "fully"),
    "unfolded": ("partial", "half", "close"),
    "folded": ("unfold", "partial", "half", "open", "window", "tab", "folder"),
}

#: Bare verbs that count only for buttons in the device window (never menu items),
#: ranked after every strong keyword. Device Hub may label its pose buttons just
#: "Open"/"Close".
_POSE_WEAK_KEYWORDS: dict[str, tuple[str, ...]] = {"folded": ("close",), "unfolded": ("open",)}
_WEAK_EXCLUDE = ("window", "tab", "folder", "finder", "new", "shell", "settings", "report",
                 "navigation", "sidebar", "inspector")

#: Roles that can be a pose button in the device window.
_PRESSABLE_ROLES = ("AXButton", "AXRadioButton", "AXCheckBox", "AXMenuItem", "AXMenuButton",
                    "AXPopUpButton", "AXSegment")


def _control_text(control: dict) -> str:
    """Join a control's accessibility strings for keyword matching.

    Args:
        control: One ``dump`` entry (``title``/``description``/``help``/``identifier``).

    Returns:
        Lower-cased text with ``_`` treated as a space.
    """
    parts = [control.get(key) or "" for key in ("title", "description", "help", "identifier")]
    return " ".join(str(part) for part in parts).lower().replace("_", " ")


def without_device_content(controls: list[dict]) -> list[dict]:
    """Drop the simulated screen's own accessibility elements from a Device Hub dump.

    Device Hub exposes the running iOS app's elements inside an ``iOSContentGroup``;
    an app row such as "… Full combo …" must never be taken for a pose button.

    Args:
        controls: ``device_hub_ax dump`` entries (``path`` lists).

    Returns:
        The entries outside every ``iOSContentGroup`` subtree (the group itself is dropped too).
    """
    roots = [tuple(control["path"]) for control in controls if control.get("subrole") == "iOSContentGroup"]
    return [control for control in controls
            if not any(tuple(control["path"][:len(root)]) == root for root in roots)]


def match_pose_control(action: str, controls: list[dict]) -> dict | None:
    """Pick the Device Hub control that performs a pose action.

    Only enabled, pressable controls are considered; window-chrome buttons (close,
    zoom, minimise) never match. Buttons in the device window win over menu items.

    Args:
        action: One of ``POSE_ACTIONS``.
        controls: ``dump`` entries from the Device Hub JXA script.

    Returns:
        The best matching control, or None.
    """
    keywords, excluded = _POSE_KEYWORDS[action], _POSE_EXCLUDE[action]
    candidates = []
    for control in without_device_content(controls):
        if control.get("enabled") is False or control.get("role") not in _PRESSABLE_ROLES:
            continue
        if (control.get("subrole") or "") in ("AXCloseButton", "AXZoomButton",
                                              "AXMinimizeButton", "AXFullScreenButton"):
            continue
        text = _control_text(control)
        if any(word in text for word in excluded):
            continue
        strong = [index for index, word in enumerate(keywords) if word in text]
        weak = [] if control.get("kind") != "control" or any(word in text for word in _WEAK_EXCLUDE) \
            else [len(keywords) + index
                  for index, word in enumerate(_POSE_WEAK_KEYWORDS.get(action, ())) if word in text]
        if not strong and not weak:
            continue
        # Prefer a button in the device window, then the earliest keyword (most specific).
        candidates.append((control.get("kind") != "control", min(strong + weak), control))
    if not candidates:
        return None
    candidates.sort(key=lambda item: (item[0], item[1]))
    return candidates[0][2]


def responsible_process() -> tuple[int, str] | None:
    """Find the process macOS privacy checks (TCC) attribute this script to.

    TCC grants Accessibility to the *responsible* process (usually the app that
    started the terminal or agent), not to ``python3`` or ``osascript``.

    Returns:
        ``(pid, executable path)``, or None if the private libSystem call is unavailable.
    """
    try:
        import ctypes
        libc = ctypes.CDLL(None)
        lookup = libc.responsibility_get_pid_responsible_for_pid
        lookup.argtypes, lookup.restype = [ctypes.c_int], ctypes.c_int
        pid = lookup(os.getpid())
        buffer = ctypes.create_string_buffer(4096)
        if pid <= 0 or libc.proc_pidpath(pid, buffer, 4096) <= 0:
            return None
        return pid, buffer.value.decode("utf-8", "replace")
    except (AttributeError, OSError):
        return None


def app_bundle_for(executable: str) -> str:
    """Return the outermost ``.app`` bundle containing an executable.

    Args:
        executable: Absolute executable path.

    Returns:
        The ``.app`` directory to add in System Settings, or the path itself if none.
    """
    parts = Path(executable).parts
    for index, part in enumerate(parts):
        if part.endswith(".app"):
            return str(Path(*parts[:index + 1]))
    return executable


def accessibility_trusted() -> bool:
    """Ask macOS (without prompting) whether this process may use UI scripting.

    Returns:
        ``AXIsProcessTrusted()``; False if ApplicationServices cannot be loaded.
    """
    try:
        import ctypes
        services = ctypes.CDLL(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
        services.AXIsProcessTrusted.restype = ctypes.c_bool
        return bool(services.AXIsProcessTrusted())
    except (AttributeError, OSError):
        return False


def scripting_preflight(needed: bool) -> int:
    """Refuse UI scripting early (before taking the simulator lock) without permission.

    Args:
        needed: The command will press Device Hub controls.

    Returns:
        0 to proceed, or ``EXIT_NO_ACCESSIBILITY`` after printing the instructions.
    """
    if not needed or accessibility_trusted():
        return 0
    print(accessibility_instructions(responsible_process()), file=sys.stderr)
    return EXIT_NO_ACCESSIBILITY


def accessibility_instructions(responsible: tuple[int, str] | None, automation: bool = False) -> str:
    """Tell the operator exactly which app to allow. Never changes settings itself.

    Args:
        responsible: ``responsible_process()`` result.
        automation: True when Accessibility is granted but the Apple-event
            (Automation) permission for System Events was refused.

    Returns:
        Multi-line instructions.
    """
    if responsible:
        pid, executable = responsible
        bundle = app_bundle_for(executable)
        who = f"{bundle}\n    (pid {pid}; executable {executable})"
    else:
        bundle = "the app that launched this terminal/agent"
        who = bundle
    if automation:
        return (
            "Device Hub UI scripting needs Automation access to System Events.\n"
            f"  App to allow: {who}\n"
            "  System Settings > Privacy & Security > Automation > (that app) > turn on "
            "\"System Events\".\n"
            "  If it is not listed, re-run this command and click OK on the macOS prompt.")
    return (
        "Device Hub UI scripting needs the macOS Accessibility permission, which is not granted.\n"
        f"  App to allow: {who}\n"
        "  System Settings > Privacy & Security > Accessibility > \"+\" > choose that app "
        f"({bundle}; press Cmd-Shift-G to type the path) > turn its switch on.\n"
        "  Quit and reopen that app so the grant applies, then re-run.\n"
        "  macOS then asks once to let it control \"System Events\" (Automation): click OK.\n"
        "  This tool never changes privacy settings itself (no tccutil, no TCC database edits).")


class DeviceHubError(RuntimeError):
    """Device Hub scripting failed; ``code`` is the CLI exit code to return."""

    def __init__(self, message: str, code: int) -> None:
        super().__init__(message)
        self.code = code


def _device_hub_script(*argv: str, timeout: float = 90) -> dict:
    """Run the compiled Device Hub accessibility helper and parse its JSON reply.

    Args:
        *argv: A ``device_hub_ax`` command and its arguments (see the Swift file header).
        timeout: Seconds before the helper is abandoned.

    Returns:
        The decoded reply.

    Raises:
        DeviceHubError: No Accessibility permission, or the helper reported an error.
    """
    binary = ensure_hub_helper()
    try:
        result = subprocess.run([str(binary), *map(str, argv)], capture_output=True, text=True,
                                timeout=timeout, check=False)
    except subprocess.TimeoutExpired as error:
        raise DeviceHubError(f"Device Hub helper timed out after {timeout:.0f}s ({argv[0]})",
                             EXIT_NO_CONTROL) from error
    try:
        reply = json.loads(result.stdout or "{}")
    except json.JSONDecodeError:
        reply = {"error": (result.stderr or result.stdout).strip()[-400:]}
    if result.returncode == EXIT_NO_ACCESSIBILITY or reply.get("error") == "not-trusted":
        raise DeviceHubError(accessibility_instructions(responsible_process()), EXIT_NO_ACCESSIBILITY)
    if result.returncode or "error" in reply:
        raise DeviceHubError(f"Device Hub helper {argv[0]} failed: {reply.get('error')}", EXIT_NO_CONTROL)
    return reply


def hub_helper_stale(source: Path, binary: Path) -> bool:
    """Whether the Device Hub helper needs recompiling.

    Args:
        source: ``tools/device_hub_ax.swift``.
        binary: Cached executable.

    Returns:
        True when the binary is missing or older than its source.
    """
    return not binary.exists() or binary.stat().st_mtime < source.stat().st_mtime


def ensure_hub_helper() -> Path:
    """Compile ``tools/device_hub_ax.swift`` when stale (no lock needed; a few seconds).

    Returns:
        Path to the helper executable.

    Raises:
        DeviceHubError: The helper did not compile.
    """
    if hub_helper_stale(DEVICE_HUB_HELPER_SOURCE, DEVICE_HUB_HELPER):
        DEVICE_HUB_HELPER.parent.mkdir(parents=True, exist_ok=True)
        built = _run(["xcrun", "swiftc", "-O", str(DEVICE_HUB_HELPER_SOURCE), "-o", str(DEVICE_HUB_HELPER)],
                     check=False, capture_output=True, text=True)
        if built.returncode:
            raise DeviceHubError(f"device_hub_ax.swift did not compile:\n{built.stderr[-2000:]}", EXIT_NO_CONTROL)
    return DEVICE_HUB_HELPER


def process_pids(executable: Path) -> list[int]:
    """List the pids running an executable (``pgrep -f``; read-only).

    Args:
        executable: Absolute executable path.

    Returns:
        Matching pids, ascending.
    """
    found = subprocess.run(["pgrep", "-f", str(executable)], capture_output=True, text=True, check=False)
    return sorted(int(token) for token in found.stdout.split() if token.isdigit())


def hub_device_name(udid: str) -> str:
    """Device Hub's display name for a simulator (its window title and sidebar row).

    Args:
        udid: Simulator UDID.

    Returns:
        The simulator's name.

    Raises:
        DeviceHubError: The UDID has no known Device Hub name.
    """
    name = HUB_DEVICE_NAMES.get(udid)
    if name is None:
        raise DeviceHubError(f"No Device Hub name is known for {udid}; add it to HUB_DEVICE_NAMES.",
                             EXIT_NO_CONTROL)
    return name


def hub_window_shows(title: str, device_name: str) -> bool:
    """Whether a Device Hub window title names this device (``<name> – iOS 27.1``).

    Prefix matching on the full name plus the separator keeps another project's
    devices (``iPhone Duo (HASS)``) and similarly named devices out.

    Args:
        title: ``AXTitle`` of a Device Hub window.
        device_name: Simulator name.

    Returns:
        True for a window showing exactly this device.
    """
    return title == device_name or any(title.startswith(f"{device_name} {dash} ") for dash in ("–", "—", "-"))


def rank_device_windows(windows: list[dict], device_name: str) -> list[dict]:
    """Order the Device Hub windows showing a device, most usable first.

    Visible standard windows first (minimized and dialog-style windows last), then
    the app's main window, then the newest process (the one Xcode's menu activates).

    Args:
        windows: ``device_hub_ax windows`` entries (``pid``/``window``/``title``/
            ``subrole``/``minimized``/``main``).
        device_name: Simulator name.

    Returns:
        Matching windows in preference order (possibly empty).
    """
    matching = [entry for entry in windows if hub_window_shows(entry.get("title", ""), device_name)]
    return sorted(matching, key=lambda entry: (bool(entry.get("minimized")),
                                               entry.get("subrole") != "AXStandardWindow",
                                               not entry.get("main"), -int(entry.get("pid", 0))))


def has_pose_controls(controls: list[dict]) -> bool:
    """Whether a window dump contains Device Hub's fold controls (the device is booted and shown).

    Args:
        controls: ``device_hub_ax dump`` entries.

    Returns:
        True when the folded and unfolded buttons are present.
    """
    return all(match_pose_control(action, controls) is not None for action in ("folded", "unfolded"))


def pose_presses(action: str, controls: list[dict]) -> list[dict]:
    """Controls to press, in order, to perform a pose action.

    Device Hub 27.1 shows only a Rotate Right button, so ``rotate-left`` falls back
    to three right rotations.

    Args:
        action: One of ``POSE_ACTIONS``.
        controls: ``device_hub_ax dump`` entries of the device window.

    Returns:
        The controls to press (empty when nothing matches).
    """
    control = match_pose_control(action, controls)
    if control is not None:
        return [control]
    if action == "rotate-left" and (right := match_pose_control("rotate-right", controls)) is not None:
        return [right] * 3
    return []


def choose_hub_process(pids: list[int], frontmost: int | None) -> int:
    """Pick the DeviceHub process to open a new window in.

    Several DeviceHub processes can run at once (other projects keep their own).
    The one Xcode's menu just activated is frontmost; otherwise take the newest.

    Args:
        pids: Running DeviceHub pids (non-empty).
        frontmost: Pid of the focused application, if known.

    Returns:
        The chosen pid.
    """
    return frontmost if frontmost in pids else max(pids)


@dataclass(frozen=True)
class HubWindow:
    """A Device Hub window showing the target simulator with its pose controls.

    Attributes:
        pid: DeviceHub process id.
        window: Index in that process's ``AXWindows``.
        controls: Its ``dump`` entries (paths relative to the window).
    """

    pid: int
    window: int
    controls: list


def hub_windows() -> list[dict]:
    """List every Device Hub window (all DeviceHub processes).

    Returns:
        ``device_hub_ax windows`` entries; empty when Device Hub is not running.
    """
    pids = process_pids(DEVICE_HUB_EXECUTABLE)
    return _device_hub_script("windows", *pids).get("windows", []) if pids else []


def find_device_hub_window(udid: str) -> HubWindow | None:
    """Find an open Device Hub window showing this simulator's pose controls.

    Args:
        udid: Booted simulator.

    Returns:
        The window, or None.
    """
    name = hub_device_name(udid)
    for entry in rank_device_windows(hub_windows(), name):
        if entry.get("minimized"):
            _device_hub_script("raise", entry["pid"], entry["window"])
            time.sleep(1.0)
        controls = _device_hub_script("dump", entry["pid"], entry["window"]).get("controls", [])
        if has_pose_controls(controls):
            return HubWindow(entry["pid"], entry["window"], controls)
    return None


def _wait_for(probe, timeout: float, interval: float = 1.0):
    """Poll ``probe()`` until it returns something truthy or the timeout passes.

    Args:
        probe: Zero-argument callable.
        timeout: Seconds.
        interval: Seconds between probes.

    Returns:
        The first truthy result, or None.
    """
    deadline = time.time() + timeout
    while True:
        result = probe()
        if result or time.time() > deadline:
            return result or None
        time.sleep(interval)


def open_device_hub_window(udid: str, timeout: float = HUB_OPEN_TIMEOUT) -> HubWindow:
    """Return a Device Hub window showing this simulator, opening one if needed.

    Order: reuse an open window that shows the device; otherwise launch Xcode if it
    is not running and choose Xcode > Open Developer Tool > Device Hub; if Device Hub
    still shows no window for the device, open a *new* Device Hub window (File > New
    Window) and select the device's sidebar row there, so windows showing other
    projects' devices are never repurposed. Never touches Xcode documents.

    Args:
        udid: Booted simulator (``HUB_DEVICE_NAMES`` must name it).
        timeout: Seconds allowed for each wait (Xcode launch, Device Hub window, selection).

    Returns:
        The window and its controls.

    Raises:
        DeviceHubError: Permission missing, or a step timed out (the message says which).
    """
    name = hub_device_name(udid)
    if (found := find_device_hub_window(udid)) is not None:
        return found
    if not process_pids(XCODE_EXECUTABLE):
        print("launching Xcode for Device Hub ...", file=sys.stderr)
        _run(["open", "-g", "-a", str(XCODE_APP)], check=False)
    xcode = _wait_for(lambda: process_pids(XCODE_EXECUTABLE), timeout)
    if not xcode:
        raise DeviceHubError(f"Xcode did not start within {timeout:.0f}s.", EXIT_NO_CONTROL)

    def press_menu() -> bool:
        try:
            _device_hub_script("menu", xcode[0], *XCODE_DEVICE_HUB_MENU)
            return True
        except DeviceHubError as error:
            if error.code == EXIT_NO_ACCESSIBILITY:
                raise
            return False  # Xcode's menu bar is not ready yet
    print("choosing Xcode > Open Developer Tool > Device Hub ...", file=sys.stderr)
    if not _wait_for(press_menu, timeout, interval=2.0):
        raise DeviceHubError(f"Xcode's menu {' > '.join(XCODE_DEVICE_HUB_MENU)} was not available within "
                             f"{timeout:.0f}s. Open Device Hub by hand and select \"{name}\".", EXIT_NO_CONTROL)
    if not _wait_for(lambda: process_pids(DEVICE_HUB_EXECUTABLE), timeout):
        raise DeviceHubError(f"Device Hub did not start within {timeout:.0f}s.", EXIT_NO_CONTROL)
    if (found := _wait_for(lambda: find_device_hub_window(udid), 8.0, interval=2.0)) is not None:
        return found

    before = {(entry["pid"], entry["window"], entry.get("title")) for entry in hub_windows()}
    try:
        frontmost = _device_hub_script("frontmost").get("pid")
    except DeviceHubError:
        frontmost = None
    pid = choose_hub_process(process_pids(DEVICE_HUB_EXECUTABLE), frontmost)
    print(f"opening a new Device Hub window for \"{name}\" ...", file=sys.stderr)
    _device_hub_script("menu", pid, *DEVICE_HUB_NEW_WINDOW_MENU)

    def new_window() -> dict | None:
        fresh = [entry for entry in hub_windows() if entry["pid"] == pid and not entry.get("minimized")
                 and (entry["pid"], entry["window"], entry.get("title")) not in before]
        return fresh[0] if fresh else None
    created = _wait_for(new_window, timeout)
    if created is None:
        raise DeviceHubError(f"Device Hub opened no new window within {timeout:.0f}s "
                             f"({' > '.join(DEVICE_HUB_NEW_WINDOW_MENU)}).", EXIT_NO_CONTROL)
    _device_hub_script("select-row", pid, created["window"], f"TableRow.Device.{udid}")
    found = _wait_for(lambda: find_device_hub_window(udid), timeout, interval=2.0)
    if found is None:
        raise DeviceHubError(f"Selected \"{name}\" in a new Device Hub window, but its pose controls did not "
                             f"appear within {timeout:.0f}s (is the simulator booted?).", EXIT_NO_CONTROL)
    return found


def list_device_hub_controls(udid: str) -> list[dict]:
    """Dump the device window's controls and Device Hub's menus (for calibration).

    Args:
        udid: Booted simulator.

    Returns:
        ``dump`` entries (window controls, then menu items with paths starting ``-1``).

    Raises:
        DeviceHubError: No permission, or no window could be opened.
    """
    if not accessibility_trusted():
        raise DeviceHubError(accessibility_instructions(responsible_process()), EXIT_NO_ACCESSIBILITY)
    hub = open_device_hub_window(udid)
    return _device_hub_script("dump", hub.pid, hub.window, "--menus").get("controls", [])


def press_device_hub_menu(udid: str, titles: list[str]) -> None:
    """Choose a Device Hub menu command for this simulator's window.

    The window is raised and made main first, so the command acts on this device.

    Args:
        udid: Booted simulator.
        titles: Menu path, e.g. ``["Device", "Keyboard", "Toggle Software Keyboard"]``.

    Raises:
        DeviceHubError: No permission, no window, or no such menu item.
    """
    hub = open_device_hub_window(udid)
    _device_hub_script("raise", hub.pid, hub.window)
    time.sleep(0.5)
    _device_hub_script("menu", hub.pid, *titles)


def find_hub_control(controls: list[dict], label: str) -> dict | None:
    """Find a Device Hub window control by its exact description or help text.

    Args:
        controls: ``device_hub_ax dump`` entries.
        label: Exact text, e.g. ``Capture Keyboard`` (the toolbar toggle).

    Returns:
        The first pressable control (outside the simulated screen) with that text, or None.
    """
    for control in without_device_content(controls):
        if control.get("role") in _PRESSABLE_ROLES and label in (control.get("description"), control.get("help")):
            return control
    return None


def press_device_hub_control(udid: str, label: str) -> None:
    """Press a Device Hub window control (e.g. the **Capture Keyboard** toggle).

    Args:
        udid: Booted simulator.
        label: Exact description or help text of the control.

    Raises:
        DeviceHubError: No permission, no window, or no such control.
    """
    hub = open_device_hub_window(udid)
    controls = _device_hub_script("dump", hub.pid, hub.window).get("controls", [])
    control = find_hub_control(controls, label)
    if control is None:
        raise DeviceHubError(f"No Device Hub control described \"{label}\".", EXIT_NO_CONTROL)
    _device_hub_script("press", hub.pid, hub.window, *control["path"])


def _panel_digest(udid: str) -> str | None:
    """Hash the lit panel's screenshot, to confirm a rotation re-laid out the app.

    Args:
        udid: Booted Duo.

    Returns:
        SHA-256 of the lit panel's BMP, or None when no panel is lit.
    """
    panel = POSE_PANEL.get(detect_pose(udid))
    if panel is None:
        return None
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / "panel.bmp"
        try:
            _run(["xcrun", "simctl", "io", udid, "screenshot", "--type=bmp",
                  f"--display={DUO_PANELS[panel]}", str(path)], check=False, capture_output=True, timeout=30)
        except subprocess.TimeoutExpired:
            return None
        return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def set_duo_pose(udid: str, action: str, settle: float = 15.0) -> str:
    """Press Device Hub's control for a pose action and verify the result.

    Call under the simulator lock with the Duo booted. Poses are verified with the
    same lit-panel check as ``--pose``; rotations by an unchanged pose plus a
    changed lit-panel image (the app re-laid out).

    Args:
        udid: Booted iPhone Duo.
        action: One of ``POSE_ACTIONS``.
        settle: Seconds to wait for each press to take effect.

    Returns:
        The verified panel classification after the action.

    Raises:
        DeviceHubError: Missing permission, no matching control, or verification failure.
    """
    expected = POSE_EXPECTED_CLASS.get(action)
    before = detect_pose(udid)
    if action == "folded" and before == expected:
        # Only "folded" is certain from the lit panel; half and flat both light the inner one.
        print(f"duo pose already {before}", file=sys.stderr)
        return before
    if not accessibility_trusted():
        raise DeviceHubError(accessibility_instructions(responsible_process()), EXIT_NO_ACCESSIBILITY)
    hub = open_device_hub_window(udid)
    presses = pose_presses(action, hub.controls)
    if not presses:
        raise DeviceHubError(
            f"No Device Hub control matched '{action}' among {len(hub.controls)} elements. "
            "Run `python3 tools/ios_sim.py pose --list-controls` and update _POSE_KEYWORDS.",
            EXIT_NO_CONTROL)
    actual = before
    for control in presses:
        print(f"pressing Device Hub control {control.get('role')} "
              f"'{control.get('title') or control.get('description')}' at {control['path']}", file=sys.stderr)
        digest = _panel_digest(udid) if expected is None else None
        _device_hub_script("press", hub.pid, hub.window, *control["path"])
        deadline = time.time() + settle
        while True:
            time.sleep(1.5)
            actual = detect_pose(udid)
            if expected is None:
                if actual == before and _panel_digest(udid) not in (None, digest):
                    break
            elif actual == expected:
                break
            if time.time() > deadline:
                if expected is None and actual == before:
                    # The device turned but nothing redrew: the app (or system) does not
                    # use that orientation on this panel, e.g. upside down. Not an error.
                    print(f"warning: {action} left the lit panel unchanged after {settle:.0f}s",
                          file=sys.stderr)
                    break
                raise DeviceHubError(
                    f"Pressed the {action} control but the Duo reads {actual} "
                    f"(expected {expected or before + ' with a re-laid-out panel'}).", EXIT_POSE_MISMATCH)
    if action == "half":
        time.sleep(2.0)  # the fold region and hinge state settle after the panel lights
    return actual

# endregion

# region Driver host bridge


def run_host_command(udid: str, command: str, values: list[str]) -> None:
    """Run one ``host:`` driver-step command. Call under the simulator lock.

    Args:
        udid: The simulator the drive runs on.
        command: ``pose``, ``capture`` or ``menu`` (see ``parse_host_command``).
        values: Its arguments.

    Raises:
        DeviceHubError: A Device Hub step failed.
        RuntimeError: A capture failed.
    """
    if command == "pose":
        set_duo_pose(udid, values[0])
    elif command == "menu":
        press_device_hub_menu(udid, [part.strip() for part in values[0].split("/")])
    elif command == "control":
        press_device_hub_control(udid, values[0])
    elif command == "capture":
        panel, out = values
        display = DUO_PANELS[POSE_PANEL.get(detect_pose(udid), "outer")] if panel == "auto" else DUO_PANELS[panel]
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        result = _run(["xcrun", "simctl", "io", udid, "screenshot", f"--display={display}", out],
                      check=False, capture_output=True)
        if result.returncode:
            raise RuntimeError(f"screenshot of {panel} failed: {result.stderr.decode(errors='replace')[-300:]}")


class HostBridge:
    """Serve ``host:`` driver steps while ``xcodebuild`` runs the driver test.

    The test writes ``<n>.request`` files into ``directory`` (``FST_DRIVER_HOST_DIR``);
    a background thread runs each command and answers ``<n>.done`` with ``ok`` or
    ``error: <message>``. Use only while holding the simulator lock.

    Args:
        udid: Simulator under test.
        directory: Handshake directory shared with the test process.
    """

    def __init__(self, udid: str, directory: Path) -> None:
        self.udid = udid
        self.directory = directory
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._serve, name="fst-host-bridge", daemon=True)

    def __enter__(self) -> "HostBridge":
        self.thread.start()
        return self

    def __exit__(self, *exc) -> None:
        self.stop.set()
        self.thread.join(timeout=5)

    def _serve(self) -> None:
        handled: set[str] = set()
        while not self.stop.is_set():
            for request in sorted(self.directory.glob("*.request")):
                if request.name in handled:
                    continue
                handled.add(request.name)
                text = request.read_text(encoding="utf-8").strip()
                print(f"host step: {text}", file=sys.stderr)
                try:
                    run_host_command(self.udid, *parse_host_command(text))
                    reply = "ok"
                except (DeviceHubError, RuntimeError, ValueError, OSError) as error:
                    reply = f"error: {error}"
                    print(f"host step failed: {error}", file=sys.stderr)
                print(f"host step done: {reply}", file=sys.stderr)
                done = request.with_suffix(".done")
                done.with_suffix(".tmp").write_text(reply, encoding="utf-8")
                done.with_suffix(".tmp").rename(done)
            self.stop.wait(0.25)

# endregion

# region Commands


def cmd_build(args: argparse.Namespace) -> int:
    """Generate the Xcode project and build the iOS app.

    No simulator lock (no device involved), but the compile itself is
    serialized on ``~/.fst-build.lock`` (see ``build_lock()``) so parallel
    lanes don't overload this Mac.

    Args:
        args: Parsed CLI arguments (``configuration``).

    Returns:
        Process exit code.
    """
    _run(["xcodegen", "generate", "-q"], cwd=APPLE_DIR)
    with build_lock():
        result = _run([
            "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", product().scheme,
            "-configuration", args.configuration,
            "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", str(derived_data()), "build", "-quiet",
        ], cwd=APPLE_DIR, check=False)
    return result.returncode


def cmd_shot(args: argparse.Namespace) -> int:
    """Install, launch and screenshot under the global simulator lock.

    Args:
        args: Parsed CLI arguments (device, tab, route, env, wait, out, keep,
            pose, display).

    Returns:
        Process exit code (3 when ``--pose`` does not match the device).
    """
    udid = resolve_device(args.device)
    app = app_path()
    if code := scripting_preflight(args.set_pose or bool(args.rotate)):
        return code
    LOCK_PATH.touch(exist_ok=True)
    with open(LOCK_PATH, "w") as lock:
        print(f"waiting for simulator lock {LOCK_PATH} ...", file=sys.stderr)
        fcntl.flock(lock, fcntl.LOCK_EX)
        lock.write(f"{os.getpid()} {REPO_ROOT}\n")
        lock.flush()
        boot_exclusive(udid)
        _run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)
        if args.clean_status_bar:
            _run(["xcrun", "simctl", "status_bar", udid, "override", *CLEAN_STATUS_BAR], capture_output=True)
        problem = require_pose(udid, args.pose, args.set_pose)
        if problem:
            print(problem, file=sys.stderr)
            return EXIT_POSE_MISMATCH
        for direction in args.rotate or []:
            try:
                set_duo_pose(udid, f"rotate-{direction}")
            except DeviceHubError as error:
                print(error, file=sys.stderr)
                return error.code
        display = screenshot_display(args, udid)
        _run(["xcrun", "simctl", "install", udid, str(app)])
        _run(["xcrun", "simctl", "terminate", udid, product().bundle_id], check=False, capture_output=True)
        launch_env = _env()
        if args.tab:
            launch_env["SIMCTL_CHILD_FST_DEBUG_TAB"] = args.tab
        if args.route:
            launch_env["SIMCTL_CHILD_FST_DEBUG_ROUTE"] = args.route
        for pair in args.env or []:
            key, _, value = pair.partition("=")
            launch_env[f"SIMCTL_CHILD_{key}"] = value
        with simulator_accessibility(udid, args.a11y), \
                ScreenRecording(udid, args.record, args.display if args.display in DUO_PANELS else None):
            _run(["xcrun", "simctl", "launch", udid, product().bundle_id, *(args.launch_arg or [])], env=launch_env)
            for index, out in enumerate(args.out):
                time.sleep(args.wait if index == 0 else args.interval)
                Path(out).parent.mkdir(parents=True, exist_ok=True)
                selector = [f"--display={display}"] if display else []
                _run(["xcrun", "simctl", "io", udid, "screenshot", *selector, out], capture_output=True)
                print(out)
            if args.record and args.record_tail:
                time.sleep(args.record_tail)
        if not args.keep:
            _run(["xcrun", "simctl", "terminate", udid, product().bundle_id], check=False, capture_output=True)
    return 0


def cmd_drive(args: argparse.Namespace) -> int:
    """Build the driver UI-test bundle (if stale) and run a scripted step sequence.

    Builds ``build-for-testing`` once per worktree (cached by ``source_hash()``
    over Sources/Apps/iOS/Apps/iOSUITests/project.yml; ``--rebuild`` forces it),
    then runs ``test-without-building -only-testing:...DriverTests/testDrive``
    under the same global simulator lock ``shot`` uses. The step script and any
    ``--tab``/``--route``/``--env`` app-launch environment travel to the test
    process via xcodebuild's ``TEST_RUNNER_`` environment passthrough; see
    ``apple/Apps/iOSUITests/DriverTests.swift`` for the step vocabulary.

    Args:
        args: Parsed CLI arguments (device, tab, route, env, steps, steps_file,
            rebuild).

    Returns:
        Process exit code (``xcodebuild``'s, or a build failure's).
    """
    try:
        steps = parse_steps(args.steps, args.steps_file)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2
    try:
        host_steps = [parse_host_command(step.partition(":")[2]) for step in steps if step.startswith("host:")]
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2
    if code := scripting_preflight(args.set_pose or any(cmd != "capture" for cmd, _ in host_steps)):
        return code
    udid = resolve_device(args.device)
    derived = driver_derived_data()

    current_hash = source_hash()
    if args.rebuild or driver_build_stale(derived, current_hash):
        _run(["xcodegen", "generate", "-q"], cwd=APPLE_DIR)
        with build_lock():
            build = _run([
                "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", product().scheme,
                "-configuration", "Debug", "-destination", "generic/platform=iOS Simulator",
                "-derivedDataPath", str(derived), "build-for-testing", "-quiet",
            ], cwd=APPLE_DIR, check=False)
        if build.returncode:
            return build.returncode
        write_driver_hash(derived, current_hash)
    else:
        print(f"driver build up to date ({current_hash[:12]}); skipping rebuild", file=sys.stderr)

    outputs = output_paths(steps)
    for out in outputs:
        Path(out).parent.mkdir(parents=True, exist_ok=True)

    steps_path = Path(tempfile.gettempdir()) / f"fst-driver-steps-{uuid.uuid4().hex}.txt"
    steps_path.write_text("\n".join(steps) + "\n", encoding="utf-8")

    launch_env = _env()
    launch_env["TEST_RUNNER_FST_DRIVER_STEPS_FILE"] = str(steps_path)
    host_dir = Path(tempfile.mkdtemp(prefix="fst-driver-host-"))
    launch_env["TEST_RUNNER_FST_DRIVER_HOST_DIR"] = str(host_dir)
    if args.tab:
        launch_env["TEST_RUNNER_FST_DEBUG_TAB"] = args.tab
    if args.route:
        launch_env["TEST_RUNNER_FST_DEBUG_ROUTE"] = args.route
    if not args.animate:
        # Freeze the album carousel so XCUITest's idle waits don't time out per step.
        launch_env["TEST_RUNNER_FST_DEBUG_STILL_BACKGROUND"] = "1"
    for pair in args.env or []:
        key, _, value = pair.partition("=")
        launch_env[f"TEST_RUNNER_{key}"] = value

    result_bundle = derived / "Results" / f"drive-{uuid.uuid4().hex}.xcresult"
    result_bundle.parent.mkdir(parents=True, exist_ok=True)
    log_path = Path(tempfile.gettempdir()) / f"fst-driver-log-{uuid.uuid4().hex}.txt"

    LOCK_PATH.touch(exist_ok=True)
    start = time.time()
    try:
        with open(LOCK_PATH, "w") as lock:
            print(f"waiting for simulator lock {LOCK_PATH} ...", file=sys.stderr)
            fcntl.flock(lock, fcntl.LOCK_EX)
            lock.write(f"{os.getpid()} {REPO_ROOT}\n")
            lock.flush()
            boot_exclusive(udid)
            _run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)
            if args.clean_status_bar:
                _run(["xcrun", "simctl", "status_bar", udid, "override", *CLEAN_STATUS_BAR], capture_output=True)
            problem = require_pose(udid, args.pose, args.set_pose)
            if problem:
                print(problem, file=sys.stderr)
                return EXIT_POSE_MISMATCH
            cmd = [
                "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", product().scheme,
                "-destination", f"platform=iOS Simulator,id={udid}",
                "-derivedDataPath", str(derived), "-resultBundlePath", str(result_bundle),
                f"-only-testing:{product().uitest_target}/DriverTests/testDrive",
                "test-without-building", "-quiet",
            ]
            print("+", " ".join(cmd), file=sys.stderr)
            with open(log_path, "w") as log, ScreenRecording(udid, args.record, args.display), \
                    HostBridge(udid, host_dir):
                try:
                    process = subprocess.run(
                        cmd, cwd=APPLE_DIR, env=launch_env,
                        stdout=log, stderr=subprocess.STDOUT, check=False,
                        timeout=args.timeout,
                    )
                except subprocess.TimeoutExpired:
                    # Never let a hung run hold the shared simulator lock.
                    _run(["xcrun", "simctl", "terminate", udid, product().bundle_id],
                         check=False, capture_output=True)
                    process = subprocess.CompletedProcess(cmd, 124)
                    log.write(f"\nTIMEOUT after {args.timeout}s; killed.\n")
    finally:
        steps_path.unlink(missing_ok=True)
        shutil.rmtree(host_dir, ignore_errors=True)
    elapsed = time.time() - start

    if process.returncode:
        log_text = log_path.read_text(encoding="utf-8", errors="replace")
        print(f"drive FAILED after {elapsed:.1f}s; last lines of {log_path}:", file=sys.stderr)
        print("\n".join(log_text.splitlines()[-40:]), file=sys.stderr)
        print(f"result bundle: {result_bundle}", file=sys.stderr)
        return process.returncode

    print(f"drive OK in {elapsed:.1f}s ({len(steps)} step(s))", file=sys.stderr)
    log_path.unlink(missing_ok=True)
    shutil.rmtree(result_bundle, ignore_errors=True)
    for out in outputs:
        print(f"{'ok' if Path(out).exists() else 'MISSING'}: {out}")
    return 0


def cmd_uitest(args: argparse.Namespace) -> int:
    """Build once (if stale) and run one or more real XCUITest classes/methods.

    Unlike ``drive`` (a single scripted ``DriverTests/testDrive`` step sequence),
    this runs ordinary ``XCTestCase`` journey tests written directly in Swift
    (e.g. ``ShellJourneyTests``, ``LeaderboardsJourneyTests``) under
    ``apple/Apps/iOSUITests/``. It reuses the exact same build-for-testing
    product and ``~/.fst-build.lock``/``~/.fst-sim.lock`` machinery as ``drive``
    (same scheme, same ``FestivalMobileUITests`` target, same DerivedData and
    staleness check), so any new journey file placed in that target is picked
    up by the next build with no tool changes. Pass one or more ``--only``
    selectors (``Class`` or ``Class/testMethod``); they run in bounded batches
    of ``--batch-size`` (default 3) selectors per ``xcodebuild
    test-without-building`` invocation, fully releasing ``~/.fst-sim.lock``
    between batches (and bounding each one to ``--timeout`` seconds, default
    300) so other lanes queued on the shared simulator aren't starved by one
    long run. See ``_run_uitest_batch`` and the 5-minute lock-hold rule in
    ``.agents/workflow/simulator-driver.md``.

    Journey tests that need the loopback mock service are responsible for
    starting/asserting it themselves (matching the existing
    ``FestivalMobileUITests.swift`` convention of setting
    ``FST_API_BASE_URL``/``FST_FIXTURE_SCENARIO`` on ``app.launchEnvironment``);
    this command does not manage ``tools/mock_service.py`` for you.

    Args:
        args: Parsed CLI arguments (device, only, timeout, rebuild).

    Returns:
        Process exit code.
    """
    if not args.only:
        print("at least one --only Class[/testMethod] is required", file=sys.stderr)
        return 2
    if code := scripting_preflight(bool(getattr(args, "set_pose", False))):
        return code
    udid = resolve_device(args.device)
    if getattr(args, "rotate", None) and getattr(args, "set_pose", False):
        # Rotations are relative: start from a fresh boot so they land on the default
        # orientation (the Duo boots closed, in its default orientation).
        def shutdown(target: str) -> int:
            _run(["xcrun", "simctl", "shutdown", target], check=False, capture_output=True)
            return 0
        _with_sim_lock(udid, shutdown)
    derived = driver_derived_data()

    current_hash = source_hash()
    if args.rebuild or driver_build_stale(derived, current_hash):
        _run(["xcodegen", "generate", "-q"], cwd=APPLE_DIR)
        with build_lock():
            build = _run([
                "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", product().scheme,
                "-configuration", "Debug", "-destination", "generic/platform=iOS Simulator",
                "-derivedDataPath", str(derived), "build-for-testing", "-quiet",
            ], cwd=APPLE_DIR, check=False)
        if build.returncode:
            return build.returncode
        write_driver_hash(derived, current_hash)
    else:
        print(f"driver build up to date ({current_hash[:12]}); skipping rebuild", file=sys.stderr)

    # Split into bounded batches, each taking (and fully releasing) the simulator
    # lock on its own: one long ``xcodebuild`` invocation covering many selectors
    # can hold ``~/.fst-sim.lock`` for 10+ minutes and starve every other lane
    # sharing this Mac's one simulator. Releasing between batches lets a queued
    # `shot`/`drive`/`uitest` from another lane interleave instead of waiting out
    # the whole list. See the 5-minute lock-hold rule in
    # ``.agents/workflow/simulator-driver.md``.
    batches = [
        args.only[index:index + args.batch_size]
        for index in range(0, len(args.only), args.batch_size)
    ]
    overall_start = time.time()
    failed_batches: list[tuple[list[str], int]] = []
    for batch_index, batch in enumerate(batches, start=1):
        label = f"batch {batch_index}/{len(batches)}"
        returncode, elapsed, log_path, result_bundle = _run_uitest_batch(
            udid=udid, derived=derived, selectors=batch, timeout=args.timeout,
            a11y=getattr(args, "a11y", None), pose=getattr(args, "pose", None),
            set_pose=getattr(args, "set_pose", False), rotate=getattr(args, "rotate", None),
        )
        if returncode == EXIT_POSE_MISMATCH:
            print(f"uitest {label}: iPhone Duo pose not reached; stopping", file=sys.stderr)
            return returncode
        if returncode:
            failed_batches.append((batch, returncode))
            log_text = log_path.read_text(encoding="utf-8", errors="replace")
            print(f"uitest {label} FAILED after {elapsed:.1f}s; last lines of {log_path}:", file=sys.stderr)
            print("\n".join(log_text.splitlines()[-60:]), file=sys.stderr)
            print(f"result bundle: {result_bundle}", file=sys.stderr)
        elif getattr(args, "fail_on_skip", False) and (problem := skip_problem(_result_summary(result_bundle))):
            failed_batches.append((batch, 1))
            print(f"uitest {label} FAILED (--fail-on-skip: {problem}) after {elapsed:.1f}s"
                  f"{_result_counts(result_bundle)}; log {log_path}; result bundle: {result_bundle}",
                  file=sys.stderr)
        else:
            print(f"uitest {label} OK in {elapsed:.1f}s ({len(batch)} selector(s)){_result_counts(result_bundle)}",
                  file=sys.stderr)
            if os.environ.get("FST_UITEST_KEEP_RESULTS") == "1":
                # Keep green evidence too (attachments, per-test results): an all-skipped
                # or zero-test batch also exits 0.
                print(f"kept: {log_path} {result_bundle}", file=sys.stderr)
            else:
                log_path.unlink(missing_ok=True)
                shutil.rmtree(result_bundle, ignore_errors=True)

    overall_elapsed = time.time() - overall_start
    if failed_batches:
        failed_selectors = [selector for batch, _ in failed_batches for selector in batch]
        print(
            f"uitest: {len(failed_batches)}/{len(batches)} batch(es) failed after "
            f"{overall_elapsed:.1f}s total: {', '.join(failed_selectors)}",
            file=sys.stderr,
        )
        return max(code for _, code in failed_batches)

    print(f"uitest OK in {overall_elapsed:.1f}s total ({len(args.only)} selector(s), {len(batches)} batch(es))",
          file=sys.stderr)
    return 0


def _result_summary(result_bundle: Path) -> dict | None:
    """Read a result bundle's test summary (``xcresulttool get test-results summary``).

    Args:
        result_bundle: The batch's ``.xcresult`` path.

    Returns:
        The summary JSON (``passedTests``, ``skippedTests``, ``failedTests``…), or ``None``
        when it cannot be read.
    """
    try:
        out = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_bundle)],
            env=_env(), capture_output=True, text=True, check=True, timeout=60,
        ).stdout
        summary = json.loads(out)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    return summary if isinstance(summary, dict) else None


def _result_counts(result_bundle: Path) -> str:
    """Summarize a result bundle's passed/skipped/failed counts (``-quiet`` hides them).

    A green batch can still be all skips (e.g. iPad-only journeys on an iPhone), so print
    the counts before the bundle is deleted.

    Args:
        result_bundle: The batch's ``.xcresult`` path.

    Returns:
        ``": N passed, N skipped, N failed"``, or an empty string when unavailable.
    """
    summary = _result_summary(result_bundle)
    if summary is None:
        return ""
    return (f": {summary.get('passedTests', 0)} passed, {summary.get('skippedTests', 0)} skipped, "
            f"{summary.get('failedTests', 0)} failed")


def skip_problem(summary: dict | None) -> str | None:
    """Explain why a green batch still fails ``uitest --fail-on-skip``.

    A journey that cannot find its fixture skips, and an all-skipped batch exits 0, so CI
    would pass without running anything. With ``--fail-on-skip`` every selected test must
    have run and passed.

    Args:
        summary: The batch's ``_result_summary``, or ``None`` when unreadable.

    Returns:
        A one-line reason, or ``None`` when every test ran and none skipped.
    """
    if summary is None:
        return "no readable result summary"
    skipped = int(summary.get("skippedTests", 0) or 0)
    passed = int(summary.get("passedTests", 0) or 0)
    if skipped:
        return f"{skipped} test(s) skipped"
    if not passed:
        return "no test ran"
    return None


def _run_uitest_batch(
    *, udid: str, derived: Path, selectors: list[str], timeout: float,
    a11y: list[str] | None = None, pose: str | None = None, set_pose: bool = False,
    rotate: list[str] | None = None,
) -> tuple[int, float, Path, Path]:
    """Run one bounded batch of ``-only-testing:`` selectors under one lock hold.

    Acquires ``~/.fst-sim.lock`` for exactly this batch's ``xcodebuild
    test-without-building`` call and releases it before returning (the ``with
    open(...)`` block closes the lock file), so ``cmd_uitest`` can interleave
    with other lanes between batches. ``timeout`` bounds this single hold: on
    expiry, both ``xcodebuild`` (via ``subprocess.run``'s own timeout kill) and
    the app under test (via an explicit ``simctl terminate``) are stopped so a
    hang can never pin the shared simulator lock past ``timeout`` seconds.

    Args:
        udid: Target simulator UDID.
        derived: The driver's DerivedData directory (already built-for-testing).
        selectors: One batch's ``Class``/``Class/testMethod`` selectors.
        timeout: Seconds before killing this batch's run.
        a11y: ``A11Y_SETTINGS`` keys switched on for this batch and restored after it.

    Returns:
        ``(returncode, elapsed_seconds, log_path, result_bundle_path)``.
    """
    result_bundle = derived / "Results" / f"uitest-{uuid.uuid4().hex}.xcresult"
    result_bundle.parent.mkdir(parents=True, exist_ok=True)
    log_path = Path(tempfile.gettempdir()) / f"fst-uitest-log-{uuid.uuid4().hex}.txt"

    LOCK_PATH.touch(exist_ok=True)
    start = time.time()
    with open(LOCK_PATH, "w") as lock:
        print(f"waiting for simulator lock {LOCK_PATH} ...", file=sys.stderr)
        fcntl.flock(lock, fcntl.LOCK_EX)
        lock.write(f"{os.getpid()} {REPO_ROOT}\n")
        lock.flush()
        state = _run(["xcrun", "simctl", "list", "devices", udid], check=False, capture_output=True, text=True)
        was_booted = "(Booted)" in (state.stdout or "")
        boot_exclusive(udid)
        _run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)
        if pose:
            # Inside this batch's lock hold: another lane's run between batches shuts the
            # Duo down, and it boots closed in its default orientation.
            # Still booted from this run's previous batch: the pose (and any rotation)
            # stands; only a fresh boot or a mismatch sets it again.
            # A fresh boot comes up folded in its default orientation, so `folded`
            # without rotations is verified by detection alone (no Device Hub needed).
            verifiable = was_booted or (pose == "folded" and not rotate)
            problem = require_pose(udid, pose, False) if verifiable else "boot"
            reset = problem is not None and set_pose
            if reset:
                problem = require_pose(udid, pose, True)
            if problem:
                print(problem, file=sys.stderr)
                return EXIT_POSE_MISMATCH, time.time() - start, log_path, result_bundle
            if reset:
                for direction in rotate or []:
                    try:
                        set_duo_pose(udid, f"rotate-{direction}")
                    except DeviceHubError as error:
                        print(error, file=sys.stderr)
                        return error.code, time.time() - start, log_path, result_bundle
        cmd = [
            "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", product().scheme,
            "-destination", f"platform=iOS Simulator,id={udid}",
            "-derivedDataPath", str(derived), "-resultBundlePath", str(result_bundle),
        ]
        for selector in selectors:
            cmd.append(f"-only-testing:{product().uitest_target}/{selector}")
        cmd += ["test-without-building", "-quiet"]
        print("+", " ".join(cmd), file=sys.stderr)
        with open(log_path, "w") as log, simulator_accessibility(udid, a11y):
            try:
                process = subprocess.run(
                    cmd, cwd=APPLE_DIR, env=_env(),
                    stdout=log, stderr=subprocess.STDOUT, check=False,
                    timeout=timeout,
                )
            except subprocess.TimeoutExpired:
                # Never let a hung run hold the shared simulator lock past `timeout`:
                # `subprocess.run` already killed the xcodebuild process tree: this
                # also stops the app under test so nothing lingers on the simulator.
                _run(["xcrun", "simctl", "terminate", udid, product().bundle_id],
                     check=False, capture_output=True)
                process = subprocess.CompletedProcess(cmd, 124)
                log.write(f"\nTIMEOUT after {timeout}s; killed.\n")
    elapsed = time.time() - start
    return process.returncode, elapsed, log_path, result_bundle

# region CI simulator

#: Device type `ci-device` creates: the iPhone the local ``iphone`` alias names.
CI_DEVICE_TYPE = "iPhone 17 Pro"

#: Name of the throwaway simulator `ci-device` creates (and reuses on a second call).
CI_DEVICE_NAME = "FST CI iPhone"

#: Device type `apple-ci`'s iPad journeys run on: the iPad the local ``ipad`` alias names.
CI_IPAD_DEVICE_TYPE = "iPad Pro 11-inch (M5)"


def ci_device_name(device_type: str = CI_DEVICE_TYPE) -> str:
    """Name the throwaway simulator ``ci-device`` creates for ``device_type``.

    Each device type gets its own name, so asking for the iPad never reuses the iPhone.

    Args:
        device_type: Device type name, e.g. ``"iPad Pro 11-inch (M5)"``.

    Returns:
        ``CI_DEVICE_NAME`` for the default iPhone, else ``"FST CI <device type>"``.
    """
    return CI_DEVICE_NAME if device_type == CI_DEVICE_TYPE else f"FST CI {device_type}"


def _version_key(version: str) -> tuple[int, ...]:
    """Turn a runtime version (``"27.1"``) into a sortable tuple (``(27, 1)``)."""
    return tuple(int(part) for part in str(version).split(".") if part.isdigit())


def pick_ci_runtime(runtimes: list[dict], device_type: str = CI_DEVICE_TYPE) -> tuple[str, str]:
    """Choose the newest available iOS runtime that can run ``device_type``.

    Args:
        runtimes: ``xcrun simctl list runtimes available -j``'s ``runtimes`` array.
        device_type: Device type name, e.g. ``"iPhone 17 Pro"``.

    Returns:
        ``(runtime identifier, device type identifier)``.

    Raises:
        LookupError: When no available iOS runtime supports the device type.
    """
    best: tuple[tuple[int, ...], str, str] | None = None
    for runtime in runtimes:
        is_ios = runtime.get("platform") == "iOS" or str(runtime.get("name", "")).startswith("iOS ")
        if not is_ios or not runtime.get("isAvailable", True):
            continue
        for kind in runtime.get("supportedDeviceTypes", []):
            if kind.get("name") != device_type:
                continue
            key = _version_key(runtime.get("version", "0"))
            if best is None or key > best[0]:
                best = (key, runtime["identifier"], kind["identifier"])
    if best is None:
        raise LookupError(f"no available iOS runtime supports {device_type!r}")
    return best[1], best[2]


def existing_ci_device(devices: dict, runtime: str, name: str = CI_DEVICE_NAME) -> str | None:
    """Find a simulator ``ci-device`` already created on this runner.

    Args:
        devices: ``xcrun simctl list devices -j``'s ``devices`` map (runtime → devices).
        runtime: Runtime identifier the device must run.
        name: Device name to match.

    Returns:
        Its UDID, or ``None``.
    """
    for device in devices.get(runtime, []):
        if device.get("name") == name and device.get("isAvailable", True):
            return device.get("udid")
    return None


def cmd_ci_device(args: argparse.Namespace) -> int:
    """Create (or reuse) the CI runner's iPhone or iPad simulator and print its UDID.

    ``apple-ci`` runs its simulator journeys on a fresh GitHub-hosted runner with no
    ``DEVICES``; this makes one ``iPhone 17 Pro`` (or ``--type``, e.g. the iPad journeys'
    ``CI_IPAD_DEVICE_TYPE``) on the newest available iOS runtime, named per type by
    ``ci_device_name``, for ``uitest --device <UDID>``. It refuses to run outside GitHub Actions: on a shared
    Mac, simulators are the operator's and are never created or changed by a lane.

    Args:
        args: Parsed CLI arguments (``type``).

    Returns:
        0 with the UDID on stdout; 2 outside CI; 1 when no runtime fits.
    """
    if os.environ.get("GITHUB_ACTIONS") != "true":
        print("ci-device creates a simulator, so it runs only on a CI runner (GITHUB_ACTIONS=true); "
              "on a shared Mac use a DEVICES alias", file=sys.stderr)
        return 2
    listing = _run(["xcrun", "simctl", "list", "runtimes", "available", "-j"], capture_output=True, text=True)
    try:
        runtime, device_type = pick_ci_runtime(json.loads(listing.stdout).get("runtimes", []), args.type)
    except LookupError as error:
        print(error, file=sys.stderr)
        return 1
    devices = _run(["xcrun", "simctl", "list", "devices", "-j"], capture_output=True, text=True)
    name = ci_device_name(args.type)
    udid = existing_ci_device(json.loads(devices.stdout).get("devices", {}), runtime, name)
    if udid is None:
        created = _run(["xcrun", "simctl", "create", name, device_type, runtime],
                       capture_output=True, text=True)
        udid = created.stdout.strip()
    print(f"{name}: {args.type} on {runtime}", file=sys.stderr)
    print(udid)
    return 0

# endregion


def _with_sim_lock(udid: str, action) -> int:
    """Boot ``udid`` exclusively under the simulator lock and run ``action(udid)``.

    Args:
        udid: Simulator to boot.
        action: Callable returning an exit code.

    Returns:
        ``action``'s exit code.
    """
    LOCK_PATH.touch(exist_ok=True)
    with open(LOCK_PATH, "w") as lock:
        print(f"waiting for simulator lock {LOCK_PATH} ...", file=sys.stderr)
        fcntl.flock(lock, fcntl.LOCK_EX)
        lock.write(f"{os.getpid()} {REPO_ROOT}\n")
        lock.flush()
        return action(udid)


def cmd_pose(args: argparse.Namespace) -> int:
    """Print, set or calibrate the iPhone Duo pose under the lock.

    Without flags, prints ``folded``/``unfolded``/``unknown`` from the lit panel.
    ``--set`` presses Device Hub's fold/unfold/partial/rotate control by UI scripting
    and verifies the result; ``--menu`` chooses a Device Hub menu command for the
    device (e.g. ``Device/Keyboard/Toggle Software Keyboard``); ``--list-controls``
    prints the device window's controls and Device Hub's menus (to calibrate
    ``_POSE_KEYWORDS``). Each opens Device Hub (via Xcode's menu) and the device's
    window when missing. They need the macOS Accessibility permission for the
    responsible app; without it they print exactly which app to allow and exit 4.
    This tool never changes privacy settings itself.

    Args:
        args: Parsed CLI arguments (device, set, menu, list_controls).

    Returns:
        0 on success; 1 unknown pose; 3 pose not reached; 4 no permission; 5 no control.
    """
    if code := scripting_preflight(bool(args.set or args.menu or args.list_controls)):
        return code

    def action(udid: str) -> int:
        boot_exclusive(udid)
        _run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)
        try:
            if args.list_controls:
                for control in list_device_hub_controls(udid):
                    text = " | ".join(str(control.get(key) or "") for key in
                                      ("role", "subrole", "title", "description", "help", "identifier"))
                    print(f"{control['kind']:7} {control['path']}  {text}")
                return 0
            if args.set:
                set_duo_pose(udid, args.set)
            if args.menu:
                press_device_hub_menu(udid, [part.strip() for part in args.menu.split("/")])
        except DeviceHubError as error:
            print(error, file=sys.stderr)
            return error.code
        pose = detect_pose(udid)
        print(pose)
        return 0 if pose != "unknown" else 1
    return _with_sim_lock(resolve_device(args.device), action)


def cmd_shutdown(args: argparse.Namespace) -> int:
    """Shut down one product simulator under the lock (e.g. the Duo after a Duo session).

    Args:
        args: Parsed CLI arguments (device).

    Returns:
        Process exit code.
    """
    def action(udid: str) -> int:
        _run(["xcrun", "simctl", "shutdown", udid], check=False, capture_output=True)
        return 0
    return _with_sim_lock(resolve_device(args.device), action)

# endregion


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Optional argument list (defaults to ``sys.argv``).

    Returns:
        Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    build = sub.add_parser("build", help="build the iOS app for this worktree")
    build.add_argument("--configuration", default="Debug")
    build.add_argument("--app", choices=sorted(PRODUCTS), default=None,
                       help="scheme to build: phone (FestivalMobile, default) or ipad (FestivalMobileIPad); "
                            "both build the same universal FestivalMobile app")
    build.set_defaults(func=cmd_build)

    shot = sub.add_parser("shot", help="install, launch, screenshot (serialized)")
    shot.add_argument("--device", default="iphone", help=f"alias {sorted(DEVICES)} or UDID")
    shot.add_argument("--tab", help="FST_DEBUG_TAB: songs|leaderboards|settings|...")
    shot.add_argument("--route", help="FST_DEBUG_ROUTE, e.g. player:<accountId>, shop, leaderboards")
    shot.add_argument("--env", action="append", help="extra KEY=VALUE launch environment")
    shot.add_argument("--wait", type=float, default=6.0, help="seconds before first screenshot")
    shot.add_argument("--interval", type=float, default=2.0, help="seconds between screenshots")
    shot.add_argument("--out", action="append", required=True, help="screenshot path (repeatable)")
    shot.add_argument("--keep", action="store_true", help="leave the app running")
    shot.add_argument("--clean-status-bar", action="store_true",
                      help="override the status bar (9:41, full bars, charged) for marketing captures")
    shot.add_argument("--launch-arg", action="append",
                      help="app launch argument (repeatable; use --launch-arg=-key form), e.g. "
                           "--launch-arg=-fst.settings.showProLead --launch-arg='<false/>'")
    shot.add_argument("--record", help="also record the session to this .mp4 (for remote review)")
    shot.add_argument("--record-tail", type=float, default=3.0,
                      help="seconds to keep recording after the last screenshot (animations)")
    shot.add_argument("--pose", choices=sorted(POSE_EXPECTED_CLASS),
                      help="iPhone Duo: fail (exit 3) unless the device is in this pose (set it in Device Hub)")
    shot.add_argument("--set-pose", action="store_true",
                      help="with --pose: press Device Hub's pose control if needed (UI scripting, Accessibility)")
    shot.add_argument("--rotate", action="append", choices=["left", "right"],
                      help="iPhone Duo: rotate via Device Hub after the pose check (repeatable; UI scripting)")
    shot.add_argument("--display", choices=[*sorted(DUO_PANELS), "auto"],
                      help="iPhone Duo panel to capture; auto = the lit panel (default: simctl's first display)")
    shot.add_argument("--a11y", action="append", choices=sorted(A11Y_SETTINGS),
                      help="switch a simulator accessibility setting on for this capture, "
                           "restored afterwards (repeatable)")
    shot.add_argument("--app", choices=sorted(PRODUCTS), default=None,
                       help="UI-test product (default: ipad for the ipad alias, else phone)")
    shot.set_defaults(func=cmd_shot)

    drive = sub.add_parser(
        "drive", help="script taps/swipes/scrolls/screenshots (serialized, builds once)"
    )
    drive.add_argument("--device", default="iphone", help=f"alias {sorted(DEVICES)} or UDID")
    drive.add_argument("--tab", help="FST_DEBUG_TAB, applied at app launch")
    drive.add_argument("--animate", action="store_true",
                       help="keep the album carousel animating (default freezes it so steps don't wait for idle)")
    drive.add_argument("--record", help="record the whole drive to this .mp4 (for remote review)")
    drive.add_argument("--timeout", type=float, default=180.0,
                       help="kill the run after this many seconds (default 180) so the sim lock is released")
    drive.add_argument("--route", help="FST_DEBUG_ROUTE, applied at app launch")
    drive.add_argument("--pose", choices=sorted(POSE_EXPECTED_CLASS),
                       help="iPhone Duo: fail (exit 3) unless the device is in this pose (set it in Device Hub)")
    drive.add_argument("--set-pose", action="store_true",
                       help="with --pose: press Device Hub's pose control if needed (UI scripting, Accessibility)")
    drive.add_argument("--display", choices=sorted(DUO_PANELS),
                       help="iPhone Duo panel to record with --record (default: simctl's first display); "
                            "recordings see transitions that shot: steps cannot")
    drive.add_argument("--env", action="append", help="extra KEY=VALUE app launch environment")
    drive.add_argument("--clean-status-bar", action="store_true",
                       help="override the status bar (9:41, full bars, charged) for marketing captures")
    drive.add_argument("--steps", help="';'-separated step script, e.g. 'tap:x; shot:/tmp/a.png'")
    drive.add_argument("--steps-file", help="path to a newline-separated step script")
    drive.add_argument(
        "--rebuild", action="store_true", help="force a fresh build-for-testing"
    )
    drive.add_argument("--app", choices=sorted(PRODUCTS), default=None,
                       help="UI-test product (default: ipad for the ipad alias, else phone)")
    drive.set_defaults(func=cmd_drive)

    uitest = sub.add_parser(
        "uitest", help="build once, run one or more XCUITest classes/methods (serialized, batched)"
    )
    uitest.add_argument("--device", default="iphone", help=f"alias {sorted(DEVICES)} or UDID")
    uitest.add_argument(
        "--only", action="append", required=True,
        help="Class or Class/testMethod under FestivalMobileUITests (repeatable)"
    )
    uitest.add_argument("--timeout", type=float, default=300.0,
                        help="kill each batch's run after this many seconds "
                             "(default 300 = 5 min) so the sim lock is released")
    uitest.add_argument("--batch-size", type=int, default=3,
                        help="max selectors per simulator-lock hold (default 3); "
                             "the lock is released between batches for other lanes")
    uitest.add_argument(
        "--rebuild", action="store_true", help="force a fresh build-for-testing"
    )
    uitest.add_argument("--a11y", action="append", choices=sorted(A11Y_SETTINGS),
                        help="switch a simulator accessibility setting on for each batch, "
                             "restored afterwards (repeatable)")
    uitest.add_argument("--app", choices=sorted(PRODUCTS), default=None,
                       help="UI-test product (default: ipad for the ipad alias, else phone)")
    uitest.add_argument("--pose", choices=sorted(POSE_EXPECTED_CLASS),
                        help="iPhone Duo: require this pose in every batch (re-set inside the batch's "
                             "lock hold with --set-pose, so another lane's reboot cannot lose it)")
    uitest.add_argument("--set-pose", action="store_true",
                        help="with --pose: press Device Hub's pose control when needed (UI scripting)")
    uitest.add_argument("--rotate", action="append", choices=["left", "right"],
                        help="with --set-pose: Device Hub rotations after the pose, applied from a fresh "
                             "boot (default orientation) whenever the Duo had to boot (repeatable)")
    uitest.add_argument("--fail-on-skip", action="store_true",
                        help="fail a batch in which any test skipped or none ran (CI: a journey that "
                             "cannot find its fixture skips, and an all-skipped batch otherwise passes)")
    uitest.set_defaults(func=cmd_uitest)

    ci_device = sub.add_parser(
        "ci-device", help="CI runner only: create (or reuse) an iPhone or iPad simulator and print its UDID"
    )
    ci_device.add_argument("--type", default=CI_DEVICE_TYPE,
                           help=f"device type name (default {CI_DEVICE_TYPE}; apple-ci's iPad: {CI_IPAD_DEVICE_TYPE})")
    ci_device.set_defaults(func=cmd_ci_device)

    pose = sub.add_parser("pose", help="print, set (Device Hub UI scripting) or calibrate the iPhone Duo pose")
    pose.add_argument("--device", default="duo", help=f"alias {sorted(DEVICES)} or UDID")
    pose.add_argument("--set", choices=POSE_ACTIONS,
                      help="press Device Hub's control for this pose/rotation and verify it (needs Accessibility)")
    pose.add_argument("--menu", help="choose a Device Hub menu command for the device, e.g. "
                                     "'Device/Keyboard/Toggle Software Keyboard' (needs Accessibility)")
    pose.add_argument("--list-controls", action="store_true",
                      help="print Device Hub's device-window controls and menus (calibrates the pose keywords)")
    pose.set_defaults(func=cmd_pose)

    shutdown = sub.add_parser("shutdown", help="shut down one product simulator (serialized)")
    shutdown.add_argument("--device", required=True, help=f"alias {sorted(DEVICES)} or UDID")
    shutdown.set_defaults(func=cmd_shutdown)

    args = parser.parse_args(argv)
    select_product(getattr(args, "app", None), getattr(args, "device", None))
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
