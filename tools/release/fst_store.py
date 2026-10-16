#!/usr/bin/env python3
"""Microsoft Store submission client for the Festival release machine (Windows).

Speaks the same contract as ``fst_release.py`` so the release orchestrator
(``festival-report-tracker``) can drive it through the ``fst-release`` wrapper
(``fst_release.py windows ...`` dispatches here)::

    fst_store.py status --json
    fst_store.py submit --build 0.1.912.0 --notes-stdin [--dry-run]
    fst_store.py record-build --build 0.1.912.0 --version 0.1.912.0 --sha <git sha>

Packages come from the newest successful ``windows-release-build`` run on master
(artifact ``fst-windows-msix_<version>_<sha>[_placeholder]``, fetched with ``gh``).
Placeholder-identity builds are reported but never valid for submission. ``submit``
replaces the package and release notes on a clone of the last published
submission and commits it with ``targetPublishMode: Manual`` (always): the Store
certifies it, but nothing goes live until someone presses *Publish now* in
Partner Center. It runs only inside ``store-release.yml`` (``actions_job.py``),
never from a local machine. Drafts it created are recognized by the
``[fst-release]`` prefix of ``notesForCertification``, so it keeps no local state.

Credentials come from ``MSSTORE_TENANT_ID`` / ``MSSTORE_CLIENT_ID`` /
``MSSTORE_CLIENT_SECRET`` / ``MSSTORE_SELLER_ID`` / ``MSSTORE_APP_ID`` (Store ID)
or the JSON file ``~/.config/fst-release/msstore.json`` (``tenant_id``,
``client_id``, ``client_secret``, ``seller_id``, ``app_id``). Missing values make
every command print ``{"blocked": "missing_store_credentials"}`` and exit 4.

Exit codes match ``fst_release.py``: 0 ok, 1 failure (``status`` exits 5 with
``blocked: store_error``), 3 refused because a submission is in certification,
4 blocked. The client secret, access token and upload SAS URL are never printed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.parse
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fst_release  # noqa: E402  (shared ledger, transport and exit codes)

# region Constants

API_ROOT = "https://manage.devcenter.microsoft.com/v1.0/my"
TOKEN_URL = "https://login.microsoftonline.com/%s/oauth2/token"
TOKEN_RESOURCE = "https://manage.devcenter.microsoft.com"
LEDGER_PLATFORM = "WINDOWS"
DEFAULT_REPO = "SFenton/FestivalNativeApps"
WORKFLOW = "windows-release-build.yml"
ARTIFACT_PREFIX = "fst-windows-msix_"
ARTIFACT_RE = re.compile(r"^fst-windows-msix_(\d+\.\d+\.\d+\.\d+)_([0-9a-f]{7,40})(_placeholder)?$")
CREDENTIAL_FIELDS = ("tenant_id", "client_id", "client_secret", "seller_id", "app_id")

# Submission statuses (Microsoft Store submission API). A pending submission in any of these is
# owned by certification/publishing and must not be disturbed; PendingPublication is a certified
# Manual-mode submission waiting for a human to press "Publish now".
IN_REVIEW_STATUSES = frozenset({"CommitStarted", "PreProcessing", "Certification",
                                "PendingPublication", "Publishing", "Release"})
FAILED_STATUSES = frozenset({"CommitFailed", "PreProcessingFailed", "CertificationFailed",
                             "PublishFailed", "ReleaseFailed", "Canceled"})
RELEASE_NOTES_LIMIT = 1500
PUBLISH_MODE = "Manual"
#: ``submit --publish-at``: the Store publishes a certified submission at this time by itself (the API has no
#: "Publish now"), which is how the release train's Monday release reaches Windows.
SCHEDULED_MODE = "SpecificDate"
PUBLISH_AT_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
#: MSIX versions ``YYMM.<DD*100+NN>.<run>.0`` (versioning.msix_version) of release versions ``YYMM.DD.NN``.
MSIX_VERSION_RE = re.compile(r"^(\d{4})\.(\d{3,4})\.\d+\.0$")
RELEASE_VERSION_RE = re.compile(r"^\d{4}\.\d{2}\.\d{2}$")
OWN_MARKER = "[fst-release]"

EXIT_OK = fst_release.EXIT_OK
EXIT_FAIL = fst_release.EXIT_FAIL
EXIT_REFUSED = fst_release.EXIT_REFUSED
EXIT_BLOCKED = fst_release.EXIT_BLOCKED
EXIT_STORE_ERROR = fst_release.EXIT_ASC_ERROR

Transport = fst_release.Transport
Runner = Callable[[List[str]], str]

# endregion

# region Errors and credentials


class StoreError(Exception):
    """A Microsoft Store/Entra request failed.

    Attributes:
        status: HTTP status code (0 for transport failures).
        detail: Short, secret-free description from the response.
    """

    def __init__(self, status: int, detail: str) -> None:
        super().__init__("Store HTTP %s: %s" % (status, detail))
        self.status = status
        self.detail = detail


Blocked = fst_release.Blocked


@dataclass
class Credentials:
    """Partner Center API identity (an Entra app added under User management)."""

    tenant_id: str
    client_id: str
    client_secret: str = field(repr=False)
    seller_id: str
    app_id: str


def config_path(env: Dict[str, str]) -> Path:
    """Return the credential file path (``FST_MSSTORE_CONFIG`` overrides)."""
    override = env.get("FST_MSSTORE_CONFIG")
    if override:
        return Path(override)
    return Path(env.get("HOME", str(Path.home()))) / ".config" / "fst-release" / "msstore.json"


def load_credentials(env: Optional[Dict[str, str]] = None) -> Optional[Credentials]:
    """Load credentials from ``MSSTORE_*`` variables, falling back to the JSON file.

    Returns:
        Credentials, or ``None`` when any field is missing.
    """
    env = dict(os.environ) if env is None else env
    values = {name: env.get("MSSTORE_" + name.upper(), "") for name in CREDENTIAL_FIELDS}
    if not all(values.values()):
        try:
            data = json.loads(config_path(env).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            data = {}
        if isinstance(data, dict):
            for name in CREDENTIAL_FIELDS:
                values[name] = values[name] or str(data.get(name) or "")
    if not all(values.values()):
        return None
    return Credentials(**values)


# endregion

# region Store client


def _detail(payload: Any) -> str:
    if isinstance(payload, dict):
        for key in ("message", "error_description", "error", "code"):
            if payload.get(key):
                text = str(payload[key])
                return text.splitlines()[0][:300]
    return "no error body"


class StoreClient:
    """Minimal Microsoft Store submission API client.

    Args:
        creds: API identity.
        transport: HTTP transport (``fst_release.urllib_transport`` in production).
        dry_run: When true, mutating calls are recorded in ``planned`` instead of sent.
    """

    def __init__(self, creds: Credentials, transport: Transport = fst_release.urllib_transport,
                 dry_run: bool = False) -> None:
        self.creds = creds
        self.transport = transport
        self.dry_run = dry_run
        self.planned: List[str] = []
        self._token: Optional[str] = None

    def token(self) -> str:
        """Fetch (once) an access token with the client-credentials grant."""
        if self._token is None:
            body = urllib.parse.urlencode({
                "grant_type": "client_credentials", "client_id": self.creds.client_id,
                "client_secret": self.creds.client_secret, "resource": TOKEN_RESOURCE,
            }).encode()
            status, payload = self.transport(
                "POST", TOKEN_URL % urllib.parse.quote(self.creds.tenant_id, safe=""),
                {"Content-Type": "application/x-www-form-urlencoded"}, body)
            if status != 200 or not isinstance(payload, dict) or not payload.get("access_token"):
                raise StoreError(status, "token: " + _detail(payload))
            self._token = str(payload["access_token"])
        return self._token

    def request(self, method: str, path: str, body: Any = None) -> Any:
        """Send one JSON request under ``/v1.0/my``.

        Returns:
            The parsed JSON response (``{}`` for dry-run mutations and empty bodies).

        Raises:
            StoreError: Non-2xx response.
        """
        if self.dry_run and method != "GET":
            self.planned.append("%s %s" % (method, path))
            return {}
        data = json.dumps(body).encode() if body is not None else None
        headers = {"Authorization": "Bearer " + self.token(), "Accept": "application/json"}
        if data is not None:
            headers["Content-Type"] = "application/json"
        status, payload = self.transport(method, API_ROOT + path, headers, data)
        if status < 200 or status >= 300:
            raise StoreError(status, "%s %s: %s" % (method, path.split("?")[0], _detail(payload)))
        return payload if payload is not None else {}

    def get(self, path: str) -> Any:
        """GET a JSON resource."""
        return self.request("GET", path)

    def upload(self, sas_url: str, data: bytes) -> None:
        """PUT the package zip to the submission's Azure blob (SAS URL never logged)."""
        if self.dry_run:
            self.planned.append("PUT <fileUploadUrl> (%d bytes)" % len(data))
            return
        status, _ = self.transport("PUT", sas_url, {"x-ms-blob-type": "BlockBlob",
                                                    "Content-Type": "application/zip"}, data)
        if status < 200 or status >= 300:
            raise StoreError(status, "package upload failed")


# endregion

# region GitHub build artifacts


def gh_runner(args: List[str]) -> str:
    """Production runner: ``gh <args>`` returning stdout (raises RuntimeError on failure)."""
    proc = subprocess.run(["gh"] + args, capture_output=True, text=True, timeout=600)
    if proc.returncode != 0:
        raise RuntimeError("gh %s failed: %s" % (args[0], (proc.stderr or "").strip()[-300:]))
    return proc.stdout


def parse_artifact(name: str) -> Optional[Dict[str, Any]]:
    """Parse ``fst-windows-msix_<version>_<sha>[_placeholder]`` (``None`` when not ours)."""
    match = ARTIFACT_RE.match(name or "")
    if not match:
        return None
    return {"version": match.group(1), "sha": match.group(2), "placeholder": bool(match.group(3))}


def latest_artifact(run: Runner, repo: str) -> Optional[Dict[str, Any]]:
    """Return the newest successful master run's MSIX artifact.

    Returns:
        ``{version, sha, placeholder, name, run_id, expired}`` or ``None``.
    """
    runs = json.loads(run(["api", "repos/%s/actions/workflows/%s/runs?branch=master&status=success"
                                  "&per_page=5" % (repo, WORKFLOW)]) or "{}")
    for item in runs.get("workflow_runs") or []:
        listing = json.loads(run(["api", "repos/%s/actions/runs/%s/artifacts" % (repo, item["id"])]) or "{}")
        for art in listing.get("artifacts") or []:
            parsed = parse_artifact(art.get("name", ""))
            if parsed:
                return dict(parsed, name=art["name"], run_id=item["id"], expired=bool(art.get("expired")))
    return None


def release_version_of(msix: str) -> Optional[str]:
    """The ``YYMM.DD.NN`` release version of MSIX version ``msix`` (``None`` for other schemes)."""
    match = MSIX_VERSION_RE.match(msix or "")
    if not match:
        return None
    day, nn = divmod(int(match.group(2)), 100)
    return "%s.%02d.%02d" % (match.group(1), day, nn) if 1 <= day <= 31 and nn >= 1 else None


def find_artifact(run: Runner, repo: str, build: str, pages: int = 10) -> Optional[Dict[str, Any]]:
    """The newest artifact for ``build``: an MSIX version, or a ``YYMM.DD.NN`` release version (the release train
    submits the newest version that passed full CI, which can be days and dozens of builds old).

    Scans the repository's artifact list newest first (100 per page, ``pages`` pages): the 20 newest build runs were
    not enough on 2026-10-15, when a day of cherry-picked Windows fixes produced 20 builds before Thursday's lookup.

    Returns:
        ``{version, sha, placeholder, name, run_id, expired}`` or ``None``.
    """
    for page in range(1, pages + 1):
        listing = json.loads(run(["api", "repos/%s/actions/artifacts?per_page=100&page=%d" % (repo, page)]) or "{}")
        arts = listing.get("artifacts") or []
        for art in arts:
            parsed = parse_artifact(art.get("name", ""))
            if parsed and build in (parsed["version"], release_version_of(parsed["version"])):
                run_id = (art.get("workflow_run") or {}).get("id")
                return dict(parsed, name=art["name"], run_id=run_id, expired=bool(art.get("expired")))
        if len(arts) < 100:
            break
    return None


def artifact_sha(run: Runner, repo: str, version: str) -> Optional[str]:
    """Find the git SHA of a built package version from artifact names (ledger fallback)."""
    listing = json.loads(run(["api", "repos/%s/actions/artifacts?per_page=100&name=" % repo]) or "{}")
    for art in listing.get("artifacts") or []:
        parsed = parse_artifact(art.get("name", ""))
        if parsed and parsed["version"] == version and not parsed["placeholder"]:
            return parsed["sha"]
    return None


def download_package(run: Runner, repo: str, artifact: Dict[str, Any], dest: Path) -> Path:
    """Download the artifact and return its ``.msixupload``/``.msix``."""
    run(["run", "download", str(artifact["run_id"]), "-n", artifact["name"], "-R", repo, "-D", str(dest)])
    packages = sorted(dest.rglob("*.msixupload")) or sorted(dest.rglob("*.msix"))
    if not packages:
        raise RuntimeError("artifact %s has no MSIX package" % artifact["name"])
    return packages[0]


def artifact_store_notes(dest: Path) -> Optional[str]:
    """The release notes the build generated (``build.json`` ``store_notes``).

    Returns ``None`` when no marker carries the key (older builds), else its text, which is empty when the
    build has nothing user-facing.
    """
    for marker in sorted(dest.rglob("build.json")):
        try:
            doc = json.loads(marker.read_text(encoding="utf-8-sig"))
        except (OSError, ValueError):
            continue
        if isinstance(doc, dict) and "store_notes" in doc:
            return str(doc.get("store_notes") or "").strip()[:RELEASE_NOTES_LIMIT]
    return None


# endregion

# region Submission state


def is_own_submission(body: Dict[str, Any]) -> bool:
    """True when this tool created the submission (its certification notes carry ``OWN_MARKER``).

    Stateless on purpose: jobs run on ephemeral Actions runners, so nothing local remembers ids.
    """
    return str(body.get("notesForCertification") or "").startswith(OWN_MARKER)


def package_version(submission: Dict[str, Any]) -> Optional[str]:
    """Return the version of the submission's active package (``None`` when unknown)."""
    for package in submission.get("applicationPackages") or []:
        if package.get("fileStatus") not in ("PendingDelete",) and package.get("version"):
            return str(package["version"])
    return None


def application(client: StoreClient) -> Dict[str, Any]:
    """GET the application resource (pending/last published submission references)."""
    return client.get("/applications/%s" % urllib.parse.quote(client.creds.app_id, safe=""))


def submission(client: StoreClient, ref: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """Resolve a ``{id}`` submission reference."""
    if not ref or not ref.get("id"):
        return None
    return client.get("/applications/%s/submissions/%s" % (client.creds.app_id, ref["id"]))


# endregion

# region Commands


def blocked_status(reason: str) -> Dict[str, Any]:
    """Return the release-orchestrator status shape for a blocked run."""
    return fst_release.blocked_status(reason)


def collect_status(client: StoreClient, run: Runner, repo: str,
                   ledger: Dict[str, Any]) -> Dict[str, Any]:
    """Build ``{in_review, state, version, publish_mode, latest_build, released_sha, blocked}``.

    ``state`` is the pending submission's status, else ``Published`` for the live one. ``publish_mode`` is that
    submission's ``targetPublishMode`` (``Manual`` keeps a certified build from going live by itself; a
    hand-made first submission should use it too).
    ``latest_build.build`` is the MSIX version (the Store's build identity).
    """
    app = application(client)
    if not app.get("lastPublishedApplicationSubmission") and not app.get("pendingApplicationSubmission"):
        raise Blocked("first_submission_required")
    pending = submission(client, app.get("pendingApplicationSubmission"))
    published = submission(client, app.get("lastPublishedApplicationSubmission"))
    current = pending or published
    state = str(current.get("status") or "") if current else None
    if pending is None and published is not None:
        state = "Published"

    latest = None
    artifact = latest_artifact(run, repo)
    if artifact:
        valid = not artifact["placeholder"] and not artifact["expired"]
        latest = {"version": artifact["version"], "build": artifact["version"], "sha": artifact["sha"],
                  "processing_state": "VALID" if valid else
                  ("PLACEHOLDER_IDENTITY" if artifact["placeholder"] else "EXPIRED")}

    released_sha = None
    released_version = package_version(published) if published else None
    if released_version:
        released_sha = (fst_release.ledger_sha(ledger, LEDGER_PLATFORM, released_version)
                        or artifact_sha(run, repo, released_version))

    return {"in_review": bool(pending) and state in IN_REVIEW_STATUSES, "state": state,
            "version": package_version(current) if current else None,
            "publish_mode": current.get("targetPublishMode") if current else None,
            "latest_build": latest, "released_sha": released_sha, "blocked": None}


def _clear_pending(client: StoreClient, app: Dict[str, Any], replace: bool = False,
                   build: str = "") -> Optional[str]:
    """Delete a failed or self-created draft; refuse anything else.

    With ``replace`` (the release train's weekly submission) a submission in certification or waiting to publish
    is deleted too, unless it already carries ``build``. The submission API has no "cancel certification", so
    the Store may refuse the delete.

    Returns:
        ``"refused:<status>"`` when certification/publishing owns it (``refused:already_submitted`` for the same
        build), ``"replaced:<status>:<version>"`` after deleting one, else ``None``.

    Raises:
        Blocked: A draft someone else is editing in Partner Center, or the Store refused to delete a
            submission in certification (``cannot_cancel_<status>``).
    """
    pending = submission(client, app.get("pendingApplicationSubmission"))
    if pending is None:
        return None
    status = str(pending.get("status") or "")
    if status in IN_REVIEW_STATUSES:
        version = package_version(pending) or ""
        if not replace:
            return "refused:" + status
        if build and build in (version, release_version_of(version)):
            return "refused:already_submitted"
        try:
            client.request("DELETE", "/applications/%s/submissions/%s" % (client.creds.app_id, pending["id"]))
        except StoreError as err:
            raise Blocked("cannot_cancel_%s" % status) from err
        return "replaced:%s:%s" % (status, version)
    if status not in FAILED_STATUSES and not is_own_submission(pending) and not _abandoned_clone(client, app, pending):
        raise Blocked("foreign_pending_submission")
    client.request("DELETE", "/applications/%s/submissions/%s" % (client.creds.app_id, pending["id"]))
    return None


def _abandoned_clone(client: StoreClient, app: Dict[str, Any], pending: Dict[str, Any]) -> bool:
    """Whether a pending draft is an unchanged clone of the published submission (a ``submit`` that failed between
    creating the clone and writing it, e.g. Store HTTP 500 on the PUT, 2026-10-15). Deleting it loses nothing."""
    if str(pending.get("status") or "") != "PendingCommit":
        return False
    published = submission(client, app.get("lastPublishedApplicationSubmission"))
    if published is None:
        return False
    return (package_version(pending) == package_version(published)
            and pending.get("notesForCertification") == published.get("notesForCertification"))


def prepare_submission(body: Dict[str, Any], file_name: str, notes: str, sha: str,
                       publish_at: Optional[str] = None) -> Dict[str, Any]:
    """Swap in the new package and release notes on a cloned submission and hold publication (Manual), or
    schedule it for ``publish_at`` (``SpecificDate``: published then if certified, else once certified)."""
    packages = []
    for package in body.get("applicationPackages") or []:
        packages.append(dict(package, fileStatus="PendingDelete"))
    packages.append({"fileName": file_name, "fileStatus": "PendingUpload",
                     "minimumDirectXVersion": "None", "minimumSystemRam": "None"})
    body["applicationPackages"] = packages
    body["targetPublishMode"] = SCHEDULED_MODE if publish_at else PUBLISH_MODE
    body.pop("targetPublishDate", None)
    if publish_at:
        body["targetPublishDate"] = publish_at
    body["notesForCertification"] = "%s automated build of commit %s. No sign-in required; the app reads " \
        "public leaderboard data." % (OWN_MARKER, sha[:12])
    for listing in (body.get("listings") or {}).values():
        base = listing.setdefault("baseListing", {})
        base["releaseNotes"] = notes
    return body


def package_zip(package: Path) -> bytes:
    """Zip the package at the archive root (the Store matches it by ``fileName``)."""
    with tempfile.TemporaryFile() as handle:
        with zipfile.ZipFile(handle, "w", zipfile.ZIP_STORED) as archive:
            archive.write(str(package), package.name)
        handle.seek(0)
        return handle.read()


def submit(client: StoreClient, run: Runner, repo: str, env: Dict[str, str], build: str,
           notes: str, replace: bool = False, publish_at: Optional[str] = None) -> Dict[str, Any]:
    """Create, fill, upload and commit a new submission for ``build`` (MSIX or ``YYMM.DD.NN`` version).

    Args:
        replace: Delete a submission still in certification or waiting to publish first (see
            :func:`_clear_pending`); ``replaced`` in the result names it.
        publish_at: ``YYYY-MM-DDTHH:MM:SSZ``: publish then if certified (``SpecificDate``) instead of holding
            for a manual publish.

    Returns:
        ``{submitted, submission_id, version, build, sha, publish_mode}`` or ``{refused: ...}``.

    Raises:
        Blocked: First submission not done, foreign draft, or the build is not submittable.
    """
    notes = (notes or "").strip()[:RELEASE_NOTES_LIMIT]
    if publish_at and not PUBLISH_AT_RE.match(publish_at):
        raise ValueError("publish_at must be YYYY-MM-DDTHH:MM:SSZ")
    app = application(client)
    if not app.get("lastPublishedApplicationSubmission") and not app.get("pendingApplicationSubmission"):
        raise Blocked("first_submission_required")
    artifact = find_artifact(run, repo, build)
    if not artifact:
        raise Blocked("build_artifact_not_found")
    if artifact["placeholder"]:
        raise Blocked("placeholder_store_identity")
    if artifact["expired"]:
        raise Blocked("artifact_expired")
    build = artifact["version"]
    cleared = _clear_pending(client, app, replace, build)
    if cleared and cleared.startswith("refused:"):
        return {"refused": cleared.split(":", 1)[1], "build": build}
    replaced = None
    if cleared:
        _, status, version = cleared.split(":", 2)
        replaced = {"state": status, "version": version}

    with tempfile.TemporaryDirectory(prefix="fst-msix-") as tmp:
        if client.dry_run:
            file_name = "FestivalScoreTracker_%s_x64.msixupload" % build
            data = b""
        else:
            package = download_package(run, repo, artifact, Path(tmp))
            file_name = package.name
            data = package_zip(package)
            generated = artifact_store_notes(Path(tmp))
            notes = notes if generated is None else generated
        if not notes:
            return {"submitted": False, "refused": "no_user_facing_changes", "build": build}
        fallback = None
        created = client.request("POST", "/applications/%s/submissions" % client.creds.app_id)
        submission_id = str(created.get("id") or "<new>")
        path = "/applications/%s/submissions/%s" % (client.creds.app_id, submission_id)
        try:
            upload_url = str(created.pop("fileUploadUrl", "") or "")
            if not client.dry_run and not upload_url:
                raise StoreError(0, "new submission has no fileUploadUrl")
            body = prepare_submission(created, file_name, notes, artifact["sha"], publish_at)
            try:
                client.request("PUT", path, body)
            except StoreError as err:
                if not publish_at or err.status < 500:
                    raise
                # The Store answered HTTP 500 to every SpecificDate PUT (2026-10-15/16) while Manual ones worked:
                # hold for a manual publish instead (Monday's check then reports manual_publish_required).
                body["targetPublishMode"] = PUBLISH_MODE
                body.pop("targetPublishDate", None)
                client.request("PUT", path, body)
                fallback = "SpecificDate rejected (HTTP %s); held for manual publish" % err.status
                publish_at = None
            client.upload(upload_url, data)
        except (StoreError, OSError, RuntimeError):
            # Don't leave an unmarked draft behind: it would block every later submission as someone else's.
            try:
                client.request("DELETE", path)
            except StoreError:
                pass
            raise
        client.request("POST", path + "/commit")

    if not client.dry_run:
        fst_release.record_build(fst_release.ledger_path(env), LEDGER_PLATFORM, build, build, artifact["sha"])
    result = {"submitted": not client.dry_run, "submission_id": submission_id, "version": build, "build": build,
              "sha": artifact["sha"], "publish_mode": SCHEDULED_MODE if publish_at else PUBLISH_MODE}
    if publish_at:
        result["publish_at"] = publish_at
    if fallback:
        result["publish_fallback"] = fallback
    if replaced:
        result["replaced"] = replaced
    return result


# region Package flights (the Windows TestFlight)


#: Flight submission statuses that mean the Store owns the submission (certification or publishing): wait for it.
FLIGHT_BUSY_STATUSES = frozenset({"CommitStarted", "PreProcessing", "Certification", "Publishing", "Release"})
FLIGHT_MODE = "Immediate"


def list_flights(client: StoreClient) -> List[Dict[str, Any]]:
    """The app's package flights (``flightId``, ``friendlyName``, ``groupIds``, submission references)."""
    data = client.get("/applications/%s/listflights?top=100" % client.creds.app_id)
    return list((data or {}).get("value") or [])


def ensure_flight(client: StoreClient, name: str, group: str) -> Dict[str, Any]:
    """Return the package flight called ``name``, creating it for known user group ``group`` when missing.

    Raises:
        Blocked: The flight doesn't exist and no group id was given (``flight_group_id_required``).
    """
    for flight in list_flights(client):
        if str(flight.get("friendlyName") or "") == name:
            return flight
    if not group or not group.isdigit():
        raise Blocked("flight_group_id_required")
    created = client.request("POST", "/applications/%s/flights" % client.creds.app_id,
                             {"friendlyName": name, "groupIds": [group]})
    return created or {"flightId": "<new>", "friendlyName": name, "groupIds": [group]}


def flight_submission(client: StoreClient, flight: Dict[str, Any], key: str) -> Optional[Dict[str, Any]]:
    """Resolve a flight's ``pendingFlightSubmission`` / ``lastPublishedFlightSubmission`` reference."""
    ref = flight.get(key) or {}
    if not ref.get("id"):
        return None
    return client.get("/applications/%s/flights/%s/submissions/%s" % (
        client.creds.app_id, flight["flightId"], ref["id"]))


def flight_package_version(sub: Optional[Dict[str, Any]]) -> Optional[str]:
    """Version of a flight submission's active package (``None`` when unknown)."""
    for package in (sub or {}).get("flightPackages") or []:
        if package.get("fileStatus") != "PendingDelete" and package.get("version"):
            return str(package["version"])
    return None


def _msix_key(version: Optional[str]) -> tuple:
    try:
        return tuple(int(p) for p in str(version or "").split("."))
    except ValueError:
        return ()


def flight_status(client: StoreClient, name: str, group: str) -> Dict[str, Any]:
    """``{flight_id, name, pending: {status, version}, published_version}`` for the flight (created if missing)."""
    flight = ensure_flight(client, name, group)
    pending = flight_submission(client, flight, "pendingFlightSubmission")
    published = flight_submission(client, flight, "lastPublishedFlightSubmission")
    return {"flight_id": flight.get("flightId"), "name": name,
            "pending": {"id": pending.get("id"), "status": pending.get("status"),
                        "version": flight_package_version(pending), "own": is_own_submission(pending),
                        "has_upload_url": bool(pending.get("fileUploadUrl"))}
            if pending else None,
            "published_version": flight_package_version(published)}


def flight_submit(client: StoreClient, run: Runner, repo: str, env: Dict[str, str], name: str, group: str,
                  build: Optional[str] = None) -> Dict[str, Any]:
    """Submit the newest Windows release build (or ``build``) to package flight ``name``: the Windows TestFlight.

    The flight publishes to its known user group as soon as certification passes (``Immediate``). Only one flight
    submission can be pending: while one is in certification this refuses with ``flight_busy`` and the next run
    (hourly, and after each build) submits whatever is newest then. A failed or self-created draft is deleted first.

    Returns:
        ``{submitted, flight_id, submission_id, version, sha}`` or ``{refused: flight_busy|up_to_date|no_build}``.
    """
    flight = ensure_flight(client, name, group)
    artifact = find_artifact(run, repo, build) if build else latest_artifact(run, repo)
    if not artifact or artifact["placeholder"] or artifact["expired"]:
        return {"refused": "no_build", "flight_id": flight.get("flightId")}
    version = artifact["version"]
    pending = flight_submission(client, flight, "pendingFlightSubmission")
    published = flight_submission(client, flight, "lastPublishedFlightSubmission")
    draft: Optional[Dict[str, Any]] = None
    if pending is not None:
        status = str(pending.get("status") or "")
        if status in FLIGHT_BUSY_STATUSES or status == "PendingPublication":
            return {"refused": "flight_busy", "state": status, "pending_version": flight_package_version(pending),
                    "version": version, "flight_id": flight.get("flightId")}
        if status == "PendingCommit" and not flight_package_version(pending) and pending.get("fileUploadUrl"):
            draft = pending  # a new flight's empty draft (Partner Center and the API create one): fill it in
        elif status not in FAILED_STATUSES and not is_own_submission(pending) and not (
                status == "PendingCommit" and not flight_package_version(pending)):
            raise Blocked("foreign_pending_flight_submission: %s %s, packages %s" % (
                pending.get("id"), status, flight_package_version(pending) or "none"))
        else:
            client.request("DELETE", "/applications/%s/flights/%s/submissions/%s" % (
                client.creds.app_id, flight["flightId"], pending["id"]))
    if _msix_key(flight_package_version(published)) >= _msix_key(version):
        return {"refused": "up_to_date", "version": version, "flight_id": flight.get("flightId")}

    path = "/applications/%s/flights/%s/submissions" % (client.creds.app_id, flight["flightId"])
    with tempfile.TemporaryDirectory(prefix="fst-flight-") as tmp:
        if client.dry_run:
            file_name = "FestivalScoreTracker_%s_x64.msixupload" % version
            data = b""
        else:
            package = download_package(run, repo, artifact, Path(tmp))
            file_name, data = package.name, package_zip(package)
        created = dict(draft) if draft is not None else (client.request("POST", path) or {})
        submission_id = str(created.get("id") or "<new>")
        upload_url = str(created.pop("fileUploadUrl", "") or "")
        if not client.dry_run and not upload_url:
            raise StoreError(0, "new flight submission has no fileUploadUrl")
        packages = [dict(p, fileStatus="PendingDelete") for p in created.get("flightPackages") or []]
        packages.append({"fileName": file_name, "fileStatus": "PendingUpload",
                         "minimumDirectXVersion": "None", "minimumSystemRam": "None"})
        created.update(flightPackages=packages, targetPublishMode=FLIGHT_MODE,
                       notesForCertification="%s automated release-candidate build of commit %s for the %s flight. "
                       "No sign-in required; the app reads public leaderboard data." % (
                           OWN_MARKER, artifact["sha"][:12], name))
        created.pop("targetPublishDate", None)
        client.request("PUT", "%s/%s" % (path, submission_id), created)
        client.upload(upload_url, data)
        client.request("POST", "%s/%s/commit" % (path, submission_id))
    return {"submitted": not client.dry_run, "flight_id": flight.get("flightId"), "submission_id": submission_id,
            "version": version, "sha": artifact["sha"], "replaced_draft": pending is not None and draft is None,
            "filled_draft": draft is not None}


# endregion


def release_state(client: StoreClient) -> Dict[str, Any]:
    """Report whether the newest submission reached customers (the release train's Monday check).

    The submission API cannot "Publish now": a certified ``Manual`` submission waits for Partner Center
    (``blocked: manual_publish_required``), while a ``SpecificDate`` one publishes itself at ``scheduled``.

    Returns:
        ``{released, state, version, publish_mode, scheduled}`` (``blocked`` set when a person must act).
    """
    app = application(client)
    pending = submission(client, app.get("pendingApplicationSubmission"))
    published = submission(client, app.get("lastPublishedApplicationSubmission"))
    if pending is None:
        return {"released": published is not None, "state": "Published" if published else None,
                "version": package_version(published) if published else None}
    status = str(pending.get("status") or "")
    doc = {"released": False, "state": status, "version": package_version(pending),
           "publish_mode": pending.get("targetPublishMode"), "scheduled": pending.get("targetPublishDate")}
    if status == "PendingPublication" and pending.get("targetPublishMode") == PUBLISH_MODE:
        doc["blocked"] = "manual_publish_required"
    return doc


# endregion

# region CLI


def build_parser() -> argparse.ArgumentParser:
    """Create the command-line parser (``fst_release.py windows`` passes its remaining args)."""
    parser = argparse.ArgumentParser(prog="fst_store.py", description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("status")
    p.add_argument("--json", action="store_true")
    p = sub.add_parser("submit")
    p.add_argument("--build", required=True)
    notes = p.add_mutually_exclusive_group(required=True)
    notes.add_argument("--notes-file")
    notes.add_argument("--notes-stdin", action="store_true")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--replace", action="store_true",
                   help="delete a submission still in certification or waiting to publish, then submit")
    p.add_argument("--publish-at", help="publish at this UTC time (YYYY-MM-DDTHH:MM:SSZ) once certified")
    p = sub.add_parser("build-for-version")
    p.add_argument("--version", required=True)
    p = sub.add_parser("release")
    p.add_argument("--version")
    p.add_argument("--dry-run", action="store_true")
    for name in ("flight-status", "flight-submit"):
        p = sub.add_parser(name)
        p.add_argument("--flight", default="Testers", help="package flight name (created when missing)")
        p.add_argument("--group", default="", help="known user group id, used to create the flight")
        if name == "flight-submit":
            p.add_argument("--build", help="MSIX or YYMM.DD.NN version (default: the newest release build)")
            p.add_argument("--dry-run", action="store_true")
    p = sub.add_parser("record-build")
    p.add_argument("--build", required=True)
    p.add_argument("--version", required=True)
    p.add_argument("--sha", required=True)
    return parser


def main(argv: Optional[List[str]] = None, env: Optional[Dict[str, str]] = None,
         transport: Transport = fst_release.urllib_transport, runner: Runner = gh_runner,
         stdin: Any = None) -> int:
    """Run the CLI.

    Args:
        argv: Arguments (defaults to ``sys.argv[1:]``).
        env: Environment mapping (defaults to ``os.environ``).
        transport: HTTP transport (injectable for tests).
        runner: ``gh`` runner (injectable for tests).
        stdin: Text stream for ``--notes-stdin``.

    Returns:
        The process exit code.
    """
    args = build_parser().parse_args(argv)
    env = dict(os.environ) if env is None else env
    repo = env.get("FST_NATIVE_REPO") or DEFAULT_REPO
    emit = fst_release.emit

    if args.command == "record-build":
        fst_release.record_build(fst_release.ledger_path(env), LEDGER_PLATFORM, args.build, args.version,
                                 args.sha)
        emit({"recorded": True, "build": args.build, "version": args.version, "sha": args.sha})
        return EXIT_OK

    creds = load_credentials(env)
    if creds is None:
        emit(blocked_status("missing_store_credentials") if args.command == "status"
             else {"blocked": "missing_store_credentials"})
        return EXIT_BLOCKED

    dry_run = bool(getattr(args, "dry_run", False))
    client = StoreClient(creds, transport=transport, dry_run=dry_run)
    try:
        if args.command == "status":
            emit(collect_status(client, runner, repo, fst_release.read_ledger(fst_release.ledger_path(env))))
            return EXIT_OK
        if args.command == "submit":
            notes = (stdin or sys.stdin).read() if args.notes_stdin else Path(args.notes_file).read_text(encoding="utf-8")
            result = submit(client, runner, repo, env, args.build, notes, replace=args.replace,
                            publish_at=args.publish_at)
            if dry_run:
                result["planned"] = client.planned
            emit(result)
            return EXIT_REFUSED if result.get("refused") else EXIT_OK
        if args.command == "build-for-version":
            artifact = find_artifact(runner, repo, args.version)
            ok = bool(artifact and not artifact["placeholder"] and not artifact["expired"])
            emit({"version": args.version, "build": artifact["version"] if ok else None, "found": ok})
            return EXIT_OK if ok else EXIT_REFUSED
        if args.command == "release":
            result = release_state(client)
            emit(result)
            return EXIT_BLOCKED if result.get("blocked") else EXIT_OK
        if args.command == "flight-status":
            emit(flight_status(client, args.flight, args.group))
            return EXIT_OK
        if args.command == "flight-submit":
            result = flight_submit(client, runner, repo, env, args.flight, args.group, args.build)
            if dry_run:
                result["planned"] = client.planned
            emit(result)
            return EXIT_REFUSED if result.get("refused") else EXIT_OK
    except Blocked as err:
        emit(blocked_status(err.reason) if args.command == "status" else {"blocked": err.reason})
        return EXIT_BLOCKED
    except StoreError as err:
        if args.command == "status":
            document = blocked_status("store_error")
            document["error"] = str(err)
            emit(document)
            return EXIT_STORE_ERROR
        emit({"error": str(err)})
        return EXIT_FAIL
    except (ValueError, OSError, RuntimeError, fst_release.AscError) as err:
        if args.command == "status":
            document = blocked_status("store_error")
            document["error"] = str(err)[:300]
            emit(document)
            return EXIT_STORE_ERROR
        emit({"error": str(err)[:300]})
        return EXIT_FAIL
    return EXIT_FAIL


# endregion

if __name__ == "__main__":
    sys.exit(main())
