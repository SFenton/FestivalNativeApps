"""Run tools/mock_service.py with switchable feedback-form states for the Windows Feedback Form journeys (issue #236).

The shared mock always reports ``feedback: true``, answers ``POST /api/feedback`` at once and files the job on the
first status read. This wrapper lets a journey reach every [feedback-form](../../.agents/controls/feedback-form/spec.md)
state, switching between phases through a loopback control route:

``GET /__feedback__/mode?features=<on|off>&post=<ok|hold>&status=<ok|hold>[&reset=1]``

* ``features=off``: ``/api/features`` reports ``feedback: false`` (the ``unavailable`` state: no rows).
* ``post=hold``: holds ``POST /api/feedback`` until a control request leaves ``hold`` (at most ``--slow-seconds``), so
  the ``sending`` progress row stays up however long the journey waits for the shared desktop lock.
* ``status=hold``: answers every ``GET /api/feedback/{id}`` with ``processing`` (the ``filing`` state). Polls are
  answered at once rather than held, because a held read would hit the app's per-request timeout while the journey
  waits for the desktop lock.
* ``reset=1``: zeroes the counters.

Every control answer also reports ``posts`` (feedback POSTs received), ``reads`` (status reads) and ``last``: the
multipart field names, ``kind``, ``platform``, the number of ``media`` parts and whether a privileged or
selected-profile header was present. Titles are never echoed. The mock's own fixtures still apply: a title containing
``fixture-unavailable`` answers ``503 feedback_busy`` and ``fixture-failed`` queues a job that fails.

Usage: ``python tools/windows/feedback_fixture.py --port 0 [--features off] [--post hold] [--status hold]
[--slow-seconds 300]`` (other flags pass through to mock_service.py). The mock runs through ``rivals_fixture.py``
(anonymized names, larger accept backlog, ``Connection: close``), so ``a11y_matrix.py`` pages can name this wrapper as
their fixture. Loopback only; never production, and nothing is filed anywhere.
"""

from __future__ import annotations

import argparse
import io
import re
import sys
import threading
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mock_service  # noqa: E402  (path set above)
import rivals_fixture  # noqa: E402  (sibling wrapper)

#: Control route a journey calls between phases.
CONTROL_PATH = "/__feedback__/mode"
#: Allowed values per control key.
MODES = {"features": ("on", "off"), "post": ("ok", "hold"), "status": ("ok", "hold")}

#: A part's ``name`` parameter, quoted (browsers) or a bare token (.NET ``MultipartFormDataContent``).
_PART = re.compile(rb'Content-Disposition:\s*form-data;\s*name=(?:"([^"]+)"|([^";\r\n]+))', re.IGNORECASE)
_BARE_NAME = re.compile(rb'(Content-Disposition:\s*form-data;\s*name=)([^";\r\n]+)', re.IGNORECASE)


def quote_names(body: bytes) -> bytes:
    """Quote bare-token part names (``name=kind`` → ``name="kind"``).

    The service's ASP.NET form reader accepts both forms, but ``mock_service`` matches the browser's quoted form,
    so the wrapper normalizes the Windows client's body before handing it on.

    Args:
        body: Raw ``multipart/form-data`` body.

    Returns:
        The body with every part name quoted.
    """
    return _BARE_NAME.sub(rb'\1"\2"', body)


def summarize(body: bytes, headers: dict[str, str]) -> dict:
    """Describe one multipart feedback body without echoing what the person typed.

    Args:
        body: Raw ``multipart/form-data`` body.
        headers: Request headers (names are compared case-insensitively).

    Returns:
        ``fields`` (part names in order), ``kind``, ``platform``, ``media`` (file-part count) and ``forbidden_header``.
    """
    names = [(m.group(1) or m.group(2)).decode("utf-8", "replace") for m in _PART.finditer(body)]

    def value(field: str) -> str | None:
        match = re.search(rb'name="?' + field.encode() + rb'"?\r?\n(?:[^\r\n]+\r?\n)*\r?\n([^\r\n]*)', body)
        return match.group(1).decode("utf-8", "replace") if match else None

    lowered = {name.lower() for name in headers}
    return {
        "fields": names,
        "kind": value("kind"),
        "platform": value("platform"),
        "media": names.count("media"),
        "forbidden_header": "x-api-key" in lowered or any(n.startswith("x-fst-selected") for n in lowered),
    }


class FeedbackState:
    """Current modes and counters, shared by the server's handler threads."""

    def __init__(self, features: str = "on", post: str = "ok", status: str = "ok", slow_seconds: float = 300.0) -> None:
        """Create the state.

        Args:
            features: ``on`` or ``off`` (the features flag).
            post: ``ok`` or ``hold`` (feedback POSTs).
            status: ``ok`` or ``hold`` (status reads).
            slow_seconds: Longest a held request waits.
        """
        self._lock = threading.Lock()
        #: Set unless POSTs are held.
        self.post_released = threading.Event()
        #: Clear while status reads answer ``processing``.
        self.status_released = threading.Event()
        self.slow_seconds = slow_seconds
        self.modes = {"features": "on", "post": "ok", "status": "ok"}
        self.posts = 0
        self.reads = 0
        self.last: dict | None = None
        self.update({"features": [features], "post": [post], "status": [status]})

    def update(self, query: dict[str, list[str]]) -> dict:
        """Apply a control request.

        Args:
            query: Parsed control query (any of ``features``, ``post``, ``status``, ``reset``).

        Returns:
            The modes now in effect plus the counters (see :meth:`snapshot`).

        Raises:
            ValueError: An unknown key or mode.
        """
        unknown = set(query) - set(MODES) - {"reset"}
        if unknown:
            raise ValueError(f"unknown control key(s): {', '.join(sorted(unknown))}")
        wanted = {key: query[key][-1] for key in MODES if key in query}
        for key, mode in wanted.items():
            if mode not in MODES[key]:
                raise ValueError(f"unknown {key} mode: {mode}")
        with self._lock:
            self.modes.update(wanted)
            # Holds first: one request that releases the POST and holds status reads (the filing phase) must not let
            # the app's first status read through as filed.
            events = (("post", self.post_released), ("status", self.status_released))
            for key, event in sorted(events, key=lambda pair: self.modes[pair[0]] != "hold"):
                if self.modes[key] == "hold":
                    event.clear()
                else:
                    event.set()
            if query.get("reset", ["0"])[-1] == "1":
                self.posts = self.reads = 0
                self.last = None
        return self.snapshot()

    def snapshot(self) -> dict:
        """Modes and counters.

        Returns:
            ``features``/``post``/``status`` modes, ``posts``, ``reads`` and ``last`` (see :func:`summarize`).
        """
        with self._lock:
            return {**self.modes, "posts": self.posts, "reads": self.reads, "last": self.last}

    def features_on(self) -> bool:
        """Whether ``/api/features`` reports feedback as available."""
        with self._lock:
            return self.modes["features"] == "on"

    def record_post(self, summary: dict) -> None:
        """Count one feedback POST.

        Args:
            summary: :func:`summarize` result.
        """
        with self._lock:
            self.posts += 1
            self.last = summary

    def record_read(self) -> None:
        """Count one status read."""
        with self._lock:
            self.reads += 1


def install(state: FeedbackState) -> None:
    """Patch the mock handler so feature, submit and status requests follow ``state``.

    Args:
        state: Shared modes.
    """
    handler = mock_service.FixtureHandler
    original_get = handler.do_GET
    original_post = handler.do_POST
    original_status = handler._feedback_status

    def do_GET(self) -> None:  # noqa: N802 (stdlib handler name)
        parsed = urlsplit(self.path)
        if parsed.path == CONTROL_PATH:
            try:
                self._json(200, state.update(parse_qs(parsed.query)))
            except ValueError as error:
                self._json(400, {"status": str(error)})
        elif parsed.path == "/api/features" and not state.features_on():
            self._json(200, {"appManual": False, "feedback": False})
        else:
            original_get(self)

    def do_POST(self) -> None:  # noqa: N802 (stdlib handler name)
        if urlsplit(self.path).path != "/api/feedback":
            original_post(self)
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(min(length, 100 * 1024 * 1024)) if length > 0 else b""
        state.record_post(summarize(body, dict(self.headers.items())))
        state.post_released.wait(state.slow_seconds)
        body = quote_names(body)
        if "Content-Length" in self.headers:
            self.headers.replace_header("Content-Length", str(len(body)))
        self.rfile = io.BytesIO(body)
        original_post(self)

    def _feedback_status(self, job: str) -> None:
        state.record_read()
        if state.status_released.is_set():
            original_status(self, job)
        else:
            self._json(200, {"id": job, "status": "processing", "attachments": []})

    handler.do_GET = do_GET
    handler.do_POST = do_POST
    handler._feedback_status = _feedback_status
    mock_service.FixtureServer.request_queue_size = 128


def parse_options(argv: list[str]) -> tuple[argparse.Namespace, list[str]]:
    """Split this wrapper's flags from the mock service's.

    Args:
        argv: Arguments after the script name.

    Returns:
        This wrapper's options and the remaining arguments.
    """
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--features", choices=MODES["features"], default="on")
    parser.add_argument("--post", choices=MODES["post"], default="ok")
    parser.add_argument("--status", choices=MODES["status"], default="ok")
    parser.add_argument("--slow-seconds", type=float, default=300.0)
    return parser.parse_known_args(argv)


def main() -> None:
    """Parse this wrapper's flags, then hand the rest to the anonymized mock's own CLI."""
    options, rest = parse_options(sys.argv[1:])
    install(FeedbackState(options.features, options.post, options.status, options.slow_seconds))
    sys.argv = [sys.argv[0], *rest]
    rivals_fixture.main()


if __name__ == "__main__":
    main()
