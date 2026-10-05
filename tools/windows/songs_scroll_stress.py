"""Songs scroll stress journey on Windows (issue #247; cross-platform check #47 of iOS #8).

iOS once crashed or hung near the top of the Songs list because scroll position lived on the whole screen, so every
scroll rebuilt and re-sorted the list. This journey holds Windows to the same bar on every run:

* no crash or hang: the app keeps writing frame statistics and still answers UI Automation afterwards;
* scrolling never rebuilds or re-sorts the list: no ``songs-sections`` perf event (one per ``SongsViewModel.Sections``
  pipeline run) once the data has settled;
* no UI-thread stall over ``--max-stall-ms`` (default 250): the ``max=`` of every ``ui-frames`` line from
  ``--frame-stats`` (``Domain/FrameIntervalSummary.cs``);
* the list ends back at its top (UIA Scroll pattern vertical percent 0) after flinging up from the bottom;
* after the measured window, jumps without animation (UIA Scroll pattern to 25/50/75/100/0%) leave the pinned section
  header (``fst.songs.section-header``) naming the first on-screen row's section, not the section before the jump.

Phases per window size and round:

``near-top``
    The app's own ``--auto-scroll-speed 2000 --auto-scroll-span 1500`` ping-pongs the list over its first 1500 epx at
    2000 epx/s (a reversal every 0.75 s) for ``--seconds``.
``flings``
    UI Automation only, so it also runs on a locked console: ``--bursts`` rapid Scroll-pattern jumps between the top and
    a few percent down, ``--cycles`` jumps from the bottom straight back to the top, then posted End/Home keys on the
    focused list. ``--wheel`` adds real mouse-wheel bursts (unlocked console only).

The fixture run (default) starts ``tools/mock_service.py --large-catalogue`` (110 songs) with a fixture player;
``--live`` uses the app's default keyless public origin (pass ``--profile <accountId>:<Name>`` for a public player;
never commit real account IDs).

Usage: ``python tools/windows/songs_scroll_stress.py [--sizes compact,medium,wide] [--rounds 2] [--seconds 20]
[--bursts 15] [--cycles 3] [--wheel] [--live [--profile ID:NAME]] [--extra-arg=--reduce-motion] [--keep DIR]
[--out result.json]``

Each phase holds one ``desktop`` host lock from launch to close (isolated settings and data folders), so other lanes'
GUI work and this run's own queue waits never fall inside the measured window.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import journey_exe  # noqa: E402  (sibling module)
import uiwin  # noqa: E402  (sibling tool; provides the lock, driver and step parser)

ROOT = Path(__file__).resolve().parents[2]
FIXTURE_PLAYER = "fixture-player-1:Fixture Player 1"
LIST = "id=fst.songs.list"
SECTIONS_EVENT = "songs-sections="
FRAMES_PREFIX = "ui-frames "
HEADER_ID = "fst.songs.section-header"
ROW_PREFIX = "fst.songs.row."
HEADER_POSITIONS = (25, 50, 75, 100, 0)
TREE_LINE = re.compile(r'^\s*\S+ "(?P<name>.*)" id=(?P<id>\S*) class=(?P<cls>\S*) rect=\S+(?: \[(?P<flags>[^\]]*)\])?')

# region Pure helpers (unit-tested)


def frame_windows(lines: list[str]) -> list[dict[str, float]]:
    """Parse the ``ui-frames k=v …`` summaries in perf-log lines.

    Args:
        lines: Perf-log lines.

    Returns:
        One ``{key: value}`` dict per summary line, in order.
    """
    windows = []
    for line in lines:
        if line.startswith(FRAMES_PREFIX):
            pairs = (part.partition("=") for part in line[len(FRAMES_PREFIX):].split())
            windows.append({key: float(value) for key, _, value in pairs if value})
    return windows


def sections_events(lines: list[str]) -> int:
    """Count ``songs-sections`` events (one per Songs pipeline run: rebuild and re-sort).

    Args:
        lines: Perf-log lines.

    Returns:
        Number of events.
    """
    return sum(1 for line in lines if line.startswith(SECTIONS_EVENT))


def evaluate(stress: list[str], seconds: float, max_stall_ms: float) -> tuple[dict, list[str]]:
    """Judge the perf-log lines written during one stress phase.

    Args:
        stress: Lines appended after the data settled, up to the end of the phase.
        seconds: Phase length, to require continuous frame summaries (one per 5 s).
        max_stall_ms: Longest allowed UI-thread frame interval.

    Returns:
        ``(metrics, failures)``; an empty failure list passes.
    """
    windows = frame_windows(stress)
    rebuilds = sections_events(stress)
    worst = max((w.get("max", 0.0) for w in windows), default=0.0)
    metrics = {
        "rebuilds": rebuilds,
        "frame_windows": len(windows),
        "frames": int(sum(w.get("count", 0) for w in windows)),
        "max_ms": round(worst, 2),
        "p99_ms": round(max((w.get("p99", 0.0) for w in windows), default=0.0), 2),
        "over33": int(sum(w.get("over33", 0) for w in windows)),
    }
    failures = []
    if rebuilds:
        failures.append(f"{rebuilds} Songs list rebuild(s)/re-sort(s) while only scrolling")
    expected = max(1, int(seconds // 5) - 1)
    if len(windows) < expected:
        failures.append(f"UI thread stopped reporting frames ({len(windows)} of {expected} expected 5 s summaries)")
    if any("max" not in w for w in windows):
        failures.append("frame summaries lack max= (app predates issue #247)")
    if worst > max_stall_ms:
        failures.append(f"UI-thread stall of {worst:.0f} ms (limit {max_stall_ms:.0f} ms)")
    return metrics, failures


def settled(lines: list[str], previous_events: int, stable_for: float, quiet_since: float, now: float) -> bool:
    """Whether the list's data has settled (no new pipeline runs for ``stable_for`` seconds).

    Args:
        lines: Perf-log lines so far.
        previous_events: ``songs-sections`` count at ``quiet_since``.
        stable_for: Required quiet time in seconds.
        quiet_since: Monotonic time the count last changed.
        now: Monotonic time now.

    Returns:
        ``True`` once rows were built at least once, frames are reported and the count held for ``stable_for``.
    """
    events = sections_events(lines)
    return (events >= 1 and events == previous_events and bool(frame_windows(lines))
            and now - quiet_since >= stable_for)


def sticky_mismatch(tree: list[str]) -> str | None:
    """Check that the pinned section header names the section of the first on-screen row.

    Args:
        tree: ``uiwin.py tree`` lines for the Songs page (rows sit in UIA ``Group "<label>"`` items).

    Returns:
        A failure message, or ``None`` when the header matches either of the first two on-screen rows' sections (a row
        about to leave under the bar may still count), the section before them while their own in-list title is still
        on screen below the bar (issue #288's push: the previous section stays current until that title pins), or the
        dump is inconclusive (no header or no on-screen row).
    """
    header, group, previous, group_shown = None, None, None, False
    allowed: list[str | None] = []
    rows = 0
    for line in tree:
        match = TREE_LINE.match(line)
        if not match:
            continue
        name, ident, cls, flags = match["name"], match["id"], match["cls"], (match["flags"] or "").split(",")
        if ident == HEADER_ID:
            header = name
        elif cls == "ListViewHeaderItem":
            previous, group, group_shown = group, name, "offscreen" not in flags
        elif ident.startswith(ROW_PREFIX) and "offscreen" not in flags:
            if rows == 0 and group_shown:
                allowed.append(previous)
            allowed.append(group)
            rows += 1
            if rows == 2:
                break
    if header is None or not rows or header in allowed:
        return None
    first = allowed[-rows]
    return f"section header reads {header!r} over rows of section {first!r}"


def header_steps(folder: Path, positions: tuple[int, ...] = HEADER_POSITIONS) -> list[str]:
    """``drive`` steps that jump the list (UIA Scroll pattern, no animation) and dump the tree at each position.

    Args:
        folder: Folder for the ``tree-<percent>.txt`` dumps.
        positions: Vertical scroll percents to visit, in order.

    Returns:
        Steps; read the dumps with :func:`sticky_mismatch`.
    """
    steps = []
    for percent in positions:
        steps += [f"scrollto:{LIST},{percent}", "wait:1", f"tree:{folder / f'tree-{percent}.txt'}"]
    return steps


def fling_steps(bursts: int, cycles: int, wheel: bool) -> list[str]:
    """``uiwin.py drive`` steps for the flings phase.

    Args:
        bursts: Rapid top ↔ a-few-percent jumps near the top.
        cycles: Bottom → top jumps (and End/Home key pairs).
        wheel: Add real mouse-wheel bursts (needs an unlocked console).

    Returns:
        Steps ending with the list asserted back at its top.
    """
    steps = [f"waitfor:{LIST}@30"]
    for index in range(bursts):
        steps += [f"scrollto:{LIST},{2 + index % 4}", f"scrollto:{LIST},0"]
    for _ in range(cycles):
        steps += [f"scrollto:{LIST},100", "wait:0.3", f"scrollto:{LIST},55", f"scrollto:{LIST},0", "wait:0.3"]
    steps += [f"focus:{LIST}"]
    for _ in range(cycles):
        steps += ["key:end", "wait:0.4", "key:home", "wait:0.4"]
    if wheel:
        for _ in range(bursts):
            steps += [f"scroll:{LIST},-5", f"scroll:{LIST},5"]
        for _ in range(cycles):
            steps += [f"scroll:{LIST},-200", "wait:0.3", f"scroll:{LIST},250", "wait:0.3"]
    steps += [f"assertstate:{LIST}|scroll=0@10", f"waitfor:{LIST}@5"]
    return steps

# endregion

# region Runner


def read_lines(path: Path) -> list[str]:
    """Read a perf log that may not exist yet.

    Args:
        path: Log path.

    Returns:
        Its lines.
    """
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return []


def wait_settled(log: Path, stable_for: float, timeout: float) -> int:
    """Wait until the Songs data stops rebuilding the list.

    Args:
        log: Perf log.
        stable_for: Quiet seconds required.
        timeout: Give up after this many seconds.

    Returns:
        The perf-log line count at the settle point.

    Raises:
        RuntimeError: Rows never settled.
    """
    start = quiet_since = time.monotonic()
    previous = -1
    while time.monotonic() - start < timeout:
        lines = read_lines(log)
        now = time.monotonic()
        events = sections_events(lines)
        if events != previous:
            previous, quiet_since = events, now
        if settled(lines, previous, stable_for, quiet_since, now):
            return len(lines)
        time.sleep(0.25)
    raise RuntimeError(f"Songs never settled in {timeout:.0f} s ({previous} pipeline runs)")


def run_phase(options: argparse.Namespace, size: str, phase: str, folder: Path) -> dict:
    """Launch, stress, judge and close one phase inside a single desktop-lock hold.

    The hold keeps other lanes' GUI work (and this run's own queue waits) out of the measured window.

    Args:
        options: Parsed arguments.
        size: Window preset.
        phase: ``near-top`` or ``flings``.
        folder: Folder for the settings file and the perf log.

    Returns:
        A result record with ``metrics``, ``failures`` and the ``log`` path.
    """
    log = folder / f"perf-r{options.round}-{size}-{phase}.log"
    log.unlink(missing_ok=True)
    env = uiwin.launch_env(None, "/songs", [f"FST_SETTINGS_PATH={folder / 'settings.json'}",
                                            f"FST_DEBUG_DATA_DIR={folder / 'data'}"]
                           + ([f"FST_DEBUG_PROFILE={options.profile}"] if options.profile else []))
    warning = uiwin.prepare_automation(options.exe, env)
    if warning:
        print(f"warning: {warning}", file=sys.stderr)
    args = [f"--perf-log={log}", "--frame-stats", *options.extra_arg]
    if not options.live:
        args.append(f"--base-url=http://127.0.0.1:{options.port}/")
    if phase == "near-top":
        args += ["--auto-scroll-speed=2000", "--auto-scroll-span=1500"]
    record: dict = {"size": size, "phase": phase, "metrics": {}, "failures": [], "log": str(log)}
    lock = uiwin.HostLock("desktop", purpose=f"songs scroll stress {size} {phase} [{ROOT.name}]",
                          hold_seconds=300, wait_seconds=1800)
    with lock:
        pid = None
        try:
            pid = uiwin.run_driver({"command": "launch", "exe": str(options.exe), "args": args, "env": env,
                                    "timeout": 60}, lock)["pid"]
            uiwin.run_driver({"command": "resize", "pid": pid, "op": uiwin.preset_op(size)}, lock)
            uiwin.run_driver({"command": "drive", "pid": pid, "steps": [uiwin.parse_step(f"waitfor:{LIST}@60")]},
                             lock, budget=90)
            mark = wait_settled(log, options.settle, 90)
            started = time.monotonic()
            if phase == "near-top":
                time.sleep(options.seconds)
                steps = [f"waitfor:{LIST}@10"]
            else:
                steps = fling_steps(options.bursts, options.cycles, options.wheel)
            uiwin.run_driver({"command": "drive", "pid": pid, "steps": [uiwin.parse_step(s) for s in steps]}, lock,
                             budget=lock.remaining())
            time.sleep(5.5)  # flush the frame summary that covers the last step
            elapsed = time.monotonic() - started
            record["metrics"], record["failures"] = evaluate(read_lines(log)[mark:], elapsed, options.max_stall_ms)
            record["metrics"]["seconds"] = round(elapsed, 1)
            if phase == "flings":
                # After the measured window: tree dumps walk the whole list on the app's UI thread.
                trees = folder / f"trees-r{options.round}-{size}"
                trees.mkdir(parents=True, exist_ok=True)
                uiwin.run_driver({"command": "drive", "pid": pid,
                                  "steps": [uiwin.parse_step(s) for s in header_steps(trees)]},
                                 lock, budget=lock.remaining())
                for percent in HEADER_POSITIONS:
                    tree = read_lines(trees / f"tree-{percent}.txt")
                    problem = sticky_mismatch(tree) if tree else "no UIA tree dump"
                    if problem:
                        record["failures"].append(f"after a jump to {percent}%: {problem}")
        except (RuntimeError, ValueError) as error:
            record["failures"].append(str(error).strip())
        finally:
            if pid:
                try:
                    problem = close_failure(uiwin.run_driver({"command": "close", "pid": pid}, lock))
                    if problem:
                        record["failures"].append(problem)
                except RuntimeError as error:
                    record["failures"].append(f"close: {error}")
    return record


def close_failure(response: dict) -> str | None:
    """Judge the driver's ``close`` response: the app must exit by itself with code 0.

    Args:
        response: ``FstUia`` close response (``exitCode`` and ``killed`` when the driver reports them).

    Returns:
        A failure message, or ``None`` for a clean exit (or an older driver that does not report the exit code).
    """
    if response.get("killed"):
        return "close: the app did not exit within 5 s and was killed"
    code = response.get("exitCode")
    if code in (None, 0):
        return None
    return f"close: the app exited with 0x{code & 0xFFFFFFFF:08x} (crash during shutdown)"

def main() -> int:
    """Run every size × round × phase.

    Returns:
        Process exit code (1 on any failure).
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--sizes", default="medium", help="comma-separated uiwin.py presets")
    parser.add_argument("--rounds", type=int, default=1)
    parser.add_argument("--phases", default="near-top,flings")
    parser.add_argument("--seconds", type=float, default=20, help="near-top auto-scroll duration")
    parser.add_argument("--bursts", type=int, default=15)
    parser.add_argument("--cycles", type=int, default=3)
    parser.add_argument("--wheel", action="store_true", help="add real mouse-wheel bursts (unlocked console)")
    parser.add_argument("--settle", type=float, default=4, help="quiet seconds before the stress starts")
    parser.add_argument("--max-stall-ms", type=float, default=250)
    parser.add_argument("--port", type=int, default=18761)
    parser.add_argument("--live", action="store_true", help="the app's default keyless public origin")
    parser.add_argument("--profile", help="FST_DEBUG_PROFILE accountId:Name (fixture default: a fixture player)")
    parser.add_argument("--anonymous", action="store_true", help="no selected player")
    parser.add_argument("--extra-arg", action="append", default=[], help="extra app flag, e.g. --extra-arg=--reduce-motion")
    parser.add_argument("--out", type=Path, help="write the results as JSON")
    parser.add_argument("--keep", type=Path, help="keep the perf logs in this folder (default: a temporary folder)")
    journey_exe.add_argument(parser)
    options = parser.parse_args()
    if options.anonymous:
        options.profile = None
    elif not options.profile and not options.live:
        options.profile = FIXTURE_PLAYER
    server = None
    if not options.live:
        server = subprocess.Popen([sys.executable, str(ROOT / "tools" / "mock_service.py"), "--port", str(options.port),
                                   "--large-catalogue"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(50):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{options.port}/api/publication", timeout=1)
                break
            except OSError:
                time.sleep(0.2)
    results = []
    try:
        with tempfile.TemporaryDirectory() as scratch:
            folder = options.keep or Path(scratch)
            folder.mkdir(parents=True, exist_ok=True)
            for round_index in range(options.rounds):
                options.round = round_index + 1
                for size in options.sizes.split(","):
                    for phase in options.phases.split(","):
                        record = run_phase(options, size, phase, folder)
                        record["round"] = round_index + 1
                        results.append(record)
                        verdict = "FAIL" if record["failures"] else "PASS"
                        print(f"{verdict} round {round_index + 1} {size} {phase}: {json.dumps(record['metrics'])}"
                              + "".join(f"\n  - {failure}" for failure in record["failures"]), flush=True)
    finally:
        if server:
            server.terminate()
    if options.out:
        options.out.write_text(json.dumps(results, indent=2), encoding="utf-8")
    return 1 if any(r["failures"] for r in results) else 0

# endregion


if __name__ == "__main__":
    sys.exit(main())
