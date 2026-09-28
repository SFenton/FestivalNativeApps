#!/usr/bin/env python3
"""Run a ``device.py drive`` journey while recording the emulator screen.

Same options as ``device.py drive`` (shared FIFO emulator lock, ≤300 s holds),
plus ``--record OUT.mp4``. ``adb shell screenrecord`` runs inside the same lock
hold as the steps, is stopped with SIGINT after the last step (so the MP4 is
finalized) and pulled to OUT. Recordings of live data are showcase material:
keep them outside the repository.

Usage::

    python tools/android/record_journey.py --record C:/showcase/journey.mp4 \
        --avd FST_Phone --launch --steps-file journey.steps [--apk app-debug.apk]
"""

from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import device  # noqa: E402  (shared emulator tool beside this script)

PACKAGE = "com.festivalscoretracker.android"
REMOTE = "/sdcard/fst-journey.mp4"
MAX_SECONDS = 170


def parse(argv: list[str]):
    """Parse ``device.py drive`` options plus ``--record``.

    Args:
        argv: Command-line arguments.

    Returns:
        Parsed namespace (``record`` is a Path).
    """
    record = None
    if "--record" in argv:
        index = argv.index("--record")
        record = Path(argv[index + 1])
        argv = argv[:index] + argv[index + 2:]
    if "--package" not in argv:
        argv = ["--package", PACKAGE, "--activity", ".MainActivity", *argv]
    args = device.build_parser().parse_args(["drive", *argv])
    if record is None:
        raise SystemExit("--record OUT.mp4 is required")
    args.record = record
    return args


def main(argv: list[str] | None = None) -> int:
    """Boot, install, launch, record the steps and pull the video.

    Args:
        argv: Arguments (defaults to ``sys.argv[1:]``).

    Returns:
        Exit code.
    """
    args = parse(list(sys.argv[1:] if argv is None else argv))
    steps = [device.parse_step(s) for s in device.parse_steps(args.steps, args.steps_file)]
    with device._lock(args, f"record {args.avd}") as lock:
        dev = device._booted(args, lock)
        device._prepare(dev, args)
        dev.shell(f"rm -f {REMOTE}", check=False)
        recorder = subprocess.Popen(
            [device.adb_path(), "-s", device.FST_SERIAL, "shell", "screenrecord", "--time-limit", str(MAX_SECONDS), REMOTE],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        try:
            time.sleep(1)
            if args.launch:
                device._launch(dev, args)
                time.sleep(args.wait)
            for verb, arg in steps:
                device.run_step(dev, args.avd, verb, arg)
            time.sleep(1)
        finally:
            dev.shell("pkill -INT screenrecord", check=False)
            try:
                recorder.wait(timeout=15)
            except subprocess.TimeoutExpired:
                recorder.kill()
            time.sleep(2)
            args.record.parent.mkdir(parents=True, exist_ok=True)
            dev.adb("pull", REMOTE, str(args.record), cap=60)
            dev.shell(f"rm -f {REMOTE}", check=False)
    print(f"recorded {args.record}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
