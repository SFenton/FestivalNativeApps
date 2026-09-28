"""Produce the Apple reference outputs for the Windows Suggestions parity test.

Compiles the *unmodified* Apple suggestion sources (SuggestionGenerator/Models/RivalData,
RivalsAll, ScoreFormatting and the Instrument/Song part of SongCatalog) together with
Shim.swift + main.swift, runs them over windows/Festival.Core.Tests/Fixtures/suggestions-parity.json
and writes suggestions-parity.expected.json beside it. Works with the Swift toolchain on Windows
(``winget install Swift.Toolchain``) or on the Mac.

Usage: python tools/windows/suggestion_parity/run_parity.py [--check]
  --check  compare against the committed expected file instead of overwriting it.
"""

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
WHOLE_FILES = ["SuggestionGenerator.swift", "SuggestionModels.swift", "SuggestionRivalData.swift",
               "RivalsAll.swift", "ScoreFormatting.swift"]


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


def main() -> int:
    """Build and run the harness, then write or check the expected outputs."""
    check = "--check" in sys.argv
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
        result = subprocess.run([str(exe), str(FIXTURES / "suggestions-parity.json")], check=True,
                                capture_output=True, env=env)
    produced = json.loads(result.stdout)
    target = FIXTURES / "suggestions-parity.expected.json"
    text = json.dumps(produced, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n"
    if check:
        same = json.loads(target.read_text(encoding="utf-8")) == produced
        print("Apple output matches the committed expected file." if same else "MISMATCH: regenerate and review.")
        return 0 if same else 1
    target.write_text(text, encoding="utf-8")
    pages = sum(len(s["pages"]) for s in produced["scenarios"])
    print(f"wrote {target} ({len(produced['scenarios'])} scenarios, {pages} pages)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
