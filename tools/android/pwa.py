#!/usr/bin/env python3
"""Installed-PWA reference lab for Android: Festival Score Tracker from Chrome on the FST AVDs.

Installs https://festivalscoretracker.com from Chrome's own menu on an FST
emulator, launches the installed app from its home-screen icon (Chrome's
standalone ``WebappActivity``), drives it with real touch input through the
DevTools protocol, and captures screenshots (``screencap`` of the physical
display, so status/navigation bars and the posture are included) and videos
(``screenrecord``, H.264).

Install path (documented): Chrome 149 on the ``google_apis_ps16k`` images
cannot mint a WebAPK (no signed-in Play Store), so *⋮ → Add to Home screen →
Install* falls back to a pinned launcher shortcut; the launcher then asks
*Add to home screen*. The shortcut still opens standalone (``display:
standalone``) in ``org.chromium.chrome.browser.webapps.WebappActivity``.

Chrome's first run is answered deterministically: usage/crash reporting is
switched off (*Manage* → switch → *Done*), *Stay signed out*, and *No thanks*
to notifications. Nothing else is accepted.

Every command holds the shared ``emulator`` lock (≤300 s) through
``device.py``'s helpers and boots the requested AVD if needed. System
animations are set to 1× for the hold and restored to 0 afterwards: Chrome
maps ``animator_duration_scale == 0`` to ``prefers-reduced-motion: reduce``,
which would hide the PWA's animations.

Examples::

    python tools/android/pwa.py setup --avd FST_Phone            # first run + install
    python tools/android/pwa.py launch --avd FST_Phone --reset-storage --shot out/songs.png
    python tools/android/pwa.py drive --avd FST_Phone --steps-file tools/android/pwa_journeys/pages.steps --out-dir out
    python tools/android/pwa.py drive --avd FST_Book_Fold --record out/fold.mp4 --steps "posture:half; wait:2; posture:unfolded; wait:2"

Drive steps are the shared web verbs from :mod:`tools.android.cdp` plus
``shot:<png>``, ``back`` (system back), ``home``, ``posture:<name>``,
``rotate:<0|90|180|270>``, ``relaunch`` (tap the home-screen icon again) and
``record:start:<mp4>``/``record:stop``.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.android import cdp  # noqa: E402
from tools.android import device as dv  # noqa: E402
from tools.android.hostlock import HostLock  # noqa: E402

# region Configuration

SITE = "https://festivalscoretracker.com/"
CHROME = "com.android.chrome"
WEBAPP_ACTIVITY = "org.chromium.chrome.browser.webapps.WebappActivity"

#: Home-screen label (manifest ``short_name``).
ICON = "FST"

#: Host port forwarded to Chrome's ``chrome_devtools_remote`` socket.
DEVTOOLS_PORT = 9444

#: Raw captures kept for ``motion`` analysis, outside the showcase budget.
RAW_DIR = Path.home() / ".fst-tools" / "pwa-raw" / "android"

ANIMATION_KEYS = ("window_animation_scale", "transition_animation_scale",
                  "animator_duration_scale")

#: Chrome first-run answers, in order; each is optional (tried when present).
FIRST_RUN_STEPS = [
    "waitfor:text=Stay signed out@20",
    "manage-usage",
    "tap:id=com.android.chrome:id/fre_uma_dialog_switch", "wait:1", "tap:text=Done", "wait:1",
    "tap:text=Stay signed out", "wait:3",
    "tap:text=No thanks", "wait:3",
]

#: Chrome menu install, then the launcher's pin confirmation.
INSTALL_STEPS = [
    "tap:id=com.android.chrome:id/menu_button", "wait:2",
    "tap:text=Add to Home screen", "wait:3",
    "tap:text=Install", "wait:10",
    "tap:text=Add to home screen", "wait:3",
]

#: Platform-specific drive verbs (on top of :data:`cdp.WEB_VERBS`).
PLATFORM_VERBS = {"shot": "path", "back": "none", "home": "none", "posture": "text",
                  "rotate": "text", "relaunch": "none", "record": "record"}

# endregion

# region Pure helpers (unit-tested)


def manage_link_point(bounds: str) -> tuple[int, int]:
    """Tap point for the *Manage* link that ends Chrome's first-run footer text.

    The link is the last word of the centred two-line footer, so it sits at the
    bottom-right of the text node.
    """
    left, top, right, bottom = dv.parse_bounds(bounds)
    return right - 65, bottom - 25


def parse_top_activity(dumpsys: str) -> str:
    """Component of the top resumed activity from ``dumpsys activity activities``."""
    match = re.search(r"topResumedActivity=ActivityRecord\{\S+ \S+ (\S+)", dumpsys)
    return match.group(1) if match else ""


def screenrecord_size(width: int, height: int) -> str:
    """``--size`` for screenrecord: the physical size capped at 1920 on the long side."""
    factor = min(1.0, 1920 / max(width, height))
    return f"{cdp.even(width * factor)}x{cdp.even(height * factor)}"

# endregion

# region Lab session


class AndroidLab:
    """Held emulator lock + booted AVD + (after ``connect``) the app page."""

    def __init__(self, lock: HostLock, avd: str):
        self.lock, self.avd = lock, avd
        self.device = dv.boot_exclusive(lock, avd, gpu="swiftshader_indirect", animations=True)
        for key in ANIMATION_KEYS:
            self.device.shell(f"settings put global {key} 1", check=False)
        self.cdp: cdp.Cdp | None = None
        self.page: cdp.PageDriver | None = None

    def close(self) -> None:
        """Drop the CDP connection and restore the lab-default animation scales (0)."""
        if self.cdp:
            try:
                self.cdp.close()
            except OSError:
                pass
        for key in ANIMATION_KEYS:
            self.device.shell(f"settings put global {key} 0", check=False)

    # region Device steps

    def tree(self) -> str:
        return self.device.dump_tree()

    def try_step(self, step: str) -> bool:
        """Run a ``device.py`` step; ``False`` if its node is absent."""
        if step == "manage-usage":
            match = re.search(r'<node [^>]*resource-id="com.android.chrome:id/signin_fre_footer"'
                              r'[^>]*bounds="([^"]+)"', self.tree())
            if not match:
                return False
            x, y = manage_link_point(match.group(1))
            self.device.shell(f"input tap {x} {y}")
            time.sleep(2)
            return True
        verb, arg = dv.parse_step(step)
        try:
            dv.run_step(self.device, self.avd, verb, arg)
            return True
        except dv.DeviceError:
            return False

    def top_activity(self) -> str:
        return parse_top_activity(self.device.shell("dumpsys activity activities", check=False))

    def installed(self) -> bool:
        """True if the home screen shows the app icon."""
        return self.find_icon()

    def find_icon(self, pages: int = 4) -> bool:
        """Go home and page right through the launcher until the app icon is visible."""
        self.device.shell("input keyevent KEYCODE_HOME")
        time.sleep(1.5)
        for _ in range(pages):
            if f'content-desc="{ICON}"' in self.tree():
                return True
            dv.run_step(self.device, self.avd, "swipe", "left")
            time.sleep(1.2)
        return False

    def open_icon(self, timeout: float = 20.0) -> float:
        """Tap the home-screen icon; return seconds until WebappActivity is on top."""
        if not self.find_icon():
            raise dv.DeviceError(f"no {ICON} icon on the home screens: run `pwa.py setup`")
        started = time.monotonic()
        dv.run_step(self.device, self.avd, "tap", f"desc={ICON}")
        while time.monotonic() - started < timeout:
            if WEBAPP_ACTIVITY in self.top_activity():
                return round(time.monotonic() - started, 2)
            time.sleep(0.2)
        raise dv.DeviceError("installed app did not reach WebappActivity")

    # endregion

    # region CDP

    def connect(self, timeout: float = 20.0) -> cdp.PageDriver:
        """Forward DevTools and attach to the installed app's page."""
        self.device.adb("forward", f"tcp:{DEVTOOLS_PORT}", "localabstract:chrome_devtools_remote")
        version = cdp.wait_for_devtools(DEVTOOLS_PORT, timeout)
        self.cdp = cdp.Cdp(version["webSocketDebuggerUrl"])
        deadline = time.monotonic() + timeout
        while True:
            pages = [t for t in self.cdp.send("Target.getTargets")["targetInfos"]
                     if t["type"] == "page" and t["url"].startswith(SITE)]
            if pages:
                break
            if time.monotonic() > deadline:
                raise dv.DeviceError("no festivalscoretracker.com page target")
            time.sleep(0.5)
        # Several tabs may exist (the install tab); the webapp page is the attached/visible one.
        page = next((p for p in pages if p.get("attached")), pages[-1])
        self.page = cdp.PageDriver(self.cdp, page["targetId"], touch=True)
        visible = self.page.eval("document.visibilityState")
        if visible != "visible":
            for other in pages:
                driver = cdp.PageDriver(self.cdp, other["targetId"], touch=True)
                if driver.eval("document.visibilityState") == "visible":
                    self.page = driver
                    break
        return self.page

    # endregion

    def shot(self, out: Path) -> dict:
        """Physical-display screenshot plus metadata (device + page) sidecar."""
        self.device.screenshot(out)
        meta = self.device.metadata(self.avd)
        meta["top_activity"] = self.top_activity()
        if self.page:
            try:
                meta["page"] = self.page.paint_timing()
            except cdp.CdpError:
                pass
        out.with_suffix(".json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
        return meta


class ScreenRecorder:
    """``adb shell screenrecord`` of the physical display showing logical display 0."""

    REMOTE = "/sdcard/fst-pwa.mp4"

    def __init__(self, lab: AndroidLab, out: Path):
        self.lab, self.out = lab, out
        self.raw = RAW_DIR / lab.avd / out.parent.name / (out.stem + ".raw.mp4")
        self.raw.parent.mkdir(parents=True, exist_ok=True)
        dev = lab.device
        physical = dv.default_physical_display(dev.shell("cmd display get-displays", check=False))
        width, height = dev.screen_size()
        args = [dv.adb_path(), "-s", dev.serial, "shell", "screenrecord", "--bit-rate", "8000000",
                "--size", screenrecord_size(width, height)]
        if physical:
            args += ["--display-id", physical]
        self.proc = lab.lock.track(subprocess.Popen([*args, self.REMOTE],
                                                    stdout=subprocess.DEVNULL,
                                                    stderr=subprocess.DEVNULL))
        time.sleep(1.0)
        self.started = time.monotonic()

    def stop(self) -> dict:
        """Stop recording, pull the raw file and write the small 540p clip."""
        self.lab.device.shell("pkill -INT screenrecord", check=False)
        try:
            self.proc.wait(timeout=20)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        time.sleep(1.0)
        self.lab.device.adb("pull", self.REMOTE, str(self.raw), cap=120)
        self.lab.device.shell(f"rm -f {self.REMOTE}", check=False)
        return cdp.finalize_clip(self.raw, self.out)

# endregion

# region Commands


def _lock(args: argparse.Namespace, purpose: str) -> HostLock:
    return HostLock("emulator", purpose=f"pwa {purpose} {args.avd} [{REPO_ROOT.name}]",
                    hold_seconds=args.hold, wait_seconds=args.wait_timeout)


def cmd_setup(args: argparse.Namespace) -> int:
    """Chrome first run (declining everything optional) and PWA install."""
    with _lock(args, "setup") as lock:
        lab = AndroidLab(lock, args.avd)
        try:
            if lab.installed() and not args.force:
                print(json.dumps({"avd": args.avd, "installed": True, "skipped": True}))
                return 0
            lab.device.shell(f"am start -a android.intent.action.VIEW -d {SITE} {CHROME}")
            time.sleep(8)
            answered = [s for s in FIRST_RUN_STEPS if lab.try_step(s)]
            time.sleep(4)
            installed = [s for s in INSTALL_STEPS if lab.try_step(s)]
            ok = lab.installed()
            print(json.dumps({"avd": args.avd, "first_run": answered, "install": installed,
                              "installed": ok}, indent=2))
            return 0 if ok else 3
        finally:
            lab.close()


def open_app(lab: AndroidLab, reset_storage: bool, route: str | None,
             posture: str | None) -> dict:
    """Pose the device, open the app from its icon and attach CDP."""
    if posture:
        dv.apply_pose(lab.device, lab.avd, posture)
    if reset_storage:
        # Cold start: background Chrome, then kill its process (``am kill`` rather
        # than force-stop, which leaves the package "stopped").
        lab.device.shell("input keyevent KEYCODE_HOME")
        time.sleep(1)
        lab.device.shell(f"am kill {CHROME}", check=False)
        time.sleep(1)
    opened = lab.open_icon()
    page = lab.connect()
    if reset_storage:
        page.eval("localStorage.clear(); sessionStorage.clear(); true")
        page.navigate(SITE)
    if route:
        page.eval(f"location.hash = {json.dumps('#' + route)}; true")
    return {"activity_s": opened}


def cmd_launch(args: argparse.Namespace) -> int:
    """Open the installed app (cold with ``--reset-storage``) and optionally screenshot."""
    with _lock(args, "launch") as lock:
        lab = AndroidLab(lock, args.avd)
        try:
            recorder = ScreenRecorder(lab, Path(args.record)) if args.record else None
            result = open_app(lab, args.reset_storage, args.route, args.posture)
            time.sleep(args.wait)
            result["page"] = lab.page.paint_timing()
            if recorder:
                result["video"] = recorder.stop()
            if args.shot:
                result["shot"] = lab.shot(Path(args.shot))
            print(json.dumps(result, indent=2))
        finally:
            lab.close()
    return 0


def parse_drive_steps(text: str | None, path: str | None,
                      values: dict[str, str] | None = None) -> list[tuple[str, str, bool]]:
    """Parse and validate drive steps (web + Android verbs)."""
    steps = []
    for step in cdp.expand_placeholders(cdp.split_steps(text, path), values or {}):
        verb, arg = cdp.parse_step(step, PLATFORM_VERBS)
        if verb == "record" and not (arg == "stop" or arg.startswith("start:")):
            raise ValueError("record: use start:<out.mp4> or stop")
        steps.append((verb, arg, cdp.is_optional(step)))
    return steps


def run_step(lab: AndroidLab, verb: str, arg: str, log: list[dict], started: float,
             recorder: ScreenRecorder | None) -> ScreenRecorder | None:
    """Execute one step; return the (possibly new) active recorder."""
    if cdp.run_web_step(lab.page, verb, arg, SITE, log, started):
        return recorder
    entry: dict = {"t": round(time.monotonic() - started, 3), "step": f"{verb}:{arg}"}
    if verb == "shot":
        entry["meta"] = {k: v for k, v in lab.shot(Path(arg)).items() if k != "page"}
    elif verb == "back":
        lab.device.shell("input keyevent KEYCODE_BACK")
    elif verb == "home":
        lab.device.shell("input keyevent KEYCODE_HOME")
    elif verb in ("posture", "rotate"):
        dv.run_step(lab.device, lab.avd, verb, arg)
        time.sleep(1.0)
        entry["wm_size"] = lab.device.shell("wm size").strip()
    elif verb == "relaunch":
        entry["activity_s"] = lab.open_icon()
    elif verb == "record":
        if arg.startswith("start"):
            recorder = ScreenRecorder(lab, Path(arg.partition(":")[2]))
            entry["t"] = 0.0
        elif recorder:
            entry["video"] = recorder.stop()
            recorder = None
    log.append(entry)
    return recorder


def cmd_drive(args: argparse.Namespace) -> int:
    """Open the app (unless ``--no-open``) and run steps against it."""
    values = {"out": (args.out_dir or ".").replace("\\", "/")}
    steps = parse_drive_steps(args.steps, args.steps_file, values)
    if args.record:
        steps = [("record", f"start:{args.record}", False), *steps, ("record", "stop", False)]
    log: list[dict] = []
    with _lock(args, "drive") as lock:
        lab = AndroidLab(lock, args.avd)
        recorder = None
        try:
            if WEBAPP_ACTIVITY not in lab.top_activity() or args.reset_storage or args.posture:
                log.append({"open": open_app(lab, args.reset_storage, args.route, args.posture)})
                time.sleep(args.wait)
            else:
                lab.connect()
                if args.route:
                    lab.page.eval(f"location.hash = {json.dumps('#' + args.route)}; true")
            started = time.monotonic()
            for verb, arg, optional in steps:
                if recorder:
                    started = recorder.started
                try:
                    recorder = run_step(lab, verb, arg, log, started, recorder)
                    if verb == "record" and arg.startswith("start"):
                        started = recorder.started
                except (cdp.CdpError, dv.DeviceError, OSError) as exc:
                    if not optional:
                        raise
                    log.append({"step": f"?{verb}:{arg}", "skipped": str(exc)[:120]})
                    print(f"skip ?{verb}:{arg}", file=sys.stderr)
                    continue
                print(f"ok {verb}:{arg}", file=sys.stderr)
        finally:
            if recorder:
                log.append({"step": "record:stop (implicit)", "video": recorder.stop()})
            if lab.cdp:
                blocked = cdp.blocked_requests(lab.cdp.events)
                if blocked:
                    log.append({"blocked_requests": blocked})
            lab.close()
            if args.log:
                Path(args.log).parent.mkdir(parents=True, exist_ok=True)
                Path(args.log).write_text(json.dumps(log, indent=2), encoding="utf-8")
    print(json.dumps(log[-3:], indent=2))
    return 0


def cmd_motion(args: argparse.Namespace) -> int:
    """Frame-step a recording and print bursts of change."""
    print(json.dumps(cdp.analyze_motion(Path(args.clip), args.crop, args.threshold, args.gap),
                     indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--hold", type=float, default=280.0, help="emulator-lock hold (≤300 s)")
    parser.add_argument("--wait-timeout", type=float, default=1800.0)
    sub = parser.add_subparsers(dest="cmd", required=True)

    def with_avd(p: argparse.ArgumentParser) -> argparse.ArgumentParser:
        p.add_argument("--avd", default=dv.DEFAULT_AVD)
        return p

    p = with_avd(sub.add_parser("setup"))
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_setup)
    for name, func in (("launch", cmd_launch), ("drive", cmd_drive)):
        p = with_avd(sub.add_parser(name))
        p.add_argument("--route")
        p.add_argument("--posture")
        p.add_argument("--reset-storage", action="store_true")
        p.add_argument("--record")
        p.add_argument("--wait", type=float, default=4.0)
        p.set_defaults(func=func)
        if name == "launch":
            p.add_argument("--shot")
        else:
            p.add_argument("--steps")
            p.add_argument("--steps-file")
            p.add_argument("--out-dir")
            p.add_argument("--log")
    p = sub.add_parser("motion")
    p.add_argument("clip")
    p.add_argument("--crop")
    p.add_argument("--threshold", type=float, default=0.04)
    p.add_argument("--gap", type=float, default=0.1)
    p.set_defaults(func=cmd_motion)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except (RuntimeError, ValueError, cdp.CdpError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main())

# endregion
