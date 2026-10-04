"""Run tools/mock_service.py with a fixed Item Shop scenario for Songs Filter journeys.

The mock service selects its empty / failing Shop feeds only through ``/api/shop?scenario=…``, which the app never
sends. This wrapper rewrites every app ``/api/shop`` read to the chosen scenario so the Windows Songs Filter can be
driven into ``shop-validated-empty`` (a valid empty feed: Available matches nothing) and ``shop-unavailable-paused``
(503: the saved Shop choice pauses with a notice). Everything else is the unchanged mock service.

Usage: ``python tools/windows/songs_filter_fixture.py --shop empty|error [mock_service.py flags]``, then launch the
app with ``--base-url http://127.0.0.1:<port>/``.
"""

from __future__ import annotations

import sys
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

SHOP_SCENARIOS = ("demo", "empty", "error")


def rewrite(path: str, scenario: str) -> str:
    """Pin an app Shop read to one fixture scenario.

    Args:
        path: Raw request path with query.
        scenario: ``demo``, ``empty`` or ``error``.

    Returns:
        The path to serve; non-Shop paths and explicit ``scenario=`` queries are unchanged.
    """
    parts = urlsplit(path)
    if scenario == "demo" or parts.path != "/api/shop" or "scenario" in parse_qs(parts.query):
        return path
    query = f"{parts.query}&scenario={scenario}" if parts.query else f"scenario={scenario}"
    return f"{parts.path}?{query}"


def split_args(argv: list[str]) -> tuple[str, list[str]]:
    """Take ``--shop SCENARIO`` out of the command line.

    Args:
        argv: Arguments after the program name.

    Returns:
        The Shop scenario and the remaining mock_service.py arguments.

    Raises:
        SystemExit: Unknown scenario or a missing value.
    """
    rest, scenario = [], "demo"
    items = iter(argv)
    for item in items:
        if item == "--shop":
            scenario = next(items, "")
        elif item.startswith("--shop="):
            scenario = item.split("=", 1)[1]
        else:
            rest.append(item)
    if scenario not in SHOP_SCENARIOS:
        raise SystemExit(f"--shop must be one of {', '.join(SHOP_SCENARIOS)}")
    return scenario, rest


def main() -> None:
    """Patch the Shop route, then hand over to the mock service's own CLI."""
    scenario, rest = split_args(sys.argv[1:])
    sys.argv = [sys.argv[0], *rest]
    original = mock_service.FixtureHandler.do_GET

    def do_get(self) -> None:  # noqa: ANN001 (stdlib handler signature)
        self.path = rewrite(self.path, scenario)
        original(self)

    mock_service.FixtureHandler.do_GET = do_get
    # Songs, Shop, artwork and score reads arrive together; socketserver's default backlog of 5 refuses the excess.
    mock_service.FixtureServer.request_queue_size = 128
    mock_service.main()


if __name__ == "__main__":
    main()
