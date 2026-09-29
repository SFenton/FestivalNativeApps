#!/usr/bin/env python3
"""Walk a screen with real TalkBack and record what it says, in order.

TalkBack ignores injected ``adb shell input`` gestures and key events, so this
tool writes kernel key events (``Meta`` + ``→``, TalkBack's "next item" in its
default new keymap) to the emulator's hardware keyboard as root. TalkBack's own
log (log level raised to verbose in its preferences) records each utterance;
the walk collects the text spoken for every accessibility-focus event until
focus stops moving or comes back to the first item. A focused text field keeps
the key chord (TalkBack gives it input focus and the IME), so from a text field
the walk hides the IME and steps on with a real one-finger swipe right, written
as multi-touch events to the display's touchscreen. Everything runs in one
``device.py`` emulator lock hold (≤300 s). UIAutomator is never used during the
walk: its UiAutomation connection suspends TalkBack and resets focus.

Usage::

    python tools/android/talkback_walk.py --avd FST_Phone --apk app-debug.apk \
        --route song:fixture-pulse --extra FST_ORIGIN=http://10.0.2.2:8791 \
        --name song-detail --out C:/showcase/a11y/talkback --max 60

Writes ``<out>/<name>.md`` (ordered table) and ``<out>/<name>.json``; with
``--shot`` also a final screenshot.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import device  # noqa: E402  (shared emulator tool beside this script)

# region Pure helpers

TALKBACK_PACKAGE = "com.google.android.marvin.talkback"

#: TalkBack's preferences (device-protected storage).
TALKBACK_PREFS = f"/data/user_de/0/{TALKBACK_PACKAGE}/shared_prefs/{TALKBACK_PACKAGE}_preferences.xml"

#: Emulator keyboard with the generic key layout (``qwerty2`` has no Meta mapping).
KEYBOARD = "AT Translated Set 2 keyboard"

#: Touchscreen of logical display 0 on the FST emulators.
TOUCHSCREEN = "virtio_input_multi_touch_1"

#: Device path of the "next item" key chord.
REMOTE_CHORD = "/data/local/tmp/fst-talkback-next.bin"

#: Device path prefix of the swipe-right frames (``<prefix><n>.bin``).
REMOTE_SWIPE = "/data/local/tmp/fst-talkback-swipe"

#: Linux input codes.
EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
KEY_LEFTMETA, KEY_RIGHT, BTN_TOUCH = 125, 106, 330
ABS_MT_SLOT, ABS_MT_POSITION_X, ABS_MT_POSITION_Y, ABS_MT_TRACKING_ID, ABS_MT_PRESSURE = 0x2F, 0x35, 0x36, 0x39, 0x3A

#: Multi-touch axis range of the emulator touchscreens.
TOUCH_MAX = 32767

#: Seconds between swipe frames (the whole swipe takes about 0.1 s).
SWIPE_FRAME_S = 0.012

#: ``Speaking fragment text="…"`` lines of a focus event.
SPEAKING = re.compile(r'Speaking fragment text="(?P<text>.*)", utteranceId=.*?event=(?P<event>.*)$')


def input_event(kind: int, code: int, value: int) -> bytes:
    """One 64-bit ``struct input_event`` (timestamp zero; the kernel stamps writes)."""
    return struct.pack("<qqHHi", 0, 0, kind, code, value)


def next_item_chord() -> bytes:
    """Meta down, → down, → up, Meta up: TalkBack's "next item" (new keymap, Meta trigger)."""
    syn = input_event(EV_SYN, 0, 0)
    return (input_event(EV_KEY, KEY_LEFTMETA, 1) + syn + input_event(EV_KEY, KEY_RIGHT, 1) + syn
            + input_event(EV_KEY, KEY_RIGHT, 0) + syn + input_event(EV_KEY, KEY_LEFTMETA, 0) + syn)


def swipe_right_frames(steps: int = 8, y: float = 0.5) -> list[bytes]:
    """One-finger swipe right across the middle 30–75 % of the screen, one chunk per frame.

    Frame 0 puts the finger down (slot 0, tracking ID, position, pressure,
    ``BTN_TOUCH``), frames 1…``steps`` move it, and the last frame lifts it
    (tracking ID −1). Coordinates are in the touchscreen's 0…32767 range.
    """
    syn = input_event(EV_SYN, 0, 0)
    x0, x1, ty = int(TOUCH_MAX * 0.3), int(TOUCH_MAX * 0.75), int(TOUCH_MAX * y)
    frames = [input_event(EV_ABS, ABS_MT_SLOT, 0) + input_event(EV_ABS, ABS_MT_TRACKING_ID, 77)
              + input_event(EV_ABS, ABS_MT_POSITION_X, x0) + input_event(EV_ABS, ABS_MT_POSITION_Y, ty)
              + input_event(EV_ABS, ABS_MT_PRESSURE, 60) + input_event(EV_KEY, BTN_TOUCH, 1) + syn]
    frames += [input_event(EV_ABS, ABS_MT_POSITION_X, x0 + (x1 - x0) * step // steps) + syn
               for step in range(1, steps + 1)]
    frames.append(input_event(EV_ABS, ABS_MT_TRACKING_ID, -1) + input_event(EV_KEY, BTN_TOUCH, 0) + syn)
    return frames


def swipe_script(touchscreen: str, count: int) -> str:
    """Root shell script that writes the ``count`` pushed swipe frames with a short pause between."""
    return "; ".join(f"cat {REMOTE_SWIPE}{index}.bin > {touchscreen}; sleep {SWIPE_FRAME_S}" for index in range(count))


def is_text_field(utterance: str) -> bool:
    """Whether TalkBack announced an editable text field (which keeps the key chord)."""
    return "Edit box" in utterance


def wrapped(heard: list[str]) -> int:
    """How many trailing items repeat the walk (0 while it is still new).

    Focus came back to the first item (1), or the last two items repeat an
    earlier consecutive pair (2): the walk started mid-screen and wrapped past
    where it began. A single repeated item is not a wrap (repeated per-card
    controls such as "View All Rivals").
    """
    if len(heard) > 1 and heard[-1] == heard[0]:
        return 1
    if len(heard) >= 4 and any(heard[i:i + 2] == heard[-2:] for i in range(len(heard) - 3)):
        return 2
    return 0


def input_device(getevent_output: str, name: str) -> str | None:
    """The ``/dev/input`` path of a named device in ``getevent -pl`` output."""
    path = None
    for line in getevent_output.splitlines():
        line = line.strip()
        if line.startswith("add device"):
            path = line.split(":", 1)[1].strip()
        elif line.startswith("name:") and line.split(":", 1)[1].strip().strip('"') == name:
            return path
    return None


def focus_utterances(log: str) -> list[str]:
    """Texts TalkBack spoke for accessibility-focus events, one per event, in order.

    Fragments of one event (same ``event=`` description) are joined; hints spoken
    without an event ("Double-tap to activate") are dropped.
    """
    spoken: list[tuple[str, str]] = []
    for line in log.splitlines():
        match = SPEAKING.search(line)
        if not match or "TYPE_VIEW_ACCESSIBILITY_FOCUSED" not in match.group("event"):
            continue
        event, text = match.group("event"), match.group("text")
        if spoken and spoken[-1][0] == event:
            spoken[-1] = (event, f"{spoken[-1][1]} {text}")
        else:
            spoken.append((event, text))
    return [text for _, text in spoken]


def with_log_level(prefs_xml: str) -> str:
    """TalkBack preferences with verbose logging (``pref_log_level`` = 2)."""
    if 'name="pref_log_level"' in prefs_xml:
        return re.sub(r'<string name="pref_log_level">[^<]*</string>', '<string name="pref_log_level">2</string>', prefs_xml)
    return prefs_xml.replace("<map>", '<map>\n    <string name="pref_log_level">2</string>', 1)


def markdown(name: str, items: list[str]) -> str:
    """The walk as a Markdown table."""
    lines = [f"# TalkBack walk: {name}", "", "| # | TalkBack says |", "|---|---|"]
    lines += [f"| {index} | {text.replace('|', chr(92) + '|')} |" for index, text in enumerate(items, 1)]
    return "\n".join(lines) + "\n"

# endregion

# region Walk


def prepare_talkback(dev: device.Device) -> tuple[str, str]:
    """Verbose TalkBack logging, the key chord and swipe frames on the device.

    Returns the keyboard's event path and the root script that swipes right.
    """
    prefs = dev.shell(f"su 0 cat {TALKBACK_PREFS}", check=False)
    if "<map>" in prefs and 'name="pref_log_level">2<' not in prefs:
        with tempfile.TemporaryDirectory() as tmp:
            local = Path(tmp) / "prefs.xml"
            local.write_text(with_log_level(prefs), encoding="utf-8")
            dev.adb("push", str(local), "/data/local/tmp/fst-talkback-prefs.xml", cap=30)
        dev.shell(f"su 0 sh -c 'cat /data/local/tmp/fst-talkback-prefs.xml > {TALKBACK_PREFS}'", check=False)
        dev.shell(f"su 0 am force-stop {TALKBACK_PACKAGE}", check=False)
    frames = swipe_right_frames()
    with tempfile.TemporaryDirectory() as tmp:
        chord = Path(tmp) / "chord.bin"
        chord.write_bytes(next_item_chord())
        dev.adb("push", str(chord), REMOTE_CHORD, cap=30)
        for index, frame in enumerate(frames):
            local = Path(tmp) / f"swipe{index}.bin"
            local.write_bytes(frame)
            dev.adb("push", str(local), f"{REMOTE_SWIPE}{index}.bin", cap=30)
    dev.shell(f"pm grant {TALKBACK_PACKAGE} android.permission.POST_NOTIFICATIONS", check=False)
    devices = dev.shell("getevent -pl", check=False)
    keyboard, touchscreen = input_device(devices, KEYBOARD), input_device(devices, TOUCHSCREEN)
    if not keyboard or not touchscreen:
        raise device.DeviceError(f"no {KEYBOARD} or {TOUCHSCREEN} input device")
    return keyboard, swipe_script(touchscreen, len(frames))


def walk(dev: device.Device, keyboard: str, swipe: str, limit: int) -> list[str]:
    """Press "next item" until focus stops moving or wraps; return what TalkBack said.

    From a text field it hides the IME (Back, only while the IME shows) and
    swipes right instead, since the field keeps the key chord.
    """
    dev.adb("logcat", "-c", cap=30)
    heard: list[str] = []
    stalls = 0
    for _ in range(limit):
        if heard and is_text_field(heard[-1]):
            if "mInputShown=true" in dev.shell("dumpsys input_method", check=False):
                dev.shell("input keyevent KEYCODE_BACK", check=False)
                time.sleep(0.5)
            dev.shell(f"su 0 sh -c '{swipe}'", check=False)
        else:
            dev.shell(f"su 0 sh -c 'cat {REMOTE_CHORD} > {keyboard}'", check=False)
        time.sleep(0.8)
        now = focus_utterances(dev.adb("logcat", "-d", "-v", "brief", cap=30).stdout)
        if len(now) == len(heard):
            stalls += 1
            # TalkBack may still be starting before the first utterance.
            if stalls >= (5 if heard else 12):
                break
            continue
        stalls = 0
        heard = now
        print(f"{len(heard):3d} {heard[-1][:100]}", file=sys.stderr)
        repeated = wrapped(heard)
        if repeated:
            del heard[-repeated:]
            break
    return heard


def build_parser() -> argparse.ArgumentParser:
    """CLI options: ``device.py drive``'s target/launch options plus the report."""
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--avd", default=device.DEFAULT_AVD, choices=sorted(device.AVDS))
    parser.add_argument("--hold", type=float, default=300.0)
    parser.add_argument("--wait-timeout", type=float, default=1800.0)
    parser.add_argument("--window", action="store_true")
    parser.add_argument("--gpu", default="swiftshader_indirect")
    parser.add_argument("--allow-foreign", action="store_true")
    parser.add_argument("--animations", action="store_true")
    parser.add_argument("--package", default=device.DEFAULT_PACKAGE)
    parser.add_argument("--activity")
    parser.add_argument("--tab")
    parser.add_argument("--route")
    parser.add_argument("--extra", action="append", metavar="KEY=VALUE")
    parser.add_argument("--posture")
    parser.add_argument("--apk")
    parser.add_argument("--name", required=True, help="screen name for the report")
    parser.add_argument("--out", required=True, help="report directory")
    parser.add_argument("--max", type=int, default=60, help="most key presses")
    parser.add_argument("--wait", type=float, default=5.0, help="seconds after launch")
    parser.add_argument("--before", help="device.py drive steps run after launch, before TalkBack (e.g. open a sheet)")
    parser.add_argument("--shot", action="store_true", help="save a screenshot at the end")
    parser.add_argument("--no-launch", action="store_true", help="walk the current screen")
    return parser


def run(args: argparse.Namespace) -> int:
    """Launch, walk and write the report."""
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    with device._lock(args, f"talkback-walk {args.name} {args.avd}") as lock:
        dev = device._booted(args, lock)
        device._prepare(dev, args)
        keyboard, swipe = prepare_talkback(dev)
        if not args.no_launch:
            device._launch(dev, args)
            time.sleep(args.wait)
        if args.before:
            for verb, arg in (device.parse_step(s) for s in device.parse_steps(args.before, None)):
                device.run_step(dev, args.avd, verb, arg)
        device.run_step(dev, args.avd, "talkback", "on")
        time.sleep(3)
        try:
            items = walk(dev, keyboard, swipe, args.max)
            # Raw speech (every event type) for diagnosing a walk.
            log = dev.adb("logcat", "-d", "-v", "brief", cap=30).stdout
            speech = [line for line in log.splitlines() if "Speaking fragment" in line]
            (out / f"{args.name}.log").write_text("\n".join(speech) + "\n", encoding="utf-8")
            if args.shot:
                dev.screenshot(out / f"{args.name}.png")
        finally:
            device.run_step(dev, args.avd, "talkback", "off")
    (out / f"{args.name}.json").write_text(json.dumps(items, indent=2, ensure_ascii=False), encoding="utf-8")
    (out / f"{args.name}.md").write_text(markdown(args.name, items), encoding="utf-8")
    print(out / f"{args.name}.md")
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    return run(build_parser().parse_args(argv))

# endregion


if __name__ == "__main__":
    sys.exit(main())
