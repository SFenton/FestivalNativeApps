#!/usr/bin/env python3
"""Repeatable CPU, main-thread stall and Instruments captures for the Apple apps.

One command launches the app on a page, lets it settle, then measures:

- **CPU**: the process's ``ps -o time`` delta over ``--duration`` seconds, split into
  ``--interval`` windows (one core = 100%). The Mac window must be visible: AppKit
  occlusion pauses every decoration, so a covered window reads ~0%.
- **Stalls** (``--stress``): the in-app Songs scroll stress pass
  (``FST_DEBUG_SONGS_SCROLL_STRESS=1``) with ``MainThreadStallMonitor``
  (``FST_DEBUG_STALL_LOG``); only units of main-thread work between the pass's start
  and end marks are counted, so launch work is excluded.
- **Instruments** (``--trace TEMPLATE``, Mac only: xctrace cannot attach to
  simulator apps on this host): ``xcrun xctrace record --attach <pid>`` for
  the measuring window (e.g. ``'Time Profiler'``, ``'Animation Hitches'``,
  ``'SwiftUI'``); ``--top N`` prints the heaviest symbols of a Time Profiler trace.

Build flavours (``build``):

- ``Debug``: the normal developer build.
- ``Release``: optimized, ignores every ``FST_DEBUG_*`` override (opens on the
  persisted page and profile); CPU only.
- ``Release --probe``: Release optimization (``-O``, whole module) with the ``DEBUG``
  compilation condition, into its own DerivedData, so the Debug launch overrides,
  stall monitor and stress pass work on optimized code. Never ship it.

Targets: ``mac`` (``FestivalDesktop``; one instance per host, shares
``tools/mac_app.py``'s pid file) and ``ipad`` (the product ``ios_sim.py`` runs on the
FST iPad simulator, under ``tools/ios_sim.py``'s global simulator lock; the app process is a
host process, so ``ps`` samples it directly).

Examples::

    python3 tools/apple_perf.py build mac --configuration Release --probe
    python3 tools/apple_perf.py mac --tab songs --profile sfentonx
    python3 tools/apple_perf.py mac --configuration Release --probe --stress
    python3 tools/apple_perf.py mac --trace 'Time Profiler' --top 25
    python3 tools/apple_perf.py ipad --tab songs --stress
"""

from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ios_sim  # noqa: E402  (sibling tool)
import mac_app  # noqa: E402  (sibling tool)

# region Configuration

REPO_ROOT = Path(__file__).resolve().parent.parent
APPLE_DIR = REPO_ROOT / "apple"
DEVELOPER_DIR = "/Applications/Xcode.app/Contents/Developer"
#: Where traces and stall logs go unless ``--out-dir`` says otherwise.
DEFAULT_OUT = APPLE_DIR / "DerivedData" / "perf"
#: Stalls at or above this many milliseconds count as failures.
STALL_THRESHOLD_MS = 100.0
#: ``MainThreadStallMonitor`` counters written by ``SongsScrollStress``.
STRESS_START = "songs.stress.start"
STRESS_END = "songs.stress.end"
#: xcodebuild overrides for the probe flavour (Release code generation, Debug hooks).
PROBE_SETTINGS = ["SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG"]

# endregion

# region Pure helpers


def parse_cpu_time(text: str) -> float:
    """Parse ``ps -o time`` output (``[[dd-]hh:]mm:ss[.ss]``) into seconds.

    Args:
        text: One ``ps`` time field.

    Returns:
        Cumulative CPU seconds.

    Raises:
        ValueError: Unparseable text.
    """
    raw = text.strip()
    days = 0
    if "-" in raw:
        day_text, raw = raw.split("-", 1)
        days = int(day_text)
    parts = [float(p) for p in raw.split(":")]
    if not parts or len(parts) > 3:
        raise ValueError(f"unexpected cpu time {text!r}")
    seconds = 0.0
    for part in parts:
        seconds = seconds * 60 + part
    return days * 86400 + seconds


def cpu_percent(cpu_delta: float, wall_delta: float) -> float:
    """CPU use over a window, one core = 100%.

    Args:
        cpu_delta: CPU seconds consumed.
        wall_delta: Wall seconds elapsed.

    Returns:
        Percentage rounded to 0.1 (0 for an empty window).
    """
    if wall_delta <= 0:
        return 0.0
    return round(100.0 * cpu_delta / wall_delta, 1)


def summarize_cpu(windows: list[float]) -> dict:
    """Summarize per-window CPU percentages.

    Args:
        windows: One percentage per sampling window.

    Returns:
        ``mean``, ``median``, ``min``, ``max`` and the raw ``windows``.
    """
    if not windows:
        return {"mean": 0.0, "median": 0.0, "min": 0.0, "max": 0.0, "windows": []}
    return {
        "mean": round(statistics.fmean(windows), 1),
        "median": round(statistics.median(windows), 1),
        "min": min(windows),
        "max": max(windows),
        "windows": windows,
    }


def summarize_stalls(report: dict, threshold_ms: float = STALL_THRESHOLD_MS,
                     start: str = STRESS_START, end: str = STRESS_END) -> dict:
    """Count main-thread stalls inside a marked pass.

    Args:
        report: ``MainThreadStallReport`` JSON.
        threshold_ms: Minimum unit length that counts.
        start: Counter whose first mark opens the window.
        end: Counter whose first mark closes it (open-ended when missing).

    Returns:
        ``count``, ``worst_ms``, ``completed`` and the ``stalls`` inside the window.
        Without marks (an older report) every listed stall counts.
    """
    marks = report.get("marks") or {}
    lo = marks.get(start, float("-inf"))
    # A stall is stamped when it ends, so allow its own length past the end mark.
    hi = marks.get(end, float("inf"))
    stalls = [
        s for s in report.get("stalls", [])
        if s.get("ms", 0) >= threshold_ms and lo <= s.get("at", 0) <= hi + s.get("ms", 0) / 1000
    ]
    cpu = report.get("cpuMarks") or {}
    counters = report.get("counters") or {}
    main_cpu = round(cpu[end] - cpu[start], 3) if start in cpu and end in cpu else None
    return {
        "count": len(stalls),
        "worst_ms": max((s["ms"] for s in stalls), default=0.0),
        "completed": end in counters,
        # Main-thread CPU seconds inside the pass: robust to host load, unlike stalls.
        "main_cpu_s": main_cpu,
        "rows_built": counters.get("songs.row"),
        "stalls": stalls,
    }


def parse_launch_pid(text: str) -> int | None:
    """Pid from ``simctl launch`` output (``<bundle>: <pid>``).

    Args:
        text: Command output.

    Returns:
        The pid, or None when absent.
    """
    match = re.search(r":\s*(\d+)\s*$", text.strip())
    return int(match.group(1)) if match else None


def ipad_product() -> "ios_sim.AppProduct":
    """The app product ``ios_sim.py`` runs on the iPad simulator.

    Returns:
        ``ios_sim.PRODUCTS`` entry for the ``ipad`` device alias (the universal app
        once the iPad target is merged into it).
    """
    return ios_sim.PRODUCTS[ios_sim.DEVICE_PRODUCTS.get("ipad", "phone")]


def derived_data(target: str, probe: bool) -> Path:
    """DerivedData for a target and flavour (probe builds never overwrite normal ones).

    Args:
        target: ``mac`` or ``ipad``.
        probe: Release with Debug hooks.

    Returns:
        A worktree-local DerivedData folder.
    """
    base = {"mac": "mac", "ipad": "lane"}[target]
    return APPLE_DIR / "DerivedData" / (f"{base}-probe" if probe else base)


def app_bundle(target: str, configuration: str, probe: bool) -> Path:
    """Built app bundle for a target and flavour.

    Args:
        target: ``mac`` or ``ipad``.
        configuration: Xcode configuration.
        probe: Release with Debug hooks.

    Returns:
        The ``.app`` path.
    """
    products = derived_data(target, probe) / "Build" / "Products"
    if target == "mac":
        return products / configuration / "FestivalDesktop.app"
    return products / f"{configuration}-iphonesimulator" / f"{ipad_product().app_name}.app"


def build_argv(target: str, configuration: str, probe: bool) -> list[str]:
    """``xcodebuild`` invocation for a target and flavour.

    Args:
        target: ``mac`` or ``ipad``.
        configuration: Xcode configuration.
        probe: Add ``PROBE_SETTINGS``.

    Returns:
        Argument vector, run from ``apple/``.
    """
    scheme, destination = {
        "mac": ("FestivalDesktop", "platform=macOS"),
        "ipad": (ipad_product().scheme, "generic/platform=iOS Simulator"),
    }[target]
    argv = [
        "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", scheme,
        "-configuration", configuration, "-destination", destination,
        "-derivedDataPath", str(derived_data(target, probe)), "build", "-quiet",
    ]
    return argv + (PROBE_SETTINGS if probe else [])


def parse_time_profile(xml_text: str) -> list[tuple[str, list[tuple[str, str]]]]:
    """Samples of an ``xctrace export`` time-profile table.

    Each ``<row>`` is one sample with a thread and a ``<backtrace>`` or
    ``<tagged-backtrace>`` listing frames leaf first. Threads, backtraces, frames and
    binaries after their first appearance are back-references (``ref=``) to an ``id``.

    Args:
        xml_text: Export of ``/trace-toc/run/data/table[@schema="time-profile"]``.

    Returns:
        ``(thread, [(symbol, binary), ...])`` per sample, frames leaf first.
    """
    root = ET.fromstring(xml_text)
    binaries: dict[str, str] = {}
    frames: dict[str, tuple[str, str]] = {}
    stacks: dict[str, list[tuple[str, str]]] = {}
    threads: dict[str, str] = {}

    def frame_value(frame: ET.Element) -> tuple[str, str]:
        if frame.get("ref"):
            return frames.get(frame.get("ref"), ("?", ""))
        binary = frame.find("binary")
        name = ""
        if binary is not None:
            if binary.get("ref"):
                name = binaries.get(binary.get("ref"), "")
            else:
                name = binary.get("name", "")
                binaries[binary.get("id", "")] = name
        value = (frame.get("name") or frame.get("addr") or "?", name)
        frames[frame.get("id", "")] = value
        return value

    samples = []
    for row in root.iter("row"):
        thread_el = row.find("thread")
        thread = ""
        if thread_el is not None:
            if thread_el.get("ref"):
                thread = threads.get(thread_el.get("ref"), "")
            else:
                thread = thread_el.get("fmt", "")
                threads[thread_el.get("id", "")] = thread
        stack_el = row.find("tagged-backtrace")
        if stack_el is None:
            stack_el = row.find("backtrace")
        if stack_el is None:
            continue
        if stack_el.get("ref"):
            stack = stacks.get(stack_el.get("ref"), [])
        else:
            stack = [frame_value(f) for f in stack_el.iter("frame")]
            stacks[stack_el.get("id", "")] = stack
        samples.append((thread, stack))
    return samples


def top_symbols(samples: list[tuple[str, list[tuple[str, str]]]], limit: int = 25,
                app_only: bool = False, main_only: bool = False) -> list[tuple[str, int]]:
    """Heaviest symbols of parsed time-profile samples.

    Args:
        samples: ``parse_time_profile`` output.
        limit: Symbols to return.
        app_only: Attribute each sample to its first frame from the app's own
            modules (``Festival*``) instead of the leaf; samples without one are skipped.
        main_only: Only main-thread samples.

    Returns:
        ``(symbol, samples)`` pairs, heaviest first.
    """
    counts: Counter[str] = Counter()
    for thread, stack in samples:
        if main_only and not thread.startswith("Main Thread"):
            continue
        for name, binary in stack:
            if not app_only or binary.startswith("Festival"):
                counts[name] += 1
                break
    return counts.most_common(limit)

# endregion

# region Process helpers


def _env() -> dict[str, str]:
    env = dict(os.environ)
    env["DEVELOPER_DIR"] = DEVELOPER_DIR
    return env


def _run(cmd: list[str], check: bool = True, **kw) -> subprocess.CompletedProcess:
    print("+", " ".join(cmd), file=sys.stderr)
    return subprocess.run(cmd, check=check, env=kw.pop("env", _env()), **kw)


def cpu_seconds(pid: int) -> float | None:
    """Cumulative CPU seconds of a live process.

    Args:
        pid: Process id.

    Returns:
        Seconds, or None when the process is gone.
    """
    result = subprocess.run(["ps", "-o", "time=", "-p", str(pid)], capture_output=True, text=True)
    if result.returncode != 0 or not result.stdout.strip():
        return None
    return parse_cpu_time(result.stdout)


def rss_mb(pid: int) -> float | None:
    """Resident memory of a live process in MB."""
    result = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True)
    try:
        return round(int(result.stdout.strip()) / 1024, 1)
    except ValueError:
        return None


def sample_cpu(pid: int, duration: float, interval: float) -> dict:
    """Sample a process's CPU in consecutive windows.

    Args:
        pid: Process id.
        duration: Total seconds.
        interval: Window length.

    Returns:
        ``summarize_cpu`` output plus ``rss_mb``.
    """
    windows: list[float] = []
    last_cpu = cpu_seconds(pid)
    last_wall = time.monotonic()
    end = last_wall + duration
    while last_cpu is not None and time.monotonic() < end:
        time.sleep(interval)
        cpu, wall = cpu_seconds(pid), time.monotonic()
        if cpu is None:
            break
        windows.append(cpu_percent(cpu - last_cpu, wall - last_wall))
        last_cpu, last_wall = cpu, wall
    summary = summarize_cpu(windows)
    summary["rss_mb"] = rss_mb(pid)
    return summary


def wait_for_stress(log: Path, timeout: float) -> dict:
    """Poll a stall log until the stress pass's end mark appears.

    Args:
        log: ``FST_DEBUG_STALL_LOG`` path.
        timeout: Seconds before giving up (the partial report is returned).

    Returns:
        The last report read (empty when none was written).
    """
    deadline = time.monotonic() + timeout
    report: dict = {}
    while time.monotonic() < deadline:
        try:
            report = json.loads(log.read_text())
        except (OSError, json.JSONDecodeError):
            pass
        if STRESS_END in (report.get("counters") or {}):
            time.sleep(1.0)  # let the final units land
            try:
                report = json.loads(log.read_text())
            except (OSError, json.JSONDecodeError):
                pass
            break
        time.sleep(0.5)
    return report


def trace_argv(pid: int | str, template: str, seconds: float, out: Path, device: str | None) -> list[str]:
    """``xctrace record`` invocation attached to a process.

    Args:
        pid: Process id (or name).
        template: xctrace template name.
        seconds: Time limit.
        out: ``.trace`` destination.
        device: Simulator UDID for an iPad process, or None for this Mac.

    Returns:
        Argument vector.
    """
    argv = ["xcrun", "xctrace", "record", "--template", template, "--attach", str(pid),
            "--time-limit", f"{int(seconds)}s", "--output", str(out), "--no-prompt"]
    if device:
        argv[3:3] = ["--device", device]
    return argv


def start_trace(pid: int | str, template: str, seconds: float, out: Path, device: str | None) -> subprocess.Popen:
    """Attach Instruments to a running process in the background.

    Args:
        pid: Process id.
        template: xctrace template name.
        seconds: Time limit.
        out: ``.trace`` destination (replaced).
        device: Simulator UDID for an iPad process, or None for this Mac.

    Returns:
        The running ``xctrace`` process; ``wait()`` for the trace to be written.
    """
    if out.exists():
        subprocess.run(["rm", "-rf", str(out)], check=False)
    out.parent.mkdir(parents=True, exist_ok=True)
    argv = trace_argv(pid, template, seconds, out, device)
    print("+", " ".join(argv), file=sys.stderr)
    log = open(out.with_suffix(".log"), "w")
    return subprocess.Popen(argv, env=_env(), stdout=log, stderr=subprocess.STDOUT)


def print_top(trace: Path, limit: int) -> dict:
    """Export a Time Profiler trace and list its heaviest leaf and app symbols."""
    result = subprocess.run(
        ["xcrun", "xctrace", "export", "--input", str(trace), "--xpath",
         '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'],
        capture_output=True, text=True, env=_env(),
    )
    if result.returncode != 0 or "<row" not in result.stdout:
        print(f"no time-profile table in {trace}", file=sys.stderr)
        return {}
    samples = parse_time_profile(result.stdout)
    leaf = top_symbols(samples, limit)
    app = top_symbols(samples, limit, app_only=True)
    total = len(samples)
    main = sum(1 for thread, _ in samples if thread.startswith("Main Thread"))
    print(f"\n{total} samples ({main} main thread). Heaviest leaf symbols:")
    for name, count in leaf:
        print(f"  {count:6d}  {100 * count / total:5.1f}%  {name}")
    print("Heaviest first app frame:")
    for name, count in app:
        print(f"  {count:6d}  {100 * count / total:5.1f}%  {name}")
    return {"samples": total, "leaf": leaf, "app": app}

# endregion

# region Commands


def cmd_build(args: argparse.Namespace) -> int:
    configuration = "Release" if args.probe else args.configuration
    _run(["xcodegen", "generate", "-q"], cwd=APPLE_DIR)
    mac_app.BUILD_LOCK_PATH.touch(exist_ok=True)
    import fcntl
    with open(mac_app.BUILD_LOCK_PATH, "w") as lock:
        print(f"waiting for build lock {mac_app.BUILD_LOCK_PATH} ...", file=sys.stderr)
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            result = _run(build_argv(args.target, configuration, args.probe), cwd=APPLE_DIR, check=False)
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)
    return result.returncode


def _measure(args: argparse.Namespace, pid: int, stall_log: Path | None, device: str | None) -> dict:
    """Settle, then CPU (or stress) and an optional trace; shared by both targets."""
    result: dict = {"pid": pid}
    out = Path(args.out_dir).expanduser() / f"{args.label or args.target}-{(args.trace or '').replace(' ', '')}.trace"
    tracer = None
    if args.stress and stall_log:
        # With --trace the recording covers the stress pass itself (--duration long
        # enough for the pass; it starts ~3 s after the list loads).
        if args.trace:
            tracer = start_trace(pid, args.trace, args.duration, out, device)
        report = wait_for_stress(stall_log, args.stress_timeout)
        result["stress"] = summarize_stalls(report)
        result["stress"]["max_awake_ms"] = report.get("maxAwakeMs")
    else:
        time.sleep(args.settle)
        if args.trace:
            tracer = start_trace(pid, args.trace, args.duration, out, device)
        else:
            result["cpu"] = sample_cpu(pid, args.duration, args.interval)
    if tracer is not None:
        tracer.wait()
        result["trace"] = str(out)
        if args.top and args.trace == "Time Profiler":
            result["top"] = print_top(out, args.top)
    return result


def _report(args: argparse.Namespace, result: dict) -> int:
    result.update({"target": args.target, "configuration": args.configuration, "probe": args.probe,
                   "tab": args.tab, "route": args.route, "label": args.label})
    text = json.dumps(result, indent=2, default=str)
    print(text)
    if args.json:
        Path(args.json).expanduser().write_text(text + "\n")
    return 0


def cmd_mac(args: argparse.Namespace) -> int:
    configuration = "Release" if args.probe else args.configuration
    bundle = app_bundle("mac", configuration, args.probe)
    if not bundle.exists():
        print(f"No build at {bundle}; run `apple_perf.py build mac` first.", file=sys.stderr)
        return 1
    mac_app.cmd_quit(argparse.Namespace(timeout=5.0))
    extra = list(args.env or [])
    stall_log = None
    if args.stress:
        stall_log = Path(args.out_dir).expanduser() / f"{args.label or 'mac'}-stalls.json"
        stall_log.parent.mkdir(parents=True, exist_ok=True)
        stall_log.unlink(missing_ok=True)
        extra += ["FST_DEBUG_SONGS_SCROLL_STRESS=1", f"FST_DEBUG_STALL_LOG={stall_log}"]
    env = mac_app.launch_environment(
        mac_app._env(), tab=args.tab, route=args.route, profile=mac_app.resolve_profile(args.profile),
        size=mac_app.parse_size(args.size) if args.size else None, extra=extra,
    )
    log_path = DEFAULT_OUT / "mac-app.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with open(log_path, "w") as log:
        process = subprocess.Popen(mac_app.launch_argv(bundle), env=env, stdout=log,
                                   stderr=subprocess.STDOUT, start_new_session=True)
    mac_app.PID_PATH.write_text(f"{process.pid} {REPO_ROOT}\n")
    if mac_app.wait_for_window(process.pid, 30) is None:
        print(f"no window (log: {log_path})", file=sys.stderr)
        return 1
    try:
        result = _measure(args, process.pid, stall_log, None)
    finally:
        if not args.keep:
            mac_app.cmd_quit(argparse.Namespace(timeout=5.0))
    return _report(args, result)


def cmd_ipad(args: argparse.Namespace) -> int:
    import fcntl

    if args.trace:
        # Xcode 27.1: `xctrace record --attach` finds no simulator app, by host pid
        # ("Cannot find process for provided pid") or by name with `--device`.
        print("--trace is Mac-only: xctrace cannot attach to simulator apps on this host; "
              "profile the shared SwiftUI code with `apple_perf.py mac --trace`.", file=sys.stderr)
        return 2

    configuration = "Release" if args.probe else args.configuration
    bundle = app_bundle("ipad", configuration, args.probe)
    if not bundle.exists():
        print(f"No build at {bundle}; run `apple_perf.py build ipad` first.", file=sys.stderr)
        return 1
    udid = ios_sim.resolve_device(args.device)
    bundle_id = ipad_product().bundle_id
    stall_log = None
    launch_env = _env()
    if args.tab:
        launch_env["SIMCTL_CHILD_FST_DEBUG_TAB"] = args.tab
    if args.route:
        launch_env["SIMCTL_CHILD_FST_DEBUG_ROUTE"] = args.route
    if args.profile:
        launch_env["SIMCTL_CHILD_FST_DEBUG_PROFILE"] = mac_app.resolve_profile(args.profile)
    for pair in args.env or []:
        key, _, value = pair.partition("=")
        launch_env[f"SIMCTL_CHILD_{key}"] = value
    if args.stress:
        stall_log = Path(args.out_dir).expanduser() / f"{args.label or 'ipad'}-stalls.json"
        stall_log.parent.mkdir(parents=True, exist_ok=True)
        stall_log.unlink(missing_ok=True)
        launch_env["SIMCTL_CHILD_FST_DEBUG_SONGS_SCROLL_STRESS"] = "1"
        launch_env["SIMCTL_CHILD_FST_DEBUG_STALL_LOG"] = str(stall_log)
    ios_sim.LOCK_PATH.touch(exist_ok=True)
    with open(ios_sim.LOCK_PATH, "w") as lock:
        print(f"waiting for simulator lock {ios_sim.LOCK_PATH} ...", file=sys.stderr)
        fcntl.flock(lock, fcntl.LOCK_EX)
        lock.write(f"{os.getpid()} {REPO_ROOT}\n")
        lock.flush()
        ios_sim.boot_exclusive(udid)
        _run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True)
        _run(["xcrun", "simctl", "install", udid, str(bundle)])
        _run(["xcrun", "simctl", "terminate", udid, bundle_id], check=False, capture_output=True)
        launched = _run(["xcrun", "simctl", "launch", udid, bundle_id], env=launch_env,
                        capture_output=True, text=True)
        pid = parse_launch_pid(launched.stdout)
        if pid is None:
            print(f"could not read the app pid from {launched.stdout!r}", file=sys.stderr)
            return 1
        try:
            result = _measure(args, pid, stall_log, udid)
        finally:
            _run(["xcrun", "simctl", "terminate", udid, bundle_id], check=False, capture_output=True)
    return _report(args, result)


def _add_measure_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--configuration", default="Debug", choices=["Debug", "Release"])
    parser.add_argument("--probe", action="store_true", help="Release optimization with Debug hooks")
    parser.add_argument("--tab", help="FST_DEBUG_TAB (Debug/probe only)")
    parser.add_argument("--route", help="FST_DEBUG_ROUTE (Debug/probe only)")
    parser.add_argument("--profile", default="sfentonx", help="'sfentonx', accountId:name, or '' for none")
    parser.add_argument("--env", action="append", help="Extra KEY=VALUE launch environment")
    parser.add_argument("--settle", type=float, default=20.0, help="Seconds before measuring")
    parser.add_argument("--duration", type=float, default=20.0, help="Seconds of CPU sampling / tracing")
    parser.add_argument("--interval", type=float, default=2.0, help="CPU window length")
    parser.add_argument("--stress", action="store_true", help="Run the Songs scroll stress pass and count stalls")
    parser.add_argument("--stress-timeout", type=float, default=150.0)
    parser.add_argument("--trace", help="xctrace template, e.g. 'Time Profiler', 'Animation Hitches', 'SwiftUI'")
    parser.add_argument("--top", type=int, default=0, help="With 'Time Profiler': print the N heaviest symbols")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT))
    parser.add_argument("--label", help="Name for output files and the JSON record")
    parser.add_argument("--json", help="Also write the result JSON here")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    build = sub.add_parser("build", help="Build a target in a flavour")
    build.add_argument("target", choices=["mac", "ipad"])
    build.add_argument("--configuration", default="Debug", choices=["Debug", "Release"])
    build.add_argument("--probe", action="store_true", help="Release optimization with Debug hooks")
    build.set_defaults(func=cmd_build)

    mac = sub.add_parser("mac", help="Measure the Mac app")
    _add_measure_args(mac)
    mac.add_argument("--size", default="1280x820", help="Window content size (Debug/probe only)")
    mac.add_argument("--keep", action="store_true", help="Leave the app running")
    mac.set_defaults(func=cmd_mac, target="mac")

    ipad = sub.add_parser("ipad", help="Measure the iPad app in the simulator")
    _add_measure_args(ipad)
    ipad.add_argument("--device", default="ipad")
    ipad.set_defaults(func=cmd_ipad, target="ipad")

    args = parser.parse_args(argv)
    if getattr(args, "profile", None) == "":
        args.profile = None
    try:
        return args.func(args)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

# endregion
