#!/usr/bin/env python3
"""Minimal Chrome DevTools Protocol (CDP) client and page driver, stdlib only.

Shared by the installed-PWA reference labs (``tools/windows/pwa.py`` for Edge
on Windows, ``tools/android/pwa.py`` for Chrome on the FST emulators). Both
browsers expose the same protocol: Edge through ``--remote-debugging-port``,
Android Chrome through the ``chrome_devtools_remote`` abstract socket that
``adb forward`` publishes on a host port.

The client speaks just enough RFC 6455 (client masking, fragmentation,
ping/pong, close) to send JSON-RPC commands and collect events. The
:class:`PageDriver` layers deterministic selectors, real input dispatch
(mouse or touch), scroll gestures, animation capture and paint timing on top.

Selectors used by every ``click``/``waitfor``/``scrollto`` step:

``css=<selector>``
    ``document.querySelector``.
``text=<text>``
    Innermost visible element whose trimmed text equals ``<text>``.
``contains=<text>``
    Innermost visible element whose text contains ``<text>`` (case-insensitive).
``aria=<label>``
    ``[aria-label="<label>"]``.
``testid=<id>``
    ``[data-testid="<id>"]``.
``x,y``
    CSS-pixel viewport coordinates.
"""

from __future__ import annotations

import base64
import json
import os
import select
import socket
import struct
import time
import urllib.parse
import urllib.request
from pathlib import Path

# region WebSocket transport


class CdpError(RuntimeError):
    """A CDP command failed or the connection broke."""


def ws_accept_key(key: str) -> str:
    """Compute the ``Sec-WebSocket-Accept`` value for a client key (RFC 6455 §4.2.2)."""
    import hashlib

    magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    return base64.b64encode(hashlib.sha1((key + magic).encode()).digest()).decode()


def encode_frame(payload: bytes, opcode: int = 0x1, mask: bytes | None = None) -> bytes:
    """Encode one final, masked client frame.

    Args:
        payload: Frame payload.
        opcode: 0x1 text, 0x8 close, 0xA pong.
        mask: Four mask bytes (random when omitted).

    Returns:
        The wire bytes.
    """
    mask = mask if mask is not None else os.urandom(4)
    header = bytearray([0x80 | opcode])
    length = len(payload)
    if length < 126:
        header.append(0x80 | length)
    elif length < 1 << 16:
        header.append(0x80 | 126)
        header += struct.pack(">H", length)
    else:
        header.append(0x80 | 127)
        header += struct.pack(">Q", length)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return bytes(header) + mask + masked


class WebSocket:
    """Blocking WebSocket client for ``ws://`` URLs (CDP never needs TLS)."""

    def __init__(self, url: str, timeout: float = 30.0):
        parts = urllib.parse.urlsplit(url)
        if parts.scheme != "ws":
            raise CdpError(f"only ws:// is supported: {url}")
        self.sock = socket.create_connection((parts.hostname, parts.port or 80), timeout=timeout)
        self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        key = base64.b64encode(os.urandom(16)).decode()
        path = parts.path + (f"?{parts.query}" if parts.query else "")
        request = (f"GET {path} HTTP/1.1\r\nHost: {parts.hostname}:{parts.port}\r\n"
                   "Upgrade: websocket\r\nConnection: Upgrade\r\n"
                   f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n")
        self.sock.sendall(request.encode())
        response = b""
        while b"\r\n\r\n" not in response:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise CdpError("websocket handshake: connection closed")
            response += chunk
        head, _, self._buffer = response.partition(b"\r\n\r\n")
        if b" 101 " not in head.split(b"\r\n", 1)[0] or ws_accept_key(key).encode() not in head:
            raise CdpError(f"websocket handshake failed: {head[:200]!r}")

    def _read_exact(self, count: int) -> bytes:
        while len(self._buffer) < count:
            chunk = self.sock.recv(max(65536, count - len(self._buffer)))
            if not chunk:
                raise CdpError("websocket closed by peer")
            self._buffer += chunk
        data, self._buffer = self._buffer[:count], self._buffer[count:]
        return data

    def send_text(self, text: str) -> None:
        """Send one text message."""
        self.sock.sendall(encode_frame(text.encode()))

    def recv_text(self, timeout: float | None) -> str | None:
        """Receive one complete text message, or ``None`` on timeout.

        Pings are answered; a close frame raises :class:`CdpError`.
        """
        if not self._buffer:
            ready, _, _ = select.select([self.sock], [], [], timeout)
            if not ready:
                return None
        self.sock.settimeout(60)
        message = b""
        while True:
            b1, b2 = self._read_exact(2)
            opcode, final = b1 & 0x0F, b1 & 0x80
            length = b2 & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._read_exact(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._read_exact(8))[0]
            mask = self._read_exact(4) if b2 & 0x80 else b""
            payload = self._read_exact(length)
            if mask:
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
            if opcode == 0x8:
                raise CdpError("websocket closed by peer")
            if opcode == 0x9:
                self.sock.sendall(encode_frame(payload, 0xA))
                continue
            if opcode in (0x0, 0x1, 0x2):
                message += payload
                if final:
                    return message.decode("utf-8", errors="replace")

    def close(self) -> None:
        """Send a close frame and drop the socket."""
        try:
            self.sock.sendall(encode_frame(b"", 0x8))
        except OSError:
            pass
        self.sock.close()

# endregion

# region CDP session


def http_json(port: int, path: str, method: str = "GET", timeout: float = 10.0):
    """Fetch a DevTools HTTP endpoint (``/json/version``, ``/json/list``)."""
    request = urllib.request.Request(f"http://127.0.0.1:{port}{path}", method=method)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode())


def wait_for_devtools(port: int, timeout: float = 30.0) -> dict:
    """Poll ``/json/version`` until the DevTools endpoint answers."""
    deadline = time.monotonic() + timeout
    last: Exception | None = None
    while time.monotonic() < deadline:
        try:
            return http_json(port, "/json/version", timeout=2)
        except (OSError, ValueError) as exc:
            last = exc
            time.sleep(0.3)
    raise CdpError(f"DevTools on port {port} did not answer: {last}")


class Cdp:
    """JSON-RPC over one browser-level WebSocket, with flattened target sessions.

    Events are buffered in arrival order; commands wait for their own id.
    """

    def __init__(self, ws_url: str, timeout: float = 30.0):
        self.ws = WebSocket(ws_url, timeout)
        self.timeout = timeout
        self._next = 0
        self.events: list[dict] = []

    def send(self, method: str, params: dict | None = None, session: str | None = None,
             timeout: float | None = None) -> dict:
        """Send a command and return its ``result``.

        Raises:
            CdpError: Protocol error or timeout.
        """
        self._next += 1
        ident = self._next
        message = {"id": ident, "method": method, "params": params or {}}
        if session:
            message["sessionId"] = session
        self.ws.send_text(json.dumps(message))
        deadline = time.monotonic() + (timeout or self.timeout)
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise CdpError(f"{method}: timed out")
            text = self.ws.recv_text(remaining)
            if text is None:
                continue
            data = json.loads(text)
            if data.get("id") == ident:
                if "error" in data:
                    raise CdpError(f"{method}: {data['error'].get('message')} "
                                   f"{data['error'].get('data', '')}".strip())
                return data.get("result", {})
            if "method" in data:
                self.events.append(data)

    def pump(self, seconds: float) -> None:
        """Collect events for ``seconds``."""
        deadline = time.monotonic() + seconds
        while (remaining := deadline - time.monotonic()) > 0:
            text = self.ws.recv_text(remaining)
            if text:
                data = json.loads(text)
                if "method" in data:
                    self.events.append(data)

    def take(self, method: str | None = None) -> list[dict]:
        """Remove and return buffered events (optionally only one method)."""
        taken = [e for e in self.events if method is None or e["method"] == method]
        self.events = [e for e in self.events if not (method is None or e["method"] == method)]
        return taken

    def close(self) -> None:
        """Close the connection."""
        self.ws.close()

# endregion

# region Page driver

#: In-page selector resolver. Returns ``{x, y, w, h, tag, text}`` in CSS px for
#: the element's visible centre, scrolling it into view first, or ``null``.
RESOLVE_JS = r"""
(sel, scroll) => {
  const visible = el => {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'
      && parseFloat(s.opacity || '1') > 0.01;
  };
  const textOf = el => (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
  const innermost = (pred) => {
    const all = [...document.querySelectorAll('body *')].filter(el => visible(el) && pred(el));
    return all.filter(el => !all.some(o => o !== el && el.contains(o)))[0] || null;
  };
  let el = null;
  const i = sel.indexOf('=');
  const kind = i > 0 ? sel.slice(0, i) : 'css', value = i > 0 ? sel.slice(i + 1) : sel;
  if (kind === 'css') el = [...document.querySelectorAll(value)].find(visible) || null;
  else if (kind === 'text') el = innermost(e => textOf(e) === value);
  else if (kind === 'contains') el = innermost(e => textOf(e).toLowerCase().includes(value.toLowerCase()));
  else if (kind === 'aria') el = [...document.querySelectorAll(`[aria-label="${CSS.escape(value)}"]`)].find(visible) || null;
  else if (kind === 'testid') el = [...document.querySelectorAll(`[data-testid="${CSS.escape(value)}"]`)].find(visible) || null;
  if (!el) return null;
  if (scroll) el.scrollIntoView({block: 'center', inline: 'center', behavior: 'instant'});
  const r = el.getBoundingClientRect();
  return {x: r.left + r.width / 2, y: r.top + r.height / 2, w: r.width, h: r.height,
          tag: el.tagName.toLowerCase(), text: textOf(el).slice(0, 80)};
}
"""

#: Requests the lab never lets the PWA send to production (``Network.setBlockedURLs``):
#: the side-effecting GETs and POSTs of ``.agents/platforms/service-safety.md``.
#: Journeys also avoid the interactions that would trigger them; this is the
#: defence in depth.
BLOCKED_URLS = [
    "*/api/bands/search*", "*/api/bands/*", "*/api/player/*/stats*", "*/sync-status*",
    "*/api/player/*/track*", "*/api/account/name-refresh*", "*/export*", "*/recompute*",
]

#: Key names for ``key:`` steps: name -> (key, code, windowsVirtualKeyCode).
KEYS = {
    "escape": ("Escape", "Escape", 27), "esc": ("Escape", "Escape", 27),
    "enter": ("Enter", "Enter", 13), "tab": ("Tab", "Tab", 9),
    "space": (" ", "Space", 32), "backspace": ("Backspace", "Backspace", 8),
    "up": ("ArrowUp", "ArrowUp", 38), "down": ("ArrowDown", "ArrowDown", 40),
    "left": ("ArrowLeft", "ArrowLeft", 37), "right": ("ArrowRight", "ArrowRight", 39),
    "home": ("Home", "Home", 36), "end": ("End", "End", 35),
    "pageup": ("PageUp", "PageUp", 33), "pagedown": ("PageDown", "PageDown", 34),
}

#: Modifier bit masks for ``Input.dispatchKeyEvent``.
MODIFIERS = {"alt": 1, "ctrl": 2, "control": 2, "meta": 4, "shift": 8}


def parse_key(combo: str) -> tuple[int, str, str, int]:
    """Parse ``ctrl+shift+tab``-style combos into ``(modifiers, key, code, vk)``.

    Raises:
        ValueError: Unknown key name.
    """
    parts = [p.strip().lower() for p in combo.split("+") if p.strip()]
    if not parts:
        raise ValueError("empty key combo")
    modifiers = 0
    for part in parts[:-1]:
        if part not in MODIFIERS:
            raise ValueError(f"unknown modifier {part!r}")
        modifiers |= MODIFIERS[part]
    name = parts[-1]
    if name in KEYS:
        key, code, vk = KEYS[name]
    elif len(name) == 1 and name.isalnum():
        key, code, vk = name, (f"Key{name.upper()}" if name.isalpha() else f"Digit{name}"), \
            ord(name.upper())
    else:
        raise ValueError(f"unknown key {name!r}")
    return modifiers, key, code, vk


def summarize_animations(events: list[dict]) -> list[dict]:
    """Reduce ``Animation.animationStarted`` events to a stable, comparable list.

    Args:
        events: Raw CDP events (other methods are ignored).

    Returns:
        One dict per animation: type, name, duration/delay (ms), easing,
        iterations, keyframe offsets and the node description if resolved.
    """
    rows = []
    for event in events:
        if event.get("method") != "Animation.animationStarted":
            continue
        anim = event["params"]["animation"]
        source = anim.get("source") or {}
        frames = (source.get("keyframesRule") or {}).get("keyframes") or []
        rows.append({
            "type": anim.get("type"),
            "name": anim.get("name") or (source.get("keyframesRule") or {}).get("name") or "",
            "duration_ms": round(source.get("duration", 0), 1),
            "delay_ms": round(source.get("delay", 0), 1),
            "easing": source.get("easing"),
            "iterations": source.get("iterations"),
            "keyframes": [f.get("offset") for f in frames],
            "node": anim.get("node", ""),
        })
    return rows


class PageDriver:
    """Drive one page target through a flattened CDP session.

    Args:
        cdp: Browser-level connection.
        target_id: Page target to attach to.
        touch: Dispatch taps as touch events (Android) instead of mouse clicks.
    """

    def __init__(self, cdp: Cdp, target_id: str, touch: bool = False):
        self.cdp = cdp
        self.target_id = target_id
        self.touch = touch
        self.session = cdp.send("Target.attachToTarget",
                                {"targetId": target_id, "flatten": True})["sessionId"]
        for domain in ("Page", "Runtime", "Network"):
            self.send(f"{domain}.enable")
        self.send("Network.setBlockedURLs", {"urls": BLOCKED_URLS})

    def send(self, method: str, params: dict | None = None, timeout: float | None = None) -> dict:
        """Send a command on this page's session."""
        return self.cdp.send(method, params, session=self.session, timeout=timeout)

    def eval(self, expression: str, timeout: float = 30.0):
        """Evaluate JavaScript (awaiting promises) and return its JSON value."""
        result = self.send("Runtime.evaluate", {"expression": expression, "returnByValue": True,
                                                "awaitPromise": True}, timeout=timeout)
        if "exceptionDetails" in result:
            detail = result["exceptionDetails"]
            raise CdpError(f"eval: {detail.get('exception', {}).get('description') or detail}")
        return result.get("result", {}).get("value")

    def resolve(self, selector: str, scroll: bool = True) -> dict | None:
        """Resolve a selector to its visible centre (CSS px), or ``None``."""
        if "," in selector and "=" not in selector:
            x, y = (float(v) for v in selector.split(","))
            return {"x": x, "y": y, "w": 0, "h": 0, "tag": "", "text": ""}
        return self.eval(f"({RESOLVE_JS})({json.dumps(selector)}, {json.dumps(scroll)})")

    def waitfor(self, selector: str, timeout: float = 10.0, scroll: bool = False) -> dict:
        """Wait until a selector resolves.

        Raises:
            CdpError: Not found within ``timeout``.
        """
        deadline = time.monotonic() + timeout
        while True:
            found = self.resolve(selector, scroll=scroll)
            if found:
                return found
            if time.monotonic() > deadline:
                raise CdpError(f"waitfor: {selector} not visible after {timeout:.0f}s")
            time.sleep(0.25)

    def tap_point(self, x: float, y: float) -> None:
        """Press and release at CSS-pixel viewport coordinates."""
        if self.touch:
            self.send("Input.dispatchTouchEvent",
                      {"type": "touchStart", "touchPoints": [{"x": x, "y": y}]})
            time.sleep(0.05)
            self.send("Input.dispatchTouchEvent", {"type": "touchEnd", "touchPoints": []})
            return
        self.send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": x, "y": y})
        for kind in ("mousePressed", "mouseReleased"):
            self.send("Input.dispatchMouseEvent", {"type": kind, "x": x, "y": y,
                                                   "button": "left", "clickCount": 1})

    def click(self, selector: str, timeout: float = 10.0) -> dict:
        """Wait for a selector, scroll it into view and tap/click its centre."""
        self.waitfor(selector, timeout)
        found = self.resolve(selector, scroll=True)
        time.sleep(0.15)
        found = self.resolve(selector, scroll=False) or found
        self.tap_point(found["x"], found["y"])
        return found

    def hover(self, selector: str) -> None:
        """Move the mouse over a selector."""
        found = self.waitfor(selector, scroll=True)
        self.send("Input.dispatchMouseEvent", {"type": "mouseMoved", "x": found["x"],
                                               "y": found["y"]})

    def scroll(self, dy: float, x: float | None = None, y: float | None = None,
               speed: int = 1600) -> None:
        """Synthesize a real scroll gesture (positive ``dy`` scrolls content up/down the page)."""
        size = self.eval("[innerWidth, innerHeight]")
        params = {"x": x if x is not None else size[0] / 2,
                  "y": y if y is not None else size[1] / 2,
                  "yDistance": -dy, "speed": speed,
                  "gestureSourceType": "touch" if self.touch else "mouse"}
        self.send("Input.synthesizeScrollGesture", params, timeout=60)

    def key(self, combo: str) -> None:
        """Press and release a key combo (``escape``, ``alt+left`` …)."""
        modifiers, key, code, vk = parse_key(combo)
        base = {"modifiers": modifiers, "key": key, "code": code,
                "windowsVirtualKeyCode": vk, "nativeVirtualKeyCode": vk}
        down = dict(base, type="rawKeyDown" if len(key) > 1 or modifiers else "keyDown")
        if len(key) == 1 and not modifiers:
            down["text"] = key
        self.send("Input.dispatchKeyEvent", down)
        self.send("Input.dispatchKeyEvent", dict(base, type="keyUp"))

    def type(self, text: str) -> None:
        """Insert text as if typed (IME-style commit)."""
        self.send("Input.insertText", {"text": text})

    def navigate(self, url: str, timeout: float = 30.0) -> None:
        """Navigate the page (a full document load) and wait for ``load``."""
        self.cdp.take("Page.loadEventFired")
        self.send("Page.navigate", {"url": url})
        deadline = time.monotonic() + timeout
        while not any(e.get("sessionId") == self.session for e in
                      self.cdp.take("Page.loadEventFired")):
            if time.monotonic() > deadline:
                raise CdpError(f"navigate: no load event for {url}")
            self.cdp.pump(0.2)

    def screenshot(self, out: Path) -> None:
        """Write a PNG of the page content (viewport only, no window chrome)."""
        data = self.send("Page.captureScreenshot", {"format": "png"}, timeout=60)["data"]
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(base64.b64decode(data))

    def start_animations(self) -> None:
        """Begin recording ``Animation.animationStarted`` events."""
        self.cdp.take("Animation.animationStarted")
        self.send("Animation.enable")

    def stop_animations(self) -> list[dict]:
        """Stop recording and return summarized animations with node descriptions."""
        self.cdp.pump(0.1)
        events = [e for e in self.cdp.take("Animation.animationStarted")
                  if e.get("sessionId") == self.session]
        self.send("Animation.disable")
        rows = summarize_animations(events)
        for row, event in zip(rows, events):
            backend = event["params"]["animation"].get("source", {}).get("backendNodeId")
            if backend:
                try:
                    node = self.send("DOM.describeNode", {"backendNodeId": backend})["node"]
                    attrs = dict(zip(node.get("attributes", [])[::2],
                                     node.get("attributes", [])[1::2]))
                    row["node"] = node.get("localName", "") + "".join(
                        f".{c}" for c in (attrs.get("class") or "").split()[:2])
                    if attrs.get("data-testid"):
                        row["node"] += f"[data-testid={attrs['data-testid']}]"
                except CdpError:
                    pass
        return rows

    def paint_timing(self) -> dict:
        """First paint/contentful paint, LCP and navigation timing (ms since navigation start)."""
        return self.eval("""(async () => {
          const out = {};
          out.lcp = await new Promise(resolve => {
            let last = null;
            try {
              new PerformanceObserver(list => { const e = list.getEntries(); last = e[e.length - 1]; })
                .observe({type: 'largest-contentful-paint', buffered: true});
            } catch (e) { resolve(null); return; }
            setTimeout(() => resolve(last ? Math.round(last.startTime) : null), 50);
          });
          for (const e of performance.getEntriesByType('paint')) out[e.name] = Math.round(e.startTime);
          const nav = performance.getEntriesByType('navigation')[0];
          if (nav) { out.domContentLoaded = Math.round(nav.domContentLoadedEventEnd);
                     out.load = Math.round(nav.loadEventEnd); out.type = nav.type; }
          out.displayMode = ['standalone','minimal-ui','browser','window-controls-overlay']
            .find(m => matchMedia(`(display-mode: ${m})`).matches) || 'unknown';
          out.reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
          out.viewport = [innerWidth, innerHeight, devicePixelRatio];
          out.path = location.pathname + location.search;
          return out; })()""")

# endregion

# region Shared step engine

#: Web-level step verbs shared by both PWA labs: verb -> argument shape.
WEB_VERBS = {
    "click": "selector", "tap": "selector", "hover": "selector", "waitfor": "selector",
    "scrollto": "selector", "scroll": "scroll", "key": "keys", "type": "text",
    "wait": "seconds", "nav": "path", "route": "path", "eval": "text", "cshot": "path",
    "anims": "anims", "mark": "text", "timing": "path",
}


def split_steps(steps: str | None, steps_file: str | None) -> list[str]:
    """Split ``;``/newline-separated steps, dropping blanks and ``#`` comments."""
    text = "\n".join(filter(None, [steps, Path(steps_file).read_text(encoding="utf-8")
                                   if steps_file else None]))
    out = []
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("#"):
            continue
        for step in line.split(" #", 1)[0].split(";"):
            if step.strip():
                out.append(step.strip())
    return out


def is_optional(step: str) -> bool:
    """True for ``?``-prefixed steps (e.g. ``?click:testid=fre-close@1``)."""
    return step.startswith("?")


def blocked_requests(events: list[dict]) -> list[str]:
    """URLs the guard blocked (``Network.loadingFailed`` with a blocked reason)."""
    urls = {e["params"]["requestId"]: e["params"]["request"]["url"] for e in events
            if e.get("method") == "Network.requestWillBeSent"}
    return [urls.get(e["params"]["requestId"], "?") for e in events
            if e.get("method") == "Network.loadingFailed" and e["params"].get("blockedReason")]


def expand_placeholders(steps: list[str], values: dict[str, str]) -> list[str]:
    """Replace ``{name}`` placeholders (e.g. ``{out}``) in step text."""
    out = []
    for step in steps:
        for key, value in values.items():
            step = step.replace("{" + key + "}", value)
        out.append(step)
    return out


def parse_step(step: str, extra_verbs: dict[str, str] | None = None) -> tuple[str, str]:
    """Split ``verb:arg`` and validate the verb and its argument shape.

    A leading ``?`` marks an optional step whose failure is logged, not fatal
    (runners check :func:`is_optional`).

    Args:
        step: One step (``back`` and other bare verbs have an empty arg).
        extra_verbs: Platform verbs (``shot``, ``resize``, ``posture`` …).

    Returns:
        ``(verb, arg)``.

    Raises:
        ValueError: Unknown verb or malformed argument.
    """
    verbs = {**WEB_VERBS, **(extra_verbs or {})}
    verb, _, arg = step.lstrip("?").partition(":")
    verb, arg = verb.strip().lower(), arg.strip()
    if verb not in verbs:
        raise ValueError(f"unknown step verb {verb!r}")
    shape = verbs[verb]
    if shape == "seconds":
        float(arg)
    elif shape == "scroll":
        amount = arg.split("@", 1)[0]
        float(amount)
    elif shape == "keys":
        parse_key(arg)
    elif shape == "anims" and not (arg == "start" or arg.startswith("stop")):
        raise ValueError("anims: use start or stop:<out.json>")
    elif shape in ("selector", "path", "text") and not arg:
        raise ValueError(f"{verb}: missing argument")
    return verb, arg


def run_web_step(page: PageDriver, verb: str, arg: str, base_url: str,
                 log: list[dict], started: float) -> bool:
    """Execute a shared web step; return ``False`` if the verb is platform-specific.

    Args:
        page: Attached page driver.
        verb: Step verb.
        arg: Step argument (selectors accept an ``@<seconds>`` timeout suffix).
        base_url: Origin used by ``nav:`` for relative paths.
        log: Step log; each executed step appends ``{t, step, …}``.
        started: ``time.monotonic()`` of the run (or recording) start.
    """
    entry: dict = {"t": round(time.monotonic() - started, 3), "step": f"{verb}:{arg}"}
    selector, _, wait = arg.rpartition("@") if "@" in arg and verb in (
        "click", "tap", "hover", "waitfor", "scrollto") else (arg, "", "")
    timeout = float(wait) if wait else 10.0
    if verb in ("click", "tap"):
        entry["hit"] = page.click(selector, timeout)
    elif verb == "hover":
        page.hover(selector)
    elif verb == "waitfor":
        entry["hit"] = page.waitfor(selector, timeout)
    elif verb == "scrollto":
        entry["hit"] = page.waitfor(selector, timeout, scroll=True)
    elif verb == "scroll":
        amount, _, at = arg.partition("@")
        x, y = (float(v) for v in at.split(",")) if at else (None, None)
        page.scroll(float(amount), x, y)
    elif verb == "key":
        page.key(arg)
    elif verb == "type":
        page.type(arg)
    elif verb == "wait":
        time.sleep(float(arg))
    elif verb == "nav":
        page.navigate(arg if "://" in arg else base_url.rstrip("/") + "/" + arg.lstrip("/"))
    elif verb == "route":
        # In-app (SPA) navigation: the HashRouter reacts to hashchange exactly as
        # it does to a link click, so route transitions still animate.
        page.eval(f"location.hash = {json.dumps('#' + arg.lstrip('#'))}; true")
    elif verb == "eval":
        entry["value"] = page.eval(arg)
    elif verb == "cshot":
        page.screenshot(Path(arg))
    elif verb == "anims":
        if arg == "start":
            page.start_animations()
        else:
            rows = page.stop_animations()
            out = Path(arg.partition(":")[2] or "anims.json")
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(json.dumps(rows, indent=2), encoding="utf-8")
            entry["animations"] = len(rows)
    elif verb == "timing":
        timing = page.paint_timing()
        Path(arg).parent.mkdir(parents=True, exist_ok=True)
        Path(arg).write_text(json.dumps(timing, indent=2), encoding="utf-8")
        entry["timing"] = timing
    elif verb == "mark":
        pass
    else:
        return False
    log.append(entry)
    return True

# endregion

# region Video helpers


def even(value: float) -> int:
    """Round down to an even integer (H.264 4:2:0 needs even dimensions)."""
    return max(2, int(value) // 2 * 2)


def scale_540(width: int, height: int) -> tuple[int, int]:
    """Scale so the shorter side is 540 px (never upscale), keeping even sizes."""
    short = min(width, height)
    factor = min(1.0, 540 / short) if short else 1.0
    return even(width * factor), even(height * factor)


def parse_frame_diffs(text: str) -> list[tuple[float, float]]:
    """Pair ``pts_time`` with ``lavfi.signalstats.YAVG`` from ffmpeg ``metadata=print`` output.

    Returns:
        ``[(seconds, mean absolute luma difference vs the previous frame)]``.
    """
    import re

    rows, current = [], None
    for line in text.splitlines():
        match = re.search(r"pts_time:([0-9.]+)", line)
        if match:
            current = float(match.group(1))
            continue
        match = re.search(r"YAVG=([0-9.]+)", line)
        if match and current is not None:
            rows.append((current, float(match.group(1))))
            current = None
    return rows


def motion_bursts(times: list[float], gap: float = 0.12) -> list[dict]:
    """Group changed-frame timestamps into bursts of motion.

    Args:
        times: Sorted timestamps of frames that differ from their predecessor.
        gap: Largest pause (s) inside one burst.

    Returns:
        ``[{start, end, duration_ms, frames}]`` in order.
    """
    bursts: list[dict] = []
    for t in sorted(times):
        if bursts and t - bursts[-1]["end"] <= gap:
            bursts[-1]["end"] = t
            bursts[-1]["frames"] += 1
        else:
            bursts.append({"start": t, "end": t, "frames": 1})
    for burst in bursts:
        burst["duration_ms"] = round((burst["end"] - burst["start"]) * 1000)
        burst["start"], burst["end"] = round(burst["start"], 3), round(burst["end"], 3)
    return bursts


#: ffmpeg search order: ``FST_FFMPEG``, the full GPL build the lab installs under
#: ``~/.fst-tools/ffmpeg`` (gdigrab + libx264), then the operator's workspace
#: build (``--disable-avdevice``, no libx264: it can only re-encode to MPEG-4 Part 2).
FFMPEG_CANDIDATES = [
    Path.home() / ".fst-tools" / "ffmpeg" / "ffmpeg-n8.1-latest-win64-gpl-8.1" / "bin" / "ffmpeg.exe",
    Path.home() / "workspace" / "ffmpeg_build_release" / "bin" / "ffmpeg.exe",
]


def ffmpeg_path() -> str:
    """Locate ffmpeg (see :data:`FFMPEG_CANDIDATES`)."""
    env = os.environ.get("FST_FFMPEG")
    if env and Path(env).is_file():
        return env
    for candidate in FFMPEG_CANDIDATES:
        if candidate.is_file():
            return str(candidate)
    raise CdpError("ffmpeg not found: set FST_FFMPEG or install the GPL build under "
                   "~/.fst-tools/ffmpeg (see .agents/testing/pwa-reference/windows.md)")


def probe_size(clip: Path) -> tuple[int, int, float]:
    """Return ``(width, height, duration_s)`` of a video via ffmpeg's banner."""
    import re
    import subprocess

    text = subprocess.run([ffmpeg_path(), "-hide_banner", "-i", str(clip)],
                          capture_output=True, text=True).stderr
    size = re.search(r"Video:.*?(\d{2,5})x(\d{2,5})", text)
    dur = re.search(r"Duration: (\d+):(\d+):([\d.]+)", text)
    if not size:
        raise CdpError(f"no video stream in {clip}")
    seconds = int(dur.group(1)) * 3600 + int(dur.group(2)) * 60 + float(dur.group(3)) if dur else 0
    return int(size.group(1)), int(size.group(2)), seconds


def finalize_clip(raw: Path, out: Path, max_bytes: int = 2_000_000) -> dict:
    """Re-encode a capture to a small 540p H.264 MP4 under ``max_bytes``.

    The bitrate is derived from the clip duration, then lowered and the clip
    re-encoded if it still overshoots.

    Returns:
        ``{out, width, height, seconds, bytes}``.
    """
    import subprocess

    width, height, seconds = probe_size(raw)
    w, h = scale_540(width, height)
    budget_kbps = max(150, int(max_bytes * 8 / 1000 / max(seconds, 1) * 0.85))
    out.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(4):
        kbps = int(min(budget_kbps, 1400) * (0.7 ** attempt))
        cmd = [ffmpeg_path(), "-hide_banner", "-loglevel", "error", "-y", "-i", str(raw),
               "-vf", f"scale={w}:{h}:flags=lanczos,fps=30", "-c:v", "libx264", "-preset", "slow",
               "-crf", "26", "-maxrate", f"{kbps}k", "-bufsize", f"{kbps * 2}k",
               "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an", str(out)]
        subprocess.run(cmd, check=True, timeout=600)
        if out.stat().st_size <= max_bytes:
            break
    return {"out": str(out), "width": w, "height": h, "seconds": round(seconds, 2),
            "bytes": out.stat().st_size}


def analyze_motion(clip: Path, crop: str | None = None, threshold: float = 0.04,
                   gap: float = 0.1) -> dict:
    """Frame-step a clip and report bursts of on-screen change.

    Each frame is differenced against its predecessor (``tblend`` difference,
    mean luma via ``signalstats``); frames above ``threshold`` count as motion.

    Args:
        clip: Video file (the raw, full-frame-rate capture is best).
        crop: Optional ffmpeg ``crop`` expression (``w:h:x:y``) to ignore
            regions such as an animated background.
        threshold: Mean absolute luma difference (0–255) counted as motion.
        gap: Largest pause inside one burst (s).

    Returns:
        ``{frames, frames_changed, peak, bursts}``.
    """
    import subprocess

    filters = ([f"crop={crop}"] if crop else []) + [
        "tblend=all_mode=difference", "signalstats",
        "metadata=print:key=lavfi.signalstats.YAVG"]
    text = subprocess.run([ffmpeg_path(), "-hide_banner", "-i", str(clip), "-vf", ",".join(filters),
                           "-f", "null", "-"], capture_output=True, text=True, timeout=600).stderr
    rows = parse_frame_diffs(text)
    moving = [t for t, value in rows if value > threshold]
    return {"frames": len(rows), "frames_changed": len(moving),
            "peak": round(max((v for _, v in rows), default=0), 2),
            "bursts": motion_bursts(moving, gap)}

def contact_sheet(images: list[Path], out: Path, cols: int = 6, width: int = 260,
                  height: int = 420) -> Path:
    """Tile screenshots (letterboxed to ``width``×``height``) into one PNG for review."""
    import subprocess

    if not images:
        raise CdpError("contact sheet: no images")
    listing = out.with_suffix(".txt")
    listing.write_text("".join(f"file '{p.as_posix()}'\nduration 1\n" for p in images),
                       encoding="utf-8")
    rows = (len(images) + cols - 1) // cols
    vf = (f"scale={width}:{height}:force_original_aspect_ratio=decrease,"
          f"pad={width}:{height}:(ow-iw)/2:(oh-ih)/2:color=0x202020,tile={cols}x{rows}:padding=4")
    subprocess.run([ffmpeg_path(), "-hide_banner", "-loglevel", "error", "-y", "-f", "concat",
                    "-safe", "0", "-i", str(listing), "-vf", vf, "-frames:v", "1", str(out)],
                   check=True, timeout=120)
    listing.unlink()
    return out

# endregion
