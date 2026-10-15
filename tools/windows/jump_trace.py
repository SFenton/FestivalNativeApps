"""Songs Jump index opening checks for the Windows journeys (issue #648, pattern ``section-jump-landing``).

With ``--perf-log`` the Songs page (``windows/Festival.App/Pages/SongsPage.xaml.cs``, region *Jump index trace*) writes
one ``jump-open`` line when the jump index starts opening, then, together once it stops (1 s after the open, or when the
index starts closing), one ``jump-frame`` line per rendered frame and a ``jump-done`` line. Each frame records the
index's laid-out size, its realized cell count and cell width, the first and last cell's position inside the index and
the index's scroll offset (all epx; ``t`` is milliseconds since the open)::

    jump-open
    jump-frame t=9 height=489.3 width=814.0 cells=27 cell=76.0 first=27.0,157.7 last=483.0,267.0 offset=0.0
    jump-frame t=20 height=489.3 width=814.0 cells=27 cell=76.0 first=27.0,157.7 last=483.0,267.0 offset=0.0
    jump-done frames=2

:func:`check_opens` judges them: once the index's cells first render, its size, cell width, cell positions and scroll
offset must not change while it opens. Before #648 the pinned section header above the list collapsed only after the
zoom-out had played, so the index grew 35 epx and its centred letters jumped 17 epx down at about 235 ms. The zoom's
own scale animation applies outside the index, so it does not move these index-relative positions.
``tests/test_jump_trace.py`` checks the judge in CI, where WinUI journeys cannot run.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

FRAME = re.compile(r"^jump-frame t=(?P<t>-?\d+) height=(?P<height>[-\d.]+) width=(?P<width>[-\d.]+) cells=(?P<cells>\d+) "
                   r"cell=(?P<cell>[-\d.NaN]+) first=(?P<first>\S+) last=(?P<last>\S+) offset=(?P<offset>[-\d.]+)\s*$")
TOLERANCE_EPX = 0.6
"""Largest change (epx) still read as the same layout: the trace rounds to 0.1 epx and layout rounds to device pixels."""
#: Frame fields compared between frames, in report order.
FIELDS = ("height", "width", "cell", "first", "last", "offset")


@dataclass
class Frame:
    """One rendered frame of an opening index."""

    t: int
    cells: int
    values: dict[str, tuple[float, ...]]


@dataclass
class Opening:
    """One traced opening: its frames and whether its ``jump-done`` line was written."""

    frames: list[Frame] = field(default_factory=list)
    done: bool = False


def _numbers(text: str) -> tuple[float, ...]:
    """``"27.0,157.7"`` → ``(27.0, 157.7)``; ``"-"`` (no cell) → ``()``."""
    return () if text == "-" else tuple(float(part) for part in text.split(","))


def parse(lines: list[str]) -> list[Opening]:
    """Group perf-log lines into openings (other lines are ignored).

    Args:
        lines: Perf-log lines.

    Returns:
        One :class:`Opening` per ``jump-open`` line, in order.
    """
    openings: list[Opening] = []
    for line in lines:
        line = line.strip()
        if line == "jump-open":
            openings.append(Opening())
        elif line.startswith("jump-done") and openings:
            openings[-1].done = True
        elif (match := FRAME.match(line)) and openings:
            values = {name: _numbers(match[name]) for name in FIELDS}
            openings[-1].frames.append(Frame(int(match["t"]), int(match["cells"]), values))
    return openings


def _moved(before: tuple[float, ...], after: tuple[float, ...]) -> bool:
    """Whether a field changed by more than :data:`TOLERANCE_EPX` (or appeared/disappeared)."""
    return len(before) != len(after) or any(abs(a - b) > TOLERANCE_EPX for a, b in zip(before, after))


def _show(value: tuple[float, ...]) -> str:
    return ",".join(f"{v:.1f}" for v in value) or "-"


def check_opens(openings: list[Opening], minimum: int = 1) -> list[str]:
    """Judge traced openings: each renders its cells and never re-lays them out while it opens.

    Args:
        openings: :func:`parse` output.
        minimum: Openings the drive performed at least.

    Returns:
        Failures (empty when every opening rendered once in its final layout).
    """
    problems = []
    if len(openings) < minimum:
        problems.append(f"expected at least {minimum} jump index opening(s) in the trace, found {len(openings)}")
    for number, opening in enumerate(openings, 1):
        if not opening.done:
            problems.append(f"opening {number}: no jump-done line (the trace never stopped)")
        shown = [frame for frame in opening.frames if frame.cells > 0]
        if not shown:
            problems.append(f"opening {number}: no frame rendered the index's cells")
            continue
        first = shown[0]
        for frame in shown[1:]:
            if frame.cells != first.cells:
                problems.append(f"opening {number}: cells changed {first.cells}→{frame.cells} at t={frame.t} ms")
                break
            changed = [f"{name} {_show(first.values[name])}→{_show(frame.values[name])}" for name in FIELDS
                       if _moved(first.values[name], frame.values[name])]
            if changed:
                problems.append(f"opening {number}: index re-laid out at t={frame.t} ms after rendering at "
                                f"t={first.t} ms ({'; '.join(changed)})")
                break
    return problems
