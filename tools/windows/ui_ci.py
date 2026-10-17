#!/usr/bin/env python3
"""``windows-ui`` CI dispatcher: runs the Windows accessibility journeys in :data:`RUNS` through ``a11y_matrix.py``.

``.github/workflows/windows-ui.yml`` builds the Debug app on a hosted ``windows-latest`` runner (an interactive,
unlocked desktop), then calls this script. Every run serves the loopback fixtures, so CI makes no service calls.
A run with a system ``mode`` (e.g. ``text-225``) changes the runner's own desktop setting and restores it afterwards.

This is the one registry of Windows accessibility journeys that gate pull requests: a journey is in CI only when it has a
:data:`RUNS` entry (``only`` limits a run to some of a file's pages). ``tests/test_ui_ci.py`` checks the entries and
that the modal journey (issue #400) and its contrast-backplate and hint-wrap legibility pages (issue #518), the Songs Jump
backward-pick pages (issue #415), the Songs Jump open, Escape and Item Shop label pages (issues #231, #517, also with
in-app Reduce Motion), the Quick Links landings
(issue #416), the Item Shop Filters flyout and its keyboard journey (issue #428), the board load swap (issue #431, also
with Animation effects off), the first-run song demos (issue #420), the header flyouts (issue #534), the Songs section
push (issue #452), the Songs scroll far jumps and keyboard End/Home (issue #520, also with Animation effects off), the
Paths swap (issue #430, also with Animation effects off), the Paths selector surfaces (issue #650, also with
Transparency effects off and under Desert contrast), the Paths chart (issue #438, also with "Always show
scrollbars" on, issue #525), the Paths text table (issue #515, also under a contrast theme), long leaderboard names
(issue #455, also with Animation effects off) and the Full
Rankings pinned row (issue #466, also with in-app Reduce Motion), the Leaderboards card "your rank" row (issue #493,
also with in-app Reduce Motion), the Search All section titles (issue #483, also with in-app Reduce Motion), the
Search results delayed behind the spinner and the Suggestions cards loaded after the first batch (issue #521, also with
motion off), the
Song Band Leaderboard rows, empty and error states (issue #510), the Suggestions cards, keyboard, filter and states
(issue #513), the Item Shop offers grid, List/Grid toggle, rings and states (issue #516, also with in-app Reduce
Motion), the real-control First Run demos (issue #498, also with Animation effects off), the profile title row
(issue #446), the wide columns (issue #653, the one-column fallback also in a wide window at 150% text), the Score
History chart (issue #512, also under Desert contrast) and the loading placement with Leaderboards' Quick Links gated
on its cards (issue #649) run at default and 225% text, that the
generated leaderboard-columns normal run switches a contrast theme with a song board open (issue #519), and that the
generated work-behind-dialogs runs (issues #83, #436) gate PRs and cover motion off.
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

#: The ``a11y-section-index.json`` fixture pages for issue #231's Jump changes (#517): focus on open, Escape from the
#: index and from Jump, Ctrl+Minus, the hide/show path, and Item Shop labels at the widest label's width.
SECTION_INDEX_JUMP = "index-open-escape,index-shop-labels"

#: The ``a11y-profile-title.json`` fixture pages (issues #97, #285, #446); its ``pt-live-*`` pages need the public service.
PROFILE_TITLE_FIXTURE = ("pt-switch,pt-anonymous,pt-selected,pt-notice,pt-actions-row,pt-actions-wrap,"
                         "pt-keyboard-switch,pt-keyboard-selected")

#: The ``a11y-keyboard.json`` page for the Item Shop Filters flyout (#19, #428); the file's other pages stay host checks.
SHOP_FILTER_KEYBOARD = "kb-shop-filter"

#: The ``a11y-board-footer-fade.json`` song-leaderboard pages (issue #93's footer fade; the file's other boards and its
#: system-mode pages stay host checks).
SONG_BOARD_FOOTER_FADE = ("footer-fade-song-leaderboard-rest,footer-fade-song-leaderboard-mid,footer-fade-song-leaderboard-end,"
                          "footer-fade-song-leaderboard-more-contrast,footer-fade-song-leaderboard-less-transparency")

#: The ``a11y-history-swap.json`` reduced-motion page (#61, #423), run in both motion-off modes it declares.
HISTORY_SWAP_REDUCED = "history-swap-reduced-access"

#: The canonical ``a11y.json`` header-flyout pages (issue #534: every app flyout is constrained to the window, so none
#: may open a windowed ``PopupHost``; the file's other pages stay host matrix checks).
POPUP_PAGES = "leaderboards-rank-by-menu,rank-by-menu,quick-links-menu,profile-flyout,notifications-panel"

#: The ``a11y-search.json`` All section-title pages (issue #348's titles, #483); the file's other pages are generated runs.
SEARCH_SECTIONS = "search-all-sections,search-all-sections-keyboard"

#: The ``a11y-search.json`` page for results that waited behind the spinner for a slow player search (issues #260, #521).
SEARCH_DELAYED_RESULTS = "search-delayed-results"

#: The ``a11y-suggestions.json`` pages for the cards loaded after the first batch (issues #260, #521), also run with
#: motion off.
SUGGESTIONS_LOAD_MORE = "suggestions-load-more,suggestions-load-more-keyboard"

#: The ``a11y-suggestions.json`` row centre-line pages (issue #654), also run at wide and at 225% text beside the title.
SUGGESTIONS_ROW_CENTRE = "suggestions-row-centre,suggestions-row-centre-rival"

#: The ``a11y-wide-columns.json`` one-column pages (issue #653): narrow windows, and wide ones from 150% text.
WIDE_COLUMNS_ONE = "wide-columns-statistics-one,wide-columns-suggestions-one"

#: Journeys the ``windows-ui`` job runs, in order. ``wide`` (1440 epx) is left to the host matrix: the runner's
#: desktop is 1920x1080 at 100% scale, so compact (500x800) and medium (900x700) fit with room for the taskbar.
RUNS: tuple[Run, ...] = (
    # Every FestivalDialog modal (issues #23, #239, #400): Narrator phrases, reading order, 40x40 commands, keyboard, Esc.
    Run("modals", "a11y-modals.json"),
    # The same pages at Windows' largest text size: text on screen, commands reachable by Tab and hit-testable.
    Run("modals-text-225", "a11y-modals.json", sizes="compact", mode="text-225"),
    # What #239 changed on top of the modal shell (issue #518): under a contrast theme the dialog command labels and the
    # First Run pips paint their own colours with no Window-coloured text backplate (pixel probes), and the Feedback
    # field hints wrap at 225% text. Default-mode names, order, targets and keyboard are the "modals" runs above.
    Run("modal-legibility-desert", "a11y-modal-legibility.json", mode="hc-desert"),
    Run("modal-legibility-night-sky", "a11y-modal-legibility.json", sizes="compact", mode="hc-night-sky"),
    Run("modal-legibility-text-225", "a11y-modal-legibility.json", sizes="compact", mode="text-225"),
    # What's New (issues #80, #274, #434): placeholder and grouped tester/store notes; level-2 version and level-3
    # category headings, reading order, the Raw bullet glyph, 40x40 Dismiss, keyboard scrolling and Esc.
    Run("whats-new", "a11y-whats-new.json"),
    # The grouped notes at Windows' largest text size: headings wrap and the keyboard still reaches "Other" and Dismiss.
    Run("whats-new-text-225", "a11y-whats-new.json", sizes="compact", mode="text-225"),
    # The Songs Filter without a profile (issues #77, #432): General-only sections, Narrator phrases and order, 40 epx
    # Reset / Select All / Clear All, live Double Bass and Year narrowing, Filters applied, keyboard and Esc.
    Run("songs-filter", "a11y-songs-filter.json"),
    Run("songs-filter-text-225", "a11y-songs-filter.json", sizes="compact", mode="text-225"),
    # Accordions (issue #561): Songs Filter Expanders, the Suggestions Instrument-Specific panel and the Settings options
    # a switch reveals (leeway slider, Song Row Visual Order) open (grow, then fade in) and close (fade out, then
    # collapse) with Narrator's expanded/collapsed or on/off phrase, revealed content read and removed from the order when
    # closed, and rapid re-toggles settling open; again with the app's Reduce Motion (instant) and at Windows' largest
    # text size.
    Run("accordion", "a11y-accordion.json"),
    Run("accordion-reduced", "a11y-accordion.json", sizes="medium", mode="app-reduced"),
    Run("accordion-text-225", "a11y-accordion.json", sizes="compact", mode="text-225",
        only="accordion-songs-filter,accordion-settings-switches"),
    # Songs Jump backward pick after a scroll (issues #48, #415): the pinned title names the picked section, reads
    # "B, text", stays a Level 2 heading, Jump -> title -> list order, Jump's name and 40x40 target, by pointer and keys.
    Run("section-index-backward", "a11y-section-index.json", only=SECTION_INDEX_BACKWARD),
    Run("section-index-backward-text-225", "a11y-section-index.json", mode="text-225", only=SECTION_INDEX_BACKWARD),
    # Songs Jump open and close (issues #231, #517): Jump hides with no results and returns, its 40x40 target; opening
    # focuses the current label; the index is the "Jump to section" list of invokable 40x40 list items in order; Escape
    # from the index or from Jump closes it with focus back on Jump; Ctrl+Minus opens it; Item Shop labels (after a sort
    # change) keep the widest label's width, so none is trimmed. Again with the app's Reduce Motion (Jump's fade off).
    Run("section-index-jump", "a11y-section-index.json", tabs=0, only=SECTION_INDEX_JUMP),
    Run("section-index-jump-text-225", "a11y-section-index.json", sizes="compact", mode="text-225", tabs=0,
        only=SECTION_INDEX_JUMP),
    Run("section-index-jump-reduced", "a11y-section-index.json", sizes="medium", mode="app-reduced", tabs=0,
        only=SECTION_INDEX_JUMP),
    # Songs section push (issues #288, #452): mid-push, scrolling down into the boundary and back up, the bar still reads
    # the outgoing section as a Level 2 heading, the incoming in-list title (transparent under the drawn copy) stays the
    # Level 2 heading in order Jump -> bar -> title, and the copy is drawn but never a second Narrator stop; by keys,
    # focus moves row -> group header -> previous row through the band and never lands on the copy.
    Run("songs-section-push", "a11y-songs-section-push.json", tabs=0),
    Run("songs-section-push-text-225", "a11y-songs-section-push.json", sizes="compact", mode="text-225", tabs=0),
    # Songs scrolling (issues #247, #520): after a UIA Scroll-pattern far jump (Narrator, scroll bar) the pinned title
    # names the section now in view (a stale "#" fails), a fling back to the top reads "#, text" again, keyboard
    # End/Home move focus to the last/first row (40 epx) with the title following, and Jump -> title -> list order
    # holds; also with Windows' Animation effects off, where End/Home are non-animated jumps.
    Run("songs-scroll", "a11y-songs-scroll.json", tabs=0),
    Run("songs-scroll-text-225", "a11y-songs-scroll.json", sizes="compact", mode="text-225", tabs=0),
    Run("songs-scroll-no-animations", "a11y-songs-scroll.json", sizes="compact", mode="no-animations", tabs=0),
    # Scroll paging (issue #642): keyboard PageDown on Statistics and Song Details moves the Quick Links current section
    # off the first section while the scroll moves (throttled reports) and keeps it at rest; later Statistics sections
    # still load once the loaded ones stop watching the viewport (tiles named, 40 epx, in order); Axe at the paged state.
    Run("scroll-paging", "a11y-scroll-paging.json", tabs=0),
    Run("scroll-paging-text-225", "a11y-scroll-paging.json", sizes="compact", mode="text-225", tabs=0),
    # Songs metadata chips (issue #644): the row speaks score, accuracy (graded and the skewed gold "100%" full combo),
    # Top %, stars, season, intensity and difficulty in visual order; every text pill is at least 24 epx and shares one
    # height with the others, the 24-epx stars and meter line up with them, the current season paints its full height,
    # Axe-scanned; at 225% text the text pills grow to one shared height, never clipped.
    Run("songs-metadata-chips", "a11y-songs-metadata-chips.json", sizes="medium,wide"),
    Run("songs-metadata-chips-text-225", "a11y-songs-metadata-chips.json", sizes="medium", mode="text-225"),
    # Songs Last Played pill (issue #647): hidden under every sort but Last Played even with its Settings switch on; under
    # Last Played it leads the row as "Last played <date> on <chart>" (the chart only when unfiltered), wraps below the
    # pills at compact and sits on their line when wide, and the row speaks it first; at 225% text it still reads.
    Run("songs-last-played", "a11y-songs-last-played.json", sizes="compact,medium,wide"),
    Run("songs-last-played-text-225", "a11y-songs-last-played.json", sizes="compact,medium", mode="text-225"),
    # Songs instrument chip rows (issue #645, instrument-chip-rows R1-R5): in a 360 epx window the nine chips read
    # 5 + 4 in lines centred on the row (assertmidline), not 7 + 2 or left-aligned; lines never overlap, each chip
    # icon keeps 21 epx and the row speaks every chart in visual order; widening re-flows them to one centred line.
    # At 225% text the chips keep their size and the same balanced, centred lines.
    Run("songs-chip-rows", "a11y-songs-chip-rows.json", sizes="compact"),
    Run("songs-chip-rows-text-225", "a11y-songs-chip-rows.json", sizes="compact", mode="text-225"),
    # Songs toolbar (issue #646): Search, Sort, Filter and Jump share one 40 epx height, each button is at least
    # 40x40 epx, the search box fills the row so the tools end at the rows' right edge (one row at medium and wide;
    # search above the buttons at compact), and search -> Sort -> Filter -> Jump -> rows reading order.
    Run("songs-toolbar", "a11y-songs-toolbar.json", sizes="compact,medium,wide", tabs=0),
    Run("songs-toolbar-text-225", "a11y-songs-toolbar.json", sizes="compact,medium", mode="text-225", tabs=0),
    # Song leaderboard footer and paging (issues #93, #443): pinned row and pager names, states and 40x40 targets,
    # header -> rows -> pinned row -> pager order, the fade layer kept out of the control view, the Tab/Shift+Tab order
    # at rest, mid-load and on page 2, and a keyboard page change that keeps the header, pinned row and pager in order
    # with focus on Next; also with in-app Reduce Motion.
    Run("song-leaderboard", "a11y-song-leaderboard.json"),
    Run("song-leaderboard-text-225", "a11y-song-leaderboard.json", sizes="compact", mode="text-225"),
    Run("song-leaderboard-reduced-motion", "a11y-song-leaderboard.json", sizes="medium", mode="app-reduced",
        only="song-board-paging-keyboard"),
    # Song leaderboard states #197 changed (issue #511): the pinned row is its own UIA element (not a second list-row
    # ID), an empty board's header names no "0 entries" total, a contrast theme's footer plate keeps row text out of the
    # footer (Desert), and with motion off a trimmed row name shows in full as the row's keyboard-focus tool tip. (The
    # mode-only runs come first: generated_runs reads a file's last explicit run as its coverage.)
    Run("song-board-states-reduced", "a11y-song-board-states.json", sizes="medium", mode="app-reduced",
        only="song-board-name-tooltip"),
    Run("song-board-states-contrast", "a11y-song-board-states.json", mode="hc-desert",
        only="song-board-contrast-plate"),
    Run("song-board-states", "a11y-song-board-states.json"),
    Run("song-board-states-text-225", "a11y-song-board-states.json", sizes="compact", mode="text-225"),
    # The rows fade 40 epx above the footer at rest, mid-scroll and end, and cut hard under More Contrast and
    # Less Transparency (issue #93).
    Run("song-leaderboard-footer-fade", "a11y-board-footer-fade.json", only=SONG_BOARD_FOOTER_FADE),
    Run("song-leaderboard-footer-fade-text-225", "a11y-board-footer-fade.json", sizes="compact", mode="text-225",
        only=SONG_BOARD_FOOTER_FADE),
    # Full Rankings pinned row (issues #318, #466): pinned even on the player's own page; Narrator reads its rank,
    # Open your statistics or Jump to your position and Button; 40x40 pinned row and pager kept apart; title -> rows ->
    # pinned row -> pager order; Tab/Shift+Tab rows -> pinned row -> pager; Enter jumps to page 2 keeping focus on the
    # pinned row (now Open your statistics) and opens the profile; also with in-app Reduce Motion. (The partial
    # reduced-motion run comes first: generated_runs reads a file's last explicit run as its coverage.)
    Run("full-rankings-pinned-reduced-motion", "a11y-full-rankings.json", sizes="medium", mode="app-reduced", tabs=0,
        only="fr-pinned-jump-keyboard"),
    Run("full-rankings-pinned", "a11y-full-rankings.json"),
    Run("full-rankings-pinned-text-225", "a11y-full-rankings.json", sizes="compact", mode="text-225"),
    # Full Rankings pinned row's load gate (issues #270, #524): a Rank By or instrument reload drops it from UIA, the
    # reading order and Tab with the rows and pager (only "Busy Loading rankings, ProgressRing" is read; Tab goes from
    # Rank By to the title bar), then the new value returns as a 40x40 Button in rows -> pinned row -> pager order; a
    # page-only reload keeps it readable, focusable and reachable by Shift+Tab beside the ring. At 225% text, with in-app
    # Reduce Motion and with Windows' Animation effects off (the pinned row returns still).
    Run("full-rankings-swap", "a11y-full-rankings-swap.json", tabs=0),
    Run("full-rankings-swap-text-225", "a11y-full-rankings-swap.json", sizes="compact", mode="text-225", tabs=0),
    Run("full-rankings-swap-reduced", "a11y-full-rankings-swap.json", sizes="medium", mode="app-reduced", tabs=0),
    Run("full-rankings-swap-no-animations", "a11y-full-rankings-swap.json", sizes="medium", mode="no-animations",
        tabs=0),
    # A Leaderboards card's "your rank" row (issues #370, #493): outside the top ten it reads "Your rank, 40th. Jump to
    # your position" and Button, keeps 40x40 apart from View All and sits between the rows and View All in reading and
    # Tab order; Enter opens Full Rankings on the player's page with their row in view (also with in-app Reduce Motion)
    # and Back returns focus to it; inside the top ten the player's highlighted row opens the profile instead.
    Run("leaderboards-card-jump-reduced-motion", "a11y-leaderboards-card-jump.json", sizes="medium",
        mode="app-reduced", tabs=0, only="card-jump-row-keyboard"),
    Run("leaderboards-card-jump", "a11y-leaderboards-card-jump.json"),
    Run("leaderboards-card-jump-text-225", "a11y-leaderboards-card-jump.json", sizes="compact", mode="text-225"),
    # Search's All section titles (issues #348, #483): "Songs", "Players" and "Bands" read as text at heading level 2,
    # never Tab stops, each before its own rows and clear of them; Tab/Shift+Tab walk All -> songs -> players -> bands;
    # also with in-app Reduce Motion (the titles fade with their rows). The file's other pages stay generated runs.
    # (The partial reduced-motion run comes first: generated_runs reads a file's last explicit run as its coverage.)
    Run("search-sections-reduced-motion", "a11y-search.json", sizes="medium", mode="app-reduced",
        only=SEARCH_SECTIONS),
    Run("search-sections", "a11y-search.json", only=SEARCH_SECTIONS),
    Run("search-sections-text-225", "a11y-search.json", sizes="compact", mode="text-225", only=SEARCH_SECTIONS),
    # Search results that waited behind the spinner for a slow player search (issues #260, #521): Narrator reads the
    # named ring while no row or title is there, then the Level 2 "Songs" title before the 40+ epx row; focus stays in
    # the field and Tab reaches All and the row. Also with in-app Reduce Motion (the rows appear in place, no fade).
    Run("search-delayed-results-reduced-motion", "a11y-search.json", sizes="medium", mode="app-reduced",
        only=SEARCH_DELAYED_RESULTS),
    Run("search-delayed-results", "a11y-search.json", only=SEARCH_DELAYED_RESULTS),
    Run("search-delayed-results-text-225", "a11y-search.json", sizes="compact", mode="text-225",
        only=SEARCH_DELAYED_RESULTS),
    # Suggestions (issues #205, #513): each card is one Narrator list item named by its Level 2 title heading, its rows
    # 40+ epx Buttons and one Tab stop per card (Down/Up cross card boundaries, Tab/Shift+Tab between cards, Esc returns
    # to Filter); the filter's named Instruments/General Expanders read their state and help text, and Tab goes straight
    # from an expanded header to its first switch; the syncing and filtered-empty titles are Level 2 headings; and the
    # rival name pill switches to the neutral contrast role live (Desert paint check, medium only, so not at 225%).
    # The cards loaded after the first ten (issues #260, #521) arrive as whole headed list items read after the first
    # batch, with 40+ epx rows that Down/Up and Tab reach across the batch boundary: at default and 225% text in the
    # full runs, and first with in-app Reduce Motion and with Animation effects off (they appear in place, no fade).
    # (The partial motion-off runs come first: generated_runs reads a file's last explicit run as its coverage.)
    Run("suggestions-load-more-reduced-motion", "a11y-suggestions.json", sizes="medium", mode="app-reduced", tabs=0,
        only=SUGGESTIONS_LOAD_MORE),
    Run("suggestions-load-more-no-animations", "a11y-suggestions.json", sizes="medium", mode="no-animations", tabs=0,
        only=SUGGESTIONS_LOAD_MORE),
    # Row centre line (issue #654): a one-line row's art and metadata (season pill, rival pill) sit on the row's vertical
    # centre within 1 epx (assertmiddle), with or without the separator, at wide and at 225% text beside the title.
    Run("suggestions-row-centre-wide", "a11y-suggestions.json", sizes="wide", tabs=0, only=SUGGESTIONS_ROW_CENTRE),
    Run("suggestions-row-centre-text-225", "a11y-suggestions.json", sizes="medium,wide", mode="text-225", tabs=0,
        only=SUGGESTIONS_ROW_CENTRE),
    Run("suggestions", "a11y-suggestions.json"),
    Run("suggestions-text-225", "a11y-suggestions.json", sizes="compact", mode="text-225"),
    # Back from View All or a rival to cached Leaderboards and Rivals (issues #82, #276, #435): the opener and its card
    # stay put, focus returns to the opener, it reads "<name>, button" after its card and heading, keeps a 40 epx target,
    # and Tab/Shift+Tab continue from it; by keys (Enter, Alt+Left) and pointer (the title-bar Back).
    Run("back-keeps-place", "a11y-back-keeps-place.json"),
    Run("back-keeps-place-text-225", "a11y-back-keeps-place.json", sizes="compact", mode="text-225"),
    # On-demand split (issue #652, split-panes R7 Windows variant): a rival or a Song Detail board opens in the trailing
    # half (Close named, 40 epx, read after the list), Back from the pane returns focus to the opener row, and 225% text
    # pushes full width instead. Wide only: compact and medium never split.
    Run("split-panes", "a11y-split-panes.json", sizes="wide", tabs=0),
    Run("split-panes-text-225", "a11y-split-panes.json", sizes="wide", mode="text-225", tabs=0),
    # Wide columns (issue #653, pattern wide-columns R1/R2): Profile sections and Suggestions cards pair row-major in a
    # wide window at default text and reflow in place on resize, and the Item Shop grid fills a wide window. The
    # one-column pages also run in a wide window at 150% (the large-text threshold) and 225% text, where text size
    # alone keeps one column. (The partial run comes first: generated_runs reads a file's last explicit run as its
    # coverage.)
    Run("wide-columns-one-text-150", "a11y-wide-columns.json", sizes="wide", mode="text-150", only=WIDE_COLUMNS_ONE),
    Run("wide-columns", "a11y-wide-columns.json", sizes="compact,medium,wide"),
    Run("wide-columns-text-225", "a11y-wide-columns.json", sizes="compact,wide", mode="text-225"),
    # Reflow motion (issue #669, pattern reflow-motion): the Rivals split opens and closes and Suggestions, the Item
    # Shop grid and the Profile/Statistics sections narrow and widen with focus, reading order and target sizes kept
    # while the compositor moves them, and every reflow is instant with in-app Reduce Motion and with Animation effects
    # off (reflow_trace). The reflow-stop pages turn each motion setting off mid-move (normal mode only; the matrix
    # restores Animation effects). At 225% text Suggestions and Statistics stay one column. Wide only: compact never
    # splits.
    Run("reflow", "a11y-reflow.json", sizes="wide", tabs=0),
    Run("reflow-reduced", "a11y-reflow.json", sizes="wide", mode="app-reduced", tabs=0),
    Run("reflow-no-animations", "a11y-reflow.json", sizes="wide", mode="no-animations", tabs=0),
    Run("reflow-text-225", "a11y-reflow.json", sizes="wide", mode="text-225", tabs=0),
    # Quick Links landings on Settings and Leaderboards (issues #51, #416): entry name and current section, 40 epx
    # entry and items, keyboard order, the jump announcement, heading landing inset and focus. The wide pane page
    # (scale-100/150 modes) stays in the host matrix.
    Run("quick-links-landing", "a11y-quick-links-landing.json", tabs=0),
    Run("quick-links-landing-text-225", "a11y-quick-links-landing.json", sizes="compact", mode="text-225", tabs=0),
    # Header flyouts open in the app window (issue #534): Leaderboards and Full Rankings Rank By, Quick Links, the
    # profile flyout and Notifications scan with no windowed PopupHost finding (windows-accessibility.md open item 8).
    Run("popups", "a11y.json", only=POPUP_PAGES),
    Run("popups-text-225", "a11y.json", sizes="compact", mode="text-225", only=POPUP_PAGES),
    # The Item Shop Filters flyout (issues #19, #428): heading, New / Available / Leaving Tomorrow switch phrases and
    # state, Filters applied, the song count and empty state, title -> switches -> Reset order, 40 epx Reset, text scaling.
    Run("shop-filter", "a11y-shop-filter.json"),
    Run("shop-filter-text-225", "a11y-shop-filter.json", sizes="compact", mode="text-225"),
    # Its keyboard journey (#428 review): Enter opens on New, Space toggles, Tab/Shift+Tab walk the switches to Reset,
    # Enter resets, Esc closes with focus back on Filters and "Filters applied", at default and 225% text.
    Run("shop-filter-keyboard", "a11y-keyboard.json", tabs=0, only=SHOP_FILTER_KEYBOARD),
    Run("shop-filter-keyboard-text-225", "a11y-keyboard.json", sizes="compact", mode="text-225", tabs=0,
        only=SHOP_FILTER_KEYBOARD),
    # Item Shop offers (issues #224, #516): tile phrases (title, artist · year, Leaving Tomorrow / New, Button), the
    # List/Grid toggle's name, 40 epx target and level with Filter (never wrapped under the tiles at default text, kept
    # clear of them at 225%), hidden at compact, empty, failed and Shop-hidden; Enter/Space switch the layout with focus
    # kept on the toggle; only the active ring reads "Busy Loading Item Shop"; and the Leaving pill follows a live
    # contrast switch (Desert paint check, medium only). Also with the app's Reduce Motion (the reveal is instant).
    # (The partial reduced-motion run comes first: generated_runs reads a file's last explicit run as its coverage.)
    Run("shop-offers-reduced", "a11y-shop-offers.json", sizes="medium", mode="app-reduced",
        only="shop-offers-view-toggle"),
    Run("shop-offers", "a11y-shop-offers.json"),
    Run("shop-offers-text-225", "a11y-shop-offers.json", mode="text-225"),
    # The pinned "your band" row on a song's full Duos/Trios/Quads board (issues #306, #461): Narrator phrases for
    # Jump / Open band, 40 epx targets, rows -> pin -> pager order, Tab/Enter jump clear of the pin, size switch,
    # no-player and reduced-motion states.
    Run("song-band-pinned", "a11y-song-band-pinned.json", tabs=0),
    Run("song-band-pinned-text-225", "a11y-song-band-pinned.json", sizes="compact", mode="text-225", tabs=0),
    Run("song-band-board", "a11y-song-band-leaderboard.json", tabs=0),
    Run("song-band-board-text-225", "a11y-song-band-leaderboard.json", sizes="compact", mode="text-225", tabs=0),
    # The shared song leaderboard header on the band and solo boards (issues #317, #465): one 40+ epx button named by
    # every visible line, title heading 1, header -> size switcher -> rows order, Tab/Shift+Tab/Right and Enter to Song
    # Details, the total leaving on a slow size switch, and no button for an unresolved song; again at 225% text.
    Run("song-leaderboard-header", "a11y-song-leaderboard-header.json", tabs=0),
    Run("song-leaderboard-header-text-225", "a11y-song-leaderboard-header.json", sizes="compact", mode="text-225",
        tabs=0),
    # The song board's pinned "your score" row joins the rows' load gate (issues #295, #457): on the first load only the
    # spinner is exposed; on a Filter Invalid Scores reload the pinned row leaves UIA and the Tab order (Tab goes from
    # the header to Next) while the header and pager stay; then it reads "Your rank, 1st. Open your statistics. …,
    # button" after the rows, keeps a 40 epx target and the purple fill, and takes Tab focus after the rows. At 225%
    # text, with in-app Reduce Motion and with Windows' Animation effects off (the pinned row arrives still).
    Run("song-pinned-reveal", "a11y-song-pinned-reveal.json", tabs=0),
    Run("song-pinned-reveal-text-225", "a11y-song-pinned-reveal.json", sizes="compact", mode="text-225", tabs=0),
    Run("song-pinned-reveal-reduced", "a11y-song-pinned-reveal.json", sizes="medium", mode="app-reduced", tabs=0),
    Run("song-pinned-reveal-no-animations", "a11y-song-pinned-reveal.json", sizes="medium", mode="no-animations",
        tabs=0),
    # Selected-row reveal (issues #323, #470): Song Details' "your score" row and the Leaderboards card's "your rank" row
    # open their boards by keyboard and the reveal centres the player's row after its entrance: "Your rank, …" names,
    # purple fill, a 40 epx target clear of the pinned row, rows -> pinned row -> pager order, Down/Up/Tab in place.
    # With motion off (app-reduced, no-animations) the reveal still lands on the row and nothing moves.
    Run("selected-row-reveal", "a11y-selected-row-reveal.json", tabs=0),
    Run("selected-row-reveal-text-225", "a11y-selected-row-reveal.json", sizes="compact", mode="text-225", tabs=0),
    Run("selected-row-reveal-reduced", "a11y-selected-row-reveal.json", sizes="medium", mode="app-reduced", tabs=0),
    Run("selected-row-reveal-no-animations", "a11y-selected-row-reveal.json", sizes="medium", mode="no-animations",
        tabs=0),
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
    # Player profile title row without the avatar card (issues #97, #446): the name is a non-focusable Level 1 heading
    # with no PersonPicture, then Select/Switch/Deselect or the paused notice, then Overview; 40 epx actions, keyboard
    # order and focus return, and Quick Links wrapping under the action at 225% text (#285).
    Run("profile-title", "a11y-profile-title.json", tabs=0, only=PROFILE_TITLE_FIXTURE),
    Run("profile-title-text-225", "a11y-profile-title.json", sizes="compact", mode="text-225", tabs=0,
        only=PROFILE_TITLE_FIXTURE),
    # Real-control First Run demos (issues #380, #498): Sort Songs, the Score History chart and Suggestions' auto-scroll
    # are built from the page's own controls (census HelpText) yet stay out of the control view and the Tab order (slide
    # -> pip -> Next -> Back -> Close, 40x40 Close); the auto-scroll runs with its edge fades, pauses while minimized and
    # holds at the top with in-app Reduce Motion or Windows' Animation effects off; with Windows' transparency effects
    # off, or the app's Less Transparency or More Contrast, it scrolls with hard clipped edges (fade=off, scroll-edge R7).
    Run("first-run-real-demos", "a11y-first-run-real-demos.json"),
    Run("first-run-real-demos-text-225", "a11y-first-run-real-demos.json", sizes="compact", mode="text-225"),
    Run("first-run-real-demos-no-animations", "a11y-first-run-real-demos.json", sizes="compact", mode="no-animations",
        only="frrd-infinite-scroll-static"),
    Run("first-run-real-demos-no-transparency", "a11y-first-run-real-demos.json", sizes="compact",
        mode="no-transparency", only="frrd-infinite-scroll-no-transparency"),
    # Songs live publication refresh (issue #616, load-transition R9): a loopback /api/ws pushes publication_changed and
    # the filtered, Artist-sorted list refreshes in place with scores (no paused notice), Narrator hears "Loading new
    # scores" once, focus parks on Songs search while the rows hide and returns to the first row, under app Reduce Motion
    # and at 200% and 225% text too.
    Run("songs-publication-refresh", "a11y-songs-publication-refresh.json", sizes="medium", tabs=0,
        only="songs-publication-refresh"),
    Run("songs-publication-refresh-reduced", "a11y-songs-publication-refresh.json", sizes="medium", mode="app-reduced",
        tabs=0, only="songs-publication-refresh-modes"),
    Run("songs-publication-refresh-text-200", "a11y-songs-publication-refresh.json", sizes="medium", mode="text-200",
        tabs=0, only="songs-publication-refresh-modes"),
    Run("songs-publication-refresh-text-225", "a11y-songs-publication-refresh.json", sizes="medium", mode="text-225",
        tabs=0, only="songs-publication-refresh-modes"),
    # Full boards as one grouped card (issue #543): song board, Full Rankings, Band Rankings and the song band board rows
    # touch (0 epx), each stays one 40+ epx Button stop in visual order, rows -> pinned row -> pager, Up/Down and Tab.
    Run("grouped-boards", "a11y-grouped-boards.json", tabs=0),
    Run("grouped-boards-text-225", "a11y-grouped-boards.json", sizes="compact", mode="text-225", tabs=0),
    Run("grouped-boards-reduced", "a11y-grouped-boards.json", sizes="medium", mode="app-reduced", tabs=0,
        only="grouped-song-board-one-card"),
    # Feedback form (issues #64, #634): every state, plus the busy status (fields fade out; a centred named ring, phase
    # title, upload bar or filing subtitle fade in; each title announced) with the app's Reduce Motion (no fades).
    Run("feedback", "a11y-feedback.json", tabs=0),
    Run("feedback-text-225", "a11y-feedback.json", sizes="compact", mode="text-225", tabs=0),
    Run("feedback-reduced", "a11y-feedback.json", sizes="medium", mode="app-reduced", tabs=0,
        only="feedback-sending,feedback-uploading-media,feedback-filing,feedback-error"),
    # Rivals lists as one card (issue #603, rival-rows R3, R6): Rivalry and All Rivals rows touch (0 epx), each stays one
    # named 40+ epx stop in visual order (iOS-design song rows read title, artist, instrument, ranks, who leads), Up/Down.
    Run("rivals-cards", "a11y-rivals-cards.json", tabs=0),
    Run("rivals-cards-text-225", "a11y-rivals-cards.json", sizes="compact", mode="text-225", tabs=0),
    Run("rival-titles", "a11y-rival-titles.json", tabs=0),
    Run("rival-titles-text-225", "a11y-rival-titles.json", sizes="compact", mode="text-225", tabs=0),
    # Combo boards (issue #602): the OG band combo card is a level-2 heading group before Lead, its View All Rankings is
    # a 40+ epx Button named with the board label, Enter opens combo Full Rankings (no instrument picker, combo title,
    # pinned combo rank) and Back restores focus; rows stay 40+ epx stops with Down between them.
    Run("combo-boards", "a11y-combo-boards.json", tabs=0),
    Run("combo-boards-text-225", "a11y-combo-boards.json", sizes="compact", mode="text-225", tabs=0),
    # Stat tiles (issue #651, stat-tile-grid R6): a linked tile's value and label are centred on the whole card, not on
    # the space left of its chevron, at every size and at 225% text; the tile stays a 40+ epx button in grid order.
    Run("stat-tile-centre", "a11y-stat-tile-centre.json", tabs=0),
    Run("stat-tile-centre-text-225", "a11y-stat-tile-centre.json", mode="text-225", tabs=0),
    # Long leaderboard names (issues #292, #455): on Full Rankings and the Leaderboards overview a name too wide for its
    # column scrolls on one line while one that fits stays still, the row reads the whole name once, stays a 40+ epx
    # stop in visual order with Up/Down between rows; at 150%, 200% and 225% text the name wraps and the row grows,
    # still, even with Reduce Motion, while every row and a loading card's placeholders keep the section's shared name
    # budget (one pitch for short, 16-character and placeholder rows); at 100% under the app's Reduce Motion (in the
    # normal run) and Windows' Animation effects off it stops on an ellipsis.
    Run("leaderboard-names", "a11y-leaderboard-names.json", tabs=0),
    Run("leaderboard-names-text-150", "a11y-leaderboard-names.json", mode="text-150", tabs=0),
    Run("leaderboard-names-text-200", "a11y-leaderboard-names.json", mode="text-200", tabs=0),
    Run("leaderboard-names-text-225", "a11y-leaderboard-names.json", mode="text-225", tabs=0),
    Run("leaderboard-names-no-animations", "a11y-leaderboard-names.json", sizes="compact", mode="no-animations",
        tabs=0),
    # Song Detail Score History as one card (issue #588): selector -> heading -> subtitle -> chart, then the best scores
    # as in-card rows that touch (0 epx) in score order, ending on a 40+ epx View All Scores named for the chart.
    Run("score-history-card", "a11y-score-history-card.json", tabs=0),
    Run("score-history-card-text-225", "a11y-score-history-card.json", sizes="compact", mode="text-225", tabs=0),
    # Preview cards (issue #643): each Leaderboards board (instrument, combo and Duos/Trios/Quads) and each Song Detail
    # instrument and band preview is one card whose rows touch (0 epx) as in-card slices in rank order, ending on a
    # 40+ epx View All inside the card; Tab returns to it from the rows.
    Run("preview-cards", "a11y-preview-cards.json", tabs=0),
    Run("preview-cards-text-225", "a11y-preview-cards.json", sizes="compact", mode="text-225", tabs=0),
    # Song Detail's Score History chart (issues #198, #512): Left/Right move focus between bar ToggleButtons and select
    # them, at 225% text the axis titles keep clear of the measured tick labels and date bands, under Desert the bars
    # paint the theme's Window/WindowText/Highlight (also after a live switch), and the syncing and failed states expose
    # a named 40+ epx Retry after the chart's heading.
    Run("score-history-chart", "a11y-score-history-chart.json", tabs=0),
    Run("score-history-chart-text-225", "a11y-score-history-chart.json", sizes="compact", mode="text-225", tabs=0),
    Run("score-history-chart-contrast", "a11y-score-history-chart.json", sizes="compact", mode="hc-desert", tabs=0,
        only="history-chart-contrast"),
    # Profile Bands groups as one card each (issue #596): rows touch, 40+ epx stops named without the band size, the
    # purple View All Bands (N) inside the card, header -> rows -> View All order, Down between rows and Tab to View All.
    Run("profile-bands", "a11y-profile-bands.json", tabs=0),
    Run("profile-bands-text-225", "a11y-profile-bands.json", sizes="compact", mode="text-225", tabs=0),
    # Settings' Experimental Ranks toggle (issue #541): enabled, off by default, named and Space-toggled; turning it on
    # shows "Rank by: Total Score, button" (40 epx) on Leaderboards and off hides it again; with it off a saved or
    # deep-linked experimental metric leaves no Rank By on Leaderboards, Full Rankings or Band Rankings.
    Run("experimental-ranks", "a11y-experimental-ranks.json", tabs=0),
    Run("experimental-ranks-text-225", "a11y-experimental-ranks.json", sizes="compact", mode="text-225", tabs=0),
    # Band Detail during a scrape freeze (issue #554, empty-error-states R9): after a verified read, the revisit's
    # stamped 503s keep history, Best and Worst rows with no inline status (history -> Five Best -> row -> Five Worst
    # -> row order, Narrator row names, 40 epx target); a cold frozen /songs shows "Scores are updating" + Retry Now.
    Run("band-freeze", "a11y-band-freeze.json", tabs=0),
    Run("band-freeze-text-225", "a11y-band-freeze.json", sizes="compact", mode="text-225", tabs=0),
    # Loading placement (issues #431, #649, load-transition R1): each page's spinner is centred in its content region,
    # named "Busy Loading …, ProgressRing", not focusable and read after the header tools; Leaderboards' Quick Links
    # entry and pane stay out of UIA until the cards arrive, and stay available during an F5 reload. The text-225 run
    # adds medium for the medium-only reload pages, so both Leaderboards pages run at both text sizes.
    Run("loading-placement", "a11y-loading-placement.json", tabs=0),
    Run("loading-placement-text-225", "a11y-loading-placement.json", mode="text-225", tabs=0),
    # Score History's instrument switch with motion off (issues #61, #423): the instant swap (new chart named within
    # 0.1 s, card and page held) by pointer and keys, under in-app Reduce Motion and Windows' Animation effects off,
    # the two paths that turn the fade off. Its other pages run as the generated a11y-history-swap-normal/-text-225.
    Run("a11y-history-swap-app-reduced", "a11y-history-swap.json", mode="app-reduced", only=HISTORY_SWAP_REDUCED),
    Run("a11y-history-swap-no-animations", "a11y-history-swap.json", mode="no-animations", only=HISTORY_SWAP_REDUCED),
    # Paths swap (issues #70, #430): mid-swap the old chart leaves UIA, "Busy Loading path, ProgressRing" sits between
    # the selectors and Close, the selectors stay enabled and show the new value, "Loading …" then "… loaded" are
    # announced; Image <-> Text; keyboard switches (compact and wide selector boxes, #650) keep focus on the selector; 40 epx zoom,
    # selectors and Close; mid-swap Axe scans; at 225% text, with in-app Reduce Motion and with Animation effects off.
    # paths-selectors-swap-* (#571) resize the window across the 900 epx selector swap with the dialog open: the dialog
    # follows the window, a focused circle's keyboard tooltip and a hovered circle's pointer tooltip close with the
    # collapsed set, and focus moves to the counterpart (circle <-> instrument box) both ways, with Axe scans.
    # The compact Instrument ComboBox (issues #88, #439) opens to "Lead, list item, selected", Bass, Drums, Tap Vocals
    # (no Karaoke), each a 40 epx option, and switches by pointer and Alt+Down/Up/Enter with focus kept, Axe-scanned open.
    # Sized for its longest option (issues #280, #526), it and its siblings keep their place and width on one line when
    # the selection changes to the longest name (Tap Vocals) and back.
    # The compact Display ComboBox at the row's right edge keeps its whole keyboard focus ring (issues #269, #523): the
    # dialog content is the dialog less its padding and border, so the ring's right, top and bottom match its left side.
    Run("paths-swap", "a11y-paths-swap.json", sizes="compact,medium,wide"),
    Run("paths-swap-text-225", "a11y-paths-swap.json", sizes="compact,wide", mode="text-225"),
    Run("paths-swap-no-animations", "a11y-paths-swap.json", sizes="compact", mode="no-animations"),
    # Paths selector surfaces (issue #650, surface-materials R4): the wide Difficulty and Display boxes read as named
    # combo boxes with their value, 40 epx, in instrument -> Difficulty -> Display -> zoom -> Close order, on the
    # translucent card surface (default and 225% text); with Windows' Transparency effects off every box (wide, and the
    # compact Instrument/Difficulty/Display row) is one opaque fill with a visible stroke; under Desert the boxes paint
    # system colours. Each page picks its own mode and size.
    Run("paths-selectors", "a11y-paths-selectors.json", sizes="wide", tabs=0),
    Run("paths-selectors-text-225", "a11y-paths-selectors.json", sizes="wide", mode="text-225", tabs=0),
    Run("paths-selectors-no-transparency", "a11y-paths-selectors.json", sizes="compact,wide", mode="no-transparency",
        tabs=0),
    Run("paths-selectors-contrast", "a11y-paths-selectors.json", sizes="wide", mode="hc-desert", tabs=0),
    # Paths chart (issues #87, #279, #438): "Path chart, pane" holds "<instrument> <difficulty> CHOpt path, image" in
    # zoom -> chart -> image -> Close order, centred in its scroller with no scroll bar at rest, zoomed (keyboard Enter on
    # Zoom in, then End/Home on the focused chart) and back at 100% with Zoom out unavailable and focus moved on to Zoom
    # in, and after Image <-> Text. With Windows' "Always show scrollbars" on (#279's exception, issue #525) the chart
    # shows its bar instead, still centred, the bar never a Tab stop, at default and 225% text.
    Run("paths-chart", "a11y-paths-chart.json", sizes="compact,medium,wide", tabs=0),
    Run("paths-chart-text-225", "a11y-paths-chart.json", sizes="compact,wide", mode="text-225", tabs=0),
    Run("paths-chart-scrollbars", "a11y-paths-chart.json", sizes="compact,medium,wide", mode="scrollbars-always", tabs=0,
        only="paths-chart-scrollbars"),
    Run("paths-chart-scrollbars-text-225", "a11y-paths-chart.json", sizes="compact,wide",
        mode="scrollbars-always+text-225", tabs=0, only="paths-chart-scrollbars"),
    # Paths text table (issues #223, #515): "Path table, pane" (a Tab stop that keeps focus on End/Home) holds one
    # "Activation n: …, group" per card in selectors -> table -> cards -> Close order, with the column captions and
    # values Raw (read once), the compact stack and wide grid with values apart; a live Desert switch repaints the frets
    # and Overdrive bar in system colours and refits the dialog so the display selector is not clipped, and back.
    Run("paths-text-contrast", "a11y-paths-text.json", sizes="compact", mode="hc-desert", tabs=0, only="paths-text"),
    Run("paths-text", "a11y-paths-text.json", sizes="compact,medium,wide", tabs=0),
    Run("paths-text-text-225", "a11y-paths-text.json", sizes="compact,wide", mode="text-225", tabs=0),
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
        # A run of every page covers the file even when another run (e.g. a reduced-motion one) picks some pages.
        if not run.only or (run.pages in covered and covered[run.pages] is None):
            covered[run.pages] = None
        else:
            covered[run.pages] = covered.get(run.pages, set()) | set(run.only.split(","))
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


def run_weight(run: Run) -> int:
    """A run's shard weight: the page × size combinations it executes (at least 1).

    A run without ``only`` executes every page of its file, so it weighs its file's page count, not 1 (#571: the
    seventh shard ran past the 55-minute job limit when whole-file runs counted as one page each).
    """
    sizes = run.sizes.split(",")
    return max(1, sum(len(a11y_matrix.page_sizes(page, sizes, run.mode)) for page in run_pages(run)))


def shard_runs(runs: list[Run], shard: int, shards: int) -> list[Run]:
    """The runs of one 1-based shard: heaviest first onto the lightest shard, so the shards are disjoint and balanced."""
    weighed = sorted(((run_weight(run), run) for run in runs), key=lambda item: (-item[0], item[1].name))
    buckets: list[list[Run]] = [[] for _ in range(shards)]
    weights = [0] * shards
    for weight, run in weighed:
        index = min(range(shards), key=lambda candidate: (weights[candidate], candidate))
        buckets[index].append(run)
        weights[index] += weight
    return buckets[shard - 1]


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
    runs = shard_runs(runs, args.shard, args.shards)
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
