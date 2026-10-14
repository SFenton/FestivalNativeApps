"""Hold page reads long enough to measure Windows loading placement through UI Automation (#624).

The ordinary anonymized fixture supplies every body and header. Only Song Details' all-instrument read and the
Leaderboards overview's first solo/combo boards wait 20 seconds, below the client's 30-second request deadline.
"""

from __future__ import annotations

import sys
import time
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rankings_fixture
import rivals_fixture

DELAY_SECONDS = 20


def delayed(path: str) -> bool:
    """Return whether this fixture read holds a page's first-load gate."""
    return path == "/api/leaderboard/fixture-pulse/all" or rankings_fixture.is_board_read(path)


def main() -> None:
    """Install the slow reads, then serve the ordinary fixture on loopback."""
    original = rivals_fixture.mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:
        """Hold only the reads that determine the page's loading state."""
        if delayed(urlsplit(self.path).path):
            time.sleep(DELAY_SECONDS)
        original(self)

    rivals_fixture.mock_service.FixtureHandler.do_GET = do_get
    rivals_fixture.main()


if __name__ == "__main__":
    main()
