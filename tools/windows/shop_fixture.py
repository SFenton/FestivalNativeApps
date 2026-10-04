"""Run the anonymized Windows fixture with an Item Shop scenario forced for every ``/api/shop`` read.

The app never sends the mock service's ``?scenario=`` query, so the Item Shop's empty and failed states (and the
"Song details unavailable" notice, which needs the catalogue read to fail while the feed loads) are otherwise
unreachable from a launched build. This wrapper rewrites the request before the mock handler sees it, then hands
over to ``rivals_fixture.py`` (anonymized names, larger accept backlog, ``Connection: close``).

Usage::

    python tools/windows/shop_fixture.py --shop empty --port 0
    python tools/windows/shop_fixture.py --shop error --port 0
    python tools/windows/shop_fixture.py --songs-fail --port 0

Flags are removed from ``sys.argv`` before the mock service parses its own (``--port`` etc.).
"""

from __future__ import annotations

import sys
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)
import rivals_fixture  # noqa: E402  (sibling wrapper)

#: Mock ``/api/shop`` scenarios this wrapper may force.
SCENARIOS = ("demo", "empty", "error", "shop-single")


def take_options(argv: list[str]) -> tuple[str, bool, list[str]]:
    """Split this wrapper's flags from the mock service's.

    Args:
        argv: Arguments after the script name.

    Returns:
        Shop scenario, whether ``/api/songs`` fails, and the remaining arguments.

    Raises:
        SystemExit: Missing or unknown ``--shop`` value.
    """
    scenario, songs_fail, rest = "demo", False, []
    items = iter(argv)
    for item in items:
        if item == "--shop":
            scenario = next(items, "")
        elif item.startswith("--shop="):
            scenario = item.split("=", 1)[1]
        elif item == "--songs-fail":
            songs_fail = True
        else:
            rest.append(item)
    if scenario not in SCENARIOS:
        raise SystemExit(f"--shop must be one of {', '.join(SCENARIOS)}")
    return scenario, songs_fail, rest


def rewrite(path: str, scenario: str, songs_fail: bool) -> str | None:
    """The request path the mock handler should see, or ``None`` to answer 503.

    Args:
        path: Original request path (with any query).
        scenario: Forced ``/api/shop`` scenario.
        songs_fail: Whether catalogue reads fail.

    Returns:
        A rewritten path, the unchanged path, or ``None`` for a forced catalogue failure.
    """
    route = urlsplit(path).path
    if route == "/api/shop" and scenario != "demo":
        return f"/api/shop?scenario={scenario}"
    if route == "/api/songs" and songs_fail:
        return None
    return path


def install(scenario: str, songs_fail: bool) -> None:
    """Patch the mock fixture handler's ``do_GET`` with :func:`rewrite`.

    Args:
        scenario: Forced ``/api/shop`` scenario.
        songs_fail: Whether catalogue reads fail.
    """
    handler = mock_service.FixtureHandler
    original = handler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        target = rewrite(self.path, scenario, songs_fail)
        if target is None:
            self._json(503, {"status": "fixture_songs_unavailable"})
            return
        self.path = target
        original(self)

    handler.do_GET = do_get


def main() -> None:
    """Install the forced scenario, then run the anonymized fixture."""
    scenario, songs_fail, rest = take_options(sys.argv[1:])
    sys.argv[1:] = rest
    install(scenario, songs_fail)
    rivals_fixture.main()


if __name__ == "__main__":
    main()
