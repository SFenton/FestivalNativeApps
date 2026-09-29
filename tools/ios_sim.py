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

Devices are named by alias (see ``DEVICES``) or UDID. The default is the
iPhone 17 Pro on iOS 26.5 (Liquid Glass).
"""

from __future__ import annotations

import argparse
import fcntl
import signal
import hashlib
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
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
}

#: Source trees that, if changed, require rebuilding the driver's UI-test bundle.
DRIVER_HASH_ROOTS = ("Sources", "Apps/iOS", "Apps/iOSUITests", "project.yml")

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
        Path to ``FestivalMobile.app``.

    Raises:
        SystemExit: If the app has not been built yet.
    """
    path = derived_data() / "Build/Products/Debug-iphonesimulator/FestivalMobile.app"
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
    """Collect the host paths a ``shot:``/``tree:`` step will write.

    Args:
        steps: Parsed step strings.

    Returns:
        Requested output paths, in step order.
    """
    paths = []
    for step in steps:
        verb, _, arg = step.partition(":")
        if verb in ("shot", "tree") and arg:
            paths.append(arg)
    return paths


def driver_derived_data() -> Path:
    """Separate DerivedData for the UI-test bundle so `build`/`shot` are untouched.

    Returns:
        ``apple/DerivedData/lane-driver`` inside the current worktree.
    """
    return APPLE_DIR / "DerivedData" / "lane-driver"


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
        / "FestivalMobileUITests-Runner.app"
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
            result = _run(["xcrun", "simctl", "io", udid, "screenshot", "--type=bmp",
                           f"--display={display}", str(path)], check=False, capture_output=True)
            if result.returncode or not path.exists():
                return "unknown"
            dark[panel] = bmp_is_dark(path.read_bytes())
    return classify_pose(dark["outer"], dark["inner"])


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
    actual = detect_pose(udid)
    print(f"duo pose: {actual}", file=sys.stderr)
    if actual == expected and not (set_pose and pose == "half"):
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

#: Accessibility-tree walk bounds for the JXA dump (each property read is an Apple event).
_HUB_MAX_DEPTH = 14
_HUB_MAX_ELEMENTS = 2000

#: JavaScript for Automation run by ``osascript -l JavaScript``. ``dump`` returns the
#: Device Hub window controls and menu items as JSON (each with a ``path``);
#: ``press <path-json>`` activates Device Hub and presses that element.
_DEVICE_HUB_JXA = r"""
function run(argv) {
  const MAX_DEPTH = %(depth)d, MAX_ELEMENTS = %(limit)d;
  const se = Application('System Events');
  const procs = se.applicationProcesses.whose({bundleIdentifier: '%(bundle)s'})();
  let proc = null;
  for (const p of procs) {
    let count = 0;
    try { count = p.windows.length; } catch (e) {}
    if (count > 0 && (proc === null || p.frontmost())) proc = p;
  }
  if (proc === null) return JSON.stringify({error: 'no-window', processes: procs.length});
  const read = (f) => { try { const v = f(); return v === undefined ? null : v; } catch (e) { return null; } };
  if (argv[0] === 'press') {
    const path = JSON.parse(argv[1]);
    proc.frontmost = true;
    delay(0.3);
    let el;
    if (path[0] === 'w') {
      el = proc.windows[path[1]];
      for (const i of path.slice(2)) el = el.uiElements[i];
      try { el.actions.byName('AXPress').perform(); } catch (e) { se.click(el); }
    } else {
      el = proc.menuBars[0].menuBarItems[path[1]].menus[0].menuItems[path[2]];
      if (path.length > 3) el = el.menus[0].menuItems[path[3]];
      el.click();
    }
    return JSON.stringify({pressed: path});
  }
  const out = [];
  const describe = (el, kind, path, windowTitle) => ({
    kind: kind, path: path, window: windowTitle,
    role: read(() => el.role()), subrole: read(() => el.subrole()),
    title: read(() => el.name()), description: read(() => el.description()),
    help: read(() => el.help()),
    identifier: read(() => el.attributes.byName('AXIdentifier').value()),
    enabled: read(() => el.enabled()),
  });
  const walk = (el, path, depth, windowTitle) => {
    if (depth > MAX_DEPTH || out.length >= MAX_ELEMENTS) return;
    const kids = read(() => el.uiElements()) || [];
    for (let i = 0; i < kids.length && out.length < MAX_ELEMENTS; i++) {
      const p = path.concat([i]);
      out.push(describe(kids[i], 'control', p, windowTitle));
      walk(kids[i], p, depth + 1, windowTitle);
    }
  };
  const windows = proc.windows();
  for (let w = 0; w < windows.length; w++) {
    walk(windows[w], ['w', w], 0, read(() => windows[w].name()));
  }
  const bar = read(() => proc.menuBars[0].menuBarItems()) || [];
  for (let m = 0; m < bar.length; m++) {
    const items = read(() => bar[m].menus[0].menuItems()) || [];
    for (let j = 0; j < items.length; j++) {
      out.push(describe(items[j], 'menu', ['m', m, j], null));
      const sub = read(() => items[j].menus[0].menuItems()) || [];
      for (let k = 0; k < sub.length; k++) out.push(describe(sub[k], 'menu', ['m', m, j, k], null));
    }
  }
  return JSON.stringify({pid: read(() => proc.unixId()), controls: out});
}
"""

#: Words that identify each action's control in Device Hub's accessibility text
#: (title, description, help or identifier). Uncalibrated guesses from DeviceKit's
#: symbols (``rotate.device.left``); ``pose --list-controls`` prints the real tree.
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
    for control in controls:
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


def _device_hub_script(*argv: str) -> dict:
    """Run the Device Hub JXA script and parse its JSON reply.

    Args:
        *argv: ``dump`` or ``press <path-json>``.

    Returns:
        The decoded reply.

    Raises:
        DeviceHubError: Permission refusals, a missing window or a script failure.
    """
    import json
    script = _DEVICE_HUB_JXA % {"depth": _HUB_MAX_DEPTH, "limit": _HUB_MAX_ELEMENTS,
                                "bundle": DEVICE_HUB_BUNDLE_ID}
    result = subprocess.run(["osascript", "-l", "JavaScript", "-e", script, *argv],
                            capture_output=True, text=True, timeout=120, check=False)
    error = (result.stderr or "").strip()
    if result.returncode:
        if "-1743" in error or "Not authorized to send Apple events" in error:
            raise DeviceHubError(accessibility_instructions(responsible_process(), automation=True),
                                 EXIT_NO_ACCESSIBILITY)
        if "-1719" in error or "-25211" in error or "assistive access" in error:
            raise DeviceHubError(accessibility_instructions(responsible_process()),
                                 EXIT_NO_ACCESSIBILITY)
        raise DeviceHubError(f"Device Hub script failed: {error}", EXIT_NO_CONTROL)
    reply = json.loads(result.stdout or "{}")
    if reply.get("error") == "no-window":
        raise DeviceHubError(
            "Device Hub has no open window. Open it (Xcode > Open Developer Tool > Device Hub), "
            "select \"iPhone Duo (FST)\" so its pose buttons show, then re-run.", EXIT_NO_CONTROL)
    return reply


def ensure_device_hub() -> None:
    """Launch Device Hub if it is not running (it hosts the pose controls)."""
    running = subprocess.run(["pgrep", "-f", str(DEVICE_HUB_APP / "Contents/MacOS/DeviceHub")],
                             capture_output=True, check=False)
    if running.returncode:
        _run(["open", "-g", str(DEVICE_HUB_APP)], check=False)
        time.sleep(4)


def list_device_hub_controls() -> list[dict]:
    """Dump Device Hub's window controls and menu items (for calibration).

    Returns:
        ``dump`` entries.

    Raises:
        DeviceHubError: No permission or no window.
    """
    if not accessibility_trusted():
        raise DeviceHubError(accessibility_instructions(responsible_process()), EXIT_NO_ACCESSIBILITY)
    ensure_device_hub()
    return _device_hub_script("dump").get("controls", [])


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
        _run(["xcrun", "simctl", "io", udid, "screenshot", "--type=bmp",
              f"--display={DUO_PANELS[panel]}", str(path)], check=False, capture_output=True)
        return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def set_duo_pose(udid: str, action: str, settle: float = 12.0) -> str:
    """Press Device Hub's control for a pose action and verify the result.

    Call under the simulator lock with the Duo booted. Poses are verified with the
    same lit-panel check as ``--pose``; rotations by an unchanged pose plus a
    changed lit-panel image (the app re-laid out).

    Args:
        udid: Booted iPhone Duo.
        action: One of ``POSE_ACTIONS``.
        settle: Seconds to wait for the pose to take effect.

    Returns:
        The verified panel classification after the action.

    Raises:
        DeviceHubError: Missing permission, no matching control, or verification failure.
    """
    import json
    expected = POSE_EXPECTED_CLASS.get(action)
    before = detect_pose(udid)
    if expected is not None and before == expected and action != "half":
        print(f"duo pose already {before}", file=sys.stderr)
        return before
    controls = list_device_hub_controls()
    control = match_pose_control(action, controls)
    if control is None:
        raise DeviceHubError(
            f"No Device Hub control matched '{action}' among {len(controls)} elements. "
            "Run `python3 tools/ios_sim.py pose --list-controls` and update _POSE_KEYWORDS.",
            EXIT_NO_CONTROL)
    print(f"pressing Device Hub control {control.get('role')} "
          f"'{control.get('title') or control.get('description')}' at {control['path']}", file=sys.stderr)
    digest = _panel_digest(udid) if expected is None else None
    _device_hub_script("press", json.dumps(control["path"]))
    deadline = time.time() + settle
    while True:
        time.sleep(1.5)
        actual = detect_pose(udid)
        if expected is None:
            if actual == before and _panel_digest(udid) not in (None, digest):
                return actual
        elif actual == expected:
            return actual
        if time.time() > deadline:
            raise DeviceHubError(
                f"Pressed the {action} control but the Duo reads {actual} "
                f"(expected {expected or before + ' with a re-laid-out panel'}).", EXIT_POSE_MISMATCH)

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
            "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", "FestivalMobile",
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
        _run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], check=False, capture_output=True)
        launch_env = _env()
        if args.tab:
            launch_env["SIMCTL_CHILD_FST_DEBUG_TAB"] = args.tab
        if args.route:
            launch_env["SIMCTL_CHILD_FST_DEBUG_ROUTE"] = args.route
        for pair in args.env or []:
            key, _, value = pair.partition("=")
            launch_env[f"SIMCTL_CHILD_{key}"] = value
        with ScreenRecording(udid, args.record, args.display if args.display in DUO_PANELS else None):
            _run(["xcrun", "simctl", "launch", udid, BUNDLE_ID], env=launch_env)
            for index, out in enumerate(args.out):
                time.sleep(args.wait if index == 0 else args.interval)
                Path(out).parent.mkdir(parents=True, exist_ok=True)
                selector = [f"--display={display}"] if display else []
                _run(["xcrun", "simctl", "io", udid, "screenshot", *selector, out], capture_output=True)
                print(out)
            if args.record and args.record_tail:
                time.sleep(args.record_tail)
        if not args.keep:
            _run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], check=False, capture_output=True)
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
    udid = resolve_device(args.device)
    derived = driver_derived_data()

    current_hash = source_hash()
    if args.rebuild or driver_build_stale(derived, current_hash):
        _run(["xcodegen", "generate", "-q"], cwd=APPLE_DIR)
        with build_lock():
            build = _run([
                "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", "FestivalMobile",
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
            problem = require_pose(udid, args.pose, args.set_pose)
            if problem:
                print(problem, file=sys.stderr)
                return EXIT_POSE_MISMATCH
            cmd = [
                "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", "FestivalMobile",
                "-destination", f"platform=iOS Simulator,id={udid}",
                "-derivedDataPath", str(derived), "-resultBundlePath", str(result_bundle),
                "-only-testing:FestivalMobileUITests/DriverTests/testDrive",
                "test-without-building", "-quiet",
            ]
            print("+", " ".join(cmd), file=sys.stderr)
            with open(log_path, "w") as log, ScreenRecording(udid, args.record, args.display):
                try:
                    process = subprocess.run(
                        cmd, cwd=APPLE_DIR, env=launch_env,
                        stdout=log, stderr=subprocess.STDOUT, check=False,
                        timeout=args.timeout,
                    )
                except subprocess.TimeoutExpired:
                    # Never let a hung run hold the shared simulator lock.
                    _run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID],
                         check=False, capture_output=True)
                    process = subprocess.CompletedProcess(cmd, 124)
                    log.write(f"\nTIMEOUT after {args.timeout}s; killed.\n")
    finally:
        steps_path.unlink(missing_ok=True)
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
    udid = resolve_device(args.device)
    derived = driver_derived_data()

    current_hash = source_hash()
    if args.rebuild or driver_build_stale(derived, current_hash):
        _run(["xcodegen", "generate", "-q"], cwd=APPLE_DIR)
        with build_lock():
            build = _run([
                "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", "FestivalMobile",
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
            udid=udid, derived=derived, selectors=batch, timeout=args.timeout
        )
        if returncode:
            failed_batches.append((batch, returncode))
            log_text = log_path.read_text(encoding="utf-8", errors="replace")
            print(f"uitest {label} FAILED after {elapsed:.1f}s; last lines of {log_path}:", file=sys.stderr)
            print("\n".join(log_text.splitlines()[-60:]), file=sys.stderr)
            print(f"result bundle: {result_bundle}", file=sys.stderr)
        else:
            print(f"uitest {label} OK in {elapsed:.1f}s ({len(batch)} selector(s))", file=sys.stderr)
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


def _run_uitest_batch(
    *, udid: str, derived: Path, selectors: list[str], timeout: float
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
        boot_exclusive(udid)
        _run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)
        cmd = [
            "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", "FestivalMobile",
            "-destination", f"platform=iOS Simulator,id={udid}",
            "-derivedDataPath", str(derived), "-resultBundlePath", str(result_bundle),
        ]
        for selector in selectors:
            cmd.append(f"-only-testing:FestivalMobileUITests/{selector}")
        cmd += ["test-without-building", "-quiet"]
        print("+", " ".join(cmd), file=sys.stderr)
        with open(log_path, "w") as log:
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
                _run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID],
                     check=False, capture_output=True)
                process = subprocess.CompletedProcess(cmd, 124)
                log.write(f"\nTIMEOUT after {timeout}s; killed.\n")
    elapsed = time.time() - start
    return process.returncode, elapsed, log_path, result_bundle

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
    and verifies the result; ``--list-controls`` prints Device Hub's accessibility
    controls (to calibrate ``_POSE_KEYWORDS``). Both need the macOS Accessibility
    permission for the responsible app; without it they print exactly which app to
    allow and exit 4. This tool never changes privacy settings itself.

    Args:
        args: Parsed CLI arguments (device, set, list_controls).

    Returns:
        0 on success; 1 unknown pose; 3 pose not reached; 4 no permission; 5 no control.
    """
    if args.list_controls:
        try:
            controls = list_device_hub_controls()
        except DeviceHubError as error:
            print(error, file=sys.stderr)
            return error.code
        for control in controls:
            text = " | ".join(str(control.get(key)) for key in
                              ("role", "subrole", "title", "description", "help", "identifier"))
            print(f"{control['kind']:7} {control['path']}  {text}")
        return 0

    if code := scripting_preflight(bool(args.set)):
        return code

    def action(udid: str) -> int:
        boot_exclusive(udid)
        _run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)
        if args.set:
            try:
                set_duo_pose(udid, args.set)
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
    drive.add_argument("--steps", help="';'-separated step script, e.g. 'tap:x; shot:/tmp/a.png'")
    drive.add_argument("--steps-file", help="path to a newline-separated step script")
    drive.add_argument(
        "--rebuild", action="store_true", help="force a fresh build-for-testing"
    )
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
    uitest.set_defaults(func=cmd_uitest)

    pose = sub.add_parser("pose", help="print, set (Device Hub UI scripting) or calibrate the iPhone Duo pose")
    pose.add_argument("--device", default="duo", help=f"alias {sorted(DEVICES)} or UDID")
    pose.add_argument("--set", choices=POSE_ACTIONS,
                      help="press Device Hub's control for this pose/rotation and verify it (needs Accessibility)")
    pose.add_argument("--list-controls", action="store_true",
                      help="print Device Hub's accessibility controls (calibrates the pose keywords)")
    pose.set_defaults(func=cmd_pose)

    shutdown = sub.add_parser("shutdown", help="shut down one product simulator (serialized)")
    shutdown.add_argument("--device", required=True, help=f"alias {sorted(DEVICES)} or UDID")
    shutdown.set_defaults(func=cmd_shutdown)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
