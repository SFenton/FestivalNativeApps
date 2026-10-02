#!/usr/bin/env python3
"""App Store Connect release client for the Festival release machine.

Runs on the Mac with the system Python 3.9 (standard library only). The release
orchestrator (``festival-report-tracker``, design §8) drives it over SSH::

    fst_release.py ios status --json
    fst_release.py ios next-version
    fst_release.py ios submit --build 202609301200 --notes-file notes.txt [--dry-run]
    fst_release.py ios record-build --build 202609301200 --version 0.1.1 --sha <git sha>
    fst_release.py ios creds            # signing helper used by ios_appstore_build.sh
    fst_release.py ios released-versions --json   # What's New history (ios_appstore_build.sh)
    fst_release.py ios beta-notes --build 57 --notes-file notes.txt --wait 1800
    fst_release.py ios submit ... --whats-new-baseline 2610.01.01   # refuse stale What's New
    fst_release.py windows status --json  # Microsoft Store: dispatched to fst_store.py

The orchestrator never runs it locally for status or submit: ``store-release.yml``
runs it on a GitHub-hosted runner through ``actions_job.py`` (secrets stay in the
``store-release`` environment). ``FST_RELEASE_SHA_FROM_ARTIFACTS=1`` maps build
numbers to commits from ``fst-ios-build_<build>`` artifacts there.

``macos`` is accepted as a second platform group (``MAC_OS``) for the disabled
macOS pipeline. Credentials come from ``ASC_KEY_ID`` / ``ASC_ISSUER_ID`` /
``ASC_KEY_PATH`` (default ``~/.appstoreconnect/private_keys/AuthKey_<id>.p8``) or
the JSON file ``~/.config/fst-release/asc.json``
(``{"key_id", "issuer_id", "key_path", "app_id"?}``). Missing credentials make every
command print ``{"blocked": "missing_asc_credentials"}`` and exit 4.

Exit codes: 0 ok, 1 usage or API failure (``status`` exits 5 with
``blocked: asc_error``), 3 refused (a version is in review, or ``stale_whats_new``:
a newer version was released after the build's What's New was generated), 4 blocked.

Nothing here ever prints the private key or the signed token.
"""

from __future__ import annotations

import argparse
import base64
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

# region Constants

API_ROOT = "https://api.appstoreconnect.apple.com"
REPO_ROOT = Path(__file__).resolve().parents[2]
PROJECT_YML = REPO_ROOT / "apple" / "project.yml"

#: platform group -> (ASC platform, default bundle id, project.yml target).
PLATFORMS: Dict[str, Tuple[str, str, str]] = {
    "ios": ("IOS", "com.sfenton.festivalscoretracker.native", "FestivalMobile"),
    "macos": ("MAC_OS", "com.sfenton.festivalscoretracker.mac", "FestivalDesktop"),
}

#: A version in any of these states must never be disturbed (design §8).
IN_REVIEW_STATES = frozenset({
    "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_APPLE_RELEASE", "PENDING_DEVELOPER_RELEASE",
    "PROCESSING_FOR_APP_STORE", "PROCESSING_FOR_DISTRIBUTION",
})
RELEASED_STATES = frozenset({"READY_FOR_SALE", "READY_FOR_DISTRIBUTION"})
#: States of versions that reached customers at some point (the What's New history).
RELEASED_HISTORY_STATES = RELEASED_STATES | frozenset({
    "REPLACED_WITH_NEW_VERSION", "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE"})
EDITABLE_STATES = frozenset({
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
    "INVALID_BINARY", "READY_FOR_REVIEW",
})
#: Review submission states that mean Apple (or the queue) owns the submission.
IN_REVIEW_SUBMISSION_STATES = ("WAITING_FOR_REVIEW", "IN_REVIEW")

EXIT_OK, EXIT_FAIL, EXIT_REFUSED, EXIT_BLOCKED, EXIT_ASC_ERROR = 0, 1, 3, 4, 5
WHATS_NEW_LIMIT = 4000
BETA_NOTES_LIMIT = 4000
#: ``submit(baseline=...)`` default: skip the What's New staleness check (builds without a marker).
UNCHECKED = object()

# endregion

# region Errors and credentials


class AscError(Exception):
    """An App Store Connect request failed.

    Attributes:
        status: HTTP status code (0 for transport failures).
        detail: Short, token-free description from the API response.
    """

    def __init__(self, status: int, detail: str) -> None:
        super().__init__("ASC HTTP %s: %s" % (status, detail))
        self.status = status
        self.detail = detail


class Blocked(Exception):
    """A precondition (credentials, app record) is missing; maps to exit 4."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


@dataclass
class Credentials:
    """App Store Connect API key identity.

    Attributes:
        key_id: The key's 10-character ID.
        issuer_id: The team's issuer UUID.
        key_path: Path to the ``.p8`` private key.
        app_id: Optional pinned ASC app ID (skips the bundle-id lookup).
    """

    key_id: str
    issuer_id: str
    key_path: Path
    app_id: Optional[str] = None


def config_path(env: Dict[str, str]) -> Path:
    """Return the JSON credential file path (``FST_RELEASE_CONFIG`` overrides)."""
    override = env.get("FST_RELEASE_CONFIG")
    if override:
        return Path(override)
    return Path(env.get("HOME", str(Path.home()))) / ".config" / "fst-release" / "asc.json"


def load_credentials(env: Optional[Dict[str, str]] = None) -> Optional[Credentials]:
    """Resolve credentials from the environment, then the JSON config file.

    Args:
        env: Environment mapping (defaults to ``os.environ``).

    Returns:
        Credentials whose key file exists, or ``None`` when anything is missing.
    """
    env = dict(os.environ) if env is None else env
    file_cfg: Dict[str, Any] = {}
    path = config_path(env)
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            file_cfg = loaded
    except (OSError, ValueError):
        pass
    key_id = env.get("ASC_KEY_ID") or file_cfg.get("key_id")
    issuer = env.get("ASC_ISSUER_ID") or file_cfg.get("issuer_id")
    if not key_id or not issuer:
        return None
    raw_path = env.get("ASC_KEY_PATH") or file_cfg.get("key_path")
    if raw_path:
        key_path = Path(os.path.expanduser(str(raw_path)))
    else:
        home = Path(env.get("HOME", str(Path.home())))
        key_path = home / ".appstoreconnect" / "private_keys" / ("AuthKey_%s.p8" % key_id)
    if not key_path.is_file():
        return None
    app_id = env.get("ASC_APP_ID") or file_cfg.get("app_id") or None
    return Credentials(str(key_id), str(issuer), key_path, str(app_id) if app_id else None)


# endregion

# region JWT


def b64url(data: bytes) -> str:
    """Base64url-encode without padding."""
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_to_raw(der: bytes, size: int = 32) -> bytes:
    """Convert a DER ECDSA signature to the fixed-width ``r || s`` JWS form.

    Args:
        der: ``SEQUENCE { INTEGER r, INTEGER s }`` as printed by ``openssl dgst -sign``.
        size: Byte width of each integer (32 for ES256).

    Returns:
        ``2 * size`` bytes.

    Raises:
        ValueError: The input is not a well-formed ECDSA signature.
    """
    def read_len(buf: bytes, pos: int) -> Tuple[int, int]:
        if pos >= len(buf):
            raise ValueError("truncated DER length")
        first = buf[pos]
        pos += 1
        if first < 0x80:
            return first, pos
        count = first & 0x7F
        if count == 0 or count > 2 or pos + count > len(buf):
            raise ValueError("unsupported DER length")
        return int.from_bytes(buf[pos:pos + count], "big"), pos + count

    if len(der) < 8 or der[0] != 0x30:
        raise ValueError("not a DER SEQUENCE")
    seq_len, pos = read_len(der, 1)
    if pos + seq_len != len(der):
        raise ValueError("DER length mismatch")
    parts = []
    for _ in range(2):
        if pos >= len(der) or der[pos] != 0x02:
            raise ValueError("expected DER INTEGER")
        n, pos = read_len(der, pos + 1)
        if pos + n > len(der):
            raise ValueError("truncated DER INTEGER")
        value = der[pos:pos + n].lstrip(b"\x00")
        if len(value) > size:
            raise ValueError("DER INTEGER too large")
        parts.append(value.rjust(size, b"\x00"))
        pos += n
    if pos != len(der):
        raise ValueError("trailing DER bytes")
    return parts[0] + parts[1]


def openssl_sign(key_path: Path, data: bytes) -> bytes:
    """Sign ``data`` with SHA-256 and an EC key via the ``openssl`` CLI (DER output).

    Args:
        key_path: PKCS#8 PEM ``.p8`` key.
        data: Bytes to sign, delivered on stdin.

    Returns:
        The DER-encoded signature.

    Raises:
        RuntimeError: ``openssl`` failed (stderr is not echoed; it may name the key).
    """
    proc = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
        input=data, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if proc.returncode != 0 or not proc.stdout:
        raise RuntimeError("openssl signing failed (exit %d)" % proc.returncode)
    return proc.stdout


def make_jwt(creds: Credentials, now: Optional[float] = None,
             signer: Callable[[Path, bytes], bytes] = openssl_sign) -> str:
    """Build an App Store Connect ES256 token valid for 20 minutes.

    Args:
        creds: Key identity.
        now: Issue time in epoch seconds (defaults to the current time).
        signer: DER signature provider; injectable for tests.

    Returns:
        The compact JWT.
    """
    issued = int(time.time() if now is None else now)
    header = {"alg": "ES256", "kid": creds.key_id, "typ": "JWT"}
    payload = {"iss": creds.issuer_id, "iat": issued, "exp": issued + 20 * 60,
               "aud": "appstoreconnect-v1"}
    signing_input = "%s.%s" % (
        b64url(json.dumps(header, separators=(",", ":")).encode()),
        b64url(json.dumps(payload, separators=(",", ":")).encode()),
    )
    signature = der_to_raw(signer(creds.key_path, signing_input.encode("ascii")))
    return "%s.%s" % (signing_input, b64url(signature))


# endregion

# region HTTP client

Transport = Callable[[str, str, Dict[str, str], Optional[bytes]], Tuple[int, Any]]


def urllib_transport(method: str, url: str, headers: Dict[str, str],
                     body: Optional[bytes]) -> Tuple[int, Any]:
    """Production transport: one HTTPS request via ``urllib``.

    Returns:
        ``(status, parsed JSON or None)``; HTTP errors are returned, not raised.
    """
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            status = response.status
    except urllib.error.HTTPError as err:
        raw = err.read()
        status = err.code
    except urllib.error.URLError as err:
        raise AscError(0, "network error: %s" % err.reason)
    try:
        return status, (json.loads(raw.decode("utf-8")) if raw else None)
    except ValueError:
        return status, None


def _error_detail(payload: Any) -> str:
    """Summarize an ASC error body, including ``meta.associatedErrors`` reasons."""
    if isinstance(payload, dict) and payload.get("errors"):
        first = payload["errors"][0]
        detail = "%s: %s" % (first.get("code", "error"), first.get("detail") or first.get("title", ""))
        associated = ((first.get("meta") or {}).get("associatedErrors") or {})
        reasons = ["%s: %s" % (e.get("code", "error"), e.get("detail") or e.get("title", ""))
                   for errs in associated.values() for e in (errs or [])]
        if reasons:
            detail += " [" + "; ".join(reasons) + "]"
        return detail
    return "no error body"


class AscClient:
    """Minimal JSON:API client for App Store Connect.

    Attributes:
        planned: In dry-run mode, the writes that would have been sent.
    """

    def __init__(self, creds: Credentials, transport: Transport = urllib_transport,
                 dry_run: bool = False,
                 signer: Callable[[Path, bytes], bytes] = openssl_sign,
                 clock: Callable[[], float] = time.time) -> None:
        self.creds = creds
        self.transport = transport
        self.dry_run = dry_run
        self.signer = signer
        self.clock = clock
        self.planned: List[Dict[str, Any]] = []
        self._token: Optional[str] = None
        self._token_at = 0.0

    def _auth(self) -> str:
        now = self.clock()
        if self._token is None or now - self._token_at > 15 * 60:
            self._token = make_jwt(self.creds, now, self.signer)
            self._token_at = now
        return self._token

    def request(self, method: str, path: str, params: Optional[Dict[str, str]] = None,
                body: Optional[Dict[str, Any]] = None) -> Any:
        """Send one request and return the parsed JSON body.

        In dry-run mode every non-GET is recorded in ``planned`` and answered with
        a placeholder resource id instead of being sent.

        Raises:
            AscError: HTTP status >= 400.
        """
        if method != "GET" and self.dry_run:
            self.planned.append({"method": method, "path": path, "body": body})
            return {"data": {"id": "DRY-RUN"}}
        url = API_ROOT + path
        if params:
            url += "?" + urllib.parse.urlencode(params, safe="[],.")
        headers = {"Authorization": "Bearer " + self._auth(), "Accept": "application/json"}
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        status, payload = self.transport(method, url, headers, data)
        if status >= 400:
            raise AscError(status, _error_detail(payload))
        return payload if payload is not None else {}

    def get(self, path: str, params: Optional[Dict[str, str]] = None) -> Any:
        """GET ``path`` with query ``params``."""
        return self.request("GET", path, params)


# endregion

# region Ledger and project version


def ledger_path(env: Optional[Dict[str, str]] = None) -> Path:
    """Return the local build ledger path (``FST_RELEASE_LEDGER`` overrides)."""
    env = dict(os.environ) if env is None else env
    override = env.get("FST_RELEASE_LEDGER")
    if override:
        return Path(override)
    home = Path(env.get("HOME", str(Path.home())))
    return home / ".local" / "state" / "fst-release" / "builds.json"


def read_ledger(path: Path) -> Dict[str, Dict[str, Dict[str, str]]]:
    """Read ``{platform: {build: {version, sha, recorded_at}}}`` (empty when absent/corrupt)."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def record_build(path: Path, platform: str, build: str, version: str, sha: str) -> None:
    """Atomically map a build number to the git SHA it was archived from."""
    data = read_ledger(path)
    data.setdefault(platform, {})[str(build)] = {
        "version": version, "sha": sha,
        "recorded_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".builds-")
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
            handle.write("\n")
        os.replace(tmp, str(path))
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def ledger_sha(ledger: Dict[str, Any], platform: str, build: Optional[str]) -> Optional[str]:
    """Look up the git SHA recorded for ``build`` (``None`` when unknown)."""
    if not build:
        return None
    entry = ledger.get(platform, {}).get(str(build))
    sha = entry.get("sha") if isinstance(entry, dict) else None
    return str(sha) if sha else None


def _gh_text(args: List[str]) -> str:
    proc = subprocess.run(["gh"] + args, capture_output=True, text=True, timeout=120)
    if proc.returncode != 0:
        raise RuntimeError("gh api failed: %s" % (proc.stderr or "").strip()[-200:])
    return proc.stdout


def _gh_bytes(args: List[str]) -> bytes:
    proc = subprocess.run(["gh"] + args, capture_output=True, timeout=120)
    if proc.returncode != 0:
        raise RuntimeError("gh api failed: %s" % (proc.stderr or b"").decode("utf-8", "replace").strip()[-200:])
    return proc.stdout


def _newest_artifact(name: str, repo: str, runner: Callable[[List[str]], str]) -> Optional[Dict[str, Any]]:
    query = "repos/%s/actions/artifacts?per_page=5&name=%s" % (repo, urllib.parse.quote(name, safe=""))
    try:
        listing = json.loads(runner(["api", query]) or "{}")
    except (RuntimeError, ValueError, OSError):
        return None
    for artifact in listing.get("artifacts") or []:
        if artifact.get("name") == name and not artifact.get("expired"):
            return artifact
    return None


def artifact_marker(name: str, repo: str, runner: Optional[Callable[[List[str]], str]] = None,
                    fetch: Optional[Callable[[List[str]], bytes]] = None) -> Optional[Dict[str, Any]]:
    """Download the newest ``name`` artifact and return its ``build.json`` (``None`` when unavailable).

    ``ios-release-build`` uploads a ``fst-ios-build_<build>`` marker per upload with the build's version,
    SHA, version tag, What's New baseline and notes.
    """
    artifact = _newest_artifact(name, repo, runner or _gh_text)
    if artifact is None or not artifact.get("id"):
        return None
    try:
        blob = (fetch or _gh_bytes)(["api", "repos/%s/actions/artifacts/%s/zip" % (repo, artifact["id"])])
        with zipfile.ZipFile(io.BytesIO(blob)) as archive:
            data = json.loads(archive.read("build.json").decode("utf-8"))
    except (RuntimeError, OSError, KeyError, ValueError, zipfile.BadZipFile):
        return None
    if not isinstance(data, dict):
        return None
    data.setdefault("run_head_sha", (artifact.get("workflow_run") or {}).get("head_sha"))
    return data


def artifact_head_sha(name: str, repo: str, runner: Optional[Callable[[List[str]], str]] = None,
                      fetch: Optional[Callable[[List[str]], bytes]] = None) -> Optional[str]:
    """Return the commit a build marker artifact was archived from (``None`` when unknown).

    Used inside GitHub Actions, where the build ledger of the machine that archived the build is not
    available. The marker's own ``sha`` (the checked-out version tag) wins; markers that cannot be
    downloaded fall back to the producing run's head SHA.
    """
    marker = artifact_marker(name, repo, runner, fetch)
    if marker and marker.get("sha"):
        return str(marker["sha"])
    artifact = _newest_artifact(name, repo, runner or _gh_text)
    sha = (artifact or {}).get("workflow_run", {}).get("head_sha") if artifact else None
    return str(sha) if sha else None


def project_version(group: str, project_yml: Path = PROJECT_YML) -> str:
    """Read ``MARKETING_VERSION`` for the platform's app target from ``apple/project.yml``."""
    target = PLATFORMS[group][2]
    inside = False
    for line in project_yml.read_text(encoding="utf-8").splitlines():
        if re.match(r"^  \S", line):
            inside = line.strip() == target + ":"
        if inside:
            found = re.match(r'^\s+MARKETING_VERSION:\s*"?([0-9][0-9.]*)"?\s*$', line)
            if found:
                return found.group(1)
    raise ValueError("MARKETING_VERSION not found for %s" % target)


def parse_version(text: str) -> Tuple[int, ...]:
    """Parse ``1.2.3`` into a comparable tuple (non-numeric parts raise ``ValueError``)."""
    return tuple(int(part) for part in text.split("."))


def bump_patch(text: str) -> str:
    """Return ``text`` with its patch component incremented (``1.2`` -> ``1.2.1``)."""
    parts = list(parse_version(text))
    while len(parts) < 3:
        parts.append(0)
    parts[2] += 1
    return ".".join(str(p) for p in parts[:3])


# endregion

# region ASC queries


def resolve_app(client: AscClient, bundle_id: str) -> str:
    """Return the ASC app id for ``bundle_id`` (or the pinned ``app_id``).

    Raises:
        Blocked: ``app_not_found`` when no app record matches.
    """
    if client.creds.app_id:
        return client.creds.app_id
    payload = client.get("/v1/apps", {"filter[bundleId]": bundle_id, "limit": "1"})
    apps = payload.get("data") or []
    if not apps:
        raise Blocked("app_not_found")
    return str(apps[0]["id"])


def version_state(resource: Dict[str, Any]) -> Optional[str]:
    """Return the version state (``appVersionState`` or the older ``appStoreState``)."""
    attrs = resource.get("attributes") or {}
    return attrs.get("appVersionState") or attrs.get("appStoreState")


def list_versions(client: AscClient, app_id: str, asc_platform: str) -> List[Dict[str, Any]]:
    """List the app's versions for a platform, newest first (sorted client-side)."""
    payload = client.get("/v1/apps/%s/appStoreVersions" % app_id,
                         {"filter[platform]": asc_platform, "limit": "50"})
    versions = list(payload.get("data") or [])
    versions.sort(key=lambda v: (v.get("attributes") or {}).get("createdDate") or "", reverse=True)
    return versions


def build_record(resource: Dict[str, Any], included: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Flatten a build resource plus its included preReleaseVersion."""
    attrs = resource.get("attributes") or {}
    rel = ((resource.get("relationships") or {}).get("preReleaseVersion") or {}).get("data") or {}
    marketing = None
    for item in included:
        if item.get("type") == "preReleaseVersions" and item.get("id") == rel.get("id"):
            marketing = (item.get("attributes") or {}).get("version")
    return {"id": resource.get("id"), "version": marketing, "build": attrs.get("version"),
            "processing_state": attrs.get("processingState"), "expired": bool(attrs.get("expired"))}


def list_builds(client: AscClient, app_id: str, asc_platform: str, limit: int = 1,
                number: Optional[str] = None) -> List[Dict[str, Any]]:
    """List builds newest first (optionally only build ``number``)."""
    params = {"filter[app]": app_id, "filter[preReleaseVersion.platform]": asc_platform,
              "sort": "-uploadedDate", "limit": str(limit), "include": "preReleaseVersion"}
    if number is not None:
        params["filter[version]"] = str(number)
    payload = client.get("/v1/builds", params)
    included = payload.get("included") or []
    return [build_record(item, included) for item in (payload.get("data") or [])]


def in_review_submissions(client: AscClient, app_id: str, asc_platform: str) -> List[str]:
    """Return ids of review submissions that are waiting for or in review."""
    payload = client.get("/v1/apps/%s/reviewSubmissions" % app_id, {
        "filter[platform]": asc_platform,
        "filter[state]": ",".join(IN_REVIEW_SUBMISSION_STATES), "limit": "10"})
    return [str(item["id"]) for item in (payload.get("data") or [])]


# endregion

# region Commands


def blocked_status(reason: str) -> Dict[str, Any]:
    """Return the design §8 status shape for a blocked run (``in_review`` false)."""
    return {"in_review": False, "state": None, "version": None, "latest_build": None,
            "released_sha": None, "blocked": reason}


def collect_status(client: AscClient, group: str, bundle_id: str, ledger: Dict[str, Any],
                   sha_lookup: Optional[Callable[[str], Optional[str]]] = None) -> Dict[str, Any]:
    """Build the design §8 status document.

    Args:
        client: Authenticated client.
        group: ``ios`` or ``macos``.
        bundle_id: App bundle id.
        ledger: Parsed local build ledger (build number -> git SHA).
        sha_lookup: Fallback build number -> git SHA (artifact markers inside Actions).

    Returns:
        ``{in_review, state, version, latest_build, released_sha, blocked}``.

    Raises:
        Blocked: The app record does not exist.
    """
    asc_platform = PLATFORMS[group][0]
    app_id = resolve_app(client, bundle_id)
    versions = list_versions(client, app_id, asc_platform)
    busy = next((v for v in versions if version_state(v) in IN_REVIEW_STATES), None)
    current = busy or (versions[0] if versions else None)
    in_review = busy is not None or bool(in_review_submissions(client, app_id, asc_platform))

    latest = None
    builds = list_builds(client, app_id, asc_platform, limit=1)
    if builds:
        b = builds[0]
        latest = {"version": b["version"], "build": b["build"],
                  "sha": ledger_sha(ledger, asc_platform, b["build"])
                         or (sha_lookup(b["build"]) if sha_lookup and b["build"] else None),
                  "processing_state": b["processing_state"]}

    released_sha = None
    released = next((v for v in versions if version_state(v) in RELEASED_STATES), None)
    if released is not None:
        attached = client.get("/v1/appStoreVersions/%s/build" % released["id"])
        data = attached.get("data") or {}
        build_no = (data.get("attributes") or {}).get("version")
        released_sha = ledger_sha(ledger, asc_platform, build_no) or (
            sha_lookup(build_no) if sha_lookup and build_no else None)

    return {"in_review": in_review,
            "state": version_state(current) if current else None,
            "version": (current.get("attributes") or {}).get("versionString") if current else None,
            "latest_build": latest, "released_sha": released_sha, "blocked": None}


def _version_key(text: str) -> Optional[Tuple[int, ...]]:
    try:
        return parse_version(text)
    except ValueError:
        return None


def released_versions(versions: List[Dict[str, Any]]) -> List[str]:
    """Version strings that reached customers (current or replaced), highest first."""
    found = {str((v.get("attributes") or {}).get("versionString") or "") for v in versions
             if version_state(v) in RELEASED_HISTORY_STATES}
    keyed = [(k, text) for text in found if text for k in [_version_key(text)] if k is not None]
    return [text for _k, text in sorted(keyed, reverse=True)]


def released_baseline(versions: List[Dict[str, Any]], marketing: str) -> Optional[str]:
    """The highest released version below ``marketing`` (the What's New baseline), or ``None``."""
    target = _version_key(marketing)
    for text in released_versions(versions):
        key = _version_key(text)
        if target is None or (key is not None and key < target):
            return text
    return None


def compute_next_version(versions: List[Dict[str, Any]], project: str) -> Tuple[str, str]:
    """Choose the marketing version for the next build.

    Args:
        versions: App versions newest first.
        project: ``MARKETING_VERSION`` from ``apple/project.yml``.

    Returns:
        ``(version, reason)``; an editable version is reused, otherwise the patch
        of the highest known version (or the project value) is bumped, and an app
        with no versions uses the project value as is.
    """
    editable = next((v for v in versions if version_state(v) in EDITABLE_STATES), None)
    if editable is not None:
        return str((editable.get("attributes") or {})["versionString"]), "reuse_editable"
    if not versions:
        return project, "first_version"
    known = [parse_version(project)]
    for item in versions:
        try:
            known.append(parse_version(str((item.get("attributes") or {}).get("versionString"))))
        except ValueError:
            continue
    return bump_patch(".".join(str(p) for p in max(known))), "bump_patch"


#: Symbols App Store Connect rejects in What's New / TestFlight text ("contains invalid characters"), with
#: readable substitutes. Anything else outside ``ASC_SAFE_RANGES`` that is not a letter, digit, mark or
#: separator is dropped.
ASC_REPLACEMENTS = {"\u2715": "\u00d7", "\u2716": "\u00d7", "\u2717": "\u00d7", "\u2718": "\u00d7",
                    "\u274c": "\u00d7", "\u2713": "check", "\u2714": "check", "\u2705": "check",
                    "\u2190": "<-", "\u2192": "->", "\u2191": "up", "\u2193": "down", "\u21c4": "<->",
                    "\u2194": "<->", "\u2b06": "up", "\u2b07": "down"}
ASC_SAFE_RANGES = ((0x0000, 0x024F), (0x2000, 0x206F), (0x20A0, 0x20CF), (0x2100, 0x214F))


def asc_text(text: str) -> str:
    """Make release-note text acceptable to App Store Connect (keeps bullets, smart punctuation and letters)."""
    out = []
    for ch in unicodedata.normalize("NFC", text or ""):
        if ch in ASC_REPLACEMENTS:
            out.append(ASC_REPLACEMENTS[ch])
            continue
        code = ord(ch)
        if any(lo <= code <= hi for lo, hi in ASC_SAFE_RANGES) or unicodedata.category(ch)[0] in "LMNZ":
            out.append(ch)
    return re.sub(r"[ \t]{2,}", " ", "".join(out))


def _write_whats_new(client: AscClient, version_id: str, notes: str, has_released: bool) -> str:
    """Set en-US What's New; returns ``set`` or ``skipped_first_version``."""
    if not has_released:
        return "skipped_first_version"
    items: List[Dict[str, Any]] = []
    if not (client.dry_run and version_id == "DRY-RUN"):
        existing = client.get("/v1/appStoreVersions/%s/appStoreVersionLocalizations" % version_id,
                              {"filter[locale]": "en-US", "limit": "1"})
        items = existing.get("data") or []
    if items:
        client.request("PATCH", "/v1/appStoreVersionLocalizations/%s" % items[0]["id"], body={
            "data": {"type": "appStoreVersionLocalizations", "id": items[0]["id"],
                     "attributes": {"whatsNew": notes}}})
    else:
        client.request("POST", "/v1/appStoreVersionLocalizations", body={
            "data": {"type": "appStoreVersionLocalizations",
                     "attributes": {"locale": "en-US", "whatsNew": notes},
                     "relationships": {"appStoreVersion": {
                         "data": {"type": "appStoreVersions", "id": version_id}}}}})
    return "set"


RELEASE_TYPES = ("MANUAL", "AFTER_APPROVAL")


def submit(client: AscClient, group: str, bundle_id: str, build_number: str,
           notes: str, release_type: str = "MANUAL", baseline: Any = UNCHECKED) -> Dict[str, Any]:
    """Attach a VALID build to its version and submit it for App Store review.

    Sequence: refuse when anything is in review, find the build, create/reuse the
    editable version for the build's marketing version, set What's New, PATCH the
    build and release type, then create a review submission, add the version as
    an item and PATCH ``submitted=true``.

    Args:
        release_type: ``MANUAL`` (approved versions wait for a human release) or
            ``AFTER_APPROVAL`` (auto-release once review passes).
        baseline: The released version the build's bundled What's New was generated against
            (``None`` = no release yet). When given and the store has released a newer version since,
            nothing is written and ``refused: stale_whats_new`` asks for a rebuild.

    Returns:
        A result document; ``refused`` is set (and nothing written) when in review or stale.

    Raises:
        Blocked: App record missing.
        AscError: The API rejected a request.
        ValueError: The build is missing, not VALID, or expired, or the
            release type is unknown.
    """
    if release_type not in RELEASE_TYPES:
        raise ValueError("unknown release type %r" % release_type)
    asc_platform = PLATFORMS[group][0]
    app_id = resolve_app(client, bundle_id)
    versions = list_versions(client, app_id, asc_platform)
    if any(version_state(v) in IN_REVIEW_STATES for v in versions) \
            or in_review_submissions(client, app_id, asc_platform):
        return {"submitted": False, "refused": "in_review"}

    builds = list_builds(client, app_id, asc_platform, limit=5, number=build_number)
    build = next((b for b in builds if str(b["build"]) == str(build_number)), None)
    if build is None:
        raise ValueError("build %s not found" % build_number)
    if build["processing_state"] != "VALID" or build["expired"]:
        raise ValueError("build %s is not submittable (state %s, expired %s)" % (
            build_number, build["processing_state"], build["expired"]))
    marketing = build["version"]
    if not marketing:
        raise ValueError("build %s has no marketing version" % build_number)
    if baseline is not UNCHECKED:
        current = released_baseline(versions, marketing)
        if current != baseline:
            return {"submitted": False, "refused": "stale_whats_new", "version": marketing,
                    "build": str(build_number), "baseline": baseline, "current_baseline": current}

    notes = asc_text(notes or "").strip()
    if not notes:
        return {"submitted": False, "refused": "no_user_facing_changes", "version": marketing,
                "build": str(build_number)}
    if len(notes) > WHATS_NEW_LIMIT:
        notes = notes[:WHATS_NEW_LIMIT].rstrip()
    has_released = any(version_state(v) in RELEASED_STATES for v in versions)

    editable = next((v for v in versions if version_state(v) in EDITABLE_STATES), None)
    if editable is None:
        created = client.request("POST", "/v1/appStoreVersions", body={"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": asc_platform, "versionString": marketing,
                           "releaseType": release_type},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        version_id = str(created["data"]["id"])
    else:
        version_id = str(editable["id"])

    whats_new = _write_whats_new(client, version_id, notes, has_released)
    attributes: Dict[str, Any] = {"releaseType": release_type}
    if editable is not None and (editable.get("attributes") or {}).get("versionString") != marketing:
        attributes["versionString"] = marketing
    client.request("PATCH", "/v1/appStoreVersions/%s" % version_id, body={"data": {
        "type": "appStoreVersions", "id": version_id, "attributes": attributes,
        "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})

    # After App Review rejects a version its submission stays open (UNRESOLVED_ISSUES) and still owns the
    # version; resubmitting means submitting that same submission again.
    reusable = client.get("/v1/apps/%s/reviewSubmissions" % app_id, {
        "filter[platform]": asc_platform, "filter[state]": "READY_FOR_REVIEW,UNRESOLVED_ISSUES", "limit": "1"})
    open_subs = reusable.get("data") or []
    if open_subs:
        submission_id = str(open_subs[0]["id"])
    else:
        sub = client.request("POST", "/v1/reviewSubmissions", body={"data": {
            "type": "reviewSubmissions", "attributes": {"platform": asc_platform},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        submission_id = str(sub["data"]["id"])
    items = client.get("/v1/reviewSubmissions/%s/items" % submission_id, {"limit": "50"}) \
        if open_subs else {}
    already = any(
        (((i.get("relationships") or {}).get("appStoreVersion") or {}).get("data") or {}).get("id")
        == version_id for i in (items.get("data") or []))
    if not already:
        client.request("POST", "/v1/reviewSubmissionItems", body={"data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
    client.request("PATCH", "/v1/reviewSubmissions/%s" % submission_id, body={"data": {
        "type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}}})
    return {"submitted": not client.dry_run, "dry_run": client.dry_run, "version": marketing,
            "build": str(build_number), "version_id": version_id,
            "submission_id": submission_id, "whats_new": whats_new}


def beta_notes(client: AscClient, group: str, bundle_id: str, build_number: str, notes: str,
               wait: float = 0, sleep: Callable[[float], None] = time.sleep,
               clock: Callable[[], float] = time.monotonic, interval: float = 30) -> Dict[str, Any]:
    """Set the en-US TestFlight "What to Test" text of one build.

    Args:
        wait: Seconds to keep polling while the uploaded build is not visible in ASC yet.

    Returns:
        ``{build, version, beta_notes: "set"}``.

    Raises:
        ValueError: Empty notes, or the build did not appear within ``wait``.
    """
    text = asc_text(notes or "").strip()[:BETA_NOTES_LIMIT].rstrip()
    if not text:
        raise ValueError("empty TestFlight notes")
    asc_platform = PLATFORMS[group][0]
    app_id = resolve_app(client, bundle_id)
    deadline = clock() + max(0.0, wait)
    while True:
        builds = list_builds(client, app_id, asc_platform, limit=5, number=build_number)
        build = next((b for b in builds if str(b["build"]) == str(build_number)), None)
        if build is not None:
            break
        if clock() >= deadline:
            raise ValueError("build %s not found" % build_number)
        sleep(interval)
    existing = client.get("/v1/builds/%s/betaBuildLocalizations" % build["id"], {"limit": "50"})
    loc = next((item for item in (existing.get("data") or [])
                if (item.get("attributes") or {}).get("locale") == "en-US"), None)
    if loc is not None:
        client.request("PATCH", "/v1/betaBuildLocalizations/%s" % loc["id"], body={"data": {
            "type": "betaBuildLocalizations", "id": loc["id"], "attributes": {"whatsNew": text}}})
    else:
        client.request("POST", "/v1/betaBuildLocalizations", body={"data": {
            "type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": text},
            "relationships": {"build": {"data": {"type": "builds", "id": build["id"]}}}}})
    return {"build": str(build_number), "version": build["version"], "beta_notes": "set",
            "dry_run": client.dry_run}


# endregion

# region CLI


#: Name App Store Connect gives certificates an API key creates (cloud-signed CI archives).
CI_CERT_MARKER = "created via api"
#: Development certificate types an automatic-signing archive can create.
DEV_CERT_TYPES = "DEVELOPMENT,IOS_DEVELOPMENT,MAC_APP_DEVELOPMENT"


def normalize_serial(serial: str) -> str:
    """Certificate serial as upper-case hex without separators or leading zeros (``serial=0A1B`` → ``A1B``)."""
    text = serial.split("=", 1)[-1].replace(":", "").strip().upper()
    return text.lstrip("0") or "0"


def create_certificate(client: AscClient, cert_type: str, csr_pem: str) -> Dict[str, Any]:
    """Create a signing certificate from a CSR (public input; the private key never leaves its owner).

    Returns:
        ``{id, name, serial, expires, certificate_type, der_base64}``; ``der_base64`` is the public
        certificate, safe to publish as an artifact.
    """
    body = "".join(line for line in csr_pem.strip().splitlines() if "-----" not in line)
    if not body:
        raise ValueError("empty CSR")
    payload = client.request("POST", "/v1/certificates", body={"data": {
        "type": "certificates", "attributes": {"certificateType": cert_type, "csrContent": body}}})
    data = payload.get("data") or {}
    attrs = data.get("attributes") or {}
    return {"id": data.get("id"), "name": attrs.get("name") or attrs.get("displayName"),
            "serial": normalize_serial(str(attrs.get("serialNumber") or "")),
            "expires": attrs.get("expirationDate"), "certificate_type": attrs.get("certificateType"),
            "der_base64": attrs.get("certificateContent")}


def prune_ci_certs(client: AscClient, keep_serials: Sequence[str] = ()) -> Dict[str, Any]:
    """Revoke development certificates created through the API (hosted-runner archives).

    Automatic signing on each fresh hosted runner asks App Store Connect for a new development certificate,
    which accumulate until the account limit blocks archives ("Your account has reached the maximum number
    of certificates"). Only certificates whose name says "Created via API" are revoked, so personal
    certificates made in Xcode with an Apple ID are kept; distribution certificates are never touched.

    Returns:
        ``{development_certificates, names, revoked, dry_run}``; ``names`` lists distinct certificate names
        (no ids or key material) for the job summary.
    """
    keep = {normalize_serial(s) for s in keep_serials if s}
    payload = client.get("/v1/certificates", {"filter[certificateType]": DEV_CERT_TYPES, "limit": "200",
                                               "fields[certificates]": "name,displayName,certificateType,serialNumber"})
    names = set()
    revoked = []
    items = payload.get("data") or [] if isinstance(payload, dict) else []
    for item in items:
        attrs = item.get("attributes") or {}
        label = " / ".join(str(attrs[k]) for k in ("name", "displayName") if attrs.get(k))
        names.add(label)
        if normalize_serial(str(attrs.get("serialNumber") or "")) in keep:
            continue
        if attrs.get("certificateType") in DEV_CERT_TYPES.split(",") and CI_CERT_MARKER in label.lower():
            client.request("DELETE", "/v1/certificates/%s" % item["id"])
            revoked.append(item["id"])
    return {"development_certificates": len(items), "names": sorted(names), "revoked": revoked,
            "kept": sorted(keep), "dry_run": client.dry_run}


def emit(document: Dict[str, Any]) -> None:
    """Print one JSON document on stdout."""
    print(json.dumps(document, sort_keys=False))


def build_parser() -> argparse.ArgumentParser:
    """Create the command-line parser."""
    parser = argparse.ArgumentParser(prog="fst_release.py", description=__doc__.split("\n")[0])
    groups = parser.add_subparsers(dest="group", required=True)
    for group in PLATFORMS:
        sub = groups.add_parser(group).add_subparsers(dest="command", required=True)
        for name in ("status", "next-version", "creds", "released-versions"):
            p = sub.add_parser(name)
            p.add_argument("--json", action="store_true")
            p.add_argument("--bundle-id")
        p = sub.add_parser("submit")
        p.add_argument("--build", required=True)
        notes = p.add_mutually_exclusive_group(required=True)
        notes.add_argument("--notes-file")
        notes.add_argument("--notes-stdin", action="store_true")
        p.add_argument("--dry-run", action="store_true")
        p.add_argument("--bundle-id")
        p.add_argument("--whats-new-baseline",
                       help="released version the build's What's New used ('none' = no release yet)")
        p = sub.add_parser("beta-notes")
        p.add_argument("--build", required=True)
        beta = p.add_mutually_exclusive_group(required=True)
        beta.add_argument("--notes-file")
        beta.add_argument("--notes-stdin", action="store_true")
        p.add_argument("--wait", type=float, default=0, help="seconds to wait for the build to appear")
        p.add_argument("--dry-run", action="store_true")
        p.add_argument("--bundle-id")
        p = sub.add_parser("prune-ci-certs")
        p.add_argument("--dry-run", action="store_true")
        p.add_argument("--keep-serial", action="append", default=[],
                       help="never revoke this certificate (the persistent CI identity); repeatable")
        p = sub.add_parser("create-certificate")
        p.add_argument("--type", default="DEVELOPMENT", choices=["DEVELOPMENT", "DISTRIBUTION"])
        p.add_argument("--csr-file", required=True)
        p.add_argument("--out", required=True, help="write the DER certificate here")
        p = sub.add_parser("record-build")
        p.add_argument("--build", required=True)
        p.add_argument("--version", required=True)
        p.add_argument("--sha", required=True)
    return parser


def main(argv: Optional[List[str]] = None, env: Optional[Dict[str, str]] = None,
         transport: Transport = urllib_transport,
         signer: Callable[[Path, bytes], bytes] = openssl_sign,
         stdin: Any = None) -> int:
    """Run the CLI.

    Args:
        argv: Arguments (defaults to ``sys.argv[1:]``).
        env: Environment mapping (defaults to ``os.environ``).
        transport: HTTP transport (injectable for tests).
        signer: JWT signature provider (injectable for tests).
        stdin: Text stream for ``--notes-stdin`` (defaults to ``sys.stdin``).

    Returns:
        The process exit code.
    """
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv[:1] == ["windows"]:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import fst_store  # Microsoft Store client shares this entry point and exit codes.
        return fst_store.main(argv[1:], env=env, stdin=stdin)
    args = build_parser().parse_args(argv)
    env = dict(os.environ) if env is None else env
    group = args.group
    asc_platform, default_bundle, _ = PLATFORMS[group]
    bundle_id = getattr(args, "bundle_id", None) or env.get("FST_RELEASE_BUNDLE_ID") or default_bundle

    if args.command == "record-build":
        record_build(ledger_path(env), asc_platform, args.build, args.version, args.sha)
        emit({"recorded": True, "build": args.build, "version": args.version, "sha": args.sha})
        return EXIT_OK

    creds = load_credentials(env)
    if creds is None:
        emit(blocked_status("missing_asc_credentials") if args.command == "status"
             else {"blocked": "missing_asc_credentials"})
        return EXIT_BLOCKED
    if args.command == "creds":
        emit({"key_id": creds.key_id, "issuer_id": creds.issuer_id, "key_path": str(creds.key_path)})
        return EXIT_OK

    dry_run = bool(getattr(args, "dry_run", False))
    client = AscClient(creds, transport=transport, dry_run=dry_run, signer=signer)
    try:
        if args.command == "status":
            lookup = None
            if env.get("FST_RELEASE_SHA_FROM_ARTIFACTS") == "1":
                repo = env.get("FST_NATIVE_REPO") or "SFenton/FestivalNativeApps"
                lookup = lambda build: artifact_head_sha("fst-%s-build_%s" % (group, build), repo)  # noqa: E731
            emit(collect_status(client, group, bundle_id, read_ledger(ledger_path(env)), sha_lookup=lookup))
            return EXIT_OK
        if args.command == "next-version":
            app_id = resolve_app(client, bundle_id)
            version, reason = compute_next_version(
                list_versions(client, app_id, asc_platform), project_version(group))
            if args.json:
                emit({"version": version, "reason": reason, "blocked": None})
            else:
                print(version)
            return EXIT_OK
        if args.command == "prune-ci-certs":
            emit(prune_ci_certs(client, args.keep_serial))
            return EXIT_OK
        if args.command == "create-certificate":
            result = create_certificate(client, args.type, Path(args.csr_file).read_text(encoding="utf-8"))
            der = result.pop("der_base64") or ""
            Path(args.out).write_bytes(base64.b64decode(der))
            emit(result)
            return EXIT_OK
        if args.command == "released-versions":
            app_id = resolve_app(client, bundle_id)
            emit({"released": released_versions(list_versions(client, app_id, asc_platform))})
            return EXIT_OK
        if args.command == "beta-notes":
            notes = (stdin or sys.stdin).read() if args.notes_stdin else Path(args.notes_file).read_text(encoding="utf-8")
            result = beta_notes(client, group, bundle_id, args.build, notes, wait=args.wait)
            if dry_run:
                result["planned"] = client.planned
            emit(result)
            return EXIT_OK
        if args.command == "submit":
            if args.notes_stdin:
                notes = (stdin or sys.stdin).read()
            else:
                notes = Path(args.notes_file).read_text(encoding="utf-8")
            baseline: Any = UNCHECKED
            if args.whats_new_baseline is not None:
                baseline = None if args.whats_new_baseline in ("", "none") else args.whats_new_baseline
            result = submit(client, group, bundle_id, args.build, notes,
                            env.get("FST_APPSTORE_RELEASE_TYPE") or "MANUAL", baseline)
            if dry_run:
                result["planned"] = client.planned
            emit(result)
            return EXIT_REFUSED if result.get("refused") else EXIT_OK
    except Blocked as err:
        emit(blocked_status(err.reason) if args.command == "status" else {"blocked": err.reason})
        return EXIT_BLOCKED
    except AscError as err:
        message = "%s" % err
        if args.command == "status":
            document = blocked_status("asc_error")
            document["error"] = message
            emit(document)
            return EXIT_ASC_ERROR
        emit({"error": message})
        return EXIT_FAIL
    except (ValueError, OSError, RuntimeError) as err:
        emit({"error": str(err)})
        return EXIT_FAIL
    return EXIT_FAIL


# endregion

if __name__ == "__main__":
    sys.exit(main())
