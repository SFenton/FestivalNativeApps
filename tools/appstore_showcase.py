#!/usr/bin/env python3
"""Deterministic App Store showcase fixture service: Epic-only songs, synthetic people.

The overlay reuses ``tools/mock_service.py``'s loopback server, publication pinning and
response headers, but serves a catalogue filtered to songs whose artist is exactly
``Epic Games`` plus seeded, obviously fictional players, scores, rankings and rivals. It
exists so the Songs, Suggestions, Statistics, Compete and Rivals tabs can be screenshotted
without exposing any real account. Nothing here contacts production except the single
keyless ``GET /api/songs`` of the ``fetch`` command.

Commands::

    python3 tools/appstore_showcase.py fetch --out ~/.cache/fst-appstore/songs.json
    python3 tools/appstore_showcase.py check --catalogue ~/.cache/fst-appstore/songs.json
    python3 tools/appstore_showcase.py serve --port 18795 --catalogue ~/.cache/fst-appstore/songs.json
    python3 tools/appstore_showcase.py shoot --out-dir /tmp/appstore-shots   # macOS, after ios_sim.py build

Catalogue payloads must stay outside the repository; artwork stays a CDN-relative filename
that the app resolves itself, so no art bytes are stored or bundled.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import re
import subprocess
import sys
import threading
import urllib.request
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterator
from urllib.parse import parse_qs, urlsplit

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import mock_service  # type: ignore[import-not-found]
else:
    from . import mock_service

# region Constants

SEED = "fst-appstore-showcase-v1"
EPIC_ARTIST = "Epic Games"
# Titles whose artist is exactly "Epic Games" but which are tied to licensed third-party
# franchises and so must not appear in store screenshots.
EXCLUDED_TITLES = frozenset({"Where My Wookiees At?", "Gwenpool's Multiverse", "For Latveria"})
SONG_FIELDS = (
    "songId", "title", "artist", "album", "year", "tempo", "sig", "durationSeconds",
    "albumArt", "doubleBassSupported", "genres", "difficulty", "maxScores",
)
DEFAULT_SEASON = 15
SHOWCASE_ETAG = '"fst-showcase-songs-v1"'
SHOWCASE_SHOP_ETAG = '"fst-showcase-shop-v1"'
PUBLIC_SONGS_URL = "https://festivalscoretracker.com/api/songs"
DEFAULT_CATALOGUE = Path("~/.cache/fst-appstore/songs.json")
USER_AGENT = "FestivalNativeApps-appstore-showcase/1.0"
AS_OF = date(2026, 9, 30)
FAR_FUTURE = "2099-01-01T00:00:00Z"

PLAYER_ID = "showcase-player-1"
PLAYER_NAME = "StageDiver"
RANK_METRICS = ("totalscore", "adjusted", "weighted", "fcrate", "maxscore")
HISTORY_DAYS = 120
ACCOUNT_ID = r"[A-Za-z0-9_-]{1,128}"


@dataclass(frozen=True)
class InstrumentSpec:
    """One chart type: wire keys plus the showcase player's play share and population."""

    key: str
    code: str
    difficulty_key: str
    player_cover: float
    population: float
    total_ranked: int
    ranks: tuple[int, int, int, int, int]  # totalscore, adjusted, weighted, fcrate, maxscore


INSTRUMENT_SPECS = (
    InstrumentSpec("Solo_Guitar", "01", "guitar", 0.89, 1.00, 24180, (3, 4, 5, 4, 3)),
    InstrumentSpec("Solo_Bass", "02", "bass", 0.62, 0.55, 11420, (5, 6, 7, 5, 6)),
    InstrumentSpec("Solo_Drums", "04", "drums", 0.66, 0.75, 15260, (2, 3, 3, 2, 2)),
    InstrumentSpec("Solo_Vocals", "08", "vocals", 0.58, 0.65, 13040, (7, 9, 8, 6, 9)),
    InstrumentSpec("Solo_PeripheralGuitar", "10", "proGuitar", 0.40, 0.30, 6310, (9, 11, 10, 8, 12)),
    InstrumentSpec("Solo_PeripheralBass", "20", "proBass", 0.28, 0.22, 3980, (12, 14, 13, 11, 15)),
    InstrumentSpec("Solo_PeripheralCymbals", "80", "proCymbals", 0.22, 0.18, 3370, (11, 13, 12, 10, 14)),
    InstrumentSpec("Solo_PeripheralDrums", "100", "proDrums", 0.30, 0.20, 4150, (8, 10, 9, 7, 11)),
)
SPEC_BY_KEY = {spec.key: spec for spec in INSTRUMENT_SPECS}
SPEC_BY_CODE = {spec.code: spec for spec in INSTRUMENT_SPECS}
KARAOKE = "Solo_PeripheralVocals"
#: Charts where the player is #1: mostly Lead, the rest on these other core instruments.
TOP_RANK_SLOTS = 5
TOP_RANK_LEAD_SLOTS = 3
TOP_RANK_OTHERS = ("Solo_Bass", "Solo_Drums", "Solo_Vocals")
#: Share of the remaining scores promoted into ranks 2-10.
TOP_TEN_SHARE = 0.15
KARAOKE_TOTAL = 2100
UNPLAYED_REFERENCE = {"total": 40_000_000, "max_percent": 0.9, "fc": 20, "played": 60, "avg_rank": 800.0}
PRO_DRUMS_TOKEN = "pro_drums"
SORTS = ("closest", "they_lead", "you_lead")


@dataclass(frozen=True)
class RivalSpec:
    """A named fictional rival: id, name, rank bias (negative = better) and instrument shares."""

    account_id: str
    name: str
    bias: float
    covers: dict[str, float]


_CORE = {"Solo_Guitar": 0.88, "Solo_Bass": 0.82, "Solo_Drums": 0.8, "Solo_Vocals": 0.78}
RIVALS = (
    RivalSpec("showcase-rival-1", "NeonRiff", -0.35, {**_CORE, "Solo_PeripheralGuitar": 0.5}),
    RivalSpec("showcase-rival-2", "BassQuake", -0.20, {**_CORE, "Solo_PeripheralBass": 0.6}),
    RivalSpec("showcase-rival-3", "EchoLark", -0.10, {**_CORE, "Solo_PeripheralDrums": 0.4}),
    RivalSpec("showcase-rival-4", "TempoTide", 0.05, {**_CORE, "Solo_PeripheralCymbals": 0.4}),
    RivalSpec("showcase-rival-5", "VoxNova", 0.15, {
        "Solo_Vocals": 0.92, "Solo_Guitar": 0.8, "Solo_Bass": 0.5, "Solo_Drums": 0.45}),
    RivalSpec("showcase-rival-6", "DrumLine77", 0.30, {
        "Solo_Drums": 0.95, "Solo_PeripheralDrums": 0.8, "Solo_PeripheralCymbals": 0.7,
        "Solo_Guitar": 0.5, "Solo_Bass": 0.4, "Solo_Vocals": 0.4}),
    RivalSpec("showcase-rival-7", "PixelPick", -0.28, {
        "Solo_Guitar": 0.9, "Solo_Bass": 0.85, "Solo_Drums": 0.7, "Solo_Vocals": 0.6,
        "Solo_PeripheralGuitar": 0.6, "Solo_PeripheralBass": 0.5}),
    RivalSpec("showcase-rival-8", "CrowdSurfer", 0.40, {
        "Solo_Vocals": 0.8, "Solo_Drums": 0.75, "Solo_Bass": 0.65, "Solo_Guitar": 0.7}),
    RivalSpec("showcase-rival-9", "SynthComet", -0.05, {**_CORE, "Solo_PeripheralGuitar": 0.45}),
    RivalSpec("showcase-rival-10", "RiffRaven", 0.22, {
        "Solo_Guitar": 0.9, "Solo_PeripheralGuitar": 0.8, "Solo_PeripheralBass": 0.6,
        "Solo_Bass": 0.55, "Solo_Vocals": 0.45}),
)
RIVAL_BY_ID = {rival.account_id: rival for rival in RIVALS}
_NAME_PREFIXES = (
    "Neon", "Echo", "Pixel", "Static", "Velvet", "Cosmic", "Turbo", "Lunar", "Crimson",
    "Glitch", "Arcade", "Midnight", "Solar", "Rapid", "Hyper", "Chrome",
)
_NAME_SUFFIXES = (
    "Riff", "Lark", "Pick", "Wave", "Surfer", "Quake", "Tide", "Nova", "Fox", "Drift",
    "Pulse", "Comet", "Fret", "Beat", "Strum", "Bolt",
)
NEIGHBOUR_ID = re.compile(r"^showcase-(totalscore|adjusted|weighted|fcrate|maxscore)-([0-9a-f]{2,3})-(\d+)$")

# endregion

# region Catalogue


def filter_catalogue(payload: dict) -> dict:
    """Reduce a public catalogue to the showcase's Epic-only song set.

    Args:
        payload: A ``GET /api/songs`` envelope (raw or already filtered).

    Returns:
        An envelope whose ``count`` matches its songs, containing only rows whose artist is
        exactly ``Epic Games`` and whose title is not in ``EXCLUDED_TITLES``. Only fields in
        ``SONG_FIELDS`` are kept, and ``albumArt`` is left as the original CDN filename.
    """
    songs = []
    for row in payload.get("songs", []):
        if row.get("artist") != EPIC_ARTIST or row.get("title") in EXCLUDED_TITLES:
            continue
        songs.append({key: row[key] for key in SONG_FIELDS if key in row})
    season = payload.get("currentSeason")
    return {
        "count": len(songs),
        "currentSeason": season if isinstance(season, int) else DEFAULT_SEASON,
        "songs": songs,
    }


def load_catalogue(path: Path | str) -> dict:
    """Read a cached public catalogue from disk.

    Args:
        path: JSON file produced by the ``fetch`` command.

    Returns:
        The decoded envelope.
    """
    with open(Path(path).expanduser(), encoding="utf-8") as handle:
        return json.load(handle)


def fetch_catalogue(out: Path | str) -> Path:
    """Perform the single allowlisted keyless public catalogue GET and save it.

    Args:
        out: Destination file; refused when it resolves inside the repository.

    Returns:
        The written path.
    """
    destination = Path(out).expanduser().resolve()
    repo_root = Path(__file__).resolve().parent.parent
    if repo_root in destination.parents:
        raise SystemExit("refusing to write catalogue payloads inside the repository")
    request = urllib.request.Request(PUBLIC_SONGS_URL, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:  # noqa: S310 - fixed https URL
        body = response.read()
    json.loads(body)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(body)
    return destination


# endregion

# region Deterministic helpers


def _rng(*parts: object) -> random.Random:
    """Build a reproducible random stream for one named entity.

    Args:
        parts: Values naming the entity; joined with the global seed.

    Returns:
        A ``random.Random`` whose output depends only on the parts.
    """
    return random.Random(":".join([SEED, *map(str, parts)]))


def _fan_names() -> list[str]:
    """Return the shuffled pool of generic fictional display names (no rival names).

    Returns:
        Unique names such as ``VelvetFret``, in a fixed seeded order.
    """
    reserved = {rival.name for rival in RIVALS} | {PLAYER_NAME}
    names = [p + s for p in _NAME_PREFIXES for s in _NAME_SUFFIXES if p + s not in reserved]
    _rng("names").shuffle(names)
    return names


FAN_NAMES = _fan_names()


def fan_name(index: int) -> str:
    """Name a generic fictional account, adding a numeric tag past the pool size.

    Args:
        index: Zero-based, stable position.

    Returns:
        A display name unique for indexes within ``len(FAN_NAMES) * 99``.
    """
    base = FAN_NAMES[index % len(FAN_NAMES)]
    lap = index // len(FAN_NAMES)
    return base if lap == 0 else f"{base}{lap + 1}"


def _ratio(fraction: float) -> float:
    """Map a chart-population fraction (rank / entries) to a score-over-maximum ratio.

    Args:
        fraction: Value in (0, 1]; smaller is better.

    Returns:
        Monotone non-increasing ratio between 0.698 and 0.998.
    """
    return 0.998 - 0.30 * math.sqrt(min(max(fraction, 1e-9), 1.0))


def _accuracy(fraction: float) -> float:
    """Derive accuracy (0-1) from a population fraction; better ranks are more accurate.

    Args:
        fraction: Value in (0, 1]; smaller is better.

    Returns:
        Accuracy between 0.88 and 1.0.
    """
    return min(1.0, 1.0 - 0.12 * min(max(fraction, 1e-9), 1.0) ** 0.8)


def _stars(accuracy: float) -> int:
    """Convert accuracy to a star count where 6 is gold.

    Args:
        accuracy: Fractional accuracy.

    Returns:
        Stars from 3 to 6.
    """
    if accuracy >= 0.985:
        return 6
    if accuracy >= 0.94:
        return 5
    return 4 if accuracy >= 0.90 else 3


def _iso(moment: datetime) -> str:
    """Format a UTC moment as the service's second-precision ISO string.

    Args:
        moment: Timestamp to format.

    Returns:
        ``YYYY-MM-DDTHH:MM:SSZ``.
    """
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


# endregion

# region Overlay model


@dataclass
class RivalData:
    """A rival's identity and per-chart ranks (song id, instrument) -> rank."""

    account_id: str
    name: str
    charts: dict[tuple[str, str], int]


class Showcase:
    """Fully materialised, deterministic showcase data derived from a public catalogue."""

    def __init__(self, catalogue: dict, *, as_of: date = AS_OF) -> None:
        """Build every showcase payload source from a catalogue envelope.

        Args:
            catalogue: Raw or filtered public ``/api/songs`` envelope.
            as_of: Fixed "today" used for history, notification and shop timestamps.
        """
        self.as_of = as_of
        self.songs_payload = filter_catalogue(catalogue)
        self.songs = self.songs_payload["songs"]
        self.current_season = self.songs_payload["currentSeason"]
        self.by_id = {song["songId"]: song for song in self.songs}
        self.max_score: dict[tuple[str, str], int] = {}
        self.population: dict[tuple[str, str], int] = {}
        for song in self.songs:
            for spec in INSTRUMENT_SPECS:
                charted = song.get("difficulty", {}).get(spec.difficulty_key)
                maximum = song.get("maxScores", {}).get(spec.key)
                if charted is None or charted < 0 or charted == 99 or not maximum:
                    continue
                key = (song["songId"], spec.key)
                self.max_score[key] = int(maximum)
                self.population[key] = max(500, int(_rng("te", *key).randint(18000, 90000) * spec.population))
        self.player_scores: dict[tuple[str, str], dict] = {}
        self._build_player_scores()
        self.charted_counts = {
            spec.key: sum(1 for key in self.max_score if key[1] == spec.key) for spec in INSTRUMENT_SPECS
        }
        self.occupied: dict[tuple[str, str], dict[int, str]] = {}
        self.rivals: dict[str, RivalData] = {}
        for spec in RIVALS:
            self.rivals[spec.account_id] = self._named_rival(spec)
        self._neighbours: dict[str, RivalData] = {}

    # region Scores

    def score_at_rank(self, key: tuple[str, str], rank: int) -> int:
        """Return the chart's canonical score at a leaderboard rank.

        Args:
            key: ``(songId, instrument)``.
            rank: 1-based rank within the chart population.

        Returns:
            An integer score no greater than the chart's maximum.
        """
        return int(self.max_score[key] * _ratio(rank / self.population[key]))

    def _build_player_scores(self) -> None:
        """Generate the selected player's scores for every instrument share in the spec."""
        for song in self.songs:
            for spec in INSTRUMENT_SPECS:
                key = (song["songId"], spec.key)
                if key not in self.max_score:
                    continue
                rng = _rng("player", *key)
                if rng.random() > spec.player_cover:
                    continue
                quality = rng.betavariate(2.0, 1.4)
                fraction = 0.002 + 0.55 * (1 - quality) ** 2.6
                te = self.population[key]
                rank = max(1, min(te, round(te * fraction)))
                self.player_scores[key] = self._score(key, spec.code, rank, rng)
        self._promote_top_ranks()

    def _score(self, key: tuple[str, str], code: str, rank: int, rng: random.Random) -> dict:
        """Build one wire score for a chart at a given leaderboard rank.

        Args:
            key: ``(songId, instrument)``.
            code: Hex instrument code.
            rank: 1-based rank within the chart population.
            rng: Seeded stream for the full-combo, difficulty and season draws.

        Returns:
            A wire score whose score, accuracy, stars and percentile follow from the rank.
        """
        te = self.population[key]
        accuracy = _accuracy(rank / te)
        lag = rng.choices(range(9), weights=(40, 18, 12, 8, 6, 6, 4, 3, 3))[0]
        return {
            "si": key[0], "ins": code, "sc": self.score_at_rank(key, rank),
            "acc": min(1000, round(accuracy * 1000)),
            "fc": rank == 1 or (accuracy >= 0.96 and rng.random() < 0.36),
            "st": _stars(accuracy), "dif": 3 if rng.random() < 0.85 else 2,
            "sn": max(1, self.current_season - lag),
            "pct": round(rank / te, 6), "rk": rank, "te": te,
        }

    def _promote_top_ranks(self) -> None:
        """Lift a seeded handful of charts to #1 and a further share into the top 10.

        Lead charts take most of the #1 slots; the rest go to other core instruments. About 15%
        of the remaining scores become ranks 2-10, so Statistics shows a believable best rank.
        """
        order = sorted(self.player_scores, key=lambda key: _rng("promote", *key).random())
        lead = [key for key in order if key[1] == "Solo_Guitar"]
        others = [key for key in order if key[1] in TOP_RANK_OTHERS]
        firsts = lead[:TOP_RANK_LEAD_SLOTS] + others[:TOP_RANK_SLOTS - TOP_RANK_LEAD_SLOTS]
        firsts += [key for key in lead[TOP_RANK_LEAD_SLOTS:] + others[TOP_RANK_SLOTS - TOP_RANK_LEAD_SLOTS:]
                   if key not in firsts][:TOP_RANK_SLOTS - len(firsts)]
        rest = [key for key in order if key not in firsts]
        for key in firsts:
            self.player_scores[key] = self._promote(key, 1)
        for key in rest[:round(len(rest) * TOP_TEN_SHARE)]:
            self.player_scores[key] = self._promote(key, _rng("top-ten", *key).randint(2, 10))

    def _promote(self, key: tuple[str, str], rank: int) -> dict:
        """Rebuild a chart's score at a better rank, keeping its season and difficulty draws.

        Args:
            key: ``(songId, instrument)``.
            rank: The new 1-based rank.

        Returns:
            The replacement wire score.
        """
        code = SPEC_BY_KEY[key[1]].code
        return self._score(key, code, min(rank, self.player_scores[key]["rk"]), _rng("promoted", *key))

    def _score_rows(self) -> list[dict]:
        """Return the player's scores in catalogue then instrument order.

        Returns:
            Wire score objects, one per ``(song, instrument)``.
        """
        return [
            self.player_scores[(song["songId"], spec.key)]
            for song in self.songs for spec in INSTRUMENT_SPECS
            if (song["songId"], spec.key) in self.player_scores
        ]

    # endregion

    # region Rivals

    def _named_rival(self, spec: RivalSpec) -> RivalData:
        """Create a named rival and reserve its ranks so song leaderboards agree with it.

        Args:
            spec: The rival's constants.

        Returns:
            Rival data with one rank per chart it plays.
        """
        charts: dict[tuple[str, str], int] = {}
        for song in self.songs:
            for inst in INSTRUMENT_SPECS:
                key = (song["songId"], inst.key)
                share = spec.covers.get(inst.key)
                if share is None or key not in self.max_score:
                    continue
                rng = _rng("rival", spec.account_id, *key)
                mine = self.player_scores.get(key)
                if mine is not None:
                    if rng.random() > share:
                        continue
                    base = mine["rk"] / mine["te"]
                else:
                    if rng.random() > share * 0.45:
                        continue
                    base = 0.002 + 0.55 * (1 - rng.betavariate(2.0, 1.4)) ** 2.6
                rank = self._place(key, base, spec.bias, rng, mine["rk"] if mine else None, spec.account_id)
                charts[key] = rank
        return RivalData(spec.account_id, spec.name, charts)

    def _place(
        self, key: tuple[str, str], base: float, bias: float, rng: random.Random,
        player_rank: int | None, owner: str | None,
    ) -> int:
        """Pick a rank near ``base`` shifted by ``bias``, avoiding rank collisions.

        Args:
            key: ``(songId, instrument)``.
            base: Starting rank fraction.
            bias: Log-space shift; negative is better than the base.
            rng: Stream used for the noise term.
            player_rank: The selected player's rank on the chart, which must stay unique.
            owner: Account reserving the rank, or None for lazy neighbours (no reservation).

        Returns:
            A 1-based rank within the chart population.
        """
        te = self.population[key]
        fraction = min(1.0, base * math.exp(bias + 0.6 * rng.gauss(0, 1)))
        rank = max(1, min(te, round(te * fraction)))
        taken = self.occupied.setdefault(key, {})
        while rank == player_rank or (owner is not None and rank in taken):
            rank = rank + 1 if rank < te else max(1, rank - 3)
        if owner is not None:
            taken[rank] = owner
        return rank

    def neighbour(self, account_id: str) -> RivalData | None:
        """Build (and cache) a rankings-neighbour rival from its encoded account id.

        Args:
            account_id: ``showcase-{metric}-{code}-{rank}``.

        Returns:
            Rival data on the encoded instrument, or None when the id does not decode.
        """
        if account_id in self._neighbours:
            return self._neighbours[account_id]
        match = NEIGHBOUR_ID.fullmatch(account_id)
        if match is None or match.group(2) not in SPEC_BY_CODE:
            return None
        metric, code, rank_text = match.group(1), match.group(2), int(match.group(3))
        spec = SPEC_BY_CODE[code]
        gap = rank_text - self.player_rank(spec.key, metric)
        bias = (0.12 + 0.06 * min(abs(gap), 8)) * (1 if gap > 0 else -1)
        charts: dict[tuple[str, str], int] = {}
        for key, mine in self.player_scores.items():
            if key[1] != spec.key:
                continue
            rng = _rng("neighbour", account_id, *key)
            if rng.random() > 0.93:
                continue
            charts[key] = self._place(key, mine["rk"] / mine["te"], bias, rng, mine["rk"], None)
        data = RivalData(account_id, self.ranking_name(spec.key, metric, rank_text), charts)
        self._neighbours[account_id] = data
        return data

    def rival_data(self, account_id: str) -> RivalData | None:
        """Look up any named or neighbour rival.

        Args:
            account_id: Rival account id.

        Returns:
            The rival, or None when unknown.
        """
        return self.rivals.get(account_id) or self.neighbour(account_id)

    def _shared(self, rival: RivalData, instruments: list[str]) -> list[dict]:
        """List charts the player and rival both have, with ranks and scores.

        Args:
            rival: Rival to compare against.
            instruments: Instrument keys in scope.

        Returns:
            Rows ``{key, ur, rr, us, rs}`` in catalogue then instrument order.
        """
        rows = []
        for song in self.songs:
            for inst in instruments:
                key = (song["songId"], inst)
                mine, rank = self.player_scores.get(key), rival.charts.get(key)
                if mine is None or rank is None:
                    continue
                rows.append({
                    "key": key, "ur": mine["rk"], "rr": rank, "us": mine["sc"],
                    "rs": self.score_at_rank(key, rank),
                })
        return rows

    @staticmethod
    def _stats(rows: list[dict]) -> dict:
        """Summarise shared-chart rows into rival counters.

        Args:
            rows: Output of ``_shared``.

        Returns:
            Wire fields sharedSongCount, aheadCount, behindCount, avgSignedDelta and rivalScore.
            Rank deltas are clipped to +/-250 in the average so one deep chart cannot flip its sign.
        """
        shared = len(rows)
        if shared == 0:
            return {"sharedSongCount": 0, "aheadCount": 0, "behindCount": 0,
                    "avgSignedDelta": 0.0, "rivalScore": 0.0}
        closeness = sum(min(r["ur"], r["rr"]) / max(r["ur"], r["rr"]) for r in rows) / shared
        return {
            "sharedSongCount": shared,
            "aheadCount": sum(1 for r in rows if r["rr"] < r["ur"]),
            "behindCount": sum(1 for r in rows if r["rr"] > r["ur"]),
            "avgSignedDelta": round(sum(max(-250, min(250, r["rr"] - r["ur"])) for r in rows) / shared, 4),
            "rivalScore": round(1000 * closeness * min(1.0, shared / 50), 4),
        }

    @staticmethod
    def scope_instruments(token: str) -> list[str] | None:
        """Decode a rivals scope token to instrument keys.

        Args:
            token: An instrument raw value, the Pro Drums family token or a combo hex mask.

        Returns:
            Instrument keys, or None when the token is not a known scope.
        """
        if token in SPEC_BY_KEY:
            return [token]
        if token == PRO_DRUMS_TOKEN:
            return ["Solo_PeripheralCymbals", "Solo_PeripheralDrums"]
        if re.fullmatch(r"[0-9a-f]{1,4}", token):
            mask = int(token, 16)
            found = [spec.key for spec in INSTRUMENT_SPECS if mask & int(spec.code, 16)]
            if found and mask & ~sum(int(spec.code, 16) for spec in INSTRUMENT_SPECS) == 0:
                return found
        return None

    def rivals_list(self, token: str) -> dict | None:
        """Build ``GET /api/player/{id}/rivals/{token}``.

        Args:
            token: Scope token.

        Returns:
            The list body, or None for an unknown scope.
        """
        instruments = self.scope_instruments(token)
        if instruments is None:
            return None
        above, below = [], []
        for rival in self.rivals.values():
            stats = self._stats(self._shared(rival, instruments))
            if stats["sharedSongCount"] == 0:
                continue
            summary = {"accountId": rival.account_id, "displayName": rival.name, **stats}
            (above if stats["avgSignedDelta"] < 0 else below).append(summary)
        for side in (above, below):
            side.sort(key=lambda item: -item["rivalScore"])
        return {"combo": token, "above": above, "below": below}

    def _detail_rows(self, rows: list[dict], sort: str) -> list[dict]:
        """Order shared rows for a detail page and project them to wire rows.

        Args:
            rows: Output of ``_shared``.
            sort: One of ``SORTS`` (an ordering; every shared chart is still returned).

        Returns:
            Wire song comparison rows.
        """
        if sort == "closest":
            ordered = sorted(rows, key=lambda r: (abs(r["rr"] - r["ur"]), r["key"]))
        elif sort == "they_lead":
            ordered = sorted(rows, key=lambda r: (r["rr"] - r["ur"], r["key"]))
        else:
            ordered = sorted(rows, key=lambda r: (-(r["rr"] - r["ur"]), r["key"]))
        result = []
        for row in ordered:
            song = self.by_id[row["key"][0]]
            result.append({
                "songId": song["songId"], "title": song["title"], "artist": song["artist"],
                "instrument": row["key"][1], "userInstrument": None, "rivalInstrument": None,
                "userRank": row["ur"], "rivalRank": row["rr"], "rankDelta": row["rr"] - row["ur"],
                "userScore": row["us"], "rivalScore": row["rs"],
            })
        return result

    def _compete_lists(self, rival: RivalData, instruments: list[str]) -> tuple[list[dict], list[dict]]:
        """Build ``songsToCompete`` and ``yourExclusiveSongs`` for a rival comparison.

        Args:
            rival: Rival being compared.
            instruments: Instrument keys in scope.

        Returns:
            Rival-only charts, then player-only charts, each limited to 12 best-ranked rows.
        """
        compete, exclusive = [], []
        for song in self.songs:
            for inst in instruments:
                key = (song["songId"], inst)
                mine, rank = self.player_scores.get(key), rival.charts.get(key)
                head = {"songId": song["songId"], "title": song["title"],
                        "artist": song["artist"], "instrument": inst}
                if rank is not None and mine is None:
                    compete.append({**head, "score": self.score_at_rank(key, rank), "rank": rank})
                elif mine is not None and rank is None:
                    exclusive.append({**head, "score": mine["sc"], "rank": mine["rk"]})
        compete.sort(key=lambda row: row["rank"])
        exclusive.sort(key=lambda row: row["rank"])
        return compete[:12], exclusive[:12]

    def rival_detail(
        self, token: str, rival_id: str, sort: str, limit: int, offset: int,
    ) -> dict | None:
        """Build ``GET /api/player/{id}/rivals/{token}/{rivalId}``.

        Args:
            token: Scope token.
            rival_id: Rival account id.
            sort: Ordering name.
            limit: Page size; 0 or less means every shared chart.
            offset: Rows to skip.

        Returns:
            The detail body, or None for an unknown scope or rival.
        """
        instruments, rival = self.scope_instruments(token), self.rival_data(rival_id)
        if instruments is None or rival is None:
            return None
        songs = self._detail_rows(self._shared(rival, instruments), sort)
        compete, exclusive = self._compete_lists(rival, instruments)
        page = songs[offset:offset + limit] if limit > 0 else songs[offset:]
        return {
            "rival": {"accountId": rival.account_id, "displayName": rival.name},
            "combo": token, "source": "precomputed", "totalSongs": len(songs),
            "offset": offset, "limit": limit if limit > 0 else max(50, len(songs)),
            "sort": sort, "songs": page, "songsToCompete": compete, "yourExclusiveSongs": exclusive,
        }

    def rivals_all(self) -> dict:
        """Build ``GET /api/player/{id}/rivals/all`` with per-instrument combos and samples.

        Returns:
            The all-combo rivals body; sample song indexes point into its ``songs`` array.
        """
        song_ids: list[str] = []
        index_of: dict[str, int] = {}
        combos = []
        for spec in INSTRUMENT_SPECS:
            above, below = [], []
            for rival in self.rivals.values():
                rows = self._shared(rival, [spec.key])
                if not rows:
                    continue
                samples = []
                for row in sorted(rows, key=lambda r: abs(r["rr"] - r["ur"]))[:12]:
                    sid = row["key"][0]
                    if sid not in index_of:
                        index_of[sid] = len(song_ids)
                        song_ids.append(sid)
                    samples.append({"s": index_of[sid], "i": spec.key, "ur": row["ur"],
                                    "rr": row["rr"], "us": row["us"], "rs": row["rs"]})
                stats = self._stats(rows)
                entry = {
                    "accountId": rival.account_id, "displayName": rival.name,
                    "direction": "above" if stats["avgSignedDelta"] < 0 else "below",
                    **stats, "samples": samples,
                }
                (above if entry["direction"] == "above" else below).append(entry)
            for side in (above, below):
                side.sort(key=lambda item: -item["rivalScore"])
            combos.append({"combo": spec.code,
                           "above": above, "below": below})
        return {"accountId": PLAYER_ID, "songs": song_ids, "combos": combos}

    # endregion

    # region Rankings

    def player_rank(self, instrument: str, metric: str) -> int:
        """Return the selected player's rank on an instrument for a ranking metric.

        Args:
            instrument: Instrument key.
            metric: One of ``RANK_METRICS``.

        Returns:
            The 1-based rank.
        """
        return SPEC_BY_KEY[instrument].ranks[RANK_METRICS.index(metric)]

    def ranking_total(self, instrument: str) -> int:
        """Return the ranked-account count for an instrument.

        Args:
            instrument: Instrument key, including karaoke.

        Returns:
            Total ranked accounts.
        """
        return KARAOKE_TOTAL if instrument == KARAOKE else SPEC_BY_KEY[instrument].total_ranked

    def ranking_account_id(self, instrument: str, metric: str, rank: int) -> str:
        """Return the account id shown at a rankings position.

        Args:
            instrument: Instrument key.
            metric: Ranking metric.
            rank: 1-based rank.

        Returns:
            The player's id at their own rank, otherwise ``showcase-{metric}-{code}-{rank}``.
        """
        if instrument != KARAOKE and rank == self.player_rank(instrument, metric):
            return PLAYER_ID
        code = "40" if instrument == KARAOKE else SPEC_BY_KEY[instrument].code
        return f"showcase-{metric}-{code}-{rank}"

    def ranking_name(self, instrument: str, metric: str, rank: int) -> str:
        """Return the fictional display name at a rankings position.

        Args:
            instrument: Instrument key.
            metric: Ranking metric.
            rank: 1-based rank.

        Returns:
            ``StageDiver`` at the player's rank, otherwise a pool name.
        """
        if instrument != KARAOKE and rank == self.player_rank(instrument, metric):
            return PLAYER_NAME
        offset = int(_rng("name-offset", instrument, metric).random() * len(FAN_NAMES))
        return fan_name(offset + rank - 1)

    def player_stats(self, instrument: str) -> dict:
        """Aggregate the player's scores on one instrument.

        Args:
            instrument: Instrument key.

        Returns:
            Counts and means used by rankings and rank history.
        """
        rows = [(key, score) for key, score in self.player_scores.items() if key[1] == instrument]
        played = len(rows)
        if played == 0:
            return {"played": 0}
        return {
            "played": played, "charted": self.charted_counts[instrument],
            "fc": sum(1 for _, s in rows if s["fc"]), "total": sum(s["sc"] for _, s in rows),
            "max_percent": sum(s["sc"] / self.max_score[k] for k, s in rows) / played,
            "accuracy": sum(s["acc"] * 1000 for _, s in rows) / played,
            "stars": sum(s["st"] for _, s in rows) / played,
            "best": min(s["rk"] for _, s in rows), "avg_rank": sum(s["rk"] for _, s in rows) / played,
        }

    def _reference_rank(self, instrument: str, metric: str, stats: dict) -> int:
        """Return the rank the reference stats are anchored to (6 for an unplayed instrument).

        Args:
            instrument: Instrument key.
            metric: Ranking metric.
            stats: Output of ``player_stats``.

        Returns:
            The player's rank when they have scores, otherwise 6.
        """
        return self.player_rank(instrument, metric) if stats["played"] else 6

    def _entry_for(self, instrument: str, metric: str, rank: int) -> dict:
        """Build one account ranking row for an instrument, metric and position.

        Args:
            instrument: Instrument key.
            metric: Ranking metric the row is listed under.
            rank: 1-based rank under that metric.

        Returns:
            A wire ``AccountRankingEntry`` object.
        """
        total = self.ranking_total(instrument)
        is_player = instrument != KARAOKE and rank == self.player_rank(instrument, metric)
        rng = _rng("entry", instrument, metric, rank)
        ranks = {}
        for name in RANK_METRICS:
            if name == metric:
                ranks[name] = rank
            elif is_player:
                ranks[name] = self.player_rank(instrument, name)
            else:
                ranks[name] = max(1, min(total, round(rank * math.exp(0.35 * rng.gauss(0, 1)))))
        stats = self.player_stats(instrument) if instrument != KARAOKE else {"played": 0}
        charted = self.charted_counts.get(instrument, 100)
        if is_player:
            played, fc, tot = stats["played"], stats["fc"], stats["total"]
            max_percent, accuracy = stats["max_percent"], stats["accuracy"]
            avg_stars, best, avg_rank = stats["stars"], stats["best"], stats["avg_rank"]
        else:
            ref = stats if stats["played"] else UNPLAYED_REFERENCE
            mine = self.player_rank(instrument, "totalscore") if stats["played"] else 6
            share = (rank / total) ** 0.4
            played = max(6, min(charted, round(charted * min(1.0, max(0.2, 0.99 - 0.55 * share)))))
            fc_rate = min(1.0, ref["fc"] / ref["played"] * (
                (self._reference_rank(instrument, "fcrate", stats) + 10) / (ranks["fcrate"] + 10)) ** 0.12)
            fc = round(played * fc_rate)
            tot = round(ref["total"] * ((mine + 10) / (ranks["totalscore"] + 10)) ** 0.9)
            max_percent = min(0.9995, ref["max_percent"] * (
                (self._reference_rank(instrument, "maxscore", stats) + 10) / (ranks["maxscore"] + 10)) ** 0.05)
            accuracy = round(1_000_000 * (1 - 0.13 * (rank / total) ** 0.5))
            avg_stars = max(3.0, 5.9 - 2.0 * (rank / total) ** 0.3)
            best = 1 + int(rng.random() * min(rank, 5))
            avg_rank = max(1.0, ref["avg_rank"] * (
                (rank + 10) / (self._reference_rank(instrument, metric, stats) + 10)) ** 0.6)
        fc_rate = round(fc / max(played, 1), 4)
        return {
            "accountId": PLAYER_ID if is_player else self.ranking_account_id(instrument, metric, rank),
            "displayName": PLAYER_NAME if is_player else self.ranking_name(instrument, metric, rank),
            "songsPlayed": played, "totalChartedSongs": charted,
            "coverage": round(played / max(charted, 1), 4),
            "rawSkillRating": round(ranks["adjusted"] / total, 6),
            "adjustedSkillRating": round(ranks["adjusted"] / total, 6),
            "adjustedSkillRank": ranks["adjusted"],
            "weightedRating": round(min(1.0, ranks["weighted"] / total * 1.1), 6),
            "weightedRank": ranks["weighted"], "fcRate": fc_rate, "fcRateRank": ranks["fcrate"],
            "totalScore": int(tot), "totalScoreRank": ranks["totalscore"],
            "maxScorePercent": round(max_percent, 4), "maxScorePercentRank": ranks["maxscore"],
            "avgAccuracy": int(accuracy), "fullComboCount": fc, "avgStars": round(avg_stars, 2),
            "bestRank": int(best), "avgRank": round(avg_rank, 2),
            "rawMaxScorePercent": round(max_percent, 4),
            "rawWeightedRating": round(min(1.0, ranks["weighted"] / total * 1.1), 6),
        }

    def rankings_page(self, instrument: str, metric: str, page: int, size: int) -> dict:
        """Build ``GET /api/rankings/{instrument}``.

        Args:
            instrument: Instrument key.
            metric: Ranking metric.
            page: 1-based page.
            size: Page size.

        Returns:
            The rankings page body.
        """
        total = self.ranking_total(instrument)
        start = (page - 1) * size
        ranks = range(start + 1, min(start + size, total) + 1)
        return {
            "instrument": instrument, "rankBy": metric, "page": page, "pageSize": size,
            "totalAccounts": total, "entries": [self._entry_for(instrument, metric, r) for r in ranks],
        }

    def player_ranking(self, instrument: str) -> dict | None:
        """Build ``GET /api/rankings/{instrument}/{accountId}`` for the selected player.

        Args:
            instrument: Instrument key.

        Returns:
            The player's entry with ``instrument`` and ``totalRankedAccounts``, or None if unranked.
        """
        if instrument not in SPEC_BY_KEY or not self.player_stats(instrument)["played"]:
            return None
        entry = self._entry_for(instrument, "totalscore", self.player_rank(instrument, "totalscore"))
        return {**entry, "instrument": instrument, "totalRankedAccounts": self.ranking_total(instrument)}

    def rank_history(self, instrument: str, days: int) -> dict:
        """Build ``GET /api/rankings/{instrument}/{accountId}/history`` with an improving trend.

        Args:
            instrument: Instrument key.
            days: Number of most recent daily snapshots to return.

        Returns:
            The history body (empty when the player has no scores on the instrument).
        """
        stats = self.player_stats(instrument) if instrument in SPEC_BY_KEY else {"played": 0}
        if not stats["played"]:
            return {"instrument": instrument, "accountId": PLAYER_ID, "history": []}
        total = self.ranking_total(instrument)
        final = {name: self.player_rank(instrument, name) for name in RANK_METRICS}
        history = []
        for back in range(HISTORY_DAYS - 1, -1, -1):
            t = 1 - back / (HISTORY_DAYS - 1)
            day = self.as_of - timedelta(days=back)
            ranks = {
                name: round(value + (value * 1.9 + 5 - value) * (1 - t) ** 1.6)
                for name, value in final.items()
            }
            played = stats["played"] - round((1 - t) * 8)
            fc = stats["fc"] - round((1 - t) * 6)
            history.append({
                "snapshotDate": day.isoformat(), "snapshotTakenAt": f"{day.isoformat()}T06:00:00Z",
                "adjustedSkillRank": ranks["adjusted"], "weightedRank": ranks["weighted"],
                "fcRateRank": ranks["fcrate"], "totalScoreRank": ranks["totalscore"],
                "maxScorePercentRank": ranks["maxscore"],
                "adjustedSkillRating": round(ranks["adjusted"] / total, 6),
                "weightedRating": round(min(1.0, ranks["weighted"] / total * 1.1), 6),
                "fcRate": round(fc / max(played, 1), 4),
                "totalScore": round(stats["total"] * (0.9 + 0.1 * t)),
                "maxScorePercent": round(stats["max_percent"] * (0.97 + 0.03 * t), 4),
                "songsPlayed": played, "coverage": round(played / stats["charted"], 4),
                "fullComboCount": fc, "totalChartedSongs": stats["charted"],
                "rankedAccountCount": total - round((1 - t) * 40),
                "rawMaxScorePercent": round(stats["max_percent"] * (0.97 + 0.03 * t), 4),
                "rawWeightedRating": round(min(1.0, ranks["weighted"] / total * 1.1), 6),
                "rawSkillRating": round(ranks["adjusted"] / total, 6),
            })
        return {"instrument": instrument, "accountId": PLAYER_ID, "history": history[-days:]}

    def leaderboard_rivals(self, instrument: str, rank_by: str) -> dict | None:
        """Build ``GET /api/player/{id}/leaderboard-rivals/{instrument}``.

        Args:
            instrument: Instrument key.
            rank_by: Ranking metric.

        Returns:
            Up to five rivals above and below the player's rank, or None if unranked.
        """
        if instrument not in SPEC_BY_KEY or rank_by not in RANK_METRICS:
            return None
        mine = self.player_rank(instrument, rank_by)
        total = self.ranking_total(instrument)
        above, below = [], []
        for rank in range(max(1, mine - 5), min(total, mine + 5) + 1):
            if rank == mine:
                continue
            rival = self.neighbour(self.ranking_account_id(instrument, rank_by, rank))
            stats = self._stats(self._shared(rival, [instrument]))
            summary = {
                "accountId": rival.account_id, "displayName": rival.name,
                "sharedSongCount": stats["sharedSongCount"], "aheadCount": stats["aheadCount"],
                "behindCount": stats["behindCount"], "avgSignedDelta": stats["avgSignedDelta"],
                "leaderboardRank": rank, "userLeaderboardRank": mine,
            }
            (above if rank < mine else below).append(summary)
        return {"instrument": instrument, "rankBy": rank_by, "userRank": mine,
                "above": above, "below": below}

    def leaderboard_rival_detail(
        self, instrument: str, rank_by: str, rival_id: str, sort: str,
    ) -> dict | None:
        """Build ``GET /api/player/{id}/leaderboard-rivals/{instrument}/{rivalId}``.

        Args:
            instrument: Instrument key.
            rank_by: Ranking metric.
            rival_id: Neighbour or named rival id.
            sort: Ordering name.

        Returns:
            The detail body, or None for an unknown instrument or rival.
        """
        rival = self.rival_data(rival_id)
        if instrument not in SPEC_BY_KEY or rank_by not in RANK_METRICS or rival is None:
            return None
        songs = self._detail_rows(self._shared(rival, [instrument]), sort)
        compete, exclusive = self._compete_lists(rival, [instrument])
        return {
            "rival": {"accountId": rival.account_id, "displayName": rival.name},
            "instrument": instrument, "rankBy": rank_by, "totalSongs": len(songs), "sort": sort,
            "songs": songs, "songsToCompete": compete, "yourExclusiveSongs": exclusive,
        }

    # endregion

    # region Player, leaderboards, history, shop

    def profile(self, account_id: str) -> dict:
        """Build ``GET /api/player/{id}``.

        Args:
            account_id: Any account id.

        Returns:
            The selected player's full profile, a rival's synthesised profile, or an empty one.
        """
        if account_id == PLAYER_ID:
            scores = self._score_rows()
            return {"accountId": PLAYER_ID, "displayName": PLAYER_NAME,
                    "totalScores": len(scores), "scores": scores}
        rival = self.rival_data(account_id)
        if rival is None:
            return {"accountId": account_id, "displayName": None, "totalScores": 0, "scores": []}
        scores = []
        for song in self.songs:
            for spec in INSTRUMENT_SPECS:
                key = (song["songId"], spec.key)
                rank = rival.charts.get(key)
                if rank is None:
                    continue
                accuracy = _accuracy(rank / self.population[key])
                rng = _rng("rival-score", rival.account_id, *key)
                scores.append({
                    "si": key[0], "ins": spec.code, "sc": self.score_at_rank(key, rank),
                    "acc": min(1000, round(accuracy * 1000)), "fc": accuracy >= 0.96 and rng.random() < 0.5,
                    "st": _stars(accuracy), "dif": 3, "sn": max(1, self.current_season - rng.randint(0, 4)),
                    "pct": round(rank / self.population[key], 6), "rk": rank, "te": self.population[key],
                })
        return {"accountId": account_id, "displayName": rival.name,
                "totalScores": len(scores), "scores": scores}

    def leaderboard(self, song_id: str, instrument: str, top: int, offset: int) -> dict | None:
        """Build ``GET /api/leaderboard/{songId}/{instrument}``.

        Args:
            song_id: Catalogue song id.
            instrument: Instrument key.
            top: Page size.
            offset: Zero-based starting row.

        Returns:
            The leaderboard body, or None for an unknown song or instrument.
        """
        if song_id not in self.by_id or instrument not in SPEC_BY_KEY and instrument != KARAOKE:
            return None
        key = (song_id, instrument)
        total = self.population.get(key, 0)
        entries = [self._leaderboard_entry(key, rank)
                   for rank in range(offset + 1, min(offset + top, total) + 1)]
        return {"songId": song_id, "instrument": instrument, "count": len(entries),
                "localEntries": total, "totalEntries": total,
                "showLeaderboardEntryTotals": True, "entries": entries}

    def _leaderboard_entry(self, key: tuple[str, str], rank: int) -> dict:
        """Build one leaderboard row, using the player or a reserved rival where they sit.

        Args:
            key: ``(songId, instrument)``.
            rank: 1-based rank.

        Returns:
            A wire leaderboard entry.
        """
        mine = self.player_scores.get(key)
        if mine is not None and mine["rk"] == rank:
            return {"accountId": PLAYER_ID, "displayName": PLAYER_NAME, "score": mine["sc"],
                    "rank": rank, "accuracy": mine["acc"] * 1000, "isFullCombo": mine["fc"],
                    "stars": mine["st"], "season": mine["sn"]}
        owner = self.occupied.get(key, {}).get(rank)
        rng = _rng("lb", *key, rank)
        accuracy = _accuracy(rank / self.population[key])
        if owner is not None:
            account_id, name = owner, self.rivals[owner].name
        else:
            offset = int(_rng("lb-offset", *key).random() * len(FAN_NAMES))
            account_id = f"showcase-lb-{SPEC_BY_KEY[key[1]].code}-{rank}-{key[0][:8]}"
            name = fan_name(offset + rank - 1)
        return {"accountId": account_id, "displayName": name, "score": self.score_at_rank(key, rank),
                "rank": rank, "accuracy": min(1000, round(accuracy * 1000)) * 1000,
                "isFullCombo": accuracy >= 0.96 and rng.random() < 0.5, "stars": _stars(accuracy),
                "season": max(1, self.current_season - rng.randint(0, 3))}

    def _recent_changes(self) -> list[dict]:
        """Create the selected player's recent score-change history, newest first.

        Returns:
            Wire history rows, each referencing a chart the player has scored.
        """
        keys = [k for k in self.player_scores if k[1] in ("Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals")]
        keys.sort()
        _rng("history").shuffle(keys)
        rows = []
        for index, key in enumerate(keys[:40]):
            mine, rng = self.player_scores[key], _rng("history-row", *key)
            moment = datetime.combine(self.as_of, datetime.min.time(), tzinfo=timezone.utc)
            moment -= timedelta(days=index * 1.5, hours=rng.randint(0, 20), minutes=rng.randint(0, 59))
            old_rank = round(mine["rk"] * rng.uniform(1.3, 2.2)) + 3
            rows.append({
                "songId": key[0], "instrument": key[1],
                "oldScore": int(mine["sc"] * rng.uniform(0.9, 0.97)), "newScore": mine["sc"],
                "oldRank": min(old_rank, mine["te"]), "newRank": mine["rk"],
                "accuracy": mine["acc"] * 1000, "isFullCombo": mine["fc"], "stars": mine["st"],
                "season": mine["sn"], "scoreAchievedAt": _iso(moment), "changedAt": _iso(moment),
            })
        return rows

    def history(self, song_id: str | None, instrument: str | None) -> dict:
        """Build ``GET /api/player/{id}/history``.

        Args:
            song_id: Optional chart filter.
            instrument: Optional instrument filter.

        Returns:
            The history envelope.
        """
        rows = [r for r in self._recent_changes()
                if (song_id is None or r["songId"] == song_id)
                and (instrument is None or r["instrument"] == instrument)]
        return {"accountId": PLAYER_ID, "count": len(rows), "history": rows}

    def notifications(self, limit: int) -> dict:
        """Build ``GET /api/player/{id}/notifications``.

        Args:
            limit: Maximum number of items.

        Returns:
            A generated envelope of rank-improved and full-combo events.
        """
        items = []
        for index, row in enumerate(self._recent_changes()[:8], start=1):
            kind = "player_fc_achieved" if row["isFullCombo"] and index % 2 == 0 else "player_song_rank_improved"
            item = {
                "eventId": index, "notificationGuid": f"showcase-notif-{index}", "accountId": PLAYER_ID,
                "eventKind": kind, "songId": row["songId"], "instrument": row["instrument"],
                "detectedAt": row["changedAt"], "expiresAt": FAR_FUTURE,
            }
            if kind == "player_song_rank_improved":
                item.update({"oldRank": row["oldRank"], "newRank": row["newRank"]})
            items.append(item)
        stamp = f"{self.as_of.isoformat()}T00:00:00Z"
        return {"generatedAt": stamp, "expiresAfterHours": 72, "sourceRunId": 1,
                "sourceCompletedAt": stamp, "notificationsGenerated": True, "items": items[:limit]}

    def shop(self) -> dict:
        """Build ``GET /api/shop`` from a seeded handful of Epic catalogue songs.

        Returns:
            A shop feed referencing only catalogue songs.
        """
        picks = sorted(self.songs, key=lambda s: _rng("shop", s["songId"]).random())[:8]
        songs = [{
            "songId": s["songId"], "title": s["title"], "artist": s["artist"], "year": s.get("year"),
            "albumArt": s.get("albumArt"),
            "shopUrl": f"https://www.fortnite.com/item-shop/jam-tracks/{s['songId']}",
            "leavingTomorrow": index == 5, "isNew": index < 3,
        } for index, s in enumerate(picks)]
        return {"count": len(songs), "lastUpdated": f"{self.as_of.isoformat()}T00:00:00Z",
                "newSongs": [s["songId"] for s in songs if s["isNew"]], "songs": songs}

    # endregion

    # region Verification

    def payloads(self) -> Iterator[Any]:
        """Yield every song-referencing payload the showcase can serve.

        Returns:
            An iterator of JSON-ready objects for dangling-reference scanning.
        """
        yield self.songs_payload
        yield self.profile(PLAYER_ID)
        yield self.shop()
        yield self.history(None, None)
        yield self.notifications(200)
        yield self.rivals_all()
        for rival_id in self.rivals:
            yield self.profile(rival_id)
            for spec in INSTRUMENT_SPECS:
                yield self.rival_detail(spec.key, rival_id, "closest", 0, 0)
            yield self.rival_detail("0f", rival_id, "closest", 0, 0)
            yield self.rival_detail(PRO_DRUMS_TOKEN, rival_id, "closest", 0, 0)
        for spec in INSTRUMENT_SPECS:
            yield self.leaderboard_rivals(spec.key, "totalscore")
            for rival in (self.leaderboard_rivals(spec.key, "totalscore") or {}).get("above", []):
                yield self.leaderboard_rival_detail(spec.key, "totalscore", rival["accountId"], "closest")
            for song in self.songs:
                yield self.leaderboard(song["songId"], spec.key, 100, 0)

    def dangling_references(self) -> list[str]:
        """Find song ids referenced by any payload that are absent from the catalogue.

        Returns:
            Sorted ids not present in the served ``/api/songs`` payload.
        """
        known = {song["songId"] for song in self.songs_payload["songs"]}
        found: set[str] = set()

        def walk(node: Any) -> None:
            """Collect song-id values from keys that carry them."""
            if isinstance(node, dict):
                for name, value in node.items():
                    if name in ("songId", "si") and isinstance(value, str):
                        found.add(value)
                    elif name == "newSongs" and isinstance(value, list):
                        found.update(v for v in value if isinstance(v, str))
                    elif name == "songs" and isinstance(value, list) and all(isinstance(v, str) for v in value):
                        found.update(value)
                    else:
                        walk(value)
            elif isinstance(node, list):
                for value in node:
                    walk(value)

        for payload in self.payloads():
            walk(payload)
        return sorted(found - known)

    def summary(self) -> dict:
        """Summarise the overlay for the ``check`` command.

        Returns:
            Counts plus any dangling song references.
        """
        scores = list(self.player_scores.values())
        dangling = self.dangling_references()
        return {
            "ok": not dangling, "songs": len(self.songs), "currentSeason": self.current_season,
            "players": 1 + len(self.rivals), "selectedPlayer": f"{PLAYER_ID}/{PLAYER_NAME}",
            "rivals": [rival.name for rival in RIVALS], "scores": len(scores),
            "scoresByInstrument": {s.key: sum(1 for k in self.player_scores if k[1] == s.key)
                                   for s in INSTRUMENT_SPECS},
            "fullComboRate": round(sum(1 for s in scores if s["fc"]) / max(len(scores), 1), 3),
            "goldStarRate": round(sum(1 for s in scores if s["st"] == 6) / max(len(scores), 1), 3),
            "leadCoverage": round(
                sum(1 for k in self.player_scores if k[1] == "Solo_Guitar")
                / max(self.charted_counts["Solo_Guitar"], 1), 3),
            "playerRanks": {s.key: s.ranks[0] for s in INSTRUMENT_SPECS},
            "shopSongs": self.shop()["count"], "danglingSongReferences": dangling,
        }

    # endregion


# endregion

# region HTTP service

SCOPE = r"[A-Za-z0-9_]+"
ROUTES = {
    "songs": re.compile(r"^/api/songs$"),
    "shop": re.compile(r"^/api/shop$"),
    "player": re.compile(rf"^/api/player/({ACCOUNT_ID})$"),
    "history": re.compile(rf"^/api/player/({ACCOUNT_ID})/history$"),
    "notifications": re.compile(rf"^/api/player/({ACCOUNT_ID})/notifications$"),
    "bands": re.compile(rf"^/api/player/({ACCOUNT_ID})/bands$"),
    "rivals_all": re.compile(rf"^/api/player/({ACCOUNT_ID})/rivals/all$"),
    "rivals_detail": re.compile(rf"^/api/player/({ACCOUNT_ID})/rivals/({SCOPE})/({ACCOUNT_ID})$"),
    "rivals_list": re.compile(rf"^/api/player/({ACCOUNT_ID})/rivals/({SCOPE})$"),
    "lb_rivals_detail": re.compile(
        rf"^/api/player/({ACCOUNT_ID})/leaderboard-rivals/({SCOPE})/({ACCOUNT_ID})$"),
    "lb_rivals_list": re.compile(rf"^/api/player/({ACCOUNT_ID})/leaderboard-rivals/({SCOPE})$"),
    "band_rankings": re.compile(r"^/api/rankings/bands/([A-Za-z_]+)$"),
    "rank_history": re.compile(rf"^/api/rankings/([A-Za-z_]+)/({ACCOUNT_ID})/history$"),
    "player_ranking": re.compile(rf"^/api/rankings/([A-Za-z_]+)/({ACCOUNT_ID})$"),
    "rankings": re.compile(r"^/api/rankings/([A-Za-z_]+)$"),
    "leaderboard": re.compile(rf"^/api/leaderboard/({ACCOUNT_ID})/([A-Za-z_]+)$"),
}
PASSTHROUGH = frozenset({
    "/__fixture__/health", "/api/publication", "/api/features", "/api/service-info", "/api/version",
})


class ShowcaseServer(mock_service.FixtureServer):
    """The mock fixture server carrying the showcase overlay."""

    def __init__(self, address: tuple[str, int], handler: type, showcase: Showcase, **options: Any) -> None:
        """Create the loopback listener.

        Args:
            address: Loopback host and port.
            handler: Request handler class (``ShowcaseHandler``).
            showcase: Overlay to serve.
            options: Forwarded to ``mock_service.FixtureServer``.
        """
        super().__init__(address, handler, **options)
        self.showcase = showcase


class ShowcaseHandler(mock_service.FixtureHandler):
    """Serve showcase routes and defer only the publication/service metadata routes to the mock."""

    @property
    def overlay(self) -> Showcase:
        """Return the overlay attached to the running server."""
        return self.server.showcase  # type: ignore[attr-defined]

    def _pin_ok(self) -> bool:
        """Reject a request pinned to a different publication with the mock's 409.

        Returns:
            True when the request may proceed.
        """
        pin = self.headers.get("X-FST-Publication-Id")
        if pin is not None and pin != str(self.fixture.publication_id):
            self._json(409, {"status": "publication_changed"})
            return False
        return True

    def _reply(self, payload: dict | None, *, etag: str | None = None, missing: str = "not_found") -> None:
        """Send a pinned 200, a conditional 304 or a 404 for an absent payload.

        Args:
            payload: JSON body, or None for 404.
            etag: Optional entity tag enabling ``If-None-Match`` handling.
            missing: 404 status string.
        """
        if payload is None:
            self._json(404, {"status": missing})
        elif etag and self.headers.get("If-None-Match") == etag:
            self._json(304, None, etag=etag)
        else:
            self._json(200, payload, etag=etag)

    def _int(self, query: dict, name: str, default: int, low: int, high: int) -> int | None:
        """Parse one bounded integer query parameter, replying 400 when invalid.

        Args:
            query: Parsed query string.
            name: Parameter name.
            default: Value when absent.
            low: Inclusive minimum.
            high: Inclusive maximum.

        Returns:
            The value, or None after a 400 response was sent.
        """
        values = query.get(name, [str(default)])
        try:
            value = int(values[0])
        except ValueError:
            value = low - 1
        if len(values) != 1 or not low <= value <= high:
            self._json(400, {"status": f"invalid_{name}"})
            return None
        return value

    def do_GET(self) -> None:
        """Serve showcase reads; refuse API keys, selected-profile headers and unknown routes."""
        parsed = urlsplit(self.path)
        path, query = parsed.path, parse_qs(parsed.query, keep_blank_values=True)
        if self.headers.get("X-API-Key") is not None or any(
            name.lower().startswith("x-fst-selected-") for name in self.headers
        ):
            self._json(400, {"status": "forbidden_client_header"})
            return
        if path in PASSTHROUGH or path.startswith("/__fixture__/art/"):
            super().do_GET()
            return
        for name, pattern in ROUTES.items():
            match = pattern.fullmatch(path)
            if match is not None:
                getattr(self, f"_get_{name}")(query, *match.groups())
                return
        self._json(404, {"status": "not_found"})

    def _get_songs(self, query: dict) -> None:
        """Serve the Epic-only catalogue under the showcase ETag."""
        if query.get("scenario", ["demo"]) != ["demo"] or set(query) - {"scenario"}:
            self._json(400, {"status": "unknown_fixture_scenario"})
        elif self._pin_ok():
            self._reply(self.overlay.songs_payload, etag=SHOWCASE_ETAG)

    def _get_shop(self, query: dict) -> None:
        """Serve the seeded Epic-only shop feed."""
        if query.get("scenario", ["demo"]) != ["demo"] or set(query) - {"scenario"}:
            self._json(400, {"status": "unknown_fixture_scenario"})
        elif self._pin_ok():
            self._reply(self.overlay.shop(), etag=SHOWCASE_SHOP_ETAG)

    def _get_player(self, query: dict, account_id: str) -> None:
        """Serve a player profile."""
        if query:
            self._json(400, {"status": "invalid_player_query"})
        elif self._pin_ok():
            self._reply(self.overlay.profile(account_id))

    def _get_history(self, query: dict, account_id: str) -> None:
        """Serve score-change history (404 for any account other than the selected player)."""
        if set(query) - {"songId", "instrument"}:
            self._json(400, {"status": "invalid_player_history_query"})
        elif self._pin_ok():
            body = self.overlay.history(
                query.get("songId", [None])[0], query.get("instrument", [None])[0],
            ) if account_id == PLAYER_ID else None
            self._reply(body, missing="unknown_history_player")

    def _get_notifications(self, query: dict, account_id: str) -> None:
        """Serve generated notifications (empty envelope for other accounts)."""
        if set(query) - {"limit"}:
            self._json(400, {"status": "invalid_notifications_query"})
            return
        limit = self._int(query, "limit", 50, 1, 200)
        if limit is None or not self._pin_ok():
            return
        body = self.overlay.notifications(limit) if account_id == PLAYER_ID else {
            "generatedAt": f"{self.overlay.as_of.isoformat()}T00:00:00Z", "expiresAfterHours": 72,
            "sourceRunId": None, "sourceCompletedAt": None, "notificationsGenerated": False, "items": [],
        }
        self._reply(body)

    def _get_bands(self, query: dict, account_id: str) -> None:
        """Serve a valid empty band list."""
        if set(query) - {"group", "page", "pageSize"}:
            self._json(400, {"status": "invalid_player_bands_query"})
        else:
            self._reply({"accountId": account_id, "totalCount": 0, "entries": []})

    def _get_band_rankings(self, query: dict, band_type: str) -> None:
        """Serve a valid empty band ranking."""
        if band_type not in mock_service.BAND_TYPES:
            self._json(404, {"status": "unknown_band_type"})
        elif self._pin_ok():
            self._reply({
                "bandType": band_type, "rankBy": query.get("rankBy", ["totalscore"])[0],
                "page": 1, "pageSize": 10, "totalTeams": 0, "entries": [],
            })

    def _get_rivals_all(self, query: dict, account_id: str) -> None:
        """Serve the Suggestions all-combo rivals feed."""
        if query:
            self._json(400, {"status": "invalid_rivals_query"})
        elif self._pin_ok():
            self._reply(self.overlay.rivals_all() if account_id == PLAYER_ID else None)

    def _get_rivals_list(self, query: dict, account_id: str, token: str) -> None:
        """Serve one rivals scope list."""
        if query:
            self._json(400, {"status": "invalid_rivals_query"})
        elif self._pin_ok():
            self._reply(self.overlay.rivals_list(token) if account_id == PLAYER_ID else None)

    def _get_rivals_detail(self, query: dict, account_id: str, token: str, rival_id: str) -> None:
        """Serve one rival's shared-song comparison."""
        sort = query.get("sort", ["closest"])
        if set(query) - {"sort", "limit", "offset"} or len(sort) != 1 or sort[0] not in SORTS:
            self._json(400, {"status": "invalid_rivals_query"})
            return
        limit = self._int(query, "limit", 0, 0, 10_000)
        offset = self._int(query, "offset", 0, 0, 10_000)
        if limit is None or offset is None or not self._pin_ok():
            return
        body = self.overlay.rival_detail(token, rival_id, sort[0], limit, offset) \
            if account_id == PLAYER_ID else None
        self._reply(body)

    def _get_lb_rivals_list(self, query: dict, account_id: str, instrument: str) -> None:
        """Serve leaderboard-neighbour rivals."""
        rank_by = query.get("rankBy", ["totalscore"])
        if set(query) - {"rankBy"} or len(rank_by) != 1:
            self._json(400, {"status": "invalid_rivals_query"})
        elif self._pin_ok():
            body = self.overlay.leaderboard_rivals(instrument, rank_by[0]) if account_id == PLAYER_ID else None
            self._reply(body)

    def _get_lb_rivals_detail(self, query: dict, account_id: str, instrument: str, rival_id: str) -> None:
        """Serve one leaderboard rival's comparison."""
        rank_by, sort = query.get("rankBy", ["totalscore"]), query.get("sort", ["closest"])
        if (set(query) - {"rankBy", "sort"} or len(rank_by) != 1 or len(sort) != 1
                or sort[0] not in SORTS):
            self._json(400, {"status": "invalid_rivals_query"})
        elif self._pin_ok():
            body = self.overlay.leaderboard_rival_detail(instrument, rank_by[0], rival_id, sort[0]) \
                if account_id == PLAYER_ID else None
            self._reply(body)

    def _get_rankings(self, query: dict, instrument: str) -> None:
        """Serve one account rankings page."""
        if instrument not in mock_service.INSTRUMENTS:
            self._json(404, {"status": "unknown_instrument"})
            return
        rank_by = query.get("rankBy", ["totalscore"])[0]
        page, size = self._int(query, "page", 1, 1, 100_000), self._int(query, "pageSize", 10, 1, 200)
        if page is None or size is None:
            return
        if rank_by not in RANK_METRICS:
            self._json(400, {"status": "invalid_rank_by"})
        elif self._pin_ok():
            self._reply(self.overlay.rankings_page(instrument, rank_by, page, size))

    def _get_player_ranking(self, query: dict, instrument: str, account_id: str) -> None:
        """Serve the selected player's ranking entry (404 when unranked)."""
        if instrument not in mock_service.INSTRUMENTS:
            self._json(404, {"status": "unknown_instrument"})
        elif self._pin_ok():
            body = self.overlay.player_ranking(instrument) if account_id == PLAYER_ID else None
            self._reply(body, missing="account_not_ranked")

    def _get_rank_history(self, query: dict, instrument: str, account_id: str) -> None:
        """Serve the selected player's improving rank history."""
        if instrument not in mock_service.INSTRUMENTS:
            self._json(404, {"error": f"Unknown instrument: {instrument}"})
            return
        if set(query) - {"days", "leeway"}:
            self._json(400, {"status": "invalid_rank_history_query"})
            return
        days = self._int(query, "days", 30, 1, 3650)
        if days is None or not self._pin_ok():
            return
        if account_id == PLAYER_ID:
            self._reply(self.overlay.rank_history(instrument, days))
        else:
            self._reply({"instrument": instrument, "accountId": account_id, "history": []})

    def _get_leaderboard(self, query: dict, song_id: str, instrument: str) -> None:
        """Serve one fictional song leaderboard."""
        if set(query) - {"top", "offset", "leeway"}:
            self._json(400, {"status": "invalid_query"})
            return
        top, offset = self._int(query, "top", 25, 1, 100), self._int(query, "offset", 0, 0, 1_000_000)
        if top is None or offset is None:
            return
        try:
            leeway = float(query["leeway"][0]) if "leeway" in query else 0.0
        except ValueError:
            leeway = math.inf
        if not math.isfinite(leeway) or not -5 <= leeway <= 5:
            self._json(400, {"status": "invalid_pagination"})
        elif self._pin_ok():
            self._reply(self.overlay.leaderboard(song_id, instrument, top, offset))


def build_server(catalogue: dict, port: int = 0, *, as_of: date = AS_OF) -> ShowcaseServer:
    """Create (but do not start) a loopback showcase server.

    Args:
        catalogue: Public catalogue envelope.
        port: Loopback port; 0 asks the OS for a free one.
        as_of: Fixed date for time-based fields.

    Returns:
        A bound ``ShowcaseServer``.
    """
    return ShowcaseServer(("127.0.0.1", port), ShowcaseHandler, Showcase(catalogue, as_of=as_of))


# endregion

# region CLI


#: App Store capture plan: (file stem, ``FST_DEBUG_TAB``, ``FST_DEBUG_ROUTE``). Rivals has no
#: iPhone tab, so it is pushed as a route over Compete.
@dataclass(frozen=True)
class Shot:
    """One App Store capture.

    Attributes:
        stem: Output file stem.
        tab: ``FST_DEBUG_TAB`` at launch.
        route: Optional ``FST_DEBUG_ROUTE``.
        launch_args: Extra app launch arguments (UserDefaults argument domain;
            never persisted to the app's preferences).
        steps: ``ios_sim.py drive`` steps run before capturing; when present the
            page is captured by the UI-test driver instead of ``simctl``.
        env: Extra ``KEY=VALUE`` app launch environment for this page only.
    """

    stem: str
    tab: str
    route: str | None = None
    launch_args: tuple[str, ...] = ()
    steps: tuple[str, ...] = ()
    env: tuple[str, ...] = ()


# Hide the Pro/Karaoke charts so Songs rows show only the tap instruments
# (Lead, Bass, Drums, Tap Vocals); keys are SettingsScreen's @AppStorage names.
TAP_ONLY_ARGS = tuple(
    arg for name in ("ProLead", "ProBass", "Karaoke", "ProCymbals", "ProDrums")
    for arg in (f"-fst.settings.show{name}", "<false/>")
)

SHOTS = (
    Shot("01-songs", "songs", launch_args=TAP_ONLY_ARGS),
    Shot("02-suggestions", "suggestions"),
    # Jump past the profile header card via Quick Links (scrolls with a .top anchor).
    Shot("03-statistics", "statistics", env=("FST_DEBUG_HIDE_PROFILE_HEADER=1",), steps=(
        "waitFor:fst.player.overview", "tap:fst.quick-links.open",
        "tap:fst.quick-links.item.global", "wait:{wait}",
    )),
    # Drag (momentum-free) so the Bass header sits under the collapsed nav bar
    # (Overview button and Lead card off-screen); load first so layout is final.
    Shot("04-compete", "compete", steps=(
        "waitFor:fst.compete.leaderboard-card.Solo_Guitar", "wait:{wait}",
        "drag:0.5,0.8,0.5,0.26", "wait:2",
    )),
    Shot("05-rivals", "compete", "rivals"),
)


def shot_commands(port: int, out_dir: Path, device: str, wait: float) -> list[list[str]]:
    """Build one ``ios_sim.py`` argv per App Store page.

    Pages without steps use ``shot`` (``simctl`` launch and framebuffer capture);
    pages with steps use ``drive`` and end with a driver ``shot:`` step.

    Args:
        port: Loopback port of the running showcase server.
        out_dir: Directory receiving ``<stem>.png`` files.
        device: ``ios_sim.py`` device alias or UDID (``promax`` = 6.9-inch).
        wait: Seconds to let each page load before capturing.

    Returns:
        Argument vectors, in ``SHOTS`` order.
    """
    tool = str(Path(__file__).resolve().parent / "ios_sim.py")
    env = ["--env", f"FST_API_BASE_URL=http://127.0.0.1:{port}",
           "--env", f"FST_DEBUG_PROFILE={PLAYER_ID}:{PLAYER_NAME}"]
    commands = []
    for shot in SHOTS:
        out = str(out_dir / f"{shot.stem}.png")
        route = ["--route", shot.route] if shot.route else []
        page_env = [arg for pair in shot.env for arg in ("--env", pair)]
        if shot.steps:
            steps = [step.format(wait=wait) for step in shot.steps] + [f"shot:{out}"]
            argv = [sys.executable, tool, "drive", "--device", device, "--tab", shot.tab, *route,
                    "--clean-status-bar", "--animate", *env, *page_env, "--steps", "; ".join(steps)]
        else:
            argv = [sys.executable, tool, "shot", "--device", device, "--tab", shot.tab, *route,
                    "--wait", str(wait), "--clean-status-bar", *env, *page_env, "--out", out]
            argv += [f"--launch-arg={arg}" for arg in shot.launch_args]
        commands.append(argv)
    return commands


def shoot(catalogue: dict, out_dir: Path, device: str, wait: float, run=subprocess.run) -> int:
    """Serve the overlay on a free loopback port and capture every ``SHOTS`` page.

    Args:
        catalogue: Public catalogue envelope.
        out_dir: Output directory (created if missing).
        device: ``ios_sim.py`` device alias or UDID.
        wait: Per-page load wait in seconds.
        run: Subprocess runner (injected by tests).

    Returns:
        0 when every capture succeeded, else the first failing exit code.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    server = build_server(catalogue, 0)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        for argv in shot_commands(server.server_port, out_dir, device, wait):
            code = run(argv).returncode
            if code:
                return code
    finally:
        server.shutdown()
        server.server_close()
    return 0


def main(argv: list[str] | None = None) -> int:
    """Run the ``serve``, ``fetch`` or ``check`` command.

    Args:
        argv: Argument list, defaulting to ``sys.argv[1:]``.

    Returns:
        Process exit status; ``check`` is nonzero when song references dangle.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    serve = sub.add_parser("serve", help="run the loopback showcase fixture service")
    serve.add_argument("--port", type=int, default=18795)
    fetch = sub.add_parser("fetch", help="one keyless GET of the public song catalogue")
    fetch.add_argument("--out", default=str(DEFAULT_CATALOGUE))
    check = sub.add_parser("check", help="build the overlay and print a JSON summary")
    shoot_cmd = sub.add_parser("shoot", help="capture the App Store pages via ios_sim.py (macOS)")
    shoot_cmd.add_argument("--out-dir", required=True)
    shoot_cmd.add_argument("--device", default="promax", help="ios_sim.py alias; promax is the 6.9-inch size")
    shoot_cmd.add_argument("--wait", type=float, default=12.0)
    for command in (serve, check, shoot_cmd):
        command.add_argument("--catalogue", default=str(DEFAULT_CATALOGUE))
        command.add_argument("--as-of", default=AS_OF.isoformat(), help="fixed date for history/shop fields")
    args = parser.parse_args(argv)
    if args.command == "fetch":
        print(f"saved {fetch_catalogue(args.out)}")
        return 0
    as_of = date.fromisoformat(args.as_of)
    if args.command == "check":
        summary = Showcase(load_catalogue(args.catalogue), as_of=as_of).summary()
        print(json.dumps(summary, indent=2))
        return 0 if summary["ok"] else 1
    if args.command == "shoot":
        return shoot(load_catalogue(args.catalogue), Path(args.out_dir).expanduser(), args.device, args.wait)
    if not 0 <= args.port <= 65535:
        parser.error("port must be between 0 (OS-assigned) and 65535")
    with build_server(load_catalogue(args.catalogue), args.port, as_of=as_of) as server:
        print(f"Local test fixture service on 127.0.0.1:{server.server_port}", flush=True)
        server.serve_forever()
    return 0


# endregion

if __name__ == "__main__":
    sys.exit(main())
