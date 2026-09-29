#!/usr/bin/env python3
"""Frame timing of one app scenario from ``dumpsys gfxinfo … framestats``.

Launches the app, resets its frame statistics, runs ``device.py drive`` steps
(scrolls, taps) or simply idles (animated background), then reads
``dumpsys gfxinfo <package> framestats`` and reports per-frame UI-thread and
total times, all inside one ``device.py`` emulator lock hold (≤300 s).

The FST emulators render with SwiftShader (CPU), so *total* frame times include
software GPU work and overstate a real device. The **UI-thread** time
(``HandleInputStart`` → ``SyncQueued``: input, animation, composition,
measure/layout and draw recording) is the app's own main-thread cost and is the
number to watch for per-frame recomposition or main-thread image decoding;
``wait`` (``Vsync`` → ``HandleInputStart``) is time the main thread spent on
other messages or starved of CPU before the frame started.

Usage::

    python tools/android/frame_stats.py --avd FST_Phone --apk app-debug.apk --tab songs \
        --extra FST_ORIGIN=http://10.0.2.2:8796 --name songs-scroll \
        --steps "swipe:up;swipe:up;swipe:up;swipe:down" --out C:/showcase/perf

Writes ``<out>/<name>.json`` (metrics) and ``<name>.txt`` (raw dumpsys) and
prints a one-line summary.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import device  # noqa: E402  (shared emulator tool beside this script)

# region Pure helpers

#: Frame budgets (ms) reported: 120 Hz and 60 Hz.
BUDGETS_MS = (8.33, 16.67)

#: Summary lines of ``dumpsys gfxinfo`` and their keys.
SUMMARY_KEYS = {
    "Total frames rendered": "frames",
    "Janky frames": "janky",
    "50th percentile": "p50_ms",
    "90th percentile": "p90_ms",
    "95th percentile": "p95_ms",
    "99th percentile": "p99_ms",
}


def parse_summary(text: str) -> dict[str, float]:
    """The first ``gfxinfo`` summary block (the app's own window stats)."""
    out: dict[str, float] = {}
    for line in text.splitlines():
        label, _, value = line.strip().partition(":")
        key = SUMMARY_KEYS.get(label.strip())
        if key and key not in out:
            number = value.strip().split()[0].rstrip("ms") if value.strip() else ""
            try:
                out[key] = float(number)
            except ValueError:
                continue
    return out


def parse_framestats(text: str) -> list[dict[str, int]]:
    """Rows of every ``---PROFILEDATA---`` block, keyed by the block's header names.

    Only frames with ``Flags == 0`` are kept (others are the first frame of a
    window, a layout-only pass, or otherwise not a normal frame).
    """
    rows: list[dict[str, int]] = []
    header: list[str] | None = None
    inside = False
    for line in text.splitlines():
        line = line.strip()
        if line == "---PROFILEDATA---":
            inside, header = not inside, None
            continue
        if not inside or not line:
            continue
        cells = [cell for cell in line.split(",") if cell != ""]
        if header is None:
            header = cells
            continue
        try:
            values = [int(cell) for cell in cells]
        except ValueError:
            continue
        row = dict(zip(header, values))
        if row.get("Flags", 1) == 0:
            rows.append(row)
    return rows


def merge_frames(seen: dict[int, dict[str, int]], rows: list[dict[str, int]]) -> None:
    """Add rows to ``seen`` keyed by ``IntendedVsync`` (framestats repeats recent frames)."""
    for row in rows:
        seen.setdefault(row.get("IntendedVsync", 0), row)


def percentile(values: list[float], fraction: float) -> float:
    """Nearest-rank percentile (0 for no values)."""
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, math.ceil(fraction * len(ordered)) - 1))
    return ordered[index]


def frame_metrics(rows: list[dict[str, int]]) -> dict[str, float]:
    """UI-thread and total frame-time percentiles plus over-budget counts.

    UI thread = ``SyncQueued - HandleInputStart`` (the frame's own main-thread work);
    ``wait`` = ``HandleInputStart - Vsync`` (the main thread was busy with other messages,
    such as lazy-list prefetch, or starved of CPU); total = ``FrameCompleted - IntendedVsync``
    (nanoseconds in the dump, milliseconds here).
    """
    ui = [(r["SyncQueued"] - r["HandleInputStart"]) / 1e6 for r in rows if r.get("SyncQueued", 0) > r.get("HandleInputStart", 0) > 0]
    total = [(r["FrameCompleted"] - r["IntendedVsync"]) / 1e6 for r in rows if r.get("FrameCompleted", 0) > r.get("IntendedVsync", 0) > 0]
    # UI-thread phases: input + animation callbacks (Compose recomposition runs in the
    # Choreographer animation phase), traversal (measure/layout), draw recording.
    phases = {
        "anim": ("HandleInputStart", "PerformTraversalsStart"),
        "layout": ("PerformTraversalsStart", "DrawStart"),
        "draw": ("DrawStart", "SyncQueued"),
        "wait": ("Vsync", "HandleInputStart"),
    }
    metrics: dict[str, float] = {"frames": float(len(rows))}
    for name, (start, end) in phases.items():
        values = [(r[end] - r[start]) / 1e6 for r in rows if r.get(end, 0) >= r.get(start, 0) > 0]
        metrics[f"{name}_p50_ms"] = round(percentile(values, 0.5), 2)
        metrics[f"{name}_p90_ms"] = round(percentile(values, 0.9), 2)
    for name, values in (("ui", ui), ("total", total)):
        for fraction in (0.5, 0.9, 0.99):
            metrics[f"{name}_p{int(fraction * 100)}_ms"] = round(percentile(values, fraction), 2)
        metrics[f"{name}_max_ms"] = round(max(values), 2) if values else 0.0
        for budget in BUDGETS_MS:
            metrics[f"{name}_over_{budget:g}ms"] = float(sum(1 for value in values if value > budget))
    return metrics


def summary_line(name: str, metrics: dict[str, float]) -> str:
    """One Markdown table row: name, frames, UI p50/p90/p99/max, UI over 8.33 ms, phase p90s, total p50/p90."""
    return (f"| {name} | {metrics['frames']:.0f} | {metrics['ui_p50_ms']} / {metrics['ui_p90_ms']} / "
            f"{metrics['ui_p99_ms']} / {metrics['ui_max_ms']} | {metrics['ui_over_8.33ms']:.0f} | "
            f"{metrics.get('anim_p90_ms', 0)} / {metrics.get('layout_p90_ms', 0)} / {metrics.get('draw_p90_ms', 0)} | "
            f"{metrics.get('wait_p50_ms', 0)} / {metrics.get('wait_p90_ms', 0)} | "
            f"{metrics['total_p50_ms']} / {metrics['total_p90_ms']} |")

# endregion

# region Run


def build_parser() -> argparse.ArgumentParser:
    """CLI options: ``device.py`` target/launch options plus the scenario."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--avd", default=device.DEFAULT_AVD, choices=sorted(device.AVDS))
    parser.add_argument("--hold", type=float, default=300.0)
    parser.add_argument("--wait-timeout", type=float, default=1800.0)
    parser.add_argument("--window", action="store_true")
    parser.add_argument("--gpu", default="swiftshader_indirect")
    parser.add_argument("--allow-foreign", action="store_true")
    parser.add_argument("--animations", action="store_true", help="keep system animations on (default scale 0)")
    parser.add_argument("--package", default=device.DEFAULT_PACKAGE)
    parser.add_argument("--activity")
    parser.add_argument("--tab")
    parser.add_argument("--route")
    parser.add_argument("--extra", action="append", metavar="KEY=VALUE")
    parser.add_argument("--posture")
    parser.add_argument("--apk")
    parser.add_argument("--name", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--wait", type=float, default=6.0, help="seconds after launch before measuring")
    parser.add_argument("--before", help="drive steps after launch, before the reset (e.g. open a page)")
    parser.add_argument("--steps", help="drive steps measured (scrolls, taps)")
    parser.add_argument("--idle", type=float, default=0.0, help="seconds to idle while measuring (after steps)")
    return parser


def run(args: argparse.Namespace) -> int:
    """Launch, measure and write the report."""
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    with device._lock(args, f"frame-stats {args.name} {args.avd}") as lock:
        dev = device._booted(args, lock)
        device._prepare(dev, args)
        device._launch(dev, args)
        time.sleep(args.wait)
        if args.before:
            for verb, arg in (device.parse_step(s) for s in device.parse_steps(args.before, None)):
                device.run_step(dev, args.avd, verb, arg)
        dev.shell(f"dumpsys gfxinfo {args.package} reset", check=False)
        # framestats only lists the most recent ~120 frames: sample after every step
        # (and every 1.5 s while idling) and merge by IntendedVsync.
        seen: dict[int, dict[str, int]] = {}

        def sample() -> str:
            text = dev.shell(f"dumpsys gfxinfo {args.package} framestats", cap=60, check=False)
            merge_frames(seen, parse_framestats(text))
            return text

        if args.steps:
            for verb, arg in (device.parse_step(s) for s in device.parse_steps(args.steps, None)):
                device.run_step(dev, args.avd, verb, arg)
                sample()
        deadline = time.monotonic() + args.idle
        while time.monotonic() < deadline:
            time.sleep(1.5)
            sample()
        raw = sample()
    metrics = {**frame_metrics(list(seen.values())), **{f"gfxinfo_{k}": v for k, v in parse_summary(raw).items()}}
    (out / f"{args.name}.txt").write_text(raw, encoding="utf-8")
    (out / f"{args.name}.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(summary_line(args.name, metrics))
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    return run(build_parser().parse_args(argv))

# endregion


if __name__ == "__main__":
    sys.exit(main())
