"""Unit tests for ``tools/release/fst_store.py`` (no network; fake transport and ``gh`` runner)."""

import io
import json
import tempfile
import unittest
import zipfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from tools.release import fst_release as fr
from tools.release import fst_store as fs

APP = "9NTESTAPP01"
SHA_NEW = "b" * 40
SHA_OLD = "a" * 40
API = "/v1.0/my/applications/" + APP


class FakeStore:
    """Routes Store/Entra requests to canned JSON by (method, path) and records them."""

    def __init__(self, routes=None):
        self.routes = dict(routes or {})
        self.calls = []

    def __call__(self, method, url, headers, body):
        parsed = urlparse(url)
        if parsed.netloc == "login.microsoftonline.com":
            form = {k: v[0] for k, v in parse_qs(body.decode()).items()}
            self.calls.append((method, parsed.path, form, headers))
            return 200, {"access_token": "tok-123"}
        if parsed.netloc == "blob.example":
            self.calls.append((method, "<blob>", body, headers))
            return 201, None
        payload = json.loads(body) if body else None
        self.calls.append((method, parsed.path, payload, headers))
        reply = self.routes.get((method, parsed.path))
        if callable(reply):
            reply = reply(payload)
        if reply is None:
            return 404, {"code": "NotFound", "message": "no route %s %s" % (method, parsed.path)}
        if isinstance(reply, tuple):
            return reply
        return 200, reply

    def writes(self):
        return [(m, p) for m, p, _b, _h in self.calls if m != "GET" and not p.endswith("/oauth2/token")]


class FakeGh:
    """Answers the ``gh api`` / ``gh run download`` calls fst_store makes."""

    def __init__(self, artifact="fst-windows-msix_0.1.912.0_%s" % SHA_NEW, expired=False,
                 history=("fst-windows-msix_0.1.900.0_%s" % SHA_OLD,), package_ext=".msixupload",
                 build_json="{}"):
        self.artifact = artifact
        self.build_json = build_json
        self.expired = expired
        self.history = history
        self.package_ext = package_ext
        self.calls = []

    def __call__(self, args):
        self.calls.append(args)
        if args[0] == "api" and "/workflows/" in args[1]:
            return json.dumps({"workflow_runs": [{"id": 77}]})
        if args[0] == "api" and args[1].endswith("/runs/77/artifacts"):
            arts = [{"name": self.artifact, "expired": self.expired}] if self.artifact else []
            return json.dumps({"artifacts": arts})
        if args[0] == "api" and "/actions/artifacts" in args[1]:
            return json.dumps({"artifacts": [{"name": n} for n in self.history]})
        if args[0] == "run" and args[1] == "download":
            dest = Path(args[args.index("-D") + 1])
            dest.mkdir(parents=True, exist_ok=True)
            version = fs.parse_artifact(args[args.index("-n") + 1])["version"]
            (dest / ("FestivalScoreTracker_%s_x64%s" % (version, self.package_ext))).write_bytes(b"MSIX")
            (dest / "build.json").write_text(self.build_json)
            return ""
        raise AssertionError("unexpected gh call %r" % (args,))


def submission(sid, status, version=None):
    packages = [{"fileName": "old.msixupload", "fileStatus": "Uploaded", "version": version}] if version else []
    return {"id": sid, "status": status, "applicationPackages": packages,
            "listings": {"en-us": {"baseListing": {"description": "d", "releaseNotes": "old"}}},
            "targetPublishMode": "Immediate"}


def store_routes(pending=None, published=submission("100", "Published", "0.1.900.0")):
    app = {"id": APP}
    routes = {}
    if published:
        app["lastPublishedApplicationSubmission"] = {"id": published["id"]}
        routes[("GET", API + "/submissions/" + published["id"])] = published
    if pending:
        app["pendingApplicationSubmission"] = {"id": pending["id"]}
        routes[("GET", API + "/submissions/" + pending["id"])] = pending
        routes[("DELETE", API + "/submissions/" + pending["id"])] = (204, None)
    routes[("GET", API)] = app
    return routes


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        home = Path(self.tmp.name)
        self.env = {"HOME": str(home), "MSSTORE_TENANT_ID": "tenant", "MSSTORE_CLIENT_ID": "client",
                    "MSSTORE_CLIENT_SECRET": "s3cret-value", "MSSTORE_SELLER_ID": "seller",
                    "MSSTORE_APP_ID": APP, "FST_RELEASE_LEDGER": str(home / "state" / "builds.json")}

    def run_cli(self, argv, transport, runner, stdin=None, env=None):
        out = io.StringIO()
        with redirect_stdout(out):
            code = fs.main(argv, env=env or self.env, transport=transport, runner=runner,
                           stdin=io.StringIO(stdin or ""))
        text = out.getvalue()
        self.assertNotIn("s3cret-value", text)
        self.assertNotIn("tok-123", text)
        self.assertNotIn("sig=", text)
        return code, json.loads(text)


class CredentialTests(Base):
    def test_missing_credentials_block_every_command(self):
        env = {"HOME": self.env["HOME"]}
        code, doc = self.run_cli(["status", "--json"], FakeStore(), FakeGh(), env=env)
        self.assertEqual((code, doc["blocked"], doc["in_review"]), (4, "missing_store_credentials", False))
        code, doc = self.run_cli(["submit", "--build", "1", "--notes-stdin"], FakeStore(), FakeGh(), env=env)
        self.assertEqual((code, doc), (4, {"blocked": "missing_store_credentials"}))

    def test_credentials_file_fallback(self):
        path = Path(self.env["HOME"]) / ".config" / "fst-release" / "msstore.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"tenant_id": "t", "client_id": "c", "client_secret": "x",
                                    "seller_id": "s", "app_id": APP}))
        creds = fs.load_credentials({"HOME": self.env["HOME"], "MSSTORE_APP_ID": "override"})
        self.assertEqual((creds.tenant_id, creds.app_id), ("t", "override"))
        self.assertNotIn("client_secret", repr(creds))


class StatusTests(Base):
    def test_published_with_new_valid_build(self):
        store = FakeStore(store_routes())
        code, doc = self.run_cli(["status", "--json"], store, FakeGh())
        self.assertEqual(code, 0)
        self.assertEqual(doc["state"], "Published")
        self.assertFalse(doc["in_review"])
        self.assertEqual(doc["version"], "0.1.900.0")
        self.assertEqual(doc["released_sha"], SHA_OLD)
        self.assertEqual(doc["latest_build"], {"version": "0.1.912.0", "build": "0.1.912.0", "sha": SHA_NEW,
                                               "processing_state": "VALID"})
        token_call = store.calls[0]
        self.assertEqual(token_call[2]["grant_type"], "client_credentials")
        self.assertEqual(token_call[2]["resource"], "https://manage.devcenter.microsoft.com")
        self.assertEqual(store.calls[1][3]["Authorization"], "Bearer tok-123")

    def test_ledger_sha_preferred_over_artifact_history(self):
        fr.record_build(Path(self.env["FST_RELEASE_LEDGER"]), "WINDOWS", "0.1.900.0", "0.1.900.0", "c" * 40)
        _, doc = self.run_cli(["status", "--json"], FakeStore(store_routes()), FakeGh(history=()))
        self.assertEqual(doc["released_sha"], "c" * 40)

    def test_certification_and_pending_publication_are_in_review(self):
        for status in ("CommitStarted", "PreProcessing", "Certification", "PendingPublication", "Publishing"):
            routes = store_routes(pending=submission("200", status, "0.1.905.0"))
            _, doc = self.run_cli(["status", "--json"], FakeStore(routes), FakeGh())
            self.assertTrue(doc["in_review"], status)
            self.assertEqual((doc["state"], doc["version"]), (status, "0.1.905.0"))

    def test_failed_or_draft_pending_is_not_in_review(self):
        for status in ("CertificationFailed", "PendingCommit"):
            _, doc = self.run_cli(["status", "--json"], FakeStore(store_routes(pending=submission("200", status))),
                                  FakeGh())
            self.assertFalse(doc["in_review"], status)
            self.assertEqual(doc["state"], status)

    def test_placeholder_and_expired_builds_are_not_valid(self):
        gh = FakeGh(artifact="fst-windows-msix_0.1.912.0_%s_placeholder" % SHA_NEW)
        _, doc = self.run_cli(["status", "--json"], FakeStore(store_routes()), gh)
        self.assertEqual(doc["latest_build"]["processing_state"], "PLACEHOLDER_IDENTITY")
        _, doc = self.run_cli(["status", "--json"], FakeStore(store_routes()), FakeGh(expired=True))
        self.assertEqual(doc["latest_build"]["processing_state"], "EXPIRED")

    def test_first_submission_must_be_manual(self):
        code, doc = self.run_cli(["status", "--json"], FakeStore(store_routes(published=None)), FakeGh())
        self.assertEqual((code, doc["blocked"]), (4, "first_submission_required"))

    def test_api_error_maps_to_store_error(self):
        store = FakeStore({("GET", API): (401, {"code": "Unauthorized", "message": "nope"})})
        code, doc = self.run_cli(["status", "--json"], store, FakeGh())
        self.assertEqual((code, doc["blocked"]), (5, "store_error"))
        self.assertIn("nope", doc["error"])


class SubmitTests(Base):
    def submit_routes(self, **kwargs):
        routes = store_routes(**kwargs)
        clone = submission("300", "PendingCommit", "0.1.900.0")
        clone["fileUploadUrl"] = "https://blob.example/upload?sig=SECRET"
        clone["targetPublishDate"] = "2026-01-01T00:00:00Z"
        routes[("POST", API + "/submissions")] = clone
        routes[("PUT", API + "/submissions/300")] = lambda body: body
        routes[("POST", API + "/submissions/300/commit")] = {"status": "CommitStarted"}
        return routes

    def test_submit_replaces_package_notes_and_holds_publication(self):
        store = FakeStore(self.submit_routes())
        code, doc = self.run_cli(["submit", "--build", "0.1.912.0", "--notes-stdin"], store, FakeGh(),
                                 stdin="Fixed the Songs filter.\n")
        self.assertEqual(code, 0)
        self.assertEqual(doc, {"submitted": True, "submission_id": "300", "version": "0.1.912.0",
                               "build": "0.1.912.0", "sha": SHA_NEW, "publish_mode": "Manual"})
        self.assertEqual(store.writes(), [("POST", API + "/submissions"), ("PUT", API + "/submissions/300"),
                                          ("PUT", "<blob>"), ("POST", API + "/submissions/300/commit")])
        put = next(c for c in store.calls if c[:2] == ("PUT", API + "/submissions/300"))[2]
        self.assertEqual(put["targetPublishMode"], "Manual")
        self.assertNotIn("targetPublishDate", put)
        self.assertNotIn("fileUploadUrl", put)
        self.assertEqual(put["listings"]["en-us"]["baseListing"]["releaseNotes"], "Fixed the Songs filter.")
        self.assertEqual([(p["fileName"], p["fileStatus"]) for p in put["applicationPackages"]],
                         [("old.msixupload", "PendingDelete"),
                          ("FestivalScoreTracker_0.1.912.0_x64.msixupload", "PendingUpload")])
        blob = next(c for c in store.calls if c[1] == "<blob>")
        self.assertEqual(blob[3]["x-ms-blob-type"], "BlockBlob")
        with zipfile.ZipFile(io.BytesIO(blob[2])) as archive:
            self.assertEqual(archive.namelist(), ["FestivalScoreTracker_0.1.912.0_x64.msixupload"])
        ledger = fr.read_ledger(Path(self.env["FST_RELEASE_LEDGER"]))
        self.assertEqual(ledger["WINDOWS"]["0.1.912.0"]["sha"], SHA_NEW)
        self.assertTrue(fs.is_own_submission(put))
        self.assertIn(SHA_NEW[:12], put["notesForCertification"])

    def test_generated_artifact_notes_win(self):
        store = FakeStore(self.submit_routes())
        gh = FakeGh(build_json=json.dumps({"version": "0.1.912.0", "store_notes": "• Windows rows load faster."}))
        code, _ = self.run_cli(["submit", "--build", "0.1.912.0", "--notes-stdin"], store, gh,
                               stdin="Orchestrator notes")
        self.assertEqual(code, 0)
        put = next(c for c in store.calls if c[:2] == ("PUT", API + "/submissions/300"))[2]
        self.assertEqual(put["listings"]["en-us"]["baseListing"]["releaseNotes"], "• Windows rows load faster.")

    def test_default_notes_and_no_publish_mode_option(self):
        store = FakeStore(self.submit_routes())
        code, doc = self.run_cli(["submit", "--build", "0.1.912.0", "--notes-stdin"], store, FakeGh(), stdin="  ")
        self.assertEqual((code, doc["publish_mode"]), (0, "Manual"))
        put = next(c for c in store.calls if c[:2] == ("PUT", API + "/submissions/300"))[2]
        self.assertEqual(put["listings"]["en-us"]["baseListing"]["releaseNotes"], fr.DEFAULT_NOTES)
        with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
            fs.build_parser().parse_args(["submit", "--build", "1", "--notes-stdin", "--publish-mode", "immediate"])

    def test_refuses_while_in_certification(self):
        store = FakeStore(self.submit_routes(pending=submission("200", "Certification")))
        code, doc = self.run_cli(["submit", "--build", "0.1.912.0", "--notes-stdin"], store, FakeGh())
        self.assertEqual((code, doc["refused"]), (3, "Certification"))
        self.assertEqual(store.writes(), [])

    def test_deletes_failed_pending_then_submits(self):
        store = FakeStore(self.submit_routes(pending=submission("200", "CertificationFailed")))
        code, _ = self.run_cli(["submit", "--build", "0.1.912.0", "--notes-stdin"], store, FakeGh())
        self.assertEqual(code, 0)
        self.assertEqual(store.writes()[0], ("DELETE", API + "/submissions/200"))

    def test_foreign_draft_blocks_but_own_draft_is_replaced(self):
        store = FakeStore(self.submit_routes(pending=submission("200", "PendingCommit")))
        code, doc = self.run_cli(["submit", "--build", "0.1.912.0", "--notes-stdin"], store, FakeGh())
        self.assertEqual((code, doc), (4, {"blocked": "foreign_pending_submission"}))
        self.assertEqual(store.writes(), [])
        own = submission("200", "PendingCommit")
        own["notesForCertification"] = fs.OWN_MARKER + " automated build"
        store = FakeStore(self.submit_routes(pending=own))
        code, _ = self.run_cli(["submit", "--build", "0.1.912.0", "--notes-stdin"], store, FakeGh())
        self.assertEqual(code, 0)
        self.assertEqual(store.writes()[0], ("DELETE", API + "/submissions/200"))

    def test_blocks_placeholder_stale_or_expired_builds(self):
        cases = [(FakeGh(artifact="fst-windows-msix_0.1.912.0_%s_placeholder" % SHA_NEW),
                  "placeholder_store_identity"),
                 (FakeGh(artifact="fst-windows-msix_0.1.913.0_%s" % SHA_NEW), "build_not_latest_artifact"),
                 (FakeGh(expired=True), "artifact_expired")]
        for gh, reason in cases:
            store = FakeStore(self.submit_routes())
            code, doc = self.run_cli(["submit", "--build", "0.1.912.0", "--notes-stdin"], store, gh)
            self.assertEqual((code, doc), (4, {"blocked": reason}))
            self.assertEqual(store.writes(), [])

    def test_dry_run_plans_without_writes_or_download(self):
        store = FakeStore(self.submit_routes())
        gh = FakeGh()
        code, doc = self.run_cli(["submit", "--build", "0.1.912.0", "--notes-stdin", "--dry-run"], store, gh)
        self.assertEqual(code, 0)
        self.assertFalse(doc["submitted"])
        self.assertEqual(doc["planned"][0], "POST /applications/%s/submissions" % APP)
        self.assertTrue(doc["planned"][-1].endswith("/commit"))
        self.assertEqual(store.writes(), [])
        self.assertFalse(any(c[0] == "run" for c in gh.calls))

    def test_upload_failure_reports_error(self):
        routes = self.submit_routes()
        store = FakeStore(routes)
        original = store.__call__

        def failing(method, url, headers, body):
            if "blob.example" in url:
                return 403, None
            return original(method, url, headers, body)
        code, doc = self.run_cli(["submit", "--build", "0.1.912.0", "--notes-stdin"], failing, FakeGh())
        self.assertEqual(code, 1)
        self.assertIn("package upload failed", doc["error"])


class DispatchTests(Base):
    def test_fst_release_windows_group_dispatches(self):
        out = io.StringIO()
        with redirect_stdout(out):
            code = fr.main(["windows", "record-build", "--build", "0.1.1.0", "--version", "0.1.1.0",
                            "--sha", SHA_NEW], env=self.env)
        self.assertEqual(code, 0)
        self.assertTrue(json.loads(out.getvalue())["recorded"])
        self.assertEqual(fr.read_ledger(Path(self.env["FST_RELEASE_LEDGER"]))["WINDOWS"]["0.1.1.0"]["sha"],
                         SHA_NEW)

    def test_parse_artifact(self):
        self.assertEqual(fs.parse_artifact("fst-windows-msix_1.2.3.0_abcdef1_placeholder"),
                         {"version": "1.2.3.0", "sha": "abcdef1", "placeholder": True})
        self.assertIsNone(fs.parse_artifact("fst-windows-msix_bad"))


if __name__ == "__main__":
    unittest.main()
