#!/usr/bin/env python3
"""Deterministic Android build, test and coverage driver for Festival Score Tracker.

Device work (boot, install, launch with debug extras, screenshot, fold posture) goes
through the host's shared, FIFO-locked emulator tool ``tools/android/device.py``
(device-lab lane) so parallel lanes never run two emulators. ``device`` forwards to
it, defaulting ``--package``/``--activity`` to this app.

Examples::

    python tools/android/fst_android.py build --tests --coverage
    python tools/android/fst_android.py coverage --min-logic 95 --files
    python tools/android/fst_android.py device install android/app/build/outputs/apk/debug/app-debug.apk --avd FST_Phone
    python tools/android/fst_android.py device shot out.png --avd FST_Phone --tab songs --extra FST_DEBUG_STILL_BACKGROUND=1
    python tools/android/fst_android.py device shot out.png --avd FST_Book_Fold --posture folded --route song:<songId>
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ANDROID = REPO / "android"
PACKAGE = "com.festivalscoretracker.android"
COVERAGE_XML = ANDROID / "app" / "build" / "reports" / "coverage" / "test" / "debug" / "report.xml"


# region Device tool

def device_tool() -> Path:
    """Locate the shared locked emulator tool: $FST_DEVICE_TOOL, this repo, or the lab worktree."""
    candidates = [
        Path(os.environ["FST_DEVICE_TOOL"]) if os.environ.get("FST_DEVICE_TOOL") else None,
        REPO / "tools" / "android" / "device.py",
        REPO.parent / "lab" / "tools" / "android" / "device.py",
    ]
    for candidate in candidates:
        if candidate and candidate.exists():
            return candidate
    raise SystemExit("tools/android/device.py (shared emulator lock) not found; set FST_DEVICE_TOOL")


def forward_to_device(args: list[str]) -> int:
    """Run device.py with this app's package/activity defaults for launch-style commands."""
    if args and args[0] in ("launch", "shot", "drive") and "--package" not in args:
        args = [args[0], "--package", PACKAGE, "--activity", ".MainActivity", *args[1:]]
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    return subprocess.call([sys.executable, str(device_tool()), *args], env=env)

# endregion


# region Build and coverage

def gradle(*tasks: str) -> None:
    """Run Gradle wrapper tasks in android/."""
    wrapper = ANDROID / ("gradlew.bat" if os.name == "nt" else "gradlew")
    subprocess.run([str(wrapper), *tasks, "--console=plain"], cwd=ANDROID, check=True)


LOGIC_PREFIXES = (
    "com/festivalscoretracker/android/core/",
    "com/festivalscoretracker/android/data/",
    "com/festivalscoretracker/android/presentation/",
)


def is_generated(class_name: str) -> bool:
    """Exclude compiler-generated serializers, Compose singletons and R/BuildConfig."""
    base = class_name.rsplit("/", 1)[-1]
    return "$$serializer" in base or base.startswith("ComposableSingletons") or base in ("BuildConfig", "R") or base.startswith("R$")


def coverage_summary(xml_path: Path) -> dict:
    """Split JaCoCo line coverage into logic (core/data/presentation) and UI buckets."""
    root = ET.parse(xml_path).getroot()
    totals = {"logic": [0, 0], "ui": [0, 0]}
    per_file: dict[str, list[int]] = {}
    for package in root.iter("package"):
        for cls in package.iter("class"):
            name = cls.get("name", "")
            if is_generated(name):
                continue
            bucket = "logic" if name.startswith(LOGIC_PREFIXES) else "ui"
            for counter in cls.findall("counter"):
                if counter.get("type") == "LINE":
                    missed, covered = int(counter.get("missed")), int(counter.get("covered"))
                    totals[bucket][0] += covered
                    totals[bucket][1] += covered + missed
                    key = f"{bucket}:{name.rsplit('/', 1)[0]}/{cls.get('sourcefilename')}"
                    entry = per_file.setdefault(key, [0, 0])
                    entry[0] += covered
                    entry[1] += covered + missed
    result = {k: (100.0 * c / t if t else 100.0) for k, (c, t) in totals.items()}
    result["files"] = {k: round(100.0 * c / t, 1) for k, (c, t) in per_file.items() if t}
    result["lines"] = {k: f"{c}/{t}" for k, (c, t) in totals.items()}
    return result

# endregion


# region CLI

def main() -> None:
    """Parse the CLI and dispatch."""
    if len(sys.argv) > 1 and sys.argv[1] == "device":
        raise SystemExit(forward_to_device(sys.argv[2:]))
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    build = sub.add_parser("build", help="assembleDebug, optionally unit/UI tests and coverage")
    build.add_argument("--tests", action="store_true")
    build.add_argument("--coverage", action="store_true", help="tests + JaCoCo report + summary")
    build.add_argument("--release", action="store_true", help="also assembleRelease")

    cov = sub.add_parser("coverage", help="summarize the JaCoCo unit-test report")
    cov.add_argument("--xml", type=Path, default=COVERAGE_XML)
    cov.add_argument("--min-logic", type=float, default=None, help="fail below this logic line coverage")
    cov.add_argument("--files", action="store_true", help="print per-file coverage")

    sub.add_parser("device", help="forward to the shared locked emulator tool (device.py)")

    ns = parser.parse_args()
    if ns.command == "build":
        tasks = [":app:assembleDebug"]
        if ns.release:
            tasks.append(":app:assembleRelease")
        if ns.tests or ns.coverage:
            tasks.append(":app:testDebugUnitTest")
        if ns.coverage:
            tasks.append(":app:createDebugUnitTestCoverageReport")
        gradle(*tasks)
        if ns.coverage:
            summary = coverage_summary(COVERAGE_XML)
            print(f"logic lines {summary['logic']:.1f}% ({summary['lines']['logic']}), UI lines {summary['ui']:.1f}% ({summary['lines']['ui']})")
        return
    summary = coverage_summary(ns.xml)
    if ns.files:
        for name, pct in sorted(summary["files"].items()):
            print(f"{pct:6.1f}%  {name}")
    print(f"logic lines {summary['logic']:.1f}% ({summary['lines']['logic']}), UI lines {summary['ui']:.1f}% ({summary['lines']['ui']})")
    if ns.min_logic is not None and summary["logic"] < ns.min_logic:
        raise SystemExit(f"logic coverage {summary['logic']:.1f}% is below {ns.min_logic}%")


if __name__ == "__main__":
    main()

# endregion
