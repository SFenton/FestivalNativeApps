"""Run tools/mock_service.py with catalogue durations, so the Songs Duration sort has bucket headings.

The shared fixture catalogue has no ``durationSeconds``: every row lands in "Unknown Duration", one unlabeled section.
This wrapper gives the ``--large-catalogue`` synthetic rows a spread of durations (under one minute to over ten), so
the Duration sort shows every one-minute bucket heading (issue #282: in-list bucket headings stay transparent like the
Title A–Z ones). The demo songs keep no duration ("Unknown Duration"). Everything else is the unchanged mock service.

Usage: ``python tools/windows/songs_duration_fixture.py --large-catalogue [mock_service.py flags]``, then launch the
app with ``--base-url http://127.0.0.1:<port>/``.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)


def duration_for(index: int) -> int:
    """Seconds for the ``index``-th synthetic row (1-based): 30 s to 12 min 23 s, every minute bucket covered.

    Args:
        index: Position of the row in the synthetic catalogue, from 1.

    Returns:
        A duration in whole seconds.
    """
    return 30 + (index * 37) % 714


def add_durations(songs: list[dict]) -> None:
    """Set ``durationSeconds`` on each synthetic row, in place.

    Args:
        songs: The ``--large-catalogue`` rows.
    """
    for index, song in enumerate(songs, start=1):
        song["durationSeconds"] = duration_for(index)


def main() -> None:
    """Add the durations, then hand over to the mock service's own CLI."""
    add_durations(mock_service.LARGE_CATALOGUE_SONGS)
    # Songs, Shop, artwork and score reads arrive together; socketserver's default backlog of 5 refuses the excess.
    mock_service.FixtureServer.request_queue_size = 128
    mock_service.main()


if __name__ == "__main__":
    main()
