#!/usr/bin/env python3
"""Installed-PWA reference lab for Windows: Festival Score Tracker as an Edge app.

The web app (https://festivalscoretracker.com) is an installable PWA. This tool
installs it into an **isolated Edge profile** (``~/.fst-tools/pwa-edge``, never
the operator's own profile), launches it as a standalone app window, applies
the Windows window-size presets shared with ``uiwin.py``, drives it with real
input, and captures window screenshots and videos.

How install works (documented choice): Edge's DevTools protocol lists a
``PWA`` domain but Edge 155 does not implement ``PWA.install``/``PWA.launch``
("wasn't found"), so ``install`` drives the **real Edge UI** through
``uiwin.py`` (UIA): it opens the site in a normal tab of the isolated profile,
clicks the address-bar *App available. Install Festival Score Tracker* button
(``EdgePwaInstallView``), invokes **Install**, then answers the *App installed*
flyout with **Don't allow** (no taskbar/Start/Desktop pins, no auto-start).
``launch`` starts the installed app exactly like its Start-menu shortcut:
``msedge --user-data-dir=<lab profile> --profile-directory=Default
--app-id=<id>`` (the id is read from ``Default/Web Applications``), which hands
off to the running lab instance and opens the standalone app window. Routes
are hash routes (``/#/songs``): ``--route`` navigates the app page after launch.

Every command that touches the desktop holds the shared FIFO ``desktop`` host
lock (≤300 s), like ``uiwin.py``. Edge itself outlives each hold; ``stop``
closes it. This tool must run in the interactive console session (it drives
Edge directly rather than hopping through ``schtasks``).

Examples::

    python tools/windows/pwa.py start            # isolated Edge, no windows
    python tools/windows/pwa.py install          # Edge UI install (UIA), declines pins/auto-start
    python tools/windows/pwa.py launch --preset compact --route /songs --shot out/songs.png
    python tools/windows/pwa.py drive --record out/nav.mp4 --steps "click:text=Leaderboards; wait:2"
    python tools/windows/pwa.py shot out/x.png   # window incl. title bar (screen pixels)
    python tools/windows/pwa.py motion out/nav.raw.mp4 --crop 600:400:0:80
    python tools/windows/pwa.py stop

Drive steps are the shared web verbs from :mod:`tools.android.cdp`
(``click``/``tap``/``hover``/``waitfor``/``scrollto``/``scroll``/``key``/``type``/
``wait``/``nav``/``eval``/``cshot``/``anims``/``timing``/``mark``) plus
``shot:<png>`` (window with title bar), ``resize:<preset|WxH>``, ``back``
(Alt+Left, the installed window's back) and ``record:start:<mp4>``/``record:stop``.
"""

from __future__ import annotations

import argparse
import ctypes
import json
import os
import subprocess
import sys
import time
from ctypes import wintypes
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.android import cdp  # noqa: E402  (shared CDP client + step engine)
from tools.android.hostlock import HostLock  # noqa: E402

# region Configuration

#: Production origin (keyless public HTTPS; browsing is read-only).
SITE = "https://festivalscoretracker.com/"

#: Manifest id: the manifest has no ``id``, so it defaults to ``start_url``.
MANIFEST_ID = SITE

#: Address-bar install button and dialog buttons (Edge 155 UIA names/classes).
INSTALL_STEPS = [
    "waitfor:class=EdgePwaInstallView@20", "click:class=EdgePwaInstallView", "wait:2",
    "invoke:name=Install", "wait:4", "waitfor:name=Don't allow@15", "invoke:name=Don't allow",
    "wait:1",
]

#: Isolated Edge profile and DevTools port for the lab.
PROFILE_DIR = Path.home() / ".fst-tools" / "pwa-edge"
DEVTOOLS_PORT = 9377

#: Full-frame-rate raw captures (kept out of the showcase size budget) for ``motion``.
RAW_DIR = Path.home() / ".fst-tools" / "pwa-raw" / "windows"

#: Lab state (Edge pid, app target) shared across commands.
STATE_FILE = Path.home() / ".fst-locks" / "pwa-edge.json"

EDGE_CANDIDATES = [
    Path(os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)"))
    / "Microsoft" / "Edge" / "Application" / "msedge.exe",
    Path(os.environ.get("ProgramFiles", r"C:\Program Files"))
    / "Microsoft" / "Edge" / "Application" / "msedge.exe",
]

#: Edge flags: isolated, quiet first run, no sync/sign-in, no background apps.
EDGE_FLAGS = [
    f"--remote-debugging-port={DEVTOOLS_PORT}",
    "--remote-allow-origins=http://127.0.0.1",
    "--no-first-run", "--no-default-browser-check", "--no-startup-window",
    "--disable-sync", "--disable-background-networking",
    "--disable-features=msEdgeSignIn,msImplicitSignin,EdgeCollections,msUndersideButton",
]

#: Window presets (outer window size in effective pixels = DIPs), as in ``uiwin.py``.
PRESETS: dict[str, dict] = {
    "compact": {"kind": "size", "width": 500, "height": 800},
    "medium": {"kind": "size", "width": 900, "height": 700},
    "wide": {"kind": "size", "width": 1440, "height": 900},
    "portrait-tablet": {"kind": "size", "width": 800, "height": 1280},
    "snap-left": {"kind": "snap-left"},
    "snap-right": {"kind": "snap-right"},
    "maximized": {"kind": "maximized"},
    "full-screen": {"kind": "fullscreen"},
}

#: Platform-specific drive verbs (on top of :data:`cdp.WEB_VERBS`).
PLATFORM_VERBS = {"shot": "path", "resize": "preset", "back": "none", "record": "record"}

# endregion

# region Pure helpers (unit-tested)


def preset_bounds(preset: str, work: tuple[int, int, int, int]) -> dict:
    """Resolve a preset to CDP ``Browser.setWindowBounds`` bounds.

    Args:
        preset: Preset name or ``WxH`` (DIPs).
        work: Monitor work area ``(left, top, width, height)`` in DIPs.

    Returns:
        ``{"windowState": …}`` or ``{"left", "top", "width", "height"}``, sizes
        clamped to the work area and centred in it.

    Raises:
        ValueError: Unknown preset.
    """
    left, top, width, height = work
    spec = PRESETS.get(preset)
    if spec is None:
        try:
            w, h = (int(v) for v in preset.lower().split("x"))
        except ValueError:
            raise ValueError(f"unknown preset {preset!r}; use {', '.join(PRESETS)} or WxH") \
                from None
        spec = {"kind": "size", "width": w, "height": h}
    kind = spec["kind"]
    if kind == "maximized":
        return {"windowState": "maximized"}
    if kind == "fullscreen":
        return {"windowState": "fullscreen"}
    if kind in ("snap-left", "snap-right"):
        half = width // 2
        return {"left": left + (half if kind == "snap-right" else 0), "top": top,
                "width": half, "height": height}
    w, h = min(spec["width"], width), min(spec["height"], height)
    return {"left": left + (width - w) // 2, "top": top + (height - h) // 2,
            "width": w, "height": h}


def clamp_note(preset: str, bounds: dict) -> str | None:
    """Describe a preset that could not be applied at full size."""
    spec = PRESETS.get(preset) or {}
    if spec.get("kind") != "size" or "width" not in bounds:
        return None
    if (bounds["width"], bounds["height"]) != (spec["width"], spec["height"]):
        return (f"{preset} clamped to {bounds['width']}x{bounds['height']} "
                f"(requested {spec['width']}x{spec['height']})")
    return None


def gdigrab_args(rect: tuple[int, int, int, int], fps: int) -> list[str]:
    """ffmpeg input arguments to grab a screen rectangle (physical px)."""
    left, top, right, bottom = rect
    width, height = cdp.even(right - left), cdp.even(bottom - top)
    return ["-f", "gdigrab", "-framerate", str(fps), "-draw_mouse", "0",
            "-offset_x", str(left), "-offset_y", str(top),
            "-video_size", f"{width}x{height}", "-i", "desktop"]

# endregion

# region Win32


user32 = ctypes.windll.user32 if os.name == "nt" else None
dwmapi = ctypes.windll.dwmapi if os.name == "nt" else None


def dpi_aware() -> None:
    """Make this process per-monitor DPI aware (physical-pixel coordinates)."""
    try:
        user32.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
    except (AttributeError, OSError):
        pass


def edge_path() -> Path:
    """Locate ``msedge.exe``."""
    for candidate in EDGE_CANDIDATES:
        if candidate.is_file():
            return candidate
    raise RuntimeError("Microsoft Edge not found")


def process_tree(root: int) -> set[int]:
    """Return ``root`` and its descendant pids (via a CIM snapshot)."""
    out = subprocess.run(["powershell", "-NoProfile", "-Command",
                          "Get-CimInstance Win32_Process -Filter \"Name='msedge.exe'\" | "
                          "ForEach-Object { \"$($_.ProcessId) $($_.ParentProcessId)\" }"],
                         capture_output=True, text=True, timeout=60).stdout
    children: dict[int, list[int]] = {}
    for line in out.split("\n"):
        parts = line.split()
        if len(parts) == 2:
            children.setdefault(int(parts[1]), []).append(int(parts[0]))
    found, todo = {root}, [root]
    while todo:
        for child in children.get(todo.pop(), []):
            if child not in found:
                found.add(child)
                todo.append(child)
    return found


def app_windows(pids: set[int]) -> list[dict]:
    """Visible top-level Edge windows owned by ``pids``."""
    found: list[dict] = []

    @ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    def callback(hwnd, _):
        pid = wintypes.DWORD()
        user32.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
        if pid.value in pids and user32.IsWindowVisible(hwnd):
            cls = ctypes.create_unicode_buffer(256)
            user32.GetClassNameW(hwnd, cls, 256)
            title = ctypes.create_unicode_buffer(512)
            user32.GetWindowTextW(hwnd, title, 512)
            if cls.value == "Chrome_WidgetWin_1" and title.value:
                found.append({"hwnd": hwnd, "title": title.value, "pid": pid.value})
        return True

    user32.EnumWindows(callback, 0)
    return found


def window_rect(hwnd: int) -> tuple[int, int, int, int]:
    """Visible window bounds in physical px (DWM extended frame, no shadow)."""
    rect = wintypes.RECT()
    if dwmapi.DwmGetWindowAttribute(hwnd, 9, ctypes.byref(rect), ctypes.sizeof(rect)) != 0:
        user32.GetWindowRect(hwnd, ctypes.byref(rect))
    return rect.left, rect.top, rect.right, rect.bottom


def window_scale(hwnd: int) -> float:
    """Window DPI scale (1.5 at 150%)."""
    return user32.GetDpiForWindow(hwnd) / 96.0


def monitors() -> list[dict]:
    """Monitors in enumeration order: device name, primary flag, work area (px) and scale."""

    class MONITORINFOEX(ctypes.Structure):
        _fields_ = [("cbSize", wintypes.DWORD), ("rcMonitor", wintypes.RECT),
                    ("rcWork", wintypes.RECT), ("dwFlags", wintypes.DWORD),
                    ("szDevice", wintypes.WCHAR * 32)]

    found: list[dict] = []
    proto = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMONITOR, wintypes.HDC,
                               ctypes.POINTER(wintypes.RECT), wintypes.LPARAM)

    def callback(handle, _dc, _rect, _data):
        info = MONITORINFOEX()
        info.cbSize = ctypes.sizeof(info)
        user32.GetMonitorInfoW(handle, ctypes.byref(info))
        dpi_x, dpi_y = wintypes.UINT(), wintypes.UINT()
        ctypes.windll.shcore.GetDpiForMonitor(handle, 0, ctypes.byref(dpi_x), ctypes.byref(dpi_y))
        work = info.rcWork
        found.append({"device": info.szDevice, "primary": bool(info.dwFlags & 1),
                      "work_px": (work.left, work.top, work.right, work.bottom),
                      "scale": dpi_x.value / 96.0})
        return True

    user32.EnumDisplayMonitors(None, None, proto(callback), 0)
    return found


def lab_monitor(available: list[dict]) -> dict:
    """The monitor the lab uses: ``FST_PWA_MONITOR`` (1-based), else the last
    non-primary one, so other lanes' centred windows on the primary never occlude
    the gdigrab region."""
    wanted = os.environ.get("FST_PWA_MONITOR")
    if wanted:
        return available[int(wanted) - 1]
    secondary = [m for m in available if not m["primary"]]
    return (secondary or available)[-1]


def work_area_dip(monitor: dict) -> tuple[int, int, int, int]:
    """Work area as ``(left, top, width, height)`` in DIPs (Chromium window units)."""
    left, top, right, bottom = monitor["work_px"]
    scale = monitor["scale"]
    return (round(left / scale), round(top / scale),
            round((right - left) / scale), round((bottom - top) / scale))


def foreground(hwnd: int, topmost: bool) -> None:
    """Raise the window (optionally pinning it topmost so captures aren't occluded)."""
    insert = -1 if topmost else -2  # HWND_TOPMOST / HWND_NOTOPMOST
    user32.SetWindowPos(hwnd, insert, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040)
    user32.ShowWindow(hwnd, 9 if user32.IsIconic(hwnd) else 5)
    user32.SetForegroundWindow(hwnd)

# endregion

# region Lab session


class Lab:
    """Connection to the isolated Edge instance and its installed-app window."""

    def __init__(self):
        dpi_aware()
        version = cdp.wait_for_devtools(DEVTOOLS_PORT, timeout=5)
        self.cdp = cdp.Cdp(version["webSocketDebuggerUrl"])
        self.state = load_state()

    # region Targets

    def app_target(self) -> dict | None:
        """The installed app's page target (``type == "page"`` in an app window)."""
        targets = self.cdp.send("Target.getTargets")["targetInfos"]
        pages = [t for t in targets if t["type"] == "page" and t["url"].startswith(SITE)]
        wanted = self.state.get("target")
        for page in pages:
            if page["targetId"] == wanted:
                return page
        return pages[0] if pages else None

    def page(self, touch: bool = False) -> cdp.PageDriver:
        """Attach to the app page."""
        target = self.app_target()
        if not target:
            raise RuntimeError("no app window: run `pwa.py launch` first")
        return cdp.PageDriver(self.cdp, target["targetId"], touch=touch)

    def hwnd(self, timeout: float = 15.0) -> int:
        """The app window handle (waits for it to appear)."""
        deadline = time.monotonic() + timeout
        pids = process_tree(self.state["pid"])
        while True:
            windows = app_windows(pids)
            if windows:
                return windows[0]["hwnd"]
            if time.monotonic() > deadline:
                raise RuntimeError("app window not found")
            time.sleep(0.3)
            pids = process_tree(self.state["pid"])

    # endregion

    # region Window

    def resize(self, preset: str) -> dict:
        """Apply a window preset through ``Browser.setWindowBounds``."""
        target = self.app_target()
        window = self.cdp.send("Browser.getWindowForTarget", {"targetId": target["targetId"]})
        bounds = preset_bounds(preset, work_area_dip(lab_monitor(monitors())))
        wid = window["windowId"]
        if window["bounds"].get("windowState", "normal") != "normal":
            self.cdp.send("Browser.setWindowBounds", {"windowId": wid,
                                                      "bounds": {"windowState": "normal"}})
            time.sleep(0.4)
        self.cdp.send("Browser.setWindowBounds", {"windowId": wid, "bounds": bounds})
        time.sleep(0.8)
        note = clamp_note(preset, bounds)
        if note:
            print(f"warning: {note}", file=sys.stderr)
        return self.describe()

    def describe(self) -> dict:
        """Window bounds (px and DIP), scale, title and viewport."""
        hwnd = self.hwnd()
        left, top, right, bottom = window_rect(hwnd)
        scale = window_scale(hwnd)
        title = ctypes.create_unicode_buffer(512)
        user32.GetWindowTextW(hwnd, title, 512)
        return {"title": title.value, "rect_px": [left, top, right, bottom],
                "size_px": [right - left, bottom - top],
                "size_epx": [round((right - left) / scale), round((bottom - top) / scale)],
                "scale": scale, "work_area_epx": list(work_area_dip(lab_monitor(monitors())))}

    def shot(self, out: Path, page: cdp.PageDriver | None = None) -> dict:
        """Screenshot the app window as composited on screen, plus a JSON sidecar."""
        hwnd = self.hwnd()
        foreground(hwnd, topmost=True)
        time.sleep(0.35)
        rect = window_rect(hwnd)
        out.parent.mkdir(parents=True, exist_ok=True)
        try:
            subprocess.run([cdp.ffmpeg_path(), "-hide_banner", "-loglevel", "error", "-y",
                            *gdigrab_args(rect, 10), "-frames:v", "1", str(out)],
                           check=True, timeout=30)
        finally:
            foreground(hwnd, topmost=False)
        meta = self.describe()
        if page:
            meta["page"] = page.paint_timing()
        meta["captured"] = time.strftime("%Y-%m-%dT%H:%M:%S")
        out.with_suffix(".json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
        return meta

    # endregion


def load_state() -> dict:
    """Read the lab state file (``{}`` when absent)."""
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_state(state: dict) -> None:
    """Persist the lab state file."""
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2), encoding="utf-8")


class Recorder:
    """gdigrab recording of the app window into a raw H.264 file."""

    def __init__(self, lab: Lab, out: Path, fps: int, lock: HostLock):
        self.lab, self.out, self.fps = lab, out, fps
        self.raw = RAW_DIR / out.parent.name / (out.stem + ".raw.mp4")
        self.raw.parent.mkdir(parents=True, exist_ok=True)
        hwnd = lab.hwnd()
        foreground(hwnd, topmost=True)
        time.sleep(0.3)
        self.hwnd = hwnd
        rect = window_rect(hwnd)
        cmd = [cdp.ffmpeg_path(), "-hide_banner", "-loglevel", "error", "-y",
               *gdigrab_args(rect, fps), "-c:v", "libx264", "-preset", "ultrafast",
               "-crf", "18", "-pix_fmt", "yuv420p", str(self.raw)]
        self.proc = lock.track(subprocess.Popen(cmd, stdin=subprocess.PIPE))
        time.sleep(0.6)
        self.started = time.monotonic()

    def stop(self) -> dict:
        """Stop recording and write the small 540p clip next to the raw capture."""
        try:
            self.proc.communicate(b"q", timeout=30)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        foreground(self.hwnd, topmost=False)
        return cdp.finalize_clip(self.raw, self.out)

# endregion

# region Commands


def _lock(args: argparse.Namespace, purpose: str) -> HostLock:
    return HostLock("desktop", purpose=f"pwa {purpose} [{REPO_ROOT.name}]",
                    hold_seconds=args.hold, wait_seconds=args.wait_timeout)


def cmd_start(args: argparse.Namespace) -> int:
    """Start the isolated Edge instance (no windows) if it is not running."""
    try:
        version = cdp.wait_for_devtools(DEVTOOLS_PORT, timeout=1)
        print(json.dumps({"running": True, "browser": version.get("Browser")}))
        return 0
    except cdp.CdpError:
        pass
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
    proc = subprocess.Popen([str(edge_path()), f"--user-data-dir={PROFILE_DIR}", *EDGE_FLAGS],
                            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, creationflags=flags)
    version = cdp.wait_for_devtools(DEVTOOLS_PORT, timeout=30)
    state = load_state()
    state.update({"pid": proc.pid, "browser": version.get("Browser")})
    save_state(state)
    print(json.dumps({"started": proc.pid, "browser": version.get("Browser"),
                      "profile": str(PROFILE_DIR)}))
    return 0


def installed_app_id() -> str | None:
    """Edge's app id for the installed PWA (a ``Web Applications`` folder name)."""
    root = PROFILE_DIR / "Default" / "Web Applications" / "Manifest Resources"
    ids = sorted(p.name for p in root.glob("*") if len(p.name) == 32) if root.is_dir() else []
    return ids[0] if ids else None


def page_targets(lab: "Lab") -> list[dict]:
    """Page targets on the site (app windows and any site tabs)."""
    return [t for t in lab.cdp.send("Target.getTargets")["targetInfos"]
            if t["type"] == "page" and t["url"].startswith(SITE)]


def cmd_install(args: argparse.Namespace) -> int:
    """Install the PWA through Edge's own install UI (see module docs)."""
    lab = Lab()
    if installed_app_id() and not args.force:
        print(json.dumps({"installed": True, "app_id": installed_app_id()}))
        return 0
    tab = lab.cdp.send("Target.createTarget", {"url": SITE, "newWindow": True})["targetId"]
    time.sleep(4)
    uiwin = [sys.executable, str(REPO_ROOT / "tools" / "windows" / "uiwin.py")]
    subprocess.run([*uiwin, "drive", "--pid", str(lab.state["pid"]),
                    "--steps", "; ".join(INSTALL_STEPS)], check=True, timeout=900)
    try:
        lab.cdp.send("Target.closeTarget", {"targetId": tab})
    except cdp.CdpError:
        pass
    app_id = installed_app_id()
    if not app_id:
        raise RuntimeError("install finished but no app id under Web Applications")
    lab.state["app_id"] = app_id
    save_state(lab.state)
    print(json.dumps({"installed": True, "app_id": app_id}))
    return 0


def cmd_uninstall(args: argparse.Namespace) -> int:
    """Uninstall by deleting the isolated profile (Edge must be stopped first)."""
    cmd_stop(args)
    time.sleep(2)
    import shutil

    shutil.rmtree(PROFILE_DIR, ignore_errors=True)
    print(json.dumps({"uninstalled": True, "profile_removed": str(PROFILE_DIR)}))
    return 0


def launch_app(lab: "Lab", fresh: bool, timeout: float = 30.0) -> str:
    """Open the installed app window like its Start-menu shortcut; return its target id."""
    app_id = installed_app_id()
    if not app_id:
        raise RuntimeError("PWA not installed: run `pwa.py install`")
    if fresh:
        for target in page_targets(lab):
            lab.cdp.send("Target.closeTarget", {"targetId": target["targetId"]})
        time.sleep(1.0)
    before = {t["targetId"] for t in page_targets(lab)}
    subprocess.Popen([str(edge_path()), f"--user-data-dir={PROFILE_DIR}",
                      "--profile-directory=Default", f"--app-id={app_id}"],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        new = [t for t in page_targets(lab) if t["targetId"] not in before]
        if new:
            lab.state["target"] = new[0]["targetId"]
            save_state(lab.state)
            return new[0]["targetId"]
        time.sleep(0.1)
    raise RuntimeError("app window did not open")


def cmd_launch(args: argparse.Namespace) -> int:
    """Open the installed app window (optionally at a route), resize and screenshot."""
    lab = Lab()
    with _lock(args, "launch") as lock:
        started = time.monotonic()
        target = launch_app(lab, args.fresh)
        opened = round(time.monotonic() - started, 2)
        hwnd = lab.hwnd()
        page = cdp.PageDriver(lab.cdp, target)
        if args.reset_storage:
            page.eval("localStorage.clear(); sessionStorage.clear(); true")
            page.navigate(SITE)
        if args.preset:
            lab.resize(args.preset)
        recorder = Recorder(lab, Path(args.record), args.fps, lock) if args.record else None
        if args.route:
            page.navigate(SITE + "#" + args.route)
        if args.ready:
            page.waitfor(args.ready, timeout=args.timeout)
        else:
            time.sleep(args.wait)
        result = {"target": target, "hwnd": hwnd, "window_open_s": opened,
                  "ready_s": round(time.monotonic() - started, 2),
                  "window": lab.describe(), "page": page.paint_timing()}
        if recorder:
            time.sleep(args.wait)
            result["video"] = recorder.stop()
        if args.shot:
            result["shot"] = lab.shot(Path(args.shot), page)
    print(json.dumps(result, indent=2))
    return 0


def cmd_resize(args: argparse.Namespace) -> int:
    """Apply a window preset."""
    lab = Lab()
    with _lock(args, f"resize {args.preset}"):
        print(json.dumps(lab.resize(args.preset), indent=2))
    return 0


def cmd_window(args: argparse.Namespace) -> int:
    """Describe the app window."""
    print(json.dumps(Lab().describe(), indent=2))
    return 0


def cmd_shot(args: argparse.Namespace) -> int:
    """Screenshot the app window (``--content`` for page pixels only)."""
    lab = Lab()
    page = lab.page()
    with _lock(args, "shot"):
        if args.content:
            page.screenshot(Path(args.out))
            print(args.out)
        else:
            print(json.dumps(lab.shot(Path(args.out), page), indent=2))
    return 0


def run_steps(lab: Lab, page: cdp.PageDriver, steps: list[tuple[str, str, bool]], lock: HostLock,
              fps: int, log: list[dict]) -> None:
    """Execute parsed drive steps against the app window."""
    started = time.monotonic()
    recorder: Recorder | None = None
    try:
        for verb, arg, optional in steps:
            if recorder:
                started = recorder.started
            try:
                run_step(lab, page, verb, arg, lock, fps, log, started, recorder)
            except (cdp.CdpError, RuntimeError, OSError) as exc:
                if not optional:
                    raise
                log.append({"step": f"?{verb}:{arg}", "skipped": str(exc)[:120]})
                print(f"skip ?{verb}:{arg}", file=sys.stderr)
                continue
            if verb == "record":
                recorder = log[-1].pop("_recorder", None)
            print(f"ok {verb}:{arg}", file=sys.stderr)
    finally:
        if recorder:
            log.append({"step": "record:stop (implicit)", "video": recorder.stop()})


def run_step(lab: Lab, page: cdp.PageDriver, verb: str, arg: str, lock: HostLock, fps: int,
             log: list[dict], started: float, recorder: "Recorder | None") -> None:
    """Execute one step (shared web verb or Windows verb)."""
    if cdp.run_web_step(page, verb, arg, SITE, log, started):
        return
    entry = {"t": round(time.monotonic() - started, 3), "step": f"{verb}:{arg}"}
    if verb == "shot":
        entry["meta"] = lab.shot(Path(arg))
    elif verb == "resize":
        entry["window"] = lab.resize(arg)
    elif verb == "back":
        page.key("alt+left")
    elif verb == "record":
        if arg.startswith("start"):
            entry["_recorder"] = Recorder(lab, Path(arg.partition(":")[2]), fps, lock)
            entry["t"] = 0.0
        elif recorder:
            entry["video"] = recorder.stop()
            entry["_recorder"] = None
    log.append(entry)


def parse_drive_steps(text: str | None, path: str | None,
                      values: dict[str, str] | None = None) -> list[tuple[str, str]]:
    """Parse and validate drive steps (web + platform verbs)."""
    steps = []
    for step in cdp.expand_placeholders(cdp.split_steps(text, path), values or {}):
        verb, arg = cdp.parse_step(step, PLATFORM_VERBS)
        optional = cdp.is_optional(step)
        if verb == "record" and not (arg == "stop" or arg.startswith("start:")):
            raise ValueError("record: use start:<out.mp4> or stop")
        if verb == "resize":
            preset_bounds(arg, (0, 0, 10_000, 10_000))
        steps.append((verb, arg, optional))
    return steps


def cmd_drive(args: argparse.Namespace) -> int:
    """Run steps against the launched app (optionally recording the whole run)."""
    values = {"out": (args.out_dir or ".").replace("\\", "/")}
    steps = parse_drive_steps(args.steps, args.steps_file, values)
    if args.record:
        steps = [("record", f"start:{args.record}", False), *steps, ("record", "stop", False)]
    lab = Lab()
    page = lab.page()
    log: list[dict] = []
    with _lock(args, "drive") as lock:
        try:
            run_steps(lab, page, steps, lock, args.fps, log)
        finally:
            blocked = cdp.blocked_requests(lab.cdp.events)
            if blocked:
                log.append({"blocked_requests": blocked})
            if args.log:
                Path(args.log).parent.mkdir(parents=True, exist_ok=True)
                Path(args.log).write_text(json.dumps(log, indent=2), encoding="utf-8")
    print(json.dumps(log, indent=2))
    return 0


def cmd_motion(args: argparse.Namespace) -> int:
    """Frame-step a recording and print bursts of change."""
    print(json.dumps(cdp.analyze_motion(Path(args.clip), args.crop, args.threshold, args.gap),
                     indent=2))
    return 0


def cmd_contact(args: argparse.Namespace) -> int:
    """Tile a folder's screenshots into one review image."""
    images = sorted(p for p in Path(args.folder).glob(args.glob) if p.suffix == ".png")
    print(cdp.contact_sheet(images, Path(args.out), args.cols))
    return 0


def cmd_close(args: argparse.Namespace) -> int:
    """Close the app window(s), keeping Edge running."""
    lab = Lab()
    for target in lab.cdp.send("Target.getTargets")["targetInfos"]:
        if target["type"] == "page":
            lab.cdp.send("Target.closeTarget", {"targetId": target["targetId"]})
    return 0


def cmd_stop(args: argparse.Namespace) -> int:
    """Close the isolated Edge instance."""
    try:
        lab = Lab()
        lab.cdp.send("Browser.close")
    except (cdp.CdpError, OSError):
        pass
    print(json.dumps({"stopped": True}))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument("--hold", type=float, default=240.0, help="desktop-lock hold (≤300 s)")
    parser.add_argument("--wait-timeout", type=float, default=1800.0)
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("start").set_defaults(func=cmd_start)
    p = sub.add_parser("install")
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_install)
    sub.add_parser("uninstall").set_defaults(func=cmd_uninstall)
    p = sub.add_parser("launch")
    p.add_argument("--route")
    p.add_argument("--preset")
    p.add_argument("--shot")
    p.add_argument("--record", help="record launch → ready into this .mp4")
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--ready", help="selector that marks the app ready")
    p.add_argument("--timeout", type=float, default=30.0)
    p.add_argument("--wait", type=float, default=3.0)
    p.add_argument("--fresh", action="store_true", help="close existing app windows first")
    p.add_argument("--reset-storage", action="store_true",
                   help="clear localStorage/sessionStorage (first-run carousels reappear)")
    p.set_defaults(func=cmd_launch)
    p = sub.add_parser("resize")
    p.add_argument("preset")
    p.set_defaults(func=cmd_resize)
    sub.add_parser("window").set_defaults(func=cmd_window)
    p = sub.add_parser("shot")
    p.add_argument("out")
    p.add_argument("--content", action="store_true")
    p.set_defaults(func=cmd_shot)
    p = sub.add_parser("drive")
    p.add_argument("--steps")
    p.add_argument("--steps-file")
    p.add_argument("--record")
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--log")
    p.add_argument("--out-dir", help="value substituted for {out} in steps")
    p.set_defaults(func=cmd_drive)
    p = sub.add_parser("motion")
    p.add_argument("clip")
    p.add_argument("--crop")
    p.add_argument("--threshold", type=float, default=0.04)
    p.add_argument("--gap", type=float, default=0.1)
    p.set_defaults(func=cmd_motion)
    p = sub.add_parser("contact")
    p.add_argument("folder")
    p.add_argument("out")
    p.add_argument("--glob", default="*.png")
    p.add_argument("--cols", type=int, default=6)
    p.set_defaults(func=cmd_contact)
    sub.add_parser("close").set_defaults(func=cmd_close)
    sub.add_parser("stop").set_defaults(func=cmd_stop)
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
