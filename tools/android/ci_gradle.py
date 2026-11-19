#!/usr/bin/env python3
"""Run the Android Gradle build in CI, retrying a transient dependency download failure (#697).

CI jobs download any dependency file the restored Gradle cache lacks. One 404 or HTTP error from
the repository fails the build with ``Could not find listenablefuture-1.0.jar (...)`` even though
the file exists (releases/2611.09 ``android-device``, run 43017000822). Gradle caches that miss in
the Gradle user home, so a plain rerun fails again without asking the server; a retry must pass
``--refresh-dependencies``. A rate limit or server error (``Received status code 429``, 5xx, a
reset) is different (releases/2611.16 ``android-fold``, run 44519886675, #702): Gradle does not
cache it, and ``--refresh-dependencies`` would re-request every cached file and hit the limit again,
so those retries keep the cache and back off longer. Gradle does not report ``Retry-After``, so the
backoff is fixed plus jitter, which keeps parallel release jobs from retrying together. Only
download failures are retried: compile, lint and test failures (and a genuinely unknown module,
``Could not find group:name:version.``) fail on the first attempt.

Usage (from the repo root)::

    python3 tools/android/ci_gradle.py :app:assembleDebug :app:assembleDebugAndroidTest --no-daemon
"""

from __future__ import annotations

import os
import random
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable, Optional, Sequence

ROOT = Path(__file__).resolve().parents[2]
ATTEMPTS = 3
# A cached 404 only needs a short wait before Gradle asks the server again.
RETRY_DELAYS_SECONDS = (30, 60)
# A 429/5xx needs the server's limit window to pass (#702).
SERVER_RETRY_DELAYS_SECONDS = (120, 300)
SERVER_RETRY_JITTER_SECONDS = 30.0
REFRESH_FLAG = "--refresh-dependencies"

# region Failure classification

# An artifact or metadata file the repository answered 404 for; Gradle caches the miss (#697).
_CACHED_MISS_PATTERNS = (re.compile(r"Could not find \S+\.(?:jar|aar|pom|module)\b"),)
# HTTP or connection errors that outlived Gradle's own retries (429, 5xx, resets, timeouts).
_SERVER_ERROR_PATTERNS = (
    re.compile(r"Could not (?:GET|HEAD) '"),
    re.compile(r"Could not download \S+"),
    re.compile(r"Could not resolve [\w.-]+:[\w.-]+:[\w.+-]+\."),
)


@dataclass(frozen=True)
class DownloadFailure:
    """What a failed build's dependency download needs from the next attempt.

    :ivar cached_miss: A repository 404 that Gradle cached; only ``--refresh-dependencies`` clears it.
    :ivar server_error: A 429, 5xx or connection error; the retry waits out the server's limit.
    """

    cached_miss: bool
    server_error: bool


def classify_download_failure(lines: Iterable[str]) -> Optional[DownloadFailure]:
    """Classifies a failed build's output by the dependency download failures it reports.

    :param lines: The build's combined stdout and stderr lines.
    :return: The failure kinds found, or ``None`` when the build failed for another reason.
    """
    cached_miss = server_error = False
    for line in lines:
        cached_miss = cached_miss or any(p.search(line) for p in _CACHED_MISS_PATTERNS)
        server_error = server_error or any(p.search(line) for p in _SERVER_ERROR_PATTERNS)
    if not (cached_miss or server_error):
        return None
    return DownloadFailure(cached_miss=cached_miss, server_error=server_error)


def is_transient_dependency_failure(lines: Iterable[str]) -> bool:
    """Tells whether a failed build's output shows a dependency download failure.

    :param lines: The build's combined stdout and stderr lines.
    :return: ``True`` when a line reports a repository fetch failure that a retry can fix.
    """
    return classify_download_failure(lines) is not None


def retry_delay(failure: DownloadFailure, attempt: int, jitter: Callable[[], float]) -> float:
    """Chooses the wait before the next attempt.

    :param failure: The failure the last attempt reported.
    :param attempt: The 1-based number of the attempt that failed.
    :param jitter: Returns extra seconds added to a server-error backoff.
    :return: Seconds to wait.
    """
    delays = SERVER_RETRY_DELAYS_SECONDS if failure.server_error else RETRY_DELAYS_SECONDS
    delay = float(delays[min(attempt - 1, len(delays) - 1)])
    return delay + jitter() if failure.server_error else delay


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
    jitter: Callable[[], float] = lambda: random.uniform(0.0, SERVER_RETRY_JITTER_SECONDS),
) -> int:
    """Runs Gradle, retrying a dependency download failure.

    A cached 404 is retried with ``--refresh-dependencies`` (kept on every later attempt, since the
    miss stays cached until a refreshed run reaches it); a 429/5xx is retried with the cache intact
    after a longer backoff.

    :param args: Gradle tasks and options.
    :param run: Runs one argv and returns its exit code and output lines.
    :param sleep: Waits between attempts.
    :param attempts: The maximum number of Gradle runs.
    :param jitter: Returns extra seconds added to a server-error backoff.
    :return: The exit code of the last run.
    """
    code = 1
    refresh = False
    for attempt in range(1, attempts + 1):
        attempt_args = list(args)
        if refresh and REFRESH_FLAG not in attempt_args:
            attempt_args.append(REFRESH_FLAG)
        code, lines = run(gradle_command(attempt_args))
        if code == 0:
            return 0
        failure = classify_download_failure(lines)
        if attempt == attempts or failure is None:
            return code
        refresh = refresh or failure.cached_miss
        delay = retry_delay(failure, attempt, jitter)
        if refresh:
            how = f"with {REFRESH_FLAG} (#697)"
        else:
            how = "keeping the Gradle cache after a rate limit or server error (#702)"
        print(
            f"ci_gradle: attempt {attempt} failed to download a dependency; "
            f"retrying {how} in {delay:.0f} s",
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
