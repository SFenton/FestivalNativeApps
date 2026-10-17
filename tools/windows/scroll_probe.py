#!/usr/bin/env python3
"""Scroll stress and smoothness suite for every Windows page and modal (issues #642, #668).

Launches the app once per entry of ``tools/windows/scroll_stress.json`` with ``--scroll-probe`` against loopback
fixtures. A modal entry (``"target": "dialog"``) first opens its dialog with FstUia ``open`` steps. In the app, the
probe scrolls the page's main scroller (or the dialog's) in three wheel cycles (animated wheel-notch steps down, then
up) and two scrollbar-drag cycles (an offset change every frame, top to bottom and back, so layout, realization and
per-scroll handlers all run inside frames on the UI thread). It then writes per-pass ``scroll-probe`` lines to the perf
log: UI-thread frame intervals, offset smoothness, the UI-thread time of per-scroll handlers and garbage collections.

Each moving pass must meet the entry's thresholds (``defaults.thresholds``, overridden per entry):
``max_reversals`` frames whose offset moved against the scroll, ``max_stalls`` frames of 33 ms or more,
``max_p95_ms`` the 95th-percentile frame interval, ``max_work_stalls`` frames whose UI-thread work (from
``CompositionTarget.Rendering`` to the thread's next idle moment: layout, realization, render walk and handlers) took
33 ms or more, ``max_work_p95_ms`` that work's 95th percentile, ``max_handler_ms`` per-scroll handler time in a pass
(about two seconds) and ``max_gc2`` blocking gen2 collections over the moving passes after the first (load settles).
Per-frame WinRT objects (event args, ``TransformToVisual``) add GC memory pressure that induces gen2 collections of
10-40 ms (#642), and a full Quick Links anchor walk per drag frame cost 3-4 ms (#668).

A pass during which the window was covered, cloaked, locked or on a display that turned off (``hidden=<reason>``)
measures DWM's throttled timer (about 31 ms frames), not the app, so the entry reruns once and then fails as an
environment problem (exit 2) rather than a regression. The runner wakes the display and brings the window to the front
before each probe, and the app keeps the display on while it scrolls. A failing entry is relaunched once and fails only
if the relaunch fails too (``--no-confirm`` skips this): a fresh launch repeats the app's cold-start work (first
realization, first layout), so only a hitch from another process on a shared host goes away.

``--ci`` (the windows-ui job, a hosted runner with software rendering and the Debug build) enforces reversals, gen2
collections, handler time (times ``--ci-handler-scale``) and frame work (``max_work_p95_ms`` times
:data:`CI_WORK_SCALE`, hitches over 100 ms), so a page whose frames regress fails CI. Frame intervals and throttled
passes are only reported there: WARP frame pacing on a hosted VM measures the runner's present path, not the app, while
frame work is the UI thread's own time per frame.

Usage: python tools/windows/scroll_probe.py [--exe release|debug|aot|PATH] [--pages songs,song-detail,...]
       [--suite FILE] [--out DIR] [--ci] [--no-confirm] [--arg=--no-art] [--env KEY=VALUE]
"""
from __future__ import annotations

import argparse
import ctypes
import json
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import journey_exe  # noqa: E402  (sibling tool; --exe aliases)
import ui_journey  # noqa: E402  (sibling tool; fixture-list convention)
import uiwin  # noqa: E402  (sibling tool; provides the lock and driver)

ROOT = Path(__file__).resolve().parents[2]
SUITE = Path(__file__).resolve().parent / "scroll_stress.json"
MOVING = ("down", "up", "drag-down", "drag-up")
PASS = re.compile(r"scroll-probe (rest|down|up|drag-down|drag-up) frames=(\d+) p50=([\d.]+) p95=([\d.]+) max=([\d.]+) "
                  r"over33=(\d+) .*?reversals=(\d+) .*?offset=([\d.]+)(?: hidden=(\S+))?")
COST = re.compile(r"scroll-probe cost (\S+) handlers=([\d.]+)ms")
GC = re.compile(r"scroll-probe gc (\S+) .*?\bgc2=(\d+)")
WORK = re.compile(r"\bwork95=([\d.]+) workMax=([\d.]+) work33=(\d+) work100=(\d+)")
#: How much slower a frame's UI-thread work may be on the hosted runner (Debug build, shared vCPUs): ``--ci`` scales
#: ``max_work_p95_ms`` by it and counts work hitches over 100 ms (33 ms times this) instead of 33 ms.
CI_WORK_SCALE = 3.0

# region Suite


def load_suite(path: Path = SUITE) -> list[dict]:
    """Reads the suite and merges each entry over the defaults.

    Args:
        path: Suite JSON (``defaults`` and ``pages``).

    Returns:
        Entries with ``size``, ``profile``, ``fixture``, ``target``, ``open`` and merged ``thresholds``.
    """
    suite = json.loads(path.read_text(encoding="utf-8"))
    defaults = suite["defaults"]
    pages = []
    for page in suite["pages"]:
        merged = {"target": "page", "open": [], **{k: v for k, v in defaults.items() if k != "thresholds"}, **page}
        merged["thresholds"] = {**defaults["thresholds"], **page.get("thresholds", {})}
        pages.append(merged)
    return pages


# endregion

# region Evaluation


@dataclass
class Pass:
    """One probe pass parsed from the perf log."""

    label: str
    frames: int
    p50: float
    p95: float
    max: float
    stalls: int
    reversals: int
    offset: float
    hidden: str = "0"
    handler_ms: float = 0.0
    gc2: int = 0
    work95: float | None = None
    work_max: float = 0.0
    work33: int = 0
    work100: int = 0
    line: str = ""


@dataclass
class Verdict:
    """An entry's result: regressions (``failures``), advisory notes and whether the environment hid a pass."""

    failures: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    hidden: list[str] = field(default_factory=list)


def parse_passes(lines: list[str]) -> list[Pass]:
    """Parses the probe's pass, cost and gc lines.

    Args:
        lines: Perf log lines.

    Returns:
        Passes in log order, each with its handler time and gen2 count.
    """
    passes: list[Pass] = []
    for line in lines:
        if match := PASS.search(line):
            label, frames, p50, p95, peak, stalls, reversals, offset, hidden = match.groups()
            passes.append(Pass(label, int(frames), float(p50), float(p95), float(peak), int(stalls), int(reversals),
                               float(offset), hidden or "0", line=line[line.index("scroll-probe"):]))
            if work := WORK.search(line):
                passes[-1].work95, passes[-1].work_max = float(work.group(1)), float(work.group(2))
                passes[-1].work33, passes[-1].work100 = int(work.group(3)), int(work.group(4))
        elif (match := COST.search(line)) and passes and passes[-1].label == match.group(1):
            passes[-1].handler_ms = float(match.group(2))
        elif (match := GC.search(line)) and passes and passes[-1].label == match.group(1):
            passes[-1].gc2 = int(match.group(2))
    return passes


def evaluate(name: str, passes: list[Pass], thresholds: dict, frames_enforced: bool = True,
             handler_scale: float = 1.0, ci: bool = False) -> Verdict:
    """Judges an entry's passes against its thresholds.

    Args:
        name: Entry name (prefixes each message).
        passes: Parsed passes.
        thresholds: ``max_reversals``, ``max_stalls``, ``max_p95_ms``, ``max_work_stalls``, ``max_work_p95_ms``,
            ``max_handler_ms`` and ``max_gc2``, plus an optional ``drag`` dict whose limits replace these for the
            scrollbar-drag passes.
        frames_enforced: Whether frame intervals (``max_stalls``, ``max_p95_ms``) fail the entry or are only noted.
        handler_scale: Multiplier for ``max_handler_ms`` (a Debug build's slower handlers).
        ci: Hosted-runner limits for frame work: ``max_work_p95_ms`` times :data:`CI_WORK_SCALE`, and work hitches
            counted over 100 ms instead of 33 ms. Frame work is always enforced: it is the UI thread's own time per frame,
            which software rendering and DWM's pacing do not change.

    Returns:
        The verdict; ``hidden`` lists passes the desktop throttled, which invalidate rather than fail the entry.
    """
    verdict = Verdict()
    moving = [p for p in passes if p.label in MOVING]
    if not moving:
        verdict.failures.append(f"{name}: no probe passes (no scrollable content found)")
        return verdict
    for p in passes:
        if p.hidden != "0":
            verdict.hidden.append(f"{name}: {p.label} hidden={p.hidden}")
    work_scale, hitch_ms = (CI_WORK_SCALE, 100) if ci else (1.0, 33)
    for p in moving:
        limits = {**thresholds, **thresholds.get("drag", {})} if p.label.startswith("drag") else thresholds
        problems = []
        if p.reversals > limits["max_reversals"]:
            problems.append(f"reversals {p.reversals} > {limits['max_reversals']}")
        if p.handler_ms > limits["max_handler_ms"] * handler_scale:
            problems.append(f"handlers {p.handler_ms:.1f} ms > {limits['max_handler_ms'] * handler_scale:.0f}")
        if p.work95 is None:
            problems.append("no frame work recorded (an app build without the work probe)")
        else:
            hitches = p.work100 if ci else p.work33
            if hitches > limits["max_work_stalls"]:
                problems.append(f"work hitches {hitches} (>{hitch_ms} ms) > {limits['max_work_stalls']}")
            if p.work95 > limits["max_work_p95_ms"] * work_scale:
                problems.append(f"work p95 {p.work95:.1f} ms > {limits['max_work_p95_ms'] * work_scale:.0f}")
        frames = []
        if p.stalls > limits["max_stalls"]:
            frames.append(f"stalls {p.stalls} > {limits['max_stalls']}")
        if p.p95 > limits["max_p95_ms"]:
            frames.append(f"p95 {p.p95:.1f} ms > {limits['max_p95_ms']}")
        if frames_enforced:
            problems += frames
        elif frames:
            verdict.notes.append(f"{name} {p.label}: " + ", ".join(frames) + " (advisory)")
        if problems:
            verdict.failures.append(f"{name} {p.label}: " + ", ".join(problems) + f" [{p.line}]")
    later = sum(p.gc2 for p in moving[1:])
    if later > thresholds["max_gc2"]:
        verdict.failures.append(f"{name}: {later} gen2 collections after the first pass > {thresholds['max_gc2']}")
    return verdict


# endregion

# region Launch


def wake_display() -> None:
    """Nudges the mouse one pixel and back, which turns a dimmed or idle-off console display back on.

    DWM throttles frames to its timer while the display is off, so a probe would measure the desktop instead of the
    app. The app keeps the display on while it scrolls; this wakes it first. No-op off Windows or in a locked session.
    """
    if sys.platform != "win32":
        return

    class MouseInput(ctypes.Structure):
        _fields_ = [("dx", ctypes.c_long), ("dy", ctypes.c_long), ("mouseData", ctypes.c_ulong),
                    ("dwFlags", ctypes.c_ulong), ("time", ctypes.c_ulong), ("dwExtraInfo", ctypes.c_size_t)]

    class Input(ctypes.Structure):
        _fields_ = [("type", ctypes.c_ulong), ("mi", MouseInput)]

    for dx in (1, -1):
        event = Input(0, MouseInput(dx, 0, 0, 0x0001, 0, 0))  # INPUT_MOUSE, MOUSEEVENTF_MOVE
        ctypes.windll.user32.SendInput(1, ctypes.byref(event), ctypes.sizeof(Input))
        time.sleep(0.05)


def start_fixture(script: Path | None, flags: tuple[str, ...], log: Path) -> tuple[subprocess.Popen, int]:
    """Starts a fixture service on a free loopback port.

    Args:
        script: Fixture wrapper (``None``: the plain mock service).
        flags: Its flags.
        log: Service output file.

    Returns:
        Process and port.

    Raises:
        RuntimeError: No port reported within 20 s.
    """
    target = script or ROOT / "tools" / "mock_service.py"
    with log.open("w", encoding="utf-8") as handle:
        proc = subprocess.Popen([sys.executable, "-u", str(target), "--port", "0", *flags], stdout=handle,
                                stderr=subprocess.STDOUT)
    for _ in range(200):
        if match := re.search(r"127\.0\.0\.1:(\d+)", log.read_text(encoding="utf-8", errors="replace")):
            return proc, int(match.group(1))
        time.sleep(0.1)
    proc.kill()
    raise RuntimeError(f"fixture service did not start; see {log}")


def run_page(exe: Path, page: dict, port: int, folder: Path, extra_env: list[str], extra_args: list[str]) -> list[str]:
    """Launches one entry with the probe, opens its modal if any, and returns its perf-log lines.

    Args:
        exe: App executable.
        page: Suite entry.
        port: Fixture service port.
        folder: Scratch folder for settings, data and the perf log.
        extra_env: Additional ``KEY=VALUE`` launch environment entries.
        extra_args: Additional app arguments (e.g. ``--no-art`` for an A/B run).

    Returns:
        The perf log's ``scroll-probe`` and ``occlusion`` lines.
    """
    name = page["name"]
    state = folder / name
    state.mkdir(parents=True, exist_ok=True)
    log = state / "perf.log"
    log.unlink(missing_ok=True)
    settings = state / "settings.json"
    settings.write_text(json.dumps(page.get("settings", {})), encoding="utf-8")
    page_env = [f"{key}={value.replace('{repo}', str(ROOT))}" for key, value in page.get("env", {}).items()]
    env = uiwin.launch_env(page.get("tab"), page.get("route"), [f"FST_SETTINGS_PATH={settings}",
                                                                 f"FST_DEBUG_DATA_DIR={state / 'data'}",
                                                                 f"FST_DEBUG_PROFILE={page['profile']}", *page_env,
                                                                 *extra_env])
    uiwin.prepare_automation(exe, env)
    args = [f"--perf-log={log}", f"--scroll-probe-target={page['target']}", "--whats-new", "off",
            f"--base-url=http://127.0.0.1:{port}/", *extra_args]
    lock = uiwin.HostLock("desktop", purpose=f"scroll probe {name} [{ROOT.name}]", hold_seconds=240, wait_seconds=1800)
    with lock:
        pid = uiwin.run_driver({"command": "launch", "exe": str(exe), "args": args, "env": env, "timeout": 60},
                               lock)["pid"]
        try:
            uiwin.run_driver({"command": "resize", "pid": pid, "op": uiwin.preset_op(page["size"])}, lock)
            wake_display()
            uiwin.run_driver({"command": "front", "pid": pid}, lock)
            if page["open"]:
                uiwin.run_driver({"command": "drive", "pid": pid, "steps": [uiwin.parse_step(s) for s in page["open"]]},
                                 lock, budget=lock.remaining())
            deadline = time.monotonic() + 150
            while time.monotonic() < deadline:
                text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
                if "scroll-probe done" in text or "scroll-probe none" in text or "scroll-probe error" in text:
                    break
                time.sleep(1)
        finally:
            uiwin.run_driver({"command": "close", "pid": pid}, lock)
    text = log.read_text(encoding="utf-8", errors="replace") if log.exists() else ""
    return [line for line in text.splitlines() if "scroll-probe" in line or "occlusion-" in line]


# endregion


def main(argv: list[str] | None = None) -> int:
    """Runs the suite; exit 1 on a regression, 2 when only the environment invalidated passes."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--exe", type=journey_exe.resolve, default=journey_exe.ALIASES["release"],
                        help="app under test: release (default), debug, aot, or a path")
    parser.add_argument("--suite", type=Path, default=SUITE)
    parser.add_argument("--pages", help="comma-separated entry names (default: every entry)")
    parser.add_argument("--out", type=Path, help="write results.json and each entry's probe lines here")
    parser.add_argument("--shots", type=Path, help=argparse.SUPPRESS)  # ci_ui passes --shots to runners
    parser.add_argument("--ci", action="store_true",
                        help="hosted runner: frame intervals are advisory; handler time and frame work are scaled")
    parser.add_argument("--ci-handler-scale", type=float, default=3.0)
    parser.add_argument("--env", action="append", default=[], help="extra KEY=VALUE launch environment")
    parser.add_argument("--arg", action="append", default=[], help="extra app argument, e.g. --arg=--no-art")
    parser.add_argument("--no-confirm", dest="confirm", action="store_false",
                        help="fail on the first failing launch instead of relaunching once to confirm the regression")
    options = parser.parse_args(argv)
    pages = load_suite(options.suite)
    if options.pages:
        wanted = options.pages.split(",")
        unknown = set(wanted) - {p["name"] for p in pages}
        if unknown:
            parser.error(f"unknown entries: {', '.join(sorted(unknown))}")
        pages = [p for p in pages if p["name"] in wanted]
    out = options.out or options.shots
    if out:
        out.mkdir(parents=True, exist_ok=True)
    fixtures: dict[tuple, tuple[subprocess.Popen, int]] = {}
    results = []
    failures: list[str] = []
    invalid: list[str] = []
    try:
        with tempfile.TemporaryDirectory(prefix="fst-scroll-probe-", ignore_cleanup_errors=True) as scratch:
            folder = Path(scratch)
            for page in pages:
                key = ui_journey.journey_fixture(tuple(page["fixture"]))
                if key not in fixtures:
                    fixtures[key] = start_fixture(key[0], key[1], folder / f"fixture-{len(fixtures)}.log")
                throttled = 0
                unconfirmed: list[str] = []
                while True:
                    lines = run_page(options.exe, page, fixtures[key][1], folder, options.env, options.arg)
                    verdict = evaluate(page["name"], parse_passes(lines), page["thresholds"],
                                       frames_enforced=not options.ci,
                                       handler_scale=options.ci_handler_scale if options.ci else 1.0, ci=options.ci)
                    if verdict.hidden and not options.ci and throttled == 0:
                        throttled += 1
                        print(f"note: {page['name']}: desktop throttled ({'; '.join(verdict.hidden)}); retrying")
                        continue
                    if verdict.failures and not verdict.hidden and not unconfirmed and options.confirm:
                        # A fresh launch repeats cold-start work, so only another process's hitch goes away.
                        unconfirmed = verdict.failures
                        print(f"note: {page['name']}: failed; relaunching to confirm ({len(unconfirmed)} finding(s))")
                        continue
                    break
                if unconfirmed and not verdict.failures:
                    verdict.notes += [f"not reproduced on relaunch: {entry}" for entry in unconfirmed]
                if options.ci and verdict.hidden:
                    # Frame intervals are advisory on a hosted runner, so a throttled pass still checks the rest.
                    verdict.notes += [f"{entry} (advisory)" for entry in verdict.hidden]
                    verdict.hidden = []
                print(f"== {page['name']} ({page['target']}, {page['size']})")
                if page.get("known"):
                    print(f"known: {page['known']}")
                for line in lines:
                    if "scroll-probe gc" not in line:
                        print("   " + line[line.index("scroll-probe") if "scroll-probe" in line else 0:])
                for note in verdict.notes:
                    print("note: " + note)
                if verdict.hidden:
                    invalid += verdict.hidden
                else:
                    failures += verdict.failures
                print(f"{'PASS' if not verdict.failures and not verdict.hidden else 'INVALID' if verdict.hidden else 'FAIL'} "
                      f"{page['name']}", flush=True)
                results.append({"name": page["name"], "target": page["target"], "size": page["size"],
                                "thresholds": page["thresholds"], "known": page.get("known", ""), "failures": verdict.failures,
                                "notes": verdict.notes, "hidden": verdict.hidden, "lines": lines})
                if out:
                    (out / f"{page['name']}.log").write_text("\n".join(lines) + "\n", encoding="utf-8")
    finally:
        for proc, _ in fixtures.values():
            proc.kill()
            proc.wait(timeout=10)
    if out:
        (out / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    for failure in failures:
        print("FAIL " + failure)
    for entry in invalid:
        print("INVALID " + entry)
    return 1 if failures else 2 if invalid else 0


if __name__ == "__main__":
    sys.exit(main())
