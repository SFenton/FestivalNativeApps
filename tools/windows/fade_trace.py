"""Load-transition fade checks for the Windows UI journeys (issues #260 and #323, pattern ``load-transition``).

With ``--perf-log`` the app's ``FadeIn`` stagger (``windows/Festival.App/Controls/FadeIn.cs``) writes one line per
re-arm and one per row it fades; one per entrance element (a page section or card, a board's pinned row) it schedules
with an entrance; one when a scroll during the load entrance rushes it (``rushed`` pending fades started at once, web
``useStaggerRush``; ``kept`` pending fades of the entrance it did not reach, only ever an appended batch's) and one
per entrance element that rush started early, or one when a scroll after the entrance closes it; one when a
selected-row reveal holds the rows below the first screen for its automatic scroll, and one when that reveal runs;
and one per row realized after a rush that a purely time-based window would have faded but the rush let appear in
place (pattern R5); never for a row that just appears otherwise. ``list`` is the entrance's owner (a stagger list, or
the page scroller of a page entrance) and ``at`` the app's monotonic clock (ms)::

    fade-arm list=CardList start=10 at=5120
    fade-play list=CardList index=10 delay=125 motion=1 at=5121
    fade-enter list=RowsRepeater target=SpotlightPanel delay=125 motion=1 at=5122
    fade-early list=Scroller target=BandBoards left=830 at=5600
    fade-rush list=CardList start=0 rushed=3 kept=0 since=420 at=5600
    fade-close list=CardList start=0 since=2600 at=7800
    fade-hold list=RowsRepeater held=8 wait=1650 at=5130
    fade-reveal list=RowsRepeater index=17 wait=1650 scrolled=1 motion=1 at=6780
    fade-skip list=CardList index=6 at=5700

A journey drives the app in phases and judges only the lines each phase appended, so it can prove that a page fades
the rows visible at load, that a scroll right after the load rushes the entrance so the rows it realizes fade in
together (never staggered, never replayed), that every entrance element belongs to its entrance and a rush starts it
if it is still pending (:func:`check_entrance_rush`), that a selected-row reveal rushes its board before it scrolls
(:func:`check_reveal`), that an appended batch fades only its own new rows, that scrolling away and back replays
nothing, and that rows held behind a spinner fade once when it clears. :data:`WIRING` lists the page calls these
journeys exercise; ``tests/test_fade_trace.py`` checks them in CI, where WinUI journeys cannot run.

Used by ``suggestions_journey.py`` (scenario ``fade``), ``search_journey.py`` (journey ``fade-delayed-results``) and
``fade_journey.py`` (Song Detail → player score → selected-row reveal, the boards' pinned rows, Player Profile).
"""

from __future__ import annotations

import re
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
LINE = re.compile(r"^fade-(?P<kind>arm|play|enter|early|rush|close|hold|reveal|skip) list=(?P<list>\S+)"
                  r"(?P<rest>(?: \w+=[^\s=]+)*)\s*$")
NUMBER = re.compile(r"-?\d+")
ARM_WINDOW_MS = 1000
"""``FadeInTiming.ArmWindow``: how long after an arm newly realized rows may still fade."""
CLOCK_SLOP_MS = 2
"""Rounding of the trace's millisecond values: a fade due within this of a rush counts as started."""

#: ``(file, regex, what breaks without it)``: the page wiring behind each fade journey assertion.
WIRING: tuple[tuple[str, str, str], ...] = (
    ("windows/Festival.App/Pages/SuggestionsPage.xaml.cs",
     r"CardsAdded\s*\+=\s*\(_,\s*(\w+)\)\s*=>\s*FadeIn\.Restagger\(CardList,\s*\1\)",
     "Suggestions batches after the first never fade (journey suggestions fade: load-more)"),
    ("windows/Festival.App/Pages/SearchPage.xaml.cs",
     r"SectionShown\s*\+=\s*OnSectionShown",
     "Search rows held behind the spinner appear without a fade (journey fade-delayed-results)"),
    ("windows/Festival.App/Pages/SearchPage.xaml.cs",
     r"FadeIn\.Restagger\(section switch\s*\{\s*SearchScope\.Songs\s*=>\s*SongsList,\s*SearchScope\.Players\s*=>\s*PlayersList,\s*_\s*=>\s*BandsList",
     "Search rows held behind the spinner appear without a fade (journey fade-delayed-results)"),
    ("windows/Festival.App/Controls/FadeIn.cs",
     r"viewer\.ViewChanging\s*\+=\s*OnViewChanging",
     "a scroll no longer rushes a list's load entrance (journey suggestions fade: load-scroll)"),
    ("windows/Festival.App/Controls/FadeIn.cs",
     r"ScrollViewer own => own,",
     "a page entrance no longer watches its own scroller, so an early drag or Quick Links jump never rushes it "
     "(journey fade profile-quick-links, song-detail)"),
    ("windows/Festival.App/Controls/FadeIn.cs",
     r"OnScrolled\(list,\s*arm,\s*arm\.Scrolled\(x,\s*y,\s*now\),\s*now\)",
     "rows realized by a scroll the scroller hasn't reported yet keep their stagger (journey suggestions fade: load-scroll)"),
    ("windows/Festival.App/Controls/FadeIn.cs",
     r"OnScrolled\(owner,\s*arm,\s*arm\.Scrolled\(x,\s*y,\s*now\),\s*now\);\s*\n\s*if \(arm\.Entrance\(",
     "a section realized by a scroll the scroller hasn't reported yet keeps its delay (journey fade song-detail)"),
    ("windows/Festival.App/Controls/FadeIn.cs",
     r"case ArmScroll\.Rushed:\s*\n\s*TraceRush\(owner,\s*arm,\s*RushPending\(owner,\s*arm,\s*now,\s*out var kept\)",
     "pending fades keep trickling in after a scroll instead of fading in together (issue #323, load-scroll)"),
    ("windows/Festival.App/Controls/FadeIn.cs",
     r"if \(fade\.Arm != arm\) continue;\s*\n\s*if \(!arm\.RushReaches\(fade\.Index\)\)",
     "a rush no longer starts its entrance's pending pinned row or page sections (journey fade boards, profile)"),
    ("windows/Festival.App/Pages/SongDetailPage.xaml.cs",
     r"FadeIn\.BeginEntrance\(Scroller\);",
     "Song Detail sections and cards keep their stagger after an early scroll or Quick Links jump (issue #323)"),
    ("windows/Festival.App/Pages/SongDetailPage.xaml.cs",
     r"Enter\(UIElement element,\s*TimeSpan natural\)\s*=>\s*FadeIn\.Enter\(Scroller,\s*element,\s*natural\)",
     "Song Detail sections and cards fade outside the page entrance, so a scroll cannot rush them (issue #323)"),
    ("windows/Festival.App/Pages/SongDetailPage.xaml.cs",
     r"Enter\(args\.Element,",
     "Song Detail leaderboard cards realized by an early scroll pop in or fade late (load-transition R5)"),
    ("windows/Festival.App/Controls/PlayerProfileView.xaml.cs",
     r"FadeIn\.BeginEntrance\(Scroller\);(?:\s*\n\s*FadeIn\.Enter\(Scroller,\s*(?:TitleRow|OverviewHeading|OverviewGrid),[^\n]*){3}",
     "Player Profile's title and Overview keep their stagger after an early scroll or Quick Links jump (issue #323)"),
    ("windows/Festival.App/Pages/LeaderboardsSongPage.xaml.cs",
     r"FadeIn\.Enter\(RowsRepeater,\s*SpotlightPanel,\s*PinnedRowReveal\.RevealDelay\)",
     "the song leaderboard's pinned row keeps its delay while a scroll rushes the rows (journey fade boards)"),
    ("windows/Festival.App/Pages/BandsSongLeaderboardPage.xaml.cs",
     r"FadeIn\.Enter\(Rows,\s*SpotlightPanel,\s*PinnedRowReveal\.RevealDelay\)",
     "the song band leaderboard's pinned row keeps its delay while a scroll rushes the rows (journey fade boards)"),
    ("windows/Festival.App/Pages/LeaderboardsFullRankingsPage.xaml.cs",
     r"FadeIn\.Enter\(RowsRepeater,\s*FooterSpotlight,\s*PinnedRowReveal\.RevealDelay\)",
     "Full Rankings' pinned row keeps its delay while a scroll rushes the rows (journey fade boards)"),
    ("windows/Festival.App/Pages/LeaderboardsSongPage.xaml.cs",
     r"SelectedRowReveal\.Start\(RowsRepeater,",
     "the song leaderboard jumps to the player's row before it has faded in, or not at all (issue #323)"),
    ("windows/Festival.App/Pages/LeaderboardsFullRankingsPage.xaml.cs",
     r"SelectedRowReveal\.Start\(RowsRepeater,",
     "Full Rankings jumps to the player's row before it has faded in (issue #323)"),
    ("windows/Festival.App/Pages/BandsSongLeaderboardPage.xaml.cs",
     r"SelectedRowReveal\.Start\(Rows,",
     "the song band leaderboard jumps to the band's row before it has faded in (issue #323)"),
)

DELAYED_PLAY = re.compile(r"FadeIn\.Play\([^()]*(?:\([^()]*\)[^()]*)*,")
"""A direct ``FadeIn.Play(element, delay)``: a delayed fade outside any entrance, which no scroll can rush."""


def delayed_play_problems(root: Path = ROOT) -> list[str]:
    """Every delayed fade must belong to an entrance (``FadeIn.Enter``), so no Windows source may play one directly.

    Args:
        root: Repository root.

    Returns:
        One message per direct delayed play.
    """
    problems = []
    for path in sorted((root / "windows").rglob("*.cs")):
        if any(part in ("bin", "obj") for part in path.relative_to(root).parts):
            continue
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not line.lstrip().startswith("//") and DELAYED_PLAY.search(line):
                problems.append(f"{path.relative_to(root).as_posix()}:{number}: delayed FadeIn.Play outside an "
                                "entrance; use FadeIn.Enter(owner, element, delay) so a scroll can rush it")
    return problems

# region Parsing


@dataclass(frozen=True)
class FadeEvent:
    """One ``fade-*`` perf-log line."""

    kind: str
    """``arm``, ``play``, ``enter``, ``early``, ``rush``, ``close``, ``hold``, ``reveal`` or ``skip``."""
    list: str
    """Entrance owner: list or page scroller name (``x:Name``, else AutomationId)."""
    values: dict[str, int | str] = field(default_factory=dict, compare=False)
    """Numeric values (``start``, ``index``, ``delay``, ``rushed``, ``kept``, ``at`` ms, …) and ``target`` names."""


def parse(lines: list[str]) -> list[FadeEvent]:
    """Parse the ``fade-*`` lines of a perf log, ignoring everything else.

    Args:
        lines: Perf-log lines.

    Returns:
        Fade events in log order.
    """
    events = []
    for line in lines:
        match = LINE.match(line)
        if match:
            pairs = (pair.partition("=") for pair in match["rest"].split())
            values = {key: int(value) if NUMBER.fullmatch(value) else value for key, _, value in pairs}
            events.append(FadeEvent(match["kind"], match["list"], values))
    return events


def plays(events: list[FadeEvent], list_id: str) -> list[int]:
    """Row indices that faded on one list, in order."""
    return [e.values["index"] for e in events if e.kind == "play" and e.list == list_id]


def arms(events: list[FadeEvent], list_id: str) -> list[int]:
    """Batch starts the list armed, in order."""
    return [e.values["start"] for e in events if e.kind == "arm" and e.list == list_id]

# endregion

# region Checks (each returns failure messages; empty passes)


def check_load(events: list[FadeEvent], list_id: str) -> list[str]:
    """The rows visible at load fade once each, staggered from the first row.

    Args:
        events: Events of the phase that loaded the list.
        list_id: List name.

    Returns:
        Failures.
    """
    played = plays(events, list_id)
    if not played:
        return [f"{list_id}: no row faded in at load"]
    failures = []
    if sorted(played) != list(range(len(played))):
        failures.append(f"{list_id}: load faded rows {played}, expected each of 0..{len(played) - 1} once")
    return failures


def check_batch(events: list[FadeEvent], list_id: str) -> list[str]:
    """An appended batch fades only its own rows; rows revealed before it never fade again.

    The batch start comes from the phase's re-arm (incremental loads that cascade within the stagger window merge
    into the reveal they follow, so the first batch's size is not fixed).

    Args:
        events: Events of the phase that appended the batch.
        list_id: List name.

    Returns:
        Failures.
    """
    starts = [start for start in arms(events, list_id) if start > 0]
    if not starts:
        return [f"{list_id}: no re-arm for an appended batch (arms {arms(events, list_id)})"]
    failures = check_only_new(events, list_id)
    played = plays(events, list_id)
    if not [i for i in played if i >= min(starts)]:
        failures.append(f"{list_id}: no row of the batch at {min(starts)} faded in")
    if len(set(played)) != len(played):
        failures.append(f"{list_id}: a row faded twice: {played}")
    return failures


def check_only_new(events: list[FadeEvent], list_id: str) -> list[str]:
    """Scrolling replays nothing: every fade belongs to a batch armed in this phase, at or after its start.

    Args:
        events: Events of a phase that only scrolled (it may still append a batch).
        list_id: List name.

    Returns:
        Failures.
    """
    start = None
    replayed = []
    for event in (e for e in events if e.list == list_id):
        if event.kind == "arm":
            start = event.values["start"]
        elif event.kind == "play" and (start is None or event.values["index"] < start):
            replayed.append(event.values["index"])
    return [f"{list_id}: rows already shown faded again while scrolling: {replayed}"] if replayed else []


def check_load_then_scroll(events: list[FadeEvent], list_id: str, window_ms: int = ARM_WINDOW_MS) -> list[str]:
    """R5 (issue #323): a scroll right after the load rushes the entrance, so the rest fades in together.

    The phase loads the list and scrolls it at once, with no wait in between. Before the first ``fade-rush`` the
    load must fade its first screen (:func:`check_load`). The scroll must rush the entrance: a ``fade-close`` instead
    means the scroll came after the entrance had finished, or (inside the arm's window) that the rush is gone. After
    the rush every fade of an old row must start at once (``delay=0``: the rows the scroll realizes fade in together,
    never staggered), except the rows of a batch the rush kept (its ``start``: a batch appended while the load
    entrance ran) or appended later (Suggestions' load-more re-arm); a reload arm from 0 licenses no old row. The run
    must prove something: the rush started pending fades (``rushed`` > 0), a realized row faded at once, or a row
    realized after the rush appeared in place (``fade-skip``).

    Args:
        events: Events of the phase that loaded the list and scrolled it immediately.
        list_id: List name.
        window_ms: The app's arm window (``FST_DEBUG_FADE_WINDOW_MS`` when a journey lengthens it).

    Returns:
        Failures.
    """
    own = [e for e in events if e.list == list_id]
    first = next((i for i, e in enumerate(own) if e.kind in ("rush", "close")), None)
    if first is None:
        return [f"{list_id}: no scroll rushed the load entrance (fade-rush missing)"]
    failures = check_load(own[:first], list_id)
    if own[first].kind == "close":
        since = own[first].values.get("since", window_ms)
        why = (f"inside the {window_ms} ms window, so the rush is missing" if since < window_ms
               else "after the entrance had finished, so R5's rush was not exercised")
        return failures + [f"{list_id}: the scroll {since} ms after the load arm closed it (fade-close) {why}"]
    start = own[first].values.get("start") or None
    proven = own[first].values.get("rushed", 0) > 0
    reloaded = False
    staggered, replayed = [], []
    for event in own[first + 1:]:
        if event.kind == "arm":
            start = event.values["start"]
            reloaded = reloaded or start == 0
        elif event.kind == "skip" and (start is None or event.values["index"] < start):
            proven = True
        elif event.kind == "play" and (start is None or start == 0 or event.values["index"] < start):
            if reloaded:
                replayed.append(event.values["index"])
            elif event.values.get("delay", 0) == 0:
                proven = True
            else:
                staggered.append(event.values["index"])
    if not proven:
        failures.append(f"{list_id}: the rush started no pending fade and the scroll realized no old row "
                        "(rushed=0, no delay-0 play, no fade-skip), nothing proven")
    if staggered:
        failures.append(f"{list_id}: rows realized by the scroll kept a stagger instead of fading in together: {staggered}")
    if replayed:
        failures.append(f"{list_id}: old rows faded in again after a reload arm: {replayed}")
    return failures


def check_none(events: list[FadeEvent]) -> list[str]:
    """Nothing fades (an idle phase after the reveal).

    Args:
        events: Events of the phase.

    Returns:
        Failures.
    """
    played = [(e.list, e.values.get("index", e.values.get("target"))) for e in events if e.kind in ("play", "enter")]
    return [f"rows faded again after the reveal: {played}"] if played else []


def check_enrolled(events: list[FadeEvent], owner: str, targets: tuple[str, ...] | list[str]) -> list[str]:
    """Each entrance element fades as part of its owner's entrance (``fade-enter list=<owner> target=<name>``).

    A pinned row scheduled outside its board's entrance, or a page section outside its page's, keeps its delay when a
    scroll rushes the rest (issue #323), so its ``fade-enter`` line must name the board list or page scroller.

    Args:
        events: Events of the phase that loaded the entrance.
        owner: The board list or page scroller.
        targets: Element names (``x:Name``) that must have entered.

    Returns:
        Failures.
    """
    entered = {e.values.get("target") for e in events if e.kind == "enter" and e.list == owner}
    elsewhere = {str(e.values.get("target")): e.list for e in events if e.kind == "enter" and e.list != owner}
    failures = []
    for target in targets:
        if target in entered:
            continue
        where = f" (it entered with {elsewhere[target]})" if target in elsewhere else ""
        failures.append(f"{owner}: {target} did not fade in with its entrance (no fade-enter target={target}){where}, "
                        "so a scroll cannot rush it")
    return failures


def _at(event: FadeEvent) -> int | None:
    """The event's clock value (ms), if traced."""
    value = event.values.get("at")
    return value if isinstance(value, int) else None


def _delayed_after(own: list[FadeEvent], first: int, start: int | None) -> list[str]:
    """Fades of the entrance scheduled with a delay after its rush, up to the next re-arm from 0.

    Args:
        own: The owner's events.
        first: Index of the rush in ``own``.
        start: The rush's kept batch start (rows at or after it are a batch's own stagger), or ``None``.

    Returns:
        ``index N``/target names of the late fades.
    """
    late = []
    for event in own[first + 1:]:
        if event.kind == "arm":
            if event.values.get("start") == 0:
                break
            start = int(event.values["start"])
        elif event.kind == "enter" and int(event.values.get("delay", 0)) > 0:
            late.append(str(event.values.get("target")))
        elif (event.kind == "play" and int(event.values.get("delay", 0)) > 0
              and (start is None or int(event.values["index"]) < start)):
            late.append(f"index {event.values['index']}")
    return late


def _rush_problems(own: list[FadeEvent], first: int) -> list[str]:
    """What a rush (``own[first]``) left pending: kept fades, entrance elements and rows still due after it.

    An entrance element scheduled before the rush whose fade was due after it (its ``at`` + ``delay`` past the rush's
    ``at``) must have a ``fade-early`` line from this rush, and the rush must have started at least as many fades as
    were still due; a fade scheduled after it must start at once (:func:`_delayed_after`).

    Args:
        own: The owner's events, in log order.
        first: Index of the ``fade-rush`` event in ``own``.

    Returns:
        Failures (without the owner prefix).
    """
    rush = own[first]
    failures = []
    if int(rush.values.get("kept", 0)):
        failures.append(f"the rush kept {rush.values['kept']} pending fade(s) of the entrance on their delay")
    rushed_at = _at(rush)
    early = set()
    for event in reversed(own[:first]):
        if event.kind != "early":
            break
        early.add(event.values.get("target"))
    if rushed_at is not None:
        start = int(rush.values.get("start", 0)) or None
        due_targets, due_rows = [], 0
        for event in own[:first]:
            if event.kind == "arm" and event.values.get("start") == 0:
                due_targets, due_rows = [], 0
                continue
            at = _at(event)
            if at is None or at + int(event.values.get("delay", 0)) <= rushed_at + CLOCK_SLOP_MS:
                continue
            if event.kind == "enter":
                due_targets.append(str(event.values.get("target")))
            elif event.kind == "play" and (start is None or int(event.values["index"]) < start):
                due_rows += 1
        missed = [target for target in due_targets if target not in early]
        if missed:
            failures.append(f"still-pending entrance fades kept their delay through the rush: {missed}")
        due = len(due_targets) + due_rows
        if int(rush.values.get("rushed", 0)) < due:
            failures.append(f"the rush started {rush.values.get('rushed', 0)} fade(s) but {due} were still pending")
    late = _delayed_after(own, first, int(rush.values.get("start", 0)) or None)
    if late:
        failures.append(f"fades scheduled after the rush kept a delay instead of starting at once: {late}")
    return failures


def check_entrance_rush(events: list[FadeEvent], owner: str, targets: tuple[str, ...] | list[str] = (),
                        window_ms: int = ARM_WINDOW_MS) -> list[str]:
    """R5 (issue #323): a scroll during an entrance rushes every fade of it that hasn't started, entrance elements too.

    The phase loads the entrance (a board's rows and its pinned row, or a page's sections) and scrolls during it: a
    drag, wheel, Quick Links jump or programmatic scroll. ``targets`` must have entered with the owner before the
    scroll (:func:`check_enrolled`); the scroll must rush the entrance (a ``fade-close`` means it came after the
    entrance, or the rush is gone); the rush must start every fade still pending (:func:`_rush_problems`); and nothing
    of the entrance may be scheduled with a delay after it.

    Args:
        events: Events of the phase.
        owner: The board list or page scroller.
        targets: Entrance elements that must have entered with the owner.
        window_ms: The app's arm window (``FST_DEBUG_FADE_WINDOW_MS`` when a journey lengthens it).

    Returns:
        Failures.
    """
    own = [e for e in events if e.list == owner]
    first = next((i for i, e in enumerate(own) if e.kind in ("rush", "close")), None)
    if first is None:
        return [f"{owner}: no scroll rushed the entrance (fade-rush missing)"]
    # A page that reloads in place (Song Details opening another song) arms again: judge the entrance the scroll hit.
    armed = [i for i, e in enumerate(own[:first]) if e.kind == "arm" and e.values.get("start") == 0]
    if armed:
        own = own[armed[-1]:]
        first -= armed[-1]
    failures = check_enrolled(own[:first], owner, targets)
    if own[first].kind == "close":
        since = int(own[first].values.get("since", window_ms))
        why = (f"inside the {window_ms} ms window, so the rush is missing" if since < window_ms
               else "after the entrance had finished, so R5's rush was not exercised")
        return failures + [f"{owner}: the scroll {since} ms after the load closed the entrance (fade-close) {why}"]
    return failures + [f"{owner}: {problem}" for problem in _rush_problems(own, first)]


def check_reveal(events: list[FadeEvent], owner: str, index: int | None = None,
                 targets: tuple[str, ...] | list[str] = (), motion: bool = True) -> list[str]:
    """Web ``navToPlayer``/``navToBand`` (issue #323): the selected-row reveal waits for its row, then rushes and scrolls.

    The phase opens a board on its selected row. The board must arm from 0, its pinned row (``targets``) must enter
    with it, the reveal must hold the rows below the first screen (``fade-hold``), wait at least the row's own
    entrance (``fade-reveal`` ``wait``, timed from the hold) and scroll (``scrolled=1``) after a rush of the board
    (:func:`_rush_problems`: nothing pending keeps a delay), and nothing of the board may fade with a delay after it.
    Under Reduce Motion (`motion` false, R6) the reveal scrolls at once (`wait=0 motion=0`) and nothing fades,
    holds or rushes.

    Args:
        events: Events of the phase.
        owner: The board list.
        index: The selected row's index, if known.
        targets: Entrance elements (the pinned row) that must have entered with the board.
        motion: Whether the app ran with motion allowed.

    Returns:
        Failures.
    """
    own = [e for e in events if e.list == owner]
    reveal_at = next((i for i, e in enumerate(own) if e.kind == "reveal"), None)
    if reveal_at is None:
        return [f"{owner}: no selected-row reveal ran (fade-reveal missing)"]
    if not motion:
        return _still_reveal_problems(own, own[reveal_at], owner, index)
    armed = [i for i, e in enumerate(own[:reveal_at]) if e.kind == "arm" and e.values.get("start") == 0]
    if not armed:
        return [f"{owner}: the board never armed its entrance before the reveal"]
    own = own[armed[-1]:]
    reveal_at -= armed[-1]
    reveal = own[reveal_at]
    failures = check_enrolled(own[:reveal_at], owner, targets)
    if index is not None and reveal.values.get("index") != index:
        failures.append(f"{owner}: the reveal went to row {reveal.values.get('index')}, expected {index}")
    if reveal.values.get("scrolled") != 1:
        failures.append(f"{owner}: the reveal did not scroll (scrolled={reveal.values.get('scrolled')})")
    hold = next((e for e in own[:reveal_at] if e.kind == "hold"), None)
    wait = int(reveal.values.get("wait", 0))
    if hold is None and wait > 0:
        failures.append(f"{owner}: the reveal held no rows for its scroll (fade-hold missing)")
    elif hold is not None and _at(hold) is not None and _at(reveal) is not None and _at(reveal) - _at(hold) < wait - CLOCK_SLOP_MS:
        failures.append(f"{owner}: the reveal scrolled {_at(reveal) - _at(hold)} ms after the hold, before the row's "
                        f"own entrance ({wait} ms) had finished")
    rush_at = next((i for i in range(reveal_at - 1, -1, -1) if own[i].kind in ("rush", "close")), None)
    if rush_at is None or own[rush_at].kind != "rush":
        failures.append(f"{owner}: the reveal scrolled without rushing the entrance (no fade-rush before fade-reveal)")
        return failures
    return failures + [f"{owner}: {problem}" for problem in _rush_problems(own, rush_at)]


def _still_reveal_problems(own: list[FadeEvent], reveal: FadeEvent, owner: str, index: int | None) -> list[str]:
    """Reduce Motion (load-transition R6): the reveal scrolls at once and the board neither fades, holds nor rushes.

    Args:
        own: The board's events of the phase.
        reveal: Its ``fade-reveal`` line.
        owner: The board list.
        index: The selected row's index, if known.

    Returns:
        Failures.
    """
    failures = []
    if index is not None and reveal.values.get("index") != index:
        failures.append(f"{owner}: the reveal went to row {reveal.values.get('index')}, expected {index}")
    if reveal.values.get("motion") != 0:
        failures.append(f"{owner}: the Reduce Motion reveal ran with motion={reveal.values.get('motion')}")
    if reveal.values.get("scrolled") != 1 or int(reveal.values.get("wait", 0)) != 0:
        failures.append(f"{owner}: the Reduce Motion reveal didn't scroll at once "
                        f"(wait={reveal.values.get('wait')} scrolled={reveal.values.get('scrolled')})")
    # The instant jump is itself a scroll, so it may log a rush; under Reduce Motion that rush finds nothing to start.
    moved = sorted({e.kind for e in own if e.kind in ("hold", "early") or (e.kind == "rush" and e.values.get("rushed"))})
    if moved:
        failures.append(f"{owner}: the Reduce Motion reveal held or rushed fades ({', '.join(moved)})")
    faded = [e.values.get("index", e.values.get("target")) for e in own
             if e.kind in ("play", "enter") and e.values.get("motion") == 1]
    if faded:
        failures.append(f"{owner}: rows faded with motion under Reduce Motion: {faded}")
    return failures

# endregion

# region Phased drive


@dataclass(frozen=True)
class Phase:
    """One drive of a fade journey and the check of the fade lines it appended."""

    label: str
    steps: list[str]
    check: Callable[[list[FadeEvent]], list[str]]


SETTLE_STEP = "wait:1.5"
"""Appended to each phase: the stagger window is 1 s after an arm, so every fade of the phase is logged by then."""


def read_lines(log: Path) -> list[str]:
    """The perf log's lines (none when the app has not written it yet)."""
    try:
        return log.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return []


def run_phases(drive: Callable[[list[str]], None], log: Path, phases: list[Phase]) -> list[str]:
    """Drive each phase and judge the fade lines it appended.

    Args:
        drive: Runs ``uiwin.py drive`` steps against the launched app (raises on a failed step).
        log: The app's ``--perf-log`` file.
        phases: Phases in order; the first also sees the lines written while the app launched.

    Returns:
        Failures prefixed with their phase label; also printed with each phase's fades.
    """
    failures: list[str] = []
    mark = 0
    for phase in phases:
        drive([*phase.steps, SETTLE_STEP])
        lines = read_lines(log)
        events = parse(lines[mark:])
        mark = len(lines)
        found = phase.check(events)
        summary = ", ".join(f"{e.kind} {e.list} {e.values}" for e in events) or "none"
        print(f"  fade {phase.label}: {summary}")
        failures += [f"{phase.label}: {failure}" for failure in found]
    return failures


def perf_log(name: str) -> Path:
    """A fresh perf-log path for one journey run (deleted if left from an earlier run)."""
    log = Path(tempfile.gettempdir()) / f"fst-fade-{name}.log"
    log.unlink(missing_ok=True)
    return log

# endregion


def wiring_problems(root: Path = ROOT) -> list[str]:
    """Check that the page wiring the fade journeys exercise is still in place.

    Args:
        root: Repository root.

    Returns:
        One message per missing call.
    """
    problems = []
    for rel, regex, consequence in WIRING:
        text = (root / rel).read_text(encoding="utf-8")
        code = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("//"))
        if not re.search(regex, code):
            problems.append(f"{rel}: missing /{regex}/: {consequence}")
    return problems
