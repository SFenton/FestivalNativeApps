#!/usr/bin/env python3
"""Adaptive-shell screenshot matrix: every section root (plus key detail routes) at every window preset.

Starts the anonymized Rivals fixture service (``rivals_fixture.py``, which serves the full mock catalogue) on a free
loopback port, then for each page launches this worktree's Debug build once with a fixture profile and its own
throwaway ``FST_DEBUG_DATA_DIR``, and drives one ``uiwin.py drive`` that resizes through the presets and screenshots
each. ``compact-pane`` opens the LeftMinimal pane overlay. Shots over ``--max-kb`` are downscaled (System.Drawing),
so fixture shots can be committed to ``windows/reports/screenshots``.

Usage::

    python tools/windows/shell_matrix.py --out C:/Users/sfent/workspace/showcase/win-shell/matrix
    python tools/windows/shell_matrix.py --out windows/reports/screenshots --pages songs --presets compact,compact-pane,medium,wide --prefix shell-
"""

from __future__ import annotations

import argparse
import json
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
UIWIN = ROOT / "tools" / "windows" / "uiwin.py"
EXE = ROOT / "windows" / "Festival.App" / "bin" / "x64" / "Debug" / "net9.0-windows10.0.26100.0" / "win-x64" / \
    "FestivalScoreTracker.exe"
PROFILE = "fixture-player-1:Demo Player"

#: page -> (tab, route, AutomationId that proves it rendered).
PAGES: dict[str, tuple[str | None, str | None, str]] = {
    "songs": ("songs", None, "fst.songs.list"),
    "suggestions": ("suggestions", None, "fst.nav.suggestions"),
    "leaderboards": ("leaderboards", None, "fst.nav.leaderboards"),
    "rivals": ("rivals", None, "fst.nav.rivals"),
    "statistics": ("statistics", None, "fst.nav.statistics"),
    "shop": ("shop", None, "fst.nav.shop"),
    "settings": ("settings", None, "fst.settings"),
    "song-detail": (None, "/songs/fixture-pulse", "fst.shell.title-bar"),
    "player": (None, "/player/fixture-player-1", "fst.shell.title-bar"),
}

#: Presets in capture order (``compact-pane`` = compact with the LeftMinimal pane opened).
PRESETS = ["compact", "compact-pane", "medium", "wide", "snap-left", "snap-right", "portrait-tablet"]


def plan_steps(page: str, presets: list[str], out: Path, prefix: str) -> list[str]:
    """Drive steps that capture one page at each preset.

    Args:
        page: Page key (file-name stem).
        presets: Presets from :data:`PRESETS`.
        out: Output folder.
        prefix: File-name prefix.

    Returns:
        ``uiwin.py`` step strings.
    """
    steps: list[str] = []
    for preset in presets:
        shot = f"shot:{(out / f'{prefix}{page}-{preset}.png').as_posix()}"
        if preset == "compact-pane":
            steps += ["resize:compact", "wait:1.5", "invoke:id=PART_PaneToggleButton", "wait:1", shot,
                      "key:esc", "wait:0.5"]
        else:
            steps += [f"resize:{preset}", "wait:2", shot]
    return steps


def free_port() -> int:
    """An unused loopback port."""
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def uiwin(*args: str) -> dict:
    """Run ``uiwin.py`` and parse its JSON report."""
    proc = subprocess.run([sys.executable, str(UIWIN), *args], capture_output=True, text=True, timeout=900)
    if proc.returncode != 0:
        raise RuntimeError(f"uiwin {args[0]} failed: {proc.stderr.strip()[-600:]}")
    start = proc.stdout.find("{")
    return json.loads(proc.stdout[start:]) if start >= 0 else {}


def shrink(png: Path, max_kb: int) -> None:
    """Downscale a PNG in 10% steps until it fits ``max_kb`` (no-op when it already fits)."""
    if png.stat().st_size <= max_kb * 1024:
        return
    script = (
        "Add-Type -AssemblyName System.Drawing; "
        f"$p='{png}'; $src=[Drawing.Image]::FromFile($p); $bytes=[IO.File]::ReadAllBytes($p); $scale=1.0; "
        "while ($bytes.Length -gt " + str(max_kb * 1024) + " -and $scale -gt 0.3) { $scale -= 0.1; "
        "$bmp=New-Object Drawing.Bitmap([int]($src.Width*$scale)),([int]($src.Height*$scale)); "
        "$g=[Drawing.Graphics]::FromImage($bmp); $g.InterpolationMode='HighQualityBicubic'; "
        "$g.DrawImage($src,0,0,$bmp.Width,$bmp.Height); $g.Dispose(); $ms=New-Object IO.MemoryStream; "
        "$bmp.Save($ms,[Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $bytes=$ms.ToArray() }; "
        "$src.Dispose(); [IO.File]::WriteAllBytes($p,$bytes)"
    )
    subprocess.run(["powershell", "-NoProfile", "-Command", script], check=True, timeout=120)


def main() -> int:
    """Capture the matrix; exit non-zero if any page failed."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", required=True)
    parser.add_argument("--pages", default=",".join(PAGES), help="comma-separated page keys")
    parser.add_argument("--presets", default=",".join(PRESETS))
    parser.add_argument("--prefix", default="")
    parser.add_argument("--max-kb", type=int, default=300)
    args = parser.parse_args()
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    presets = [p for p in args.presets.split(",") if p]
    unknown = [p for p in presets if p not in PRESETS] + [p for p in args.pages.split(",") if p not in PAGES]
    if unknown:
        parser.error(f"unknown page/preset: {unknown}")
    port = free_port()
    server = subprocess.Popen([sys.executable, str(ROOT / "tools" / "windows" / "rivals_fixture.py"), "--port", str(port)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    failures = []
    try:
        for _ in range(50):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{port}/api/publication", timeout=1)
                break
            except OSError:
                time.sleep(0.2)
        with tempfile.TemporaryDirectory(prefix="fst-matrix-") as data:
            for page in args.pages.split(","):
                tab, route, ready = PAGES[page]
                launch = ["launch", str(EXE), "--extra", f"FST_BASE_URL=http://127.0.0.1:{port}/",
                          "--extra", f"FST_DEBUG_PROFILE={PROFILE}", "--extra", f"FST_DEBUG_DATA_DIR={Path(data) / page}",
                          "--extra", "FST_DEBUG_FIRST_RUN=off"]
                if tab:
                    launch += ["--tab", tab]
                if route:
                    launch += ["--route", route]
                pid = None
                try:
                    pid = uiwin(*launch)["pid"]
                    steps = [f"waitfor:id={ready}@20", "wait:2", *plan_steps(page, presets, out, args.prefix)]
                    uiwin("drive", "--pid", str(pid), "--steps", "; ".join(steps))
                    for preset in presets:
                        shrink(out / f"{args.prefix}{page}-{preset}.png", args.max_kb)
                    print(f"ok {page}")
                except (RuntimeError, KeyError) as error:
                    failures.append(page)
                    print(f"FAIL {page}: {error}", file=sys.stderr)
                finally:
                    if pid:
                        subprocess.run([sys.executable, str(UIWIN), "close", "--pid", str(pid)], capture_output=True)
    finally:
        server.terminate()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
