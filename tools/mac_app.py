#!/usr/bin/env python3
"""Build, launch, capture and quit the native Festival macOS app (Debug).

The Mac app cannot be driven by XCUITest on this host (Automation Mode needs
operator authentication; never bypass it), so evidence comes from Debug launch
overrides plus captures of **only the app's own window**:

- ``build``   xcodegen + ``xcodebuild -scheme FestivalDesktop`` into
  ``apple/DerivedData/mac`` (serialized on ``~/.fst-build.lock`` like
  ``ios_sim.py build``).
- ``launch``  starts the built app directly with ``-ApplePersistenceIgnoreState
  YES`` (no window restoration, so no "reopen windows" prompt), Debug deep-link
  environment (``FST_DEBUG_TAB``/``FST_DEBUG_ROUTE``/``FST_DEBUG_PROFILE``) and an
  optional content size (``FST_DEBUG_WINDOW_SIZE``). One instance per host: a
  previous instance recorded in ``~/.fst-mac-app.pid`` is quit first.
- ``resize``  changes the running window's content size (Debug distributed
  notification; no Accessibility permission needed).
- ``shot``    ``screencapture -l <CGWindowID>`` of the app's main window, found
  with ``tools/mac_window.swift`` (``CGWindowListCopyWindowInfo`` filtered to the
  app's PID). It **never** captures the full screen: without a window ID it fails.
- ``command`` runs a Debug shell command in the running app (``select:3``,
  ``select:leaderboards``, ``route:player:<id>``, ``back``, ``refresh``, ``search``,
  ``profile``, ``notifications``, ``whatsnew``, ``sort``, ``filter``), so one launch can
  visit many pages and sheets without Accessibility permission.
- ``quit``    posts the Debug quit notification so AppKit terminates normally;
  falls back to SIGTERM.

Examples::

    python3 tools/mac_app.py build
    python3 tools/mac_app.py launch --tab leaderboards --profile sfentonx --size 1280x800
    python3 tools/mac_app.py shot --out ~/FestivalShowcase/native-mac/leaderboards.png
    python3 tools/mac_app.py resize --size 760x600
    python3 tools/mac_app.py command route:fullRankings:Solo_Guitar
    python3 tools/mac_app.py quit
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

# region Configuration

DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer"
REPO_ROOT = Path(__file__).resolve().parent.parent
APPLE_DIR = REPO_ROOT / "apple"
BUILD_LOCK_PATH = Path.home() / ".fst-build.lock"
PID_PATH = Path.home() / ".fst-mac-app.pid"
HELPER_SOURCE = REPO_ROOT / "tools" / "mac_window.swift"

#: Named profiles for ``--profile``. SFentonX is the operator's own account and the
#: only identity used for operator-facing live media (`.agents/testing/strategy.md`).
PROFILES = {"sfentonx": "195e93ef108143b2975ee46662d4d0e1:SFentonX"}

#: Debug shell commands without an argument (`MacDebugCommand`).
SIMPLE_COMMANDS = {"back", "refresh", "search", "profile", "notifications", "whatsnew", "sort", "filter", "dismiss"}
#: Debug shell commands that take ``verb:argument``.
ARGUMENT_COMMANDS = {"select", "route"}

#: Smallest content size a capture accepts as the main window (filters menus/tooltips).
MIN_WINDOW_SIDE = 200

# endregion

# region Pure helpers


def derived_data() -> Path:
    """Per-worktree DerivedData for the Mac app.

    Returns:
        ``apple/DerivedData/mac`` inside this worktree.
    """
    return APPLE_DIR / "DerivedData" / "mac"


def app_bundle(configuration: str = "Debug") -> Path:
    """Path of the built app bundle.

    Args:
        configuration: Xcode build configuration.

    Returns:
        ``FestivalDesktop.app`` under this worktree's DerivedData.
    """
    return derived_data() / "Build" / "Products" / configuration / "FestivalDesktop.app"


def helper_binary() -> Path:
    """Where the compiled window helper is cached.

    Returns:
        ``apple/DerivedData/mac-tool/mac_window``.
    """
    return APPLE_DIR / "DerivedData" / "mac-tool" / "mac_window"


def parse_size(raw: str) -> tuple[int, int]:
    """Parse a ``WIDTHxHEIGHT`` window content size in points.

    Args:
        raw: Text such as ``1280x800``.

    Returns:
        ``(width, height)``.

    Raises:
        ValueError: Malformed text or a side outside 320…8000 points.
    """
    parts = raw.lower().replace("×", "x").split("x")
    if len(parts) != 2:
        raise ValueError(f"size must be WIDTHxHEIGHT, got {raw!r}")
    width, height = (int(part.strip()) for part in parts)
    for side in (width, height):
        if not 320 <= side <= 8000:
            raise ValueError(f"size {raw!r} outside 320…8000 points")
    return width, height


def resolve_profile(raw: str | None) -> str | None:
    """Map ``--profile`` to an ``FST_DEBUG_PROFILE`` value.

    Args:
        raw: A ``PROFILES`` alias (case-insensitive) or ``accountId:displayName``.

    Returns:
        The environment value, or None when no profile was requested.

    Raises:
        ValueError: Neither a known alias nor ``id:name``.
    """
    if raw is None:
        return None
    if raw.lower() in PROFILES:
        return PROFILES[raw.lower()]
    account, sep, name = raw.partition(":")
    if not sep or not account or not name:
        raise ValueError(f"profile must be one of {sorted(PROFILES)} or accountId:displayName")
    return raw


def launch_environment(
    base: dict[str, str],
    *,
    tab: str | None = None,
    route: str | None = None,
    profile: str | None = None,
    anonymous: bool = False,
    size: tuple[int, int] | None = None,
    extra: list[str] | None = None,
) -> dict[str, str]:
    """Build the app's launch environment.

    Args:
        base: Starting environment (usually ``os.environ``).
        tab: ``FST_DEBUG_TAB`` section raw value.
        route: ``FST_DEBUG_ROUTE`` deep link.
        profile: Resolved ``FST_DEBUG_PROFILE`` value.
        anonymous: Ignore any stored profile for this launch.
        size: Window content size.
        extra: ``KEY=VALUE`` pairs added last.

    Returns:
        A new environment dictionary; ``base`` is not modified.

    Raises:
        ValueError: An ``extra`` entry without ``=``.
    """
    env = dict(base)
    # Never inherit another launch's deep link from the caller's shell.
    for key in ("FST_DEBUG_TAB", "FST_DEBUG_ROUTE", "FST_DEBUG_PROFILE", "FST_DEBUG_ANONYMOUS",
                "FST_DEBUG_WINDOW_SIZE"):
        env.pop(key, None)
    if tab:
        env["FST_DEBUG_TAB"] = tab
    if route:
        env["FST_DEBUG_ROUTE"] = route
    if profile:
        env["FST_DEBUG_PROFILE"] = profile
    if anonymous:
        env["FST_DEBUG_ANONYMOUS"] = "1"
    if size:
        env["FST_DEBUG_WINDOW_SIZE"] = f"{size[0]}x{size[1]}"
    for pair in extra or []:
        key, sep, value = pair.partition("=")
        if not sep or not key:
            raise ValueError(f"--env expects KEY=VALUE, got {pair!r}")
        env[key] = value
    return env


def launch_argv(bundle: Path) -> list[str]:
    """Argument vector that starts the app without window restoration.

    Args:
        bundle: The ``.app`` bundle.

    Returns:
        Executable path plus ``-ApplePersistenceIgnoreState YES``.
    """
    return [str(bundle / "Contents" / "MacOS" / "FestivalDesktop"), "-ApplePersistenceIgnoreState", "YES"]


def parse_window_lines(text: str) -> list[dict]:
    """Decode the helper's JSON-lines window list, skipping junk lines.

    Args:
        text: ``mac_window list`` output.

    Returns:
        Window dictionaries in output order.
    """
    windows = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            windows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return windows


def pick_main_window(windows: list[dict]) -> dict | None:
    """Choose the app's main window: normal layer, large enough, largest area.

    Args:
        windows: Helper window dictionaries for one process.

    Returns:
        The chosen window or None (menus, tooltips and sheets' shadows excluded).
    """
    candidates = [
        w for w in windows
        if w.get("layer", 0) == 0 and w.get("w", 0) >= MIN_WINDOW_SIDE and w.get("h", 0) >= MIN_WINDOW_SIDE
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda w: w["w"] * w["h"])


def screencapture_argv(window_id: int, out: Path) -> list[str]:
    """``screencapture`` invocation for exactly one window.

    Args:
        window_id: CGWindowID of the app window.
        out: PNG destination.

    Returns:
        Silent (``-x``), shadowless (``-o``), window-only (``-l``) capture command.
    """
    if not isinstance(window_id, int) or window_id <= 0:
        raise ValueError("a positive CGWindowID is required; full-screen capture is never allowed")
    return ["screencapture", "-x", "-o", "-l", str(window_id), str(out)]


def helper_stale(source: Path, binary: Path) -> bool:
    """Whether the window helper needs recompiling.

    Args:
        source: ``mac_window.swift``.
        binary: Cached executable.

    Returns:
        True when the binary is missing or older than its source.
    """
    return not binary.exists() or binary.stat().st_mtime < source.stat().st_mtime


# endregion

# region Process helpers


def _env() -> dict[str, str]:
    env = dict(os.environ)
    env["DEVELOPER_DIR"] = DEVELOPER_DIR
    return env


def _run(cmd: list[str], check: bool = True, **kw) -> subprocess.CompletedProcess:
    print("+", " ".join(cmd), file=sys.stderr)
    return subprocess.run(cmd, check=check, env=kw.pop("env", _env()), **kw)


def ensure_helper() -> Path:
    """Compile ``mac_window.swift`` when stale.

    Returns:
        Path to the helper executable.
    """
    binary = helper_binary()
    if helper_stale(HELPER_SOURCE, binary):
        binary.parent.mkdir(parents=True, exist_ok=True)
        _run(["xcrun", "swiftc", "-O", str(HELPER_SOURCE), "-o", str(binary)])
    return binary


def running_pid() -> int | None:
    """PID of the instance this tool launched, if it is still alive.

    Returns:
        The PID or None.
    """
    try:
        pid = int(PID_PATH.read_text().split()[0])
    except (OSError, ValueError, IndexError):
        return None
    try:
        os.kill(pid, 0)
    except OSError:
        return None
    return pid


def main_window(pid: int) -> dict | None:
    """Look up the app's main window.

    Args:
        pid: App process.

    Returns:
        The window dictionary or None.
    """
    result = subprocess.run([str(ensure_helper()), "list", str(pid)], capture_output=True, text=True, check=False)
    return pick_main_window(parse_window_lines(result.stdout))


def wait_for_window(pid: int, timeout: float) -> dict | None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        window = main_window(pid)
        if window:
            return window
        time.sleep(0.25)
    return None


# endregion

# region Commands


def cmd_build(args: argparse.Namespace) -> int:
    _run(["xcodegen", "generate", "-q"], cwd=APPLE_DIR)
    BUILD_LOCK_PATH.touch(exist_ok=True)
    with open(BUILD_LOCK_PATH, "w") as lock:
        print(f"waiting for build lock {BUILD_LOCK_PATH} ...", file=sys.stderr)
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            result = _run([
                "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", "FestivalDesktop",
                "-configuration", args.configuration, "-destination", "platform=macOS",
                "-derivedDataPath", str(derived_data()), "build", "-quiet",
            ], cwd=APPLE_DIR, check=False)
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
    return result.returncode


def cmd_quit(args: argparse.Namespace) -> int:
    pid = running_pid()
    if pid is None:
        PID_PATH.unlink(missing_ok=True)
        return 0
    subprocess.run([str(ensure_helper()), "quit"], check=False)
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except OSError:
            break
        time.sleep(0.2)
    else:
        print(f"app {pid} ignored the quit notification; sending SIGTERM", file=sys.stderr)
        os.kill(pid, signal.SIGTERM)
    PID_PATH.unlink(missing_ok=True)
    return 0


def cmd_launch(args: argparse.Namespace) -> int:
    bundle = app_bundle(args.configuration)
    if not bundle.exists():
        print(f"No build at {bundle}; run `python3 tools/mac_app.py build` first.", file=sys.stderr)
        return 1
    cmd_quit(argparse.Namespace(timeout=5.0))
    env = launch_environment(
        _env(), tab=args.tab, route=args.route, profile=resolve_profile(args.profile),
        anonymous=args.anonymous, size=parse_size(args.size) if args.size else None, extra=args.env,
    )
    log_path = derived_data().parent / "mac-tool" / "app.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with open(log_path, "w") as log:
        process = subprocess.Popen(
            launch_argv(bundle), env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
        )
    PID_PATH.write_text(f"{process.pid} {REPO_ROOT}\n")
    window = wait_for_window(process.pid, args.timeout)
    if window is None:
        print(f"app {process.pid} showed no window within {args.timeout}s (log: {log_path})", file=sys.stderr)
        return 1
    print(json.dumps({"pid": process.pid, "window": window}))
    return 0


def cmd_resize(args: argparse.Namespace) -> int:
    pid = running_pid()
    if pid is None:
        print("app is not running; use `launch` first", file=sys.stderr)
        return 1
    width, height = parse_size(args.size)
    subprocess.run([str(ensure_helper()), "resize", str(width), str(height)], check=True)
    time.sleep(args.settle)
    print(json.dumps(main_window(pid)))
    return 0


def validate_command(raw: str) -> str:
    """Check a Debug shell command before sending it.

    Args:
        raw: Command text.

    Returns:
        The command, stripped.

    Raises:
        ValueError: Unknown verb or a missing argument.
    """
    command = raw.strip()
    verb, sep, arg = command.partition(":")
    if verb in SIMPLE_COMMANDS and not sep:
        return command
    if verb in ARGUMENT_COMMANDS and sep and arg:
        return command
    raise ValueError(f"unknown command {raw!r}; use {sorted(SIMPLE_COMMANDS)} or select:/route:")


def cmd_command(args: argparse.Namespace) -> int:
    pid = running_pid()
    if pid is None:
        print("app is not running; use `launch` first", file=sys.stderr)
        return 1
    subprocess.run([str(ensure_helper()), "command", validate_command(args.text)], check=True)
    time.sleep(args.settle)
    return 0


def cmd_shot(args: argparse.Namespace) -> int:
    pid = running_pid()
    if pid is None:
        print("app is not running; use `launch` first", file=sys.stderr)
        return 1
    for index, raw in enumerate(args.out):
        time.sleep(args.wait if index == 0 else args.interval)
        window = main_window(pid)
        if window is None:
            print("no app window found; refusing to capture anything else", file=sys.stderr)
            return 1
        out = Path(raw).expanduser()
        out.parent.mkdir(parents=True, exist_ok=True)
        _run(screencapture_argv(int(window["id"]), out))
        if not out.exists() or out.stat().st_size < 1024:
            print(f"capture {out} is missing or empty (Screen Recording permission?)", file=sys.stderr)
            return 1
        print(out)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    build = sub.add_parser("build", help="Build the Mac app")
    build.add_argument("--configuration", default="Debug")
    build.set_defaults(func=cmd_build)

    launch = sub.add_parser("launch", help="Quit any previous instance and launch the built app")
    launch.add_argument("--tab", help="FST_DEBUG_TAB section (songs, leaderboards, settings, …)")
    launch.add_argument("--route", help="FST_DEBUG_ROUTE deep link (shop, player:<id>, …)")
    launch.add_argument("--profile", help="'sfentonx' or accountId:displayName (in memory only)")
    launch.add_argument("--anonymous", action="store_true", help="Ignore any stored profile")
    launch.add_argument("--size", help="Window content size WIDTHxHEIGHT in points")
    launch.add_argument("--env", action="append", help="Extra KEY=VALUE launch environment")
    launch.add_argument("--configuration", default="Debug")
    launch.add_argument("--timeout", type=float, default=20.0)
    launch.set_defaults(func=cmd_launch)

    resize = sub.add_parser("resize", help="Resize the running window's content")
    resize.add_argument("--size", required=True)
    resize.add_argument("--settle", type=float, default=1.0)
    resize.set_defaults(func=cmd_resize)

    shot = sub.add_parser("shot", help="Capture only the app's window")
    shot.add_argument("--out", action="append", required=True)
    shot.add_argument("--wait", type=float, default=3.0, help="Seconds before the first capture")
    shot.add_argument("--interval", type=float, default=1.0, help="Seconds between captures")
    shot.set_defaults(func=cmd_shot)

    command = sub.add_parser("command", help="Run a Debug shell command in the running app")
    command.add_argument("text", help="e.g. select:2, route:shop, back, sort, search")
    command.add_argument("--settle", type=float, default=1.5)
    command.set_defaults(func=cmd_command)

    quit_ = sub.add_parser("quit", help="Quit the app normally")
    quit_.add_argument("--timeout", type=float, default=5.0)
    quit_.set_defaults(func=cmd_quit)

    args = parser.parse_args(argv)
    try:
        return args.func(args)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

# endregion
