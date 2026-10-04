"""Run tools/mock_service.py with designed score-accuracy rows for Windows UI tests.

The shared mock's song leaderboard (``/api/leaderboard/{songId}/Solo_Guitar``) gives every rank a ~98% accuracy,
omits accuracy on ranks 3 and 4 and marks even ranks as full combos. The score-accuracy control has more reachable
states (``.agents/controls/score-accuracy/spec.md``), so this wrapper rewrites the first ranks' ``accuracy`` and
``isFullCombo`` after the mock built the page, keeping its validation, pagination and every other route:

=====  ==========================  ======================================
Rank   State                       Wire (ten-thousandths of a percent)
=====  ==========================  ======================================
1      graded-high                 ``accuracy=995000``, FC false
2      full-combo                  ``accuracy=1000000``, FC true
3      absent                      no accuracy, FC false
4      full-combo-no-accuracy      no accuracy, FC true
5      graded-mid                  ``accuracy=500000``, FC false
6      graded-low                  ``accuracy=120000``, FC false
7      invalid (out of range)      ``accuracy=1050000``, FC false
=====  ==========================  ======================================

Ranks 8-26 keep the mock's values (graded ~98%, FC on even ranks). JSON cannot carry NaN or infinity, so non-finite
input is a unit-test state (``ScoreAccuracyTests``), not a wire state.

Usage: ``python tools/windows/score_accuracy_fixture.py --port 0`` (other flags pass through to mock_service.py).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)

CHART = re.compile(r"^/api/leaderboard/(fixture-[a-z0-9-]+)/Solo_Guitar$")

#: rank -> (accuracy or None to omit it, isFullCombo).
DESIGNED: dict[int, tuple[int | None, bool]] = {
    1: (995_000, False),
    2: (1_000_000, True),
    3: (None, False),
    4: (None, True),
    5: (500_000, False),
    6: (120_000, False),
    7: (1_050_000, False),
}


def design(body: dict) -> dict:
    """Rewrites a song leaderboard page's designed ranks in place.

    Args:
        body: The mock's ``LeaderboardResponse`` JSON object.

    Returns:
        The same object, with ranks in :data:`DESIGNED` replaced.
    """
    for entry in body.get("entries", []):
        designed = DESIGNED.get(entry.get("rank"))
        if designed is None:
            continue
        accuracy, full_combo = designed
        entry.pop("accuracy", None)
        if accuracy is not None:
            entry["accuracy"] = accuracy
        entry["isFullCombo"] = full_combo
    return body


def install() -> None:
    """Patches the mock handler so Lead song leaderboards carry the designed rows."""
    handler = mock_service.FixtureHandler
    original_json = handler._json

    def _json(self, status: int, payload: dict | None, **kwargs) -> None:
        if status == 200 and isinstance(payload, dict) and CHART.fullmatch(urlsplit(self.path).path):
            payload = design(payload)
        original_json(self, status, payload, **kwargs)

    handler._json = _json
    # Song Detail reads every chart plus artwork at once; socketserver's default backlog of 5 can overflow.
    mock_service.FixtureServer.request_queue_size = 128


def main() -> None:
    """Installs the designed rows, then hands the command line to the mock service."""
    install()
    mock_service.main()


if __name__ == "__main__":
    main()
