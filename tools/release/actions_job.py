#!/usr/bin/env python3
"""GitHub Actions entry point for every store call (``store-release.yml``).

Store status reads and submissions never run from a developer or agent machine:
the release orchestrator dispatches ``store-release.yml`` and reads the
``result.json`` artifact this script writes::

    actions_job.py --platform windows --command status --out result.json
    actions_job.py --platform windows --command submit --build 0.1.912.0 --notes-b64 <b64> --out result.json
    actions_job.py --platform ios --command submit --version 2610.15.02 --replace --out result.json
    actions_job.py --platform ios --command release --version 2610.15.02 --out result.json

``result.json`` is ``{platform, command, exit_code, output, sha}`` where
``output`` is the JSON document printed by ``fst_release.py`` (exit codes as
there). Policy enforced here, independent of the orchestrator:

- iOS ``submit`` (App Store review) is refused with
  ``blocked: app_store_review_disabled`` unless
  ``FST_APPSTORE_REVIEW_ENABLED=true`` (repository variable). Approved versions
  wait for a manual release unless ``FST_APPSTORE_RELEASE_TYPE=AFTER_APPROVAL``.
- Windows ``submit`` uses Manual publish mode (certification only, never a
  release) unless ``--publish-at`` schedules publication (the release train's
  Monday release; the Store API has no "Publish now").
- ``--version YYMM.DD.NN`` (release train) submits that version's build: iOS
  resolves the newest VALID build of it first (``build-for-version``), Windows
  finds its MSIX artifact. ``--replace`` removes a submission still in review
  (or approved, unreleased) before submitting.
- ``release`` releases the approved iOS version (``--version`` must match) and
  reports whether the Windows submission is published or scheduled.
- iOS ``submit`` reads the build's ``fst-ios-build_<build>`` marker artifact: its
  generated ``store_notes`` replace the orchestrator's notes, and its
  ``whats_new_baseline`` must still be the newest released version. Otherwise the
  store refuses with ``stale_whats_new`` and this job dispatches a rebuild of the
  same version tag (new build number, regenerated What's New) unless an
  ``ios-release-build`` run is already queued or running.

The process exits 0 for ok/refused/blocked (the result carries the detail) and
1 otherwise, so failed jobs stay visible in Actions.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import io
import json
import os
import re
import subprocess
import sys
from contextlib import redirect_stdout
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fst_release  # noqa: E402

BUILD_RE = re.compile(r"^[0-9][0-9.]{0,31}$")
VERSION_RE = re.compile(r"^\d{4}\.\d{2}\.\d{2}$")
PUBLISH_AT_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
NOTES_LIMIT = 8000
QUIET_EXITS = (fst_release.EXIT_OK, fst_release.EXIT_REFUSED, fst_release.EXIT_BLOCKED)


def decode_notes(value: str) -> str:
    """Decode base64 release notes (empty → empty); raises ValueError on bad input."""
    if not value:
        return ""
    try:
        text = base64.b64decode(value.encode("ascii"), validate=True).decode("utf-8")
    except (binascii.Error, UnicodeError) as err:
        raise ValueError("notes_b64 is not base64 UTF-8: %s" % err)
    return text[:NOTES_LIMIT]


REBUILD_WORKFLOW = {"ios": "ios-release-build.yml"}
UNSET = object()


def tool_argv(platform: str, command: str, build: Optional[str], dry_run: bool,
              baseline: Any = UNSET, replace: bool = False, publish_at: Optional[str] = None,
              version: Optional[str] = None) -> List[str]:
    """Build the ``fst_release.py`` arguments for one job (``baseline`` None = no release yet)."""
    if command == "status":
        return [platform, "status", "--json"]
    if version and not VERSION_RE.match(version):
        raise ValueError("--version must be YYMM.DD.NN")
    if command == "release":
        argv = [platform, "release"] + (["--version", version] if version else [])
        return argv + (["--dry-run"] if dry_run else [])
    if not build or not BUILD_RE.match(build):
        raise ValueError("submit needs a numeric --build")
    argv = [platform, "submit", "--build", build, "--notes-stdin"]
    if baseline is not UNSET:
        argv += ["--whats-new-baseline", baseline or "none"]
    if replace:
        argv.append("--replace")
    if publish_at:
        if platform != "windows" or not PUBLISH_AT_RE.match(publish_at):
            raise ValueError("--publish-at is a Windows YYYY-MM-DDTHH:MM:SSZ time")
        argv += ["--publish-at", publish_at]
    if dry_run:
        argv.append("--dry-run")
    return argv


def call_tool(main: Any, argv: List[str], env: Dict[str, str], notes: str = "") -> Any:
    """Run ``fst_release.main`` in-process; returns ``(exit code, last JSON document)``."""
    out = io.StringIO()
    with redirect_stdout(out):
        code = (main or fst_release.main)(argv, env=env, stdin=io.StringIO(notes))
    text = out.getvalue().strip()
    try:
        output: Any = json.loads(text.splitlines()[-1]) if text else None
    except ValueError:
        output = {"error": "non-JSON output", "text": text[-500:]}
    return code, output


def default_marker(platform: str, build: str, env: Dict[str, str]) -> Optional[Dict[str, Any]]:
    """Download the build marker written by the platform's release build (``None`` when absent)."""
    repo = env.get("FST_NATIVE_REPO") or "SFenton/FestivalNativeApps"
    return fst_release.artifact_marker("fst-%s-build_%s" % (platform, build), repo)


def gh(args: List[str]) -> str:
    """Run ``gh`` and return stdout (raises ``RuntimeError``)."""
    proc = subprocess.run(["gh"] + args, capture_output=True, text=True, timeout=120)
    if proc.returncode != 0:
        raise RuntimeError("gh %s failed: %s" % (" ".join(args[:2]), (proc.stderr or "").strip()[-300:]))
    return proc.stdout


def dispatch_rebuild(platform: str, marker: Dict[str, Any], runner: Any = None) -> Dict[str, Any]:
    """Dispatch a rebuild of the marker's version tag unless a build is already queued or running."""
    workflow = REBUILD_WORKFLOW.get(platform)
    tag = marker.get("version_tag")
    if not workflow or not tag:
        return {"dispatched": False, "reason": "no_version_tag"}
    run = runner or gh
    try:
        for state in ("queued", "in_progress"):
            active = json.loads(run(["run", "list", "--workflow", workflow, "--status", state,
                                     "--json", "databaseId", "-L", "5"]) or "[]")
            if active:
                return {"dispatched": False, "reason": "build_%s" % state, "version_tag": tag}
        run(["workflow", "run", workflow, "--ref", "master", "-f", "version_tag=%s" % tag,
             "-f", "rebuild_reason=stale_whats_new"])
    except (RuntimeError, ValueError, OSError) as err:
        return {"dispatched": False, "reason": "error", "error": str(err)[-300:], "version_tag": tag}
    return {"dispatched": True, "version_tag": tag}


def run_job(platform: str, command: str, build: Optional[str], notes: str, dry_run: bool,
            env: Dict[str, str], main: Any = None, marker_lookup: Any = None,
            runner: Any = None, version: Optional[str] = None, replace: bool = False,
            publish_at: Optional[str] = None) -> Dict[str, Any]:
    """Apply policy, run the release tool in-process and return the result document."""
    result: Dict[str, Any] = {"platform": platform, "command": command, "build": build,
                              "sha": env.get("GITHUB_SHA"), "dry_run": dry_run}
    if version:
        result["version"] = version
    if command == "submit" and platform == "ios" and env.get("FST_APPSTORE_REVIEW_ENABLED") != "true":
        result.update(exit_code=fst_release.EXIT_BLOCKED, output={"blocked": "app_store_review_disabled"})
        return result
    if command == "submit" and version and not build:
        if not VERSION_RE.match(version):
            raise ValueError("--version must be YYMM.DD.NN")
        code, found = call_tool(main, [platform, "build-for-version", "--version", version], env)
        if code != fst_release.EXIT_OK or not isinstance(found, dict) or not found.get("build"):
            result.update(exit_code=fst_release.EXIT_REFUSED if code == fst_release.EXIT_REFUSED else code,
                          output={"refused": "build_not_found", "version": version, "lookup": found})
            return result
        build = str(found["build"])
        result["build"] = build
    baseline: Any = UNSET
    marker: Optional[Dict[str, Any]] = None
    if command == "submit" and platform in REBUILD_WORKFLOW and build and BUILD_RE.match(build):
        marker = (marker_lookup or default_marker)(platform, build, env)
        if marker:
            result["marker"] = {k: marker.get(k) for k in ("version", "version_tag", "sha", "whats_new_baseline")}
            if "whats_new_baseline" in marker:
                baseline = marker.get("whats_new_baseline")
            if "store_notes" in marker:
                # The build's generated notes are authoritative, even when empty (nothing user-facing:
                # the store client refuses with no_user_facing_changes instead of shipping generic text).
                notes = str(marker.get("store_notes") or "")
    argv = tool_argv(platform, command, build, dry_run, baseline, replace, publish_at, version)
    code, output = call_tool(main, argv, env, notes)
    result.update(exit_code=code, output=output)
    if marker and isinstance(output, dict) and output.get("refused") == "stale_whats_new" and not dry_run:
        result["rebuild"] = dispatch_rebuild(platform, marker, runner)
    return result


def summary(result: Dict[str, Any]) -> str:
    """Markdown job summary (no secrets: the tools never print them)."""
    return "### store-release %s %s → exit %s\n\n```json\n%s\n```\n" % (
        result["platform"], result["command"], result["exit_code"],
        json.dumps(result.get("output"), indent=2)[:4000])


def main(argv: Optional[List[str]] = None, env: Optional[Dict[str, str]] = None) -> int:
    """Run one store job and write ``--out``."""
    parser = argparse.ArgumentParser(prog="actions_job.py", description=__doc__.split("\n")[0])
    parser.add_argument("--platform", choices=["ios", "windows"], required=True)
    parser.add_argument("--command", choices=["status", "submit", "release"], required=True)
    parser.add_argument("--build")
    parser.add_argument("--version", help="release version YYMM.DD.NN (submit: its build; release: must match)")
    parser.add_argument("--replace", action="store_true", help="submit: replace a submission still in review")
    parser.add_argument("--publish-at", help="Windows submit: publish at this UTC time once certified")
    parser.add_argument("--notes-b64", default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    env = dict(os.environ) if env is None else env
    try:
        result = run_job(args.platform, args.command, args.build, decode_notes(args.notes_b64),
                         args.dry_run, env, version=args.version, replace=args.replace,
                         publish_at=args.publish_at)
    except ValueError as err:
        result = {"platform": args.platform, "command": args.command, "build": args.build,
                  "sha": env.get("GITHUB_SHA"), "dry_run": args.dry_run,
                  "exit_code": fst_release.EXIT_FAIL, "output": {"error": str(err)}}
    Path(args.out).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    summary_path = env.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a") as handle:
            handle.write(summary(result))
    print(json.dumps(result))
    return 0 if result["exit_code"] in QUIET_EXITS else 1


if __name__ == "__main__":
    sys.exit(main())
