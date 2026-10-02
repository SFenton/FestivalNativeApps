#!/usr/bin/env python3
"""Relay git history and Claude Code lanes between this Mac and the Windows host.

The Windows host (``sfenton-music``) builds and runs the Android and Windows
apps and pushes to GitHub directly (see ``.agents/workflow/windows-relay.md``).
This tool creates lane worktrees there, runs headless Claude Code lanes, and
keeps ``collect``/``integrate`` as a bundle-based fallback if GitHub auth breaks.

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

HOST = "sfenton-music"
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
    """Fast-forward the Windows main clone to GitHub ``origin/master``.

    The Windows host has direct GitHub access (gh file-stored token), so this is
    a plain fetch + reset of the main clone; lane worktrees rebase themselves.

    Returns:
        Process exit code.
    """
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
    # SSH sessions create files owned by BUILTIN\\Administrators; the lane runs as sfent in
    # the desktop session and git refuses repositories owned by someone else.
    remote(f"icacls {win(path)} /setowner sfent /T /C /Q", check=False)
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


def cmd_launch(args: argparse.Namespace) -> int:
    """Start a lane as a named, monitorable Remote Control session on Windows.

    The session runs interactively in the operator's logged-in desktop session
    (via a one-shot scheduled task), so it has its own console window on the
    Windows desktop and appears in claude.ai/code as ``FST-<name>`` for the
    operator to watch and steer. The lane brief is copied to
    ``relay/prompt-<name>.md``; the startup prompt tells the session to follow it
    and to write ``relay/status/<name>.done`` (its final report) when finished.

    Args:
        args: ``name`` of the lane and local ``prompt`` file.

    Returns:
        Process exit code.
    """
    name = args.name
    session = f"FST-{name}"
    path = f"{WIN_LANES}/{name}"
    prompt_remote = f"{WIN_ROOT}/relay/prompt-{name}.md"
    done_remote = f"{WIN_ROOT}/relay/status/{name}.done"
    remote(f"if not exist {win(WIN_ROOT + '/relay/status')} mkdir {win(WIN_ROOT + '/relay/status')}")
    remote(f"if exist {win(done_remote)} del {win(done_remote)}", check=False)
    scp_to(Path(args.prompt), prompt_remote)
    startup = (
        f"You are lane {session}. Read {prompt_remote.replace('/', chr(92))} and follow it exactly. "
        f"When your milestone is complete (or you are blocked), write your final report to "
        f"{done_remote.replace('/', chr(92))} and then stay idle for follow-up instructions."
    )
    wrapper = (
        "@echo off\r\n"
        f"title {session}\r\n"
        f"cd /d {win(path)}\r\n"
        f'claude --remote-control {session} --permission-mode bypassPermissions "{startup}"\r\n'
    )
    with tempfile.TemporaryDirectory() as tmp:
        cmd_file = Path(tmp) / f"launch-{name}.cmd"
        cmd_file.write_bytes(wrapper.encode("utf-8"))
        scp_to(cmd_file, f"{WIN_ROOT}/relay/launch-{name}.cmd")
    task = f"FST-Lane-{name}"
    remote(f"schtasks /create /f /tn {task} /tr {win(WIN_ROOT + '/relay/launch-' + name + '.cmd')} "
           f"/sc once /st 23:59 /it /rl LIMITED")
    remote(f"schtasks /run /tn {task}")
    print(f"launched {session} (claude.ai/code); done marker: {done_remote}")
    return 0


def cmd_wait(args: argparse.Namespace) -> int:
    """Block until a launched lane writes its done marker, then print its report.

    Run as a background job so the orchestrator is notified when the lane finishes.

    Args:
        args: ``name`` of the lane and ``poll`` interval in seconds.

    Returns:
        Process exit code.
    """
    import time
    done_remote = f"{WIN_ROOT}/relay/status/{args.name}.done"
    while True:
        result = remote(f"if exist {win(done_remote)} (type {win(done_remote)}) else (echo __PENDING__)",
                        check=False, capture=True)
        if "__PENDING__" not in (result.stdout or "") and result.returncode == 0:
            print(result.stdout)
            return 0
        time.sleep(args.poll)


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
    launch = sub.add_parser("launch", help="start a monitorable Remote Control lane session")
    launch.add_argument("name")
    launch.add_argument("prompt", help="local lane brief (markdown)")
    launch.set_defaults(func=cmd_launch)
    wait = sub.add_parser("wait", help="block until a launched lane writes its done marker")
    wait.add_argument("name")
    wait.add_argument("--poll", type=float, default=120.0)
    wait.set_defaults(func=cmd_wait)
    ex = sub.add_parser("exec")
    ex.add_argument("command")
    ex.set_defaults(func=cmd_exec)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
