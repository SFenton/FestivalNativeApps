#!/usr/bin/env python3
"""Run one command while holding the shared ``desktop`` host lock.

``tools/windows/*.ps1`` route every desktop-session hop (launch, screenshot, window
lookup) through this wrapper so they queue with ``tools/windows/uiwin.py`` and other
lanes on the FIFO lock from :mod:`tools.android.hostlock`. The hold is bounded
(≤300 s); the child is tracked so the watchdog can kill it on overrun.

Usage::

    python tools/windows/desktop_lock.py --purpose "screenshot" -- pwsh -File step.ps1
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.android.hostlock import HostLock, LockTimeout  # noqa: E402  (shared host lock)

def ci_desktop() -> bool:
    """Return whether this process owns an isolated GitHub Actions desktop."""
    return os.environ.get("FST_CI") == "1"

def main(argv: list[str] | None = None) -> int:
    """Acquire the desktop lock, run the command, release.

    Args:
        argv: Arguments after the program name; the command follows ``--``.

    Returns:
        The command's exit code, or 75 if the lock could not be acquired in time.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--purpose", default="tools/windows")
    parser.add_argument("--hold", type=float, default=300.0, help="hard hold limit in seconds (max 300)")
    parser.add_argument("--wait", type=float, default=900.0, help="queue timeout in seconds")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("missing command after --")
    if ci_desktop():
        return subprocess.run(command).returncode
    try:
        with HostLock("desktop", purpose=f"{args.purpose} [{Path.cwd().name}]",
                      hold_seconds=args.hold, wait_seconds=args.wait) as lock:
            process = lock.track(subprocess.Popen(command))
            return process.wait(timeout=lock.remaining())
    except LockTimeout as error:
        print(f"desktop lock: {error}", file=sys.stderr)
        return 75


if __name__ == "__main__":
    sys.exit(main())
