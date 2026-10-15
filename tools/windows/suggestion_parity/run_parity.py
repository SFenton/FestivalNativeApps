"""Produce and check the Apple reference outputs for the Suggestions parity tests.

Compiles the *unmodified* Apple suggestion sources (SuggestionGenerator/Models/RivalData,
RivalsAll, ScoreFormatting and the Instrument/Song part of SongCatalog) together with
Shim.swift + main.swift and runs them over two fixtures:

- the shared fixture windows/Festival.Core.Tests/Fixtures/suggestions-parity.json, whose
  expected output (suggestions-parity.expected.json beside it) the Windows and Android
  parity tests read;
- the named-rival fixture fixtures/named-rival-parity.json (two rivals on alternating songs,
  Suggestions rule R1, #656; ``make_named_rival_fixture.py``), expected output beside it.

Every output must also satisfy rule R1: a card that names one rival ("Climb Past {rival}",
"Gain Stars & Beat {rival}", "FC These to Beat {rival}!") lists only that rival.

While a cross-platform rule has landed on Apple but not yet in the Windows/Android ports,
``pending-ports.json`` pins the Apple output's SHA-256 for the shared fixture; the committed
shared baseline stays at the pre-rule output so those ports' tests keep passing. ``--check``
accepts that mismatch only when the Apple output still hashes to the pinned value (any other
Apple drift fails). The Apple lane records such a rule with ``--pin`` (writes the named-rival
expected file and the pending record, never the shared baseline); the lane that ports the
rule runs this script with no flag: it rewrites both baselines and deletes the pending record.

Works with the Swift toolchain on Windows (``winget install Swift.Toolchain``) or on the Mac.

Usage: python tools/windows/suggestion_parity/run_parity.py [--check [--strict] | --pin RULE --awaiting LANES]
  --check   compare against the committed expected files instead of overwriting them.
  --strict  with --check, require the shared baseline to match exactly (ignore pending ports).
  --pin     keep the shared baseline; write the named-rival expected file and pin the Apple
            shared output in pending-ports.json for RULE, awaiting LANES (comma-separated).
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CORE = ROOT / "apple" / "Sources" / "FestivalCore"
FIXTURES = ROOT / "windows" / "Festival.Core.Tests" / "Fixtures"
SHARED = FIXTURES / "suggestions-parity.json"
SHARED_EXPECTED = FIXTURES / "suggestions-parity.expected.json"
NAMED = HERE / "fixtures" / "named-rival-parity.json"
NAMED_EXPECTED = HERE / "fixtures" / "named-rival-parity.expected.json"
PENDING = HERE / "pending-ports.json"
WHOLE_FILES = ["SuggestionGenerator.swift", "SuggestionModels.swift", "SuggestionRivalData.swift",
               "RivalsAll.swift", "ScoreFormatting.swift"]
# Suggestions rule R1 (#656): category key -> title for its named rival.
NAMED_RIVAL_TITLES = {
    "song_rival_pct_push": "Climb Past {}",
    "song_rival_star_gains": "Gain Stars & Beat {}",
    "song_rival_near_fc": "FC These to Beat {}!",
}


def swift_environment() -> dict[str, str]:
    """Return an environment where swiftc resolves, adding the per-user Windows install if needed."""
    env = dict(os.environ)
    if shutil.which("swiftc") or os.name != "nt":
        return env
    base = Path(os.environ["LOCALAPPDATA"]) / "Programs" / "Swift"
    toolchain = next((base / "Toolchains").glob("*"))
    runtime = next((base / "Runtimes").glob("*"))
    platform = next((base / "Platforms").glob("*"))
    env["PATH"] = os.pathsep.join([str(toolchain / "usr" / "bin"), str(runtime / "usr" / "bin"), env["PATH"]])
    env.setdefault("SDKROOT", str(platform / "Windows.platform" / "Developer" / "SDKs" / "Windows.sdk"))
    return env


def song_catalog_prefix() -> str:
    """Return SongCatalog.swift up to (not including) the SongsResponse envelope, which needs the API layer."""
    text = (CORE / "SongCatalog.swift").read_text(encoding="utf-8")
    return text[: text.index("/// Catalog wire envelope")]


def canonical(produced: dict) -> str:
    """Return the committed text form of an output (also what the pending SHA-256 covers)."""
    return json.dumps(produced, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n"


def sha256(produced: dict) -> str:
    """Return the SHA-256 of an output's canonical text."""
    return hashlib.sha256(canonical(produced).encode("utf-8")).hexdigest()


def categories(produced: dict):
    """Yield (scenario name, category) for every category on every page of every scenario."""
    for scenario in produced["scenarios"]:
        for page in scenario["pages"] + scenario["resetPages"]:
            for category in page:
                yield scenario["name"], category


def named_rival_violations(produced: dict) -> tuple[list[str], dict[str, int], set[str], int]:
    """Check rule R1 on an output.

    Returns:
        (violations, named cards per key, rival names in titles, largest named card's row count).
    """
    problems, counts, names, largest = [], {}, set(), 0
    for scenario, category in categories(produced):
        template = NAMED_RIVAL_TITLES.get(category["key"])
        if template is None:
            continue
        counts[category["key"]] = counts.get(category["key"], 0) + 1
        accounts = {song.get("rivalAccountId") for song in category["songs"]}
        rows = {song.get("rivalName") for song in category["songs"]}
        where = f"{scenario}/{category['key']} '{category['title']}'"
        if len(accounts) != 1 or None in accounts:
            problems.append(f"{where}: rows name rival accounts {sorted(map(str, accounts))}")
            continue
        name = next(iter(rows))
        if len(rows) != 1 or category["title"] != template.format(name):
            problems.append(f"{where}: rows name {sorted(map(str, rows))}")
            continue
        names.add(name)
        largest = max(largest, len(category["songs"]))
    return problems, counts, names, largest


def run_harness(fixtures: list[Path]) -> list[dict]:
    """Compile the Apple sources with the harness once and return its output for each fixture."""
    env = swift_environment()
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for name in WHOLE_FILES:
            shutil.copy(CORE / name, work / name)
        (work / "SongCatalog.swift").write_text(song_catalog_prefix(), encoding="utf-8")
        shutil.copy(HERE / "Shim.swift", work / "Shim.swift")
        shutil.copy(HERE / "main.swift", work / "main.swift")
        exe = work / ("parity.exe" if os.name == "nt" else "parity")
        sources = sorted(str(p) for p in work.glob("*.swift"))
        swiftc = shutil.which("swiftc", path=env["PATH"]) or "swiftc"
        subprocess.run([swiftc, "-O", "-module-name", "Parity", "-o", str(exe), *sources], check=True, env=env)
        return [json.loads(subprocess.run([str(exe), str(f)], check=True, capture_output=True, env=env).stdout)
                for f in fixtures]


def check_named_rival(shared: dict, named: dict) -> bool:
    """Report rule R1 on both outputs; the named-rival fixture must also exercise every family."""
    ok = True
    for label, produced in (("shared fixture", shared), ("named-rival fixture", named)):
        problems, counts, names, largest = named_rival_violations(produced)
        for problem in problems:
            print(f"R1 FAIL ({label}): {problem}")
        ok &= not problems
        print(f"R1 {'ok' if not problems else 'FAIL'} ({label}): {sum(counts.values())} named-rival cards "
              f"{dict(sorted(counts.items()))}, {len(problems)} list another rival.")
        if produced is named:
            missing = set(NAMED_RIVAL_TITLES) - set(counts)
            if missing or names != {"Alpha Rival", "Beta Rival"} or largest < 2:
                print(f"R1 FAIL (named-rival fixture): not discriminating (missing {sorted(missing)}, "
                      f"named {sorted(names)}, largest card {largest} rows).")
                ok = False
    return ok


def check_named_expected(named: dict) -> bool:
    """Compare the named-rival output with its committed expected file."""
    same = json.loads(NAMED_EXPECTED.read_text(encoding="utf-8")) == named
    print("Named-rival fixture: Apple output matches its expected file." if same
          else "Named-rival fixture: MISMATCH: regenerate and review.")
    return same


def check_shared_baseline(shared: dict, strict: bool) -> bool:
    """Compare the shared output with the Windows/Android baseline, honouring a pinned pending port."""
    baseline = json.loads(SHARED_EXPECTED.read_text(encoding="utf-8"))
    pending = None if strict or not PENDING.exists() else json.loads(PENDING.read_text(encoding="utf-8"))
    if baseline == shared:
        print("Shared fixture: Apple output matches the committed baseline.")
        if pending:
            print(f"NOTE: {PENDING.name} is stale (the baseline already includes it); delete it.")
        return True
    if pending is None:
        print("Shared fixture: MISMATCH with the committed baseline: regenerate and review.")
        return False
    digest = sha256(shared)
    if digest != pending["appleOutputSha256"]:
        print(f"Shared fixture: MISMATCH: Apple output ({digest[:12]}) differs from both the baseline and "
              f"the output pinned for the pending port ({pending['appleOutputSha256'][:12]}): "
              "an unported Apple change; review it, then repin or regenerate.")
        return False
    baseline_problems = named_rival_violations(baseline)[0]
    print(f"Shared fixture: PENDING PORT ({pending['rule']}, awaiting {', '.join(pending['awaiting'])}): "
          f"Apple output matches the pinned reference {digest[:12]}; the committed baseline predates the "
          f"rule ({len(baseline_problems)} named-rival cards there list another rival). The porting lane "
          "regenerates it with run_parity.py.")
    return True


def argument(flag: str) -> str:
    """Return the value after ``flag`` on the command line."""
    index = sys.argv.index(flag)
    if index + 1 >= len(sys.argv):
        raise SystemExit(f"{flag} needs a value")
    return sys.argv[index + 1]


def main() -> int:
    """Build and run the harness, then write, pin or check the expected outputs."""
    check = "--check" in sys.argv
    shared, named = run_harness([SHARED, NAMED])
    if "--pin" in sys.argv:
        if not check_named_rival(shared, named):
            return 1
        NAMED_EXPECTED.write_text(canonical(named), encoding="utf-8")
        record = {"rule": argument("--pin"), "awaiting": argument("--awaiting").split(","),
                  "baseline": SHARED_EXPECTED.relative_to(ROOT).as_posix(), "appleOutputSha256": sha256(shared)}
        PENDING.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {NAMED_EXPECTED} and pinned {record['appleOutputSha256'][:12]} in {PENDING.name}")
        return 0
    if check:
        results = [check_named_rival(shared, named), check_named_expected(named),
                   check_shared_baseline(shared, "--strict" in sys.argv)]
        print("PASS" if all(results) else "FAIL")
        return 0 if all(results) else 1
    if not check_named_rival(shared, named):
        return 1
    SHARED_EXPECTED.write_text(canonical(shared), encoding="utf-8")
    NAMED_EXPECTED.write_text(canonical(named), encoding="utf-8")
    if PENDING.exists():
        PENDING.unlink()
        print(f"removed {PENDING.name}: the shared baseline now includes the pending rule")
    for target, produced in ((SHARED_EXPECTED, shared), (NAMED_EXPECTED, named)):
        pages = sum(len(s["pages"]) + len(s["resetPages"]) for s in produced["scenarios"])
        print(f"wrote {target} ({len(produced['scenarios'])} scenarios, {pages} pages)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
