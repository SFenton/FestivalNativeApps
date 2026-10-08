#!/usr/bin/env python3
"""Windows UI CI: runs the ``a11y_matrix.py`` journeys listed in ``journeys/ci-ui.json`` (the ``windows-ui`` job).

Each manifest entry names a page file under ``tools/windows/journeys``, the pages to run (``only``), window sizes,
system modes (e.g. ``normal`` and ``text-225``) and whether every size is Axe-scanned. The runner calls
``a11y_matrix.main`` once per entry and mode against the Debug build (or ``--exe``) and the loopback fixture
service, so the job never touches the public service. Results land in ``--out/<entry>/``; the exit code is 1 when
any run failed.

Add an accessibility journey to CI by appending an entry (issue, pages, sizes, modes); ``tests/test_ci_ui.py``
checks every entry resolves to real pages, sizes and modes. The runner never passes ``--live``: every page runs
against the loopback fixture service.

Usage::

    python tools/windows/ci_ui.py --out out/windows-ui
    python tools/windows/ci_ui.py --out out/windows-ui --only songs-section-index-backward-pick --modes text-225
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import a11y_matrix  # noqa: E402  (sibling module)
import journey_exe  # noqa: E402  (sibling module: --exe debug|release|aot)
import uiwin  # noqa: E402  (window presets)

JOURNEYS = Path(__file__).resolve().parent / "journeys"
MANIFEST = JOURNEYS / "ci-ui.json"

# region Manifest (pure, unit-tested)


def load(path: Path = MANIFEST) -> list[dict]:
    """The manifest's entries, validated.

    Args:
        path: Manifest file.

    Returns:
        Entries in file order.

    Raises:
        ValueError: An entry names a missing page file or page, an unknown size or mode, or repeats a name.
    """
    entries = json.loads(path.read_text(encoding="utf-8"))
    seen: set[str] = set()
    for entry in entries:
        validate(entry, path.parent)
        if entry["name"] in seen:
            raise ValueError(f"duplicate CI entry {entry['name']!r}")
        seen.add(entry["name"])
    return entries


def validate(entry: dict, journeys: Path = JOURNEYS) -> None:
    """Check one manifest entry against its page file.

    Args:
        entry: ``name``, ``issue``, ``pages`` (file under ``journeys``), ``only`` (page names), ``sizes``, ``modes``
            and optional ``scan`` (default true).
        journeys: Directory holding the page files.

    Raises:
        ValueError: See :func:`load`.
    """
    for key in ("name", "issue", "pages", "only", "sizes", "modes"):
        if not entry.get(key):
            raise ValueError(f"CI entry {entry.get('name')!r} needs {key!r}")
    file = journeys / entry["pages"]
    if not file.is_file():
        raise ValueError(f"CI entry {entry['name']!r}: no page file {file.name}")
    pages = {p["name"]: p for p in json.loads(file.read_text(encoding="utf-8"))}
    for name in entry["only"]:
        if name not in pages:
            raise ValueError(f"CI entry {entry['name']!r}: {file.name} has no page {name!r}")
    for size in entry["sizes"]:
        if size not in uiwin.PRESETS:
            raise ValueError(f"CI entry {entry['name']!r}: unknown size {size!r}")
    for mode in entry["modes"]:
        a11y_matrix.mode_spec(mode)


def matrix_args(entry: dict, mode: str, out: Path, exe: Path) -> list[str]:
    """``a11y_matrix.py`` arguments for one entry in one mode.

    Args:
        entry: Validated manifest entry.
        mode: One of the entry's modes.
        out: Output root; the entry writes to ``out/<name>``.
        exe: App executable.

    Returns:
        Argument list for :func:`a11y_matrix.main`.
    """
    args = ["--pages", str(JOURNEYS / entry["pages"]), "--only", ",".join(entry["only"]),
            "--sizes", ",".join(entry["sizes"]), "--mode", mode, "--out", str(out / entry["name"]),
            "--exe", str(exe)]
    if entry.get("scan", True):
        args.append("--scan")
    return args

# endregion


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        0 when every entry passed in every mode, 1 otherwise.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--only", help="comma-separated entry names")
    parser.add_argument("--modes", help="comma-separated modes to run (default: each entry's own)")
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    journey_exe.add_argument(parser)
    args = parser.parse_args(argv)
    entries = load(args.manifest)
    if args.only:
        wanted = set(args.only.split(","))
        entries = [e for e in entries if e["name"] in wanted]
    failed: list[str] = []
    for entry in entries:
        modes = [m for m in entry["modes"] if not args.modes or m in args.modes.split(",")]
        for mode in modes:
            print(f"== {entry['name']} (#{entry['issue']}) {mode}", flush=True)
            if a11y_matrix.main(matrix_args(entry, mode, args.out.resolve(), args.exe)) != 0:
                failed.append(f"{entry['name']} {mode}")
    if failed:
        print("FAILED: " + "; ".join(failed), file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
