#!/usr/bin/env python3
"""Windows accessibility matrix: Axe.Windows scans, Tab walks and screenshots per page, size and mode.

Pages come from ``tools/windows/journeys/a11y.json`` (route/tab, optional fixture player, optional ``env``
launch hooks such as ``FST_DEBUG_CONTROL_LAB``, optional ``fixture`` flags such as ``["--band-rankings", "empty"]``,
readiness ``waitfor`` steps, optional setup steps such as opening a flyout). For every page the runner holds the
shared ``desktop`` lock once (≤300 s), optionally applies a system accessibility mode, launches this
worktree's build against the anonymized loopback fixture (``rivals_fixture.py``) with isolated settings
and app data, then for each window size: resize → setup → ready → screenshot → Axe.Windows scan → Tab
walk. System modes change the operator's real desktop, so they are applied inside the lock and the
previous values are always restored before it is released.

Modes: ``normal``; ``hc-aquatic``, ``hc-desert``, ``hc-dusk``, ``hc-night-sky`` (contrast themes);
``light-theme``, ``dark-theme`` (default app mode); ``scale-100``, ``scale-150`` (primary display scale);
``text-150``, ``text-200``, ``text-225`` (text size);
``no-animations`` (Animation effects off); ``no-transparency``;
``app-reduced`` (in-app Reduce Motion + Disable Animated Artwork + Save Data); ``app-contrast`` (in-app
More Contrast + Less Transparency). Join modes with ``+`` to combine them (``hc-desert+scale-150``: a contrast
theme on a page area wide enough for the Quick Links pane on a high-scale host).

Outputs in ``--out``: ``<page>-<size>[-<mode>].png``, ``results.json`` and ``summary.md`` (page × size:
Axe errors, tab stops, stops outside the app, repeated stops). Exit code 1 when any page failed to load
or (with ``--scan``) any scan reported errors.

Usage::

    python tools/windows/a11y_matrix.py --out out/a11y --scan --tabs 30
    python tools/windows/a11y_matrix.py --only songs,settings --sizes compact --mode hc-desert --out out/hc
    python tools/windows/a11y_matrix.py --pages tools/windows/journeys/a11y-keyboard.json --sizes medium --out out/kb
    python tools/windows/a11y_matrix.py --exe aot --scan --out out/aot   # NativeAOT Release in automation mode
"""

from __future__ import annotations

import argparse
import contextlib
import json
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import journey_exe  # noqa: E402  (sibling module: --exe debug|release|aot)
import uiwin  # noqa: E402  (sibling tool; provides the lock, driver and step parser)

REPO_ROOT = Path(__file__).resolve().parents[2]
PAGES = REPO_ROOT / "tools" / "windows" / "journeys" / "a11y.json"
FIXTURE = REPO_ROOT / "tools" / "windows" / "rivals_fixture.py"
#: Previous system values of an in-flight mode change. Written before ``sysset`` changes the operator's
#: desktop and removed after the restore, so a run killed mid-mode is repaired by the next run.
RESTORE_FILE = uiwin.EXCHANGE_DIR / "a11y-sysset-restore.json"

# region Modes (pure, unit-tested)

#: Mode → system settings (``FstUia sysset``) and in-app settings seeded into settings.json.
MODES: dict[str, dict] = {
    "normal": {},
    "hc-aquatic": {"system": {"high_contrast": "aquatic"}},
    "hc-desert": {"system": {"high_contrast": "desert"}},
    "hc-dusk": {"system": {"high_contrast": "dusk"}},
    "hc-night-sky": {"system": {"high_contrast": "night-sky"}},
    "light-theme": {"system": {"light_theme": True}},
    "dark-theme": {"system": {"light_theme": False}},
    "scale-100": {"system": {"display_scale": 100}},
    "scale-150": {"system": {"display_scale": 150}},
    "text-150": {"system": {"text_scale": 150}},
    "text-200": {"system": {"text_scale": 200}},
    "text-225": {"system": {"text_scale": 225}},
    "no-animations": {"system": {"animations": False}},
    "no-transparency": {"system": {"transparency": False}},
    "app-reduced": {"app": {"reduceMotion": True, "disableAnimatedArtwork": True, "saveData": True}},
    "app-contrast": {"app": {"moreContrast": True, "lessTransparency": True}},
}


def mode_spec(mode: str) -> dict:
    """Merged settings for a mode or a ``+``-joined combination (e.g. ``hc-desert+scale-150``).

    A combination lets a check that needs a wide page area (the Quick Links pane at ≥ 1150 epx) run in a contrast
    theme or at a larger text size on a high-scale host; later parts win on a shared key.

    Args:
        mode: A ``MODES`` key, or keys joined with ``+``.

    Returns:
        ``{"system": {...}, "app": {...}}`` with only the non-empty parts.

    Raises:
        ValueError: A part is not a known mode.
    """
    merged: dict = {}
    for part in mode.split("+"):
        if part not in MODES:
            raise ValueError(f"unknown mode {part!r}; use {', '.join(sorted(MODES))} (join with +)")
        for kind, values in MODES[part].items():
            merged.setdefault(kind, {}).update(values)
    return merged


def restore_values(previous: dict, applied: dict) -> dict:
    """The subset of ``previous`` settings that ``applied`` changed (what to restore).

    Args:
        previous: ``sysset`` ``previous`` values.
        applied: Settings that were set.

    Returns:
        ``{key: previous value}`` for every applied key.
    """
    return {key: previous[key] for key in applied if key in previous}


def pending_restore(path: Path) -> dict:
    """System values a killed run failed to restore.

    Args:
        path: Restore file.

    Returns:
        ``sysset`` values to apply, or ``{}`` when there is nothing (or nothing readable) to restore.
    """
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def page_steps(page: dict, size: str, out: Path, suffix: str, scan: bool, tabs: int) -> list[str]:
    """Drive steps for one page at one size.

    Args:
        page: Page definition: ``ready`` steps, optional ``setup`` (before ready), ``after_ready``
            (e.g. open a flyout), ``teardown`` (e.g. Esc) and ``tabs``. ``{stem}`` in any step is
            replaced by the output path stem for this page/size/mode, so extra shots such as
            ``shot:{stem}-footer.png`` stay distinct per run.
        size: Window preset.
        out: Output directory.
        suffix: File-name suffix for the mode (``""`` for normal).
        scan: Run an Axe.Windows scan.
        tabs: Default Tab presses (page ``tabs`` overrides; 0 skips the walk).

    Returns:
        Step strings for ``uiwin.parse_step``.
    """
    stem = f"{page['name']}-{size}{suffix}"
    steps = [f"resize:{size}", "wait:1.5", *page.get("setup", []), *page.get("ready", []),
             *page.get("after_ready", []), "wait:0.5",
             f"shot:{out / (stem + '.png')}"]
    if scan:
        steps.append(f"scan:{out / 'axe' / stem}")
    count = page.get("tabs", tabs)
    if count:
        steps.append(f"tabwalk:{count}")
    steps.extend(page.get("teardown", []))
    return [s.replace("{stem}", str(out / stem)) for s in steps]


def summarize_focus(focus: list[dict]) -> dict:
    """Tab-walk statistics for one size.

    Args:
        focus: ``tabwalk`` entries.

    Returns:
        Unique in-app stops, stops outside the app, consecutive repeats (possible traps) and the order.
    """
    order: list[str] = []
    for entry in focus:
        label = entry.get("id") or entry.get("name") or entry.get("type") or "?"
        if entry.get("in_window") and label not in order:
            order.append(label)
    return {"stops": len(order), "outside": sum(1 for e in focus if not e.get("in_window")),
            "repeats": sum(1 for e in focus if e.get("repeat")), "order": order}


def summary_table(results: list[dict]) -> str:
    """Markdown summary of a run.

    Args:
        results: Per page × size records.

    Returns:
        Markdown table text.
    """
    lines = ["| Page | Size | Mode | Loaded | Axe errors | Tab stops | Outside app | Repeats |",
             "|---|---|---|---|---|---|---|---|"]
    for r in results:
        focus = r.get("focus") or {}
        axe = "–" if r.get("axe_errors") is None else str(r["axe_errors"])
        lines.append(f"| {r['page']} | {r['size']} | {r['mode']} | {'yes' if r['ok'] else 'NO: ' + r.get('error', '')[:60]} "
                     f"| {axe} | {focus.get('stops', '–')} | {focus.get('outside', '–')} | {focus.get('repeats', '–')} |")
    return "\n".join(lines) + "\n"

# endregion

# region Runner


def start_fixture(log: Path, extra: tuple[str, ...] = (), fixture: Path = FIXTURE) -> tuple[subprocess.Popen, int]:
    """Start the anonymized fixture service on a free loopback port.

    Args:
        log: Service output file.
        extra: Additional fixture flags (a page's ``fixture`` list, e.g. ``--band-rankings empty``).
        fixture: Fixture script taking ``mock_service.py`` flags (default ``rivals_fixture.py``).

    Returns:
        Process and port.

    Raises:
        RuntimeError: No port reported within 20 s.
    """
    handle = log.open("w", encoding="utf-8")
    proc = subprocess.Popen([sys.executable, "-u", str(fixture), "--port", "0", *extra], stdout=handle,
                            stderr=subprocess.STDOUT)
    for _ in range(200):
        match = re.search(r"127\.0\.0\.1:(\d+)", log.read_text(encoding="utf-8", errors="replace"))
        if match:
            return proc, int(match.group(1))
        time.sleep(0.1)
    proc.kill()
    raise RuntimeError(f"fixture service did not start; see {log}")


def run_page(page: dict, mode: str, sizes: list[str], exe: Path, port: int, out: Path, scan: bool,
             tabs: int, hold: float) -> list[dict]:
    """Run one page at every size; each size is a fresh launch under its own desktop-lock hold.

    A fresh launch per size keeps sizes independent (a Tab walk scrolls content and moves focus).

    Args:
        page: Page definition.
        mode: Mode name (``MODES``).
        sizes: Window presets.
        exe: App executable.
        port: Fixture port.
        out: Output directory.
        scan: Run Axe.Windows scans.
        tabs: Default Tab presses.
        hold: Lock hold seconds.

    Returns:
        One record per size.
    """
    return [run_size(page, mode, size, exe, port, out, scan, tabs, hold) for size in sizes]


def page_env(page: dict, data_dir: Path) -> dict[str, str]:
    """Automation environment for one matrix page.

    Args:
        page: Page entry (``profile``, ``tab``, ``route`` and optional ``env`` launch hooks such as
            ``FST_DEBUG_CONTROL_LAB``; page ``env`` wins over the derived values).
        data_dir: Isolated app data directory.

    Returns:
        Environment variables to add to the app launch.
    """
    env = {"FST_DEBUG_DATA_DIR": str(data_dir)}
    if page.get("profile"):
        env["FST_DEBUG_PROFILE"] = page["profile"]
    else:
        env["FST_DEBUG_ANONYMOUS"] = "1"
    env.update(uiwin.launch_env(page.get("tab"), page.get("route"), None))
    env.update({key: str(value) for key, value in page.get("env", {}).items()})
    return env

def run_size(page: dict, mode: str, size: str, exe: Path, port: int, out: Path, scan: bool, tabs: int,
             hold: float) -> dict:
    """Launch, check and close one page at one size (see :func:`run_page`)."""
    spec = mode_spec(mode)
    suffix = "" if mode == "normal" else f"-{mode}"
    state = Path(tempfile.mkdtemp(prefix=f"fst-a11y-{page['name']}-"))
    settings = state / "settings.json"
    if spec.get("app") or page.get("settings"):
        settings.write_text(json.dumps({**page.get("settings", {}), **spec.get("app", {})}), encoding="utf-8")
    env = page_env(page, state / "data")
    warning = uiwin.prepare_automation(exe, env)
    if warning:
        print(f"warning: {warning}", file=sys.stderr)
    args = ["--base-url", f"http://127.0.0.1:{port}/", f"--first-run={page.get('first_run', 'off')}",
            f"--settings-path={settings}"]
    record: dict = {"page": page["name"], "size": size, "mode": mode, "ok": False}
    lock = uiwin.HostLock("desktop", purpose=f"a11y {page['name']} {size} {mode} [{REPO_ROOT.name}]",
                          hold_seconds=hold, wait_seconds=1800)
    with lock:
        applied = spec.get("system") or {}
        previous: dict = {}
        pid = None
        leftover = pending_restore(RESTORE_FILE)
        if leftover:
            print(f"warning: restoring system settings left by a killed run: {leftover}", file=sys.stderr)
            uiwin.run_driver({"command": "sysset", "set": leftover}, lock)
            RESTORE_FILE.unlink(missing_ok=True)
        try:
            if applied:
                current = uiwin.run_driver({"command": "sysset", "set": {}}, lock)["current"]
                previous = restore_values(current, applied)
                RESTORE_FILE.parent.mkdir(parents=True, exist_ok=True)
                RESTORE_FILE.write_text(json.dumps(previous), encoding="utf-8")
                uiwin.run_driver({"command": "sysset", "set": applied}, lock)
            launched = uiwin.run_driver({"command": "launch", "exe": str(exe), "args": args, "env": env,
                                         "timeout": 30}, lock)
            pid = launched["pid"]
            steps = [uiwin.parse_step(s) for s in page_steps(page, size, out, suffix, scan, tabs)]
            result = uiwin.run_driver({"command": "drive", "pid": pid, "steps": steps}, lock,
                                      budget=lock.remaining())
            record["ok"] = True
            scans = result.get("scans") or []
            if scans:
                record["axe_errors"] = scans[0]["errors"]
                record["axe_findings"] = scans[0]["findings"]
            if "focus" in result:
                record["focus"] = summarize_focus(result["focus"])
                record["focus_raw"] = [e["line"] for e in result["focus"]]
            record["window"] = {k: result.get(k) for k in ("bounds_epx", "scale")}
        except RuntimeError as error:
            record["error"] = str(error)
            if pid:
                try:
                    uiwin.run_driver({"command": "shot", "pid": pid,
                                      "out": str(out / f"{page['name']}-{size}{suffix}-failure.png")}, lock)
                except RuntimeError:
                    pass
        finally:
            if pid:
                try:
                    uiwin.run_driver({"command": "close", "pid": pid}, lock)
                except RuntimeError as error:
                    print(f"warning: close failed: {error}", file=sys.stderr)
            if previous:
                uiwin.run_driver({"command": "sysset", "set": previous}, lock)
                RESTORE_FILE.unlink(missing_ok=True)
    print(f"{'PASS' if record['ok'] else 'FAIL'} {page['name']} {size} {mode}"
          + (f" axe={record.get('axe_errors')}" if scan and record["ok"] else "")
          + (f": {record.get('error')}" if not record["ok"] else ""), flush=True)
    return record


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        0 when every page loaded (and scans were clean with ``--scan``), 1 otherwise.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--only", help="comma-separated page names")
    parser.add_argument("--sizes", default="compact,medium,wide")
    parser.add_argument("--mode", default="normal",
                        help=f"one of {', '.join(sorted(MODES))}, or several joined with + (e.g. hc-desert+scale-150)")
    parser.add_argument("--scan", action="store_true", help="run Axe.Windows at every page/size")
    parser.add_argument("--tabs", type=int, default=0, help="Tab presses per page/size (0: no walk)")
    journey_exe.add_argument(parser)
    parser.add_argument("--hold", type=float, default=300.0)
    parser.add_argument("--pages", type=Path, default=PAGES,
                        help="page list (e.g. journeys/a11y-keyboard.json: assertfocus journeys, run without --scan)")
    parser.add_argument("--fixture", type=Path, default=FIXTURE,
                        help="fixture service script (e.g. tools/windows/rankings_fixture.py for every Full Rankings state)")
    args = parser.parse_args(argv)
    try:
        mode_spec(args.mode)
    except ValueError as error:
        parser.error(str(error))
    if not args.exe.is_file():
        print(f"error: build first (tools/windows/build.ps1); no {args.exe}", file=sys.stderr)
        return 1
    out = args.out.resolve()
    (out / "axe").mkdir(parents=True, exist_ok=True)
    pages = json.loads(args.pages.read_text(encoding="utf-8"))
    if args.only:
        wanted = set(args.only.split(","))
        pages = [p for p in pages if p["name"] in wanted]
    sizes = [s for s in args.sizes.split(",") if s]
    # One fixture service per distinct page ``fixture`` flag list (most pages share the default one).
    fixtures: dict[tuple[str, ...], tuple[subprocess.Popen, int]] = {}
    results: list[dict] = []
    try:
        # Driver step logs (every focus stop) go to a file; the console gets one line per page and size.
        with (out / "driver.log").open("a", encoding="utf-8") as log, contextlib.redirect_stderr(log):
            for page in pages:
                extra = tuple(page.get("fixture", ()))
                if extra not in fixtures:
                    fixtures[extra] = start_fixture(out / f"fixture-service-{len(fixtures)}.log", extra,
                                                    args.fixture.resolve())
                page_sizes = [s for s in sizes if s in page.get("sizes", sizes)]
                results.extend(run_page(page, args.mode, page_sizes, args.exe.resolve(), fixtures[extra][1], out,
                                        args.scan, args.tabs, args.hold))
    finally:
        for fixture, _ in fixtures.values():
            fixture.kill()
    name = "results.json" if args.mode == "normal" else f"results-{args.mode}.json"
    (out / name).write_text(json.dumps(results, indent=2), encoding="utf-8")
    (out / name.replace(".json", ".md").replace("results", "summary")).write_text(summary_table(results),
                                                                                 encoding="utf-8")
    print(summary_table(results))
    failed = [r for r in results if not r["ok"] or (args.scan and r.get("axe_errors"))]
    return 1 if failed else 0

# endregion


if __name__ == "__main__":
    sys.exit(main())
