#!/usr/bin/env python3
"""Summarises a ``tools/uikit_perf.py`` run directory into Markdown tables (SwiftUI app against the UIKit port).

    uikit_perf_report.py apple/build/perf/<label> [--csv FILE]

Tables, medians and primary-signal ranges over rounds:

- **Scroll** per surface and kind (``idle``: 8 s standing still; ``scroll``: two 8 s sweeps at 900 pt/s per round): the
  in-app numbers (``FramePacer``, ``MainThreadCostMeter``) and the host numbers matched to each run's wall-clock window
  (``perf_sampler.py``): Mac GPU utilisation and the simulator render server's CPU time.
- **Launch** per surface: process start to first content, and the CPU and memory used by the end of the settle time.
- **Navigation** per scenario: push and pop timing and main-thread turn costs.
- **Modal/task and component** cases: the same first-frame/settled or first-frame timing, with missing hooks left incomplete.
- **Qualification**: hard gates for complete content, matched rounds, executed cases and minimum sample counts.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import statistics
import sys
from collections import defaultdict
from pathlib import Path

#: ``r<round>-<app>-<safe surface name>.tsv``.
FILE = re.compile(r"r(\d+)-(.+?)-(.+)\.tsv$")
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
COMPONENT_COLUMNS = [
    ("cold_first_ms", "cold first ms", "%.0f"), ("first_p50_ms", "first p50 ms", "%.0f"),
    ("first_p95_ms", "first p95 ms", "%.0f"), ("active_s", "active s", "%.2f"),
    ("cpu_ms", "process CPU ms", "%.0f"), ("main_ms", "main CPU ms", "%.0f"),
    ("p95_ms", "main p95 ms", "%.2f"), ("worst_ms", "main worst ms", "%.2f"),
    ("over8", "turns >8 ms", "%.0f"), ("fps", "fps", "%.1f"),
    ("dropped", "dropped frames", "%.0f"), ("hitch_ms_per_s", "hitch ms/s", "%.1f"),
    ("mem_mb", "memory MB", "%.1f"), ("peak_mb", "peak MB", "%.1f"),
    ("restored", "restored", "%.0f"),
]
LATENCY_COLUMNS = [
    ("cpu_ms", "process CPU ms", "%.0f"), ("main_ms", "main CPU ms", "%.0f"),
    ("mem_mb", "memory MB", "%.1f"), ("peak_mb", "peak MB", "%.1f"),
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
    for line in text.splitlines():
        if not line or line.startswith("#") or line.startswith("t\t"):
            continue
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
    files: dict[str, dict] = {}
    rounds: set[int] = set()
    manifest_path = directory / "manifest.json"
    manifest_apps = (
        json.loads(manifest_path.read_text()).get("apps", [])
        if manifest_path.exists() else []
    )
    for path in sorted(directory.glob("r*-*.tsv")):
        if path.name.endswith(".samples.tsv"):
            continue
        round_match = re.match(r"r(\d+)-(.+)\.tsv$", path.name)
        if not round_match:
            continue
        round_number = int(round_match.group(1))
        remainder = round_match.group(2)
        app = next(
            (label for label in sorted(manifest_apps, key=len, reverse=True)
             if remainder.startswith(f"{label}-")),
            None,
        )
        if app is None:
            match = FILE.match(path.name)
            if not match:
                continue
            app = match.group(2)
        rounds.add(round_number)
        raw = path.read_text()
        files[path.name] = {
            "round": round_number,
            "app": app,
            "complete": any(line.strip() == "FSTPERF_DONE" for line in raw.splitlines()),
            "names": sorted({row[0] for row in parse_run(raw)}),
        }
        if manifest_path.exists() and json.loads(manifest_path.read_text()).get("platform") == "physical-ios":
            files[path.name]["physical_context_failures"] = physical_context_failures(raw)
        sample_path = path.with_name(path.name[:-4] + ".samples.tsv")
        host = parse_samples(sample_path.read_text()) if sample_path.exists() else []
        for name, kind, summary in parse_run(raw):
            if name not in order:
                order.append(name)
            route = re.search(r"\broute=([^\s]+)", summary)
            if kind in ("idle", "scroll"):
                metrics = scroll_metrics(summary, host)
            else:
                if kind == "component" and summary.startswith("component did not settle:"):
                    metrics = {"error": summary[:80]}
                else:
                    pairs = parse_pairs(summary)
                    metrics = pairs if pairs else {"error": summary[:80]}
            metrics["_round"] = round_number
            metrics["_file"] = path.name
            if route:
                metrics["_route"] = route.group(1)
            runs[(name, kind, app)].append(metrics)
    apps = list(APPS)
    for app in sorted({record["app"] for record in files.values()}):
        if app not in apps:
            apps.append(app)
    return {"order": order, "runs": runs, "files": files, "rounds": sorted(rounds), "apps": apps}

# endregion

# region Qualification


def load_manifest(directory: Path) -> dict | None:
    """Load the run manifest, if the directory was produced by the full runner."""
    path = directory / "manifest.json"
    return json.loads(path.read_text()) if path.exists() else None


def physical_context_failures(text: str) -> list[str]:
    """Independently validate raw physical thermal, power and fixture context."""
    contexts = [summary for _, kind, summary in parse_run(text) if kind == "context"]
    start = [row for row in contexts if "phase=start " in row]
    end = [row for row in contexts if "phase=end " in row]
    failures = []
    if len(start) != 1 or len(end) != 1:
        failures.append("missing physical start/end context")
    for summary in contexts:
        values = parse_pairs(summary)
        if values.get("thermal", -1) != 0 or values.get("low_power", -1) != 0:
            failures.append("thermal not nominal or Low Power Mode enabled")
        if values.get("fixture_active") != 1 or values.get("fixture_misses", -1) != 0:
            failures.append("fixture inactive, unrecorded read or fixture startup failure")
        if "phase=end " in summary and values.get("maximum_hz", 0) <= 0:
            failures.append("display capability unavailable")
    return sorted(set(failures))


def qualify(collected: dict, manifest: dict | None) -> list[str]:
    """Return hard-gate failures for a run.

    A table can still be rendered for an incomplete baseline, but it is never
    considered qualified: every app/case/round must execute, content must be
    real, and every measured family must have at least three warm samples.
    """
    if manifest is None:
        return []
    failures: list[str] = []
    if manifest.get("platform") == "physical-ios":
        failures.extend(manifest.get("physical_failures", []))
        for filename, record in collected["files"].items():
            failures.extend(f"{filename}: {failure}" for failure in record.get("physical_context_failures", []))
    apps = manifest.get("apps", [])
    rounds = int(manifest.get("rounds", 0))
    if rounds < 3:
        failures.append(f"rounds={rounds} is below the required n>=3 alternating rounds")
    expected = manifest.get("surfaces", [])
    for surface in expected:
        name, mode = surface["name"], surface.get("mode", surface.get("section", "scroll"))
        if surface.get("status", "measure") != "measure":
            continue
        min_runs = max(3, int(surface.get("min_runs", 3)))
        expect_content = surface.get("expect_content", True)
        env = surface.get("env", {})
        routes_key = {
            "nav": "FST_PERF_NAV", "modal": "FST_PERF_MODAL", "component": "FST_PERF_COMPONENT"
        }.get(mode)
        routes = [item for item in env.get(routes_key, "").split(";") if item] if routes_key else []
        for round_number in range(1, rounds + 1):
            for app in apps:
                prefix = f"{name!r} round {round_number} {app}"
                matching_files = [
                    record for filename, record in collected["files"].items()
                    if record["round"] == round_number and record["app"] == app
                    and name in record["names"] and filename.startswith(f"r{round_number}-{app}-")
                ]
                if not matching_files:
                    failures.append(f"{prefix}: unexecuted case")
                    continue
                if not all(record["complete"] for record in matching_files):
                    failures.append(f"{prefix}: missing FSTPERF_DONE")
                launch = [m for m in collected["runs"].get((name, "launch", app), []) if m.get("_round") == round_number]
                if len(launch) != 1:
                    failures.append(f"{prefix}: expected one launch record, got {len(launch)}")
                elif expect_content:
                    row = launch[0]
                    if row.get("first_content_ms", -1) < 0 or row.get("content_real", 0) < 1:
                        failures.append(f"{prefix}: first real content was not observed")
                if mode == "scroll":
                    idle = [m for m in collected["runs"].get((name, "idle", app), []) if m.get("_round") == round_number]
                    scroll = [m for m in collected["runs"].get((name, "scroll", app), []) if m.get("_round") == round_number]
                    if len(idle) != 1 or len(scroll) < 2:
                        failures.append(f"{prefix}: expected one idle and two scroll samples")
                    for kind, rows in (("idle", idle), ("scroll", scroll)):
                        for row in rows:
                            if "error" in row or row.get("seconds", 0) <= 0 or row.get("fps", 0) <= 0:
                                failures.append(f"{prefix}: invalid {kind} timing record")
                            if kind == "scroll" and row.get("travelled", 0) <= 0:
                                failures.append(f"{prefix}: scroll did not move content")
                elif mode == "latency":
                    rows = [
                        m for m in collected["runs"].get((name, "latency", app), [])
                        if m.get("_round") == round_number
                    ]
                    if len(rows) != 1:
                        failures.append(f"{prefix}: expected one no-scroll latency record")
                    elif (
                        "error" in rows[0] or rows[0].get("seconds", 0) <= 0
                        or rows[0].get("cpu_ms", 0) < 0 or rows[0].get("mem_mb", 0) <= 0
                    ):
                        failures.append(f"{prefix}: invalid no-scroll latency/memory record")
                elif mode in ("nav", "modal"):
                    kinds = ("push", "pop") if mode == "nav" else ("present", "dismiss")
                    for route in routes:
                        for kind in kinds:
                            rows = [
                                m for m in collected["runs"].get((name, kind, app), [])
                                if m.get("_round") == round_number and m.get("_route") == route
                            ]
                            if len(rows) != 1:
                                failures.append(f"{prefix}: missing {kind} record for {route}")
                            elif "error" in rows[0] or rows[0].get("n", 0) < min_runs:
                                failures.append(f"{prefix}: {kind} for {route} has fewer than {min_runs} samples")
                elif mode == "component":
                    for route in routes:
                        rows = [
                            m for m in collected["runs"].get((name, "component", app), [])
                            if m.get("_round") == round_number and m.get("_route") == route
                        ]
                        if len(rows) != 1 or "error" in (rows[0] if rows else {}):
                            failures.append(f"{prefix}: missing component record for {route}")
                        elif rows[0].get("n", 0) < min_runs:
                            failures.append(f"{prefix}: component {route} has fewer than {min_runs} samples")
                        elif (
                            rows[0].get("restored", 0) < 1
                            or rows[0].get("active_s", 0) <= 0
                            or rows[0].get("cpu_ms", -1) < 0
                            or rows[0].get("mem_mb", 0) <= 0
                            or rows[0].get("fps", 0) <= 0
                        ):
                            failures.append(f"{prefix}: component {route} has incomplete active CPU/frame/memory evidence")
    for key, rows in collected["runs"].items():
        name, _, app = key
        if name not in {surface["name"] for surface in expected} or app not in apps:
            failures.append(f"unmatched result data: {name!r}/{app}")
    expected_names = {surface["name"] for surface in expected}
    for filename, record in collected["files"].items():
        for name in record["names"]:
            if name not in expected_names:
                failures.append(f"unmatched result data in {filename}: {name!r}")
    return sorted(set(failures))


def qualification_markdown(collected: dict, manifest: dict | None) -> str:
    """Render the qualification state without turning missing metrics into zeros."""
    if manifest is None:
        return ""
    failures = qualify(collected, manifest)
    excluded = [
        (surface.get("name"), surface.get("status"), surface.get("status_reason", ""))
        for surface in manifest.get("surfaces", [])
        if surface.get("status", "measure") != "measure"
    ]
    warnings = []
    sample_values = [
        row["gpu_pct"] for rows in collected["runs"].values() for row in rows
        if "gpu_pct" in row and row["gpu_pct"] == row["gpu_pct"]
    ]
    physical = manifest.get("platform") == "physical-ios"
    if physical:
        warnings.append("Device GPU counters and render-server CPU unavailable; no Mac samples substitute for them.")
        warnings.append("Process CPU and footprint include the identical in-process synthetic fixture replay.")
    elif not sample_values:
        warnings.append("Mac GPU utilisation unavailable; this is a missing simulator metric, not zero.")
    if manifest.get("source", {}).get("dirty"):
        warnings.append("source worktree was dirty; compare only with an explicitly matched source digest.")
    if manifest.get("capacity", {}).get("other_simulator_workload_present"):
        warnings.append("other simulator workloads were admitted; host GPU/render-server values are not idle-host comparable.")
    lines = ["### Qualification", "", f"**Status:** {'QUALIFIED' if not failures else 'INCOMPLETE'}", ""]
    if failures:
        lines += ["**Hard-gate failures:**"] + [f"- {failure}" for failure in failures] + [""]
    if warnings:
        lines += ["**Metric/source warnings:**"] + [f"- {warning}" for warning in warnings] + [""]
    if excluded:
        lines += ["**Declared non-measurement cases:**"] + [
            f"- {name}: {status} — {reason}" for name, status, reason in excluded
        ] + [""]
    lines += [f"Source commit: `{manifest.get('source', {}).get('commit', 'unknown')}`  "]
    if physical:
        source = manifest.get("build", {}).get("source_after", {}).get("app_source_digest", "unknown")
        lines += [
            f"Compiled app source digest: `{source}`  ",
            f"Physical iOS device: `{manifest.get('device_udid', 'unknown')}`; synthetic fixture archive: `{manifest.get('archive_digest', 'unknown')}`",
        ]
        if manifest.get("failure_reassessments"):
            lines.append("Original runner assessment retained in `manifest.runner-original.json`; raw context independently revalidated.")
    else:
        lines.append(f"Simulator: `{manifest.get('udid', 'unknown')}`; fixture: `{manifest.get('fixture', {}).get('mode', 'unknown')}`")
    lines.append("")
    return "\n".join(lines)

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


def table(
    title: str, kinds: tuple[str, ...], columns: list, collected: dict, kind_column: bool, spread_key: str
) -> tuple[list[str], list[dict]]:
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
            for app in collected.get("apps", APPS):
                cell = collected["runs"].get((name, kind, app), [])
                data = [m for m in cell if "error" not in m]
                errors = [m for m in cell if "error" in m]
                if not data:
                    if errors:
                        prefix = f"| {name} | " + (f"{kind} | " if kind_column else "")
                        lines.append(prefix + f"{APP_LABEL.get(app, app)} | 0 | – | " + errors[0]["error"].replace("|", "/") + " |")
                    continue
                cells, raw = median_row(data, columns)
                spread_values = [m[spread_key] for m in data if spread_key in m and m[spread_key] == m[spread_key]]
                spread = (
                    f"{min(spread_values):.1f}..{max(spread_values):.1f}"
                    if spread_values else "–"
                )
                rows.append({
                    "table": title, "surface": name, "kind": kind, "app": app, "n": len(data),
                    "spread_key": spread_key, "spread": spread, **raw,
                })
                prefix = f"| {name} | " + (f"{kind} | " if kind_column else "")
                lines.append(prefix + f"{APP_LABEL.get(app, app)} | {len(data)} | {spread} | " + " | ".join(cells) + " |")
    if not lines:
        return [], rows
    head = f"| {title} | " + ("Kind | " if kind_column else "") + f"App | n | spread ({spread_key}) | " + " | ".join(c[1] for c in columns) + " |"
    rule = "|" + "---|" * ((5 if kind_column else 4) + len(columns))
    return [head, rule, *lines], rows


def render(collected: dict, physical: bool = False) -> tuple[str, list[dict]]:
    """The whole report.

    Args:
        collected: ``collect`` output.
        physical: Omit simulator-only host metrics and labels.

    Returns:
        Markdown text and the raw rows.
    """
    out: list[str] = []
    all_rows: list[dict] = []
    for heading, title, kinds, columns, kind_column, spread_key in (
        ("Scroll and idle", "Surface", ("idle", "scroll"),
         [column for column in SCROLL_COLUMNS if not physical or column[0] not in ("render_ms", "gpu_pct")], True, "fps"),
        ("Cold launch (fresh install, to first content)", "Surface", ("launch",), LAUNCH_COLUMNS, False, "first_content_ms"),
        ("Navigation (push and pop, process CPU)" if physical else "Navigation (push and pop, simulator CPU)",
         "Scenario", ("push", "pop"), NAV_COLUMNS, True, "first_p50_ms"),
        ("Modal/task presentation", "Scenario", ("present", "dismiss"), NAV_COLUMNS, True, "first_p50_ms"),
        ("Component and animation probes", "Component", ("component",), COMPONENT_COLUMNS, False, "first_p50_ms"),
        ("No-scroll latency and memory", "Surface", ("latency",), LATENCY_COLUMNS, False, "cpu_ms"),
    ):
        lines, rows = table(title, kinds, columns, collected, kind_column, spread_key)
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
    parser.add_argument("--allow-incomplete", action="store_true", help="render evidence without a zero-exit qualification gate")
    args = parser.parse_args(argv)
    collected = collect(args.directory)
    manifest = load_manifest(args.directory)
    text, rows = render(collected, physical=bool(manifest and manifest.get("platform") == "physical-ios"))
    qualification = qualification_markdown(collected, manifest)
    text = text + ("\n" if text and qualification else "") + qualification
    print(text)
    if args.csv:
        fields = sorted({k for r in rows for k in r}, key=lambda k: (k not in ("table", "surface", "kind", "app", "n"), k))
        with open(args.csv, "w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
    return 0 if args.allow_incomplete or not qualify(collected, manifest) else 2


if __name__ == "__main__":
    sys.exit(main())
