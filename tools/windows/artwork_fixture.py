"""Run the anonymized Windows fixture (``rivals_fixture.py``) with every album-art read failing.

The shared mock serves ``/__fixture__/art/{pulse,orbit,white}.png`` for its demo songs; this wrapper answers every
``/__fixture__/art/*`` request with HTTP 404 instead. The Windows app has no per-request ``?scenario=`` switch, so
this is how the artwork backdrop's ``no-art`` state (``fst.shell.artwork-background`` ItemStatus) becomes reachable:
the carousel exhausts its covers and the Song Detail cover falls back to the brand surface.

Usage: ``a11y_matrix.py --fixture tools/windows/artwork_fixture.py
--pages tools/windows/journeys/artwork-background-no-art.json`` (same flags as ``mock_service.py``).
"""

from __future__ import annotations

import sys
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)
import rivals_fixture  # noqa: E402  (sibling wrapper)

#: Path prefix of the mock's album-art routes.
ART_PREFIX = "/__fixture__/art/"


def is_art(path: str) -> bool:
    """Whether a request path is a fixture album-art read.

    Args:
        path: Request path (no query).

    Returns:
        ``True`` for any ``/__fixture__/art/*`` path.
    """
    return path.startswith(ART_PREFIX)


def install() -> None:
    """Patch the mock service in place so every album-art read is a 404."""
    original = mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        if is_art(urlsplit(self.path).path):
            self._json(404, {"status": "fixture_art_unavailable"})
        else:
            original(self)

    mock_service.FixtureHandler.do_GET = do_get


def main() -> None:
    """Install the failing art routes and hand over to ``rivals_fixture``."""
    install()
    rivals_fixture.main()


if __name__ == "__main__":
    main()
