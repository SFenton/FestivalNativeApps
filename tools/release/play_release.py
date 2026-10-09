#!/usr/bin/env python3
"""Publish Android App Bundles to Google Play through the Play Developer API (android-release.yml).

Runs only in GitHub Actions with the ``store-release`` environment's ``PLAY_SERVICE_ACCOUNT_JSON`` (a service account
invited in Play Console > Users and permissions with release-to-testing permission for the app). No third-party
action or client library: the OAuth assertion is signed with ``openssl`` and the REST calls use ``urllib``::

    play_release.py check  --package com.festivalscoretracker.android
    play_release.py upload --package com.festivalscoretracker.android --aab app-release.aab \\
        --track internal --version-name 2610.09.01 --notes-file store-notes.txt

``check`` opens and discards an edit (proves the credentials and app access). ``upload`` opens an edit, uploads the
bundle, sets the track's release to that version code (``completed``; ``draft`` when Play still treats the app as a
draft app, until its first release is rolled out by hand) and commits. Both print one JSON object; credentials are
never printed. Exit codes: 0 ok, 2 invalid input or missing credentials, 1 API failure.

Google requires the app's **first** bundle to be uploaded by hand in Play Console; until then ``upload`` reports
``app_not_ready``. Documentation: .agents/workflow/release-android.md.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Callable, Dict, Optional, Tuple

API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
UPLOAD_API = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
TOKEN_URL = "https://oauth2.googleapis.com/token"
TRACKS = ("internal", "alpha", "beta", "production")
#: Play's per-language release-notes limit.
NOTES_LIMIT = 500

#: ``(method, url, headers, body) -> (status, parsed JSON or text)``.
Http = Callable[[str, str, Dict[str, str], Optional[bytes]], Tuple[int, Any]]


class InputError(ValueError):
    """Invalid arguments or credentials (exit 2)."""


class PlayError(RuntimeError):
    """A Play Developer API failure (exit 1)."""

    def __init__(self, status: int, body: Any, step: str):
        message = body.get("error", {}).get("message") if isinstance(body, dict) else str(body)[:300]
        super().__init__(f"{step}: HTTP {status}: {message}")
        self.status, self.body, self.step = status, body, step


# region HTTP and auth


def urllib_http(method: str, url: str, headers: Dict[str, str], body: Optional[bytes]) -> Tuple[int, Any]:
    """Perform one HTTPS request; returns ``(status, JSON or text)`` without raising on HTTP errors."""
    request = urllib.request.Request(url, data=body, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            status, raw = response.status, response.read()
    except urllib.error.HTTPError as err:
        status, raw = err.code, err.read()
    text = raw.decode("utf-8", "replace")
    try:
        return status, json.loads(text) if text else {}
    except ValueError:
        return status, text


def load_service_account(raw: str) -> Dict[str, str]:
    """Parse and validate service-account JSON (``type``, ``client_email``, ``private_key``)."""
    try:
        data = json.loads(raw)
    except ValueError as err:
        raise InputError("PLAY_SERVICE_ACCOUNT_JSON is not JSON") from err
    if not isinstance(data, dict) or data.get("type") != "service_account":
        raise InputError("PLAY_SERVICE_ACCOUNT_JSON is not a service-account key")
    if not str(data.get("client_email", "")).endswith(".iam.gserviceaccount.com"):
        raise InputError("service account client_email is missing or not a service account")
    if "BEGIN PRIVATE KEY" not in str(data.get("private_key", "")):
        raise InputError("service account private_key is missing")
    return data


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def openssl_sign(private_key_pem: str, message: bytes) -> bytes:
    """RS256-sign ``message`` with ``openssl`` (the key goes to a private temp file, deleted at once)."""
    fd, path = tempfile.mkstemp(suffix=".pem")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(private_key_pem)
        result = subprocess.run(["openssl", "dgst", "-sha256", "-sign", path], input=message,
                                capture_output=True, check=False)
    finally:
        os.unlink(path)
    if result.returncode != 0:
        raise InputError("could not sign with the service account key (openssl)")
    return result.stdout


def access_token(account: Dict[str, str], http: Http, now: Callable[[], float] = time.time,
                 sign: Callable[[str, bytes], bytes] = openssl_sign) -> str:
    """Exchange a signed JWT assertion for an OAuth access token."""
    issued = int(now())
    header = _b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claims = _b64(json.dumps({"iss": account["client_email"], "scope": SCOPE, "aud": TOKEN_URL,
                              "iat": issued, "exp": issued + 3600}).encode())
    unsigned = f"{header}.{claims}".encode()
    assertion = unsigned.decode() + "." + _b64(sign(account["private_key"], unsigned))
    body = urllib.parse.urlencode({"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
                                   "assertion": assertion}).encode()
    status, data = http("POST", TOKEN_URL, {"Content-Type": "application/x-www-form-urlencoded"}, body)
    if status != 200 or not isinstance(data, dict) or "access_token" not in data:
        raise PlayError(status, data, "token")
    return str(data["access_token"])


# endregion

# region Play edits


class Play:
    """A thin Play Developer API v3 client for one package."""

    def __init__(self, package: str, token: str, http: Http):
        self.package, self.token, self.http = package, token, http

    def _call(self, method: str, url: str, step: str, body: Optional[bytes] = None,
              content_type: str = "application/json") -> Any:
        headers = {"Authorization": f"Bearer {self.token}"}
        if body is not None:
            headers["Content-Type"] = content_type
        status, data = self.http(method, url, headers, body)
        if status >= 300:
            raise PlayError(status, data, step)
        return data

    def insert_edit(self) -> str:
        return str(self._call("POST", f"{API}/{self.package}/edits", "edits.insert", b"{}")["id"])

    def delete_edit(self, edit: str) -> None:
        self._call("DELETE", f"{API}/{self.package}/edits/{edit}", "edits.delete")

    def upload_bundle(self, edit: str, aab: bytes) -> int:
        data = self._call("POST", f"{UPLOAD_API}/{self.package}/edits/{edit}/bundles?uploadType=media",
                          "edits.bundles.upload", aab, "application/octet-stream")
        return int(data["versionCode"])

    def set_track(self, edit: str, track: str, version_code: int, name: str, notes: str, status: str) -> None:
        release: Dict[str, Any] = {"name": name, "versionCodes": [str(version_code)], "status": status}
        if notes:
            release["releaseNotes"] = [{"language": "en-US", "text": notes}]
        self._call("PUT", f"{API}/{self.package}/edits/{edit}/tracks/{track}", "edits.tracks.update",
                   json.dumps({"track": track, "releases": [release]}).encode())

    def commit(self, edit: str) -> None:
        self._call("POST", f"{API}/{self.package}/edits/{edit}:commit", "edits.commit", b"{}")


def clip_notes(text: str) -> str:
    """Release notes within Play's 500-character limit (cut at a line break when possible)."""
    text = text.strip()
    if len(text) <= NOTES_LIMIT:
        return text
    cut = text[:NOTES_LIMIT - 1]
    return (cut[:cut.rfind("\n")] if "\n" in cut else cut).rstrip() + "…"


def _app_not_ready(err: PlayError) -> bool:
    message = str(err).lower()
    return err.status == 404 or "package not found" in message or "applicationnotfound" in message


def check(play: Play) -> Dict[str, Any]:
    """Open and discard an edit: the credentials work and the app exists for this account."""
    try:
        edit = play.insert_edit()
    except PlayError as err:
        if _app_not_ready(err):
            return {"ok": False, "status": "app_not_ready", "detail": str(err)}
        raise
    play.delete_edit(edit)
    return {"ok": True, "status": "ready", "package": play.package}


def upload(play: Play, aab: bytes, track: str, version_name: str, notes: str) -> Dict[str, Any]:
    """Upload ``aab`` and release it on ``track``; ``draft`` when Play only accepts drafts for the app."""
    try:
        edit = play.insert_edit()
    except PlayError as err:
        if _app_not_ready(err):
            return {"ok": False, "status": "app_not_ready", "detail": str(err)}
        raise
    try:
        version_code = play.upload_bundle(edit, aab)
        status = "completed"
        try:
            play.set_track(edit, track, version_code, version_name, notes, status)
        except PlayError as err:
            if "draft" not in str(err).lower():
                raise
            status = "draft"  # the app is still a draft app: finish its first rollout in Play Console
            play.set_track(edit, track, version_code, version_name, notes, status)
        play.commit(edit)
    except PlayError:
        try:
            play.delete_edit(edit)
        except PlayError:
            pass
        raise
    return {"ok": True, "status": status, "track": track, "version_code": version_code,
            "version_name": version_name}


# endregion

# region CLI


def main(argv: Optional[list] = None, http: Http = urllib_http, env: Optional[Dict[str, str]] = None,
         sign: Callable[[str, bytes], bytes] = openssl_sign) -> int:
    """Command-line entry point; see the module docstring."""
    env = dict(os.environ) if env is None else env
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("check", "upload"):
        p = sub.add_parser(name)
        p.add_argument("--package", required=True)
    up = sub.choices["upload"]
    up.add_argument("--aab", required=True)
    up.add_argument("--track", choices=TRACKS, default="internal")
    up.add_argument("--version-name", required=True)
    up.add_argument("--notes-file")
    args = parser.parse_args(argv)
    try:
        raw = env.get("PLAY_SERVICE_ACCOUNT_JSON") or ""
        if not raw.strip():
            print(json.dumps({"ok": False, "status": "missing_play_credentials"}))
            return 2
        account = load_service_account(raw)
        play = Play(args.package, access_token(account, http, sign=sign), http)
        if args.command == "check":
            result = check(play)
        else:
            aab = Path(args.aab).read_bytes()
            notes = clip_notes(Path(args.notes_file).read_text(encoding="utf-8")) if args.notes_file else ""
            result = upload(play, aab, args.track, args.version_name, notes)
    except (InputError, OSError) as err:
        print(json.dumps({"ok": False, "error": str(err)}))
        return 2
    except PlayError as err:
        print(json.dumps({"ok": False, "error": str(err), "step": err.step}))
        return 1
    print(json.dumps(result, sort_keys=True))
    return 0 if result.get("ok") else 2


# endregion

if __name__ == "__main__":
    sys.exit(main())
