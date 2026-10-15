"""Generate the named-rival Suggestions parity fixture (Suggestions rule R1, issue #656).

Two rivals, "Alpha Rival" and "Beta Rival", are each the only (so the closest) rival on
alternating Lead songs of three song groups, one per named-rival family:

- ``cp*``: percentile push (4 stars, 80%, rank 51+ of 1,000), rival ahead -> "Climb Past {rival}".
- ``gs*``: star gains (4 stars, 70%, unranked), rival ahead -> "Gain Stars & Beat {rival}".
- ``fc*``: near FC (6 stars, 93%, no FC), rival behind -> "FC These to Beat {rival}!".

Every other chart is an inert six-star full combo, and all songs share one artist so
``variety_pack`` cannot claim them. The web and the pre-R1 generators name the first selected
row's rival and keep every row's own, so their cards mix Alpha and Beta here; R1 generators
list one rival per card. The output has the same shape as ``suggestions-parity.json`` so
``main.swift`` (and the Windows/Android parity tests) can run it unchanged.

Usage: python3 tools/windows/suggestion_parity/make_named_rival_fixture.py
Then regenerate its expected output with ``run_parity.py``.
"""

import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "fixtures" / "named-rival-parity.json"
INSTRUMENTS = [
    "Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals", "Solo_PeripheralGuitar",
    "Solo_PeripheralBass", "Solo_PeripheralVocals", "Solo_PeripheralCymbals", "Solo_PeripheralDrums",
]
DIFFICULTY_KEYS = ["guitar", "bass", "drums", "vocals", "proGuitar", "proBass", "proVocals", "proCymbals", "proDrums"]
LEAD = "Solo_Guitar"
# (prefix, count, stars, accuracy, rank start or None, sample user rank, sample rival rank)
GROUPS = [
    ("cp", 30, 4, 800_000, 51, 10, 51),
    ("gs", 16, 4, 700_000, None, 2, 10),
    ("fc", 16, 6, 930_000, None, 5, 2),
]


def main() -> None:
    """Write the deterministic two-rival fixture."""
    songs, scores, samples = [], [], {0: [], 1: []}
    for prefix, count, stars, accuracy, rank_start, user_rank, rival_rank in GROUPS:
        for offset in range(count):
            song_id = f"{prefix}{offset}"
            index = len(songs)
            songs.append({"songId": song_id, "title": f"Signal {song_id}", "artist": "Signal Artist",
                          "difficulty": {k: 0 for k in DIFFICULTY_KEYS}})
            lead = {"songId": song_id, "instrument": LEAD, "score": 1_000_000, "stars": stars,
                    "accuracy": accuracy, "fullCombo": False}
            if rank_start is not None:
                lead["rank"] = rank_start + offset
                lead["totalEntries"] = 1_000
            scores.append(lead)
            for other in INSTRUMENTS[1:]:
                scores.append({"songId": song_id, "instrument": other, "score": 1_000_000, "stars": 6,
                               "accuracy": 1_000_000, "fullCombo": True})
            samples[offset % 2].append({"s": index, "i": LEAD, "ur": user_rank, "rr": rival_rank})

    def rival(account: str, name: str, parity: int) -> dict:
        return {"accountId": account, "displayName": name, "direction": "above",
                "sharedSongCount": len(samples[parity]), "aheadCount": 5, "behindCount": 5,
                "rivalScore": 100, "samples": samples[parity]}

    scenarios = [
        {"name": f"two-rivals-seed-{seed}", "seed": seed, "disableSkipping": True, "fixedDisplayCount": 4,
         "currentSeason": 0, "rivals": "early", "pages": [50, 50]}
        for seed in range(1, 13)
    ] + [
        {"name": "two-rivals-skipping", "seed": 2026, "currentSeason": 0, "rivals": "early",
         "pages": [10] * 12, "resetPages": [10, 10], "resetCycles": 2},
        {"name": "two-rivals-late", "seed": 656, "disableSkipping": True, "fixedDisplayCount": 6,
         "currentSeason": 0, "rivals": "late", "pages": [5] * 16},
    ]
    fixture = {"songs": songs, "scores": scores,
               "rivalsAll": {"accountId": "player-1", "songs": [s["songId"] for s in songs],
                             "combos": [{"combo": "01", "above": [rival("riv-a", "Alpha Rival", 0),
                                                                  rival("riv-b", "Beta Rival", 1)],
                                         "below": []}]},
               "rngSeeds": [1], "scenarios": scenarios}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(fixture, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({len(songs)} songs, {len(scores)} scores, {len(scenarios)} scenarios)")


if __name__ == "__main__":
    main()
