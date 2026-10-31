#!/usr/bin/env python3
"""Summarises a ``tools/uikit_perf.py`` run directory into Markdown tables (SwiftUI app against the UIKit port).

    uikit_perf_report.py apple/build/perf/<label> [--csv FILE]

Three tables, medians over rounds:

- **Scroll** per surface and kind (``idle``: 8 s standing still; ``scroll``: two 8 s sweeps at 900 pt/s per round): the
  in-app numbers (``FramePacer``, ``MainThreadCostMeter``) and the host numbers matched to each run's wall-clock window
  (``perf_sampler.py``): Mac GPU utilisation and the simulator render server's CPU time.
- **Launch** per surface: process start to first content, and the CPU and memory used by the end of the settle time.
- **Navigation** per scenario: push and pop timing and main-thread turn costs.
"""
from __future__ import annotations

import argparse
import csv
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

#: ``r<round>-<app>-<safe surface name>.tsv``.
FILE = re.compile(r"r(\d+)-(swiftui|uikit)-(.+)\.tsv$")
APPS = ("swiftui", "uikit")
APP_LABEL = {"swiftui": "SwiftUI", "uikit": "UIKit"}

#: (key, header, format) of the scroll table, after Surface | Kind | App | n.
SCROLL_COLUMNS = [
    ("fps", "fps", "%.1f"), ("dropped", "dropped frames", "%.0f"), ("hitch_ms_per_s", "hitch ms/s", "%.1f"),
    ("p95_ms", "main p95 ms", "%.2f"), ("over8", "turns >8 ms", "%.0f"), ("main_ms", "main CPU ms", "%.0f"),
    ("cpu_ms", "process CPU ms", "%.0f"), ("render_ms", "render server CPU ms", "%.0f"),
    ("gpu_pct", "Mac GPU %", "%.0f"), ("mem_mb", "memory MB", "%.1f"), ("peak_mb", "peak MB", "%.1f"),
]
LAUNCH_COLUMNS = [
    ("first_content_ms", "first content ms", "%.0f"), ("ready_ms", "launch code ms", "%.0f"),
    ("cpu_ms", "CPU ms at settle", "%.0f"), ("instr_m", "Minstr at settle", "%.0f"), ("mem_mb", "memory MB", "%.1f"),
]
NAV_COLUMNS = [
    ("cold_first_ms", "cold first ms", "%.0f"), ("first_p50_ms", "first p50 ms", "%.0f"), ("first_p95_ms", "first p95 ms", "%.0f"),
    ("settled_p50_ms", "settled p50 ms", "%.0f"), ("settled_p95_ms", "settled p95 ms", "%.0f"),
    ("turn_p95_ms", "turn p95 ms", "%.2f"), ("turn_worst_ms", "turn worst ms", "%.1f"), ("over8", "turns >8 ms", "%.0f"),
    ("main_ms", "main CPU ms", "%.0f"), ("cpu_ms", "process CPU ms", "%.0f"),
]

# region Parsing


def parse_samples(text: str) -> list[dict]:
    """Parse a ``perf_sampler.py`` file.

    Args:
        text: File contents (header line first).

    Returns:
        One dict per tick: ``t``, ``gpu``, ``renderer``, ``bb`` (render server CPU s), ``app`` (app CPU s), ``rss``;
        missing values are None.
    """
    rows = []
    for line in text.splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) < 7:
            continue

        def num(value: str):
            return float(value) if value not in ("", "-1") else None

        rows.append(dict(t=float(parts[0]), gpu=num(parts[1]), renderer=num(parts[2]), bb=num(parts[4]),
                         app=num(parts[5]), rss=num(parts[6])))
    return rows


def at(rows: list[dict], key: str, t: float):
    """Linear interpolation of a cumulative counter at time ``t`` (None when the counter has no points)."""
    points = [(r["t"], r[key]) for r in rows if r[key] is not None]
    if not points:
        return None
    if t <= points[0][0]:
        return points[0][1]
    for (t0, v0), (t1, v1) in zip(points, points[1:]):
        if t0 <= t <= t1:
            return v0 + (v1 - v0) * (t - t0) / max(t1 - t0, 1e-6)
    return points[-1][1]


def window(rows: list[dict], key: str, t0: float, t1: float):
    """Mean of a gauge over ``[t0, t1]`` (None when no sample falls inside)."""
    values = [r[key] for r in rows if r[key] is not None and t0 <= r["t"] <= t1]
    return statistics.mean(values) if values else None


def parse_pairs(summary: str) -> dict[str, float]:
    """The numeric ``key=value`` pairs of a result line's summary."""
    pairs = (kv.split("=", 1) for kv in summary.split() if "=" in kv)
    return {k: float(v) for k, v in pairs if re.fullmatch(r"-?\d+(\.\d+)?", v)}


def parse_run(text: str) -> list[tuple[str, str, str]]:
    """Parse one run's result file.

    Args:
        text: File contents.

    Returns:
        ``(name, kind, summary)`` for every ``FSTPERF`` line.
    """
    rows = []
    for line in text.splitlines():
        parts = line.split("\t")
        if len(parts) >= 4 and parts[0] == "FSTPERF":
            rows.append((parts[1], parts[2], parts[3]))
    return rows


def scroll_metrics(summary: str, host: list[dict]) -> dict:
    """Merge a scroll/idle line's in-app numbers with the host samples of its window.

    Args:
        summary: The line's ``key=value`` text.
        host: ``parse_samples`` rows of the same run.

    Returns:
        Metrics, with ``render_ms``, ``gpu_pct`` and ``gpu_renderer_pct`` added (NaN when the host has no samples), or
        ``{"error": text}`` when the line carries no timing window.
    """
    values = parse_pairs(summary)
    if "t0" not in values:
        return {"error": summary[:80]}
    t0, t1 = values["t0"], values["t1"]
    bb0, bb1 = at(host, "bb", t0), at(host, "bb", t1)
    values["render_ms"] = (bb1 - bb0) * 1000 if bb0 is not None and bb1 is not None else float("nan")
    for key, name in (("gpu", "gpu_pct"), ("renderer", "gpu_renderer_pct")):
        mean = window(host, key, t0, t1)
        values[name] = mean if mean is not None else float("nan")
    return values


def collect(directory: Path) -> dict:
    """Read every run file of a directory.

    Args:
        directory: A ``uikit_perf.py`` results folder.

    Returns:
        ``{"order": [names], "runs": {(name, kind, app): [metrics]}}``.
    """
    runs: dict = defaultdict(list)
    order: list[str] = []
    for path in sorted(directory.glob("r*-*.tsv")):
        match = FILE.match(path.name)
        if path.name.endswith(".samples.tsv") or not match:
            continue
        app = match.group(2)
        sample_path = path.with_name(path.name[:-4] + ".samples.tsv")
        host = parse_samples(sample_path.read_text()) if sample_path.exists() else []
        for name, kind, summary in parse_run(path.read_text()):
            if name not in order:
                order.append(name)
            if kind in ("idle", "scroll"):
                runs[(name, kind, app)].append(scroll_metrics(summary, host))
            else:
                pairs = parse_pairs(summary)
                runs[(name, kind, app)].append(pairs if pairs else {"error": summary[:80]})
    return {"order": order, "runs": runs}

# endregion

# region Tables


def median_row(data: list[dict], columns: list) -> tuple[list[str], dict]:
    """Medians of the columns over the good runs.

    Args:
        data: Metrics of the runs of one cell.
        columns: ``(key, header, format)`` triples.

    Returns:
        The formatted cells ("–" where nothing was measured) and the raw medians.
    """
    cells, raw = [], {}
    for key, _, fmt in columns:
        values = [m[key] for m in data if key in m and m[key] == m[key]]
        value = statistics.median(values) if values else None
        raw[key] = value
        cells.append(fmt % value if value is not None else "–")
    return cells, raw


def table(title: str, kinds: tuple[str, ...], columns: list, collected: dict, kind_column: bool) -> tuple[list[str], list[dict]]:
    """One Markdown table.

    Args:
        title: First column header.
        kinds: Result kinds shown (rows per surface, in this order).
        columns: Metric columns.
        collected: ``collect`` output.
        kind_column: Whether to print the kind as a column.

    Returns:
        Markdown lines (empty when nothing was measured) and the raw rows for the CSV.
    """
    lines, rows = [], []
    for name in collected["order"]:
        for kind in kinds:
            for app in APPS:
                cell = collected["runs"].get((name, kind, app), [])
                data = [m for m in cell if "error" not in m]
                errors = [m for m in cell if "error" in m]
                if not data:
                    if errors:
                        prefix = f"| {name} | " + (f"{kind} | " if kind_column else "")
                        lines.append(prefix + f"{APP_LABEL[app]} | 0 | " + errors[0]["error"].replace("|", "/") + " |")
                    continue
                cells, raw = median_row(data, columns)
                rows.append({"table": title, "surface": name, "kind": kind, "app": app, "n": len(data), **raw})
                prefix = f"| {name} | " + (f"{kind} | " if kind_column else "")
                lines.append(prefix + f"{APP_LABEL[app]} | {len(data)} | " + " | ".join(cells) + " |")
    if not lines:
        return [], rows
    head = f"| {title} | " + ("Kind | " if kind_column else "") + "App | n | " + " | ".join(c[1] for c in columns) + " |"
    rule = "|" + "---|" * ((4 if kind_column else 3) + len(columns))
    return [head, rule, *lines], rows


def render(collected: dict) -> tuple[str, list[dict]]:
    """The whole report.

    Args:
        collected: ``collect`` output.

    Returns:
        Markdown text and the raw rows.
    """
    out: list[str] = []
    all_rows: list[dict] = []
    for heading, title, kinds, columns, kind_column in (
        ("Scroll and idle", "Surface", ("idle", "scroll"), SCROLL_COLUMNS, True),
        ("Cold launch (fresh install, to first content)", "Surface", ("launch",), LAUNCH_COLUMNS, False),
        ("Navigation (push and pop, simulator CPU)", "Scenario", ("push", "pop"), NAV_COLUMNS, True),
    ):
        lines, rows = table(title, kinds, columns, collected, kind_column)
        if lines:
            out += [f"### {heading}", "", *lines, ""]
        all_rows += rows
    return "\n".join(out), all_rows

# endregion


def main(argv: list[str] | None = None) -> int:
    """Print the report for a results directory.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        Exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("directory", type=Path)
    parser.add_argument("--csv", type=Path)
    args = parser.parse_args(argv)
    text, rows = render(collect(args.directory))
    print(text)
    if args.csv:
        fields = sorted({k for r in rows for k in r}, key=lambda k: (k not in ("table", "surface", "kind", "app", "n"), k))
        with open(args.csv, "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
