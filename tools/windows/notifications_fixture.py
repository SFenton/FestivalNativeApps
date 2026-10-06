"""Run tools/mock_service.py with switchable notification feeds for the Windows Notifications journeys (issue #229).

The shared mock answers ``/api/player/fixture-player-1/notifications`` with two song rows and every other fixture
account with a never-generated empty feed. That reaches neither "generated but empty", a rankings destination, a
row without a destination nor a failed read, so this wrapper answers the notifications read for every ``fixture-*``
account itself and lets a journey change the feed between phases through a loopback control route:

``GET /__notifications__/mode?feed=<rich|media|mock|empty|not-generated|error|slow>[&reset=1]``

* ``rich`` (default): five rows covering every Windows row shape and destination: a song rank climb (Song Detail on
  Lead), a Full Combo (Song Detail on Bass), an FC-rate rank climb (Leaderboards ranked by FC Rate), an aggregate
  total-score improvement (no destination) and an Item Shop song (art from the catalogue, no flag).
* ``media`` (issue #272): six song rows covering the media rail and flag chips: a multi-chart personal best (art
  above a three-instrument grid, "Affected instruments" in its name) and one row per remaining flag kind (First Play,
  Stars Up, Gold Stars, Difficulty Up, New High Score).
* ``mock``: the unchanged mock feed.
* ``empty``: a generated feed with no rows (``notifications.empty.generatedBody``).
* ``not-generated``: no detection run yet (``notifications.empty.notGeneratedBody``).
* ``error``: HTTP 503 without a freeze header (failed state with Retry).
* ``slow``: holds the ``rich`` feed until a control request leaves ``slow`` (at most ``--slow-seconds``).

Every control response also reports ``reads``, the notifications reads served since the last ``reset=1``, so a
journey can prove that a state sends no request (no selected profile).

In ``rich`` mode the accounts in :data:`ACCOUNT_FEEDS` keep a fixed feed instead, so a page list for
``a11y_matrix.py --fixture`` reaches every state by selected profile alone (e.g. ``fixture-feed-empty``).

Usage: ``python tools/windows/notifications_fixture.py --port 0 [--feed empty] [--slow-seconds 300]`` (other flags pass
through to mock_service.py). Loopback only; never production. Every row is synthetic (no production payloads/IDs).
"""

from __future__ import annotations

import argparse
import re
import sys
import threading
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

#: Feeds this wrapper can serve.
FEED_MODES = ("rich", "media", "mock", "empty", "not-generated", "error", "slow")
#: Control route a journey calls between phases.
CONTROL_PATH = "/__notifications__/mode"
#: Notifications read for any fixture account.
NOTIFICATIONS = re.compile(r"^/api/player/(fixture-[a-z0-9-]+)/notifications$")
#: Accounts whose feed stays fixed while the mode is ``rich``.
ACCOUNT_FEEDS = {
    "fixture-feed-empty": "empty",
    "fixture-feed-new": "not-generated",
    "fixture-feed-error": "error",
    "fixture-feed-media": "media",
}


def rich_feed(account_id: str) -> dict:
    """Build the five-row feed, newest first.

    Args:
        account_id: Fixture account the rows belong to (the shop row has none, as in production).

    Returns:
        The notifications envelope.
    """
    def row(event_id: int, guid: str, kind: str, day: int, **fields) -> dict:
        return {
            "eventId": event_id, "notificationGuid": guid, "accountId": account_id, "eventKind": kind,
            "detectedAt": f"2024-01-{day:02d}T12:00:00Z", "expiresAt": f"2024-02-{day:02d}T12:00:00Z", **fields,
        }

    shop = row(5, "fixture-notif-shop", "service_new_shop_song", 1, songId="fixture-orbit",
               payload={"songTitle": "Fixture Orbit", "artist": "Synthetic Quartet"})
    shop["accountId"] = None
    return {
        "generatedAt": "2024-01-05T00:00:00Z", "expiresAfterHours": 72,
        "sourceRunId": 1, "sourceCompletedAt": "2024-01-05T00:00:00Z", "notificationsGenerated": True,
        "items": [
            row(1, "fixture-notif-rank", "player_song_rank_improved", 5, songId="fixture-pulse",
                instrument="Solo_Guitar", oldRank=9, newRank=4),
            row(2, "fixture-notif-fc", "player_fc_achieved", 4, songId="fixture-orbit", instrument="Solo_Bass"),
            row(3, "fixture-notif-fcrate", "player_fc_rate_rank_improved", 3, instrument="Solo_Drums",
                metric="fc_rate_rank", oldRank=120, newRank=45),
            row(4, "fixture-notif-total", "player_total_score_improved", 2, instrument="Solo_Vocals",
                oldNumeric=1200000, newNumeric=1234567),
            shop,
        ],
    }


def media_feed(account_id: str) -> dict:
    """Build the six-row media/flags feed, newest first (issue #272).

    Args:
        account_id: Fixture account the rows belong to.

    Returns:
        The notifications envelope.
    """
    def row(event_id: int, guid: str, kind: str, day: int, **fields) -> dict:
        return {
            "eventId": event_id, "notificationGuid": guid, "accountId": account_id, "eventKind": kind,
            "detectedAt": f"2024-01-{day:02d}T12:00:00Z", "expiresAt": f"2024-02-{day:02d}T12:00:00Z", **fields,
        }

    return {
        "generatedAt": "2024-01-07T00:00:00Z", "expiresAfterHours": 72,
        "sourceRunId": 1, "sourceCompletedAt": "2024-01-07T00:00:00Z", "notificationsGenerated": True,
        "items": [
            row(11, "fixture-notif-grid", "player_score_pb", 7, songId="fixture-pulse", instrument="Solo_Guitar",
                oldNumeric=180000, newNumeric=201234,
                payload={"coalescedInstruments": ["Solo_Guitar", "Solo_Bass", "Solo_Drums"]}),
            row(12, "fixture-notif-first", "player_first_score", 6, songId="fixture-orbit", instrument="Solo_Bass",
                newNumeric=154321),
            row(13, "fixture-notif-stars", "player_stars_improved", 5, songId="fixture-pulse", instrument="Solo_Drums",
                oldNumeric=4, newNumeric=5),
            row(14, "fixture-notif-gold", "player_gold_stars_achieved", 4, songId="fixture-orbit",
                instrument="Solo_Vocals"),
            row(15, "fixture-notif-difficulty", "player_difficulty_bumped", 3, songId="fixture-pulse",
                instrument="Solo_Guitar", oldNumeric=2, newNumeric=3),
            row(16, "fixture-notif-pb", "player_score_pb", 2, songId="fixture-orbit", instrument="Solo_Drums",
                oldNumeric=99000, newNumeric=123456),
        ],
    }


def empty_feed(generated: bool) -> dict:
    """Build an empty envelope.

    Args:
        generated: Whether a detection run produced it.

    Returns:
        The envelope.
    """
    return {
        "generatedAt": "2024-01-05T00:00:00Z", "expiresAfterHours": 72,
        "sourceRunId": 1 if generated else None,
        "sourceCompletedAt": "2024-01-05T00:00:00Z" if generated else None,
        "notificationsGenerated": generated, "items": [],
    }


class FeedState:
    """Current feed mode, shared by the server's handler threads."""

    def __init__(self, feed: str = "rich", slow_seconds: float = 300.0) -> None:
        """Create the state.

        Args:
            feed: Initial mode (one of :data:`FEED_MODES`).
            slow_seconds: Longest a ``slow`` read is held.
        """
        self._lock = threading.Lock()
        #: Set whenever the mode is not ``slow``; held reads wait on it.
        self.released = threading.Event()
        self.slow_seconds = slow_seconds
        self.feed = "rich"
        self.reads = 0
        self.update({"feed": [feed]})

    def update(self, query: dict[str, list[str]]) -> dict[str, str | int]:
        """Apply a control request.

        Args:
            query: Parsed control query (``feed`` and/or ``reset=1``).

        Returns:
            The mode now in effect and the reads served since the last reset.

        Raises:
            ValueError: An unknown key or mode.
        """
        unknown = set(query) - {"feed", "reset"}
        if unknown:
            raise ValueError(f"unknown control key(s): {', '.join(sorted(unknown))}")
        feed = query.get("feed", [None])[-1]
        if feed is not None and feed not in FEED_MODES:
            raise ValueError(f"unknown feed mode: {feed}")
        with self._lock:
            if feed is not None:
                self.feed = feed
                if feed == "slow":
                    self.released.clear()
                else:
                    self.released.set()
            if query.get("reset", ["0"])[-1] == "1":
                self.reads = 0
            return {"feed": self.feed, "reads": self.reads}

    def route(self, path: str) -> tuple[str, str] | None:
        """Decide how this wrapper answers a request.

        Args:
            path: Request path without the query string.

        Returns:
            ``("control", "")`` or ``(mode, account)`` for a notifications read; ``None`` defers to the mock.
        """
        if path == CONTROL_PATH:
            return ("control", "")
        match = NOTIFICATIONS.fullmatch(path)
        if match is None:
            return None
        with self._lock:
            feed = self.feed
            self.reads += 1
        account = match.group(1)
        if feed == "rich":
            feed = ACCOUNT_FEEDS.get(account, feed)
        return None if feed == "mock" else (feed, account)


def install(state: FeedState) -> None:
    """Patch the mock handler so notifications reads follow ``state``.

    Args:
        state: Shared mode.
    """
    handler = mock_service.FixtureHandler
    original = handler.do_GET

    def do_GET(self) -> None:  # noqa: N802 (stdlib handler name)
        parsed = urlsplit(self.path)
        kind = state.route(parsed.path)
        if kind is None:
            original(self)
            return
        mode, account = kind
        if mode == "control":
            try:
                self._json(200, state.update(parse_qs(parsed.query)))
            except ValueError as error:
                self._json(400, {"status": str(error)})
        elif mode == "error":
            self._json(503, {"status": "fixture_unavailable"})
        elif mode in ("empty", "not-generated"):
            self._json(200, empty_feed(mode == "empty"))
        elif mode == "media":
            self._json(200, media_feed(account))
        else:
            if mode == "slow":
                state.released.wait(state.slow_seconds)
            self._json(200, rich_feed(account))

    handler.do_GET = do_GET
    # Artwork bursts can overflow socketserver's default backlog of 5 (see rivals_fixture.py).
    mock_service.FixtureServer.request_queue_size = 128


def main() -> None:
    """Parse this wrapper's flags, then hand the rest to the mock service's own CLI."""
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--feed", choices=FEED_MODES, default="rich")
    parser.add_argument("--slow-seconds", type=float, default=300.0)
    options, rest = parser.parse_known_args()
    install(FeedState(options.feed, options.slow_seconds))
    sys.argv = [sys.argv[0], *rest]
    mock_service.main()


if __name__ == "__main__":
    main()
