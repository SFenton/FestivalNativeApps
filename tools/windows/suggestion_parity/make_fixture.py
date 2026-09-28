"""Generate the synthetic Suggestions parity fixture (catalogue, scores, rivals, scenarios).

The output is committed at windows/Festival.Core.Tests/Fixtures/suggestions-parity.json; rerun
only to change the fixture, then regenerate the expected outputs with run_parity.py.
"""

import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "windows" / "Festival.Core.Tests" / "Fixtures" / "suggestions-parity.json"
INSTRUMENTS = [
    "Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals", "Solo_PeripheralGuitar",
    "Solo_PeripheralBass", "Solo_PeripheralVocals", "Solo_PeripheralCymbals", "Solo_PeripheralDrums",
]
DIFFICULTY_KEYS = ["guitar", "bass", "drums", "vocals", "proGuitar", "proBass", "proVocals", "proCymbals", "proDrums"]


def main() -> None:
    """Write a deterministic fixture covering every suggestion family."""
    rng = random.Random(20260928)
    artists = [f"Artist {chr(65 + i)}" for i in range(18)] + ["  Artist A  ", "X"]
    titles = [f"Track {i}" for i in range(140)]
    for i in range(0, 20, 4):
        titles[i + 1] = titles[i]  # same-name pairs
    songs = []
    for i in range(140):
        difficulty = {k: rng.choice([0, 1, 2, 3, 4, 5, 6, 99] if k in ("proVocals", "proCymbals") else [0, 1, 2, 3, 4, 5, 6])
                      for k in DIFFICULTY_KEYS}
        song = {
            "songId": f"s{i:03d}",
            "title": titles[i],
            "artist": artists[i % len(artists)] if i % 7 else artists[(i // 7) % 5],
            "difficulty": difficulty,
        }
        year = rng.choice([None, 1968, 1975, 1984, 1989, 1993, 1999, 2004, 2008, 2012, 2019, 2023, 2100])
        if year is not None:
            song["year"] = year
        if rng.random() < 0.7:
            song["maxScores"] = {ins: rng.randint(90_000, 400_000) for ins in INSTRUMENTS if ins != "Solo_PeripheralVocals"}
        songs.append(song)

    scores = []
    for song in songs[:110]:
        for ins in INSTRUMENTS:
            if rng.random() < 0.45:
                continue
            stars = rng.choice([0, 1, 2, 3, 4, 5, 5, 6, 6, 6])
            accuracy = rng.choice([700_000, 880_000, 905_000, 925_000, 955_000, 990_000, 1_000_000])
            row = {"songId": song["songId"], "instrument": ins, "stars": stars, "accuracy": accuracy,
                   "fullCombo": rng.random() < 0.3, "season": rng.randint(1, 12)}
            max_score = song.get("maxScores", {}).get(ins)
            row["score"] = max_score - rng.choice([1_000, 4_999, 5_000, 7_500, 12_000, 15_001, 40_000]) if max_score else rng.randint(1, 300_000)
            if rng.random() < 0.85:
                total = rng.choice([100, 1_000, 5_000, 20_000])
                row["rank"] = max(1, int(total * rng.choice([0.004, 0.012, 0.025, 0.045, 0.07, 0.13, 0.18, 0.27, 0.38, 0.47, 0.6, 0.95])))
                row["totalEntries"] = total
            if rng.random() < 0.1:
                del row["stars"]
            scores.append(row)

    rival_songs = [s["songId"] for s in songs[:60]] + ["missing-song"]
    combos = []
    for combo in ["01", "02", "05"]:
        groups = {}
        for direction in ("above", "below"):
            entries = []
            for r in range(7):
                account = f"rival-{direction}-{r}" if combo != "02" or r > 1 else f"rival-shared-{r}"
                samples = []
                for _ in range(rng.randint(2, 14)):
                    user_rank = rng.randint(1, 400)
                    samples.append({"s": rng.randrange(len(rival_songs)), "i": rng.choice(INSTRUMENTS[:5] + ["Bogus"]),
                                    "ur": user_rank, "rr": max(1, user_rank + rng.choice([-60, -25, -9, -3, 2, 5, 12, 35, 70])),
                                    "us": rng.randint(1, 300_000), "rs": rng.randint(1, 300_000)})
                entry = {"accountId": account, "displayName": None if r == 6 else f"Rival {direction[0].upper()}{r}",
                         "direction": direction, "sharedSongCount": len(samples), "aheadCount": rng.randint(0, 9),
                         "behindCount": rng.randint(0, 9), "rivalScore": round(rng.random() * 10, 3), "samples": samples}
                entries.append(entry)
            groups[direction] = entries
        combos.append({"combo": combo, "above": groups["above"], "below": groups["below"]})

    scenarios = [
        {"name": "default-rivals", "seed": 1, "currentSeason": 12, "rivals": "early", "pages": [10] * 40, "resetPages": [10, 10]},
        {"name": "deterministic-no-rivals", "seed": 42, "disableSkipping": True, "fixedDisplayCount": 3, "currentSeason": 9,
         "rivals": "none", "pages": [7] * 50},
        {"name": "late-rivals", "seed": 7, "currentSeason": 12, "rivals": "late", "pages": [5] * 60},
        {"name": "no-season", "seed": 2024, "currentSeason": 0, "rivals": "early", "pages": [12] * 30, "resetPages": [12]},
        {"name": "repeat-mixes", "seed": 99, "currentSeason": 12, "rivals": "early", "pages": [25] * 8,
         "resetPages": [25] * 8, "resetCycles": 3},
        {"name": "max-seed", "seed": 4294967295, "currentSeason": 12, "rivals": "early", "fixedDisplayCount": 6, "pages": [9] * 40},
    ]
    fixture = {"songs": songs, "scores": scores,
               "rivalsAll": {"accountId": "player-1", "songs": rival_songs, "combos": combos},
               "rngSeeds": [0, 1, 42, 4294967295], "scenarios": scenarios}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(fixture, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({len(songs)} songs, {len(scores)} scores)")


if __name__ == "__main__":
    main()
