"""Run tools/mock_service.py with every Settings Service Info state for the Windows UI tests (issue #275).

The shared mock answers ``GET /api/service-info`` with an idle worker or, with ``--service-info-discovery``, one
band-discovery snapshot. This wrapper adds ``--service-info <state>`` so every state the card can reach is
observable through UI Automation (``.agents/pages/settings/windows.md``):

==================  =========================================================================================
State               ``/api/service-info`` answer → card
==================  =========================================================================================
``loading``         The first read is held :data:`LOADING_DELAY_SECONDS` and then answers idle; later reads answer
                    at once → "Loading" · Loading with the spinner, state row only, then "Waiting for the Next
                    Update". The hold outlasts the app's 3 s request timeout, so the page lengthens it with the
                    Debug/automation ``FST_DEBUG_SERVICE_INFO_TIMEOUT_MS`` hook (opening Settings, scrolling to
                    the card, the checks and an Axe scan take ~4 s). Loading only precedes the first read after
                    Settings opens, so the page starts on Songs and opens Settings itself.
``idle``            Idle worker → "Waiting for the Next Update" · Idle, publication row
``discovery``       Band discovery, 24.8% of 5,000 accounts, attempts → bar, attempt line, spoken percent/units
``monotonic``       Band discovery whose attempt counts go 1,310 → 1,200 → 1,200 (a lower, older count) → 1,400:
                    the card keeps 1,310 for the lower reads and shows 1,400 on the fourth (never backwards). The
                    sequence counts reads per fixture service, so its journey page runs at one size and mode.
``indeterminate``   Updating with no known total → empty track, no attempt line, "Total not yet known" spoken
``failed``          Online worker, last update failed → "Last Leaderboard Update Failed" · Idle
``stopped``         Offline worker → "Leaderboard Updater Unavailable" · Stopped
``unpublished``     Idle, nothing published yet → "No successful publication yet"
``unavailable``     HTTP 503 → "Failed to load data" · Stopped, state row only
==================  =========================================================================================

A read held past the app's timeout shows "Failed to load data" instead (``SettingsServiceInfoTests`` covers that and
the default 3 s timeout).

Every other route is the anonymized mock (``rivals_fixture.py``). Fixture-only: never point this at, or capture
evidence from, it.

Usage: ``python tools/windows/service_info_fixture.py --port 0 --service-info discovery`` (other flags pass through
to mock_service.py).
"""

from __future__ import annotations

import argparse
import copy
import sys
import threading
import time
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)
import rivals_fixture  # noqa: E402  (sibling wrapper: anonymized names)

ROUTE = "/api/service-info"
#: ``monotonic`` attempt counts per read (5 s apart): the lower count holds for two reads so a check ~6 s after the
#: first read sees it kept back; the last repeats.
MONOTONIC_ATTEMPTS = ((1310, 70), (1200, 60), (1200, 60), (1400, 80))
#: ``loading`` hold on the first read: long enough to check and scan Loading, and shorter than the page's
#: ``FST_DEBUG_SERVICE_INFO_TIMEOUT_MS`` so the card shows Loading rather than "Failed to load data".
LOADING_DELAY_SECONDS = 8.0
STATES = ("loading", "idle", "discovery", "monotonic", "indeterminate", "failed", "stopped", "unpublished",
          "unavailable")


def _discovery(attempted: int, unavailable: int) -> dict:
    """The mock's band-discovery body with other attempt counts.

    Args:
        attempted: ``attemptedThisPass``.
        unavailable: ``retryableUnavailableThisPass``.

    Returns:
        A fresh body.
    """
    body = copy.deepcopy(mock_service.SERVICE_INFO_DISCOVERY)
    body["currentUpdate"]["attemptProgress"] = {
        "schemaVersion": 1, "attemptedThisPass": attempted, "retryableUnavailableThisPass": unavailable}
    return body


def response(state: str, read: int) -> tuple[int, dict]:
    """Status and body for the ``read``-th (0-based) Service Info read in ``state``.

    Args:
        state: One of :data:`STATES`.
        read: Reads already answered in this state.

    Returns:
        ``(status, body)``.

    Raises:
        ValueError: Unknown state.
    """
    idle = copy.deepcopy(mock_service.SERVICE_INFO_IDLE)
    if state in ("idle", "loading"):
        return 200, idle
    if state == "discovery":
        return 200, copy.deepcopy(mock_service.SERVICE_INFO_DISCOVERY)
    if state == "monotonic":
        return 200, _discovery(*MONOTONIC_ATTEMPTS[min(read, len(MONOTONIC_ATTEMPTS) - 1)])
    if state == "indeterminate":
        body = copy.deepcopy(mock_service.SERVICE_INFO_DISCOVERY)
        current = body["currentUpdate"]
        current.update(phaseId="scrape.leaderboards", phase="Scrape", unitsKind="leaderboards", unitsCompleted=None,
                       unitsTotal=None, unitsTotalFinal=False, phasePercent=None)
        current.pop("attemptProgress")
        return 200, body
    if state == "failed":
        idle["currentUpdate"]["status"] = "failed"
        return 200, idle
    if state == "stopped":
        idle["workerStatus"] = {"workerKey": "fixture-worker", "status": "offline", "rawStatus": "offline"}
        return 200, idle
    if state == "unpublished":
        idle["lastCompletedUpdate"] = None
        idle["publication"]["publishedAt"] = None
        return 200, idle
    if state == "unavailable":
        return 503, {"status": "service_unavailable"}
    raise ValueError(f"unknown Service Info state {state!r}; use one of {', '.join(STATES)}")


def delay(state: str, read: int) -> float:
    """Seconds to hold the ``read``-th (0-based) Service Info read before answering.

    Args:
        state: One of :data:`STATES`.
        read: Reads already answered in this state.

    Returns:
        :data:`LOADING_DELAY_SECONDS` for the first ``loading`` read, else 0.
    """
    return LOADING_DELAY_SECONDS if state == "loading" and read == 0 else 0.0


class ServiceInfoState:
    """Counts reads so ``monotonic`` can step through its sequence and ``loading`` holds only the first."""

    def __init__(self, state: str) -> None:
        """Remember the state.

        Args:
            state: One of :data:`STATES`.
        """
        response(state, 0)
        self.state = state
        self.reads = 0
        self.lock = threading.Lock()

    def next(self) -> tuple[int, dict, float]:
        """The next read's answer (thread-safe).

        Returns:
            ``(status, body, seconds to hold it)``.
        """
        with self.lock:
            read = self.reads
            self.reads += 1
        return (*response(self.state, read), delay(self.state, read))


def install(state: ServiceInfoState) -> None:
    """Patch the mock handler so Service Info reads answer from ``state``.

    Args:
        state: The configured state.
    """
    handler = mock_service.FixtureHandler
    original_get = handler.do_GET

    def do_GET(self) -> None:  # noqa: N802 (stdlib handler name)
        if urlsplit(self.path).path == ROUTE:
            status, body, hold = state.next()
            if hold:
                time.sleep(hold)
            self._json(status, body)
            return
        original_get(self)

    handler.do_GET = do_GET


def parse_options(argv: list[str]) -> tuple[argparse.Namespace, list[str]]:
    """Split this wrapper's flags from the mock service's.

    Args:
        argv: Arguments after the script name.

    Returns:
        This wrapper's options and the remaining arguments.
    """
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--service-info", choices=STATES, default="idle")
    return parser.parse_known_args(argv)


def main() -> None:
    """Parse this wrapper's flags, then hand the rest to the anonymized mock's own CLI."""
    options, rest = parse_options(sys.argv[1:])
    install(ServiceInfoState(options.service_info))
    sys.argv = [sys.argv[0], *rest]
    rivals_fixture.main()


if __name__ == "__main__":
    main()
