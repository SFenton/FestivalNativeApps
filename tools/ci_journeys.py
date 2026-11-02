#!/usr/bin/env python3
"""Run apple-ci's simulator journey steps locally, against the SwiftUI app or the UIKit port.

``.github/workflows/apple-ci.yml`` registers the journeys that gate a release, each step with
its own fixture services (the large catalogue on 8765, a plain fixture on an OS-assigned port,
an unpinned listener, large rankings …) and its own device legs (iPhone, iPad, folded iPhone
Duo). This tool runs those same step scripts on this Mac, so a local parity run uses exactly
CI's fixtures and journey lists:

- each step's ``env:`` and ``run:`` script runs under ``bash -eo pipefail``, with
  ``RUNNER_TEMP``, ``GITHUB_ENV`` and ``GITHUB_WORKSPACE`` pointed at this run;
- matrix legs expand, and ``${{ matrix.* }}`` takes the leg's value;
- ``ios_sim.py ci-device`` (CI's throwaway simulators) becomes the local ``iphone``,
  ``ipad`` or ``duo`` alias, and per-leg simulator shutdowns are skipped;
- ``--app uikit`` sets ``FST_SIM_PRODUCT_FAMILY=uikit``, so every ``ios_sim.py`` call runs
  the UIKit port's UI-test bundles (``phone`` → ``uikit``, ``ipad`` → ``uikit-ipad``).

Steps run one at a time (the simulator lock serializes them anyway). Stop any fixture service
already listening on a port a step starts (8765, 18934, 18446, 18944, 8766) first.

Usage::

    python3 tools/ci_journeys.py --list
    python3 tools/ci_journeys.py --app uikit --out /tmp/ci-uikit
    python3 tools/ci_journeys.py --app uikit --out /tmp/ci-uikit --job ipad-journeys --leg ipad

Each step writes ``<out>/<n>-<job>-<leg>-<step>.log``; ``<out>/summary.tsv`` gets one line per
step: name, exit code, seconds, and the step's last ``uitest`` summary line. A step already in
the summary is skipped, so an interrupted run resumes.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github/workflows/apple-ci.yml"

#: Local simulator alias for each CI device type.
DEVICE_ALIASES = {"iPad": "ipad", "Duo": "duo"}

#: Shell prelude: CI's throwaway simulators become the shared local aliases.
PRELUDE = """
fst_local_device() { case "$*" in *iPad*) echo ipad;; *Duo*) echo duo;; *) echo iphone;; esac; }
"""


# region Workflow


def load_workflow(path: Path = WORKFLOW) -> dict:
    """Parse the workflow YAML (PyYAML when installed, else Ruby's YAML).

    Args:
        path: The workflow file.

    Returns:
        The parsed workflow.

    Raises:
        SystemExit: Neither parser is available.
    """
    try:
        import yaml  # type: ignore[import-not-found]

        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except ImportError:
        pass
    try:
        out = subprocess.run(
            ["ruby", "-ryaml", "-rjson", "-e", "puts JSON.dump(YAML.load_file(ARGV[0]))", str(path)],
            check=True, capture_output=True, text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"ci_journeys: needs PyYAML or Ruby to read {path}: {error}") from error
    return json.loads(out.stdout)


def journey_steps(workflow: dict) -> list[dict]:
    """List every journey step, one entry per matrix leg.

    Args:
        workflow: The parsed workflow.

    Returns:
        Dicts with ``job``, ``leg``, ``name``, ``env`` and ``run`` (matrix values substituted).
    """
    steps = []
    for job_name, job in workflow.get("jobs", {}).items():
        legs = ((job.get("strategy") or {}).get("matrix") or {}).get("include") or [{}]
        for leg in legs:
            for step in job.get("steps") or []:
                run = step.get("run") or ""
                if "ios_sim.py uitest" not in run:
                    continue
                env = {key: substitute(str(value), leg) for key, value in (step.get("env") or {}).items()}
                device_type = leg.get("device_type")
                if device_type:
                    env.setdefault("FST_CI_DEVICE", local_alias(device_type))
                steps.append({
                    "job": job_name, "leg": str(leg.get("leg", "")), "name": step.get("name", ""),
                    "env": env, "run": substitute(run, leg),
                })
    return steps


def substitute(text: str, leg: dict) -> str:
    """Replace ``${{ matrix.key }}`` with the leg's value and drop other expressions.

    Args:
        text: A step value or script.
        leg: The matrix leg.

    Returns:
        The text with expressions resolved.
    """
    def value(match: re.Match[str]) -> str:
        expression = match.group(1).strip()
        if expression.startswith("matrix."):
            return str(leg.get(expression.split(".", 1)[1], ""))
        return ""

    return re.sub(r"\$\{\{(.*?)\}\}", value, text)


def local_alias(device_type: str) -> str:
    """Map a CI device type to the local simulator alias.

    Args:
        device_type: e.g. ``"iPad Pro 11-inch (M5)"``.

    Returns:
        ``ipad``, ``duo`` or ``iphone``.
    """
    for needle, alias in DEVICE_ALIASES.items():
        if needle in device_type:
            return alias
    return "iphone"


def localize(script: str) -> str:
    """Rewrite CI-only commands for this Mac.

    Args:
        script: A step's ``run`` script.

    Returns:
        The script using local simulator aliases and no per-leg shutdowns.
    """
    script = script.replace("python3 tools/ios_sim.py ci-device", "fst_local_device")
    script = re.sub(r"python3 tools/ios_sim\.py shutdown[^\n]*", "true", script)
    return PRELUDE + script


# endregion

# region Run


def slug(text: str) -> str:
    """A filename-safe slug."""
    return re.sub(r"[^A-Za-z0-9]+", "-", text).strip("-")[:60]


def run_step(index: int, step: dict, out: Path, app: str) -> tuple[int, float, str]:
    """Run one step's script, logging to ``out``.

    Args:
        index: The step's position, for the log name.
        step: The step from ``journey_steps``.
        out: Output directory.
        app: ``uikit`` or ``swiftui``.

    Returns:
        Exit code, seconds taken, and the last ``uitest`` summary line.
    """
    temp = out / f"runner-temp-{index}"
    temp.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, **step["env"]}
    env.update({
        "RUNNER_TEMP": str(temp), "GITHUB_ENV": str(temp / "github_env"), "GITHUB_WORKSPACE": str(ROOT),
        "DEVELOPER_DIR": os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"),
    })
    if app == "uikit":
        env["FST_SIM_PRODUCT_FAMILY"] = "uikit"
    log = out / f"{index:02d}-{slug(step['job'])}-{slug(step['leg'] or 'all')}-{slug(step['name'])}.log"
    start = time.time()
    with log.open("w") as handle:
        code = subprocess.call(
            ["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", localize(step["run"])],
            cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT,
        )
    lines = [line for line in log.read_text(errors="replace").splitlines() if line.startswith("uitest")]
    return code, time.time() - start, lines[-1] if lines else ""


def main(argv: list[str] | None = None) -> int:
    """Entry point."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--app", choices=["uikit", "swiftui"], default="swiftui")
    parser.add_argument("--out", type=Path, help="output directory (required unless --list)")
    parser.add_argument("--job", action="append", help="only these jobs (repeatable)")
    parser.add_argument("--leg", action="append", help="only these matrix legs (repeatable)")
    parser.add_argument("--list", action="store_true", help="list the journey steps and exit")
    args = parser.parse_args(argv)

    steps = [
        step for step in journey_steps(load_workflow())
        if (not args.job or step["job"] in args.job) and (not args.leg or step["leg"] in args.leg)
    ]
    if args.list:
        for index, step in enumerate(steps):
            journeys = sum(len(value.split()) for key, value in step["env"].items() if "JOURNEYS" in key)
            print(f"{index:02d} {step['job']} [{step['leg'] or '-'}] {step['name']} ({journeys} journeys)")
        return 0
    if not args.out:
        parser.error("--out is required")
    args.out.mkdir(parents=True, exist_ok=True)
    summary = args.out / "summary.tsv"
    done = {line.split("\t")[0] for line in summary.read_text().splitlines()} if summary.exists() else set()
    worst = 0
    for index, step in enumerate(steps):
        key = f"{step['job']}/{step['leg'] or '-'}/{step['name']}"
        if key in done:
            continue
        code, seconds, last = run_step(index, step, args.out, args.app)
        worst = worst or code
        with summary.open("a") as handle:
            handle.write(f"{key}\t{code}\t{seconds:.0f}\t{last}\n")
        print(f"{key}: exit {code} in {seconds:.0f}s {last}", flush=True)
    return worst


# endregion

if __name__ == "__main__":
    sys.exit(main())
