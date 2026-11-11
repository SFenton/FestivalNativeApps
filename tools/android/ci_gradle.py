#!/usr/bin/env python3
"""Run the Android Gradle build in CI, retrying a transient dependency download failure (#697).

CI jobs download any dependency file the restored Gradle cache lacks. One 404 or HTTP error from
the repository fails the build with ``Could not find listenablefuture-1.0.jar (...)`` even though
the file exists (releases/2611.09 ``android-device``, run 43017000822). Gradle caches that miss in
the Gradle user home, so a plain rerun fails again without asking the server; a retry must pass
``--refresh-dependencies``. Only download failures are retried: compile, lint and test failures
(and a genuinely unknown module, ``Could not find group:name:version.``) fail on the first attempt.

Usage (from the repo root)::

    python3 tools/android/ci_gradle.py :app:assembleDebug :app:assembleDebugAndroidTest --no-daemon
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable, Iterable, Sequence

ROOT = Path(__file__).resolve().parents[2]
ATTEMPTS = 3
RETRY_DELAYS_SECONDS = (30, 60)
REFRESH_FLAG = "--refresh-dependencies"

# region Failure classification

_TRANSIENT_PATTERNS = (
    # An artifact or metadata file the repository answered 404 for (#697).
    re.compile(r"Could not find \S+\.(?:jar|aar|pom|module)\b"),
    # HTTP or connection errors that outlived Gradle's own retries (429, 5xx, resets, timeouts).
    re.compile(r"Could not (?:GET|HEAD) '"),
    re.compile(r"Could not download \S+"),
    re.compile(r"Could not resolve [\w.-]+:[\w.-]+:[\w.+-]+\."),
)


def is_transient_dependency_failure(lines: Iterable[str]) -> bool:
    """Tells whether a failed build's output shows a dependency download failure.

    :param lines: The build's combined stdout and stderr lines.
    :return: ``True`` when a line reports a repository fetch failure that a retry can fix.
    """
    return any(pattern.search(line) for line in lines for pattern in _TRANSIENT_PATTERNS)


# endregion

# region Running Gradle


def gradle_command(args: Sequence[str]) -> list[str]:
    """Builds the wrapper invocation for the ``android`` project on this OS.

    :param args: Gradle tasks and options.
    :return: The argv list (``gradlew`` runs through ``bash``: it is committed without +x).
    """
    if os.name == "nt":
        return [str(ROOT / "android" / "gradlew.bat"), "-p", str(ROOT / "android"), *args]
    return ["bash", str(ROOT / "android" / "gradlew"), "-p", str(ROOT / "android"), *args]


def run_streaming(argv: Sequence[str]) -> tuple[int, list[str]]:
    """Runs a command, echoing its output live and keeping it for classification.

    :param argv: The command to run.
    :return: The exit code and the output lines.
    """
    lines: list[str] = []
    with subprocess.Popen(
        argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace", cwd=ROOT
    ) as process:
        assert process.stdout is not None
        for line in process.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            lines.append(line)
    return process.returncode, lines


def run_with_retry(
    args: Sequence[str],
    run: Callable[[Sequence[str]], tuple[int, list[str]]] = run_streaming,
    sleep: Callable[[float], None] = time.sleep,
    attempts: int = ATTEMPTS,
) -> int:
    """Runs Gradle, retrying with ``--refresh-dependencies`` after a dependency download failure.

    :param args: Gradle tasks and options.
    :param run: Runs one argv and returns its exit code and output lines.
    :param sleep: Waits between attempts.
    :param attempts: The maximum number of Gradle runs.
    :return: The exit code of the last run.
    """
    code = 1
    for attempt in range(1, attempts + 1):
        attempt_args = list(args)
        if attempt > 1 and REFRESH_FLAG not in attempt_args:
            attempt_args.append(REFRESH_FLAG)
        code, lines = run(gradle_command(attempt_args))
        if code == 0:
            return 0
        if attempt == attempts or not is_transient_dependency_failure(lines):
            return code
        delay = RETRY_DELAYS_SECONDS[min(attempt - 1, len(RETRY_DELAYS_SECONDS) - 1)]
        print(
            f"ci_gradle: attempt {attempt} failed to download a dependency; "
            f"retrying with {REFRESH_FLAG} in {delay} s (#697)",
            flush=True,
        )
        sleep(delay)
    return code


# endregion


def main(argv: Sequence[str]) -> int:
    """Entry point: forwards every argument to Gradle."""
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    return run_with_retry(argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
