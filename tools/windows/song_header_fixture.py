"""Run tools/mock_service.py with a song title and artist too long for any song header (Windows UI tests, issue #315).

The song-header-title pattern (``.agents/patterns/song-header-title.md``) draws the song title and its artist line
on one line each, scrolling when they overflow and ellipsized when motion is off. The demo titles fit every header,
so this wrapper renames ``fixture-pulse`` to :data:`LONG_TITLE` by :data:`LONG_ARTIST` in the served catalogue (with
its own ETag). Every route that names the song (Song Detail, Song Leaderboard, Band Song Leaderboard, Player History)
then shows the long text; every other response is the unchanged mock service.

Usage: ``python tools/windows/song_header_fixture.py --port 0`` (other flags pass through to mock_service.py), or
``python tools/windows/ui_journey.py tools/windows/journeys/song-header-title.json --fixture tools/windows/song_header_fixture.py``.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

SONG_ID = "fixture-pulse"
#: Wider than any header column at the compact preset, and wider than Song Detail's at wide.
LONG_TITLE = "Fixture Pulse and the Extraordinarily Long Song Title That Never Fits on One Line"
LONG_ARTIST = "Synthetic Quartet featuring the Extraordinarily Long Guest Ensemble Name"
ETAG = '"fst-fixture-songs-long-title-v1"'


def install() -> None:
    """Renames :data:`SONG_ID` in the served catalogue and gives the catalogue its own ETag.

    The handler reads ``mock_service.DEMO_SONGS`` and ``SONGS_ETAG`` at request time, so replacing the module globals
    is enough; the loaded fixture file is untouched.
    """
    songs = [
        {**song, "title": LONG_TITLE, "artist": LONG_ARTIST} if song["songId"] == SONG_ID else song
        for song in mock_service.DEMO_SONGS["songs"]
    ]
    if not any(song["songId"] == SONG_ID for song in songs):
        raise ValueError(f"{SONG_ID} is missing from the demo catalogue")
    mock_service.DEMO_SONGS = {**mock_service.DEMO_SONGS, "songs": songs}
    mock_service.SONGS_ETAG = ETAG
    # Song pages read the catalogue, boards and artwork at once; socketserver's default backlog of 5 overflows.
    mock_service.FixtureServer.request_queue_size = 128


def main() -> None:
    """Installs the long song, then hands the command line to the mock service."""
    install()
    mock_service.main()


if __name__ == "__main__":
    main()
