"""Notifications (bell + flyout) UI journeys on Windows for every reachable state (issue #229).

Starts ``tools/windows/notifications_fixture.py`` (the synthetic mock plus switchable notification feeds) on a free
loopback port, then for each scenario launches this worktree's app with a throwaway settings file and app-data folder
(so seen state starts empty), drives it by ``fst.*`` AutomationIds and UIA names through ``uiwin.py`` and fails on the
first missing (``waitfor:``) or lingering (``waitgone:``) element. A ``@feed=<mode>`` step switches the fixture between
phases (e.g. 503 -> Retry -> rows). Steps use UIA patterns, except ``older-section``, which closes the flyout with Esc
(the light-dismiss close is what marks every row seen).

States (``contracts/product.json`` notifications): empty-generated, empty-not-generated, loaded, unread-section,
older-section, tap-navigate-song, tap-navigate-rankings, no-profile; plus the spec's loading, failed + retry and
"row tap, no destination" rows.

Usage: ``python tools/windows/notifications_journey.py [--only NAME[,NAME…]] [--sizes compact,medium,wide]
[--shots DIR] [--exe debug|release|aot|PATH]``
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import journey_exe  # noqa: E402  (sibling module)
import ui_journey  # noqa: E402  (sibling module)

ROOT = Path(__file__).resolve().parents[2]
UIWIN = ROOT / "tools" / "windows" / "uiwin.py"
FIXTURE = ROOT / "tools" / "windows" / "notifications_fixture.py"
EXE = journey_exe.DEBUG_EXE
PLAYER = {"FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1"}
ANONYMOUS = {"FST_DEBUG_ANONYMOUS": "1"}
BELL = "id=fst.shell.notifications"
ROW = "id=fst.notifications.row."
GENERATED_BODY = ("Notifications will appear here when new high scores are set or global ranks improve. "
                  "Set new high scores and compete with friends to see them!")
NOT_GENERATED_BODY = ("Notifications may appear here after the next leaderboard update. "
                      "Set new high scores and compete with friends to see them!")
RANK_ROW = "Fixture Pulse · Lead. You climbed from #9 to #4 on Lead for Fixture Pulse. Rank Up."
TOTAL_ROW = "Total Score Improved. Your Tap Vocals total score increased to 1,234,567 points. Progress."
# Rows of the rich feed, newest first.
RICH_ROWS = ("rank", "fc", "fcrate", "total", "shop")
# Rows of the media feed (issue #272), newest first, and their Narrator names after "Unread. ".
MEDIA_ROWS = ("grid", "first", "stars", "gold", "difficulty", "pb")
MEDIA_NAMES = {
    "grid": "Fixture Pulse · Lead. You set a new personal best on Lead for Fixture Pulse with 201,234 points. "
            "Affected instruments: Lead, Bass, Drums. New High Score. Jan 7",
    "first": "Fixture Orbit · Bass. Your first Bass play on Fixture Orbit scored 154,321 points and started at your "
             "new rank. First Play. Jan 6",
    "stars": "Fixture Pulse · Drums. You improved from 4 to 5 stars on Drums for Fixture Pulse. Stars Up. Jan 5",
    "gold": "Fixture Orbit · Tap Vocals. You earned gold stars on Tap Vocals for Fixture Orbit. Gold Stars. Jan 4",
    "difficulty": "Fixture Pulse · Lead. You improved your difficulty on Lead for Fixture Pulse from 2 to 3. "
                  "Difficulty Up. Jan 3",
    "pb": "Fixture Orbit · Drums. You set a new personal best on Drums for Fixture Orbit with 123,456 points. "
          "New High Score. Jan 2",
}


def open_flyout() -> list[str]:
    """Steps that open the flyout from the Songs page once the catalogue is up.

    Returns:
        Drive steps.
    """
    return ["waitfor:id=fst.songs.row.fixture-pulse@30", f"invoke:{BELL}", "waitfor:id=fst.notifications.sheet@10"]


def rows_present(section: str) -> list[str]:
    """Steps asserting every rich row is on screen in one section.

    Args:
        section: ``New`` or ``Older``.

    Returns:
        Drive steps.
    """
    other = "Older" if section == "New" else "New"
    return [
        "waitfor:id=fst.notifications.list@15",
        f"waitfor:name={section} notifications",
        f"waitgone:name={other} notifications",
        *[f"waitfor:{ROW}fixture-notif-{row}" for row in RICH_ROWS],
    ]


# name -> (environment, route, steps, sizes or None for every size).
# {shot:NAME} becomes a screenshot with --shots; @feed=… switches the fixture (a new drive phase).
SCENARIOS: dict[str, tuple[dict[str, str], str, list[str], set[str] | None]] = {
    "no-profile": (
        # Windows shows the bell only with a selected profile (operator 2026-09-28): no bell, no flyout, no request.
        ANONYMOUS, "/songs",
        [
            "waitfor:id=fst.songs.row.fixture-pulse@30",
            "waitfor:id=fst.shell.profile",
            "wait:2",
            f"waitgone:{BELL}",
            "waitgone:id=fst.notifications.sheet",
            "{shot:notifications-no-profile}",
            "?reads=0",
        ],
        None,
    ),
    "empty-generated": (
        PLAYER, "/songs",
        [
            "@feed=empty",
            *open_flyout(),
            "waitfor:id=fst.notifications.empty@15",
            "waitfor:name=No notifications available",
            f"waitfor:name={GENERATED_BODY}",
            "waitgone:id=fst.notifications.list",
            "assertstate:" + BELL + "|name=Notifications",
            "{shot:notifications-empty-generated}",
        ],
        None,
    ),
    "empty-not-generated": (
        PLAYER, "/songs",
        [
            "@feed=not-generated",
            *open_flyout(),
            "waitfor:id=fst.notifications.empty@15",
            f"waitfor:name={NOT_GENERATED_BODY}",
            "waitgone:id=fst.notifications.list",
            "{shot:notifications-empty-not-generated}",
        ],
        None,
    ),
    "unread-section": (
        # loaded + unread-section: a fresh seen store, so every row is New and the bell counts them.
        PLAYER, "/songs",
        [
            "waitfor:id=fst.songs.row.fixture-pulse@30",
            "assertstate:" + BELL + "|name=Notifications, 5 unread@15",
            f"invoke:{BELL}",
            *rows_present("New"),
            f"assertstate:{ROW}fixture-notif-rank|name=Unread. {RANK_ROW} Jan 5",
            "{shot:notifications-unread}",
        ],
        None,
    ),
    "older-section": (
        # Closing the flyout marks every loaded row seen: reopening lists them under Older and the badge goes away.
        PLAYER, "/songs",
        [
            *open_flyout(),
            *rows_present("New"),
            "key:esc",
            "waitgone:id=fst.notifications.sheet@5",
            "assertstate:" + BELL + "|name=Notifications@5",
            f"invoke:{BELL}",
            *rows_present("Older"),
            f"assertstate:{ROW}fixture-notif-rank|name={RANK_ROW} Jan 5",
            "{shot:notifications-older}",
        ],
        None,
    ),
    "tap-no-destination": (
        # An aggregate improvement has no destination: it becomes seen, the flyout stays open, nothing navigates.
        PLAYER, "/songs",
        [
            *open_flyout(),
            *rows_present("New"),
            f"invoke:{ROW}fixture-notif-total",
            "wait:1",
            "waitfor:id=fst.notifications.list@5",
            f"assertstate:{ROW}fixture-notif-total|name={TOTAL_ROW} Jan 2@5",
            "assertstate:" + BELL + "|name=Notifications, 4 unread@5",
            "waitfor:id=fst.songs.row.fixture-pulse",
        ],
        {"medium"},
    ),
    "tap-navigate-song": (
        # Song destination: the flyout closes, Song Detail opens on the Songs stack and Back returns to Songs.
        PLAYER, "/songs",
        [
            *open_flyout(),
            *rows_present("New"),
            f"invoke:{ROW}fixture-notif-rank",
            "waitgone:id=fst.notifications.sheet@5",
            "waitfor:id=fst.song-detail.title@15",
            "waitfor:name=Fixture Pulse",
            # Dismissing the flyout marks every loaded row seen (spec), so the badge clears.
            "assertstate:" + BELL + "|name=Notifications@5",
            "{shot:notifications-song-detail}",
            "invoke:id=PART_BackButton",
            "waitfor:id=fst.songs.row.fixture-pulse@15",
        ],
        None,
    ),
    "tap-navigate-rankings": (
        # Rank destination: Leaderboards opens ranked by the row's metric (FC Rate, not the Total Score default).
        PLAYER, "/songs",
        [
            *open_flyout(),
            *rows_present("New"),
            f"invoke:{ROW}fixture-notif-fcrate",
            "waitgone:id=fst.notifications.sheet@5",
            "waitfor:name=Rank by: FC Rate@20",
            "assertstate:" + BELL + "|name=Notifications@5",
            "{shot:notifications-rankings}",
        ],
        None,
    ),
    "failed-retry": (
        PLAYER, "/songs",
        [
            "@feed=error",
            *open_flyout(),
            "waitfor:id=fst.notifications.failed@15",
            "waitfor:id=fst.notifications.retry",
            "waitgone:id=fst.notifications.list",
            "{shot:notifications-failed}",
            "@feed=rich",
            "invoke:id=fst.notifications.retry",
            *rows_present("New"),
            "waitgone:id=fst.notifications.failed",
        ],
        {"medium"},
    ),
    "media-rows": (
        # Issue #272: the web NotificationRow media rail and flag chips. A multi-chart row (art above an instrument grid)
        # names its charts like the web grid's aria-label; one row per remaining flag kind; the time is spoken only.
        PLAYER, "/songs",
        [
            "@feed=media",
            *open_flyout(),
            "waitfor:id=fst.notifications.list@15",
            *[f"waitfor:{ROW}fixture-notif-{row}@10" for row in MEDIA_ROWS[:3]],
            "assertstate:" + BELL + f"|name=Notifications, {len(MEDIA_ROWS)} unread@5",
            *[f"assertstate:{ROW}fixture-notif-{row}|name=Unread. {MEDIA_NAMES[row]}" for row in MEDIA_ROWS[:3]],
            "{shot:notifications-media}",
            f"scrollinto:{ROW}fixture-notif-{MEDIA_ROWS[-1]}",
            *[f"waitfor:{ROW}fixture-notif-{row}@5" for row in MEDIA_ROWS[3:]],
            *[f"assertstate:{ROW}fixture-notif-{row}|name=Unread. {MEDIA_NAMES[row]}" for row in MEDIA_ROWS[3:]],
            "{shot:notifications-media-end}",
        ],
        None,
    ),
    "loading": (
        # The read is held only once the flyout is open (Retry from failed), so lock queuing cannot outrun the ring.
        PLAYER, "/songs",
        [
            "@feed=error",
            *open_flyout(),
            "waitfor:id=fst.notifications.retry@15",
            "@feed=slow",
            "invoke:id=fst.notifications.retry",
            "waitfor:id=fst.notifications.loading@10",
            "waitgone:id=fst.notifications.failed",
            "waitgone:id=fst.notifications.list",
            "{shot:notifications-loading}",
            "@feed=rich",
            *rows_present("New"),
            "waitgone:id=fst.notifications.loading",
        ],
        {"medium"},
    ),
}


def uiwin(*args: str) -> None:
    """Runs one uiwin.py command, raising on failure.

    Args:
        args: Command-line arguments after ``uiwin.py``.

    Raises:
        RuntimeError: The command failed.
    """
    result = subprocess.run([sys.executable, str(UIWIN), *args], capture_output=True, text=True,
                            encoding="utf-8", errors="replace")
    if result.returncode != 0:
        raise RuntimeError(f"uiwin {' '.join(args[:2])} failed:\n{result.stdout}\n{result.stderr}")


def phases(steps: list[str], shots: Path | None, size: str) -> list[tuple[str | None, list[str]]]:
    """Splits a scenario into drive phases at ``@`` fixture switches and ``?`` fixture checks, expanding ``{shot:NAME}``.

    Args:
        steps: Scenario steps.
        shots: Screenshot directory, or ``None`` to drop shots.
        size: Window preset used in screenshot names.

    Returns:
        ``(control or None, drive steps)`` pairs in order. A control is ``feed=…`` (applied before its steps run) or
        ``?reads=N`` (checked before its steps run).
    """
    out: list[tuple[str | None, list[str]]] = [(None, [])]
    for step in steps:
        if step.startswith("@"):
            out.append((step[1:], []))
        elif step.startswith("?"):
            out.append((step, []))
        elif step.startswith("{shot:"):
            if shots is not None:
                out[-1][1].append(f"shot:{shots / (step[6:-1] + '-' + size + '.png')}")
        else:
            out[-1][1].append(step)
    return [phase for phase in out if phase[0] is not None or phase[1]]


def control(port: int, query: str) -> dict:
    """Switches the fixture's feed mode.

    Args:
        port: Fixture port.
        query: ``feed=…`` and/or ``reset=1``; empty to only read the state.

    Returns:
        The fixture's state (``feed`` and ``reads``).
    """
    with urllib.request.urlopen(f"http://127.0.0.1:{port}/__notifications__/mode?{query}", timeout=5) as response:
        return json.loads(response.read())


def check(port: int, expectation: str) -> None:
    """Checks a ``?reads=N`` expectation against the fixture.

    Args:
        port: Fixture port.
        expectation: ``?reads=N``.

    Raises:
        RuntimeError: The fixture served a different number of notifications reads.
    """
    key, _, value = expectation[1:].partition("=")
    seen = control(port, "")[key]
    if str(seen) != value:
        raise RuntimeError(f"fixture {key} is {seen}, expected {value}")


def run(name: str, port: int, shots: Path | None, size: str) -> None:
    """Launches, drives and closes one scenario with throwaway settings and app data.

    Args:
        name: Scenario key.
        port: Fixture port.
        shots: Screenshot directory, if any.
        size: Window preset.
    """
    env, route, steps, _ = SCENARIOS[name]
    plan = phases(steps, shots, size)
    control(port, "feed=rich&reset=1")
    # A switch before the first drive step applies before launch (the app reads the feed at launch).
    if plan and plan[0][0] is not None:
        control(port, plan[0][0])
        plan[0] = (None, plan[0][1])
    with tempfile.TemporaryDirectory() as folder:
        settings_path = Path(folder) / "settings.json"
        settings_path.write_text(json.dumps({"version": 1}), encoding="utf-8")
        args = ["launch", str(EXE), "--timeout", "60", "--wait", "1", "--preset", size,
                "--extra", f"FST_SETTINGS_PATH={settings_path}",
                "--extra", f"FST_DEBUG_DATA_DIR={Path(folder) / 'data'}",
                "--route", route, f"--arg=--base-url=http://127.0.0.1:{port}/"]
        for key, value in env.items():
            args += ["--extra", f"{key}={value}"]
        uiwin(*args)
        try:
            for index, (query, drive) in enumerate(plan):
                if query is not None and query.startswith("?"):
                    check(port, query)
                elif query is not None:
                    control(port, query)
                if drive:
                    steps_file = Path(folder) / f"steps-{index}.txt"
                    steps_file.write_text("\n".join(drive), encoding="utf-8")
                    uiwin("drive", "--steps-file", str(steps_file))
            print(f"PASS {name} [{size}]", flush=True)
        finally:
            uiwin("close")


def main() -> int:
    """Runs the selected scenarios.

    Returns:
        Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--shots", type=Path)
    parser.add_argument("--only", help=f"comma-separated scenarios ({', '.join(SCENARIOS)})")
    parser.add_argument("--sizes", default="compact,medium,wide", help="comma-separated window presets")
    journey_exe.add_argument(parser)
    options = parser.parse_args()
    names = options.only.split(",") if options.only else list(SCENARIOS)
    if unknown := [name for name in names if name not in SCENARIOS]:
        parser.error(f"unknown scenario(s): {', '.join(unknown)}")
    global EXE
    EXE = options.exe
    if options.shots:
        options.shots.mkdir(parents=True, exist_ok=True)
    failures = 0
    with tempfile.TemporaryDirectory() as folder:
        server, port = ui_journey.start_mock(Path(folder) / "fixture.log", fixture=FIXTURE)
        try:
            for name in names:
                sizes = SCENARIOS[name][3]
                for size in options.sizes.split(","):
                    if sizes is not None and size not in sizes:
                        continue
                    try:
                        run(name, port, options.shots, size)
                    except RuntimeError as error:
                        failures += 1
                        print(f"FAIL {name} [{size}]: {error}", flush=True)
        finally:
            server.terminate()
            server.wait(timeout=10)
    print(f"{'FAILED' if failures else 'OK'}: {failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
