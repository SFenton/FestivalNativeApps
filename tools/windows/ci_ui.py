#!/usr/bin/env python3
"""Run one deterministic shard of the fixture-backed Windows UI CI suite.

The dispatcher covers every checked-in JSON journey and dedicated journey runner while
excluding entries explicitly labelled ``live``. It gives GitHub Actions bounded,
independent shards without changing the local runners or ever selecting the public
service. ``FST_CI=1`` makes the desktop lock a no-op because each hosted runner owns
its desktop session.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
WINDOWS_TOOLS = REPO_ROOT / "tools" / "windows"
JOURNEYS = WINDOWS_TOOLS / "journeys"
MATRIX_GROUP_SIZE = 6


@dataclass(frozen=True)
class Task:
    """One fixture-backed journey command."""

    name: str
    kind: str
    source: Path | None = None
    command: tuple[str, ...] = ()
    entries: tuple[str, ...] = ()


DEDICATED_RUNNERS = (
    ("fade", ("fade_journey.py",)),
    ("first-run", ("first_run_journey.py",)),
    ("leaderboards", ("leaderboards_journey.py",)),
    ("notifications", ("notifications_journey.py",)),
    ("rivals", ("rivals_journey.py",)),
    ("search", ("search_journey.py",)),
    ("selected-reveal", ("selected_reveal_journey.py",)),
    ("shop", ("shop_journey.py",)),
    ("songs-filter", ("songs_filter_journey.py",)),
    ("songs", ("songs_journey.py",)),
    ("suggestions", ("suggestions_journey.py",)),
    ("feedback", ("journeys/feedback.py", "--preset", "medium")),
    ("navigation", ("journeys/navigation.py",)),
    ("profile", ("journeys/profile.py",)),
    ("settings", ("journeys/settings.py",)),
)


def fixture_entries(source: Path) -> list[dict]:
    """Return JSON journeys not labelled as a production/live-service run."""
    entries = json.loads(source.read_text(encoding="utf-8"))
    if not isinstance(entries, list):
        raise ValueError(f"{source} must contain a journey list")
    return [entry for entry in entries if "live" not in str(entry.get("name", "")).lower()]


def all_tasks() -> list[Task]:
    """Return all fixture-only JSON and dedicated-runner tasks in stable order."""
    tasks = []
    for source in sorted(JOURNEYS.glob("*.json")):
        if source.name.startswith("a11y") and source.name != "a11y.json":
            continue
        entries = fixture_entries(source)
        if not entries:
            continue
        kind = "matrix" if source.name.startswith("a11y") else "journey"
        if kind == "journey" and not all("route" in entry and "steps" in entry for entry in entries):
            continue
        names = tuple(str(entry["name"]) for entry in entries)
        if kind == "matrix":
            for index in range(0, len(names), MATRIX_GROUP_SIZE):
                group = names[index:index + MATRIX_GROUP_SIZE]
                tasks.append(Task(f"{kind}:{source.stem}:{index // MATRIX_GROUP_SIZE + 1}", kind, source,
                                  entries=group))
        else:
            tasks.append(Task(f"{kind}:{source.stem}", kind, source, entries=names))
    tasks.extend(Task(f"runner:{name}", "runner", command=command) for name, command in DEDICATED_RUNNERS)
    return tasks


def task_weight(task: Task) -> int:
    """Estimate a task's desktop time for balanced deterministic CI sharding."""
    if task.kind == "runner":
        return 12
    assert task.source is not None
    entries = [entry for entry in fixture_entries(task.source) if entry["name"] in task.entries]
    return sum(len(entry.get("sizes", ("compact", "medium", "wide"))) for entry in entries) if task.kind == "matrix" else len(entries)


def shard_tasks(tasks: list[Task], shard: int, shards: int) -> list[Task]:
    """Assign tasks to a one-based shard with deterministic weighted balancing."""
    if not 1 <= shard <= shards:
        raise ValueError(f"shard must be between 1 and {shards}, got {shard}")
    buckets: list[list[Task]] = [[] for _ in range(shards)]
    weights = [0] * shards
    for task in sorted(tasks, key=lambda item: (-task_weight(item), item.name)):
        index = min(range(shards), key=lambda candidate: (weights[candidate], candidate))
        buckets[index].append(task)
        weights[index] += task_weight(task)
    return sorted(buckets[shard - 1], key=lambda item: item.name)


def write_entries(task: Task, directory: Path) -> Path:
    """Write the selected fixture-only entries for a JSON task."""
    assert task.source is not None
    directory.mkdir(parents=True, exist_ok=True)
    selected = directory / task.source.name
    entries = [entry for entry in fixture_entries(task.source) if entry["name"] in task.entries]
    selected.write_text(json.dumps(entries, indent=2), encoding="utf-8")
    return selected


def task_command(task: Task, out: Path, retries: int) -> list[str]:
    """Build the command for a task, keeping all output under ``out`` when supported."""
    if task.kind in ("journey", "matrix"):
        selected = write_entries(task, out / "inputs")
        if task.kind == "journey":
            return [sys.executable, str(WINDOWS_TOOLS / "ui_journey.py"), str(selected),
                    "--shots", str(out / "screenshots"), "--retries", str(retries)]
        return [sys.executable, str(WINDOWS_TOOLS / "a11y_matrix.py"), "--pages", str(selected),
                "--out", str(out / "a11y"), "--scan", "--tabs", "30"]
    assert task.command
    script, *args = task.command
    command = [sys.executable, str(WINDOWS_TOOLS / script), *args]
    if script not in ("fade_journey.py",):
        command.extend(["--shots", str(out / "screenshots")])
    return command


def main(argv: list[str] | None = None) -> int:
    """Run the requested task shard and return nonzero after any failed task."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--shard", type=int, required=True)
    parser.add_argument("--shards", type=int, required=True)
    parser.add_argument("--retries", type=int, default=2)
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args(argv)

    selected = shard_tasks(all_tasks(), args.shard, args.shards)
    if args.list:
        print("\n".join(task.name for task in selected))
        return 0
    if not selected:
        print(f"shard {args.shard}/{args.shards}: no tasks")
        return 0

    args.out.mkdir(parents=True, exist_ok=True)
    failures = []
    for task in selected:
        task_out = args.out / task.name.replace(":", "-")
        command = task_command(task, task_out, args.retries)
        print(f"::group::{task.name}\n{' '.join(command)}", flush=True)
        task_out.mkdir(parents=True, exist_ok=True)
        with (task_out / "command.log").open("w", encoding="utf-8") as log:
            result = subprocess.run(command, cwd=REPO_ROOT, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            tail = (task_out / "command.log").read_text(encoding="utf-8", errors="replace").splitlines()[-20:]
            print("\n".join(tail), flush=True)
        print("::endgroup::", flush=True)
        if result.returncode:
            failures.append(task.name)
    (args.out / "summary.json").write_text(
        json.dumps({"shard": args.shard, "shards": args.shards, "tasks": [task.name for task in selected],
                    "failures": failures}, indent=2),
        encoding="utf-8",
    )
    if failures:
        print(f"failed tasks: {', '.join(failures)}", file=sys.stderr)
        return 1
    print(f"passed {len(selected)} fixture-only tasks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
