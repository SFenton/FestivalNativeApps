#!/usr/bin/env python3
"""Live, read-only check for operator batch 6.12: Filter Invalid Scores removes many Winterfest Wish (Lead) scores.

Reads the public catalogue, then page one of ``GET /api/leaderboard/{song}/Solo_Guitar`` without and with
``leeway=1`` (what the Windows app sends when Filter Invalid Scores is on at the default +1.0%). Only keyless public
GETs on the allowlist in ``.agents/platforms/service-safety.md``; no selected-profile headers, no writes. Asserts:

1. every unfiltered top-25 score is above the CHOpt maximum × 1.01 (they are the invalid scores);
2. the filtered board keeps no score above that threshold and has far fewer local entries.

Not part of the offline ``unittest`` discovery (file name does not start with ``test``); the unit tests use the
fixture in ``windows/Festival.Core.Tests/FilterInvalidScoresTests.cs``. Run from anywhere::

    python tools/windows/tests/live_filter_invalid_scores.py [--base https://festivalscoretracker.com]
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request

SONG_TITLE = "Winterfest Wish"
INSTRUMENT = "Solo_Guitar"
LEEWAY = 1.0


def get(base: str, path: str) -> dict:
    """Keyless public GET returning decoded JSON."""
    request = urllib.request.Request(base.rstrip("/") + path, headers={"User-Agent": "FestivalNative-live-check"})
    with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310 - fixed https origin
        return json.loads(response.read().decode("utf-8"))


def main() -> int:
    """Runs the check; exit 1 on failure."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", default="https://festivalscoretracker.com")
    args = parser.parse_args()

    song = next(s for s in get(args.base, "/api/songs")["songs"] if s.get("title") == SONG_TITLE)
    maximum = song["maxScores"][INSTRUMENT]
    threshold = maximum * (1 + LEEWAY / 100)
    path = f"/api/leaderboard/{song['songId']}/{INSTRUMENT}?top=25&offset=0"
    unfiltered = get(args.base, path)
    filtered = get(args.base, f"{path}&leeway={LEEWAY:g}")

    raw_local = unfiltered.get("localEntries") or unfiltered["totalEntries"]
    kept_local = filtered.get("localEntries") or filtered["totalEntries"]
    over = [e["score"] for e in unfiltered["entries"] if e["score"] > threshold]
    leaked = [e["score"] for e in filtered["entries"] if e["score"] > threshold]
    print(f"{SONG_TITLE} ({INSTRUMENT}): max {maximum:,}, threshold {threshold:,.0f}")
    print(f"unfiltered: {raw_local:,} local entries, {len(over)}/{len(unfiltered['entries'])} of page one over threshold")
    print(f"filtered (leeway={LEEWAY:g}): {kept_local:,} local entries, {len(leaked)} over threshold")

    ok = len(over) == len(unfiltered["entries"]) > 0 and not leaked and kept_local * 10 < raw_local
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
