"""Serve all six Rival Detail categories using synthetic comparisons for Quick Links journeys."""

from copy import deepcopy

import rivals_fixture


def main() -> None:
    """Replace the detail sample with five comparisons reaching every category, then serve the fixture."""
    detail = rivals_fixture.mock_service.RIVAL_DETAIL_DEMO
    sample = detail["songs"][0]
    songs = []
    for index, delta in enumerate((-1, -50, 1, 20, 500)):
        song = deepcopy(sample)
        song.update(songId=f"fixture-battle-{index}", title=f"Fixture Battle {index + 1}",
                    instrument="Solo_Guitar", userRank=100, rivalRank=100 + delta, rankDelta=delta)
        songs.append(song)
    detail["songs"] = songs
    rivals_fixture.main()


if __name__ == "__main__":
    main()
