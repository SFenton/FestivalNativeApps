"""Run tools/mock_service.py with anonymized Rivals display names.

The shared Rivals fixtures in contracts/fixtures were captured from live shapes and still carry real player
names. Committed Windows screenshots must not show real names, so this wrapper swaps every rival display
name for a deterministic "Demo Rival N" before serving. Everything else (routes, scenarios such as the
``-empty``/``-503`` account suffixes, songs and artwork) is the unchanged mock service.

Usage: ``python tools/windows/rivals_fixture.py --port 8765`` (same flags as mock_service.py), then launch the
app with ``--base-url http://127.0.0.1:8765/`` and ``FST_DEBUG_PROFILE=fixture-player-1:Demo Player``.
"""

from __future__ import annotations

import sys
from http.server import BaseHTTPRequestHandler
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)


def anonymize(payload: dict, names: dict[str, str]) -> None:
    """Replace every rival display name in a Rivals payload in place.

    Args:
        payload: A rivals list, leaderboard-rivals list or rival detail body.
        names: Account ID to demo name, extended as new accounts are seen.
    """
    rows = [*payload.get("above", []), *payload.get("below", [])]
    if "rival" in payload:
        rows.append(payload["rival"])
    for row in rows:
        account = row["accountId"]
        names.setdefault(account, f"Demo Rival {len(names) + 1}")
        row["displayName"] = names[account]


def name_detail_bodies(names: dict[str, str]) -> None:
    """Make each rival detail body carry the requested rival's demo name.

    The mock serves one shared detail payload for every rival, so without this every rival opens as the
    first demo name and a journey cannot tell which rival the detail column shows.

    Args:
        names: Account ID to demo name, as built by :func:`anonymize`.
    """
    for builder_name, id_index in (("_rival_detail_body", 1), ("_leaderboard_rival_detail_body", 2)):
        original = getattr(mock_service, builder_name)

        def build(*args, _original=original, _id_index=id_index):  # noqa: ANN002, ANN202 (mirrors the builder)
            body = _original(*args)
            rival_id = args[_id_index]
            if rival_id in names:
                body["rival"] = {**body["rival"], "displayName": names[rival_id]}
            return body

        setattr(mock_service, builder_name, build)


def main() -> None:
    """Anonymize the Rivals fixtures, then hand over to the mock service's own CLI."""
    names: dict[str, str] = {}
    for payload in (
        mock_service.RIVALS_LIST_DEMO,
        mock_service.LEADERBOARD_RIVALS_DEMO,
        mock_service.RIVAL_DETAIL_DEMO,
        mock_service.LEADERBOARD_RIVAL_DETAIL_DEMO,
    ):
        anonymize(payload, names)
    name_detail_bodies(names)
    # The app's carousel art plus up to four concurrent Rivals reads overflow socketserver's default backlog
    # of 5, and Windows refuses the excess connections (the app then shows "You're offline").
    mock_service.FixtureServer.request_queue_size = 128
    # The stdlib server answers HTTP/1.0 and closes each socket; without an explicit "Connection: close" .NET's
    # pooled client occasionally reuses a closing socket (WSAECONNABORTED -> the app reports "offline").
    for handler in vars(mock_service).values():
        if isinstance(handler, type) and issubclass(handler, BaseHTTPRequestHandler) and handler is not BaseHTTPRequestHandler:
            original = handler.end_headers

            def end_headers(self, _original=original):  # noqa: ANN001 (stdlib handler signature)
                self.send_header("Connection", "close")
                _original(self)

            handler.end_headers = end_headers
    mock_service.main()


if __name__ == "__main__":
    main()
