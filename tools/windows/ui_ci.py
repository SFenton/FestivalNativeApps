#!/usr/bin/env python3
"""``windows-ui`` CI dispatcher: runs the Windows accessibility journeys in :data:`RUNS` through ``a11y_matrix.py``.

``.github/workflows/windows-ui.yml`` builds the Debug app on a hosted ``windows-latest`` runner (an interactive,
unlocked desktop), then calls this script. Every run serves the loopback fixtures, so CI makes no service calls.
A run with a system ``mode`` (e.g. ``text-225``) changes the runner's own desktop setting and restores it afterwards.

This is the one registry of Windows accessibility journeys that gate pull requests: a journey is in CI only when it has a
:data:`RUNS` entry (``only`` limits a run to some of a file's pages). ``tests/test_ui_ci.py`` checks the entries and
that the modal journey (issue #400), the Songs Jump backward-pick pages (issue #415), the Quick Links landings
(issue #416), the Item Shop Filters flyout and its keyboard journey (issue #428), the board load swap (issue #431, also
with Animation effects off), the first-run song demos (issue #420), the Songs section push (issue #452) and the Paths
swap (issue #430, also with Animation effects off) run at default
and 225% text, and that the generated work-behind-dialogs runs (issues #83, #436) gate PRs and cover motion off.
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
from dataclasses import dataclass, replace
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

#: The ``a11y-keyboard.json`` page for the Item Shop Filters flyout (#19, #428); the file's other pages stay host checks.
SHOP_FILTER_KEYBOARD = "kb-shop-filter"

#: The ``a11y-board-footer-fade.json`` song-leaderboard pages (issue #93's footer fade; the file's other boards and its
#: system-mode pages stay host checks).
SONG_BOARD_FOOTER_FADE = ("footer-fade-song-leaderboard-rest,footer-fade-song-leaderboard-mid,footer-fade-song-leaderboard-end,"
                          "footer-fade-song-leaderboard-more-contrast,footer-fade-song-leaderboard-less-transparency")

#: Journeys the ``windows-ui`` job runs, in order. ``wide`` (1440 epx) is left to the host matrix: the runner's
#: desktop is 1920x1080 at 100% scale, so compact (500x800) and medium (900x700) fit with room for the taskbar.
RUNS: tuple[Run, ...] = (
    # Every FestivalDialog modal (issues #23, #239, #400): Narrator phrases, reading order, 40x40 commands, keyboard, Esc.
    Run("modals", "a11y-modals.json"),
    # The same pages at Windows' largest text size: text on screen, commands reachable by Tab and hit-testable.
    Run("modals-text-225", "a11y-modals.json", sizes="compact", mode="text-225"),
    # What's New (issues #80, #274, #434): placeholder and grouped tester/store notes; level-2 version and level-3
    # category headings, reading order, the Raw bullet glyph, 40x40 Dismiss, keyboard scrolling and Esc.
    Run("whats-new", "a11y-whats-new.json"),
    # The grouped notes at Windows' largest text size: headings wrap and the keyboard still reaches "Other" and Dismiss.
    Run("whats-new-text-225", "a11y-whats-new.json", sizes="compact", mode="text-225"),
    # The Songs Filter without a profile (issues #77, #432): General-only sections, Narrator phrases and order, 40 epx
    # Reset / Select All / Clear All, live Double Bass and Year narrowing, Filters applied, keyboard and Esc.
    Run("songs-filter", "a11y-songs-filter.json"),
    Run("songs-filter-text-225", "a11y-songs-filter.json", sizes="compact", mode="text-225"),
    # Songs Jump backward pick after a scroll (issues #48, #415): the pinned title names the picked section, reads
    # "B, text", stays a Level 2 heading, Jump -> title -> list order, Jump's name and 40x40 target, by pointer and keys.
    Run("section-index-backward", "a11y-section-index.json", only=SECTION_INDEX_BACKWARD),
    Run("section-index-backward-text-225", "a11y-section-index.json", mode="text-225", only=SECTION_INDEX_BACKWARD),
    # Songs section push (issues #288, #452): mid-push, scrolling down into the boundary and back up, the bar still reads
    # the outgoing section as a Level 2 heading, the incoming in-list title (transparent under the drawn copy) stays the
    # Level 2 heading in order Jump -> bar -> title, and the copy is drawn but never a second Narrator stop; by keys,
    # focus moves row -> group header -> previous row through the band and never lands on the copy.
    Run("songs-section-push", "a11y-songs-section-push.json", tabs=0),
    Run("songs-section-push-text-225", "a11y-songs-section-push.json", sizes="compact", mode="text-225", tabs=0),
    # Song leaderboard footer and paging (issues #93, #443): pinned row and pager names, states and 40x40 targets,
    # header -> rows -> pinned row -> pager order, the fade layer kept out of the control view, the Tab/Shift+Tab order
    # at rest, mid-load and on page 2, and a keyboard page change that keeps the header, pinned row and pager in order
    # with focus on Next; also with in-app Reduce Motion.
    Run("song-leaderboard", "a11y-song-leaderboard.json"),
    Run("song-leaderboard-text-225", "a11y-song-leaderboard.json", sizes="compact", mode="text-225"),
    Run("song-leaderboard-reduced-motion", "a11y-song-leaderboard.json", sizes="medium", mode="app-reduced",
        only="song-board-paging-keyboard"),
    # The rows fade 40 epx above the footer at rest, mid-scroll and end, and cut hard under More Contrast and
    # Less Transparency (issue #93).
    Run("song-leaderboard-footer-fade", "a11y-board-footer-fade.json", only=SONG_BOARD_FOOTER_FADE),
    Run("song-leaderboard-footer-fade-text-225", "a11y-board-footer-fade.json", sizes="compact", mode="text-225",
        only=SONG_BOARD_FOOTER_FADE),
    # Back from View All or a rival to cached Leaderboards and Rivals (issues #82, #276, #435): the opener and its card
    # stay put, focus returns to the opener, it reads "<name>, button" after its card and heading, keeps a 40 epx target,
    # and Tab/Shift+Tab continue from it; by keys (Enter, Alt+Left) and pointer (the title-bar Back).
    Run("back-keeps-place", "a11y-back-keeps-place.json"),
    Run("back-keeps-place-text-225", "a11y-back-keeps-place.json", sizes="compact", mode="text-225"),
    # Quick Links landings on Settings and Leaderboards (issues #51, #416): entry name and current section, 40 epx
    # entry and items, keyboard order, the jump announcement, heading landing inset and focus. The wide pane page
    # (scale-100/150 modes) stays in the host matrix.
    Run("quick-links-landing", "a11y-quick-links-landing.json", tabs=0),
    Run("quick-links-landing-text-225", "a11y-quick-links-landing.json", sizes="compact", mode="text-225", tabs=0),
    # The Item Shop Filters flyout (issues #19, #428): heading, New / Available / Leaving Tomorrow switch phrases and
    # state, Filters applied, the song count and empty state, title -> switches -> Reset order, 40 epx Reset, text scaling.
    Run("shop-filter", "a11y-shop-filter.json"),
    Run("shop-filter-text-225", "a11y-shop-filter.json", sizes="compact", mode="text-225"),
    # Its keyboard journey (#428 review): Enter opens on New, Space toggles, Tab/Shift+Tab walk the switches to Reset,
    # Enter resets, Esc closes with focus back on Filters and "Filters applied", at default and 225% text.
    Run("shop-filter-keyboard", "a11y-keyboard.json", tabs=0, only=SHOP_FILTER_KEYBOARD),
    Run("shop-filter-keyboard-text-225", "a11y-keyboard.json", sizes="compact", mode="text-225", tabs=0,
        only=SHOP_FILTER_KEYBOARD),
    # The pinned "your band" row on a song's full Duos/Trios/Quads board (issues #306, #461): Narrator phrases for
    # Jump / Open band, 40 epx targets, rows -> pin -> pager order, Tab/Enter jump clear of the pin, size switch,
    # no-player and reduced-motion states.
    Run("song-band-pinned", "a11y-song-band-pinned.json", tabs=0),
    Run("song-band-pinned-text-225", "a11y-song-band-pinned.json", sizes="compact", mode="text-225", tabs=0),
    # Board load swap (issues #71, #431): spinner "Busy Loading …, ProgressRing", stale rows leave UIA, selectors ->
    # spinner -> pager order, enabled 40x40 selectors and pager, focus kept on the pager, mid-load Axe scans; then the
    # same swap at 225% text and with Windows' Animation effects off. Every page is medium-only (pager plus spinner).
    Run("load-swap", "a11y-load-swap.json", sizes="medium", tabs=0),
    Run("load-swap-text-225", "a11y-load-swap.json", sizes="medium", mode="text-225", tabs=0),
    Run("load-swap-no-animations", "a11y-load-swap.json", sizes="medium", mode="no-animations", tabs=0),
    # First-run song demos (issues #57, #420): Songs, top-songs and Item Shop demos in placeholder and catalogue states
    # stay out of the control view, slide name and slide -> pips -> Next -> Back -> Close order, Tab to an on-screen pip,
    # keyboard Settings replay with Esc focus return, demo frame clear of the title. At 225% the guide body scrolls.
    Run("first-run-demos", "a11y-first-run-demos.json"),
    Run("first-run-demos-text-225", "a11y-first-run-demos.json", sizes="compact", mode="text-225"),
    # Full boards as one grouped card (issue #543): song board, Full Rankings, Band Rankings and the song band board rows
    # touch (0 epx), each stays one 40+ epx Button stop in visual order, rows -> pinned row -> pager, Up/Down and Tab.
    Run("grouped-boards", "a11y-grouped-boards.json", tabs=0),
    Run("grouped-boards-text-225", "a11y-grouped-boards.json", sizes="compact", mode="text-225", tabs=0),
    # Settings' Experimental Ranks toggle (issue #541): enabled, off by default, named and Space-toggled; turning it on
    # shows "Rank by: Total Score, button" (40 epx) on Leaderboards and off hides it again; with it off a saved or
    # deep-linked experimental metric leaves no Rank By on Leaderboards, Full Rankings or Band Rankings.
    Run("experimental-ranks", "a11y-experimental-ranks.json", tabs=0),
    Run("experimental-ranks-text-225", "a11y-experimental-ranks.json", sizes="compact", mode="text-225", tabs=0),
    # Paths swap (issues #70, #430): mid-swap the old chart leaves UIA, "Busy Loading path, ProgressRing" sits between
    # the selectors and Close, the selectors stay enabled and show the new value, "Loading …" then "… loaded" are
    # announced; Image <-> Text; keyboard switches (ComboBox, wide RadioButtons) keep focus on the selector; 40 epx zoom,
    # selectors and Close; mid-swap Axe scans; at 225% text, with in-app Reduce Motion and with Animation effects off.
    Run("paths-swap", "a11y-paths-swap.json", sizes="compact,medium,wide"),
    Run("paths-swap-text-225", "a11y-paths-swap.json", sizes="compact,wide", mode="text-225"),
    Run("paths-swap-no-animations", "a11y-paths-swap.json", sizes="compact", mode="no-animations"),
)


def generated_runs(explicit: tuple[Run, ...]) -> tuple[Run, ...]:
    """Add fixture runs for every uncovered ``a11y-*.json`` page, in the modes the page runs in.

    A page without ``modes`` runs at ``normal`` and ``text-225``; a page that declares ``modes`` (any of them shows its
    state, e.g. ``["hc-desert", "no-transparency"]`` for a hard edge that only exists under a contrast theme or with
    transparency off) runs once, in its first listed mode. ``live_only`` pages (they need the live service) and ``ci_skip.json`` ``a11y_pages`` are left out.
    """
    skip_file = JOURNEYS.parent / "ci_skip.json"
    skipped = json.loads(skip_file.read_text(encoding="utf-8")).get("a11y_pages", {}) if skip_file.exists() else {}
    covered: dict[str, set[str] | None] = {}
    for run in explicit:
        covered[run.pages] = None if not run.only else set(run.only.split(","))
    generated = []
    for source in sorted(JOURNEYS.glob("a11y-*.json")):
        if covered.get(source.name) is None and source.name in covered:
            continue
        pages = [page for page in json.loads(source.read_text(encoding="utf-8"))
                 if "live" not in page["name"].lower() and not page.get("live_only")
                 and page["name"] not in skipped and page["name"] not in covered.get(source.name, set())]
        if not pages:
            continue
        by_mode: dict[str, list[dict]] = {"normal": [], "text-225": []}
        for page in pages:
            for mode in (page["modes"][:1] if page.get("modes") else ("normal", "text-225")):
                by_mode.setdefault(mode, []).append(page)
        for mode, candidates in by_mode.items():
            chosen = a11y_matrix.mode_pages(candidates, mode)
            if not chosen:
                continue
            only = ",".join(page["name"] for page in chosen)
            sizes = ["compact"] if mode.startswith("text-") else ["compact", "medium"]
            for page in chosen:  # a page that only runs at other sizes (e.g. wide) adds its first one
                if not a11y_matrix.page_sizes(page, sizes, mode) and page.get("sizes"):
                    sizes.append(page["sizes"][0])
            generated.append(Run(f"{source.stem}-{mode}", source.name, sizes=",".join(dict.fromkeys(sizes)),
                                 mode=mode, only=only))
    return (*explicit, *generated)


RUNS = generated_runs(RUNS)


def tier_runs(runs: list[Run], tier: str) -> list[Run]:
    """The runs for a CI tier.

    ``pr`` is the pull-request gate: every page at ``normal`` mode in one window (the run's first size any page runs at,
    usually compact) (about a third of the full
    matrix, so Windows PRs don't monopolize the shared hosted runners). ``full`` (pushes to master and the nightly
    schedule) adds the medium window, 225% text and each page's declared modes; a regression it finds on master is
    filed as a Priority fix by the release machine.

    Args:
        runs: Candidate runs.
        tier: ``pr`` or ``full``.

    Returns:
        The runs to execute.
    """
    if tier == "full":
        return list(runs)
    out = []
    for run in runs:
        if run.mode != "normal":
            continue
        pages = run_pages(run)
        size = next((s for s in run.sizes.split(",") if any(a11y_matrix.page_sizes(p, [s], run.mode) for p in pages)),
                    None)
        if size:
            out.append(replace(run, sizes=size))
    return out


def run_pages(run: Run) -> list[dict]:
    """The page definitions one run executes (its ``only`` subset of its page file, filtered to its mode)."""
    pages = json.loads((JOURNEYS / run.pages).read_text(encoding="utf-8"))
    if run.only:
        wanted = set(run.only.split(","))
        pages = [page for page in pages if page["name"] in wanted]
    return a11y_matrix.mode_pages(pages, run.mode)


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
    parser.add_argument("--tier", choices=("pr", "full"), default="full",
                        help="pr: normal mode at compact only (the pull-request gate); full: every run (master, nightly)")
    parser.add_argument("--shard", type=int, default=1)
    parser.add_argument("--shards", type=int, default=1)
    args = parser.parse_args(argv)
    try:
        runs = select(RUNS, args.only)
    except ValueError as error:
        parser.error(str(error))
    runs = tier_runs(runs, args.tier)
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
