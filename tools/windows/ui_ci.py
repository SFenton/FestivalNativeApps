#!/usr/bin/env python3
"""``windows-ui`` CI dispatcher: runs the Windows accessibility journeys in :data:`RUNS` through ``a11y_matrix.py``.

``.github/workflows/windows-ui.yml`` builds the Debug app on a hosted ``windows-latest`` runner (an interactive,
unlocked desktop), then calls this script. Every run serves the loopback fixtures, so CI makes no service calls.
A run with a system ``mode`` (e.g. ``text-225``) changes the runner's own desktop setting and restores it afterwards.

This is the one registry of Windows accessibility journeys that gate pull requests: a journey is in CI only when it has a
:data:`RUNS` entry (``only`` limits a run to some of a file's pages). ``tests/test_ui_ci.py`` checks the entries and
that the modal journey (issue #400), the Songs Jump backward-pick pages (issue #415) and the Quick Links landings
(issue #416) run at default and 225% text.
Add an entry with each new ``journeys/a11y-*.json``, at ``normal`` and ``text-225`` at least.

Usage::

    python tools/windows/ui_ci.py --out out/windows-ui            # every run
    python tools/windows/ui_ci.py --out out/windows-ui --only modals-text-225
    python tools/windows/ui_ci.py --list
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import a11y_matrix  # noqa: E402  (sibling tool)

JOURNEYS = Path(__file__).resolve().parent / "journeys"

# region Runs (pure, unit-tested)


@dataclass(frozen=True)
class Run:
    """One ``a11y_matrix.py`` invocation.

    Attributes:
        name: Run name (its output folder under ``--out``).
        pages: Page list file name under ``tools/windows/journeys``.
        sizes: Window presets, comma-separated.
        mode: ``a11y_matrix`` mode (``normal`` or a ``MODES`` key, ``+``-joined).
        tabs: Tab presses per page and size (0: no walk).
        scan: Fail on any Axe.Windows error.
        only: Comma-separated page names to run from ``pages`` (empty: every page).
    """

    name: str
    pages: str
    sizes: str = "compact,medium"
    mode: str = "normal"
    tabs: int = 30
    scan: bool = True
    only: str = ""

    def argv(self, out: Path, exe: str | None = None) -> list[str]:
        """``a11y_matrix.main`` arguments for this run.

        Args:
            out: Root output folder; this run writes to ``out/<name>``.
            exe: Optional ``--exe`` value (default: the Debug build).

        Returns:
            Argument list.
        """
        args = ["--pages", str(JOURNEYS / self.pages), "--sizes", self.sizes, "--mode", self.mode,
                "--tabs", str(self.tabs), "--out", str(out / self.name)]
        if self.scan:
            args.append("--scan")
        if self.only:
            args += ["--only", self.only]
        if exe:
            args += ["--exe", exe]
        return args


#: The ``a11y-section-index.json`` fixture pages for the #48 backward pick (the file's other pages are ``--live``-capable
#: host checks).
SECTION_INDEX_BACKWARD = "index-backward-after-scroll,index-backward-after-scroll-keyboard"

#: Journeys the ``windows-ui`` job runs, in order. ``wide`` (1440 epx) is left to the host matrix: the runner's
#: desktop is 1920x1080 at 100% scale, so compact (500x800) and medium (900x700) fit with room for the taskbar.
RUNS: tuple[Run, ...] = (
    # Every FestivalDialog modal (issues #23, #239, #400): Narrator phrases, reading order, 40x40 commands, keyboard, Esc.
    Run("modals", "a11y-modals.json"),
    # The same pages at Windows' largest text size: text on screen, commands reachable by Tab and hit-testable.
    Run("modals-text-225", "a11y-modals.json", sizes="compact", mode="text-225"),
    # The Songs Filter without a profile (issues #77, #432): General-only sections, Narrator phrases and order, 40 epx
    # Reset / Select All / Clear All, live Double Bass and Year narrowing, Filters applied, keyboard and Esc.
    Run("songs-filter", "a11y-songs-filter.json"),
    Run("songs-filter-text-225", "a11y-songs-filter.json", sizes="compact", mode="text-225"),
    # Songs Jump backward pick after a scroll (issues #48, #415): the pinned title names the picked section, reads
    # "B, text", stays a Level 2 heading, Jump -> title -> list order, Jump's name and 40x40 target, by pointer and keys.
    Run("section-index-backward", "a11y-section-index.json", only=SECTION_INDEX_BACKWARD),
    Run("section-index-backward-text-225", "a11y-section-index.json", mode="text-225", only=SECTION_INDEX_BACKWARD),
    # Quick Links landings on Settings and Leaderboards (issues #51, #416): entry name and current section, 40 epx
    # entry and items, keyboard order, the jump announcement, heading landing inset and focus. The wide pane page
    # (scale-100/150 modes) stays in the host matrix.
    Run("quick-links-landing", "a11y-quick-links-landing.json", tabs=0),
    Run("quick-links-landing-text-225", "a11y-quick-links-landing.json", sizes="compact", mode="text-225", tabs=0),
)


def generated_runs(explicit: tuple[Run, ...]) -> tuple[Run, ...]:
    """Add normal and text-225 fixture runs for every uncovered ``a11y-*.json`` page."""
    skip_file = JOURNEYS.parent / "ci_skip.json"
    skipped = json.loads(skip_file.read_text(encoding="utf-8")).get("a11y_pages", {}) if skip_file.exists() else {}
    covered: dict[str, set[str] | None] = {}
    for run in explicit:
        covered[run.pages] = None if not run.only else set(run.only.split(","))
    generated = []
    for source in sorted(JOURNEYS.glob("a11y-*.json")):
        pages = [page["name"] for page in json.loads(source.read_text(encoding="utf-8"))
                 if "live" not in page["name"].lower() and page["name"] not in skipped]
        if covered.get(source.name) is None and source.name in covered:
            continue
        pages = [page for page in pages if page not in covered.get(source.name, set())]
        if pages:
            only = ",".join(pages)
            source_pages = [page for page in json.loads(source.read_text(encoding="utf-8")) if page["name"] in pages]
            if a11y_matrix.mode_pages(source_pages, "normal"):
                generated.append(Run(f"{source.stem}-normal", source.name, only=only))
            if a11y_matrix.mode_pages(source_pages, "text-225"):
                generated.append(Run(f"{source.stem}-text-225", source.name, sizes="compact", mode="text-225", only=only))
    return (*explicit, *generated)


RUNS = generated_runs(RUNS)


def select(runs: tuple[Run, ...], only: str | None) -> list[Run]:
    """Runs named by ``--only`` (all when empty).

    Args:
        runs: Candidate runs.
        only: Comma-separated run names, or ``None``.

    Returns:
        The selected runs, in :data:`RUNS` order.

    Raises:
        ValueError: A name matches no run.
    """
    if not only:
        return list(runs)
    wanted = {name for name in only.split(",") if name}
    unknown = wanted - {run.name for run in runs}
    if unknown:
        raise ValueError(f"unknown run(s): {', '.join(sorted(unknown))}")
    return [run for run in runs if run.name in wanted]

# endregion


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        0 when every run passed, 1 otherwise.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, help="output root (one folder per run)")
    parser.add_argument("--only", help="comma-separated run names")
    parser.add_argument("--exe", help="app under test (a11y_matrix --exe; default: the Debug build)")
    parser.add_argument("--list", action="store_true", help="print the runs and exit")
    parser.add_argument("--shard", type=int, default=1)
    parser.add_argument("--shards", type=int, default=1)
    args = parser.parse_args(argv)
    try:
        runs = select(RUNS, args.only)
    except ValueError as error:
        parser.error(str(error))
    if not 1 <= args.shard <= args.shards:
        parser.error("--shard must be within --shards")
    buckets = [[] for _ in range(args.shards)]
    weights = [0] * args.shards
    for run in sorted(runs, key=lambda item: (-len(item.only.split(",")) * len(item.sizes.split(",")), item.name)):
        index = min(range(args.shards), key=lambda candidate: (weights[candidate], candidate))
        buckets[index].append(run)
        weights[index] += len(run.only.split(",")) * len(run.sizes.split(","))
    runs = buckets[args.shard - 1]
    if args.list:
        for run in runs:
            only = f" only={run.only}" if run.only else ""
            print(f"{run.name}: {run.pages}{only} sizes={run.sizes} mode={run.mode} tabs={run.tabs} scan={run.scan}")
        return 0
    if args.out is None:
        parser.error("--out is required")
    failed = []
    for run in runs:
        print(f"== {run.name}", flush=True)
        if a11y_matrix.main(run.argv(args.out.resolve(), args.exe)) != 0:
            failed.append(run.name)
    print(f"windows-ui: {len(runs) - len(failed)}/{len(runs)} run(s) passed" + (f"; failed: {', '.join(failed)}" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
