"""Reflow motion checks for the Windows journeys (issue #669, pattern ``reflow-motion``).

With ``--perf-log`` the app writes these lines (``windows/Festival.App/Controls/OnDemandSplitHost.cs`` and
``ReflowMotion.cs``)::

    split-move open=1 from=0.000 to=1.000 pane=590.0 duration=300
    split-settle open=1 animated=1 motion=1 stopped=0 t=304 list=590.0
    split-settle open=0 animated=0 motion=0 stopped=0 t=0 list=1180.0
    reflow-move host=suggestions moved=3 entered=1 motion=1 t=81234
    reflow-stop stopped=4 motion=0 t=81420

``split-move`` starts an animated open (``open=1``) or close of a split pane: the columns change once and the
compositor slides and fades the pane, so the UI thread draws no frames of its own. ``split-settle`` ends it when the
compositor reports the animation complete (``t`` after the start), or reports an instant open or close (``animated=0``)
under Reduce Motion or Animation effects off; ``stopped=1`` means motion turned off mid-move and the move settled at
once (R4). ``reflow-move`` reports one column change of a card layout: how many cards glide to their new places and how
many fade in (``host`` is ``suggestions``, ``shop-grid`` or ``card-grid``). ``reflow-stop`` reports card glides and
fades that motion turning off stopped in their settled state.

:func:`check_split` judges one animated open or close: one move toward the right end that ran its whole 300 ms
(the settle no earlier than :data:`MIN_SHARE` of it, no later than :data:`SLOP_MS` after it).
:func:`check_split_instant` judges motion off: no move, only an un-animated settle. :func:`check_reflow` and
:func:`check_reflow_instant` judge a column change with and without motion, and :func:`check_no_restagger` that the
reflow re-armed or played no load stagger (``fade-arm``, ``fade-play``). :func:`check_counts` judges an accessibility
page's ``reflow_trace`` (``a11y_matrix.py``) in every mode, and :func:`check_stops` its ``reflow_stops``: reflows that
motion turning off mid-move stopped at once. ``tests/test_reflow_trace.py`` checks the
judges in CI, where WinUI journeys cannot run.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

LINE = re.compile(r"^(?P<kind>split-move|split-settle|reflow-move|reflow-stop|fade-arm|fade-play)\b(?P<rest>.*)$")
PAIR = re.compile(r"(\w+)=([^\s=]+)")
SLOP_MS = 400
"""Allowance after the move's duration: the compositor starts it at the first commit after the list's relayout and the
opened page's first layout (about 150-200 ms on a Debug build), then delivers completion on the UI thread."""
MIN_SHARE = 0.8
"""A settle earlier than this share of the move's duration means the motion was cut short."""


@dataclass(frozen=True)
class Event:
    """One parsed trace line."""

    kind: str
    values: dict[str, float | str] = field(default_factory=dict)

    def num(self, key: str, default: float = 0.0) -> float:
        """A numeric value."""
        value = self.values.get(key, default)
        try:
            return float(value)
        except (TypeError, ValueError):
            return default


def parse(lines: list[str]) -> list[Event]:
    """The reflow, ``fade-arm`` and ``fade-play`` lines among perf-log lines."""
    events: list[Event] = []
    for line in lines:
        match = LINE.match(line.strip())
        if not match:
            continue
        values: dict[str, float | str] = {}
        for key, value in PAIR.findall(match.group("rest")):
            try:
                values[key] = float(value)
            except ValueError:
                values[key] = value
        events.append(Event(match.group("kind"), values))
    return events


def check_split(events: list[Event], opening: bool) -> list[str]:
    """One animated split open (``opening``) or close that ran its whole duration on the compositor."""
    want = 1 if opening else 0
    moves = [e for e in events if e.kind == "split-move"]
    settles = [e for e in events if e.kind == "split-settle"]
    if len(moves) != 1:
        return [f"expected one split-move, got {len(moves)}"]
    move = moves[0]
    problems: list[str] = []
    if move.num("open") != want or move.num("to") != want:
        problems.append(f"split-move {move.values} does not head to open={want}")
    if move.num("from") == move.num("to"):
        problems.append("split-move has nothing to cover")
    if move.num("pane") <= 0:
        problems.append(f"split-move pane={move.num('pane')}: no width to slide")
    duration = move.num("duration")
    if not settles or settles[-1].num("animated") != 1 or settles[-1].num("open") != want:
        problems.append(f"expected an animated settle open={want}, got {[s.values for s in settles]}")
    else:
        t = settles[-1].num("t")
        if t < duration * MIN_SHARE:
            problems.append(f"settled after {t:.0f} ms of a {duration:.0f} ms move: the motion was cut short")
        elif t > duration + SLOP_MS:
            problems.append(f"settled after {t:.0f} ms (> {duration + SLOP_MS:.0f})")
    return problems


def check_split_instant(events: list[Event], opening: bool) -> list[str]:
    """A split open or close with motion off: no move or frame, one un-animated settle."""
    want = 1 if opening else 0
    problems = [f"unexpected {e.kind} with motion off" for e in events if e.kind == "split-move"]
    settles = [e for e in events if e.kind == "split-settle"]
    if not any(s.num("animated") == 0 and s.num("motion") == 0 and s.num("open") == want for s in settles):
        problems.append(f"expected an instant settle open={want} motion=0, got {[s.values for s in settles]}")
    return problems


def check_reflow(events: list[Event], host: str, minimum: int = 1) -> list[str]:
    """A column change of ``host`` with motion on that glides at least ``minimum`` cards."""
    reflows = [e for e in events if e.kind == "reflow-move" and e.values.get("host") == host]
    if not reflows:
        return [f"no reflow-move for {host}"]
    if not any(e.num("motion") == 1 and e.num("moved") >= minimum for e in reflows):
        return [f"{host}: no reflow moved {minimum}+ card(s) with motion on: {[e.values for e in reflows]}"]
    return []


def check_reflow_instant(events: list[Event], host: str) -> list[str]:
    """A column change of ``host`` with motion off: reported, nothing moved or faded."""
    reflows = [e for e in events if e.kind == "reflow-move" and e.values.get("host") == host]
    if not reflows:
        return [f"no reflow-move for {host}"]
    return [f"{host}: motion off but {e.values}" for e in reflows
            if e.num("motion") != 0 or e.num("moved") or e.num("entered")]


def check_no_restagger(events: list[Event]) -> list[str]:
    """A reflow re-arms or plays no load stagger (load-transition: nothing replays on a resize)."""
    return [f"a reflow replayed a load stagger: {e.kind} {e.values}" for e in events
            if e.kind == "fade-arm" or (e.kind == "fade-play" and e.num("motion") == 1)]


def check_stops(events: list[Event], expected: dict[str, int]) -> list[str]:
    """Motion turned off mid-reflow stopped it at once (pattern ``reflow-motion`` R4).

    ``expected["split"]`` split moves must end in a ``split-settle animated=1 motion=0 stopped=1`` earlier than the
    move's ``duration`` (it settled where it was heading instead of running on); ``expected["cards"]`` card reflows
    must end in a ``reflow-stop motion=0`` that stopped at least one glide or fade, after a reflow that moved or faded
    cards with motion on. A journey stretches moves (``FST_DEBUG_REFLOW_MS``) so the switch lands mid-move.
    """
    problems: list[str] = []
    split_stops = card_stops = 0
    move: Event | None = None
    moving_reflow = False
    for e in events:
        if e.kind == "split-move":
            move = e
        elif e.kind == "split-settle" and e.num("stopped") == 1:
            if move is None:
                problems.append(f"split stopped without a move: {e.values}")
            elif e.num("animated") != 1 or e.num("motion") != 0:
                problems.append(f"split stop must end an animated move with motion off: {e.values}")
            elif e.num("t") >= move.num("duration"):
                problems.append(f"split stop after {e.num('t'):.0f} ms of a {move.num('duration'):.0f} ms move: "
                                "it ran on instead of stopping")
            else:
                split_stops += 1
            move = None
        elif e.kind == "split-settle":
            move = None
        elif e.kind == "reflow-move" and e.num("motion") == 1 and (e.num("moved") or e.num("entered")):
            moving_reflow = True
        elif e.kind == "reflow-stop":
            if not moving_reflow:
                problems.append(f"cards stopped without a moving reflow: {e.values}")
            elif e.num("motion") != 0 or e.num("stopped") < 1:
                problems.append(f"card stop must stop a glide or fade with motion off: {e.values}")
            else:
                card_stops += 1
            moving_reflow = False
    for host, found in (("split", split_stops), ("cards", card_stops)):
        if found < expected.get(host, 0):
            problems.append(f"{host}: expected {expected[host]}+ reflow(s) stopped mid-move, got {found}")
    return problems


def check_counts(events: list[Event], expected: dict[str, int], motion: bool | None) -> list[str]:
    """An accessibility page's reflows: at least ``expected[host]`` of each, instant when ``motion`` is ``False``.

    ``host`` ``split`` counts split opens and closes (``split-settle``); any other host counts its ``reflow-move``
    lines. ``motion`` ``None`` (the host's Animation effects decide) checks the counts only; ``False`` (Reduce Motion
    or Animation effects off) also requires no ``split-move`` and only motion-off, unmoved reflows.
    """
    problems: list[str] = []
    for host, count in expected.items():
        if host == "split":
            found = [e for e in events if e.kind == "split-settle"]
            if motion is False:
                problems += [f"split moved with motion off: {e.values}" for e in events if e.kind == "split-move"]
                problems += [f"split settled animated with motion off: {e.values}" for e in found
                             if e.num("animated") or e.num("motion")]
        else:
            found = [e for e in events if e.kind == "reflow-move" and e.values.get("host") == host]
            if motion is False:
                problems += [f"{host}: motion off but {e.values}" for e in found
                             if e.num("motion") or e.num("moved") or e.num("entered")]
        if len(found) < count:
            problems.append(f"{host}: expected {count}+ reflow(s), got {len(found)}")
    return problems
