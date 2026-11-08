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

Steps run one at a time (the simulator lock serializes them anyway). Fixed fixture ports
must be free; an occupied listener is never stopped or repurposed by this tool.

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
import hashlib
import json
import os
import re
import shlex
import socket
import subprocess
import sys
import time
import uuid
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


def localize(script: str, devices: dict[str, str] | None = None) -> str:
    """Rewrite CI-only commands for this Mac.

    Args:
        script: A step's ``run`` script.

    Returns:
        The script using local simulator aliases and no per-leg shutdowns.
    """
    devices = devices or {}
    script = script.replace("python3 tools/ios_sim.py ci-device", "fst_local_device")
    script = script.replace(
        "python3 tools/ios_sim.py uitest",
        "python3 tools/ios_sim.py uitest --fail-on-skip" + (" --owned-device" if devices else ""),
    )
    script = re.sub(r"python3 tools/ios_sim\.py shutdown[^\n]*", "true", script)
    script = re.sub(
        r"(--device\s+)(iphone27|iphone|ipad|duo)\b",
        lambda match: match[1] + devices.get("iphone" if match[2] == "iphone27" else match[2], match[2]),
        script,
    )
    prelude = PRELUDE
    for family, device in devices.items():
        prelude = prelude.replace(f"echo {family}", f"echo {shlex.quote(device)}")
    return prelude + script


def source_fingerprint(root: Path = ROOT) -> str:
    """Bind resume acceptance to real app, fixture, runner and workflow source."""
    roots = (
        "apple/Sources/", "apple/Apps/", "tools/fixtures/", "tools/mock_service.py",
        "tools/ios_sim.py", "tools/devcap.py", "tools/ci_journeys.py",
        ".github/workflows/apple-ci.yml", "apple/project.yml",
    )
    try:
        names = subprocess.check_output(
            ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            cwd=root, text=True, stderr=subprocess.DEVNULL,
        ).split("\0")
    except (OSError, subprocess.CalledProcessError):
        names = [path.relative_to(root).as_posix() for path in root.rglob("*") if path.is_file()]
    digest = hashlib.sha256()
    for name in sorted(set(names)):
        if not name or not name.startswith(roots):
            continue
        path = root / name
        if path.is_file():
            digest.update(name.encode() + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def bind_provenance(out: Path, configuration: dict, *, root: Path = ROOT) -> None:
    """Refuse cross-source/configuration resume or legacy unbound summaries."""
    expected = {"schemaVersion": 1, "sourceDigest": source_fingerprint(root), **configuration}
    path = out / "provenance.json"
    if path.exists():
        if json.loads(path.read_text()) != expected:
            raise SystemExit("ci_journeys: source/configuration changed; use a new evidence directory")
    elif (out / "summary.tsv").exists():
        raise SystemExit("ci_journeys: legacy summary has no source provenance; use a new evidence directory")
    else:
        path.write_text(json.dumps(expected, indent=2) + "\n")


def fixed_fixture_ports(script: str) -> set[int]:
    """Find fixed mock-service listeners without changing or stopping another process."""
    ports = set()
    for command in re.findall(r"tools/mock_service\.py[^\n;&]*", script):
        if "--port" not in command:
            ports.add(8765)
        else:
            match = re.search(r"--port[ =]+(\d+)\b", command)
            if match and int(match[1]):
                ports.add(int(match[1]))
    return ports


def require_free_ports(script: str) -> None:
    """Fail before a fixture step if a fixed port is already owned elsewhere."""
    for port in fixed_fixture_ports(script):
        with socket.socket() as probe:
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            try:
                probe.bind(("127.0.0.1", port))
            except OSError as error:
                raise SystemExit(f"ci_journeys: fixture port {port} is occupied; leave its owner untouched") from error


# endregion

# region Run


def slug(text: str) -> str:
    """A filename-safe slug."""
    return re.sub(r"[^A-Za-z0-9]+", "-", text).strip("-")[:60]


def run_step(
    index: int, step: dict, out: Path, app: str, *, devices: dict[str, str] | None = None,
    timeout: int = 7200,
) -> tuple[int, float, str]:
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
    devices = devices or {}
    if env.get("FST_CI_DEVICE") in devices:
        env["FST_CI_DEVICE"] = devices[env["FST_CI_DEVICE"]]
    env.update({
        "RUNNER_TEMP": str(temp), "GITHUB_ENV": str(temp / "github_env"), "GITHUB_WORKSPACE": str(ROOT),
        "DEVELOPER_DIR": os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"),
        "FST_UITEST_KEEP_RESULTS": "1",
    })
    if app == "uikit":
        env["FST_SIM_PRODUCT_FAMILY"] = "uikit"
    log = out / f"{index:02d}-{slug(step['job'])}-{slug(step['leg'] or 'all')}-{slug(step['name'])}.log"
    start = time.time()
    require_free_ports(step["run"])
    try:
        from .ios_sim import run_bounded
    except ImportError:
        from ios_sim import run_bounded
    with log.open("w") as handle:
        code = run_bounded(
            ["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", localize(step["run"], devices)],
            timeout,
            cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT,
        )
    lines = [line for line in log.read_text(errors="replace").splitlines() if line.startswith("uitest")]
    if code == 0 and not lines:
        code = 1
        lines = ["uitest: no completed test summary; not acceptance evidence"]
    return code if code is not None else 124, time.time() - start, lines[-1] if lines else ""


def main(argv: list[str] | None = None) -> int:
    """Entry point."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--app", choices=["uikit", "swiftui"], default="swiftui")
    parser.add_argument("--out", type=Path, help="output directory (required unless --list)")
    parser.add_argument("--job", action="append", help="only these jobs (repeatable)")
    parser.add_argument("--leg", action="append", help="only these matrix legs (repeatable)")
    parser.add_argument("--step", action="append", help="only these exact workflow step names (repeatable)")
    parser.add_argument("--list", action="store_true", help="list the journey steps and exit")
    parser.add_argument("--device", action="append", default=[], metavar="FAMILY=UDID",
                        help="use an explicitly owned iphone/ipad/duo device (repeatable)")
    parser.add_argument("--step-timeout", type=int, default=7200, help="bounded script lifetime in seconds")
    args = parser.parse_args(argv)
    devices = {}
    for raw in args.device:
        family, separator, device = raw.partition("=")
        if not separator or family not in {"iphone", "ipad", "duo"}:
            parser.error("--device requires iphone/ipad/duo=UDID")
        try:
            devices[family] = str(uuid.UUID(device)).upper()
        except ValueError:
            parser.error("--device requires a valid simulator UDID")
    if args.step_timeout <= 0:
        parser.error("--step-timeout must be positive")

    steps = [
        step for step in journey_steps(load_workflow())
        if (not args.job or step["job"] in args.job) and (not args.leg or step["leg"] in args.leg)
        and (not args.step or step["name"] in args.step)
    ]
    if args.list:
        for index, step in enumerate(steps):
            journeys = sum(len(value.split()) for key, value in step["env"].items() if "JOURNEYS" in key)
            print(f"{index:02d} {step['job']} [{step['leg'] or '-'}] {step['name']} ({journeys} journeys)")
        return 0
    if not steps:
        parser.error("no journey steps match the requested jobs/legs")
    if not args.out:
        parser.error("--out is required")
    args.out.mkdir(parents=True, exist_ok=True)
    configuration = {
        "app": args.app, "devices": devices, "stepTimeout": args.step_timeout,
        "steps": steps,
    }
    bind_provenance(args.out, configuration)
    summary = args.out / "summary.tsv"
    done = {
        parts[0]: int(parts[1])
        for line in summary.read_text().splitlines()
        if len(parts := line.split("\t")) >= 2
    } if summary.exists() else {}
    selected = {f"{step['job']}/{step['leg'] or '-'}/{step['name']}" for step in steps}
    worst = next((code for key, code in done.items() if key in selected and code), 0)
    for index, step in enumerate(steps):
        key = f"{step['job']}/{step['leg'] or '-'}/{step['name']}"
        if key in done:
            continue
        bind_provenance(args.out, configuration)
        code, seconds, last = run_step(
            index, step, args.out, args.app, devices=devices, timeout=args.step_timeout,
        )
        bind_provenance(args.out, configuration)
        worst = worst or code
        with summary.open("a") as handle:
            handle.write(f"{key}\t{code}\t{seconds:.0f}\t{last}\n")
        print(f"{key}: exit {code} in {seconds:.0f}s {last}", flush=True)
    return worst


# endregion

if __name__ == "__main__":
    sys.exit(main())
