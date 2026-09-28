#!/usr/bin/env python3
"""Relay git history and Claude Code lanes between this Mac and the Windows host.

The Windows host (``sfenton-primary``) builds and runs the Android and Windows
apps, but it has no working GitHub credentials over SSH (Git Credential Manager
cannot use the Windows credential store in a non-interactive session). This Mac
is therefore the only machine that talks to GitHub: it ships ``origin/master``
to Windows as a git bundle and collects Windows lane branches back the same way.

Layout on Windows::

    C:/Users/sfent/workspace/FestivalNativeApps          main clone; origin = master.bundle
    C:/Users/sfent/workspace/FestivalNativeApps-lanes/X  one worktree per lane (branch lane/X)

Examples::

    python3 tools/win_relay.py sync                 # push current origin/master to Windows
    python3 tools/win_relay.py lane android         # create/refresh worktree lane/android
    python3 tools/win_relay.py run android prompt.md  # run a headless Claude Code lane
    python3 tools/win_relay.py collect android      # fetch lane/android back as win/android
    python3 tools/win_relay.py integrate android    # collect + rebase onto master + push
    python3 tools/win_relay.py exec "git -C C:/... status"   # ad-hoc command
"""

from __future__ import annotations

import argparse
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

# region Configuration

HOST = "sfenton-primary"
WIN_ROOT = "C:/Users/sfent/workspace"
WIN_REPO = f"{WIN_ROOT}/FestivalNativeApps"
WIN_LANES = f"{WIN_ROOT}/FestivalNativeApps-lanes"
WIN_BUNDLE = f"{WIN_ROOT}/relay/master.bundle"
REPO_ROOT = Path(__file__).resolve().parent.parent

# endregion

# region Helpers


def local(cmd: list[str], check: bool = True, **kw) -> subprocess.CompletedProcess:
    """Run a command on this Mac.

    Args:
        cmd: Argument vector.
        check: Raise on non-zero exit.
        **kw: Extra ``subprocess.run`` arguments.

    Returns:
        The completed process.
    """
    print("+", " ".join(shlex.quote(c) for c in cmd), file=sys.stderr)
    return subprocess.run(cmd, check=check, **kw)


def remote(command: str, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess:
    """Run a ``cmd.exe`` command on the Windows host over SSH.

    Args:
        command: Command line interpreted by the Windows default shell (cmd.exe).
        check: Raise on non-zero exit.
        capture: Capture stdout/stderr as text instead of streaming.

    Returns:
        The completed process.
    """
    print(f"+ [win] {command}", file=sys.stderr)
    return subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ServerAliveInterval=30", "-o", "ServerAliveCountMax=10", HOST, command],
        check=check, text=True,
        capture_output=capture,
    )


def win(path: str) -> str:
    """Quote a Windows path for cmd.exe.

    Args:
        path: Forward-slash Windows path.

    Returns:
        Double-quoted path with backslashes.
    """
    return '"' + path.replace("/", "\\") + '"'


def scp_to(local_path: Path, win_path: str) -> None:
    """Copy a local file to the Windows host.

    Args:
        local_path: File on this Mac.
        win_path: Destination (forward slashes).
    """
    local(["scp", "-q", "-o", "BatchMode=yes", str(local_path), f"{HOST}:{win_path}"])


def scp_from(win_path: str, local_path: Path) -> None:
    """Copy a file from the Windows host.

    Args:
        win_path: Source on Windows (forward slashes).
        local_path: Destination on this Mac.
    """
    local(["scp", "-q", "-o", "BatchMode=yes", f"{HOST}:{win_path}", str(local_path)])

# endregion

# region Commands


def cmd_sync(_: argparse.Namespace) -> int:
    """Ship ``origin/master`` to Windows and fast-forward the main clone.

    The bundle carries a single branch, ``relay-master``; Windows maps it to
    ``refs/remotes/origin/master`` so lane worktrees can rebase on ``origin/master``.

    Returns:
        Process exit code.
    """
    local(["git", "-C", str(REPO_ROOT), "fetch", "-q", "origin", "master"])
    local(["git", "-C", str(REPO_ROOT), "branch", "-q", "-f", "relay-master", "origin/master"])
    with tempfile.TemporaryDirectory() as tmp:
        bundle = Path(tmp) / "master.bundle"
        local(["git", "-C", str(REPO_ROOT), "bundle", "create", "-q", str(bundle), "relay-master"])
        remote(f"if not exist {win(WIN_ROOT + '/relay')} mkdir {win(WIN_ROOT + '/relay')}")
        scp_to(bundle, WIN_BUNDLE)
    exists = remote(f"if exist {win(WIN_REPO + '/.git')} (echo yes) else (echo no)", capture=True)
    if "yes" not in exists.stdout:
        remote(f"git clone -q -b relay-master {WIN_BUNDLE} {win(WIN_REPO)}")
        remote(f"git -C {win(WIN_REPO)} checkout -q -B master")
    remote(f"git -C {win(WIN_REPO)} remote set-url origin {WIN_BUNDLE}")
    remote(f"git -C {win(WIN_REPO)} config remote.origin.fetch +refs/heads/relay-master:refs/remotes/origin/master")
    remote(f"git -C {win(WIN_REPO)} fetch -q origin")
    remote(f"git -C {win(WIN_REPO)} checkout -q master")
    remote(f"git -C {win(WIN_REPO)} reset -q --hard origin/master")
    print(remote(f"git -C {win(WIN_REPO)} log --oneline -1", capture=True).stdout.strip())
    return 0


def cmd_lane(args: argparse.Namespace) -> int:
    """Create (or report) a Windows worktree for a lane.

    Args:
        args: ``name`` of the lane.

    Returns:
        Process exit code.
    """
    path = f"{WIN_LANES}/{args.name}"
    exists = remote(f"if exist {win(path)} (echo yes) else (echo no)", capture=True)
    if "yes" in exists.stdout:
        print(f"exists: {path}")
        return 0
    remote(f"git -C {win(WIN_REPO)} worktree add -q -b lane/{args.name} {win(path)} origin/master")
    print(path)
    return 0


def cmd_run(args: argparse.Namespace) -> int:
    """Run a headless Claude Code session in a lane worktree on Windows.

    The prompt file is copied to Windows and passed via stdin so no shell quoting
    of the prompt is needed. Runs in the foreground; call it from a background job.

    Args:
        args: ``name`` of the lane and local ``prompt`` file.

    Returns:
        The remote Claude Code exit status.
    """
    path = f"{WIN_LANES}/{args.name}"
    prompt_remote = f"{WIN_ROOT}/relay/prompt-{args.name}.md"
    scp_to(Path(args.prompt), prompt_remote)
    command = (
        f"cd /d {win(path)} && type {win(prompt_remote)} | claude -p "
        f"--permission-mode bypassPermissions --output-format text"
    )
    return remote(command, check=False).returncode


def cmd_collect(args: argparse.Namespace) -> int:
    """Fetch a Windows lane branch back to this Mac as ``win/<lane>``.

    Args:
        args: ``name`` of the lane.

    Returns:
        Process exit code.
    """
    bundle_remote = f"{WIN_ROOT}/relay/lane-{args.name}.bundle"
    remote(f"git -C {win(WIN_REPO)} bundle create -q {win(bundle_remote)} lane/{args.name}")
    with tempfile.TemporaryDirectory() as tmp:
        bundle = Path(tmp) / "lane.bundle"
        scp_from(bundle_remote, bundle)
        local(["git", "-C", str(REPO_ROOT), "fetch", "-q", str(bundle),
               f"+refs/heads/lane/{args.name}:refs/heads/win/{args.name}"])
    log = local(["git", "-C", str(REPO_ROOT), "log", "--oneline", f"origin/master..win/{args.name}"],
                capture_output=True, text=True)
    print(log.stdout.strip() or "(no new commits)")
    return 0


def cmd_integrate(args: argparse.Namespace) -> int:
    """Collect a Windows lane, rebase it onto ``origin/master`` and push.

    Uses a throwaway Mac worktree so the main checkout is untouched. Apple builds
    are not rerun (Windows lanes only touch ``android/``, ``windows/`` and docs);
    platform builds must already have passed on Windows.

    Args:
        args: ``name`` of the lane.

    Returns:
        Process exit code.
    """
    cmd_collect(args)
    tree = REPO_ROOT.parent / "FestivalNativeApps-lanes" / f"win-{args.name}"
    if tree.exists():
        local(["git", "-C", str(REPO_ROOT), "worktree", "remove", "--force", str(tree)])
    local(["git", "-C", str(REPO_ROOT), "worktree", "add", "-q", "--detach", str(tree), f"win/{args.name}"])
    try:
        for attempt in range(5):
            local(["git", "-C", str(tree), "fetch", "-q", "origin", "master"])
            rebase = local(["git", "-C", str(tree), "rebase", "-q", "origin/master"], check=False)
            if rebase.returncode:
                local(["git", "-C", str(tree), "rebase", "--abort"], check=False)
                print("Rebase conflict; resolve on Windows after `sync`.", file=sys.stderr)
                return 2
            if local(["git", "-C", str(tree), "push", "-q", "origin", "HEAD:master"], check=False).returncode == 0:
                print(f"Integrated win/{args.name} (attempt {attempt + 1}).")
                cmd_sync(args)
                return 0
        return 3
    finally:
        local(["git", "-C", str(REPO_ROOT), "worktree", "remove", "--force", str(tree)], check=False)


def cmd_exec(args: argparse.Namespace) -> int:
    """Run an ad-hoc cmd.exe command on Windows.

    Args:
        args: ``command`` string.

    Returns:
        The remote exit status.
    """
    return remote(args.command, check=False).returncode

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
    sub.add_parser("sync").set_defaults(func=cmd_sync)
    for name, func in (("lane", cmd_lane), ("collect", cmd_collect), ("integrate", cmd_integrate)):
        p = sub.add_parser(name)
        p.add_argument("name")
        p.set_defaults(func=func)
    run = sub.add_parser("run")
    run.add_argument("name")
    run.add_argument("prompt", help="local prompt file")
    run.set_defaults(func=cmd_run)
    ex = sub.add_parser("exec")
    ex.add_argument("command")
    ex.set_defaults(func=cmd_exec)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
