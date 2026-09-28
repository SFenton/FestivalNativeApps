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

def session(avd: str, apk: Path, shots: list[str], hold: int, wait_timeout: int) -> None:
    """Install the APK and take several screenshots inside **one** shared-lock hold.

    The device lab boots every AVD fresh (``-no-snapshot``) and may shut it down
    between holds, so separate ``install`` and ``shot`` calls can lose the app.

    Args:
        avd: FST AVD name.
        apk: Debug APK path.
        shots: Specs ``out.png|posture|wait|KEY=VALUE,KEY=VALUE`` (posture may be empty).
        hold: Lock hold budget in seconds (≤300).
        wait_timeout: Seconds to queue for the lock.
    """
    import importlib.util
    import json
    import time
    tool = device_tool()
    sys.path.insert(0, str(tool.parent))
    spec = importlib.util.spec_from_file_location("fst_device", tool)
    device_module = importlib.util.module_from_spec(spec)
    sys.modules["fst_device"] = device_module
    spec.loader.exec_module(device_module)
    args = argparse.Namespace(avd=avd, window=False, gpu="swiftshader_indirect", allow_foreign=False,
                              animations=False, hold=hold, wait_timeout=wait_timeout)
    with device_module._lock(args, f"android-lane session {avd}") as lock:
        device = device_module._booted(args, lock)
        print(device.adb("install", "-r", "-t", "-g", str(apk), cap=180).stdout.strip())
        for raw in shots:
            out, posture, wait, extras = (raw.split("|") + ["", "", "", ""])[:4]
            if posture:
                device_module.apply_posture(device, avd, posture)
            pairs = dict(item.split("=", 1) for item in extras.split(",") if "=" in item)
            launch = argparse.Namespace(package=PACKAGE, activity=".MainActivity", tab=pairs.pop("FST_DEBUG_TAB", None),
                                        route=pairs.pop("FST_DEBUG_ROUTE", None), extra=[f"{k}={v}" for k, v in pairs.items()])
            device_module._launch(device, launch)
            time.sleep(float(wait or 10))
            path = Path(out)
            path.parent.mkdir(parents=True, exist_ok=True)
            device.screenshot(path)
            path.with_suffix(".json").write_text(json.dumps(device.metadata(avd), indent=2), encoding="utf-8")
            print(path)

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
    ses = sub.add_parser("session", help="install + several screenshots in one shared-lock hold")
    ses.add_argument("--avd", required=True)
    ses.add_argument("--apk", type=Path, default=ANDROID / "app" / "build" / "outputs" / "apk" / "debug" / "app-debug.apk")
    ses.add_argument("--hold", type=int, default=300)
    ses.add_argument("--wait-timeout", type=int, default=1800)
    ses.add_argument("shots", nargs="+", help="out.png|posture|waitSeconds|KEY=VALUE,KEY=VALUE")

    ns = parser.parse_args()
    if ns.command == "session":
        session(ns.avd, ns.apk, ns.shots, ns.hold, ns.wait_timeout)
        return
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
