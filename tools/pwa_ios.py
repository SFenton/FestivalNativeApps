#!/usr/bin/env python3
"""Installed-PWA reference lab for Apple simulators (and macOS Safari).

Reproduces the real festivalscoretracker.com PWA the way users run it: opened in
Mobile Safari, added to the Home Screen as a web app, then launched standalone
from SpringBoard. Everything that touches a simulator reuses ``tools/ios_sim.py``'s
machinery: the shared ``~/.fst-sim.lock`` (bounded holds), ``boot_exclusive`` (one
FST product simulator at a time), Duo pose checks, and ``simctl`` screen recording.
Scripted interaction runs ``apple/Apps/iOSUITests/PWADriverTests.swift`` from the
same cached build-for-testing product as ``ios_sim.py drive``.

Service safety: the production PWA is browse-only. Never select a profile, open a
player page (it calls the blocked player-stats GET), type into band search or the
global search (it queries bands), or open Shop purchase links. Use ``--url`` with a
loopback fixture origin (``fixture-web``) for selected-profile and search states.

Examples::

    python3 tools/pwa_ios.py open --device iphone --url https://festivalscoretracker.com/songs
    python3 tools/pwa_ios.py install --device iphone        # Safari > Share > Add to Home Screen
    python3 tools/pwa_ios.py drive --device iphone --record ~/FestivalShowcase/pwa/ios/songs-launch.mp4 \\
        --steps "home; launchIcon:FST; wait:6; shot:/tmp/pwa.png"
    python3 tools/pwa_ios.py shot --device iphone --out /tmp/now.png
    python3 tools/pwa_ios.py motion ~/FestivalShowcase/pwa/ios/songs-launch.mp4   # transition timing
    python3 tools/pwa_ios.py compress in.mp4 out.mp4                             # phone-sized clip
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ios_sim  # noqa: E402  (shared simulator lock, boot, pose and recording helpers)

# region Configuration

#: Production PWA origin (browse-only; see the module docstring).
PWA_URL = "https://festivalscoretracker.com/"
#: Home Screen label: the page's ``apple-mobile-web-app-title`` meta tag.
PWA_ICON_LABEL = "FST"
#: Default capture root (private: real player data and third-party art; never commit).
SHOWCASE = Path.home() / "FestivalShowcase" / "pwa"
#: XCUITest selector for the PWA driver.
PWA_TEST = "FestivalMobileUITests/PWADriverTests/testPWADrive"
#: Swift helper that extracts frames from a recording at exact timestamps.
FRAMES_SWIFT = Path(__file__).resolve().parent / "visual" / "video_frames.swift"

#: Safari Share > Add to Home Screen, per form factor. Labels are the iOS 26.5 /
#: 27.1 Safari accessibility labels (calibrated with ``tree:`` dumps). ``stopIfExists``
#: makes a re-install a no-op when the icon is already on the Home Screen.
INSTALL_STEPS = {
    "phone": [
        "target:springboard", "home", "wait:1", "stopIfExists:{label}",
        "target:safari", "openURL:{url}", "activate", "wait:6",
        "tap:MoreMenuButton", "wait:1", "tapText:Share", "wait:2",
        "scrollTo:Add to Home Screen", "tapText:Add to Home Screen", "wait:2",
        "{rename}", "tapText:Add", "wait:3",
    ],
    "pad": [
        "target:springboard", "home", "wait:1", "stopIfExists:{label}",
        "target:safari", "openURL:{url}", "activate", "wait:6",
        # iPad shares from a popover: swiping (scrollTo) would dismiss it, and the
        # action row is collapsed behind "View More".
        "tap:ShareButton", "wait:2", "tapText:View More", "wait:1.5",
        "tapText:Add to Home Screen", "wait:2",
        "{rename}", "tapText:Add", "wait:3",
    ],
}

# endregion

# region Simulator driver


def ensure_driver_build(rebuild: bool) -> int:
    """Build the shared UI-test bundle when stale (same cache as ``ios_sim.py drive``).

    Args:
        rebuild: Force ``build-for-testing``.

    Returns:
        0 on success, else ``xcodebuild``'s exit code.
    """
    derived = ios_sim.driver_derived_data()
    current = ios_sim.source_hash()
    if not rebuild and not ios_sim.driver_build_stale(derived, current):
        print(f"driver build up to date ({current[:12]})", file=sys.stderr)
        return 0
    ios_sim._run(["xcodegen", "generate", "-q"], cwd=ios_sim.APPLE_DIR)
    with ios_sim.build_lock():
        build = ios_sim._run([
            "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", "FestivalMobile",
            "-configuration", "Debug", "-destination", "generic/platform=iOS Simulator",
            "-derivedDataPath", str(derived), "build-for-testing", "-quiet",
        ], cwd=ios_sim.APPLE_DIR, check=False)
    if build.returncode == 0:
        ios_sim.write_driver_hash(derived, current)
    return build.returncode


class SimLock:
    """Hold ``~/.fst-sim.lock`` and boot one FST simulator exclusively.

    Args:
        udid: Simulator to boot.
    """

    def __init__(self, udid: str):
        self.udid = udid
        self.handle = None

    def __enter__(self) -> "SimLock":
        ios_sim.LOCK_PATH.touch(exist_ok=True)
        self.handle = open(ios_sim.LOCK_PATH, "w")
        print(f"waiting for simulator lock {ios_sim.LOCK_PATH} ...", file=sys.stderr)
        fcntl.flock(self.handle, fcntl.LOCK_EX)
        self.handle.write(f"{os.getpid()} {ios_sim.REPO_ROOT} pwa\n")
        self.handle.flush()
        ios_sim.boot_exclusive(self.udid)
        ios_sim._run(["xcrun", "simctl", "bootstatus", self.udid, "-b"], capture_output=True)
        return self

    def __exit__(self, *exc) -> None:
        if self.handle:
            fcntl.flock(self.handle, fcntl.LOCK_UN)
            self.handle.close()


def form_factor(udid: str) -> str:
    """Classify a simulator as ``pad`` or ``phone`` from its device type.

    Args:
        udid: Simulator UDID.

    Returns:
        ``pad`` for iPad device types, else ``phone``.
    """
    listing = subprocess.run(["xcrun", "simctl", "list", "devices", "-j"], capture_output=True,
                             text=True, env=ios_sim._env(), check=False)
    for devices in json.loads(listing.stdout or "{}").get("devices", {}).values():
        for device in devices:
            if device.get("udid") == udid:
                return "pad" if "iPad" in device.get("deviceTypeIdentifier", "") else "phone"
    return "phone"


def run_pwa_steps(udid: str, steps: list[str], *, record: str | None = None, display: str | None = None,
                  pose: str | None = None, target: str = "safari", timeout: float = 240.0) -> int:
    """Run a PWA step script under one bounded simulator-lock hold.

    Args:
        udid: Simulator UDID.
        steps: Parsed ``PWADriverTests`` steps.
        record: Optional ``.mp4`` to record the run into (marks go to ``<mp4>.marks.txt``).
        display: iPhone Duo panel to record (``outer``/``inner``).
        pose: Required Duo pose (verified, never set: setting needs Accessibility).
        target: Initial target app alias or bundle identifier.
        timeout: Seconds before the run is killed (keeps the lock hold under 5 minutes).

    Returns:
        ``xcodebuild``'s exit code (124 on timeout, 3 on a pose mismatch).
    """
    derived = ios_sim.driver_derived_data()
    for step in steps:
        verb, _, arg = step.partition(":")
        if verb in ("shot", "tree") and arg:
            Path(arg).parent.mkdir(parents=True, exist_ok=True)
    steps_path = Path(tempfile.gettempdir()) / f"fst-pwa-steps-{uuid.uuid4().hex}.txt"
    steps_path.write_text("\n".join(steps) + "\n", encoding="utf-8")
    env = ios_sim._env()
    env["TEST_RUNNER_FST_PWA_STEPS_FILE"] = str(steps_path)
    env["TEST_RUNNER_FST_PWA_TARGET"] = target
    marks = None
    if record:
        Path(record).parent.mkdir(parents=True, exist_ok=True)
        marks = Path(record + ".marks.txt")
        marks.unlink(missing_ok=True)
        env["TEST_RUNNER_FST_PWA_MARKS_FILE"] = str(marks)
    log_path = Path(tempfile.gettempdir()) / f"fst-pwa-log-{uuid.uuid4().hex}.txt"
    result_bundle = derived / "Results" / f"pwa-{uuid.uuid4().hex}.xcresult"
    result_bundle.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", "FestivalMobile",
        "-destination", f"platform=iOS Simulator,id={udid}", "-derivedDataPath", str(derived),
        "-resultBundlePath", str(result_bundle), f"-only-testing:{PWA_TEST}",
        "test-without-building", "-quiet",
    ]
    start = time.time()
    try:
        with SimLock(udid):
            if problem := ios_sim.require_pose(udid, pose):
                print(problem, file=sys.stderr)
                return ios_sim.EXIT_POSE_MISMATCH
            with open(log_path, "w") as log, ios_sim.ScreenRecording(udid, record, display):
                if marks:
                    marks.write_text(f"{time.time():.3f} recording-start\n", encoding="utf-8")
                try:
                    code = subprocess.run(cmd, cwd=ios_sim.APPLE_DIR, env=env, stdout=log,
                                          stderr=subprocess.STDOUT, check=False, timeout=timeout).returncode
                except subprocess.TimeoutExpired:
                    code = 124
                    log.write(f"\nTIMEOUT after {timeout}s; killed.\n")
    finally:
        steps_path.unlink(missing_ok=True)
    elapsed = time.time() - start
    if code:
        text = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
        print(f"pwa drive FAILED ({code}) after {elapsed:.1f}s; log {log_path}:", file=sys.stderr)
        print("\n".join(line for line in text[-40:]), file=sys.stderr)
        print("failure captures: /tmp/fst-pwa-failure-<step>.{png,tree.txt}", file=sys.stderr)
        return code
    print(f"pwa drive OK in {elapsed:.1f}s ({len(steps)} step(s))", file=sys.stderr)
    log_path.unlink(missing_ok=True)
    shutil.rmtree(result_bundle, ignore_errors=True)
    for step in steps:
        verb, _, arg = step.partition(":")
        if verb in ("shot", "tree") and arg:
            print(f"{'ok' if Path(arg).exists() else 'MISSING'}: {arg}")
    return 0

# endregion

# region Commands


def cmd_open(args: argparse.Namespace) -> int:
    """Open a URL in Mobile Safari on the chosen simulator (no XCUITest needed).

    Args:
        args: ``device``, ``url``, optional ``out`` screenshot after ``wait`` seconds.

    Returns:
        Exit code.
    """
    udid = ios_sim.resolve_device(args.device)
    with SimLock(udid):
        ios_sim._run(["xcrun", "simctl", "openurl", udid, args.url])
        if args.out:
            time.sleep(args.wait)
            Path(args.out).parent.mkdir(parents=True, exist_ok=True)
            ios_sim._run(["xcrun", "simctl", "io", udid, "screenshot", args.out], capture_output=True)
            print(args.out)
    return 0


def cmd_shot(args: argparse.Namespace) -> int:
    """Screenshot whatever is on screen now (e.g. after ``drive``), under the lock.

    Args:
        args: ``device``, ``out``, ``display``.

    Returns:
        Exit code.
    """
    udid = ios_sim.resolve_device(args.device)
    selector = [f"--display={ios_sim.DUO_PANELS[args.display]}"] if args.display else []
    with SimLock(udid):
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        ios_sim._run(["xcrun", "simctl", "io", udid, "screenshot", *selector, args.out], capture_output=True)
    print(args.out)
    return 0


def _steps(args: argparse.Namespace) -> list[str]:
    """Combine ``--steps-file`` and ``--steps`` like ``ios_sim.py drive``."""
    return ios_sim.parse_steps(args.steps, args.steps_file)


def cmd_drive(args: argparse.Namespace) -> int:
    """Run a PWA step script (Safari / SpringBoard / standalone web app).

    Args:
        args: Parsed CLI arguments.

    Returns:
        Exit code.
    """
    try:
        steps = _steps(args)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2
    if code := ensure_driver_build(args.rebuild):
        return code
    return run_pwa_steps(ios_sim.resolve_device(args.device), steps, record=args.record,
                         display=args.display, pose=args.pose, target=args.target, timeout=args.timeout)


def cmd_install(args: argparse.Namespace) -> int:
    """Add the PWA to the Home Screen through Safari's Share sheet (idempotent).

    Args:
        args: ``device``, ``url``, ``label``, ``record``, ``pose``, ``display``.

    Returns:
        Exit code.
    """
    if code := ensure_driver_build(args.rebuild):
        return code
    udid = ios_sim.resolve_device(args.device)
    kind = form_factor(udid)
    rename = f"clearType:{args.label}" if args.label != PWA_ICON_LABEL else "wait:0.1"
    steps = [step.format(url=args.url, label=args.label, rename=rename) for step in INSTALL_STEPS[kind]]
    if args.debug_dir:
        steps = [s for pair in ((f"tree:{args.debug_dir}/install-{i:02d}.tree.txt", s)
                                for i, s in enumerate(steps)) for s in pair]
    steps += ["target:springboard", "home", "wait:2", f"waitFor:{args.label}"]
    return run_pwa_steps(udid, steps, record=args.record, display=args.display, pose=args.pose)


def cmd_frames(args: argparse.Namespace) -> int:
    """Extract frames from a recording at a fixed rate (frame-stepping aid).

    Args:
        args: ``video``, ``out``, ``fps``, ``start``, ``end``, ``scale``.

    Returns:
        Exit code.
    """
    Path(args.out).mkdir(parents=True, exist_ok=True)
    return subprocess.run(["xcrun", "swift", str(FRAMES_SWIFT), args.video, args.out, str(args.fps),
                           str(args.start), str(args.end if args.end is not None else -1), str(args.scale)],
                          env=ios_sim._env(), check=False).returncode


def frame_difference(first: Path, second: Path) -> float:
    """Mean absolute per-channel difference between two frames, 0-255.

    Args:
        first: Earlier frame.
        second: Later frame.

    Returns:
        Mean absolute difference over all RGB samples.
    """
    from PIL import Image, ImageChops, ImageStat
    a = Image.open(first).convert("RGB")
    b = Image.open(second).convert("RGB").resize(a.size)
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3


def motion_segments(diffs: list[float], fps: float, threshold: float, gap: int = 2) -> list[tuple[float, float, float]]:
    """Group consecutive above-threshold frame differences into motion segments.

    Args:
        diffs: Difference between frame ``i`` and ``i+1``.
        fps: Sampling rate the frames were extracted at.
        threshold: Minimum difference that counts as motion.
        gap: Quiet frames allowed inside one segment.

    Returns:
        ``(start_seconds, end_seconds, peak_difference)`` per segment.
    """
    segments, start, quiet, peak = [], None, 0, 0.0
    for index, value in enumerate(diffs):
        if value >= threshold:
            if start is None:
                start, peak = index, 0.0
            quiet, peak = 0, max(peak, value)
        elif start is not None:
            quiet += 1
            if quiet > gap:
                segments.append((start / fps, (index - quiet + 1) / fps, peak))
                start, quiet = None, 0
    if start is not None:
        segments.append((start / fps, (len(diffs) - quiet) / fps, peak))
    return segments


#: Seconds between the ``recording-start`` stamp and the video's first frame.
#: Calibrated 2026-09-28 by frame-stepping a SpringBoard launch (±0.5 s): the stamp
#: is written after ``ScreenRecording`` returns, but ``recordVideo`` emits its first
#: frame about a second later still.
MARK_ORIGIN_OFFSET = 1.0


def load_marks(video: str) -> list[tuple[float, str]]:
    """Read ``<video>.marks.txt`` as video-relative ``(seconds, label)`` pairs.

    Args:
        video: Recording path.

    Returns:
        Marks after ``recording-start``, in order; empty when there is no marks file.
    """
    path = Path(video + ".marks.txt")
    if not path.exists():
        return []
    rows = [line.split(" ", 1) for line in path.read_text(encoding="utf-8").splitlines() if " " in line]
    if not rows:
        return []
    origin = float(rows[0][0]) + MARK_ORIGIN_OFFSET
    return [(max(0.0, float(stamp) - origin), label) for stamp, label in rows[1:]]


def clip_plan(marks: list[tuple[float, str]], duration: float, pre: float, post: float
              ) -> list[tuple[str, float, float]]:
    """Turn ``clip:<name>`` / ``end`` marks into ``(name, start, length)`` cuts.

    A clip runs from its ``clip:<name>`` mark (minus ``pre``) to the next ``clip:`` or
    ``end`` mark (plus ``post``), or to the end of the video.

    Args:
        marks: ``load_marks`` output.
        duration: Video length in seconds.
        pre: Seconds kept before the start mark.
        post: Seconds kept after the end mark.

    Returns:
        One entry per ``clip:`` mark.
    """
    plan = []
    for index, (start, label) in enumerate(marks):
        if not label.startswith("clip:"):
            continue
        stop = next((t for t, other in marks[index + 1:] if other.startswith("clip:") or other == "end"),
                    duration)
        begin = max(0.0, start - pre)
        end = min(duration, stop + post)
        plan.append((label[5:], begin, max(0.5, end - begin)))
    return plan


def video_duration(video: str) -> float:
    """Return a movie's duration in seconds via ``mdls``/AVFoundation-free probing.

    Args:
        video: Movie path.

    Returns:
        Duration in seconds (0 when unknown).
    """
    probe = subprocess.run(["mdls", "-raw", "-name", "kMDItemDurationSeconds", video],
                           capture_output=True, text=True, check=False)
    try:
        return float(probe.stdout.strip())
    except ValueError:
        return 0.0


def compress(video: str, out: str, preset: str = "PresetMediumQuality", start: float | None = None,
             length: float | None = None) -> int:
    """``avconvert`` a (trimmed) recording and report its size.

    Args:
        video: Source movie.
        out: Destination ``.mp4``.
        preset: avconvert preset.
        start: Seconds to skip.
        length: Seconds to keep.

    Returns:
        avconvert's exit code.
    """
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    cmd = ["avconvert", "--source", video, "--output", out, "--preset", preset, "--replace"]
    if start is not None:
        cmd += ["--start", f"{start:.2f}"]
    if length is not None:
        cmd += ["--duration", f"{length:.2f}"]
    result = subprocess.run(cmd, check=False, stdout=subprocess.DEVNULL)
    if result.returncode == 0:
        size = Path(out).stat().st_size / 1_000_000
        print(f"{out}: {size:.2f} MB{'  (over 2 MB)' if size > 2 else ''}")
    return result.returncode


def cmd_motion(args: argparse.Namespace) -> int:
    """Report when the screen moves in a recording: transition start/end/duration.

    Frames are extracted at ``--fps`` (default 30) and diffed pairwise; runs of
    change above ``--threshold`` are printed with their duration so transition
    lengths can be read without an editor. Marks from ``<video>.marks.txt`` (the
    driver's ``mark:`` steps) are printed on the same timeline, offset by the
    recording start (approximate: ``recordVideo`` starts ~1 s after launch).

    Args:
        args: ``video``, ``fps``, ``threshold``, ``start``, ``end``, ``json``.

    Returns:
        Exit code.
    """
    with tempfile.TemporaryDirectory() as folder:
        code = subprocess.run(["xcrun", "swift", str(FRAMES_SWIFT), args.video, folder, str(args.fps),
                               str(args.start), str(args.end if args.end is not None else -1), "0.25"],
                              env=ios_sim._env(), check=False, stdout=subprocess.DEVNULL).returncode
        if code:
            return code
        frames = sorted(Path(folder).glob("*.png"))
        diffs = [frame_difference(a, b) for a, b in zip(frames, frames[1:])]
    segments = motion_segments(diffs, args.fps, args.threshold)
    marks = load_marks(args.video)
    if args.json:
        print(json.dumps({"segments": [{"start": round(args.start + s, 3), "end": round(args.start + e, 3),
                                         "duration": round(e - s, 3), "peak": round(p, 2)}
                                        for s, e, p in segments],
                          "marks": [{"t": round(t, 2), "label": label} for t, label in marks]}, indent=1))
        return 0
    events = [(args.start + s, f"motion {args.start + s:7.2f}-{args.start + e:7.2f}s  "
                               f"{(e - s) * 1000:6.0f} ms  peak {p:5.1f}") for s, e, p in segments]
    events += [(t, f"mark   {t:7.2f}s  {label}") for t, label in marks]
    for _, line in sorted(events):
        print(line)
    return 0


def cmd_compress(args: argparse.Namespace) -> int:
    """Re-encode a recording for phone viewing (``avconvert`` medium quality).

    Args:
        args: ``video``, ``out``, ``preset``.

    Returns:
        Exit code.
    """
    return compress(args.video, args.out, args.preset, args.start, args.duration)


def cmd_cut(args: argparse.Namespace) -> int:
    """Cut a recorded run into per-state clips at its ``clip:<name>`` marks.

    Args:
        args: ``video``, ``out_dir``, ``pre``, ``post``, ``preset``.

    Returns:
        0 when every clip converted, else the last failing exit code.
    """
    plan = clip_plan(load_marks(args.video), video_duration(args.video), args.pre, args.post)
    if not plan:
        print(f"no clip: marks in {args.video}.marks.txt", file=sys.stderr)
        return 1
    status = 0
    for name, start, length in plan:
        status = compress(args.video, str(Path(args.out_dir) / f"{name}.mp4"), args.preset, start, length) or status
    return status


_MAC_ADD_TO_DOCK = r"""
on run argv
  set theURL to item 1 of argv
  tell application "Safari"
    activate
    open location theURL
  end tell
  delay 6
  tell application "System Events" to tell process "Safari"
    click menu item "Add to Dock…" of menu "File" of menu bar 1
    delay 2
    keystroke return
  end tell
end run
"""


def cmd_mac_install(args: argparse.Namespace) -> int:
    """macOS: open the PWA in Safari and use File > Add to Dock (UI scripting).

    Needs the Accessibility and Automation (System Events) permissions for the
    responsible app; without them this prints the manual steps and exits 4. It
    never changes privacy settings.

    Args:
        args: ``url``.

    Returns:
        Exit code.
    """
    if not ios_sim.accessibility_trusted():
        print(ios_sim.accessibility_instructions(ios_sim.responsible_process()), file=sys.stderr)
        print("Manual alternative: Safari > open the URL > File > Add to Dock… > Add; the web app "
              "lands in ~/Applications and opens standalone from the Dock.", file=sys.stderr)
        return ios_sim.EXIT_NO_ACCESSIBILITY
    return subprocess.run(["osascript", "-e", _MAC_ADD_TO_DOCK, args.url], check=False).returncode


def cmd_mac_record(args: argparse.Namespace) -> int:
    """macOS: record the screen (or a region) for ``seconds`` with ``screencapture -v``.

    Needs the Screen Recording permission for the responsible app; without it
    ``screencapture`` fails with "could not create image from display".

    Args:
        args: ``out``, ``seconds``, ``region`` (``x,y,w,h``).

    Returns:
        Exit code.
    """
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    cmd = ["screencapture", "-v", "-V", str(args.seconds), "-x"]
    if args.region:
        cmd += ["-R", args.region]
    return subprocess.run(cmd + [args.out], check=False).returncode

# endregion


# region Fixture origin

#: Sibling web source (read-only; this tool only runs its Vite dev server).
WEB_DIR = Path.home() / "repos" / "FortniteFestivalLeaderboardScraper" / "FortniteFestivalWeb"
#: Loopback ports: mock service, header-stripping proxy, Vite dev server.
FIXTURE_PORTS = {"mock": 18775, "proxy": 18776, "web": 14175}
#: Request headers the proxy drops before a request reaches the mock service. The
#: web client adds selected-profile headers to every GET once a profile is selected;
#: the mock rejects them (400) to catch native clients, so the reference origin strips them.
STRIPPED_HEADERS = ("x-fst-selected-", "x-api-key")


#: Reads the web gates on that ``tools/mock_service.py`` does not serve, answered by
#: the proxy with the web repo's own e2e defaults (``e2e/fixtures/scenarios.ts``
#: ``createServiceInfo``): without ``/api/service-info`` the PWA shows its
#: maintenance screen.
_FIXTURE_NOW = "2026-01-01T12:00:00.000Z"
SYNTHETIC_READS: dict[str, dict] = {
    "/api/service-info": {
        "lastCompletedUpdate": {"scrapeId": 1, "startedAt": _FIXTURE_NOW, "completedAt": _FIXTURE_NOW,
                                "publishedAt": _FIXTURE_NOW},
        "currentUpdate": {"status": "idle", "startedAt": None, "phase": None, "subOperation": None},
        "activeScrapeId": None, "publishedScrapeId": 1,
        "publication": {"publishedScrapeId": 1, "publishedAt": _FIXTURE_NOW, "publicReadsFrozen": False,
                        "frozenAt": None, "frozenScrapeId": None, "freezeReason": None},
        "workerStatus": {"workerKey": "fixture-worker", "status": "online", "rawStatus": "idle"},
        "nextScheduledUpdateAt": "2026-01-02T12:00:00.000Z",
    },
    "/api/version": {"version": "fixture"},
}


def proxy_headers(headers: list[tuple[str, str]]) -> dict[str, str]:
    """Filter request headers for the fixture proxy.

    Args:
        headers: Incoming ``(name, value)`` pairs.

    Returns:
        Headers to forward: no selected-profile/API-key headers, no hop-by-hop ``Host``.
    """
    return {name: value for name, value in headers
            if not name.lower().startswith(STRIPPED_HEADERS) and name.lower() not in ("host", "connection")}


def serve_fixture_proxy(port: int, upstream: int):
    """Start a loopback GET-only proxy in a daemon thread.

    POSTs (profile tracking, name refresh) are answered 405 locally and never forwarded.

    Args:
        port: Listen port on 127.0.0.1.
        upstream: Mock service port.

    Returns:
        The running ``ThreadingHTTPServer``.
    """
    import threading
    import urllib.error
    import urllib.request
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 (http.server API)
            synthetic = SYNTHETIC_READS.get(self.path.split("?", 1)[0])
            if synthetic is not None:
                body = json.dumps(synthetic).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            request = urllib.request.Request(f"http://127.0.0.1:{upstream}{self.path}",
                                             headers=proxy_headers(list(self.headers.items())))
            try:
                with urllib.request.urlopen(request, timeout=20) as response:
                    status, body, headers = response.status, response.read(), response.getheaders()
            except urllib.error.HTTPError as error:
                status, body, headers = error.code, error.read(), error.headers.items()
            self.send_response(status)
            for name, value in headers:
                if name.lower() not in ("transfer-encoding", "connection", "content-length"):
                    self.send_header(name, value)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self) -> None:  # noqa: N802
            body = b'{"status":"fixture_origin_is_read_only"}'
            self.send_response(405)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args) -> None:
            pass

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def cmd_fixture_web(args: argparse.Namespace) -> int:
    """Serve the web source against loopback fixtures for selected-profile/search states.

    Starts ``tools/mock_service.py``, a GET-only header-stripping proxy, and the web
    repo's Vite dev server (``VITE_API_BASE`` = the proxy), then waits until
    interrupted. Open ``http://127.0.0.1:<web>/`` in the simulator (``open``/``install
    --url``); it reaches the host's loopback. Nothing here touches production.

    Args:
        args: ``web_dir``.

    Returns:
        Exit code.
    """
    import urllib.request
    ports = FIXTURE_PORTS
    server = serve_fixture_proxy(ports["proxy"], ports["mock"])
    mock = subprocess.Popen([sys.executable, str(ios_sim.REPO_ROOT / "tools" / "mock_service.py"),
                             "--port", str(ports["mock"])])
    env = dict(os.environ, VITE_API_BASE=f"http://127.0.0.1:{ports['proxy']}", VITE_API_KEY="")
    web = subprocess.Popen([str(Path(args.web_dir) / "node_modules/.bin/vite"), "--host", "127.0.0.1",
                            "--port", str(ports["web"]), "--strictPort"], cwd=args.web_dir, env=env)
    try:
        for _ in range(60):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{ports['web']}/", timeout=2)
                break
            except OSError:
                time.sleep(1)
        print(f"fixture web ready: http://127.0.0.1:{ports['web']}/  (api via :{ports['proxy']} -> mock :{ports['mock']})",
              flush=True)
        web.wait()
    except KeyboardInterrupt:
        pass
    finally:
        web.terminate()
        mock.terminate()
        server.shutdown()
    return 0

# endregion


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Optional argument list.

    Returns:
        Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    devices = f"alias {sorted(ios_sim.DEVICES)} or UDID"

    opener = sub.add_parser("open", help="open a URL in Mobile Safari")
    opener.add_argument("--device", default="iphone", help=devices)
    opener.add_argument("--url", default=PWA_URL)
    opener.add_argument("--out", help="screenshot after --wait seconds")
    opener.add_argument("--wait", type=float, default=6.0)
    opener.set_defaults(func=cmd_open)

    shot = sub.add_parser("shot", help="screenshot the current screen")
    shot.add_argument("--device", default="iphone", help=devices)
    shot.add_argument("--out", required=True)
    shot.add_argument("--display", choices=sorted(ios_sim.DUO_PANELS))
    shot.set_defaults(func=cmd_shot)

    for name, func, text in (("drive", cmd_drive, "run a PWA step script"),
                             ("install", cmd_install, "Safari Share > Add to Home Screen (idempotent)")):
        command = sub.add_parser(name, help=text)
        command.add_argument("--device", default="iphone", help=devices)
        command.add_argument("--record", help="record the run to this .mp4 (marks: <mp4>.marks.txt)")
        command.add_argument("--display", choices=sorted(ios_sim.DUO_PANELS), help="iPhone Duo panel to record")
        command.add_argument("--pose", choices=sorted(ios_sim.POSE_EXPECTED_CLASS),
                             help="iPhone Duo: require this pose (verified, not set)")
        command.add_argument("--rebuild", action="store_true")
        command.set_defaults(func=func)
        if name == "drive":
            command.add_argument("--steps", help="';'-separated PWADriverTests steps")
            command.add_argument("--steps-file")
            command.add_argument("--target", default="safari", help="initial target: safari|springboard|webapp|<bundle>")
            command.add_argument("--timeout", type=float, default=240.0)
        else:
            command.add_argument("--url", default=PWA_URL)
            command.add_argument("--label", default=PWA_ICON_LABEL, help="Home Screen icon label")
            command.add_argument("--debug-dir", help="dump the accessibility tree before every step")

    frames = sub.add_parser("frames", help="extract frames from a recording")
    frames.add_argument("video")
    frames.add_argument("--out", required=True)
    frames.add_argument("--fps", type=float, default=30.0)
    frames.add_argument("--start", type=float, default=0.0)
    frames.add_argument("--end", type=float)
    frames.add_argument("--scale", type=float, default=0.5)
    frames.set_defaults(func=cmd_frames)

    motion = sub.add_parser("motion", help="measure transitions (frame-difference segments)")
    motion.add_argument("video")
    motion.add_argument("--fps", type=float, default=30.0)
    motion.add_argument("--threshold", type=float, default=1.5, help="mean abs difference (0-255) counted as motion")
    motion.add_argument("--start", type=float, default=0.0)
    motion.add_argument("--end", type=float)
    motion.add_argument("--json", action="store_true")
    motion.set_defaults(func=cmd_motion)

    compress = sub.add_parser("compress", help="avconvert a recording for phone viewing")
    compress.add_argument("video")
    compress.add_argument("out")
    compress.add_argument("--preset", default="PresetMediumQuality")
    compress.add_argument("--start", type=float)
    compress.add_argument("--duration", type=float)
    compress.set_defaults(func=cmd_compress)

    cut = sub.add_parser("cut", help="split a recording into clips at its clip:<name> marks")
    cut.add_argument("video")
    cut.add_argument("--out-dir", required=True)
    cut.add_argument("--pre", type=float, default=0.5)
    cut.add_argument("--post", type=float, default=0.5)
    cut.add_argument("--preset", default="PresetMediumQuality")
    cut.set_defaults(func=cmd_cut)

    mac_install = sub.add_parser("mac-install", help="macOS Safari File > Add to Dock (UI scripting)")
    mac_install.add_argument("--url", default=PWA_URL)
    mac_install.set_defaults(func=cmd_mac_install)

    mac_record = sub.add_parser("mac-record", help="macOS screencapture -v recording")
    mac_record.add_argument("--out", required=True)
    mac_record.add_argument("--seconds", type=int, default=10)
    mac_record.add_argument("--region", help="x,y,w,h")
    mac_record.set_defaults(func=cmd_mac_record)

    fixture = sub.add_parser("fixture-web", help="serve the web source against loopback fixtures")
    fixture.add_argument("--web-dir", default=str(WEB_DIR))
    fixture.set_defaults(func=cmd_fixture_web)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
