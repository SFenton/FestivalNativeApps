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
    python3 tools/ios_sim.py shot --out /tmp/p.png --route player:e408c4613c8f4da5907090b390bda80c

    # Several screenshots in one lock hold, e.g. per tab.
    python3 tools/ios_sim.py shot --out /tmp/songs.png --out /tmp/songs2.png --wait 4

    # Script taps/swipes/screenshots (builds the UI-test bundle once, then
    # reuses it; still serialized under the same simulator lock).
    python3 tools/ios_sim.py drive --tab settings \
        --steps "tap:fst.shell.drawer.open; shot:/tmp/drawer.png; tree:/tmp/drawer.tree.txt"

Devices are named by alias (see ``DEVICES``) or UDID. The default is the
iPhone 17 Pro on iOS 26.5 (Liquid Glass).
"""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import os
import shutil
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
        args: Parsed CLI arguments (device, tab, route, env, wait, out, keep).

    Returns:
        Process exit code.
    """
    udid = resolve_device(args.device)
    app = app_path()
    LOCK_PATH.touch(exist_ok=True)
    with open(LOCK_PATH, "w") as lock:
        print(f"waiting for simulator lock {LOCK_PATH} ...", file=sys.stderr)
        fcntl.flock(lock, fcntl.LOCK_EX)
        lock.write(f"{os.getpid()} {REPO_ROOT}\n")
        lock.flush()
        _run(["xcrun", "simctl", "boot", udid], check=False, capture_output=True)
        _run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)
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
        _run(["xcrun", "simctl", "launch", udid, BUNDLE_ID], env=launch_env)
        for index, out in enumerate(args.out):
            time.sleep(args.wait if index == 0 else args.interval)
            Path(out).parent.mkdir(parents=True, exist_ok=True)
            _run(["xcrun", "simctl", "io", udid, "screenshot", out], capture_output=True)
            print(out)
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
            _run(["xcrun", "simctl", "boot", udid], check=False, capture_output=True)
            _run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)
            cmd = [
                "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", "FestivalMobile",
                "-destination", f"platform=iOS Simulator,id={udid}",
                "-derivedDataPath", str(derived), "-resultBundlePath", str(result_bundle),
                "-only-testing:FestivalMobileUITests/DriverTests/testDrive",
                "test-without-building", "-quiet",
            ]
            print("+", " ".join(cmd), file=sys.stderr)
            with open(log_path, "w") as log:
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
    shot.set_defaults(func=cmd_shot)

    drive = sub.add_parser(
        "drive", help="script taps/swipes/scrolls/screenshots (serialized, builds once)"
    )
    drive.add_argument("--device", default="iphone", help=f"alias {sorted(DEVICES)} or UDID")
    drive.add_argument("--tab", help="FST_DEBUG_TAB, applied at app launch")
    drive.add_argument("--animate", action="store_true",
                       help="keep the album carousel animating (default freezes it so steps don't wait for idle)")
    drive.add_argument("--timeout", type=float, default=180.0,
                       help="kill the run after this many seconds (default 180) so the sim lock is released")
    drive.add_argument("--route", help="FST_DEBUG_ROUTE, applied at app launch")
    drive.add_argument("--env", action="append", help="extra KEY=VALUE app launch environment")
    drive.add_argument("--steps", help="';'-separated step script, e.g. 'tap:x; shot:/tmp/a.png'")
    drive.add_argument("--steps-file", help="path to a newline-separated step script")
    drive.add_argument(
        "--rebuild", action="store_true", help="force a fresh build-for-testing"
    )
    drive.set_defaults(func=cmd_drive)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
