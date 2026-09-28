#!/usr/bin/env python3
"""Live regression: ``uiwin.py drive`` must act on its target even when another lane's app window covers it.

Launches two Debug instances of this worktree's app at the same preset (so the second exactly covers the first),
each with its own ``FST_DEBUG_DATA_DIR``, then mouse-clicks the **covered** instance's Settings pane item. Before
the foreground fix the click landed in the covering window. Checks:

1. a wheel ``scroll`` on the covered target scrolls its Songs list, not the cover's (the pre-fix driver scrolled
   the cover: it never foregrounded before wheel input);
2. a mouse ``click`` navigates the covered target to Settings while the cover stays on Songs;
3. ``--isolate`` minimizes the covering instance during the request and restores it afterwards.

Needs the operator's console session and takes the shared desktop lock (via ``uiwin.py``). Not part of the offline
``unittest`` discovery (file name does not start with ``test``). Run from the repo root after
``tools/windows/build.ps1``::

    python tools/windows/tests/live_occluded_drive.py
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
UIWIN = ROOT / "tools" / "windows" / "uiwin.py"
EXE = ROOT / "windows" / "Festival.App" / "bin" / "x64" / "Debug" / "net9.0-windows10.0.26100.0" / "win-x64" / \
    "FestivalScoreTracker.exe"


def uiwin(*args: str, check: bool = True) -> dict:
    """Run ``uiwin.py`` and return its JSON report (``{}`` for failures when ``check`` is False)."""
    proc = subprocess.run([sys.executable, str(UIWIN), *args], capture_output=True, text=True, timeout=600)
    if proc.returncode != 0:
        if check:
            raise RuntimeError(f"uiwin {' '.join(args)} failed ({proc.returncode}): {proc.stderr.strip()}")
        return {"error": proc.stderr.strip()}
    start = proc.stdout.find("{")
    return json.loads(proc.stdout[start:]) if start >= 0 else {}


def has_element(pid: int, automation_id: str, out: Path) -> bool:
    """Whether the window's UIA tree contains an AutomationId."""
    uiwin("tree", str(out), "--pid", str(pid), "--depth", "12")
    return f"id={automation_id} " in out.read_text(encoding="utf-8")


def visible_rows(pid: int, out: Path) -> list[str]:
    """On-screen Songs row names (UIA ``ListViewItem``s not flagged offscreen)."""
    uiwin("tree", str(out), "--pid", str(pid), "--depth", "16")
    return [line.split('"')[1] for line in out.read_text(encoding="utf-8").splitlines()
            if "ListItem \"" in line and "class=ListViewItem" in line and "offscreen" not in line]


def main() -> int:
    """Run the regression; exit 0 on success."""
    if not EXE.is_file():
        print(f"build first: {EXE} is missing", file=sys.stderr)
        return 2
    pids: list[int] = []
    with tempfile.TemporaryDirectory(prefix="fst-occluded-") as tmp:
        work = Path(tmp)
        try:
            for name in ("target", "cover"):
                result = uiwin("launch", str(EXE), "--tab", "songs", "--preset", "medium",
                               "--extra", f"FST_DEBUG_DATA_DIR={work / name}", "--extra", "FST_DEBUG_ANONYMOUS=1")
                pids.append(result["pid"])
            target, cover = pids
            front = uiwin("window", "--pid", str(cover))
            print(f"target {target} is covered by {cover} at {front['bounds']}")

            # Wheel input goes to whatever window is under the cursor: the pre-fix driver scrolled the cover.
            uiwin("drive", "--pid", str(target), "--steps", "waitfor:id=fst.songs.list@20; wait:2")
            first_target = visible_rows(target, work / "rows-target.txt")[0]
            first_cover = visible_rows(cover, work / "rows-cover.txt")[0]
            uiwin("drive", "--pid", str(target), "--steps", "scroll:id=fst.songs.list,-25; wait:1.5")
            assert first_target not in visible_rows(target, work / "rows-target.txt"), "covered target did not scroll"
            assert first_cover in visible_rows(cover, work / "rows-cover.txt"), "scroll leaked into the covering window"
            print("ok: wheel scroll reached the covered target only")

            uiwin("front", "--pid", str(cover))
            uiwin("drive", "--pid", str(target), "--steps",
                  "waitfor:id=fst.nav.settings@15; click:id=fst.nav.settings; waitfor:id=fst.settings@10")
            assert has_element(target, "fst.settings", work / "target.txt"), "target did not open Settings"
            assert not has_element(cover, "fst.settings", work / "cover.txt"), "click leaked into the covering window"
            print("ok: click reached the covered target only")

            uiwin("front", "--pid", str(cover))
            uiwin("drive", "--pid", str(target), "--isolate", "--steps",
                  "click:id=fst.nav.songs; waitfor:id=fst.songs.list@10")
            state = uiwin("window", "--pid", str(cover))["state"]
            assert state == "normal", f"isolated window was not restored (state {state})"
            print("ok: --isolate minimized and restored the covering window")
            return 0
        except (AssertionError, RuntimeError, KeyError) as error:
            print(f"FAIL: {error}", file=sys.stderr)
            return 1
        finally:
            for pid in pids:
                uiwin("close", "--pid", str(pid), check=False)


if __name__ == "__main__":
    sys.exit(main())
