#!/usr/bin/env python3
"""GitHub Actions entry point for every store call (``store-release.yml``).

Store status reads and submissions never run from a developer or agent machine:
the release orchestrator dispatches ``store-release.yml`` and reads the
``result.json`` artifact this script writes::

    actions_job.py --platform windows --command status --out result.json
    actions_job.py --platform windows --command submit --build 0.1.912.0 --notes-b64 <b64> --out result.json

``result.json`` is ``{platform, command, exit_code, output, sha}`` where
``output`` is the JSON document printed by ``fst_release.py`` (exit codes as
there). Policy enforced here, independent of the orchestrator:

- iOS ``submit`` (App Store review, which auto-releases on approval) is refused
  with ``blocked: app_store_review_disabled`` unless
  ``FST_APPSTORE_REVIEW_ENABLED=true`` (repository variable).
- Windows ``submit`` always uses Manual publish mode: certification only, never
  a release.

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
import sys
from contextlib import redirect_stdout
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fst_release  # noqa: E402

BUILD_RE = re.compile(r"^[0-9][0-9.]{0,31}$")
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


def tool_argv(platform: str, command: str, build: Optional[str], dry_run: bool) -> List[str]:
    """Build the ``fst_release.py`` arguments for one job."""
    if command == "status":
        return [platform, "status", "--json"]
    if not build or not BUILD_RE.match(build):
        raise ValueError("submit needs a numeric --build")
    argv = [platform, "submit", "--build", build, "--notes-stdin"]
    if dry_run:
        argv.append("--dry-run")
    return argv


def run_job(platform: str, command: str, build: Optional[str], notes: str, dry_run: bool,
            env: Dict[str, str], main: Any = None) -> Dict[str, Any]:
    """Apply policy, run the release tool in-process and return the result document."""
    result: Dict[str, Any] = {"platform": platform, "command": command, "build": build,
                              "sha": env.get("GITHUB_SHA"), "dry_run": dry_run}
    if command == "submit" and platform == "ios" and env.get("FST_APPSTORE_REVIEW_ENABLED") != "true":
        result.update(exit_code=fst_release.EXIT_BLOCKED, output={"blocked": "app_store_review_disabled"})
        return result
    argv = tool_argv(platform, command, build, dry_run)
    out = io.StringIO()
    with redirect_stdout(out):
        code = (main or fst_release.main)(argv, env=env, stdin=io.StringIO(notes))
    text = out.getvalue().strip()
    try:
        output: Any = json.loads(text.splitlines()[-1]) if text else None
    except ValueError:
        output = {"error": "non-JSON output", "text": text[-500:]}
    result.update(exit_code=code, output=output)
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
    parser.add_argument("--command", choices=["status", "submit"], required=True)
    parser.add_argument("--build")
    parser.add_argument("--notes-b64", default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    env = dict(os.environ) if env is None else env
    try:
        result = run_job(args.platform, args.command, args.build, decode_notes(args.notes_b64),
                         args.dry_run, env)
    except ValueError as err:
        result = {"platform": args.platform, "command": args.command, "build": args.build,
                  "sha": env.get("GITHUB_SHA"), "dry_run": args.dry_run,
                  "exit_code": fst_release.EXIT_FAIL, "output": {"error": str(err)}}
    Path(args.out).write_text(json.dumps(result, indent=2) + "\n")
    summary_path = env.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a") as handle:
            handle.write(summary(result))
    print(json.dumps(result))
    return 0 if result["exit_code"] in QUIET_EXITS else 1


if __name__ == "__main__":
    sys.exit(main())
