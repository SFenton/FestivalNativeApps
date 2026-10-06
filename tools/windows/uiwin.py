#!/usr/bin/env python3
"""Serialized Windows-desktop UI driving for parallel lanes on ``sfenton-music``.

The Windows app is not a simulator: it runs on the operator's real interactive
desktop (console session 1), which every lane shares. This tool serializes all
desktop driving through the FIFO ``desktop`` host lock (:mod:`hostlock`,
≤300 s per hold) and executes UI Automation through ``FstUia.exe``, a small
FlaUI.UIA3 driver in ``tools/windows/FstUia`` (built on demand, cached by
source hash under ``~/.fst-tools/fstuia``).

Lanes usually run over SSH, in non-interactive session 0, where windows,
UIA trees and screenshots do not exist. When the caller is not in the active
console session, each driver request hops into it through a one-shot
scheduled task created with ``schtasks /IT`` (run only while ``sfent`` is logged
on interactively) and deleted immediately afterwards. No autologon or
persistent task is configured.

Examples::

    # Launch the app on a debug route at a window-size preset and screenshot it.
    python tools/windows/uiwin.py launch windows/Festival.App/bin/x64/Debug/.../Festival.App.exe \\
        --tab songs --route player:abc --preset compact --shot out/win-compact.png

    # Resize the last-launched window and capture it again.
    python tools/windows/uiwin.py resize snap-left
    python tools/windows/uiwin.py shot out/win-snap-left.png

    # UIA tree dump and scripted steps.
    python tools/windows/uiwin.py tree out/win.tree.txt
    python tools/windows/uiwin.py drive --steps "invoke:id=fst.songs.refresh; waitfor:id=fst.songs.list@10; shot:out/s.png"

    # Axe.Windows scan of the current page, and a keyboard Tab walk.
    python tools/windows/uiwin.py scan out/axe --scan-id songs-compact
    python tools/windows/uiwin.py focus-order --count 20 --out out/songs-tab.json

    # CPU/GPU/working-set sampling (and optional PresentMon frame timing).
    python tools/windows/uiwin.py perf-sample --seconds 10 --presentmon --out out/perf.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import statistics
import subprocess
import sys
import time
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.android.hostlock import HostLock, LockTimeout  # noqa: E402  (shared host lock)

# region Configuration

#: Driver project and cached build root.
DRIVER_DIR = Path(__file__).resolve().parent / "FstUia"
DRIVER_BUILD_ROOT = Path.home() / ".fst-tools" / "fstuia"

#: Request/response exchange directory (short path: ``schtasks /TR`` ≤ 261 chars).
EXCHANGE_DIR = Path.home() / ".fst-locks" / "uiwin"

#: PresentMon console binary installed by the device lab.
PRESENTMON = Path.home() / ".fst-tools" / "presentmon" / "PresentMon-2.6.0-x64.exe"

#: Window presets. ``size`` values are effective pixels (epx), scaled by the
#: window's DPI; they are centred in the monitor work area and clamped to it.
PRESETS: dict[str, dict] = {
    "compact": {"kind": "size", "width": 500, "height": 800},
    "medium": {"kind": "size", "width": 900, "height": 700},
    "wide": {"kind": "size", "width": 1440, "height": 900},
    "portrait-tablet": {"kind": "size", "width": 800, "height": 1280},
    "snap-left": {"kind": "snap-left"},
    "snap-right": {"kind": "snap-right"},
    "maximized": {"kind": "maximize"},
    "full-screen": {"kind": "fullscreen"},
    "minimized": {"kind": "minimize"},
    "restored": {"kind": "restore"},
}

#: Virtual-key codes for ``key:`` steps (letters/digits map to their ASCII code).
VK = {
    "ctrl": 0x11, "control": 0x11, "shift": 0x10, "alt": 0x12, "win": 0x5B,
    "enter": 0x0D, "return": 0x0D, "tab": 0x09, "esc": 0x1B, "escape": 0x1B,
    "space": 0x20, "backspace": 0x08, "delete": 0x2E, "insert": 0x2D,
    "left": 0x25, "up": 0x26, "right": 0x27, "down": 0x28,
    "home": 0x24, "end": 0x23, "pageup": 0x21, "pagedown": 0x22, "apps": 0x5D,
    "comma": 0xBC, "period": 0xBE, "minus": 0xBD, "plus": 0xBB,
    **{f"f{n}": 0x6F + n for n in range(1, 13)},
}

#: Step verbs understood by ``drive``: verb -> argument shape.
STEP_VERBS = {
    "click": "selector", "rightclick": "selector", "hover": "selector", "invoke": "selector",
    "toggle": "selector", "select": "selector", "expand": "selector",
    "collapse": "selector", "focus": "selector", "reveal": "selector", "waitfor": "selector", "waitgone": "selector",
    "scrollinto": "selector",
    "type": "text", "key": "keys", "keys": "keyseq", "scroll": "scroll", "wait": "seconds",
    "shot": "path", "tree": "path", "resize": "preset",
    "tabwalk": "tabwalk", "assertfocus": "selector", "scan": "path", "setvalue": "setvalue",
    "scrollto": "scrollto",
    "assertname": "setvalue", "assertaligned": "pair", "assertbelow": "pair", "assertlevel": "pair", "assertgap": "gap",
    "assertinset": "gap", "scrollinset": "gap", "assertstatus": "status", "assertstate": "state",
    "markspan": "span", "assertspan": "span", "film": "path", "filmstop": "path", "pin": "selector",
    "assertpinned": "selector", "foreground": "onoff", "listen": "listen", "assertannounced": "announced",
    "assertannouncedcount": "announcedcount",
}

#: ``assertstate`` properties and the values each accepts (``None`` = any non-empty text; ``scroll`` takes a rounded
#: vertical scroll percent, ``0``-``100`` or ``-1`` when the content fits; ``type`` the lower-case UIA control type such as
#: ``button`` or ``text``; ``invoke`` whether the Invoke pattern is offered; ``focusable`` UIA IsKeyboardFocusable).
STATE_KEYS = {"toggle": ("on", "off", "indeterminate"), "enabled": ("true", "false"), "selected": ("true", "false"),
              "name": None, "scroll": None, "type": None, "invoke": ("true", "false"), "focusable": ("true", "false")}

# endregion

# region Pure helpers (unit-tested)


def parse_selector(text: str) -> dict:
    """Parse a UIA selector.

    Forms: ``id=<AutomationId>``, ``name=<Name>``, ``class=<ClassName>``, ``raw=<AutomationId>`` (searches the
    raw view, for parts a control marks ``AccessibilityView=Raw`` such as a score row's badge text) or
    ``<x>,<y>`` (window-relative physical pixels, ``click``/``rightclick``/``hover`` only). An ``id=``/``name=``
    selector may end with ``&class=<ClassName>`` to also match the class, e.g. ``id=1&class=Button`` for a
    system file picker's Open button, which shares AutomationId ``1`` with the picker's first folder.

    Args:
        text: Selector text.

    Returns:
        ``{"kind": "id"|"name"|"class"|"raw", "value": ...}`` (plus ``"class"`` when qualified) or
        ``{"kind": "xy", "x", "y"}``.

    Raises:
        ValueError: Unrecognized selector.
    """
    match = re.fullmatch(r"\s*(\d+)\s*,\s*(\d+)\s*", text)
    if match:
        return {"kind": "xy", "x": int(match.group(1)), "y": int(match.group(2))}
    kind, sep, value = text.partition("=")
    kind = kind.strip().lower()
    qualified = re.fullmatch(r"(.+)&class=([^&]+)", value) if kind in ("id", "name") else None
    if sep and qualified:
        return {"kind": kind, "value": qualified.group(1), "class": qualified.group(2)}
    if sep and kind in ("id", "name", "class", "raw") and value:
        return {"kind": kind, "value": value}
    raise ValueError(f"bad selector {text!r}; use id=, name=, class=, raw= or x,y")


def parse_keys(combo: str) -> list[int]:
    """Parse a key combo such as ``ctrl+shift+tab`` or ``alt+left``.

    Args:
        combo: ``+``-separated key names; single letters/digits allowed.

    Returns:
        Virtual-key codes, pressed together in order.

    Raises:
        ValueError: Unknown key name.
    """
    codes = []
    for name in (part.strip().lower() for part in combo.split("+")):
        if name in VK:
            codes.append(VK[name])
        elif re.fullmatch(r"[a-z0-9]", name):
            codes.append(ord(name.upper()))
        else:
            raise ValueError(f"unknown key {name!r} in {combo!r}")
    return codes


def parse_step(step: str) -> dict:
    """Validate one ``verb:argument`` step and expand it for the driver.

    Selector steps accept an ``@<seconds>`` wait suffix (``waitfor:id=x@10``);
    ``waitgone`` waits until no on-screen element matches (an absence assertion);
    ``scrollinto`` brings a scrolled-out element on screen (UIA ScrollItem, no wheel);
    ``scroll`` takes ``up``/``down``/``<wheel clicks>``, optionally prefixed by a
    selector and a comma (``scroll:id=fst.songs.list,down``); ``shot`` accepts
    ``@screen`` to capture composited screen pixels instead of ``PrintWindow``;
    ``tabwalk`` takes ``<count>`` or ``<count>,shift`` (Tab/Shift+Tab presses, each
    focused element recorded); ``assertfocus`` fails unless focus matches the selector;
    ``scan:<dir>/<scan-id>`` runs an Axe.Windows scan (results in the ``scans`` output);
    ``setvalue:<sel>|<text>`` writes text through the UIA Value pattern (no keyboard input,
    so it also works while the console session is locked; an empty text clears the field);
    ``scrollto:<selector>,<percent>`` sets a scroller's vertical position through the UIA
    Scroll pattern and ``reveal:<selector>`` scrolls the target into view (UIA ScrollItem, else
    stepping its scroller from the top), with no input, so both work while the console is locked;
    ``assertname:<sel>|<text>`` waits (default 5 s) until the element's UIA Name is exactly the text (each ``*`` matches
    any run of characters, so ``|*<text>`` waits until it ends with the text, for names that start with a local-time date);
    ``assertaligned:<sel>|<sel>`` fails unless both elements' horizontal centres are within 2 px (a column);
    ``assertbelow:<sel>|<sel>`` fails unless the first element's vertical centre is at least 8 px below the second's,
    and ``assertlevel:<sel>|<sel>`` unless both vertical centres are within 4 px (a line);
    ``assertgap:<sel>|<sel>|<epx>`` fails unless the gap from the first element's bottom edge to the second's top
    edge is ``<epx>`` effective pixels (window DPI) within 1 epx, e.g. a list's last row above a pinned footer;
    ``assertinset:<sel>|<sel>|<epx>`` waits (up to 3 s) until the first element's top edge is ``<epx>`` effective
    pixels below the second's top edge within 1 epx, e.g. a Quick Links target landed under its page scroller's top;
    ``scrollinset:<sel>|<scroller>|<epx>`` scrolls the second element (UIA Scroll pattern, no input) until the first
    element's top edge sits ``<epx>`` (more than 0) effective pixels below the scroller's top within 1 epx: a fixed,
    unclipped list position for scans (a clipped element's UIA top reads as the viewport edge, so a 0 inset proves nothing).
    ``markspan:<sel>|<sel>|<name>`` records the distance from the first element's top edge to the second's (epx)
    under ``<name>`` and ``assertspan:<sel>|<sel>|<name>`` fails unless that distance is unchanged within 1 epx
    in the same drive (a card that must keep its height across a transition, measured top to top so scrolling
    doesn't matter).
    ``film:<dir>`` starts a background ``PrintWindow`` capture (frames scaled to at most 1280 px, up to 300) while
    the following steps run, and ``filmstop:<dir>`` ends it and writes ``f0000.jpg``… and ``frames.json`` (each
    frame's offset in ms) to ``<dir>``: motion evidence for a short transition such as a fade.
    ``keys:<chord> <chord>…`` presses space-separated chords (``key:`` syntax) back to back without the per-step
    pause, e.g. ``keys:left space left space`` for several picks inside one ~400 ms transition.
    ``assertstatus:<sel>|<status>[@<seconds>]`` waits until the element's UIA ItemStatus equals
    ``<status>`` (or matches it as a .NET regex when it starts with ``~``; no ``;`` since steps split on it)
    (off-screen and raw-view elements count, e.g. ``fst.shell.artwork-background``; a status containing
    ``not-visible`` or ``=background`` is read without bringing the window to the front);
    ``foreground:on`` activates the app window and ``foreground:off`` hands activation to the taskbar, leaving the window
    visible and uncovered but inactive (e.g. a first-run demo's ``rotation=background``; while the console is locked
    both send ``WM_ACTIVATE`` instead);
    ``assertstate:<sel>|<key>=<value>[@<seconds>]`` waits until the element's ``toggle`` state
    (``on``/``off``/``indeterminate``), ``enabled`` (``true``/``false``), ``selected`` (UIA SelectionItem
    ``IsSelected``: ``true``/``false``, e.g. a list's current item), ``scroll`` (UIA Scroll pattern vertical percent,
    rounded: ``0`` is a list back at its top) or ``name`` equals ``<value>``;
    ``pin:<sel>`` records the element's window-relative rectangle and ``assertpinned:<sel>`` (same selector, later in
    the same ``drive``) fails unless it is unchanged within 1 px, e.g. a toolbar that must stay put while a list scrolls;
    ``listen:announcements`` starts recording the window's UIA notification events (the app's screen-reader
    announcements, what Narrator speaks) and a later ``assertannounced:<text>[@<seconds>]`` in the same ``drive`` waits
    (default 5 s) until one equals ``<text>`` (or matches it as a .NET regex when it starts with ``~``);
    ``assertannouncedcount:<n>|<text>`` fails unless exactly ``<n>`` recorded announcements match ``<text>`` so far
    (no wait), e.g. a value announced once and not repeated on later reads.

    Args:
        step: A step string.

    Returns:
        A JSON-able step object for ``FstUia``.

    Raises:
        ValueError: Unknown verb or malformed argument.
    """
    verb, _, arg = step.partition(":")
    verb, arg = verb.strip().lower(), arg.strip()
    shape = STEP_VERBS.get(verb)
    if shape is None:
        raise ValueError(f"unknown step verb {verb!r} in {step!r}")
    if not arg:
        raise ValueError(f"step {verb!r} needs an argument")
    result: dict = {"verb": verb, "arg": arg}
    if shape == "setvalue":
        selector, sep, text = arg.partition("|")
        if not sep:
            raise ValueError(f"bad {verb} {arg!r}; use <selector>|<text>")
        if verb == "assertname" and "@" in selector:
            selector, _, wait = selector.rpartition("@")
            result["timeout"] = float(wait)
        result["selector"] = parse_selector(selector)
        if result["selector"]["kind"] == "xy":
            raise ValueError(f"{verb} needs an element selector, not coordinates")
        result["text"] = step.partition(":")[2].lstrip().partition("|")[2]
    elif shape == "pair":
        first, sep, second = arg.partition("|")
        if not sep:
            raise ValueError(f"bad {verb} {arg!r}; use <selector>|<selector>")
        result["selector"], result["other"] = parse_selector(first), parse_selector(second)
        if "xy" in (result["selector"]["kind"], result["other"]["kind"]):
            raise ValueError(f"{verb} needs element selectors, not coordinates")
    elif shape == "gap":
        first, sep, rest = arg.partition("|")
        second, sep2, epx = rest.rpartition("|")
        if not sep or not sep2 or not re.fullmatch(r"\d+(\.\d+)?", epx.strip()):
            raise ValueError(f"bad {verb} {arg!r}; use <selector>|<selector>|<epx>")
        result["selector"], result["other"] = parse_selector(first), parse_selector(second)
        if "xy" in (result["selector"]["kind"], result["other"]["kind"]):
            raise ValueError(f"{verb} needs element selectors, not coordinates")
        result["epx"] = float(epx)
        if verb == "scrollinset" and result["epx"] <= 0:
            raise ValueError(f"scrollinset needs a positive inset (a clipped top reads as 0), not {epx!r}")
    elif shape == "span":
        first, sep, rest = arg.partition("|")
        second, sep2, name = rest.rpartition("|")
        if not sep or not sep2 or not re.fullmatch(r"[A-Za-z0-9_.-]+", name.strip()):
            raise ValueError(f"bad {verb} {arg!r}; use <selector>|<selector>|<name>")
        result["selector"], result["other"] = parse_selector(first), parse_selector(second)
        if "xy" in (result["selector"]["kind"], result["other"]["kind"]):
            raise ValueError(f"{verb} needs element selectors, not coordinates")
        result["name"] = name.strip()
    elif shape == "status":
        body, _, wait = arg.rpartition("@") if re.search(r"@\d+(\.\d+)?$", arg) else (arg, "", "")
        selector, sep, status = body.partition("|")
        if not sep or not status.strip():
            raise ValueError(f"bad assertstatus {arg!r}; use <selector>|<status>[@<seconds>]")
        result["selector"] = parse_selector(selector)
        if result["selector"]["kind"] == "xy":
            raise ValueError("assertstatus needs an element selector, not coordinates")
        result["status"] = status.strip()
        if wait:
            result["timeout"] = float(wait)
    elif shape == "state":
        body, _, wait = arg.rpartition("@") if re.search(r"@\d+(\.\d+)?$", arg) else (arg, "", "")
        selector, sep, assertion = body.partition("|")
        key, eq, value = assertion.partition("=")
        key, value = key.strip().lower(), value.strip()
        if not sep or not eq or key not in STATE_KEYS or not value:
            raise ValueError(f"bad assertstate {arg!r}; use <selector>|toggle|enabled|selected|name|scroll|type|invoke|focusable=<value>[@<seconds>]")
        allowed = STATE_KEYS[key]
        if allowed is not None and value.lower() not in allowed:
            raise ValueError(f"assertstate {key} must be one of {allowed}, not {value!r}")
        if key == "scroll" and not (re.fullmatch(r"\d+", value) and int(value) <= 100 or value == "-1"):
            raise ValueError(f"assertstate scroll must be a whole percent 0-100 or -1, not {value!r}")
        result["selector"] = parse_selector(selector)
        if result["selector"]["kind"] == "xy":
            raise ValueError("assertstate needs an element selector, not coordinates")
        result["key"], result["value"] = key, value if allowed is None and key != "type" else value.lower()
        if wait:
            result["timeout"] = float(wait)
    elif shape == "selector":
        selector, _, wait = arg.rpartition("@") if "@" in arg else (arg, "", "")
        result["selector"] = parse_selector(selector)
        if wait:
            result["timeout"] = float(wait)
        if result["selector"]["kind"] == "xy" and verb not in ("click", "rightclick", "hover"):
            raise ValueError(f"{verb} needs an element selector, not coordinates")
    elif shape == "keys":
        result["vk"] = parse_keys(arg)
    elif shape == "keyseq":
        result["seq"] = [parse_keys(chord) for chord in arg.split()]
    elif shape == "scroll":
        target, _, amount = arg.rpartition(",")
        if target:
            result["selector"] = parse_selector(target)
        amount = amount.strip().lower()
        result["amount"] = {"down": -3, "up": 3}.get(amount)
        if result["amount"] is None:
            if not re.fullmatch(r"-?\d+", amount):
                raise ValueError(f"bad scroll amount {amount!r}")
            result["amount"] = int(amount)
    elif shape == "scrollto":
        target, _, percent = arg.rpartition(",")
        if not target or not re.fullmatch(r"\d+(\.\d+)?", percent.strip()) or float(percent) > 100:
            raise ValueError(f"bad scrollto {arg!r}; use <selector>,<0-100>")
        result["selector"] = parse_selector(target)
        if result["selector"]["kind"] == "xy":
            raise ValueError("scrollto needs an element selector, not coordinates")
        result["percent"] = float(percent)
    elif shape == "seconds":
        result["arg"] = str(float(arg))
    elif shape == "onoff":
        if arg.lower() not in ("on", "off"):
            raise ValueError(f"bad {verb} {arg!r}; use on or off")
        result["arg"] = arg.lower()
    elif shape == "listen":
        if arg.lower() != "announcements":
            raise ValueError(f"bad listen {arg!r}; use listen:announcements")
        result["arg"] = "announcements"
    elif shape == "announced":
        text, _, wait = arg.rpartition("@") if re.search(r"@\d+(\.\d+)?$", arg) else (arg, "", "")
        if not text.strip():
            raise ValueError(f"bad assertannounced {arg!r}; use <text>[@<seconds>]")
        result["text"] = text.strip()
        if wait:
            result["timeout"] = float(wait)
    elif shape == "announcedcount":
        count, _, text = arg.partition("|")
        if not re.fullmatch(r"\d+", count.strip()) or not text.strip():
            raise ValueError(f"bad assertannouncedcount {arg!r}; use <count>|<text>")
        result["count"], result["text"] = int(count), text.strip()
    elif shape == "path" and verb == "shot" and arg.endswith("@screen"):
        result["arg"], result["mode"] = arg[: -len("@screen")], "screen"
    elif shape == "preset":
        result["op"] = preset_op(arg)
    elif shape == "tabwalk":
        count, _, direction = arg.partition(",")
        if not re.fullmatch(r"\d+", count.strip()) or direction.strip() not in ("", "shift"):
            raise ValueError(f"bad tabwalk {arg!r}; use <count> or <count>,shift")
        result["count"], result["reverse"] = int(count), direction.strip() == "shift"
    if shape == "path":
        result["arg"] = str(Path(native_path(result["arg"])).resolve())
    return result


def native_path(text: str) -> str:
    """Translate an MSYS/Git Bash drive path (``/c/Users/...``) to Windows form.

    Git Bash rewrites standalone ``/c/...`` arguments for native programs but not
    paths embedded in a step (``shot:/c/...``), which Python would otherwise
    resolve to ``C:\\c\\...``.

    Args:
        text: A path as typed.

    Returns:
        ``C:/Users/...`` for an MSYS drive path; anything else unchanged.
    """
    match = re.fullmatch(r"/([a-zA-Z])(/.*)?", text)
    if match and os.name == "nt":
        return f"{match.group(1).upper()}:{match.group(2) or '/'}"
    return text


def parse_steps(steps: str | None, steps_file: str | None) -> list[str]:
    """Combine inline (``;``-separated) and file (newline-separated) steps.

    File steps come first; blank lines and ``#`` comments are dropped.

    Args:
        steps: Inline script or None.
        steps_file: Script path or None.

    Returns:
        Ordered step strings.

    Raises:
        ValueError: No steps.
    """
    raw: list[str] = []
    if steps_file:
        raw.extend(Path(steps_file).read_text(encoding="utf-8").splitlines())
    if steps:
        raw.extend(steps.split(";"))
    parsed = [s.strip() for s in raw if s.strip() and not s.strip().startswith("#")]
    if not parsed:
        raise ValueError("no driver steps provided (use --steps and/or --steps-file)")
    return parsed


def preset_op(name: str) -> dict:
    """Resolve a window preset or explicit ``<w>x<h>`` epx size.

    Args:
        name: Preset name from ``PRESETS`` or e.g. ``"1024x768"``.

    Returns:
        A resize op for ``FstUia``.

    Raises:
        ValueError: Unknown preset.
    """
    if name in PRESETS:
        return dict(PRESETS[name])
    match = re.fullmatch(r"(\d+)x(\d+)", name)
    if match:
        return {"kind": "size", "width": int(match.group(1)), "height": int(match.group(2))}
    raise ValueError(f"unknown preset {name!r}; use {', '.join(PRESETS)} or <w>x<h>")


def launch_env(tab: str | None, route: str | None, extras: list[str] | None) -> dict[str, str]:
    """Environment for a debug launch (same names as the Apple/Android debug hooks).

    Args:
        tab: ``FST_DEBUG_TAB`` value.
        route: ``FST_DEBUG_ROUTE`` value.
        extras: ``KEY=VALUE`` pairs.

    Returns:
        Environment additions.

    Raises:
        ValueError: A malformed pair.
    """
    env = {}
    if tab:
        env["FST_DEBUG_TAB"] = tab
    if route:
        env["FST_DEBUG_ROUTE"] = route
    for pair in extras or []:
        key, sep, value = pair.partition("=")
        if not sep or not key.strip():
            raise ValueError(f"extra must be KEY=VALUE, got {pair!r}")
        env[key.strip()] = value
    return env


#: Automation marker (``Festival.Core.Domain.AutomationLaunch.MarkerFileName``): a Release build honours
#: ``FST_AUTOMATION=1`` only when this file sits next to its executable.
AUTOMATION_MARKER = "fst-automation.marker"

#: Publish folders this tool may mark for automation (never an installed build).
ARTIFACTS_ROOT = REPO_ROOT / "windows" / ".artifacts"


def prepare_automation(exe: Path, env: dict[str, str]) -> str | None:
    """Turn on test automation for a launch (first run off, ``FST_*`` hooks honoured in Release).

    Sets ``FST_AUTOMATION=1`` unless the caller set it, and writes the marker next to a publish
    under ``windows/.artifacts``. Debug builds need no marker.

    Args:
        exe: Resolved executable.
        env: Launch environment, updated in place.

    Returns:
        A warning when a non-Debug build outside ``windows/.artifacts`` has no marker, else ``None``.
    """
    env.setdefault("FST_AUTOMATION", "1")
    if env["FST_AUTOMATION"] != "1":
        return None
    marker = exe.parent / AUTOMATION_MARKER
    if marker.exists() or any(part.lower() == "debug" for part in exe.parts):
        return None
    if ARTIFACTS_ROOT.resolve() in exe.resolve().parents:
        marker.write_text("Test automation marker written by tools/windows/uiwin.py; not part of a shipped build.\n",
                          encoding="utf-8")
        return None
    return f"{exe} has no {AUTOMATION_MARKER}; FST_* hooks and first-run defaults stay in release mode"


def clamp_warning(op: dict, result: dict) -> str | None:
    """Explain when a size preset could not be honoured exactly.

    Args:
        op: The resize op that was requested.
        result: ``FstUia`` window description after resizing.

    Returns:
        A warning, or None if the epx size matches within 2 px.
    """
    if op.get("kind") != "size":
        return None
    got_w, got_h = result.get("bounds_epx", [0, 0])
    if abs(got_w - op["width"]) <= 2 and abs(got_h - op["height"]) <= 2:
        return None
    return (f"requested {op['width']}x{op['height']} epx but window is {got_w:.0f}x{got_h:.0f} epx "
            "(clamped to the work area or the app's minimum size)")


def counter_paths(name: str, pid: int) -> dict[str, str]:
    """Performance-counter paths for one process (``Process V2`` names are ``name:pid``).

    Args:
        name: Process name without ``.exe``.
        pid: Process id.

    Returns:
        Metric name -> counter path (GPU paths contain wildcards and are summed).
    """
    instance = f"{name}:{pid}"
    return {
        "cpu_percent": rf"\Process V2({instance})\% Processor Time",
        "working_set_private_mb": rf"\Process V2({instance})\Working Set - Private",
        "gpu_percent": rf"\GPU Engine(pid_{pid}_*)\Utilization Percentage",
        "gpu_dedicated_mb": rf"\GPU Process Memory(pid_{pid}_*)\Dedicated Usage",
    }


def summarize(values: list[float]) -> dict:
    """Mean/max/p95 of a sample series.

    Args:
        values: Samples.

    Returns:
        Summary numbers rounded to 2 decimals (zeros if empty).
    """
    if not values:
        return {"mean": 0.0, "max": 0.0, "p95": 0.0, "samples": 0}
    ordered = sorted(values)
    p95 = ordered[min(len(ordered) - 1, int(round(0.95 * (len(ordered) - 1))))]
    return {"mean": round(statistics.fmean(values), 2), "max": round(max(values), 2),
            "p95": round(p95, 2), "samples": len(values)}


def aggregate_counters(samples: list[dict[str, float]], paths: dict[str, str],
                       cpu_count: int) -> dict:
    """Aggregate raw counter samples into per-metric summaries.

    Args:
        samples: One ``{counter path (lower-case): value}`` dict per sample tick.
        paths: Output of :func:`counter_paths`.
        cpu_count: Logical processors (CPU% is normalised to 0–100 of the machine).

    Returns:
        ``{metric: summary}``.
    """
    series: dict[str, list[float]] = {metric: [] for metric in paths}
    for tick in samples:
        for metric, path in paths.items():
            pattern = re.escape(path.lower()).replace(r"\*", ".*")
            hits = [v for k, v in tick.items() if re.search(pattern + "$", k)]
            if not hits:
                continue
            value = sum(hits)
            if metric == "cpu_percent":
                value /= max(cpu_count, 1)
            elif metric == "gpu_percent":
                value = min(value, 100.0)
            elif metric.endswith("_mb"):
                value /= 1024 * 1024
            series[metric].append(value)
    return {metric: summarize(values) for metric, values in series.items()}


def frame_stats(csv_text: str) -> dict:
    """Summarize PresentMon CSV frame timing.

    Args:
        csv_text: PresentMon 2.x (``FrameTime``) or 1.x (``MsBetweenPresents``) CSV.

    Returns:
        Frame count, mean FPS and frame-time summary in ms (empty dict if none).
    """
    import csv
    import io

    rows = list(csv.DictReader(io.StringIO(csv_text)))
    column = next((c for c in ("FrameTime", "MsBetweenPresents") if rows and c in rows[0]), None)
    if not column:
        return {}
    times = [float(r[column]) for r in rows if r.get(column) not in (None, "", "NA")]
    if not times:
        return {}
    summary = summarize(times)
    return {"frames": len(times), "fps_mean": round(1000.0 / statistics.fmean(times), 1),
            "frame_ms": summary}

# endregion

# region Session hop and driver


def session_ids() -> tuple[int, int]:
    """Return ``(this process's session, active console session)``."""
    import ctypes
    from ctypes import wintypes

    kernel32 = ctypes.windll.kernel32
    current = wintypes.DWORD()
    kernel32.ProcessIdToSessionId(os.getpid(), ctypes.byref(current))
    return current.value, kernel32.WTSGetActiveConsoleSessionId()


def driver_exe() -> Path:
    """Build ``FstUia.exe`` if its sources changed; return the cached binary."""
    sources = sorted(p for p in DRIVER_DIR.rglob("*")
                     if p.is_file() and "bin" not in p.parts and "obj" not in p.parts)
    digest = hashlib.sha256(b"".join(p.read_bytes() for p in sources)).hexdigest()[:12]
    out = DRIVER_BUILD_ROOT / digest
    exe = out / "FstUia.exe"
    if not exe.exists():
        print(f"building FstUia -> {out}", file=sys.stderr)
        subprocess.run(["dotnet", "build", str(DRIVER_DIR / "FstUia.csproj"), "-c", "Release",
                        "-o", str(out), "--nologo", "-v", "q"], check=True, timeout=600)
    return exe


def run_driver(request: dict, lock: HostLock, budget: float = 120.0) -> dict:
    """Execute one ``FstUia`` request in the interactive desktop session.

    Args:
        request: Request JSON (``command`` plus arguments).
        lock: Held ``desktop`` lock; bounds the wait.
        budget: Max seconds for this request (also bounded by the hold).

    Returns:
        The driver's result object.

    Raises:
        RuntimeError: No interactive session, driver failure or timeout.
    """
    exe = driver_exe()
    EXCHANGE_DIR.mkdir(parents=True, exist_ok=True)
    token = uuid.uuid4().hex[:10]
    req, resp = EXCHANGE_DIR / f"{token}.req.json", EXCHANGE_DIR / f"{token}.resp.json"
    req.write_text(json.dumps(request), encoding="utf-8")
    current, console = session_ids()
    if console in (0, 0xFFFFFFFF):
        raise RuntimeError("no interactive console session; the operator must be logged on")
    try:
        if current == console:
            proc = lock.track(subprocess.Popen([str(exe), "--request", str(req),
                                                "--response", str(resp)]))
            proc.wait(timeout=min(budget, lock.remaining()))
        else:
            _run_in_console_session(exe, req, resp, token, lock, budget)
        data = json.loads(resp.read_text(encoding="utf-8"))
    finally:
        req.unlink(missing_ok=True)
        resp.unlink(missing_ok=True)
    for line in data.get("log") or []:
        print(line, file=sys.stderr)
    if not data.get("ok"):
        raise RuntimeError(f"driver: {data.get('error')}")
    return data["result"]


def task_status(query_csv: str) -> str:
    """Extract the status column from ``schtasks /Query /FO CSV /NH`` output.

    Args:
        query_csv: Raw query output (one CSV row: name, next run time, status).

    Returns:
        Status text such as ``"Running"`` or ``"Ready"`` (empty if unparsable).
    """
    import csv
    import io

    for row in csv.reader(io.StringIO(query_csv)):
        if len(row) >= 3:
            return row[2].strip()
    return ""


def task_running(task: str) -> bool:
    """Report whether a scheduled task instance is still running."""
    out = subprocess.run(["schtasks", "/Query", "/TN", task, "/FO", "CSV", "/NH"],
                         capture_output=True, text=True, timeout=30).stdout
    return task_status(out) in ("Running", "Queued")


def _run_in_console_session(exe: Path, req: Path, resp: Path, token: str, lock: HostLock,
                            budget: float) -> None:
    """Run the driver through a one-shot ``/IT`` scheduled task, then delete it."""
    task = f"FST_UiWin_{token}"
    command = f'"{exe}" --request "{req}" --response "{resp}"'
    if len(command) > 261:
        raise RuntimeError(f"schtasks /TR too long ({len(command)} chars)")
    create = ["schtasks", "/Create", "/TN", task, "/TR", command, "/SC", "ONCE",
              "/ST", "23:59", "/IT", "/F"]
    subprocess.run(create, check=True, capture_output=True, timeout=30)
    try:
        subprocess.run(["schtasks", "/Run", "/TN", task], check=True, capture_output=True,
                       timeout=30)
        started, checked = time.monotonic(), time.monotonic()
        while not resp.exists():
            if lock.remaining(floor=0) < 2 or time.monotonic() - started > budget:
                subprocess.run(["schtasks", "/End", "/TN", task], capture_output=True)
                raise RuntimeError(f"driver timed out after {time.monotonic() - started:.0f}s")
            if time.monotonic() - checked > 2:
                checked = time.monotonic()
                if not task_running(task) and not resp.exists():
                    time.sleep(0.5)
                    if not resp.exists():
                        raise RuntimeError("driver exited without a response (crash? see the "
                                           "Application event log for FstUia.exe)")
            time.sleep(0.2)
    finally:
        subprocess.run(["schtasks", "/Delete", "/TN", task, "/F"], capture_output=True)

# endregion

# region Commands


def _state_path() -> Path:
    return EXCHANGE_DIR / f"last-{REPO_ROOT.name}.json"


def target_request(pid: int | None, process: str | None, last: dict | None,
                   isolate: bool = False) -> dict:
    """Build the target part of a driver request.

    Args:
        pid: Explicit ``--pid``.
        process: Explicit ``--process`` name.
        last: This worktree's last-launch record (``{"pid": ...}``) or None.
        isolate: ``--isolate``: minimize other same-named app windows overlapping
            the target before input (restored when the request ends).

    Returns:
        ``{"pid": ...}`` or ``{"process": ...}``, plus ``"isolate": True`` when set.

    Raises:
        ValueError: No target could be resolved.
    """
    if pid:
        target: dict = {"pid": pid}
    elif process:
        target = {"process": process}
    elif last and last.get("pid"):
        target = {"pid": last["pid"]}
    else:
        raise ValueError("no target: pass --pid/--process or `launch` first")
    if isolate:
        target["isolate"] = True
    return target


def _target(args: argparse.Namespace) -> dict:
    """Resolve ``--pid``/``--process`` or the pid last launched from this worktree."""
    try:
        last = json.loads(_state_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        last = None
    return target_request(getattr(args, "pid", None), getattr(args, "process", None), last,
                          getattr(args, "isolate", False))


def _lock(args: argparse.Namespace, purpose: str) -> HostLock:
    return HostLock("desktop", purpose=f"{purpose} [{Path.cwd().name}]",
                    hold_seconds=args.hold, wait_seconds=args.wait_timeout)


def _report(result: dict) -> None:
    result = {k: v for k, v in result.items() if k != "text"}
    print(json.dumps(result, indent=2))


def cmd_launch(args: argparse.Namespace) -> int:
    """Launch the app in automation mode with debug environment, optionally resize and screenshot."""
    exe = Path(native_path(args.exe)).resolve()
    if not exe.is_file():
        raise ValueError(f"no executable at {exe}")
    env = launch_env(args.tab, args.route, args.extra)
    if not args.no_automation:
        warning = prepare_automation(exe, env)
        if warning:
            print(f"warning: {warning}", file=sys.stderr)
    request = {"command": "launch", "exe": str(exe), "args": args.arg or [], "env": env, "timeout": args.timeout}
    with _lock(args, f"launch {exe.name}") as lock:
        result = run_driver(request, lock)
        pid = result["pid"]
        EXCHANGE_DIR.mkdir(parents=True, exist_ok=True)
        _state_path().write_text(json.dumps({"pid": pid, "exe": str(exe)}),
                                 encoding="utf-8")
        if args.preset:
            op = preset_op(args.preset)
            result = run_driver({"command": "resize", "pid": result["pid"], "op": op}, lock)
            warning = clamp_warning(op, result)
            if warning:
                print(f"warning: {warning}", file=sys.stderr)
        if args.shot:
            time.sleep(args.wait)
            result = run_driver({"command": "shot", "pid": result["pid"],
                                 "out": str(Path(native_path(args.shot)).resolve())}, lock)
        if args.steps or args.steps_file:
            # Same hold as the launch: timing-sensitive first checks can't queue behind another lane.
            steps = [parse_step(s) for s in parse_steps(args.steps, args.steps_file)]
            result = {**run_driver({"command": "drive", "pid": pid, "steps": steps}, lock, budget=lock.remaining()),
                      "pid": pid}
    _report(result)
    return 0


def cmd_window(args: argparse.Namespace) -> int:
    """Describe the target window (bounds, epx size, DPI scale, monitor)."""
    with _lock(args, "window") as lock:
        _report(run_driver({"command": "window", **_target(args)}, lock))
    return 0


def cmd_resize(args: argparse.Namespace) -> int:
    """Apply a window-size preset."""
    op = preset_op(args.preset)
    with _lock(args, f"resize {args.preset}") as lock:
        result = run_driver({"command": "resize", **_target(args), "op": op}, lock)
    warning = clamp_warning(op, result)
    if warning:
        print(f"warning: {warning}", file=sys.stderr)
    _report(result)
    return 0


def cmd_shot(args: argparse.Namespace) -> int:
    """Screenshot the target window (PrintWindow, or composited screen pixels)."""
    out = str(Path(native_path(args.out)).resolve())
    with _lock(args, "shot") as lock:
        result = run_driver({"command": "shot", **_target(args), "out": out,
                             "mode": args.mode}, lock)
    Path(out).with_suffix(".json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    _report(result)
    return 0


def cmd_tree(args: argparse.Namespace) -> int:
    """Dump the UIA control-view tree (to a file or stdout)."""
    out = str(Path(native_path(args.out)).resolve()) if args.out else None
    with _lock(args, "tree") as lock:
        result = run_driver({"command": "tree", **_target(args), "out": out,
                             "depth": args.depth}, lock)
    if out is None:
        print(result.get("text", ""))
    else:
        _report(result)
    return 0


def cmd_drive(args: argparse.Namespace) -> int:
    """Run scripted UIA steps against the target window."""
    steps = [parse_step(s) for s in parse_steps(args.steps, args.steps_file)]
    with _lock(args, "drive") as lock:
        _report(run_driver({"command": "drive", **_target(args), "steps": steps}, lock,
                           budget=lock.remaining()))
    return 0


def summarize_scan(result: dict) -> list[str]:
    """One line per Axe.Windows finding, grouped by rule.

    Args:
        result: ``FstUia`` ``scan`` result (``errors``, ``findings``).

    Returns:
        Human-readable lines (empty when there are no findings).
    """
    lines = []
    for finding in result.get("findings") or []:
        element = finding.get("element") or {}
        parent = (finding.get("parents") or [""])[0]
        known = " [framework issue]" if finding.get("framework_issue") else ""
        lines.append(f"{finding.get('rule')}{known}: {element.get('ControlType', '?')} "
                     f"\"{element.get('Name', '')}\" id={element.get('AutomationId', '')} "
                     f"class={element.get('ClassName', '')} (in {parent})")
    return sorted(lines)


def cmd_scan(args: argparse.Namespace) -> int:
    """Run an Axe.Windows scan of the target window; exit 1 when it finds errors."""
    out = Path(native_path(args.out)).resolve()
    out.mkdir(parents=True, exist_ok=True)
    with _lock(args, f"scan {args.scan_id}") as lock:
        result = run_driver({"command": "scan", **_target(args), "out": str(out),
                             "scanid": args.scan_id}, lock)
    (out / f"{args.scan_id}.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    for line in summarize_scan(result):
        print(line)
    print(f"{args.scan_id}: {result.get('errors', 0)} Axe.Windows error(s); details in "
          f"{out / (args.scan_id + '.json')}")
    return 1 if result.get("errors") else 0


def cmd_focus_order(args: argparse.Namespace) -> int:
    """Press Tab (or Shift+Tab) N times and print/save the focused element after each."""
    step = parse_step(f"tabwalk:{args.count}" + (",shift" if args.reverse else ""))
    with _lock(args, "focus-order") as lock:
        result = run_driver({"command": "drive", **_target(args), "steps": [step]}, lock)
    focus = result.get("focus") or []
    for entry in focus:
        print(f"{entry['index']:>3}{' (repeat)' if entry.get('repeat') else ''}"
              f"{'' if entry.get('in_window') else ' (outside app)'}: {entry['line']}")
    if args.out:
        Path(args.out).write_text(json.dumps(focus, indent=2), encoding="utf-8")
    return 0


def cmd_front(args: argparse.Namespace) -> int:
    """Bring the target to the foreground and report anything still covering it."""
    with _lock(args, "front") as lock:
        _report(run_driver({"command": "front", **_target(args)}, lock))
    return 0


def cmd_close(args: argparse.Namespace) -> int:
    """Close the target window (kill after 5 s)."""
    with _lock(args, "close") as lock:
        _report(run_driver({"command": "close", **_target(args)}, lock))
    return 0


def _sample_counters(paths: dict[str, str], seconds: int) -> list[dict[str, float]]:
    """Sample counters once per second via ``Get-Counter`` (works from session 0)."""
    quoted = ",".join("'" + p.replace("'", "''") + "'" for p in paths.values())
    script = (f"Get-Counter -Counter @({quoted}) -SampleInterval 1 -MaxSamples {seconds} "
              "-ErrorAction SilentlyContinue | ForEach-Object { $h=@{}; "
              "$_.CounterSamples | ForEach-Object { $h[$_.Path]=$_.CookedValue }; "
              "$h | ConvertTo-Json -Compress }")
    out = subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True,
                         text=True, timeout=seconds + 60).stdout
    ticks = []
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("{"):
            ticks.append({re.sub(r"^\\\\[^\\]+", "", k).lower(): float(v)
                          for k, v in json.loads(line).items()})
    return ticks


def cmd_perf(args: argparse.Namespace) -> int:
    """Sample CPU, GPU and memory (and optionally PresentMon frame timing)."""
    if args.pid:
        pid = args.pid
        name = subprocess.run(["powershell", "-NoProfile", "-Command",
                               f"(Get-Process -Id {pid}).ProcessName"],
                              capture_output=True, text=True, timeout=30).stdout.strip()
    else:
        target = _target(args)
        if "process" in target:
            name = target["process"]
            pid = int(subprocess.run(["powershell", "-NoProfile", "-Command",
                                      f"(Get-Process -Name '{name}' | Select -First 1).Id"],
                                     capture_output=True, text=True, timeout=30).stdout.strip())
        else:
            pid = target["pid"]
            name = subprocess.run(["powershell", "-NoProfile", "-Command",
                                   f"(Get-Process -Id {pid}).ProcessName"],
                                  capture_output=True, text=True, timeout=30).stdout.strip()
    if not name:
        raise ValueError(f"process {pid} is not running")
    paths = counter_paths(name, pid)
    presentmon = None
    csv_path = EXCHANGE_DIR / f"presentmon-{pid}.csv"
    if args.presentmon:
        EXCHANGE_DIR.mkdir(parents=True, exist_ok=True)
        csv_path.unlink(missing_ok=True)
        presentmon = subprocess.Popen(
            [str(PRESENTMON), "--process_id", str(pid), "--timed", str(args.seconds),
             "--terminate_after_timed", "--output_file", str(csv_path), "--no_console_stats",
             "--session_name", f"FST_PresentMon_{pid}", "--stop_existing_session"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ticks = _sample_counters(paths, args.seconds)
    report = {"pid": pid, "process": name, "seconds": args.seconds, "logical_cpus": os.cpu_count(),
              "metrics": aggregate_counters(ticks, paths, os.cpu_count() or 1)}
    if presentmon:
        presentmon.wait(timeout=args.seconds + 30)
        report["frames"] = frame_stats(csv_path.read_text(encoding="utf-8")) \
            if csv_path.exists() else {"error": "PresentMon wrote no CSV (no presents?)"}
    text = json.dumps(report, indent=2)
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(text, encoding="utf-8")
    print(text)
    return 0


def cmd_status(args: argparse.Namespace) -> int:
    """Show the desktop lock, sessions and cached driver."""
    lock = HostLock("desktop")
    holder = lock.holder()
    current, console = session_ids()
    print(f"session: {current}; active console session: {console}")
    print("desktop lock: " + ("free" if lock.is_free() else
                              f"held by pid {holder and holder.get('pid')} "
                              f"({holder and holder.get('purpose')})"))
    if lock.waiting():
        print(f"queue: {lock.waiting()}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Build the CLI parser (exposed for unit tests)."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--hold", type=float, default=300.0, help="max lock hold (≤300 s)")
    common.add_argument("--wait-timeout", type=float, default=1800.0)
    target = argparse.ArgumentParser(add_help=False, parents=[common])
    group = target.add_mutually_exclusive_group()
    group.add_argument("--pid", type=int)
    group.add_argument("--process", help="process name without .exe")
    target.add_argument("--isolate", action="store_true",
                        help="minimize other instances' windows overlapping the target during "
                             "input (other lanes' app windows); restored afterwards")

    sub = parser.add_subparsers(dest="command", required=True)
    launch = sub.add_parser("launch", parents=[common], help="launch with debug env")
    launch.add_argument("exe")
    launch.add_argument("--tab", help="FST_DEBUG_TAB")
    launch.add_argument("--route", help="FST_DEBUG_ROUTE")
    launch.add_argument("--extra", action="append", metavar="KEY=VALUE")
    launch.add_argument("--arg", action="append",
                        help="app argument (repeatable; use --arg=--flag for dashes)")
    launch.add_argument("--preset", help="resize after launch")
    launch.add_argument("--shot", help="screenshot after launch/resize")
    launch.add_argument("--wait", type=float, default=2.0, help="settle seconds before --shot")
    launch.add_argument("--timeout", type=float, default=30.0, help="seconds to wait for a window")
    launch.add_argument("--no-automation", action="store_true",
                        help="launch without FST_AUTOMATION (first-run and release defaults as a user sees them)")
    launch.add_argument("--steps", help="drive steps run right after launch, in the same desktop-lock hold")
    launch.add_argument("--steps-file", help="file of drive steps (one per line) run like --steps")
    launch.set_defaults(func=cmd_launch)
    sub.add_parser("window", parents=[target], help="describe window").set_defaults(func=cmd_window)
    resize = sub.add_parser("resize", parents=[target], help="apply a window preset")
    resize.add_argument("preset", help=f"{', '.join(PRESETS)} or <w>x<h> (epx)")
    resize.set_defaults(func=cmd_resize)
    shot = sub.add_parser("shot", parents=[target], help="window screenshot")
    shot.add_argument("out")
    shot.add_argument("--mode", choices=("print", "screen"), default="print")
    shot.set_defaults(func=cmd_shot)
    tree = sub.add_parser("tree", parents=[target], help="UIA tree dump")
    tree.add_argument("out", nargs="?")
    tree.add_argument("--depth", type=int, default=40)
    tree.set_defaults(func=cmd_tree)
    drive = sub.add_parser("drive", parents=[target], help="scripted UIA steps")
    drive.add_argument("--steps")
    drive.add_argument("--steps-file")
    drive.set_defaults(func=cmd_drive)
    sub.add_parser("front", parents=[target],
                   help="bring to foreground; report covering windows").set_defaults(func=cmd_front)
    sub.add_parser("close", parents=[target], help="close window").set_defaults(func=cmd_close)
    perf = sub.add_parser("perf-sample", parents=[target], help="CPU/GPU/memory sampling")
    perf.add_argument("--seconds", type=int, default=10)
    perf.add_argument("--presentmon", action="store_true", help="also record frame timing")
    perf.add_argument("--out")
    perf.set_defaults(func=cmd_perf)
    scan = sub.add_parser("scan", parents=[target], help="Axe.Windows rule scan (exit 1 on errors)")
    scan.add_argument("out", help="output directory (.json summary, .a11ytest on errors)")
    scan.add_argument("--scan-id", default="scan")
    scan.set_defaults(func=cmd_scan)
    focus = sub.add_parser("focus-order", parents=[target], help="Tab walk: focused element per press")
    focus.add_argument("--count", type=int, default=25)
    focus.add_argument("--reverse", action="store_true", help="Shift+Tab")
    focus.add_argument("--out", help="save the walk as JSON")
    focus.set_defaults(func=cmd_focus_order)
    sub.add_parser("status", help="lock and session state").set_defaults(func=cmd_status)
    return parser


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        Exit code (2 usage, 3 failure, 124 lock timeout).
    """
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except (ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 3
    except LockTimeout as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 124

# endregion


if __name__ == "__main__":
    sys.exit(main())
