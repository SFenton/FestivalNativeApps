#!/usr/bin/env python3
"""Selected-row reveal journey for the Windows leaderboards (issue #307; patterns ``leaderboard-row`` R7 and
``load-transition`` R5).

A board opened on the selected row (Song Detail's "Jump to your band's position" -> ``navToBand``; its solo spotlight
row -> ``navToPlayer``) must replay its row entrance first and bring that row into view only once the row's own fade
has finished, starting every fade that hasn't begun together rather than letting the jump cut the stagger short.
Each scenario launches this worktree's Debug build on the board with ``--perf-log`` against the loopback fixture
service (``mock_service.py --large-rankings``: the fixture-pulse Duos board pads to 75 bands, ``fixture-player-1``'s
band at rank 29, page 2 row 3; solo ``fixture-player-N`` ranks N), waits for the selected row, and judges the
``fade-reveal``/``fade-rush`` lines with :func:`fade_trace.check_reveal`. The Reduce Motion scenario must reveal at
once and rush nothing. Journeys never touch production.

Usage::

    python tools/windows/selected_reveal_journey.py [--only band] [--shots DIR] [--exe aot]
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fade_trace  # noqa: E402  (sibling module)
import journey_exe  # noqa: E402
import ui_journey  # noqa: E402

REVEAL_WAIT_STEP = "wait:2.5"
"""The load swap's 500 ms spinner-out, the row's stagger delay and fade, and the reveal's frame."""


@dataclass(frozen=True)
class Scenario:
    """One board opened on its selected row."""

    name: str
    route: str
    profile: str
    list_id: str
    """The stagger list's ``x:Name`` in the fade trace."""
    index: int
    """The selected row's index on the opened page."""
    row: str
    """UIA selector of the selected row."""
    row_name: str
    """``assertname`` pattern of the selected row."""
    motion: bool = True
    args: list[str] = field(default_factory=list)


SCENARIOS = (
    Scenario("band", "/songs/fixture-pulse/bands/Band_Duets?page=2&navToBand=true", "fixture-player-1:Fixture Player 1",
             "Rows", 3, "id=fst.song-band-leaderboard.row.fixture-band-fixture-player-1:29", "Your band. *"),
    Scenario("band-reduce-motion", "/songs/fixture-pulse/bands/Band_Duets?page=2&navToBand=true",
             "fixture-player-1:Fixture Player 1", "Rows", 3,
             "id=fst.song-band-leaderboard.row.fixture-band-fixture-player-1:29", "Your band. *",
             motion=False, args=["--reduce-motion"]),
    Scenario("solo", "/songs/fixture-pulse/Solo_Guitar?page=1&navToPlayer=true", "fixture-player-6:Fixture Player 6",
             "RowsRepeater", 5, "id=fst.song-leaderboard.row.fixture-player-6", "*"),
)


def run(scenario: Scenario, port: int, shots: Path) -> list[str]:
    """Launch one scenario, open the board on its selected row and judge the reveal's fade lines.

    Args:
        scenario: Scenario.
        port: Fixture service port.
        shots: Screenshot directory.

    Returns:
        Failures.
    """
    settings = Path(tempfile.gettempdir()) / f"fst-reveal-settings-{scenario.name}.json"
    settings.unlink(missing_ok=True)
    log = fade_trace.perf_log(f"reveal-{scenario.name}")
    launch = ui_journey.uiwin("launch", str(ui_journey.EXE), f"--arg=--route={scenario.route}",
                              "--arg=--base-url", f"--arg=http://127.0.0.1:{port}/",
                              "--arg=--settings-path", f"--arg={settings}", "--arg=--first-run=off",
                              "--arg=--profile", f"--arg={scenario.profile}",
                              f"--arg=--perf-log={log}", *(f"--arg={a}" for a in scenario.args), "--preset", "medium")
    if launch.returncode != 0:
        return ["launch: " + launch.stderr.strip()]

    def drive(steps: list[str]) -> None:
        with tempfile.NamedTemporaryFile("w", suffix=".steps", delete=False, encoding="utf-8") as handle:
            handle.write("\n".join(steps))
        try:
            result = ui_journey.uiwin("drive", "--steps-file", handle.name)
        finally:
            Path(handle.name).unlink(missing_ok=True)
        if result.returncode != 0:
            raise RuntimeError((result.stderr.strip() or result.stdout.strip() or "driver failed").splitlines()[-1])

    phase = fade_trace.Phase(
        "open", [f"waitfor:{scenario.row}@20", REVEAL_WAIT_STEP, f"assertname:{scenario.row}|{scenario.row_name}"],
        lambda events: fade_trace.check_reveal(events, scenario.list_id, scenario.index, motion=scenario.motion,
                                               require_rush=scenario.motion and scenario.name == "band"))
    try:
        failures = fade_trace.run_phases(drive, log, [phase])
        ui_journey.uiwin("shot", str(shots / f"reveal-{scenario.name}.png"))
    except RuntimeError as error:
        ui_journey.uiwin("shot", str(shots / f"reveal-{scenario.name}-failure.png"), "--mode", "screen")
        failures = [str(error)]
    finally:
        ui_journey.uiwin("close")
        settings.unlink(missing_ok=True)
    return failures


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        0 when every scenario passed, 1 otherwise.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--only", action="append", choices=[s.name for s in SCENARIOS])
    parser.add_argument("--shots", type=Path, default=Path(tempfile.gettempdir()) / "fst-journeys")
    journey_exe.add_argument(parser)
    args = parser.parse_args(argv)
    ui_journey.EXE = args.exe
    if not ui_journey.EXE.is_file():
        print(f"error: build first (tools/windows/build.ps1); no {ui_journey.EXE}", file=sys.stderr)
        return 1
    args.shots.mkdir(parents=True, exist_ok=True)
    selected = [s for s in SCENARIOS if not args.only or s.name in args.only]
    mock, port = ui_journey.start_mock(args.shots / "reveal-fixture-service.log", ("--large-rankings",))
    failed = 0
    try:
        for scenario in selected:
            failures = run(scenario, port, args.shots.resolve())
            failed += bool(failures)
            print(f"{'FAIL' if failures else 'PASS'} reveal-{scenario.name}" + (f": {'; '.join(failures)}" if failures else ""),
                  flush=True)
    finally:
        mock.kill()
    print(f"{len(selected) - failed}/{len(selected)} reveal journeys passed; screenshots in {args.shots}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
