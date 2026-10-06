#!/usr/bin/env python3
"""Local, read-only Festival API fixture server for native device automation."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import struct
import threading
import time
import zlib
from functools import lru_cache
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

ROOT = Path(__file__).resolve().parents[1]
# Delay for the "slowpoke" account search, long enough for a UI test to see the
# global-search spinner.
SLOW_ACCOUNT_SEARCH_SECONDS = 4


def load_fixture(name: str) -> tuple[dict, str]:
    """Decode exactly the fixture bytes whose startup hash is advertised.

    Args:
        name: Allowlisted JSON fixture basename without its extension.

    Returns:
        Parsed object and SHA-256 of the same bytes loaded into this process.

    Raises:
        ValueError: If a fixture is not a JSON object.
    """
    data = (ROOT / "contracts/fixtures" / f"{name}.json").read_bytes()
    value = json.loads(data)
    if not isinstance(value, dict):
        raise ValueError(f"Invalid {name} fixture object")
    return value, hashlib.sha256(data).hexdigest()


PUBLICATION, PUBLICATION_HASH = load_fixture("publication")
EMPTY_SONGS, EMPTY_SONGS_HASH = load_fixture("songs-empty")
DEMO_SONGS, DEMO_SONGS_HASH = load_fixture("songs-demo")
PATH_DEMO, PATH_DEMO_HASH = load_fixture("path-demo")
SHOP_DEMO, SHOP_DEMO_HASH = load_fixture("shop-demo")
PLAYER_DEMO, PLAYER_DEMO_HASH = load_fixture("player-demo")
PLAYER_RANK_HISTORY_DEMO, PLAYER_RANK_HISTORY_DEMO_HASH = load_fixture("player-rank-history-demo")
METADATA_EDGE, METADATA_EDGE_HASH = load_fixture("metadata-edge")
RIVALS_LIST_DEMO, RIVALS_LIST_DEMO_HASH = load_fixture("rivals-list-demo")
LEADERBOARD_RIVALS_DEMO, LEADERBOARD_RIVALS_DEMO_HASH = load_fixture("leaderboard-rivals-demo")
RIVAL_DETAIL_DEMO, RIVAL_DETAIL_DEMO_HASH = load_fixture("rival-detail-demo")
LEADERBOARD_RIVAL_DETAIL_DEMO, LEADERBOARD_RIVAL_DETAIL_DEMO_HASH = load_fixture(
    "leaderboard-rival-detail-demo"
)
ROLLOVER_PLAYER_2_LEAD_SCORE = 99_850
EDGE_SONG_ID = "fixture-marathon"
_edge_song = METADATA_EDGE["songs"]["songs"][0]
_edge_profile = METADATA_EDGE["player"]
_edge_score = _edge_profile["scores"][0]
_edge_entry = METADATA_EDGE["leaderboard"]["entries"][0]
if (
    METADATA_EDGE["songs"]["count"] != 1
    or METADATA_EDGE["shop"]["count"] != 1
    or _edge_song["songId"] != EDGE_SONG_ID
    or METADATA_EDGE["shop"]["songs"][0]["songId"] != EDGE_SONG_ID
    or METADATA_EDGE["shop"]["newSongs"] != [EDGE_SONG_ID]
    or _edge_profile["totalScores"] != 1
    or _edge_score["si"] != EDGE_SONG_ID
    or _edge_score["ins"] != "01"
    or METADATA_EDGE["leaderboard"]["songId"] != EDGE_SONG_ID
    or METADATA_EDGE["leaderboard"]["instrument"] != "Solo_Guitar"
    or METADATA_EDGE["leaderboard"]["totalEntries"] != _edge_score["te"]
    or _edge_profile["accountId"] != _edge_entry["accountId"]
    or _edge_profile["displayName"] != _edge_entry["displayName"]
    or any(
        _edge_score[key] != _edge_entry[field]
        for key, field in (
            ("sc", "score"), ("rk", "rank"), ("fc", "isFullCombo"),
            ("st", "stars"), ("sn", "season")
        )
    )
    or _edge_score["acc"] * 1_000 != _edge_entry["accuracy"]
):
    raise ValueError("Metadata edge profile, Shop and leaderboard fixtures disagree")
DRUMS_SCORE = next(
    (
        row for row in PLAYER_DEMO["profiles"]["fixture-player-2"]["scores"]
        if row["si"] == "fixture-pulse" and row["ins"] == "04"
    ),
    None,
)
if DRUMS_SCORE is None:
    raise ValueError("Selected-player Drums score fixture is missing")
SOURCE_HASHES = {
    "tools/mock_service.py": hashlib.sha256(Path(__file__).resolve().read_bytes()).hexdigest(),
    "contracts/fixtures/publication.json": PUBLICATION_HASH,
    "contracts/fixtures/songs-empty.json": EMPTY_SONGS_HASH,
    "contracts/fixtures/songs-demo.json": DEMO_SONGS_HASH,
    "contracts/fixtures/path-demo.json": PATH_DEMO_HASH,
    "contracts/fixtures/shop-demo.json": SHOP_DEMO_HASH,
    "contracts/fixtures/player-demo.json": PLAYER_DEMO_HASH,
    "contracts/fixtures/player-rank-history-demo.json": PLAYER_RANK_HISTORY_DEMO_HASH,
    "contracts/fixtures/metadata-edge.json": METADATA_EDGE_HASH,
    "contracts/fixtures/rivals-list-demo.json": RIVALS_LIST_DEMO_HASH,
    "contracts/fixtures/leaderboard-rivals-demo.json": LEADERBOARD_RIVALS_DEMO_HASH,
    "contracts/fixtures/rival-detail-demo.json": RIVAL_DETAIL_DEMO_HASH,
    "contracts/fixtures/leaderboard-rival-detail-demo.json": LEADERBOARD_RIVAL_DETAIL_DEMO_HASH,
}
SONGS_ETAG = '"fst-fixture-songs-v1"'
EMPTY_ETAG = '"fst-fixture-empty-v1"'
SHOP_ETAG = '"fst-fixture-shop-v1"'
LEADERBOARD = re.compile(r"^/api/leaderboard/(fixture-[a-z0-9-]+)/([A-Za-z_]+)$")
SONG_BAND_LEADERBOARD = re.compile(r"^/api/leaderboard/(fixture-[a-z0-9-]+)/bands/([A-Za-z_]+)$")
SONG_BAND_LEADERBOARDS_ALL = re.compile(r"^/api/leaderboard/(fixture-[a-z0-9-]+)/bands/all$")
PLAYER = re.compile(r"^/api/player/(fixture-[a-z0-9-]+)$")
PLAYER_HISTORY = re.compile(r"^/api/player/(fixture-[a-z0-9-]+)/history$")
PLAYER_NOTIFICATIONS = re.compile(r"^/api/player/(fixture-[a-z0-9-]+)/notifications$")
PLAYER_BANDS = re.compile(r"^/api/player/(fixture-[a-z0-9-]+)/bands$")
RANKINGS = re.compile(r"^/api/rankings/([A-Za-z_]+)$")
PLAYER_RANK_HISTORY = re.compile(r"^/api/rankings/([A-Za-z_]+)/(fixture-[a-z0-9-]+)/history$")
PLAYER_INSTRUMENT_RANKING = re.compile(r"^/api/rankings/([A-Za-z_]+)/(fixture-[a-z0-9-]+)$")
BAND_RANKINGS = re.compile(r"^/api/rankings/bands/([A-Za-z_]+)$")
BAND_HISTORY = re.compile(r"^/api/rankings/bands/([A-Za-z_]+)/(fixture-[a-z0-9-]+)/history$")
BAND_SONGS = re.compile(r"^/api/rankings/bands/([A-Za-z_]+)/(fixture-[a-z0-9-]+)/songs$")
PATH_ARTIFACT = re.compile(
    r"^/api/paths/(fixture-[a-z0-9-]+)/([A-Za-z_]+)/([a-z]+)(/data)?$"
)
INSTRUMENTS = frozenset({
    "Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals",
    "Solo_PeripheralGuitar", "Solo_PeripheralBass", "Solo_PeripheralVocals",
    "Solo_PeripheralCymbals", "Solo_PeripheralDrums",
})
BAND_TYPES = frozenset({"Band_Duets", "Band_Trios", "Band_Quad"})
# `--large-rankings`: enough synthetic rows for multi-page pagers (48 pages of 25).
LARGE_RANKINGS_ACCOUNTS = 1_200
LARGE_RANKINGS_TEAMS = 600
# `--large-catalogue`: synthetic songs spread over #, A–Z so lists scroll and the section
# index has every bucket; artwork reuses the generated fixture motifs.
_CATALOGUE_WORDS = (
    "Anthem", "Ballad", "Cascade", "Drift", "Echo", "Flare", "Glow", "Horizon", "Ignite",
    "Jubilee", "Kinetic", "Lumen", "Mirage", "Nova", "Orbit", "Prism", "Quartz", "Rhythm",
    "Signal", "Tempo", "Uplift", "Vortex", "Wave", "Xenon", "Yonder", "Zenith",
)


def _large_catalogue_songs() -> list[dict]:
    """Synthetic catalogue rows for `--large-catalogue` (original names and generated art).

    Returns:
        Four songs per letter A–Z plus four digit-leading titles, each with a stable
        `fixture-song-{n}` id, a varied year/difficulty spread and generated artwork.
    """
    titles = [f"{n} {word}" for n, word in zip((1, 7, 24, 99), ("Beat", "Nights", "Hours", "Lights"))]
    for word in _CATALOGUE_WORDS:
        titles += [f"{word} {suffix}" for suffix in ("Theory", "Run", "Signal", "Garden")]
    return [
        {
            "songId": f"fixture-song-{index}", "title": title,
            "artist": f"Synthetic Artist {index % 17 + 1}", "year": 2000 + index % 27,
            "pathArtifactGenerationId": "fixture-path-generation",
            "albumArt": f"/__fixture__/art/{'pulse' if index % 2 else 'orbit'}.png",
            "difficulty": {
                "guitar": index % 7, "bass": (index + 2) % 7,
                "drums": (index + 4) % 7, "vocals": (index + 1) % 7,
            },
        }
        for index, title in enumerate(titles, start=1)
    ]


LARGE_CATALOGUE_SONGS = _large_catalogue_songs()

# `--long-titles`: `fixture-pulse` (scrollable Song Detail, Lead and Duos boards) with a
# title wider than any navigation bar, so pinned-title width journeys can measure it.
LONG_TITLE = (
    "Fixture Pulse: An Extraordinarily Long Synthetic Encore Title "
    "That Keeps Going Well Past Any Navigation Bar"
)


def _ranking_entry(rank: int, account_id: str, display_name: str) -> dict:
    """One deterministic `/api/rankings/{instrument}` row for the UX-test fixtures.

    Args:
        rank: 1-based rank; also seeds every metric's numeric spread.
        account_id: Fixture player id (reuse a `player-demo` id to let a rankings
            row navigate to a real profile).
        display_name: Row's display name.

    Returns:
        A JSON-ready `AccountRankingEntry` object.
    """
    return {
        "accountId": account_id, "displayName": display_name,
        "songsPlayed": 40 - rank, "totalChartedSongs": 50,
        "coverage": 0.8, "rawSkillRating": max(0.001, 0.05 - rank * 0.01),
        "adjustedSkillRating": max(0.001, 0.05 - rank * 0.01), "adjustedSkillRank": rank,
        "weightedRating": max(0.001, 0.06 - rank * 0.01), "weightedRank": rank,
        "fcRate": max(0.1, 0.6 - rank * 0.1), "fcRateRank": rank,
        "totalScore": max(1_000, 90_000_000 - rank * 1_000_000 if rank <= 80 else 10_000_000 - rank * 5_000), "totalScoreRank": rank,
        "maxScorePercent": max(0.5, 0.99 - rank * 0.02), "maxScorePercentRank": rank,
        "avgAccuracy": max(500_000, 990_000 - rank * 1_000), "fullComboCount": max(0, 20 - rank),
        "avgStars": 4.9, "bestRank": 1, "avgRank": float(rank),
    }


def _band_ranking_entry(rank: int) -> dict:
    """One deterministic `/api/rankings/bands/{bandType}` row for the UX-test fixtures.

    Args:
        rank: 1-based rank; also seeds every metric's numeric spread.

    Returns:
        A JSON-ready `BandRankingEntry` object.
    """
    return {
        "bandId": f"fixture-band-{rank}", "teamKey": f"fixture-team-{rank}",
        "teamMembers": [
            {"accountId": f"fixture-band-{rank}-a", "displayName": f"Band {rank} Member A"},
            {"accountId": f"fixture-band-{rank}-b", "displayName": f"Band {rank} Member B"},
        ],
        "songsPlayed": 30 - rank, "totalChartedSongs": 50, "coverage": 0.6,
        "rawSkillRating": max(0.001, 0.04 - rank * 0.01),
        "adjustedSkillRating": max(0.001, 0.04 - rank * 0.01),
        "adjustedSkillRank": rank, "weightedRating": max(0.001, 0.05 - rank * 0.01),
        "weightedRank": rank,
        "fcRate": max(0.1, 0.4 - rank * 0.1), "fcRateRank": rank,
        "totalScore": max(1_000, 50_000_000 - rank * 500_000 if rank <= 90 else 5_000_000 - rank * 5_000), "totalScoreRank": rank,
        "avgAccuracy": max(500_000, 970_000 - rank * 1_000), "fullComboCount": max(0, 10 - rank),
        "avgStars": 4.5, "bestRank": 1, "avgRank": float(rank),
    }


def _band_detail(team_key: str, rank: int, band_type: str) -> dict:
    """One `selectedBandEntry` (`BandDetail`) for `GET /api/rankings/bands/{bandType}?teamKey=`.

    `fixture-team-1` (rank 1) carries one duets combo configuration; every other
    team has none, matching the live service's rarity of combo data.

    Args:
        team_key: Requested `teamKey`, echoed back.
        rank: 1-based rank; also seeds every metric's numeric spread.
        band_type: Requested band size, echoed back on the member instrument shape.

    Returns:
        A JSON-ready `BandDetail` object (richer member/config shape than a plain
        `BandRankingEntry` list row — the live service only attaches full instrument
        and combo detail to the single filtered `teamKey` match).
    """
    instruments_a = ["Solo_Guitar"]
    instruments_b = ["Solo_Bass"]
    return {
        "bandId": f"fixture-band-{rank}", "comboId": None, "teamKey": team_key,
        "members": [
            {
                "accountId": f"fixture-band-{rank}-a", "displayName": f"Band {rank} Member A",
                "instruments": instruments_a, "score": None, "accuracy": None,
                "isFullCombo": None, "stars": None, "difficulty": None, "season": None,
            },
            {
                "accountId": f"fixture-band-{rank}-b", "displayName": f"Band {rank} Member B",
                "instruments": instruments_b, "score": None, "accuracy": None,
                "isFullCombo": None, "stars": None, "difficulty": None, "season": None,
            },
        ],
        "configurations": [
            {
                "rawInstrumentCombo": "Solo_Guitar+Solo_Bass", "comboId": "guitar-bass",
                "instruments": ["Solo_Guitar", "Solo_Bass"],
                "assignmentKey": f"fixture-config-{rank}", "appearanceCount": 12,
                "memberInstruments": {
                    f"fixture-band-{rank}-a": "Solo_Guitar",
                    f"fixture-band-{rank}-b": "Solo_Bass",
                },
            },
        ] if rank == 1 else [],
        "songsPlayed": 30 - rank, "totalChartedSongs": 50, "coverage": 0.6,
        "rawSkillRating": 0.04 - rank * 0.01, "adjustedSkillRating": 0.04 - rank * 0.01,
        "adjustedSkillRank": rank, "weightedRating": 0.05 - rank * 0.01, "weightedRank": rank,
        "fcRate": max(0.1, 0.4 - rank * 0.1), "fcRateRank": rank,
        "totalScore": 50_000_000 - rank * 500_000, "totalScoreRank": rank,
        "avgAccuracy": 970_000 - rank * 1_000, "fullComboCount": max(0, 10 - rank),
        "avgStars": 4.5, "bestRank": 1, "avgRank": float(rank),
        "rawWeightedRating": 0.05 - rank * 0.01, "computedAt": "2024-01-05T00:00:00Z",
    }


def _player_band_entry(band_id: str, team_key: str, band_type: str, members: int) -> dict:
    """One `PlayerBandEntry` row for `GET /api/player/{accountId}/bands`.

    Args:
        band_id: Deterministic synthetic band identifier.
        team_key: Deterministic synthetic team roster key.
        band_type: Band size key (`Band_Duets`/`Band_Trios`/`Band_Quad`).
        members: Member count (2, 3 or 4) to match `band_type`.

    Returns:
        A JSON-ready `PlayerBandEntry` object.
    """
    instrument_cycle = ["Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals"]
    return {
        "bandId": band_id, "teamKey": team_key, "bandType": band_type,
        "appearanceCount": 12, "members": [
            {
                "accountId": f"{team_key}-{index}", "displayName": f"{team_key} Member {index}",
                "instruments": [instrument_cycle[index % len(instrument_cycle)]],
                "score": None, "accuracy": None, "isFullCombo": None,
                "stars": None, "difficulty": None, "season": None,
            }
            for index in range(members)
        ],
    }


def _song_band_leaderboard_entry(rank: int, band_type: str) -> dict:
    """One `SongBandLeaderboardEntry` row for `GET /api/leaderboard/{songId}/bands/{bandType}`.

    Args:
        rank: 1-based rank; also selects the reused `fixture-team-{rank}` roster.
        band_type: Requested band size, echoed back.

    Returns:
        A JSON-ready `SongBandLeaderboardEntry` object.
    """
    return {
        "bandId": f"fixture-band-{rank}", "bandType": band_type,
        "teamKey": f"fixture-team-{rank}", "comboId": None,
        "members": [
            {
                "accountId": f"fixture-band-{rank}-a", "displayName": f"Band {rank} Member A",
                "instruments": ["Solo_Guitar"], "score": 95_000 - rank * 500,
                "accuracy": 970_000, "isFullCombo": rank == 1, "stars": 5,
                "difficulty": 4, "season": 10,
            },
            {
                "accountId": f"fixture-band-{rank}-b", "displayName": f"Band {rank} Member B",
                "instruments": ["Solo_Bass"], "score": 94_500 - rank * 500,
                "accuracy": 960_000, "isFullCombo": rank == 1, "stars": 5,
                "difficulty": 4, "season": 10,
            },
        ],
        "score": 95_000 - rank * 500, "rank": rank, "accuracy": 965_000,
        "isFullCombo": rank == 1, "stars": 5, "season": 10, "difficulty": 4,
        "percentile": 0.1 * rank, "endTime": None,
    }


# The selected fixture player's Duos band on `fixture-pulse`: rank 29, so it is
# appended after Song Detail's preview and sits on page 2 of the 25-row full board,
# exercising the footer's jump and open states (issues #306, #307).
SELECTED_SONG_BAND_RANK = 29


def _selected_song_band_entry(account_id: str | None, band_type: str) -> dict | None:
    """The `selectedPlayerEntry` band of a `fixture-player-*` account.

    Args:
        account_id: Optional selected player from the `accountId` query (its band's
            first member).
        band_type: Requested band size, echoed back.

    Returns:
        A rank-29 `SongBandLeaderboardEntry` with that player's band identity, or None
        for a missing or non-fixture player.
    """
    if not account_id or not account_id.startswith("fixture-player-"):
        return None
    selected = _song_band_leaderboard_entry(SELECTED_SONG_BAND_RANK, band_type)
    selected["members"][0]["accountId"] = account_id
    selected["members"][0]["displayName"] = RIVAL_DISPLAY_NAMES.get(account_id, account_id)
    selected["bandId"] = f"fixture-band-{account_id}"
    selected["teamKey"] = f"fixture-team-{account_id}"
    return selected


def _song_band_leaderboards_all(song_id: str, top: int, account_id: str | None) -> dict:
    """Song Detail's band previews for `GET /api/leaderboard/{songId}/bands/all`.

    `fixture-pulse` has two Duos rows; every other size and song is empty. A
    `fixture-player-*` `accountId` adds that player's rank-29 Duos band as the
    `selectedPlayerEntry`, exercising the appended highlighted row.

    Args:
        song_id: Requested fixture song.
        top: Rows per band size (1-50).
        account_id: Optional selected player from the `accountId` query.

    Returns:
        A JSON-ready `{songId, showLeaderboardEntryTotals, bands}` object.
    """
    bands = []
    for band_type in ("Band_Duets", "Band_Trios", "Band_Quad"):
        rows = ([_song_band_leaderboard_entry(rank, band_type) for rank in (1, 2)]
                if song_id == "fixture-pulse" and band_type == "Band_Duets" else [])
        selected = _selected_song_band_entry(account_id, band_type) if rows else None
        entries = rows[:top]
        bands.append({
            "bandType": band_type, "count": len(entries),
            "totalEntries": SELECTED_SONG_BAND_RANK if selected else len(rows),
            "localEntries": SELECTED_SONG_BAND_RANK if selected else len(rows),
            "entries": entries, "selectedPlayerEntry": selected, "selectedBandEntry": None,
        })
    return {"songId": song_id, "showLeaderboardEntryTotals": False, "bands": bands}


# Rivals/Compete: `RivalsEndpoints.cs`/`LeaderboardRivalsEndpoints.cs` reads
# (see `.agents/pages/rivals/ios.md`). The selected player's own accountId
# selects a scenario (`-empty`/`-503` suffix); the rival id is echoed back
# verbatim so Find Rival / deep-link journeys see a consistent identity.
RIVALS_LIST = re.compile(r"^/api/player/(fixture-[a-z0-9-]+)/rivals/([A-Za-z0-9_]+)$")
RIVALS_DETAIL = re.compile(
    r"^/api/player/(fixture-[a-z0-9-]+)/rivals/([A-Za-z0-9_]+)/([A-Za-z0-9]+)$"
)
LEADERBOARD_RIVALS_LIST = re.compile(
    r"^/api/player/(fixture-[a-z0-9-]+)/leaderboard-rivals/([A-Za-z_]+)$"
)
LEADERBOARD_RIVALS_DETAIL = re.compile(
    r"^/api/player/(fixture-[a-z0-9-]+)/leaderboard-rivals/([A-Za-z_]+)/([A-Za-z0-9]+)$"
)
RIVAL_DISPLAY_NAMES = {
    "fixture-player-1": "Fixture Player 1",
    "fixture-player-2": "Fixture Player 2",
    "fixture-cpp": "C++",
}



def _multi_instrument_history(account_id: str) -> dict:
    """Build `fixture-pulse` history on three instruments for `fixture-history-multi`.

    Lead has eight rows (more than one chart page on a phone), Bass two and Drums
    three ending in a 100% full combo, so switching instruments changes whether the
    pager and the gold legend are needed. Accuracy uses the wire's ten-thousandths of
    a percent scale.

    Args:
        account_id: The requested fixture account.

    Returns:
        A `GET /api/player/{accountId}/history` body.
    """
    plan = {
        "Solo_Guitar": [(610000, 921000), (655000, 934000), (700000, 948000), (742000, 955500),
                        (768000, 962000), (801000, 971000), (826000, 979500), (850000, 991200)],
        "Solo_Bass": [(540000, 902000), (612000, 937500)],
        "Solo_Drums": [(580000, 915000), (690000, 958000), (781000, 1000000)],
    }
    rows = []
    for instrument, scores in plan.items():
        previous = None
        for day, (score, accuracy) in enumerate(scores, start=1):
            stamp = f"2024-02-{day:02d}T00:00:00Z"
            rows.append({
                "songId": "fixture-pulse", "instrument": instrument,
                "oldScore": previous, "newScore": score,
                "oldRank": None, "newRank": 20 - day, "accuracy": accuracy,
                "isFullCombo": accuracy == 1000000, "stars": 5 if accuracy >= 950000 else 4,
                "season": 40, "scoreAchievedAt": stamp, "changedAt": stamp,
            })
            previous = score
    rows.reverse()
    return {"accountId": account_id, "count": len(rows), "history": rows}

def _rivals_scenario(account_id: str) -> str:
    """Select a Rivals/Compete fixture scenario from the viewing player's own id.

    Args:
        account_id: Path segment naming the selected (viewing) player.

    Returns:
        `"empty"` (no rivals/shared songs yet), `"unavailable"` (503, matching
        the live service's scrape-window freeze) or `"demo"` (populated).
    """
    if account_id.endswith("-empty"):
        return "empty"
    if account_id.endswith("-503"):
        return "unavailable"
    return "demo"


def _rivals_list_body(token: str, scenario: str) -> dict:
    """Build a `GET /api/player/{id}/rivals/{token}` (or combo) body."""
    if scenario == "empty":
        return {"combo": token, "above": [], "below": []}
    return {**RIVALS_LIST_DEMO, "combo": token}


def _leaderboard_rivals_body(instrument: str, rank_by: str, scenario: str) -> dict:
    """Build a `GET /api/player/{id}/leaderboard-rivals/{instrument}` body."""
    if scenario == "empty":
        return {
            "instrument": instrument, "rankBy": rank_by, "userRank": None,
            "above": [], "below": [],
        }
    return {**LEADERBOARD_RIVALS_DEMO, "instrument": instrument, "rankBy": rank_by}


def _rival_detail_body(token: str, rival_id: str, scenario: str) -> dict:
    """Build a `GET /api/player/{id}/rivals/{token}/{rivalId}` (or combo) body."""
    display_name = RIVAL_DISPLAY_NAMES.get(rival_id)
    if scenario == "empty":
        return {
            "rival": {"accountId": rival_id, "displayName": display_name},
            "combo": token, "source": None, "totalSongs": 0,
            "offset": 0, "limit": 50, "sort": "closest",
            "songs": [], "songsToCompete": [], "yourExclusiveSongs": [],
        }
    return {
        **RIVAL_DETAIL_DEMO,
        "rival": {
            "accountId": rival_id,
            "displayName": display_name or RIVAL_DETAIL_DEMO["rival"]["displayName"],
        },
        "combo": token,
    }


def _leaderboard_rival_detail_body(
    instrument: str, rank_by: str, rival_id: str, scenario: str
) -> dict:
    """Build a `GET /api/player/{id}/leaderboard-rivals/{instrument}/{rivalId}` body."""
    display_name = RIVAL_DISPLAY_NAMES.get(rival_id)
    if scenario == "empty":
        return {
            "rival": {"accountId": rival_id, "displayName": display_name},
            "instrument": instrument, "rankBy": rank_by, "totalSongs": 0,
            "sort": "closest", "songs": [], "songsToCompete": [], "yourExclusiveSongs": [],
        }
    return {
        **LEADERBOARD_RIVAL_DETAIL_DEMO,
        "rival": {
            "accountId": rival_id,
            "displayName": display_name or LEADERBOARD_RIVAL_DETAIL_DEMO["rival"]["displayName"],
        },
        "instrument": instrument, "rankBy": rank_by,
    }


#: Synthetic ``GET /api/service-info`` (contract 2 subset, idle worker, not frozen) for the
#: Settings Service Info card; shape follows ``FSTService/Api/HealthEndpoints.cs``.
# Fixture feedback job IDs (32 lowercase hex, as the service issues them).
FEEDBACK_FILED_JOB = "0" * 31 + "1"
FEEDBACK_FAILED_JOB = "f" * 32

SERVICE_INFO_IDLE = {
    "contractVersion": 2,
    "lastCompletedUpdate": {
        "scrapeId": 1, "startedAt": "2026-01-01T11:30:00Z", "completedAt": "2026-01-01T11:55:00Z",
        "publishedAt": "2026-01-01T12:00:00.0000000Z",
    },
    "currentUpdate": {"status": "idle", "startedAt": None, "phase": None, "subOperation": None},
    "activeScrapeId": None,
    "publishedScrapeId": 1,
    "publication": {
        "publishedScrapeId": 1, "publishedAt": "2026-01-01T12:00:00.0000000Z",
        "publicReadsFrozen": False, "frozenAt": None, "frozenScrapeId": None, "freezeReason": None,
    },
    "workerStatus": {"workerKey": "fixture-worker", "status": "online", "rawStatus": "idle"},
    "nextScheduledUpdateAt": None,
}

#: Opt-in ``--service-info-discovery`` body: an update in the registered-band discovery
#: phase with per-pass lookup counts (``attemptProgress``), for Settings captures.
SERVICE_INFO_DISCOVERY = {
    **SERVICE_INFO_IDLE,
    "currentUpdate": {
        "status": "updating", "scrapeId": 2, "operationId": "fixture-op-2",
        "startedAt": "2026-01-02T12:00:00Z", "phase": "PostScrape", "subOperation": None,
        "phaseId": "post.registered_player_band_discovery", "subphaseId": None,
        "phasePlanVersion": "fixture", "phaseOrdinal": 5, "phaseAttempt": 1,
        "unitsKind": "accounts", "unitsCompleted": 1240, "unitsTotal": 5000,
        "unitsTotalFinal": True, "phasePercent": 24.8,
        "attemptProgress": {
            "schemaVersion": 1, "attemptedThisPass": 1310, "retryableUnavailableThisPass": 70,
        },
        "lastProgressAt": "2026-01-02T12:10:00Z",
    },
    "activeScrapeId": 2,
    "workerStatus": {"workerKey": "fixture-worker", "status": "online", "rawStatus": "updating"},
}


class FixtureServer(ThreadingHTTPServer):
    """Isolate mock publication and query evidence within one loopback listener."""

    # socketserver's default listen backlog is 5; pages that fan out many parallel
    # reads (Leaderboards/Rivals cards) overflowed it on Windows and saw resets.
    request_queue_size = 128
    daemon_threads = True

    def __init__(
        self, address: tuple[str, int], handler: type[BaseHTTPRequestHandler],
        *, unpinned: bool = False, rollover_on_read: int | None = None,
        rollover_on_command: bool = False,
        mismatched_shop_rollover: bool = False,
        fail_first_white_catalogue: bool = False,
        stop_after_first_songs: bool = False,
        stop_after_first_score: bool = False,
        stop_after_first_shop: bool = False,
        metadata_edge: bool = False,
        large_rankings: bool = False,
        large_catalogue: bool = False,
        long_titles: bool = False,
        service_info_discovery: bool = False,
    ) -> None:
        """Create a deterministic, bounded service fixture.

        Args:
            address: Loopback host and port.
            handler: Allowlisted HTTP request handler.
            unpinned: Omit response publication headers like an unfrozen service.
            rollover_on_read: First publication GET that advances generation 7 to 8.
            rollover_on_command: Advance once only after an explicit test-only GET.
            mismatched_shop_rollover: Pinned new Shop/profile with a failed new Songs read.
            fail_first_white_catalogue: Fail one white-art catalogue read, then recover.
            stop_after_first_songs: Stop this mock listener after its first successful Songs read.
            stop_after_first_score: Stop after the first successful full 25-row chart read.
            stop_after_first_shop: Stop after one Shop feed and explicit visual acknowledgement.
            metadata_edge: Publish one isolated long-title, score and Shop contract.
            large_rankings: Pad account/band rankings with synthetic `fixture-rank-{n}` /
                `fixture-team-{n}` rows so pagers have many pages; ranks 1–3 are unchanged.
            large_catalogue: Append 108 synthetic `fixture-song-{n}` songs (#, A–Z) to the
                demo catalogue; their Lead charts serve the generic fixture leaderboard.
            long_titles: Retitle `fixture-pulse` with ``LONG_TITLE`` (wider than any bar).
            service_info_discovery: Serve ``SERVICE_INFO_DISCOVERY`` (an update in the
                registered-band discovery phase) instead of the idle Service Info body.
        """
        if metadata_edge and (
            unpinned or rollover_on_read is not None or rollover_on_command
            or mismatched_shop_rollover
            or fail_first_white_catalogue
            or stop_after_first_songs or stop_after_first_score or stop_after_first_shop
        ):
            raise ValueError("Metadata edge fixture must remain publication-pinned and persistent")
        if mismatched_shop_rollover and not rollover_on_command:
            raise ValueError("Mismatched Shop rollover needs an explicit command")
        if rollover_on_command and (
            unpinned == mismatched_shop_rollover
            or rollover_on_read is not None or fail_first_white_catalogue
            or stop_after_first_songs or stop_after_first_score or stop_after_first_shop
        ):
            raise ValueError("Command rollover needs its own persistent fixture mode")
        self.unpinned = unpinned
        self.metadata_edge = metadata_edge
        self.large_rankings = large_rankings
        self.large_catalogue = large_catalogue
        self.long_titles = long_titles
        self.service_info_discovery = service_info_discovery
        self.rollover_on_read = rollover_on_read
        self.rollover_on_command = rollover_on_command
        self.mismatched_shop_rollover = mismatched_shop_rollover
        self.source_hashes = SOURCE_HASHES.copy()
        self.options = {
            "unpinned": unpinned,
            "rolloverOnRead": rollover_on_read,
            "rolloverOnCommand": rollover_on_command,
            "mismatchedShopRollover": mismatched_shop_rollover,
            "failFirstWhiteCatalogue": fail_first_white_catalogue,
            "stopAfterFirstSongs": stop_after_first_songs,
            "stopAfterFirstScore": stop_after_first_score,
            "stopAfterFirstShop": stop_after_first_shop,
            "metadataEdge": metadata_edge,
            "largeRankings": large_rankings,
            "largeCatalogue": large_catalogue,
            "longTitles": long_titles,
            "serviceInfoDiscovery": service_info_discovery,
        }
        self._publication_reads = 0
        self._publication_id = 7
        self._last_score_query: dict | None = None
        self._last_full_score_query: dict | None = None
        self._fail_first_white_catalogue = fail_first_white_catalogue
        self._stop_after_first_songs = stop_after_first_songs
        self._stop_after_first_score = stop_after_first_score
        self._stop_after_first_shop = stop_after_first_shop
        self._shop_read_succeeded = False
        self._publication_join_reads: dict[str, int | None] = {
            "shop": None, "player": None, "failedSongs": None,
        }
        self._lock = threading.Lock()
        super().__init__(address, handler)

    @property
    def publication_id(self) -> int:
        """Return the fixture generation without advancing the read counter."""
        with self._lock:
            return self._publication_id

    def publication(self) -> dict:
        """Advance on the configured publication GET and return its wire object."""
        with self._lock:
            self._publication_reads += 1
            if self.rollover_on_read and self._publication_reads >= self.rollover_on_read:
                self._publication_id = 8
            identifier = self._publication_id
        return {
            **PUBLICATION,
            "publicationId": identifier,
            "publishedScrapeId": 42 if identifier == 7 else 43,
            "readyForPinning": not self.unpinned,
            "pinningEnabled": not self.unpinned,
        }

    def advance_publication(self) -> bool:
        """Move one dedicated local fixture from seven to eight exactly once.

        Returns:
            True only for a command-enabled, previously unadvanced listener.
        """
        with self._lock:
            if not self.rollover_on_command or self._publication_id != 7:
                return False
            self._publication_id = 8
            return True

    def record_score_query(self, top: int, offset: int, leeway: float | None) -> None:
        """Retain only validated synthetic query numbers, never account identifiers.

        Args:
            top: Bounded page size.
            offset: Nonnegative score-row offset.
            leeway: Optional score tolerance sent by the native Settings control.
        """
        with self._lock:
            self._last_score_query = {"top": top, "offset": offset, "leeway": leeway}
            if top == 25:
                self._last_full_score_query = self._last_score_query

    def last_score_query(self) -> dict | None:
        """Return the last validated mock score request, if any."""
        with self._lock:
            return self._last_score_query

    def last_full_score_query(self) -> dict | None:
        """Return only the most recent full chart query, ignoring ten-row previews."""
        with self._lock:
            return self._last_full_score_query

    def should_fail_white_catalogue(self) -> bool:
        """Consume one configured white-art 503 without advancing publication.

        Returns:
            True exactly once per listener when that synthetic failure is enabled.
        """
        with self._lock:
            should_fail = self._fail_first_white_catalogue
            self._fail_first_white_catalogue = False
            return should_fail

    def should_stop_after_songs(self) -> bool:
        """Consume the configured one-shot simulated connectivity loss.

        Returns:
            True only after the first successful catalogue read on this listener.
        """
        with self._lock:
            should_stop = self._stop_after_first_songs
            self._stop_after_first_songs = False
            return should_stop

    def should_stop_after_score(self, top: int) -> bool:
        """Consume one full page, not a ten-row Detail preview, before disconnecting.

        Args:
            top: Validated number of chart rows requested.

        Returns:
            True only after the first successful 25-row chart on this listener.
        """
        if top != 25:
            return False
        with self._lock:
            should_stop = self._stop_after_first_score
            self._stop_after_first_score = False
            return should_stop

    def record_shop_read(self) -> None:
        """Arm a visual-confirmed connection loss after one valid Shop feed."""
        with self._lock:
            self._shop_read_succeeded = True
            if self.mismatched_shop_rollover:
                self._publication_join_reads["shop"] = self._publication_id

    def record_publication_join_read(self, kind: str) -> None:
        """Record only allowlisted generation numbers in the dedicated fixture.

        Args:
            kind: Successful player read or failed new Songs read.

        Raises:
            ValueError: On an unrelated listener or unrecognized diagnostic.
        """
        if not self.mismatched_shop_rollover or kind not in ("player", "failedSongs"):
            raise ValueError("Invalid publication-join diagnostic")
        with self._lock:
            self._publication_join_reads[kind] = self._publication_id

    def publication_join_reads(self) -> dict[str, int | None]:
        """Return sanitized generation-only read evidence for the local XCTest.

        Returns:
            Latest Shop/player/failed-Songs generation, with no account or song IDs.
        """
        with self._lock:
            return self._publication_join_reads.copy()

    def acknowledge_visible_shop(self) -> bool:
        """Stop only after the test has seen the loaded offer and artwork.

        Returns:
            True once for the first validated Shop feed, never before it.
        """
        with self._lock:
            if self._stop_after_first_shop and self._shop_read_succeeded:
                self._stop_after_first_shop = False
                return True
            return False


def fixture_png(width: int, height: int, rows: list[bytes]) -> bytes:
    """Encode original synthetic RGBA pixels without writing a file.

    Args:
        width: PNG pixel width.
        height: PNG pixel height.
        rows: Filter-prefixed RGBA rows generated by an allowlisted fixture.

    Returns:
        One complete PNG with ImageIO-compatible dimensions and CRCs.
    """
    def chunk(kind: bytes, data: bytes) -> bytes:
        """Serialize a PNG chunk with its length and CRC.

        Args:
            kind: Four-byte chunk marker.
            data: The chunk's raw bytes.

        Returns:
            Serialized chunk length, marker, payload and checksum.
        """
        return struct.pack(">I", len(data)) + kind + data + struct.pack(
            ">I", zlib.crc32(kind + data) & 0xFFFFFFFF
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(
        b"IDAT", zlib.compress(b"".join(rows), 9)
    ) + chunk(b"IEND", b"")


@lru_cache(maxsize=3)
def fixture_artwork(name: str) -> bytes:
    """Generate original, deterministic PNG artwork without bundled album art.

    Args:
        name: One of the three synthetic fixture artwork identifiers.

    Returns:
        128-by-128 RGBA PNG bytes for a branded motif or a pure-white cover.

    Raises:
        ValueError: For names not in the fixture allowlist.
    """
    if name not in ("pulse", "orbit", "white"):
        raise ValueError(f"Unknown fixture artwork: {name}")
    rows = []
    for y in range(128):
        row = bytearray(b"\x00")
        for x in range(128):
            if name == "white":
                row.extend((255, 255, 255, 255))
            else:
                accent = ((x + y) // 16) % 2 if name == "pulse" else ((x - y) // 18) % 2
                row.extend((26 + 20 * accent, 8 + (x * 55 // 127), 48 + (y * 70 // 127), 255))
        rows.append(bytes(row))

    return fixture_png(128, 128, rows)


@lru_cache(maxsize=2)
def fixture_path_image(difficulty: str) -> bytes:
    """Paint a tall synthetic chart with original lines and activation bands.

    Args:
        difficulty: One of the fixture's two generated path levels.

    Returns:
        A 256-by-960 PNG without licensed album art or note-chart content.

    Raises:
        ValueError: For a path difficulty without a generated fixture.
    """
    if difficulty not in ("hard", "expert"):
        raise ValueError(f"Unknown fixture path difficulty: {difficulty}")
    rows: list[bytes] = []
    for y in range(960):
        row = bytearray(b"\x00")
        for x in range(256):
            active = 270 <= y <= 355 or 630 <= y <= 720
            accent = (x % 44 <= 2 and x < 226) or y % 96 <= 2
            if active and accent:
                pixel = (242, 181, 68, 255)
            elif accent:
                pixel = (69, 137, 231, 255)
            else:
                pixel = (22, 32 if difficulty == "expert" else 44, 56, 255)
            row.extend(pixel)
        rows.append(bytes(row))
    return fixture_png(256, 960, rows)


class FixtureHandler(BaseHTTPRequestHandler):
    """Serve a tiny allowlist, never proxy requests or perform side effects."""

    @property
    def fixture(self) -> FixtureServer:
        """Require the configured loopback server, not a fallback global fixture."""
        if not isinstance(self.server, FixtureServer):
            raise RuntimeError("FixtureHandler requires a FixtureServer")
        return self.server

    def end_headers(self) -> None:
        """Advertise ``Connection: close`` on every response.

        The stdlib server speaks HTTP/1.0 and closes each connection; without the
        explicit header .NET's HttpClient intermittently tries to reuse the socket
        and fails with WSAECONNABORTED (seen by the Windows lanes).
        """
        self.send_header("Connection", "close")
        self.close_connection = True
        super().end_headers()

    def _json(self, status: int, payload: dict | None, *, etag: str | None = None) -> None:
        """Write a bounded JSON response and explicit publication metadata.

        Args:
            status: HTTP response status.
            payload: JSON object to encode, or None for a bodyless 304.
            etag: Entity tag on the synthetic catalogue endpoint.

        Returns:
            None; bytes are written to the local response stream.
        """
        data = json.dumps(payload, separators=(",", ":")).encode() if payload is not None else b""
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        if not self.fixture.unpinned:
            self.send_header("X-FST-Publication-Id", str(self.fixture.publication_id))
        if etag:
            self.send_header("ETag", etag)
        self.end_headers()
        if data:
            self.wfile.write(data)

    def _art(self, name: str) -> None:
        """Serve artwork generated in memory without saving a cold-launch cache.

        Args:
            name: Valid fixture artwork identifier.

        Returns:
            None; the PNG response is written to the local socket.
        """
        data = fixture_artwork(name)
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _path_image(self, difficulty: str, etag: str) -> None:
        """Serve one generated path PNG with a publication-aware ETag.

        Args:
            difficulty: Valid generated fixture path difficulty.
            etag: Stable ETag for the selected image URL.
        """
        unchanged = self.headers.get("If-None-Match") == etag
        data = b"" if unchanged else fixture_path_image(difficulty)
        self.send_response(304 if unchanged else 200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        if not self.fixture.unpinned:
            self.send_header("X-FST-Publication-Id", str(self.fixture.publication_id))
        self.send_header("ETag", etag)
        self.end_headers()
        if data:
            self.wfile.write(data)

    # region Public-only endpoint fixtures
    def do_GET(self) -> None:
        """Serve public reads and explicitly allowlisted local-only test controls.

        Returns:
            None; every known outcome produces a complete HTTP response.
        """
        parsed = urlsplit(self.path)
        path = parsed.path
        query = parse_qs(parsed.query, keep_blank_values=True)
        if self.headers.get("X-API-Key") is not None or any(
            name.lower().startswith("x-fst-selected-") for name in self.headers
        ):
            self._json(400, {"status": "forbidden_client_header"})
            return
        if path == "/__fixture__/health":
            self._json(200, {
                "ready": True, "sourceHashes": self.fixture.source_hashes,
                "options": self.fixture.options,
            })
        elif path == "/__fixture__/advance-publication":
            if query:
                self._json(400, {"status": "invalid_fixture_query"})
            elif not self.fixture.rollover_on_command:
                self._json(404, {"status": "not_found"})
            elif self.fixture.advance_publication():
                self._json(200, {"publicationId": 8})
            else:
                self._json(409, {"status": "publication_already_advanced"})
        elif path == "/__fixture__/publication-join-reads":
            if query:
                self._json(400, {"status": "invalid_fixture_query"})
            elif not self.fixture.mismatched_shop_rollover:
                self._json(404, {"status": "not_found"})
            else:
                self._json(200, self.fixture.publication_join_reads())
        elif path == "/__fixture__/last-score-query":
            self._json(200, {"last": self.fixture.last_score_query()})
        elif path == "/__fixture__/last-full-score-query":
            self._json(200, {"last": self.fixture.last_full_score_query()})
        elif path == "/__fixture__/shop-visible":
            if self.fixture.acknowledge_visible_shop():
                self._json(200, {"stopping": True})
                print("Shop fixture stopped after visual acknowledgement", flush=True)
                self.fixture.shutdown()
            else:
                self._json(409, {"status": "shop_not_ready"})
        elif path == "/api/publication":
            self._json(200, self.fixture.publication())
        elif path == "/api/features":
            self._json(200, {"appManual": False, "feedback": True})
        elif path.startswith("/api/feedback/"):
            self._feedback_status(path.removeprefix("/api/feedback/"))
        elif path == "/api/service-info":
            self._json(200, SERVICE_INFO_DISCOVERY if self.fixture.service_info_discovery
                       else SERVICE_INFO_IDLE)
        elif path == "/api/version":
            self._json(200, {"version": "fixture"})
        elif path == "/api/account/search":
            terms = query.get("q", [])
            limits = query.get("limit", [])
            if (set(query) != {"q", "limit"} or len(terms) != 1
                    or len(limits) != 1 or not 2 <= len(terms[0].strip()) <= 200):
                self._json(400, {"status": "invalid_account_search"})
                return
            try:
                limit = int(limits[0])
            except ValueError:
                self._json(400, {"status": "invalid_account_search"})
                return
            if not 1 <= limit <= 10:
                self._json(400, {"status": "invalid_account_search"})
                return
            if terms[0].strip().casefold() == "blocked":
                self._json(403, {"status": "account_search_denied"})
                return
            if terms[0].strip().casefold() == "busy":
                self._json(503, {"status": "account_search_unavailable"})
                return
            if terms[0].strip().casefold() == "rate":
                self._json(429, {"status": "account_search_rate_limited"})
                return
            if terms[0].strip().casefold() == "slowpoke":
                # Holds the global-search spinner on screen for UI tests (issue #299).
                time.sleep(SLOW_ACCOUNT_SEARCH_SECONDS)
                self._json(200, {"results": []})
                return
            term = terms[0].strip().casefold()
            candidates = (
                {"accountId": _edge_profile["accountId"],
                 "displayName": _edge_profile["displayName"]},
            ) if self.fixture.metadata_edge else (
                {"accountId": "fixture-player-1", "displayName": "Fixture Player 1"},
                {"accountId": "fixture-player-2", "displayName": "Fixture Player 2"},
                {"accountId": "fixture-cpp", "displayName": "C++"},
                {"accountId": "fixture-syncing", "displayName": "Syncing Player"},
                {"accountId": "fixture-empty", "displayName": "Empty Player"},
                {"accountId": "fixture-denied", "displayName": "Denied Player"},
            )
            matches = [
                player for player in candidates
                if (player["displayName"].casefold().startswith(term) if len(term) <= 2
                    else term in player["displayName"].casefold())
            ]
            self._json(200, {"results": matches[:limit]})
        elif match := PLAYER_HISTORY.fullmatch(path):
            account_id = match.group(1)
            if set(query) - {"songId", "instrument"}:
                self._json(400, {"status": "invalid_player_history_query"})
                return
            pin = self.headers.get("X-FST-Publication-Id")
            if pin is not None and pin != str(self.fixture.publication_id):
                self._json(409, {"status": "publication_changed"})
                return
            if account_id == "fixture-syncing":
                self._json(202, {
                    "accountId": account_id, "count": 0, "history": [],
                    "status": "syncing", "notYetPublished": True,
                })
            elif account_id == "fixture-player-1":
                self._json(200, {
                    "accountId": account_id, "count": 2, "history": [
                        {
                            "songId": "fixture-pulse", "instrument": "Solo_Guitar",
                            "oldScore": 700000, "newScore": 850000,
                            "oldRank": 9, "newRank": 4, "accuracy": 991200,
                            "isFullCombo": True, "stars": 5, "season": 40,
                            "scoreAchievedAt": "2024-01-05T00:00:00Z",
                            "changedAt": "2024-01-05T00:00:00Z",
                        },
                        {
                            "songId": "fixture-pulse", "instrument": "Solo_Guitar",
                            "oldScore": None, "newScore": 700000,
                            "oldRank": None, "newRank": 9, "accuracy": 954500,
                            "isFullCombo": False, "stars": 4, "season": 39,
                            "scoreAchievedAt": "2024-01-01T00:00:00Z",
                            "changedAt": "2024-01-01T00:00:00Z",
                        },
                    ],
                })
            elif account_id == "fixture-history-multi":
                # Score History instrument switching (issue #31): Lead pages (eight
                # rows), Bass fits one page (two rows), Drums has a gold full combo.
                self._json(200, _multi_instrument_history(account_id))
            elif account_id == "fixture-history-fail":
                # Score History's failed state and Retry (issue #198).
                self._json(500, {"status": "internal_error"})
            else:
                # Every other fixture account is "unregistered" (never tracked for
                # history): the real service 404s and `FestivalAPI.playerHistory`
                # translates that into `PlayerHistoryState.unregistered`.
                self._json(404, {"status": "unknown_history_player"})
        elif match := PLAYER_NOTIFICATIONS.fullmatch(path):
            account_id = match.group(1)
            limits = query.get("limit", ["50"])
            if set(query) - {"limit"} or len(limits) != 1:
                self._json(400, {"status": "invalid_notifications_query"})
                return
            try:
                limit = int(limits[0])
            except ValueError:
                self._json(400, {"status": "invalid_notifications_query"})
                return
            if not 1 <= limit <= 200:
                self._json(400, {"status": "invalid_notifications_query"})
                return
            pin = self.headers.get("X-FST-Publication-Id")
            if pin is not None and pin != str(self.fixture.publication_id):
                self._json(409, {"status": "publication_changed"})
                return
            if account_id == "fixture-player-1":
                self._json(200, {
                    "generatedAt": "2024-01-05T00:00:00Z", "expiresAfterHours": 72,
                    "sourceRunId": 1, "sourceCompletedAt": "2024-01-05T00:00:00Z",
                    "notificationsGenerated": True, "items": [
                        {
                            "eventId": 1, "notificationGuid": "fixture-notif-1",
                            "accountId": account_id,
                            "eventKind": "player_song_rank_improved",
                            "songId": "fixture-pulse", "instrument": "Solo_Guitar",
                            "oldRank": 9, "newRank": 4,
                            "detectedAt": "2024-01-05T00:00:00Z",
                            "expiresAt": "2024-02-05T00:00:00Z",
                        },
                        {
                            "eventId": 2, "notificationGuid": "fixture-notif-2",
                            "accountId": account_id, "eventKind": "player_fc_achieved",
                            "songId": "fixture-pulse", "instrument": "Solo_Guitar",
                            "detectedAt": "2024-01-04T00:00:00Z",
                            "expiresAt": "2024-02-04T00:00:00Z",
                        },
                    ][:limit],
                })
            else:
                # An unregistered/unknown account gets an empty *generated* envelope,
                # never a 404 (`FestivalAPI+Notifications.swift`'s doc comment).
                self._json(200, {
                    "generatedAt": "2024-01-05T00:00:00Z", "expiresAfterHours": 72,
                    "sourceRunId": None, "sourceCompletedAt": None,
                    "notificationsGenerated": False, "items": [],
                })
        elif match := BAND_RANKINGS.fullmatch(path):
            band_type = match.group(1)
            if band_type not in BAND_TYPES:
                self._json(404, {"status": "unknown_band_type"})
                return
            pin = self.headers.get("X-FST-Publication-Id")
            if pin is not None and pin != str(self.fixture.publication_id):
                self._json(409, {"status": "publication_changed"})
                return
            rank_by = query.get("rankBy", ["totalscore"])[0]
            try:
                page = int(query.get("page", ["1"])[0])
                page_size = int(query.get("pageSize", ["10"])[0])
            except ValueError:
                self._json(400, {"status": "invalid_pagination"})
                return
            if page < 1 or not 1 <= page_size <= 200:
                self._json(400, {"status": "invalid_pagination"})
                return
            team_keys = query.get("teamKey", [])
            if team_keys:
                team_key = team_keys[0]
                if team_key == "fixture-team-503":
                    self.send_response(503)
                    self.send_header("Retry-After", "30")
                    self.send_header("X-Fst-Public-Read-Freeze-Reason", "scrape")
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                known = {
                    "fixture-team-1": 1, "fixture-team-2": 2,
                }
                deep = re.fullmatch(r"fixture-team-(\d+)", team_key)
                if self.fixture.large_rankings and deep and 2 < int(deep.group(1)) <= LARGE_RANKINGS_TEAMS:
                    known[team_key] = int(deep.group(1))
                selected = (
                    _band_detail(team_key, known[team_key], band_type)
                    if team_key in known else None
                )
                self._json(200, {
                    "bandType": band_type, "rankBy": rank_by, "page": 1,
                    "pageSize": 1, "totalTeams": 2, "entries": [],
                    "selectedBandEntry": selected,
                })
                return
            total = LARGE_RANKINGS_TEAMS if self.fixture.large_rankings else 2
            start = (page - 1) * page_size
            entries = [
                _band_ranking_entry(rank)
                for rank in range(start + 1, min(start + page_size, total) + 1)
            ]
            self._json(200, {
                "bandType": band_type, "rankBy": rank_by, "page": page,
                "pageSize": page_size, "totalTeams": total, "entries": entries,
            })
        elif match := PLAYER_RANK_HISTORY.fullmatch(path):
            # Pure-read `GET /api/rankings/{instrument}/{accountId}/history`
            # (`InstrumentDatabase.GetRankHistory`). The two player-demo accounts get
            # the committed 7-day series on every instrument; any other fixture
            # account is simply unranked (an empty `history`, never a 404).
            instrument, account_id = match.group(1), match.group(2)
            if instrument not in INSTRUMENTS:
                self._json(404, {"error": f"Unknown instrument: {instrument}"})
                return
            if set(query) - {"days", "leeway"}:
                self._json(400, {"status": "invalid_rank_history_query"})
                return
            ranked = account_id in {"fixture-player-1", "fixture-player-2"}
            self._json(200, {
                "instrument": instrument, "accountId": account_id,
                "history": PLAYER_RANK_HISTORY_DEMO["history"] if ranked else [],
            })
        elif match := BAND_HISTORY.fullmatch(path):
            band_type, team_key = match.group(1), match.group(2)
            if band_type not in BAND_TYPES:
                self._json(404, {"status": "unknown_band_type"})
                return
            try:
                days = int(query.get("days", ["30"])[0])
            except ValueError:
                self._json(400, {"status": "invalid_band_history_query"})
                return
            if not 1 <= days <= 3650:
                self._json(400, {"status": "invalid_band_history_query"})
                return
            if team_key == "fixture-team-1":
                history = [
                    {
                        "snapshotDate": date, "snapshotTakenAt": f"{date}T00:00:00Z",
                        "adjustedSkillRank": rank, "weightedRank": rank,
                        "fcRateRank": rank, "totalScoreRank": rank,
                        "adjustedSkillRating": 0.04 - rank * 0.01,
                        "weightedRating": 0.05 - rank * 0.01, "fcRate": 0.3,
                        "totalScore": 49_500_000, "songsPlayed": 29,
                        "totalChartedSongs": 50, "totalRankedTeams": 2,
                    }
                    for rank, date in enumerate(
                        ["2024-01-01", "2024-01-02", "2024-01-03"], start=1
                    )
                ]
            else:
                history = []
            self._json(200, {
                "bandType": band_type, "teamKey": team_key, "days": days,
                "history": history, "historyStatus": None, "historyMessage": None,
            })
        elif match := BAND_SONGS.fullmatch(path):
            band_type, team_key = match.group(1), match.group(2)
            if band_type not in BAND_TYPES:
                self._json(404, {"status": "unknown_band_type"})
                return
            try:
                limit = int(query.get("limit", ["5"])[0])
            except ValueError:
                self._json(400, {"status": "invalid_band_songs_query"})
                return
            if not 1 <= limit <= 20:
                self._json(400, {"status": "invalid_band_songs_query"})
                return
            if team_key == "fixture-team-1":
                best = [{
                    "songId": "fixture-pulse", "comboId": None, "rank": 1,
                    "totalEntries": 10, "percentile": 0.1, "score": 95_000,
                    "accuracy": 970_000, "isFullCombo": True, "stars": 5,
                    "season": 10, "endTime": None,
                }]
                worst = [{
                    "songId": "fixture-ghost-song", "comboId": None, "rank": 8,
                    "totalEntries": 10, "percentile": 0.8, "score": 40_000,
                    "accuracy": 800_000, "isFullCombo": False, "stars": 2,
                    "season": 10, "endTime": None,
                }]
            else:
                best, worst = [], []
            self._json(200, {
                "bandType": band_type, "teamKey": team_key, "limit": limit,
                "best": best[:limit], "worst": worst[:limit],
            })
        elif match := PLAYER_INSTRUMENT_RANKING.fullmatch(path):
            instrument, account_id = match.group(1), match.group(2)
            if instrument not in INSTRUMENTS:
                self._json(404, {"status": "unknown_instrument"})
                return
            if account_id == "fixture-rank-fail":
                self._json(500, {"status": "internal_error"})
                return
            roster = {
                "fixture-player-1": (1, "Fixture Player 1"),
                "fixture-player-2": (2, "Fixture Player 2"),
                "fixture-rank-3": (3, "Fixture Rank 3"),
            }
            total = LARGE_RANKINGS_ACCOUNTS if self.fixture.large_rankings else len(roster)
            deep = re.fullmatch(r"fixture-rank-(\d+)", account_id)
            if self.fixture.large_rankings and deep and 3 < int(deep.group(1)) <= total:
                roster[account_id] = (int(deep.group(1)), f"Fixture Rank {deep.group(1)}")
            if account_id not in roster:
                self._json(404, {"status": "account_not_ranked"})
                return
            rank, display_name = roster[account_id]
            self._json(200, {
                **_ranking_entry(rank, account_id, display_name),
                "instrument": instrument, "totalRankedAccounts": total,
            })
        elif match := RANKINGS.fullmatch(path):
            instrument = match.group(1)
            if instrument not in INSTRUMENTS:
                self._json(404, {"status": "unknown_instrument"})
                return
            pin = self.headers.get("X-FST-Publication-Id")
            if pin is not None and pin != str(self.fixture.publication_id):
                self._json(409, {"status": "publication_changed"})
                return
            rank_by = query.get("rankBy", ["totalscore"])[0]
            try:
                page = int(query.get("page", ["1"])[0])
                page_size = int(query.get("pageSize", ["10"])[0])
            except ValueError:
                self._json(400, {"status": "invalid_pagination"})
                return
            if page < 1 or not 1 <= page_size <= 200:
                self._json(400, {"status": "invalid_pagination"})
                return
            roster = [
                ("fixture-player-1", "Fixture Player 1"),
                ("fixture-player-2", "Fixture Player 2"),
                ("fixture-rank-3", "Fixture Rank 3"),
            ]
            if self.fixture.large_rankings:
                roster += [
                    (f"fixture-rank-{n}", f"Fixture Rank {n}")
                    for n in range(len(roster) + 1, LARGE_RANKINGS_ACCOUNTS + 1)
                ]
            total = len(roster)
            start = (page - 1) * page_size
            entries = [
                _ranking_entry(rank, account_id, display_name)
                for rank, (account_id, display_name)
                in enumerate(roster[start:start + page_size], start=start + 1)
            ]
            self._json(200, {
                "instrument": instrument, "rankBy": rank_by, "page": page,
                "pageSize": page_size, "totalAccounts": total, "entries": entries,
            })
        elif match := PLAYER_BANDS.fullmatch(path):
            account_id = match.group(1)
            groups = query.get("group", ["all"])
            if set(query) - {"group", "page", "pageSize"} or len(groups) != 1:
                self._json(400, {"status": "invalid_player_bands_query"})
                return
            group = groups[0]
            if group not in ("all", "duos", "trios", "quads"):
                self._json(400, {"status": "invalid_player_bands_query"})
                return
            try:
                page = int(query.get("page", ["1"])[0])
                page_size = int(query.get("pageSize", ["25"])[0])
            except ValueError:
                self._json(400, {"status": "invalid_pagination"})
                return
            if page < 1 or not 1 <= page_size <= 100:
                self._json(400, {"status": "invalid_pagination"})
                return
            if account_id == "fixture-player-1":
                by_group = {
                    "duos": [
                        _player_band_entry(
                            "fixture-band-1" if index == 1 else f"fixture-pband-duo-{index}",
                            "fixture-team-1" if index == 1 else f"fixture-pteam-duo-{index}",
                            "Band_Duets", 2
                        )
                        for index in range(1, 19)
                    ],
                    "trios": [
                        _player_band_entry(
                            f"fixture-pband-trio-{index}", f"fixture-pteam-trio-{index}",
                            "Band_Trios", 3
                        )
                        for index in range(1, 9)
                    ],
                    "quads": [
                        _player_band_entry(
                            f"fixture-pband-quad-{index}", f"fixture-pteam-quad-{index}",
                            "Band_Quad", 4
                        )
                        for index in range(1, 5)
                    ],
                }
                by_group["all"] = by_group["duos"] + by_group["trios"] + by_group["quads"]
                entries = by_group[group]
            else:
                entries = []
            total = len(entries)
            start = (page - 1) * page_size
            self._json(200, {
                "accountId": account_id, "totalCount": total,
                "entries": entries[start:start + page_size],
            })
        elif match := PLAYER.fullmatch(path):
            account_id = match.group(1)
            if query:
                self._json(400, {"status": "invalid_player_query"})
                return
            pin = self.headers.get("X-FST-Publication-Id")
            if pin is not None and pin != str(self.fixture.publication_id):
                self._json(409, {"status": "publication_changed"})
                return
            if self.fixture.metadata_edge:
                if account_id == _edge_profile["accountId"]:
                    self._json(200, _edge_profile)
                else:
                    self._json(404, {"status": "unknown_metadata_edge_player"})
            elif account_id == "fixture-denied":
                self._json(403, {"status": "player_profile_denied"})
            elif account_id == "fixture-syncing":
                self._json(202, {
                    "accountId": account_id, "displayName": "Syncing Player",
                    "status": "syncing", "notYetPublished": True,
                    "totalScores": 0, "scores": [],
                })
            elif account_id == "fixture-rank-unranked":
                # A registered player with one Lead score but outside the
                # rankings roster, so `PLAYER_INSTRUMENT_RANKING` 404s and
                # `InstrumentGlobalRankView` shows its honest unranked state.
                self._json(200, {
                    "accountId": account_id, "displayName": "Fixture Rank Unranked",
                    "totalScores": 1, "scores": [{
                        "si": "fixture-pulse", "ins": "01", "sc": 80_000, "acc": 900,
                        "fc": False, "st": 3, "sn": 9, "pct": 0.5, "rk": 6, "te": 26,
                    }],
                })
            elif account_id == "fixture-rank-fail":
                # A registered player with one Lead score, so its Global Rank
                # section renders and calls `PLAYER_INSTRUMENT_RANKING`, which
                # this fixture always 500s for this one account (see above) —
                # exercises `InstrumentGlobalRankView`'s failed/retry state.
                self._json(200, {
                    "accountId": account_id, "displayName": "Fixture Rank Fail",
                    "totalScores": 1, "scores": [{
                        "si": "fixture-pulse", "ins": "01", "sc": 90_000, "acc": 950,
                        "fc": False, "st": 4, "sn": 9, "pct": 0.5, "rk": 5, "te": 26,
                    }],
                })
            elif account_id in ("fixture-empty", "fixture-cpp"):
                self._json(200, {
                    "accountId": account_id,
                    "displayName": "Empty Player" if account_id == "fixture-empty" else "C++",
                    "totalScores": 0, "scores": [],
                })
            elif account_id in PLAYER_DEMO["profiles"]:
                profile = PLAYER_DEMO["profiles"][account_id]
                if (self.fixture.mismatched_shop_rollover
                        and self.fixture.publication_id == 8
                        and account_id == "fixture-player-2"):
                    profile = {
                        **profile,
                        "scores": [
                            {**score, "sc": ROLLOVER_PLAYER_2_LEAD_SCORE}
                            if score.get("si") == "fixture-pulse"
                            and score.get("ins") == "01" else score
                            for score in profile["scores"]
                        ],
                    }
                self._json(200, profile)
                if self.fixture.mismatched_shop_rollover:
                    self.fixture.record_publication_join_read("player")
            else:
                self._json(200, {
                    "accountId": account_id, "displayName": None,
                    "totalScores": 0, "scores": [],
                })
        elif path == "/api/shop":
            scenarios = query.get("scenario", ["demo"])
            if len(scenarios) != 1 or scenarios[0] not in (
                "demo", "empty", "error", "shop-empty", "shop-error",
                "shop-single", "art-error", "art-skip", "art-white"
            ):
                self._json(400, {"status": "unknown_fixture_scenario"})
                return
            if self.fixture.mismatched_shop_rollover and scenarios[0] != "demo":
                self._json(400, {"status": "unsupported_publication_join_scenario"})
                return
            if scenarios[0] in ("error", "shop-error"):
                self._json(503, {"status": "fixture_shop_unavailable"})
                return
            if self.fixture.metadata_edge:
                if scenarios[0] != "demo":
                    self._json(400, {"status": "unsupported_metadata_edge_scenario"})
                    return
                shop, etag = METADATA_EDGE["shop"], '"fst-fixture-metadata-edge-shop-v1"'
            elif scenarios[0] in ("empty", "shop-empty"):
                shop, etag = {
                    "count": 0, "songs": [], "newSongs": [], "lastUpdated": None,
                }, '"fst-fixture-shop-empty-v1"'
            elif scenarios[0] == "shop-single":
                shop, etag = {
                    **SHOP_DEMO,
                    "count": 1,
                    "songs": [SHOP_DEMO["songs"][0]],
                }, '"fst-fixture-shop-single-v1"'
            elif self.fixture.mismatched_shop_rollover and self.fixture.publication_id == 8:
                shop, etag = {
                    **SHOP_DEMO,
                    "count": 1,
                    "songs": [SHOP_DEMO["songs"][0]],
                }, '"fst-fixture-shop-rollover-v8"'
            elif scenarios[0] == "art-white":
                shop, etag = {
                    **SHOP_DEMO,
                    "songs": [
                        {**SHOP_DEMO["songs"][0], "albumArt": "/__fixture__/art/white.png"},
                        SHOP_DEMO["songs"][1],
                    ],
                }, '"fst-fixture-shop-white-v1"'
            else:
                shop, etag = SHOP_DEMO, SHOP_ETAG
            pin = self.headers.get("X-FST-Publication-Id")
            if pin is not None and pin != str(self.fixture.publication_id):
                self._json(409, {"status": "publication_changed"})
            elif self.headers.get("If-None-Match") == etag:
                self._json(304, None, etag=etag)
            else:
                self._json(200, shop, etag=etag)
                self.fixture.record_shop_read()
        elif path in (
            "/__fixture__/art/pulse.png", "/__fixture__/art/orbit.png",
            "/__fixture__/art/white.png",
        ):
            self._art(path.split("/")[-1].removesuffix(".png"))
        elif path == "/api/songs":
            scenarios = query.get("scenario", ["demo"])
            if len(scenarios) != 1 or scenarios[0] not in (
                "demo", "empty", "error", "shop-empty", "shop-error",
                "shop-single", "art-error", "art-skip", "art-white"
            ):
                self._json(400, {"status": "unknown_fixture_scenario"})
                return
            if self.fixture.mismatched_shop_rollover and scenarios[0] != "demo":
                self._json(400, {"status": "unsupported_publication_join_scenario"})
                return
            if self.fixture.mismatched_shop_rollover and self.fixture.publication_id == 8:
                pin = self.headers.get("X-FST-Publication-Id")
                if pin is not None and pin != "8":
                    self._json(409, {"status": "publication_changed"})
                else:
                    self.fixture.record_publication_join_read("failedSongs")
                    self._json(503, {"status": "fixture_new_songs_unavailable"})
                return
            if scenarios[0] == "error":
                self._json(503, {"status": "fixture_unavailable"})
                return
            if scenarios[0] == "art-white" and self.fixture.should_fail_white_catalogue():
                self._json(503, {"status": "fixture_initial_white_failure"})
                return
            if self.fixture.metadata_edge:
                if scenarios[0] != "demo":
                    self._json(400, {"status": "unsupported_metadata_edge_scenario"})
                    return
                songs, etag = METADATA_EDGE["songs"], '"fst-fixture-metadata-edge-songs-v1"'
            elif scenarios[0] == "empty":
                songs, etag = EMPTY_SONGS, EMPTY_ETAG
            elif scenarios[0] == "art-error":
                songs = {
                    **DEMO_SONGS,
                    "songs": [
                        {**song, "albumArt": f"/__fixture__/art/unavailable-{index}.png"}
                        for index, song in enumerate(DEMO_SONGS["songs"])
                    ],
                }
                etag = '"fst-fixture-art-error-v1"'
            elif scenarios[0] == "art-skip":
                missing = {
                    **DEMO_SONGS["songs"][0],
                    "songId": "fixture-missing",
                    "title": "Fixture Missing",
                    "albumArt": "/__fixture__/art/unavailable-middle.png",
                }
                songs = {
                    **DEMO_SONGS,
                    "count": 3,
                    "songs": [
                        DEMO_SONGS["songs"][0], missing, DEMO_SONGS["songs"][1],
                    ],
                }
                etag = '"fst-fixture-art-skip-v1"'
            elif scenarios[0] == "art-white":
                songs = {
                    **DEMO_SONGS,
                    "count": 1,
                    "songs": [{
                        **DEMO_SONGS["songs"][0],
                        "songId": "fixture-white",
                        "title": "Fixture White",
                        "albumArt": "/__fixture__/art/white.png",
                    }],
                }
                etag = '"fst-fixture-art-white-v1"'
            elif self.fixture.large_catalogue:
                rows = DEMO_SONGS["songs"] + LARGE_CATALOGUE_SONGS
                songs = {**DEMO_SONGS, "count": len(rows), "songs": rows}
                etag = '"fst-fixture-large-catalogue-v1"'
            elif self.fixture.long_titles:
                rows = [
                    {**song, "title": LONG_TITLE} if song["songId"] == "fixture-pulse" else song
                    for song in DEMO_SONGS["songs"]
                ]
                songs = {**DEMO_SONGS, "songs": rows}
                etag = '"fst-fixture-long-titles-v1"'
            else:
                songs, etag = DEMO_SONGS, SONGS_ETAG
            pin = self.headers.get("X-FST-Publication-Id")
            if pin is not None and pin != str(self.fixture.publication_id):
                self._json(409, {"status": "publication_changed"})
            elif self.headers.get("If-None-Match") == etag:
                self._json(304, None, etag=etag)
            else:
                self._json(200, songs, etag=etag)
                if self.fixture.should_stop_after_songs():
                    print("Songs fixture stopped after validated catalogue", flush=True)
                    self.fixture.shutdown()
        elif match := PATH_ARTIFACT.fullmatch(path):
            song_id, instrument, difficulty, data_route = match.groups()
            pin = self.headers.get("X-FST-Publication-Id")
            query_pin = query.get("publicationId", [None])
            if pin is not None and pin != str(self.fixture.publication_id):
                self._json(409, {"status": "publication_changed"})
                return
            if (set(query) - {"generationId", "publicationId"}
                    or len(query.get("generationId", ["fixture-path-generation"])) != 1
                    or len(query_pin) != 1
                    or query_pin[0] not in (None, str(self.fixture.publication_id))):
                self._json(400, {"status": "invalid_path_query"})
                return
            if instrument not in INSTRUMENTS or instrument == "Solo_PeripheralVocals":
                self._json(400, {"status": "invalid_path_instrument"})
                return
            if difficulty not in ("easy", "medium", "hard", "expert"):
                self._json(400, {"status": "invalid_path_difficulty"})
                return
            if (song_id != "fixture-pulse"
                    or query.get("generationId", ["fixture-path-generation"])[0]
                        != "fixture-path-generation"
                    or difficulty in ("easy", "medium")
                    or instrument != "Solo_Guitar"):
                self._json(404, {"status": "path_not_generated"})
                return
            etag = f'"fst-fixture-{difficulty}-{"json" if data_route else "png"}-v1"'
            if data_route:
                if self.headers.get("If-None-Match") == etag:
                    self._json(304, None, etag=etag)
                else:
                    self._json(200, {
                        **PATH_DEMO,
                        "difficulty": difficulty,
                        "pathSummary": f"Two synthetic {difficulty.title()} activations",
                    }, etag=etag)
            else:
                self._path_image(difficulty, etag)
        elif match := SONG_BAND_LEADERBOARDS_ALL.fullmatch(path):
            # Checked before the per-size route, whose pattern also matches `all`.
            account_ids = query.get("accountId", [])
            try:
                top = int(query.get("top", ["10"])[0])
            except ValueError:
                self._json(400, {"status": "invalid_query"})
                return
            if not 1 <= top <= 50 or len(account_ids) > 1:
                self._json(400, {"status": "invalid_query"})
                return
            self._json(200, _song_band_leaderboards_all(
                match.group(1), top, account_ids[0] if account_ids else None
            ))
        elif match := SONG_BAND_LEADERBOARD.fullmatch(path):
            song_id, band_type = match.groups()
            if band_type not in BAND_TYPES:
                self._json(404, {"status": "unknown_band_type"})
                return
            account_ids = query.get("accountId", [])
            try:
                top = int(query.get("top", ["25"])[0])
                offset = int(query.get("offset", ["0"])[0])
            except ValueError:
                self._json(400, {"status": "invalid_pagination"})
                return
            if not 1 <= top <= 100 or offset < 0 or len(account_ids) > 1:
                self._json(400, {"status": "invalid_pagination"})
                return
            if song_id == "fixture-pulse" and band_type == "Band_Duets":
                # Ranks 1-29; rank 29 (page 2) is `fixture-player-1`'s band, the row
                # Song Detail appends to its Duos preview, so its jump lands on a real
                # row and the pinned footer can jump or open (#307).
                all_entries = [_song_band_leaderboard_entry(rank, band_type)
                               for rank in range(1, SELECTED_SONG_BAND_RANK)]
                all_entries.append(_selected_song_band_entry("fixture-player-1", band_type))
            else:
                all_entries = []
            # A `fixture-player-*` `accountId` adds that player's rank-29 band as the
            # `selectedPlayerEntry` (the service's pure-read
            # `GetSongBandLeaderboardEntryForAccount`), pinned as the page footer.
            selected = (_selected_song_band_entry(account_ids[0] if account_ids else None, band_type)
                        if all_entries else None)
            total = len(all_entries)
            entries = all_entries[offset:offset + top]
            self._json(200, {
                "songId": song_id, "bandType": band_type, "count": len(entries),
                "totalEntries": total, "localEntries": total, "entries": entries,
                "selectedPlayerEntry": selected, "selectedBandEntry": None,
            })
        elif match := LEADERBOARD.fullmatch(path):
            song_id, instrument = match.groups()
            pin = self.headers.get("X-FST-Publication-Id")
            if pin is not None and pin != str(self.fixture.publication_id):
                self._json(409, {"status": "publication_changed"})
                return
            if song_id == "fixture-white" and instrument in INSTRUMENTS:
                self._json(503, {"status": "fixture_score_unavailable"})
                return
            if (instrument not in INSTRUMENTS
                    or (song_id != EDGE_SONG_ID if self.fixture.metadata_edge
                        else song_id not in ("fixture-pulse", "fixture-orbit")
                        and not (self.fixture.large_catalogue
                                 and song_id in {row["songId"] for row in LARGE_CATALOGUE_SONGS}))):
                self._json(404, {"status": "unknown_chart"})
                return
            if any(len(query.get(key, [""])) != 1 for key in ("top", "offset", "leeway")):
                self._json(400, {"status": "invalid_query"})
                return
            try:
                top = int(query.get("top", ["25"])[0])
                offset = int(query.get("offset", ["0"])[0])
                leeway = float(query["leeway"][0]) if "leeway" in query else None
            except (ValueError, IndexError):
                self._json(400, {"status": "invalid_pagination"})
                return
            if (top < 1 or top > 100 or offset < 0
                    or (leeway is not None and (not math.isfinite(leeway) or not -5 <= leeway <= 5))):
                self._json(400, {"status": "invalid_pagination"})
                return
            self.fixture.record_score_query(top, offset, leeway)
            if self.fixture.metadata_edge:
                if instrument != "Solo_Guitar":
                    self._json(404, {"status": "metadata_edge_chart_missing"})
                    return
                entries = METADATA_EDGE["leaderboard"]["entries"] if offset == 0 else []
                self._json(200, {
                    **METADATA_EDGE["leaderboard"],
                    "count": len(entries),
                    "entries": entries,
                })
                return
            ranks = range(offset + 1, min(offset + top, 26) + 1) if instrument == "Solo_Guitar" else ()
            entries = [
                {
                    "accountId": f"fixture-player-{rank}",
                    "displayName": f"Fixture Player {rank}",
                    "score": 100000 - rank * 100,
                    "rank": rank,
                    **({"accuracy": 980000 - rank} if rank not in (3, 4) else {}),
                    "isFullCombo": rank % 2 == 0,
                    "stars": 5,
                    "season": 9,
                }
                for rank in ranks
            ]
            if (self.fixture.mismatched_shop_rollover
                    and self.fixture.publication_id == 8
                    and song_id == "fixture-pulse"
                    and instrument == "Solo_Guitar"):
                for entry in entries:
                    if entry["rank"] == 2:
                        entry["score"] = ROLLOVER_PLAYER_2_LEAD_SCORE
            total = 26 if instrument == "Solo_Guitar" else 0
            if song_id == "fixture-pulse" and instrument == "Solo_Drums":
                total = 1
                if offset == 0:
                    entries = [{
                        "accountId": "fixture-player-2",
                        "displayName": PLAYER_DEMO["profiles"]["fixture-player-2"]["displayName"],
                        "score": DRUMS_SCORE["sc"],
                        "rank": DRUMS_SCORE["rk"],
                        "accuracy": DRUMS_SCORE["acc"] * 1_000,
                        "isFullCombo": DRUMS_SCORE["fc"],
                        "stars": DRUMS_SCORE["st"],
                        "season": DRUMS_SCORE["sn"],
                    }]
            self._json(200, {
                "songId": song_id, "instrument": instrument, "count": len(entries),
                "localEntries": total, "totalEntries": total,
                "showLeaderboardEntryTotals": True, "entries": entries,
            })
            if self.fixture.should_stop_after_score(top):
                print("Scores fixture stopped after full chart", flush=True)
                self.fixture.shutdown()
        elif match := RIVALS_DETAIL.fullmatch(path):
            account_id, token, rival_id = match.groups()
            sorts = query.get("sort", ["closest"])
            limits = query.get("limit", ["0"])
            offsets = query.get("offset", ["0"])
            # The service also accepts `allowLiveFallback` (web Find Rival).
            live = query.get("allowLiveFallback", ["false"])
            if (set(query) - {"sort", "limit", "offset", "allowLiveFallback"} or len(sorts) != 1
                    or sorts[0] not in ("closest", "they_lead", "you_lead")
                    or len(limits) != 1 or len(offsets) != 1
                    or len(live) != 1 or live[0] not in ("true", "false")):
                self._json(400, {"status": "invalid_rivals_query"})
                return
            scenario = _rivals_scenario(account_id)
            if scenario == "unavailable":
                self.send_response(503)
                self.send_header("Retry-After", "30")
                self.send_header("X-Fst-Public-Read-Freeze-Reason", "scrape")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self._json(200, _rival_detail_body(token, rival_id, scenario))
        elif match := RIVALS_LIST.fullmatch(path):
            account_id, token = match.groups()
            if query:
                self._json(400, {"status": "invalid_rivals_query"})
                return
            scenario = _rivals_scenario(account_id)
            if scenario == "unavailable":
                self.send_response(503)
                self.send_header("Retry-After", "30")
                self.send_header("X-Fst-Public-Read-Freeze-Reason", "scrape")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self._json(200, _rivals_list_body(token, scenario))
        elif match := LEADERBOARD_RIVALS_DETAIL.fullmatch(path):
            account_id, instrument, rival_id = match.groups()
            rank_bys = query.get("rankBy", ["totalscore"])
            sorts = query.get("sort", ["closest"])
            if (set(query) - {"rankBy", "sort"} or len(rank_bys) != 1 or len(sorts) != 1
                    or sorts[0] not in ("closest", "they_lead", "you_lead")):
                self._json(400, {"status": "invalid_rivals_query"})
                return
            scenario = _rivals_scenario(account_id)
            if scenario == "unavailable":
                self.send_response(503)
                self.send_header("Retry-After", "30")
                self.send_header("X-Fst-Public-Read-Freeze-Reason", "scrape")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self._json(
                200,
                _leaderboard_rival_detail_body(instrument, rank_bys[0], rival_id, scenario),
            )
        elif match := LEADERBOARD_RIVALS_LIST.fullmatch(path):
            account_id, instrument = match.groups()
            rank_bys = query.get("rankBy", ["totalscore"])
            if set(query) - {"rankBy"} or len(rank_bys) != 1:
                self._json(400, {"status": "invalid_rivals_query"})
                return
            scenario = _rivals_scenario(account_id)
            if scenario == "unavailable":
                self.send_response(503)
                self.send_header("Retry-After", "30")
                self.send_header("X-Fst-Public-Read-Freeze-Reason", "scrape")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            self._json(200, _leaderboard_rivals_body(instrument, rank_bys[0], scenario))
        else:
            self._json(404, {"status": "not_found"})

    def do_POST(self) -> None:
        """Accept fixture feedback; reject every other mutation attempt.

        Returns:
            None; a JSON response is written to the local response.
        """
        if urlsplit(self.path).path == "/api/feedback":
            self._feedback()
            return
        self._json(405, {"status": "mock_is_read_only"})

    def _feedback(self) -> None:
        """Fixture for the native feedback form's ``POST /api/feedback`` (issue #78).

        Mirrors the service contract (``docs/components/in-app-feedback.md`` in the service
        repository): flat multipart text fields plus ``media`` file parts, answered with
        ``202 {"id", "status": "queued"}``. Refuses privileged or selected-profile headers.
        A title containing ``fixture-unavailable`` answers ``503 feedback_busy`` and one
        containing ``fixture-failed`` queues a job that later fails, so automation can reach
        both error states. Nothing is filed anywhere.

        Returns:
            None; a JSON response is written to the local response.
        """
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(min(length, 100 * 1024 * 1024)) if length > 0 else b""
        names = {name.lower() for name in self.headers.keys()}
        if "x-api-key" in names or any(name.startswith("x-fst-selected") for name in names):
            self._json(400, {"error": "Forbidden header.", "code": "invalid_form"})
            return
        if "multipart/form-data" not in (self.headers.get("Content-Type") or ""):
            self._json(400, {"error": "Submit multipart/form-data.", "code": "invalid_form"})
            return
        for field, code in (
            ("kind", "invalid_kind"), ("platform", "invalid_platform"),
            ("title", "title_required"), ("description", "description_required"),
        ):
            if f'name="{field}"'.encode() not in body:
                self._json(400, {"error": f"{field} is missing.", "code": code})
                return
        if b"fixture-unavailable" in body:
            payload = json.dumps({
                "error": "Too many reports are being processed right now.",
                "code": "feedback_busy",
            }).encode()
            self.send_response(503)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Retry-After", "60")
            self.end_headers()
            self.wfile.write(payload)
            return
        job = FEEDBACK_FAILED_JOB if b"fixture-failed" in body else FEEDBACK_FILED_JOB
        self._json(202, {"id": job, "status": "queued"})

    def _feedback_status(self, job: str) -> None:
        """Fixture for ``GET /api/feedback/{id}``: the filed job reports issue #1, the
        failed job reports ``failed`` and any other ID is ``404 not_found``.

        Args:
            job: Path segment after ``/api/feedback/``.

        Returns:
            None; a JSON response is written to the local response.
        """
        if job == FEEDBACK_FILED_JOB:
            self._json(200, {
                "id": job, "status": "submitted", "issueNumber": 1,
                "attachments": [],
            })
        elif job == FEEDBACK_FAILED_JOB:
            self._json(200, {
                "id": job, "status": "failed", "error": "fixture failure", "attachments": [],
            })
        else:
            self._json(404, {"error": "Feedback submission not found.", "code": "not_found"})

    def log_message(self, format: str, *args: object) -> None:
        """Avoid logging player identifiers or request URLs in automation output.

        Args:
            format: Server-provided log format (intentionally not printed).
            args: Request data (intentionally not printed).

        Returns:
            None; test responses and exceptions remain observable to callers.
        """

    # endregion


def main() -> None:
    """Bind the fixture server to loopback and serve until explicitly stopped.

    Returns:
        None; the command remains attached to the current development session.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--port", type=int, default=8765,
        help="0 asks the OS for a free loopback port (see the printed ready line)",
    )
    parser.add_argument("--unpinned", action="store_true")
    parser.add_argument("--rollover-on-read", type=int)
    parser.add_argument("--rollover-on-command", action="store_true")
    parser.add_argument("--mismatched-shop-rollover", action="store_true")
    parser.add_argument("--fail-first-white-catalogue", action="store_true")
    parser.add_argument("--stop-after-first-songs", action="store_true")
    parser.add_argument("--stop-after-first-score", action="store_true")
    parser.add_argument("--stop-after-first-shop", action="store_true")
    parser.add_argument("--metadata-edge", action="store_true")
    parser.add_argument(
        "--large-rankings", action="store_true",
        help="pad rankings to 1,200 accounts / 600 teams for multi-page pager captures",
    )
    parser.add_argument(
        "--large-catalogue", action="store_true",
        help="append 108 synthetic songs (#, A-Z) for scrolling/section-index captures",
    )
    parser.add_argument(
        "--long-titles", action="store_true",
        help="retitle fixture-pulse wider than any bar for pinned-title width journeys",
    )
    parser.add_argument(
        "--service-info-discovery", action="store_true",
        help="serve an updating Service Info body in the registered-band discovery phase",
    )
    args = parser.parse_args()
    if not 0 <= args.port <= 65535:
        parser.error("port must be between 0 (OS-assigned) and 65535")
    if args.rollover_on_read is not None and args.rollover_on_read < 2:
        parser.error("rollover-on-read must be at least 2")
    one_shot_count = sum((
        args.stop_after_first_songs, args.stop_after_first_score,
        args.stop_after_first_shop,
    ))
    if one_shot_count:
        if not args.unpinned:
            parser.error("one-shot offline fixtures require --unpinned")
        if one_shot_count > 1:
            parser.error("choose one endpoint for the one-shot connection loss")
    if args.mismatched_shop_rollover and not args.rollover_on_command:
        parser.error("mismatched Shop rollover needs an explicit command")
    if args.rollover_on_command and (
        args.unpinned == args.mismatched_shop_rollover
        or args.rollover_on_read is not None
        or one_shot_count or args.fail_first_white_catalogue or args.metadata_edge
    ):
        parser.error("command rollover requires a separate persistent fixture mode")
    with FixtureServer(
        ("127.0.0.1", args.port), FixtureHandler,
        unpinned=args.unpinned, rollover_on_read=args.rollover_on_read,
        rollover_on_command=args.rollover_on_command,
        mismatched_shop_rollover=args.mismatched_shop_rollover,
        fail_first_white_catalogue=args.fail_first_white_catalogue,
        stop_after_first_songs=args.stop_after_first_songs,
        stop_after_first_score=args.stop_after_first_score,
        stop_after_first_shop=args.stop_after_first_shop,
        metadata_edge=args.metadata_edge,
        large_rankings=args.large_rankings,
        large_catalogue=args.large_catalogue,
        long_titles=args.long_titles,
        service_info_discovery=args.service_info_discovery,
    ) as server:
        print(f"Local test fixture service on 127.0.0.1:{server.server_port}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
