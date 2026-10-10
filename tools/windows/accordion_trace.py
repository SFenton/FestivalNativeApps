"""Accordion choreography checks for the Windows journeys (issue #561, pattern ``load-transition`` R10).

With ``--perf-log`` the app's ``AccordionMover`` (``windows/Festival.App/Controls/Accordion.cs``, the one mover behind
every Expander, Settings switch panel and Instrument Selector panel) writes one line when a toggle starts a move, one
when its storyboard begins (after the content's first frame has rendered), one per rendered frame of the move (the
clip's laid-out height and the content's opacity, sampled on ``CompositionTarget.Rendering``) and one when the section
settles; ``t`` is milliseconds since the toggle::

    accordion-move id=fst.songs.filter.year open=1 from=0.0 to=148.0 opacity=0.000
    accordion-frame id=fst.songs.filter.year t=9 height=0.0 opacity=0.000
    accordion-begin id=fst.songs.filter.year t=18
    accordion-frame id=fst.songs.filter.year t=34 height=12.4 opacity=0.000
    accordion-frame id=fst.songs.filter.year t=170 height=148.0 opacity=0.214
    accordion-settle id=fst.songs.filter.year open=1 animated=1 motion=1 t=305
    accordion-settle id=LeewayInline open=0 animated=0 motion=0 t=0

:func:`check_open` and :func:`check_close` judge the frames of one move: opening grows the height while the content
is fully transparent and only then fades it in at full height; closing fades out at full height and only then
collapses. Each phase must have frames strictly inside it (a snap has none), no frame may jump more than
:data:`MAX_STEP` of the range (a stalled first frame once jumped 87 % of the grow) unless it follows a mid-move
:data:`STALL_MS` stall, and each phase must happen inside
its 150 ms window after the begin, with :data:`SLOP_MS` for UI-thread timing; the begin must follow the toggle within
:data:`MAX_START_WAIT_MS`. :func:`check_instant` judges Reduce Motion: no move, only an un-animated
settle. ``tests/test_accordion_trace.py`` checks the judges in CI, where WinUI journeys cannot run.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

LINE = re.compile(r"^accordion-(?P<kind>move|begin|frame|settle) id=(?P<id>\S+)(?P<rest>(?: \w+=[^\s=]+)*)\s*$")
PHASE_MS = 150
"""``AccordionMotion.PhaseDuration``: each phase's length."""
SLOP_MS = 60
"""UI-thread allowance at each phase edge (frame cadence, storyboard start latency, the trace's own sampling)."""
HEIGHT_EPS = 0.6
"""Layout rounding: a height within this of the target counts as reached."""
OPACITY_EPS = 0.01
"""A fade within this of 0 or 1 counts as transparent or opaque."""
MAX_STEP = 0.5
"""Largest share of a phase's range one frame may cover (the CSS ``ease`` curve covers under 0.2 per 60 Hz frame)."""
MAX_START_WAIT_MS = 150
"""Longest wait from the toggle to the storyboard's begin (the content's first layout plus one frame)."""
STALL_MS = 40
"""A gap between two of a move's frames longer than this is a UI-thread stall (two or more dropped 60 Hz frames, e.g.
under host load). The storyboard clock runs on through it, so the next one or two samples may step past
:data:`MAX_STEP` (the sample right after a stall can still read the stale value); those steps are excused. The start
stall is not: the gap from the toggle to the first frame is not between two frames, and ``begin`` must follow it."""


@dataclass(frozen=True)
class Event:
    """One parsed accordion trace line."""

    kind: str
    id: str
    values: dict[str, float] = field(default_factory=dict)


@dataclass
class Move:
    """One move: its start line, its frames and how it ended (``settle`` is ``None`` when a toggle interrupted it)."""

    start: Event
    frames: list[Event] = field(default_factory=list)
    begin: Event | None = None
    settle: Event | None = None

    @property
    def origin(self) -> float:
        """When the storyboard began, in ms since the toggle (0 when it never began)."""
        return self.begin.values.get("t", 0) if self.begin else 0

    @property
    def opening(self) -> bool:
        """Whether the move opens the section."""
        return self.start.values.get("open") == 1

    @property
    def target(self) -> float:
        """The open height (the move's ``to``, or ``from`` when closing)."""
        return self.start.values["to"] if self.opening else self.start.values["from"]


def parse(lines: list[str]) -> list[Event]:
    """Parse the accordion lines of a perf log, ignoring every other line."""
    events = []
    for line in lines:
        match = LINE.match(line.strip())
        if not match:
            continue
        values = {}
        for pair in match["rest"].split():
            key, _, value = pair.partition("=")
            try:
                values[key] = float(value)
            except ValueError:
                continue
        events.append(Event(match["kind"], match["id"], values))
    return events


def moves(events: list[Event], accordion: str) -> list[Move]:
    """Group one accordion's lines into moves, in order."""
    found: list[Move] = []
    for event in events:
        if event.id != accordion:
            continue
        if event.kind == "move":
            found.append(Move(event))
        elif event.kind == "frame" and found:
            found[-1].frames.append(event)
        elif event.kind == "begin" and found and found[-1].begin is None:
            found[-1].begin = event
        elif event.kind == "settle" and found and found[-1].settle is None:
            found[-1].settle = event
    return found


def _frame_text(frame: Event) -> str:
    v = frame.values
    return f"t={v.get('t', 0):.0f} height={v.get('height', 0):.1f} opacity={v.get('opacity', 0):.3f}"


def _steps(frames: list[Event], key: str, rising: bool, span: float) -> list[str]:
    """Frame-to-frame problems for one value: moving the wrong way, or jumping more than :data:`MAX_STEP` of ``span``."""
    eps = HEIGHT_EPS if key == "height" else OPACITY_EPS
    times = [frame.values.get("t", 0) for frame in frames]
    stalled = {i for i in range(1, len(frames)) if times[i] - times[i - 1] > STALL_MS}
    problems = []
    for i, (before, after) in enumerate(zip(frames, frames[1:]), start=1):
        step = after.values[key] - before.values[key]
        pair = f"{_frame_text(before)} and {_frame_text(after)}"
        if (rising and step < -eps) or (not rising and step > eps):
            problems.append(f"{key} {'fell' if rising else 'rose'} between frames {pair}")
        elif span > 0 and abs(step) > MAX_STEP * span and not stalled & {i, i - 1}:
            problems.append(f"{key} jumped {abs(step) / span:.0%} of its range in one frame between {pair}")
    return problems


def _phase_problems(move: Move, grow_label: str, fade_label: str) -> tuple[list[Event], list[Event], list[str]]:
    """Split a full move's frames into its height and fade phases and check that they never overlap."""
    target = move.target
    problems = []
    if target <= HEIGHT_EPS:
        problems.append(f"open height {target:.1f} is too small to show a height phase")
    if move.begin is None:
        problems.append("the move never began")
    elif move.origin > MAX_START_WAIT_MS:
        problems.append(f"the move began {move.origin:.0f} ms after the toggle (limit {MAX_START_WAIT_MS} ms)")
    if move.settle is None:
        problems.append("the move never settled (interrupted or still running when the phase ended)")
    elif move.settle.values.get("open") != (1 if move.opening else 0):
        problems.append(f"settled open={move.settle.values.get('open'):.0f}, not where the move was heading")
    height_frames = [f for f in move.frames if HEIGHT_EPS < f.values["height"] < target - HEIGHT_EPS]
    fade_frames = [f for f in move.frames if OPACITY_EPS < f.values["opacity"] < 1 - OPACITY_EPS]
    if not height_frames:
        problems.append(f"no rendered frame between closed and open height ({grow_label} snapped)")
    if not fade_frames:
        problems.append(f"no rendered frame between transparent and opaque ({fade_label} snapped)")
    for frame in move.frames:
        partial_height = frame.values["height"] < target - HEIGHT_EPS
        if partial_height and frame.values["opacity"] > OPACITY_EPS:
            problems.append(f"content visible before the section reached full height: {_frame_text(frame)} "
                            f"(open height {target:.1f})")
    problems += _steps(move.frames, "height", move.opening, target)
    problems += _steps(move.frames, "opacity", move.opening, 1.0)
    return height_frames, fade_frames, problems


def _window(frames: list[Event], origin: float, low: float, high: float, label: str) -> list[str]:
    """Frames outside ``low``..``high`` ms after the storyboard's begin (``origin``)."""
    return [f"{label} frame outside {low:.0f}-{high:.0f} ms after the begin at {origin:.0f} ms: {_frame_text(f)}"
            for f in frames if not origin + low <= f.values["t"] <= origin + high]


def check_open(move: Move) -> list[str]:
    """Opening: the height grows in the first phase with the content transparent, then the content fades in."""
    if not move.opening:
        return ["expected an opening move, got a closing one"]
    grow, fade, problems = _phase_problems(move, "the grow", "the fade-in")
    problems += _window(grow, move.origin, 0, PHASE_MS + SLOP_MS, "grow")
    problems += _window(fade, move.origin, PHASE_MS - SLOP_MS, 2 * PHASE_MS + SLOP_MS, "fade-in")
    if grow and fade and max(f.values["t"] for f in grow) > min(f.values["t"] for f in fade):
        problems.append("the fade-in started before the grow finished")
    return problems


def check_close(move: Move) -> list[str]:
    """Closing: the content fades out at full height in the first phase, then the height collapses."""
    if move.opening:
        return ["expected a closing move, got an opening one"]
    collapse, fade, problems = _phase_problems(move, "the collapse", "the fade-out")
    problems += _window(fade, move.origin, 0, PHASE_MS + SLOP_MS, "fade-out")
    problems += _window(collapse, move.origin, PHASE_MS - SLOP_MS, 2 * PHASE_MS + SLOP_MS, "collapse")
    if collapse and fade and max(f.values["t"] for f in fade) > min(f.values["t"] for f in collapse):
        problems.append("the collapse started before the fade-out finished")
    return problems


def check_toggle(events: list[Event], accordion: str, sequence: tuple[bool, ...]) -> list[str]:
    """Check that ``accordion`` made exactly the full moves in ``sequence`` (``True`` opens) with the choreography.

    Args:
        events: The phase's parsed lines.
        accordion: Trace id (AutomationId or x:Name).
        sequence: Expected moves in order.

    Returns:
        Failures (empty when every move has both phases in order).
    """
    own = moves(events, accordion)
    if len(own) != len(sequence):
        return [f"{accordion}: expected {len(sequence)} move(s), traced {len(own)}"]
    problems = []
    for index, (move, opening) in enumerate(zip(own, sequence)):
        found = check_open(move) if opening else check_close(move)
        problems += [f"{accordion} move {index + 1} ({'open' if opening else 'close'}): {p}" for p in found]
    return problems


def check_instant(events: list[Event], accordion: str, sequence: tuple[bool, ...]) -> list[str]:
    """Reduce Motion: ``accordion`` settled at each state in ``sequence`` without a move or a frame.

    Args:
        events: The phase's parsed lines.
        accordion: Trace id.
        sequence: Expected settles in order (``True`` open).

    Returns:
        Failures.
    """
    own = [e for e in events if e.id == accordion]
    problems = [f"{accordion}: {e.kind} line under Reduce Motion" for e in own if e.kind != "settle"]
    settles = [e for e in own if e.kind == "settle"]
    states = tuple(e.values.get("open") == 1 for e in settles)
    if states != sequence:
        problems.append(f"{accordion}: settled {states}, expected {sequence}")
    problems += [f"{accordion}: animated settle under Reduce Motion" for e in settles if e.values.get("animated") != 0]
    problems += [f"{accordion}: motion=1 while Reduce Motion is on" for e in settles if e.values.get("motion") != 0]
    return problems
