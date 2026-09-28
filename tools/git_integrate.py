#!/usr/bin/env python3
"""Cross-platform lane integration: rebase onto origin/master, verify, push.

The Mac lanes use ``tools/lane_integrate.sh`` (Apple builds). Lanes on the
Windows host (Android/Windows apps) use this script with their own verification
commands, so both machines push straight to GitHub and stay in sync.

Usage (from inside a lane worktree, with everything committed)::

    python tools/git_integrate.py --verify "android\\gradlew.bat -p android testDebugUnitTest"
    python tools/git_integrate.py --verify "dotnet test windows\\Festival.sln -c Release"

Each ``--verify`` command runs from the repository root after every rebase; a
failing command aborts without pushing. A rejected push (another lane landed
first) fetches, rebases and re-verifies, up to five attempts.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

# region Helpers


def git(*args: str, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    """Run a git command in the current repository.

    Args:
        *args: git arguments.
        check: Raise on non-zero exit.
        capture: Capture output as text.

    Returns:
        The completed process.
    """
    return subprocess.run(["git", *args], check=check, text=True, capture_output=capture)


def repo_root() -> Path:
    """Locate the worktree root.

    Returns:
        Absolute path of the current git worktree.
    """
    return Path(git("rev-parse", "--show-toplevel", capture=True).stdout.strip())


def verify(commands: list[str], root: Path) -> bool:
    """Run every verification command, stopping at the first failure.

    Args:
        commands: Shell command lines.
        root: Directory to run them in.

    Returns:
        True when all commands succeeded.
    """
    for command in commands:
        print(f"+ verify: {command}", file=sys.stderr)
        if subprocess.run(command, shell=True, cwd=root).returncode != 0:
            print(f"Verification failed: {command}", file=sys.stderr)
            return False
    return True

# endregion


def main(argv: list[str] | None = None) -> int:
    """Rebase, verify and push the current lane branch to ``origin/master``.

    Args:
        argv: Optional argument list.

    Returns:
        0 on success, 1 dirty tree, 2 rebase conflict, 3 verify failure, 4 gave up.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--verify", action="append", default=[], help="command to run after rebase (repeatable)")
    parser.add_argument("--attempts", type=int, default=5)
    args = parser.parse_args(argv)

    root = repo_root()
    if git("status", "--porcelain", capture=True).stdout.strip():
        print("Uncommitted changes; commit first.", file=sys.stderr)
        return 1
    for attempt in range(1, args.attempts + 1):
        git("fetch", "-q", "origin", "master")
        if git("rebase", "-q", "origin/master", check=False).returncode:
            print("Rebase conflict: resolve (keep both sides' intent), `git rebase --continue`, rerun.",
                  file=sys.stderr)
            return 2
        if not verify(args.verify, root):
            return 3
        if git("push", "-q", "origin", "HEAD:master", check=False).returncode == 0:
            head = git("rev-parse", "--short", "HEAD", capture=True).stdout.strip()
            print(f"Integrated {head} into master (attempt {attempt}).")
            return 0
        print("Push rejected (another lane landed); retrying...", file=sys.stderr)
    return 4


if __name__ == "__main__":
    sys.exit(main())
