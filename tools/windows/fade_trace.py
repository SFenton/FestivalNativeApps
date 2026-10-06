"""Load-transition fade checks for the Windows UI journeys (issue #260, pattern ``load-transition``).

With ``--perf-log`` the app's ``FadeIn`` stagger (``windows/Festival.App/Controls/FadeIn.cs``) writes one line per
re-arm and one per row it fades, never for a row that just appears::

    fade-arm list=CardList start=10
    fade-play list=CardList index=10 delay=125 motion=1

A journey drives the app in phases and judges only the lines each phase appended, so it can prove that a page fades
the rows visible at load, that an appended batch fades only its own new rows, that scrolling away and back replays
nothing, and that rows held behind a spinner fade once when it clears. :data:`WIRING` lists the page calls these
journeys exercise; ``tests/test_fade_trace.py`` checks them in CI, where WinUI journeys cannot run.

Used by ``suggestions_journey.py`` (scenario ``fade``) and ``search_journey.py`` (journey ``fade-delayed-results``).
"""

from __future__ import annotations

import re
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
LINE = re.compile(r"^fade-(?P<kind>arm|play) list=(?P<list>\S+)(?P<rest>(?: \w+=-?\d+)*)\s*$")

#: ``(file, regex, what breaks without it)``: the page wiring behind each fade journey assertion.
WIRING: tuple[tuple[str, str, str], ...] = (
    ("windows/Festival.App/Pages/SuggestionsPage.xaml.cs",
     r"CardsAdded\s*\+=\s*\(_,\s*(\w+)\)\s*=>\s*FadeIn\.Restagger\(CardList,\s*\1\)",
     "Suggestions batches after the first never fade (journey suggestions fade: load-more)"),
    ("windows/Festival.App/Pages/SearchPage.xaml.cs",
     r"SectionShown\s*\+=\s*OnSectionShown",
     "Search rows held behind the spinner appear without a fade (journey fade-delayed-results)"),
    ("windows/Festival.App/Pages/SearchPage.xaml.cs",
     r"FadeIn\.Restagger\(section == SearchScope\.Songs \? SongsList : PlayersList\)",
     "Search rows held behind the spinner appear without a fade (journey fade-delayed-results)"),
)

# region Parsing


@dataclass(frozen=True)
class FadeEvent:
    """One ``fade-*`` perf-log line."""

    kind: str
    """``arm`` (the list re-armed its stagger) or ``play`` (a row faded)."""
    list: str
    """List name (``x:Name``, else AutomationId)."""
    values: dict[str, int] = field(default_factory=dict, compare=False)
    """``start`` for arms; ``index`` and ``delay`` (ms) for plays."""


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
            events.append(FadeEvent(match["kind"], match["list"], {key: int(value) for key, _, value in pairs}))
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
        elif start is None or event.values["index"] < start:
            replayed.append(event.values["index"])
    return [f"{list_id}: rows already shown faded again while scrolling: {replayed}"] if replayed else []


def check_none(events: list[FadeEvent]) -> list[str]:
    """Nothing fades (an idle phase after the reveal).

    Args:
        events: Events of the phase.

    Returns:
        Failures.
    """
    played = [(e.list, e.values.get("index")) for e in events if e.kind == "play"]
    return [f"rows faded again after the reveal: {played}"] if played else []

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
