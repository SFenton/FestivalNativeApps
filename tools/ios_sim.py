#!/usr/bin/env python3
"""Serialized iOS simulator access for parallel agent lanes.

Many lanes build in parallel (each in its own git worktree and DerivedData),
but only ONE product simulator may run at a time on this Mac. Every simulator
interaction goes through this tool, which holds an exclusive ``flock`` on
``~/.fst-sim.lock`` for the whole install/launch/screenshot sequence.

Examples::

    # Build the iOS app from the current worktree (no lock needed).
    python3 tools/ios_sim.py build

    # Install, launch on a debug route, and screenshot (takes the lock).
    python3 tools/ios_sim.py shot --out /tmp/lb.png --tab leaderboards
    python3 tools/ios_sim.py shot --out /tmp/p.png --route player:e408c4613c8f4da5907090b390bda80c

    # Several screenshots in one lock hold, e.g. per tab.
    python3 tools/ios_sim.py shot --out /tmp/songs.png --out /tmp/songs2.png --wait 4

Devices are named by alias (see ``DEVICES``) or UDID. The default is the
iPhone 17 Pro on iOS 26.5 (Liquid Glass).
"""

from __future__ import annotations

import argparse
import fcntl
import os
import subprocess
import sys
import time
from pathlib import Path

# region Configuration

DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer"
BUNDLE_ID = "com.sfenton.festivalscoretracker.native"
LOCK_PATH = Path.home() / ".fst-sim.lock"
REPO_ROOT = Path(__file__).resolve().parent.parent
APPLE_DIR = REPO_ROOT / "apple"

#: Alias -> simulator UDID. Keep in sync with `.agents/platforms/apple/simulators.md`.
DEVICES = {
    "iphone": "4E9F2A49-127D-40BC-A909-08AF3D4BE6A5",  # FST iOS 26.5 iPhone 17 Pro
    "iphone27": "32DF9891-BCDB-46FB-9317-35EC1239267E",  # FST iOS 27 Fresh iPhone 17 Pro
    "ipad": "11E2F7B2-DE32-4466-8A97-04B37F559086",  # FST Native iPad Pro 11 (26.5)
    "duo": "BC8A530D-805F-45FD-9D32-71B838C7A05F",  # iPhone Duo (FST), iOS 27.1
}

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

# region Commands


def cmd_build(args: argparse.Namespace) -> int:
    """Generate the Xcode project and build the iOS app (no simulator lock).

    Args:
        args: Parsed CLI arguments (``configuration``).

    Returns:
        Process exit code.
    """
    _run(["xcodegen", "generate", "-q"], cwd=APPLE_DIR)
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

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
