"""Songs Filter (``fst.songs.filter``) state journeys on Windows through uiwin.py (FlaUI driver).

One scenario per reachable state of ``.agents/controls/songs-filter/spec.md`` that the Windows live-apply flyout has
(see ``.agents/controls/songs-filter/windows.md`` for the unreachable ones). Each scenario starts the synthetic fixture
(``songs_filter_fixture.py``, Item Shop feed ``demo``/``empty``/``error``) on a private loopback port, launches the
Debug app with a throwaway settings file (``FST_SETTINGS_PATH``) and drives it by ``fst.*`` AutomationIds using only UIA
patterns and posted keys, so every step also works on a locked console. A scenario may relaunch the app on the same
settings file (``RELAUNCH``) to prove persistence. ``{status:TEXT}`` dumps the UIA tree and checks the Filter button's
item status (``""`` = none); ``{scan:NAME}`` runs Axe.Windows and fails on any error. Never touches the live service.

Usage: ``python tools/windows/songs_filter_journey.py [--port 18761] [--shots DIR] [--only NAME[,NAME…]]
[--sizes compact,medium,wide] [--exe debug|release|PATH]``
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import journey_exe  # noqa: E402  (sibling module)
from uiwin import framework_popup_finding  # noqa: E402  (sibling tool; windows-accessibility.md open item 8)

ROOT = Path(__file__).resolve().parents[2]
UIWIN = ROOT / "tools" / "windows" / "uiwin.py"
FIXTURE = ROOT / "tools" / "windows" / "songs_filter_fixture.py"
EXE = journey_exe.DEBUG_EXE
PLAYER = {"FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1"}
ANONYMOUS = {"FST_DEBUG_ANONYMOUS": "1"}
SAVED_PLAYER = {"accountId": "fixture-player-1", "displayName": "Fixture Player 1"}
RELAUNCH = "RELAUNCH"
PULSE, ORBIT = "id=fst.songs.row.fixture-pulse", "id=fst.songs.row.fixture-orbit"
NO_RESULTS = "name=No Results"
SHOP_LOADS = "Item Shop filters paused until Item Shop data loads. Showing all songs; your choice is saved."
SCORE_PAUSED = ("Player score filters paused until the player's scores and songs are from the same update. "
                "Showing songs without score filters.")


@dataclass(frozen=True)
class Scenario:
    """One Songs Filter state journey.

    Attributes:
        states: Spec state IDs this scenario proves.
        steps: uiwin drive steps; ``RELAUNCH`` restarts the app on the same settings file.
        env: Launch environment (debug profile hooks).
        settings: Initial settings (schema v3) merged into ``{"version": 3}``.
        shop: Fixture Item Shop feed: ``demo``, ``empty`` or ``error``.
    """

    states: tuple[str, ...]
    steps: list[str]
    env: dict[str, str] = field(default_factory=lambda: dict(PLAYER))
    settings: dict = field(default_factory=dict)
    shop: str = "demo"


def opened(*ready: str) -> list[str]:
    """Steps that wait for the list, then open the Filter flyout.

    Args:
        ready: Extra selectors that must be on screen before opening.

    Returns:
        Steps.
    """
    return [f"waitfor:{PULSE}@20", *(f"waitfor:{selector}@10" for selector in ready),
            "expand:id=fst.songs.filter", "waitfor:id=fst.songs.filter.reset@5"]


def bucket(section: str, key: str | None = None) -> list[str]:
    """Steps that empty one Selected Instrument bucket section (No Results), then restore it.

    Args:
        section: ``season``, ``percentile``, ``stars`` or ``intensity``.
        key: Optional bucket key toggled back on before Select All (proves a single switch applies live).

    Returns:
        Steps (flyout open, Lead selected).
    """
    steps = [f"scrollinto:id=fst.songs.filter.{section}@5", f"expand:id=fst.songs.filter.{section}",
             f"scrollinto:id=fst.songs.filter.{section}.clear-all@5", f"invoke:id=fst.songs.filter.{section}.clear-all",
             f"waitfor:{NO_RESULTS}@10", f"waitgone:{PULSE}@5", f"{{shot:filter-{section}}}"]
    if key is not None:
        steps += [f"scrollinto:id=fst.songs.filter.{section}.{key}@5", f"toggle:id=fst.songs.filter.{section}.{key}",
                  f"waitgone:{NO_RESULTS}@10"]
    return steps + [f"scrollinto:id=fst.songs.filter.{section}.select-all@5",
                    f"invoke:id=fst.songs.filter.{section}.select-all", f"waitfor:{PULSE}@10", f"waitfor:{ORBIT}",
                    f"scrollinto:id=fst.songs.filter.{section}@5", f"collapse:id=fst.songs.filter.{section}"]


LEAD = ["scrollinto:id=fst.songs.filter.instrument.compact@5", "toggle:id=fst.songs.filter.instrument.compact",
        "scrollinto:id=fst.songs.filter.season@5"]

SCENARIOS: dict[str, Scenario] = {
    "anonymous": Scenario(
        ("anonymous-hidden", "discard-confirm"),
        [*opened(), "waitfor:id=fst.songs.filter.general", "waitfor:id=fst.songs.filter.year",
         "waitfor:id=fst.songs.filter.duration", "waitfor:id=fst.songs.filter.shop", "waitfor:id=fst.songs.filter.double-bass",
         # No player: General only; no score, instrument or band sections; live apply has no Cancel/Apply.
         "waitgone:id=fst.songs.filter.score.global", "waitgone:id=fst.songs.filter.instrument-filters",
         "waitgone:id=fst.songs.filter.cancel", "waitgone:id=fst.songs.filter.apply",
         "{shot:filter-anonymous}", "{scan:filter-anonymous}", "collapse:id=fst.songs.filter", "{status:}"],
        env=dict(ANONYMOUS)),
    "anonymous-general": Scenario(
        ("anonymous-hidden", "applied", "relaunch-persisted"),
        # Issue #273 (#77): with no player, Double Bass / Year / Duration narrow the list live, mark Filter, survive a
        # relaunch and keep narrowing once a player is selected. The fixture marks Pulse supported, Orbit unsupported.
        [*opened(), "waitgone:id=fst.songs.filter.score.global",
         "scrollinto:id=fst.songs.filter.double-bass@5", "expand:id=fst.songs.filter.double-bass",
         "scrollinto:id=fst.songs.filter.double-bass.unsupported@5",
         "toggle:id=fst.songs.filter.double-bass.unsupported", f"waitgone:{ORBIT}@10", f"waitfor:{PULSE}",
         "{shot:filter-anonymous-double-bass}",
         "toggle:id=fst.songs.filter.double-bass.unsupported", f"waitfor:{ORBIT}@10",
         "toggle:id=fst.songs.filter.double-bass.supported", f"waitgone:{PULSE}@10", f"waitfor:{ORBIT}",
         "scrollinto:id=fst.songs.filter.year@5", "expand:id=fst.songs.filter.year",
         "scrollinto:id=fst.songs.filter.year.clear-all@5", "invoke:id=fst.songs.filter.year.clear-all",
         f"waitfor:{NO_RESULTS}@10", f"waitgone:{ORBIT}@5",
         "scrollinto:id=fst.songs.filter.year.select-all@5", "invoke:id=fst.songs.filter.year.select-all",
         f"waitfor:{ORBIT}@10", "scrollinto:id=fst.songs.filter.year@5", "collapse:id=fst.songs.filter.year",
         "scrollinto:id=fst.songs.filter.duration@5", "expand:id=fst.songs.filter.duration",
         "scrollinto:id=fst.songs.filter.duration.clear-all@5", "invoke:id=fst.songs.filter.duration.clear-all",
         f"waitfor:{NO_RESULTS}@10", f"waitgone:{ORBIT}@5",
         "scrollinto:id=fst.songs.filter.duration.select-all@5", "invoke:id=fst.songs.filter.duration.select-all",
         f"waitfor:{ORBIT}@10", "collapse:id=fst.songs.filter", "{status:Filters applied}",
         "{shot:filter-anonymous-applied}",
         RELAUNCH,
         f"waitfor:{ORBIT}@20", f"waitgone:{PULSE}@5", "{status:Filters applied}",
         "invoke:id=fst.shell.profile", "waitfor:id=fst.profile.search@5",
         "setvalue:id=fst.profile.search|Fixture Player 1", "waitfor:name=Fixture Player 1@10",
         "invoke:name=Fixture Player 1", "waitfor:id=fst.player.select@15", "invoke:id=fst.player.select",
         "waitfor:id=fst.player.deselect@10", "key:alt+left", "waitfor:id=fst.songs.filter@15",
         f"waitfor:{ORBIT}@10", f"waitgone:{PULSE}@5", "{status:Filters applied}",
         "expand:id=fst.songs.filter", "waitfor:id=fst.songs.filter.reset@5", "waitfor:id=fst.songs.filter.score.global@10",
         "scrollinto:id=fst.songs.filter.double-bass@5", "expand:id=fst.songs.filter.double-bass",
         "{toggle:fst.songs.filter.double-bass.supported=Off}", "{toggle:fst.songs.filter.double-bass.unsupported=On}",
         "{shot:filter-anonymous-general-player}",
         "invoke:id=fst.songs.filter.reset", f"waitfor:{PULSE}@10", "collapse:id=fst.songs.filter", "{status:}"],
        env={}),
    "player-loaded": Scenario(
        ("player-loaded", "normal-audit"),
        [*opened(), "waitfor:id=fst.songs.filter.score.global", "scrollinto:id=fst.songs.filter.score-sections@5",
         "scrollinto:id=fst.songs.filter.instrument-filters@5", "scrollinto:id=fst.songs.filter.instrument.compact@5",
         "waitgone:id=fst.songs.filter.cancel", "{shot:filter-player}", "{scan:filter-player}",
         "collapse:id=fst.songs.filter", "{status:}"]),
    "score": Scenario(
        ("score", "applied", "relaunch-persisted"),
        # Pro Lead Missing Scores: Orbit (Pro Lead unscored) stays; Pulse has no Pro Lead chart, so it drops.
        [*opened(), "scrollinto:id=fst.songs.filter.score.chart.prolead@5", "expand:id=fst.songs.filter.score.chart.prolead",
         "scrollinto:id=fst.songs.filter.score.chart.prolead.missing-scores@5",
         "toggle:id=fst.songs.filter.score.chart.prolead.missing-scores", f"waitgone:{PULSE}@10", f"waitfor:{ORBIT}",
         "{shot:filter-score}", "collapse:id=fst.songs.filter", "{status:Filters applied}", "{shot:filter-applied}",
         RELAUNCH,
         f"waitfor:{ORBIT}@20", f"waitgone:{PULSE}@5", "{status:Filters applied}",
         *opened()[1:], "scrollinto:id=fst.songs.filter.score.chart.prolead@5",
         "expand:id=fst.songs.filter.score.chart.prolead", "{toggle:fst.songs.filter.score.chart.prolead.missing-scores=On}",
         "invoke:id=fst.songs.filter.reset", f"waitfor:{PULSE}@10",
         "{toggle:fst.songs.filter.score.chart.prolead.missing-scores=Off}", "collapse:id=fst.songs.filter",
         "{status:}"],
        # Debug-profile launches keep settings in memory; persistence needs the file store with a saved player.
        env={}, settings={"selectedPlayer": SAVED_PLAYER}),
    "full-combo": Scenario(
        ("full-combo",),
        [*opened(), "expand:id=fst.songs.filter.score.global",
         "scrollinto:id=fst.songs.filter.score.global.has-fcs@5", "toggle:id=fst.songs.filter.score.global.has-fcs",
         "wait:1", "{shot:filter-full-combo}",
         "toggle:id=fst.songs.filter.score.global.has-fcs", f"waitfor:{PULSE}@10", f"waitfor:{ORBIT}",
         "scrollinto:id=fst.songs.filter.score.global.missing-fcs@5", "toggle:id=fst.songs.filter.score.global.missing-fcs",
         "wait:1", "{shot:filter-missing-fc}", "invoke:id=fst.songs.filter.reset", f"waitfor:{PULSE}@10"]),
    "instrument": Scenario(
        ("instrument", "season", "percentile", "stars", "intensity"),
        [*opened(), *LEAD, "{shot:filter-instrument}", "{scan:filter-instrument}",
         *bucket("season"), *bucket("percentile"), *bucket("stars"), *bucket("intensity"),
         "collapse:id=fst.songs.filter", "{status:Filters applied}",
         *opened()[1:], "invoke:id=fst.songs.filter.reset", "collapse:id=fst.songs.filter", "{status:}"]),
    "shop": Scenario(
        ("shop-draft", "leaving-draft", "reset-draft", "applied", "relaunch-persisted"),
        # Orbit is Leaving Tomorrow, Pulse is a current offer: both count as Available (retired Leaving draft).
        [*opened(), "expand:id=fst.songs.filter.shop", "waitfor:id=fst.songs.filter.shop-available@5",
         "toggle:id=fst.songs.filter.shop-unavailable", f"waitfor:{PULSE}@10", f"waitfor:{ORBIT}",
         "toggle:id=fst.songs.filter.shop-available", f"waitfor:{NO_RESULTS}@10", f"waitgone:{ORBIT}@5",
         "{shot:filter-shop-draft}", "collapse:id=fst.songs.filter", "{status:Filters applied}",
         f"waitfor:{NO_RESULTS}@5", "waitgone:name=Clear Filters", "{shot:filter-shop-applied}",
         RELAUNCH,
         f"waitfor:{NO_RESULTS}@20", "{status:Filters applied}", "expand:id=fst.songs.filter",
         "waitfor:id=fst.songs.filter.reset@5", "expand:id=fst.songs.filter.shop",
         "waitfor:id=fst.songs.filter.shop-available@5", "{toggle:fst.songs.filter.shop-available=Off}",
         "{toggle:fst.songs.filter.shop-unavailable=Off}", "invoke:id=fst.songs.filter.reset", f"waitfor:{PULSE}@10",
         f"waitfor:{ORBIT}", "{toggle:fst.songs.filter.shop-available=On}", "{toggle:fst.songs.filter.shop-unavailable=On}",
         "{shot:filter-reset}", "collapse:id=fst.songs.filter", "{status:}"],
        env={}, settings={"selectedPlayer": SAVED_PLAYER}),
    "shop-hidden": Scenario(
        ("shop-hidden-paused",),
        # A saved Shop choice is inert while the Shop is hidden (web behavior): no Shop section, nothing hidden.
        [f"waitfor:{PULSE}@20", f"waitfor:{ORBIT}", "{status:}", "expand:id=fst.songs.filter",
         "waitfor:id=fst.songs.filter.reset@5", "waitgone:id=fst.songs.filter.shop", "{shot:filter-shop-hidden}",
         "collapse:id=fst.songs.filter"],
        settings={"hideShop": True, "songShopFilter": {"available": False, "unavailable": True}}),
    "shop-unavailable": Scenario(
        ("shop-unavailable-paused",),
        [f"waitfor:{PULSE}@20", f"waitfor:{ORBIT}", "waitfor:class=Microsoft.UI.Xaml.Controls.InfoBar@10",
         f"waitfor:name={SHOP_LOADS}@5", "{status:Filters applied}", "{shot:filter-shop-paused}", "{scan:filter-shop-paused}"],
        settings={"songShopFilter": {"available": False, "unavailable": True}}, shop="error"),
    "shop-empty": Scenario(
        ("shop-validated-empty", "shop-sort-badges-suppressed"),
        # A validated empty feed: nothing is Available, so "Available only" is a real No Results (never a pause). The
        # shared empty state has no Clear Filters button (empty-error-states R8, #377): the flyout's Reset is the way back.
        [f"waitfor:{NO_RESULTS}@20", f"waitgone:name={SHOP_LOADS}", "waitgone:name=Clear Filters",
         "{status:Filters applied}", "{shot:filter-shop-empty}", "expand:id=fst.songs.filter",
         "waitfor:id=fst.songs.filter.reset@5", "invoke:id=fst.songs.filter.reset", f"waitfor:{PULSE}@10",
         f"waitfor:{ORBIT}", "collapse:id=fst.songs.filter", "{status:}"],
        settings={"songShopFilter": {"available": True, "unavailable": False}}, shop="empty"),
    "player-unavailable": Scenario(
        ("player-unavailable",),
        # 403 scores: a score check pauses with a notice and the list keeps every song.
        [*opened(), "scrollinto:id=fst.songs.filter.score.chart.prolead@5", "expand:id=fst.songs.filter.score.chart.prolead",
         "scrollinto:id=fst.songs.filter.score.chart.prolead.missing-scores@5",
         "toggle:id=fst.songs.filter.score.chart.prolead.missing-scores", "collapse:id=fst.songs.filter",
         f"waitfor:name={SCORE_PAUSED}@10", f"waitfor:{PULSE}", f"waitfor:{ORBIT}", "{shot:filter-player-unavailable}"],
        env={"FST_DEBUG_PROFILE": "fixture-denied:Denied Player"}),
    "player-loading-shop": Scenario(
        ("player-loading-shop-active",),
        # 202 syncing scores: the public Shop filter still applies (both songs are offers -> No Results).
        [f"waitfor:name=Scores syncing@20", *opened()[1:], "expand:id=fst.songs.filter.shop",
         "toggle:id=fst.songs.filter.shop-available", "collapse:id=fst.songs.filter", f"waitfor:{NO_RESULTS}@10",
         f"waitgone:{PULSE}", "{status:Filters applied}", "{shot:filter-loading-shop}"],
        env={"FST_DEBUG_PROFILE": "fixture-syncing:Syncing Player"}),
    "deselect": Scenario(
        ("deselected-paused", "reselected-restored-native"),
        # Deselect resets every filter like the web (#359): General too. Reselecting does not restore them.
        [*opened(), "scrollinto:id=fst.songs.filter.score.chart.prolead@5", "expand:id=fst.songs.filter.score.chart.prolead",
         "scrollinto:id=fst.songs.filter.score.chart.prolead.missing-scores@5",
         "toggle:id=fst.songs.filter.score.chart.prolead.missing-scores", f"waitgone:{PULSE}@10",
         "scrollinto:id=fst.songs.filter.double-bass@5", "expand:id=fst.songs.filter.double-bass",
         "toggle:id=fst.songs.filter.double-bass.unsupported", "collapse:id=fst.songs.filter",
         "key:ctrl+shift+p", "waitfor:id=fst.profile.deselect@5", "invoke:id=fst.profile.deselect",
         "waitfor:id=PrimaryButton@10", "invoke:id=PrimaryButton", "waitgone:id=PrimaryButton@10",
         "{status:}", "expand:id=fst.songs.filter", "waitfor:id=fst.songs.filter.reset@5",
         "waitgone:id=fst.songs.filter.score.global", "scrollinto:id=fst.songs.filter.double-bass@5",
         "expand:id=fst.songs.filter.double-bass", "{toggle:fst.songs.filter.double-bass.unsupported=On}",
         "{shot:filter-deselected}", "collapse:id=fst.songs.filter",
         "invoke:id=fst.shell.profile", "waitfor:id=fst.profile.search@5",
         "setvalue:id=fst.profile.search|Fixture Player 1", "waitfor:name=Fixture Player 1@10",
         "invoke:name=Fixture Player 1", "waitfor:id=fst.player.select@15", "invoke:id=fst.player.select",
         "waitfor:id=fst.player.deselect@10", "key:alt+left", "waitfor:id=fst.songs.filter@15",
         "expand:id=fst.songs.filter", "waitfor:id=fst.songs.filter.reset@5", "wait:2", "scrollinto:id=fst.songs.filter.score.global@10",
         "scrollinto:id=fst.songs.filter.score.chart.prolead@5", "expand:id=fst.songs.filter.score.chart.prolead",
         "{toggle:fst.songs.filter.score.chart.prolead.missing-scores=Off}",
         "scrollinto:id=fst.songs.filter.double-bass@5", "expand:id=fst.songs.filter.double-bass",
         "{toggle:fst.songs.filter.double-bass.unsupported=On}", "{shot:filter-reselected}",
         "invoke:id=fst.songs.filter.reset", "collapse:id=fst.songs.filter", "{status:}"]),
}


def uiwin(*args: str) -> str:
    """Runs one uiwin.py command.

    Args:
        args: Command-line arguments after ``uiwin.py``.

    Returns:
        Standard output.

    Raises:
        RuntimeError: Non-zero exit.
    """
    result = subprocess.run([sys.executable, str(UIWIN), *args], capture_output=True, text=True, encoding="utf-8",
                            errors="replace")
    if result.returncode != 0:
        raise RuntimeError(f"uiwin {' '.join(args[:2])} failed:\n{result.stdout[-3000:]}\n{result.stderr[-3000:]}")
    return result.stdout


def status_of(tree: str, automation_id: str = "fst.songs.filter") -> str | None:
    """Reads an element's UIA item status from a ``tree:`` dump.

    Args:
        tree: Tree text.
        automation_id: Element AutomationId (default: the Filter button).

    Returns:
        The status (``""`` when none), or ``None`` when the element is missing.
    """
    for line in tree.splitlines():
        if f" id={automation_id} " in line:
            match = re.search(r' status="([^"]*)"', line)
            return match.group(1) if match else ""
    return None


def toggle_of(tree: str, automation_id: str) -> str | None:
    """Reads a toggle's state (``On``/``Off``) from a ``tree:`` dump.

    Args:
        tree: Tree text.
        automation_id: Toggle AutomationId.

    Returns:
        The state, or ``None`` when the element or its state is missing.
    """
    for line in tree.splitlines():
        if f" id={automation_id} " in line:
            match = re.search(r" toggle=(\w+)", line)
            return match.group(1) if match else None
    return None


def compile_steps(steps: list[str], work: Path, shots: Path | None, size: str,
                  phase: int = 0) -> tuple[list[str], list[tuple[Path, str, str]]]:
    """Expands placeholders into uiwin steps.

    ``{status:TEXT}`` checks the Filter button's item status; ``{toggle:ID=On|Off}`` checks a switch's state.

    Args:
        steps: Scenario steps for one launch.
        work: Scratch folder for tree dumps and scans.
        shots: Screenshot folder, or ``None``.
        size: Window preset (file-name suffix).
        phase: Launch index (keeps tree dumps of a relaunch apart).

    Returns:
        Drive steps and the (tree file, kind, expected) checks to run afterwards.
    """
    out: list[str] = []
    checks: list[tuple[Path, str, str]] = []
    for step in steps:
        if step.startswith("{shot:"):
            if shots is not None:
                out.append(f"shot:{shots / (step[6:-1] + '-' + size + '.png')}")
        elif step.startswith("{scan:"):
            out.append(f"scan:{work / (step[6:-1] + '-' + size)}")
        elif step.startswith(("{status:", "{toggle:")):
            kind, _, expected = step[1:-1].partition(":")
            tree = work / f"tree-{phase}-{len(checks)}.txt"
            out.append(f"tree:{tree}")
            checks.append((tree, kind, expected))
        else:
            out.append(step)
    return out, checks


def check_tree(tree: str, kind: str, expected: str) -> str | None:
    """Evaluates one tree check.

    Args:
        tree: Tree text.
        kind: ``status`` or ``toggle``.
        expected: Expected status text, or ``ID=State`` for a toggle.

    Returns:
        A failure message, or ``None`` when it holds.
    """
    if kind == "status":
        actual = status_of(tree)
        return None if actual == expected else f"Filter item status {actual!r}, expected {expected!r}"
    automation_id, _, state = expected.partition("=")
    actual = toggle_of(tree, automation_id)
    return None if actual == state else f"{automation_id} toggle {actual!r}, expected {state!r}"


def scan_errors(stdout: str) -> list[str]:
    """Collects Axe.Windows failures from a drive response, minus the known framework popup-host finding.

    Args:
        stdout: uiwin drive output (JSON response).

    Returns:
        One message per scan with app errors.
    """
    start = stdout.find("{")
    try:
        response = json.loads(stdout[start:]) if start >= 0 else {}
    except json.JSONDecodeError:
        return []
    messages = []
    for scan in response.get("scans", []):
        findings = [f for f in scan.get("findings") or [] if not framework_popup_finding(f)]
        if scan.get("errors") and (findings or not scan.get("findings")):
            messages.append(f"{scan.get('scan_id')}: {len(findings) or scan.get('errors')} Axe error(s) "
                            f"{json.dumps(findings)[:900]}")
    return messages


def run(name: str, port: int, shots: Path | None, size: str) -> None:
    """Launches, drives and closes one scenario (relaunching on the same settings file when asked).

    Args:
        name: Scenario key.
        port: Fixture port.
        shots: Screenshot folder, if any.
        size: Window preset.

    Raises:
        RuntimeError: A step, status check or scan failed.
    """
    scenario = SCENARIOS[name]
    with tempfile.TemporaryDirectory() as folder:
        work = Path(folder)
        settings_path = work / "settings.json"
        settings_path.write_text(json.dumps({"version": 3, **scenario.settings}), encoding="utf-8")
        phases, current = [], []
        for step in scenario.steps:
            if step == RELAUNCH:
                phases.append(current)
                current = []
            else:
                current.append(step)
        phases.append(current)
        for index, phase in enumerate(phases):
            args = ["launch", str(EXE), "--timeout", "60", "--wait", "1", "--preset", size,
                    "--extra", f"FST_SETTINGS_PATH={settings_path}", f"--arg=--base-url=http://127.0.0.1:{port}/",
                    "--route", "/songs"]
            for key, value in scenario.env.items():
                args += ["--extra", f"{key}={value}"]
            uiwin(*args)
            try:
                steps, checks = compile_steps(phase, work, shots, size if index == 0 else f"{size}-relaunch", index)
                steps_file = work / "steps.txt"
                steps_file.write_text("\n".join(steps), encoding="utf-8")
                stdout = uiwin("drive", "--steps-file", str(steps_file))
            finally:
                uiwin("close")
            for tree, kind, expected in checks:
                if failure := check_tree(tree.read_text(encoding="utf-8", errors="replace"), kind, expected):
                    raise RuntimeError(f"{failure} ({tree.name})")
            if errors := scan_errors(stdout):
                raise RuntimeError("; ".join(errors))
    print(f"PASS {name} [{size}] ({', '.join(scenario.states)})")


def start_fixture(shop: str, port: int) -> subprocess.Popen:
    """Starts the Shop-scenario fixture and waits until it answers.

    Args:
        shop: Item Shop feed.
        port: Loopback port.

    Returns:
        The server process.
    """
    server = subprocess.Popen([sys.executable, str(FIXTURE), "--shop", shop, "--port", str(port)],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(50):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{port}/api/publication", timeout=1)
            break
        except OSError:
            time.sleep(0.2)
    return server


def main() -> int:
    """Runs the selected scenarios, grouped by fixture Shop feed.

    Returns:
        Process exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=18761)
    parser.add_argument("--shots", type=Path)
    parser.add_argument("--only", help=f"comma-separated scenarios ({', '.join(SCENARIOS)})")
    parser.add_argument("--sizes", default="medium", help="comma-separated presets for every scenario")
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
    for shop in dict.fromkeys(SCENARIOS[name].shop for name in names):
        server = start_fixture(shop, options.port)
        try:
            for name in (n for n in names if SCENARIOS[n].shop == shop):
                for size in options.sizes.split(","):
                    try:
                        run(name, options.port, options.shots, size)
                    except RuntimeError as error:
                        failures += 1
                        print(f"FAIL {name} [{size}]: {error}")
        finally:
            server.terminate()
            server.wait(timeout=10)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
