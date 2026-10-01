"""Unit tests for ``tools/release/fst_release.py`` (no network; fake transport)."""

import base64
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from tools.release import fst_release as fr


def raw_to_der(raw):
    """Re-encode ``r || s`` as a DER ECDSA signature so openssl can verify it."""
    def enc(chunk):
        value = chunk.lstrip(b"\x00") or b"\x00"
        if value[0] & 0x80:
            value = b"\x00" + value
        return b"\x02" + bytes([len(value)]) + value
    body = enc(raw[:32]) + enc(raw[32:])
    return b"\x30" + bytes([len(body)]) + body


def b64url_decode(text):
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


class FakeAsc:
    """Routes ASC requests to canned JSON by (method, path) and records them."""

    def __init__(self, routes=None):
        self.routes = routes or {}
        self.calls = []

    def __call__(self, method, url, headers, body):
        parsed = urlparse(url)
        query = {k: v[0] for k, v in parse_qs(parsed.query).items()}
        payload = json.loads(body) if body else None
        self.calls.append((method, parsed.path, query, payload, headers))
        reply = self.routes.get((method, parsed.path))
        if callable(reply):
            reply = reply(query, payload)
        if reply is None:
            return 404, {"errors": [{"code": "NOT_FOUND", "detail": "no route %s %s" % (method, parsed.path)}]}
        if isinstance(reply, tuple):
            return reply
        return 200, reply

    def writes(self):
        return [(m, p) for m, p, _q, _b, _h in self.calls if m != "GET"]


def version(vid, string, state, created, key="appVersionState"):
    return {"type": "appStoreVersions", "id": vid,
            "attributes": {"versionString": string, key: state, "createdDate": created}}


def build_doc(bid, number, marketing, state="VALID", expired=False):
    return {"data": [{"type": "builds", "id": bid,
                      "attributes": {"version": number, "processingState": state, "expired": expired},
                      "relationships": {"preReleaseVersion": {"data": {"type": "preReleaseVersions", "id": "pr-" + bid}}}}],
            "included": [{"type": "preReleaseVersions", "id": "pr-" + bid, "attributes": {"version": marketing}}]}


class TempHome(unittest.TestCase):
    """Fixture with an isolated HOME holding a real EC test key."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        sec1 = os.path.join(cls.tmp, "sec1.pem")
        cls.key = os.path.join(cls.tmp, "AuthKey_KEY1234567.p8")
        subprocess.run(["openssl", "ecparam", "-genkey", "-name", "prime256v1", "-noout", "-out", sec1],
                       check=True, stderr=subprocess.DEVNULL)
        subprocess.run(["openssl", "pkcs8", "-topk8", "-nocrypt", "-in", sec1, "-out", cls.key],
                       check=True, stderr=subprocess.DEVNULL)
        cls.pub = os.path.join(cls.tmp, "pub.pem")
        subprocess.run(["openssl", "ec", "-in", cls.key, "-pubout", "-out", cls.pub],
                       check=True, stderr=subprocess.DEVNULL)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def env(self, **extra):
        env = {"HOME": self.tmp, "ASC_KEY_ID": "KEY1234567", "ASC_ISSUER_ID": "issuer-uuid",
               "ASC_KEY_PATH": self.key, "FST_RELEASE_LEDGER": os.path.join(self.tmp, "ledger.json"),
               "FST_RELEASE_CONFIG": os.path.join(self.tmp, "none.json")}
        env.update(extra)
        return env

    def creds(self):
        return fr.load_credentials(self.env())


class JwtTests(TempHome):
    def test_der_to_raw_strips_and_pads(self):
        r = (b"\x00\x80" + b"\x11" * 31)  # leading zero kept in DER for a high bit
        s = b"\x01" * 30  # short integer needs left padding
        der = b"\x30" + bytes([4 + len(r) + len(s)]) + b"\x02" + bytes([len(r)]) + r + b"\x02" + bytes([len(s)]) + s
        raw = fr.der_to_raw(der)
        self.assertEqual(len(raw), 64)
        self.assertEqual(raw[:32], r[1:])
        self.assertEqual(raw[32:], b"\x00\x00" + s)

    def test_der_to_raw_rejects_garbage(self):
        for bad in (b"", b"\x31\x00" * 5, b"\x30\x06\x02\x01\x01\x04\x01\x01"):
            with self.assertRaises(ValueError):
                fr.der_to_raw(bad)

    def test_jwt_structure_and_signature_verifies(self):
        token = fr.make_jwt(self.creds(), now=1_700_000_000)
        head, payload, sig = token.split(".")
        self.assertEqual(json.loads(b64url_decode(head)), {"alg": "ES256", "kid": "KEY1234567", "typ": "JWT"})
        claims = json.loads(b64url_decode(payload))
        self.assertEqual(claims, {"iss": "issuer-uuid", "iat": 1_700_000_000,
                                  "exp": 1_700_001_200, "aud": "appstoreconnect-v1"})
        raw = b64url_decode(sig)
        self.assertEqual(len(raw), 64)
        sig_file = os.path.join(self.tmp, "sig.der")
        data_file = os.path.join(self.tmp, "data.txt")
        Path(sig_file).write_bytes(raw_to_der(raw))
        Path(data_file).write_bytes(("%s.%s" % (head, payload)).encode())
        verify = subprocess.run(["openssl", "dgst", "-sha256", "-verify", self.pub, "-signature", sig_file, data_file],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(verify.returncode, 0, verify.stdout + verify.stderr)

    def test_bad_key_does_not_leak_path_or_token(self):
        bad = Path(self.tmp) / "bad.p8"
        bad.write_text("not a key")
        with self.assertRaises(RuntimeError) as ctx:
            fr.openssl_sign(bad, b"x")
        self.assertNotIn("bad.p8", str(ctx.exception))


class CredentialTests(TempHome):
    def test_env_credentials(self):
        creds = self.creds()
        self.assertEqual((creds.key_id, creds.issuer_id), ("KEY1234567", "issuer-uuid"))

    def test_default_key_path_from_home(self):
        home = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, str(home), True)
        keys = home / ".appstoreconnect" / "private_keys"
        keys.mkdir(parents=True)
        shutil.copy(self.key, str(keys / "AuthKey_KEY1234567.p8"))
        env = {"HOME": str(home), "ASC_KEY_ID": "KEY1234567", "ASC_ISSUER_ID": "i"}
        self.assertEqual(fr.load_credentials(env).key_path, keys / "AuthKey_KEY1234567.p8")

    def test_json_config_file(self):
        cfg = Path(self.tmp) / "asc.json"
        cfg.write_text(json.dumps({"key_id": "K2", "issuer_id": "I2", "key_path": self.key, "app_id": "42"}))
        creds = fr.load_credentials({"HOME": self.tmp, "FST_RELEASE_CONFIG": str(cfg)})
        self.assertEqual((creds.key_id, creds.issuer_id, creds.app_id), ("K2", "I2", "42"))

    def test_missing_pieces_return_none(self):
        self.assertIsNone(fr.load_credentials({"HOME": self.tmp, "FST_RELEASE_CONFIG": "/nonexistent"}))
        self.assertIsNone(fr.load_credentials(self.env(ASC_KEY_PATH="/nonexistent.p8")))
        self.assertIsNone(fr.load_credentials(self.env(ASC_ISSUER_ID="")))

    def run_main(self, argv, env, transport=None, stdin=None):
        out = io.StringIO()
        with redirect_stdout(out):
            code = fr.main(argv, env=env, transport=transport or FakeAsc(), stdin=stdin)
        text = out.getvalue()
        return code, (json.loads(text) if text.strip().startswith("{") else text.strip())

    def test_status_without_credentials_prints_full_shape_and_exits_4(self):
        code, doc = self.run_main(["ios", "status", "--json"], {"HOME": self.tmp, "FST_RELEASE_CONFIG": "/none"})
        self.assertEqual(code, 4)
        self.assertEqual(doc, {"in_review": False, "state": None, "version": None, "latest_build": None,
                               "released_sha": None, "blocked": "missing_asc_credentials"})

    def test_other_commands_without_credentials_exit_4(self):
        env = {"HOME": self.tmp, "FST_RELEASE_CONFIG": "/none"}
        for argv in (["ios", "next-version"], ["ios", "creds"],
                     ["ios", "submit", "--build", "1", "--notes-stdin"]):
            code, doc = self.run_main(argv, env, stdin=io.StringIO("x"))
            self.assertEqual((code, doc), (4, {"blocked": "missing_asc_credentials"}))

    def test_creds_prints_ids_but_not_key_material(self):
        code, doc = self.run_main(["ios", "creds"], self.env())
        self.assertEqual(code, 0)
        self.assertEqual(set(doc), {"key_id", "issuer_id", "key_path"})


def standard_routes(versions, build=None, in_review_subs=None, released_build="777"):
    routes = {
        ("GET", "/v1/apps"): {"data": [{"type": "apps", "id": "APP1"}]},
        ("GET", "/v1/apps/APP1/appStoreVersions"): {"data": versions},
        ("GET", "/v1/builds"): build or {"data": []},
        ("GET", "/v1/apps/APP1/reviewSubmissions"): lambda q, _b: {"data": (
            in_review_subs if q.get("filter[state]") == "WAITING_FOR_REVIEW,IN_REVIEW" else [])},
        ("GET", "/v1/appStoreVersions/V1/build"): {"data": {"type": "builds", "id": "B", "attributes": {"version": released_build}}},
    }
    return routes


class StatusTests(TempHome):
    def status(self, routes, ledger=None):
        client = fr.AscClient(self.creds(), transport=FakeAsc(routes))
        return fr.collect_status(client, "ios", "com.example", ledger or {})

    def test_released_with_latest_build_and_ledger_shas(self):
        routes = standard_routes(
            [version("V1", "1.0.0", "READY_FOR_SALE", "2026-09-01T00:00:00Z", key="appStoreState")],
            build=build_doc("B2", "888", "1.0.1", "PROCESSING"))
        ledger = {"IOS": {"777": {"sha": "aaa"}, "888": {"sha": "bbb"}}}
        doc = self.status(routes, ledger)
        self.assertEqual(doc, {
            "in_review": False, "state": "READY_FOR_SALE", "version": "1.0.0",
            "latest_build": {"version": "1.0.1", "build": "888", "sha": "bbb", "processing_state": "PROCESSING"},
            "released_sha": "aaa", "blocked": None})

    def test_sha_lookup_fills_ledger_gaps(self):
        routes = standard_routes(
            [version("V1", "1.0.0", "READY_FOR_SALE", "2026-09-01T00:00:00Z", key="appStoreState")],
            build=build_doc("B2", "888", "1.0.1", "VALID"))
        client = fr.AscClient(self.creds(), transport=FakeAsc(routes))
        doc = fr.collect_status(client, "ios", "com.example", {"IOS": {"777": {"sha": "aaa"}}},
                                sha_lookup={"888": "ccc"}.get)
        self.assertEqual((doc["latest_build"]["sha"], doc["released_sha"]), ("ccc", "aaa"))

    def test_in_review_states(self):
        for state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_APPLE_RELEASE", "PENDING_DEVELOPER_RELEASE"):
            doc = self.status(standard_routes([version("V2", "1.0.1", state, "2026-09-02T00:00:00Z")]))
            self.assertTrue(doc["in_review"], state)
            self.assertEqual(doc["state"], state)

    def test_review_submission_in_flight_counts_as_in_review(self):
        routes = standard_routes([version("V2", "1.0.1", "PREPARE_FOR_SUBMISSION", "2026-09-02T00:00:00Z")],
                                 in_review_subs=[{"id": "S1"}])
        self.assertTrue(self.status(routes)["in_review"])

    def test_rejected_and_unresolved_are_not_in_review(self):
        for state in ("REJECTED", "METADATA_REJECTED", "DEVELOPER_REJECTED", "PREPARE_FOR_SUBMISSION"):
            doc = self.status(standard_routes([version("V2", "1.0.1", state, "2026-09-02T00:00:00Z")]))
            self.assertFalse(doc["in_review"], state)

    def test_busy_old_version_wins_over_newer_editable(self):
        routes = standard_routes([version("V3", "1.0.2", "PREPARE_FOR_SUBMISSION", "2026-09-03T00:00:00Z"),
                                  version("V2", "1.0.1", "IN_REVIEW", "2026-09-02T00:00:00Z")])
        doc = self.status(routes)
        self.assertEqual((doc["in_review"], doc["state"], doc["version"]), (True, "IN_REVIEW", "1.0.1"))

    def test_no_versions_and_no_builds(self):
        doc = self.status(standard_routes([]))
        self.assertEqual(doc, {"in_review": False, "state": None, "version": None, "latest_build": None,
                               "released_sha": None, "blocked": None})

    def test_unknown_ledger_sha_is_none(self):
        routes = standard_routes([version("V1", "1.0.0", "READY_FOR_DISTRIBUTION", "2026-09-01T00:00:00Z")])
        self.assertIsNone(self.status(routes)["released_sha"])

    def test_app_not_found_is_blocked_with_full_shape(self):
        transport = FakeAsc({("GET", "/v1/apps"): {"data": []}})
        out = io.StringIO()
        with redirect_stdout(out):
            code = fr.main(["ios", "status", "--json"], env=self.env(), transport=transport)
        self.assertEqual(code, 4)
        self.assertEqual(json.loads(out.getvalue())["blocked"], "app_not_found")

    def test_api_error_fails_closed(self):
        out = io.StringIO()
        with redirect_stdout(out):
            code = fr.main(["ios", "status", "--json"], env=self.env(), transport=FakeAsc({}))
        doc = json.loads(out.getvalue())
        self.assertEqual((code, doc["blocked"], doc["in_review"]), (5, "asc_error", False))

    def test_requests_carry_bearer_token_and_platform_filter(self):
        fake = FakeAsc(standard_routes([]))
        fr.collect_status(fr.AscClient(self.creds(), transport=fake), "ios", "com.example", {})
        self.assertTrue(all(h["Authorization"].startswith("Bearer ey") for *_x, h in fake.calls))
        versions_call = [c for c in fake.calls if c[1].endswith("/appStoreVersions")][0]
        self.assertEqual(versions_call[2]["filter[platform]"], "IOS")
        self.assertEqual(fake.writes(), [])


class NextVersionTests(unittest.TestCase):
    def test_no_versions_uses_project(self):
        self.assertEqual(fr.compute_next_version([], "0.1.0"), ("0.1.0", "first_version"))

    def test_released_bumps_patch_of_max(self):
        vs = [version("a", "1.0.3", "READY_FOR_SALE", "2"), version("b", "1.0.0", "READY_FOR_SALE", "1")]
        self.assertEqual(fr.compute_next_version(vs, "0.1.0"), ("1.0.4", "bump_patch"))

    def test_project_higher_than_released_wins(self):
        vs = [version("a", "1.0.0", "READY_FOR_SALE", "1")]
        self.assertEqual(fr.compute_next_version(vs, "1.2.0")[0], "1.2.1")

    def test_editable_is_reused(self):
        for state in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"):
            vs = [version("a", "1.0.5", state, "3"), version("b", "1.0.4", "READY_FOR_SALE", "2")]
            self.assertEqual(fr.compute_next_version(vs, "0.1.0"), ("1.0.5", "reuse_editable"))

    def test_in_review_version_bumps_past_it(self):
        vs = [version("a", "1.0.5", "WAITING_FOR_REVIEW", "3")]
        self.assertEqual(fr.compute_next_version(vs, "0.1.0")[0], "1.0.6")

    def test_two_component_versions(self):
        self.assertEqual(fr.bump_patch("1.2"), "1.2.1")

    def test_project_version_reads_each_target(self):
        self.assertRegex(fr.project_version("ios"), r"^\d+\.\d+\.\d+$")
        self.assertRegex(fr.project_version("macos"), r"^\d+\.\d+\.\d+$")


class SubmitTests(TempHome):
    def routes(self, versions, **kw):
        routes = standard_routes(versions, build=kw.get("build", build_doc("B9", "999", "1.0.1")),
                                 in_review_subs=kw.get("in_review_subs"))
        routes[("GET", "/v1/apps/APP1/reviewSubmissions")] = lambda q, _b: {"data": (
            kw.get("in_review_subs") or [] if q.get("filter[state]") == "WAITING_FOR_REVIEW,IN_REVIEW"
            else kw.get("open_subs") or [])}
        routes[("GET", "/v1/appStoreVersions/NEW/appStoreVersionLocalizations")] = {"data": kw.get("locs", [])}
        routes[("GET", "/v1/appStoreVersions/V2/appStoreVersionLocalizations")] = {"data": kw.get("locs", [])}
        routes[("POST", "/v1/appStoreVersions")] = {"data": {"id": "NEW"}}
        routes[("POST", "/v1/appStoreVersionLocalizations")] = {"data": {"id": "LOC"}}
        routes[("PATCH", "/v1/appStoreVersionLocalizations/L1")] = {"data": {"id": "L1"}}
        routes[("PATCH", "/v1/appStoreVersions/NEW")] = {"data": {"id": "NEW"}}
        routes[("PATCH", "/v1/appStoreVersions/V2")] = {"data": {"id": "V2"}}
        routes[("POST", "/v1/reviewSubmissions")] = {"data": {"id": "SUB"}}
        routes[("POST", "/v1/reviewSubmissionItems")] = {"data": {"id": "ITEM"}}
        routes[("PATCH", "/v1/reviewSubmissions/SUB")] = {"data": {"id": "SUB"}}
        routes[("PATCH", "/v1/reviewSubmissions/OPEN")] = {"data": {"id": "OPEN"}}
        routes[("GET", "/v1/reviewSubmissions/OPEN/items")] = {"data": kw.get("items", [])}
        return routes

    released = [version("V1", "1.0.0", "READY_FOR_SALE", "2026-09-01T00:00:00Z")]

    def run_submit(self, routes, notes="Fixed things", dry_run=False, release_type="AFTER_APPROVAL"):
        fake = FakeAsc(routes)
        client = fr.AscClient(self.creds(), transport=fake, dry_run=dry_run)
        return fake, client, fr.submit(client, "ios", "com.example", "999", notes, release_type)

    def test_manual_release_type_is_written(self):
        fake, _client, _result = self.run_submit(self.routes(self.released), release_type="MANUAL")
        bodies = {(m, p): b for m, p, _q, b, _h in fake.calls if m != "GET"}
        self.assertEqual(bodies[("POST", "/v1/appStoreVersions")]["data"]["attributes"]["releaseType"], "MANUAL")
        self.assertEqual(bodies[("PATCH", "/v1/appStoreVersions/NEW")]["data"]["attributes"]["releaseType"], "MANUAL")

    def test_unknown_release_type_writes_nothing(self):
        fake = FakeAsc(self.routes(self.released))
        client = fr.AscClient(self.creds(), transport=fake)
        with self.assertRaises(ValueError):
            fr.submit(client, "ios", "com.example", "999", "x", "IMMEDIATE")
        self.assertEqual(fake.writes(), [])

    def test_full_sequence_creates_version(self):
        fake, _client, result = self.run_submit(self.routes(self.released))
        self.assertEqual(fake.writes(), [
            ("POST", "/v1/appStoreVersions"),
            ("POST", "/v1/appStoreVersionLocalizations"),
            ("PATCH", "/v1/appStoreVersions/NEW"),
            ("POST", "/v1/reviewSubmissions"),
            ("POST", "/v1/reviewSubmissionItems"),
            ("PATCH", "/v1/reviewSubmissions/SUB")])
        bodies = {(m, p): b for m, p, _q, b, _h in fake.calls if m != "GET"}
        create = bodies[("POST", "/v1/appStoreVersions")]["data"]
        self.assertEqual(create["attributes"], {"platform": "IOS", "versionString": "1.0.1", "releaseType": "AFTER_APPROVAL"})
        loc = bodies[("POST", "/v1/appStoreVersionLocalizations")]["data"]
        self.assertEqual(loc["attributes"], {"locale": "en-US", "whatsNew": "Fixed things"})
        patch = bodies[("PATCH", "/v1/appStoreVersions/NEW")]["data"]
        self.assertEqual(patch["relationships"]["build"]["data"], {"type": "builds", "id": "B9"})
        self.assertEqual(patch["attributes"]["releaseType"], "AFTER_APPROVAL")
        item = bodies[("POST", "/v1/reviewSubmissionItems")]["data"]["relationships"]
        self.assertEqual(item["appStoreVersion"]["data"]["id"], "NEW")
        self.assertEqual(item["reviewSubmission"]["data"]["id"], "SUB")
        self.assertEqual(bodies[("PATCH", "/v1/reviewSubmissions/SUB")]["data"]["attributes"], {"submitted": True})
        self.assertTrue(result["submitted"])
        self.assertEqual(result["whats_new"], "set")

    def test_reuses_editable_version_and_existing_localization(self):
        versions = [version("V2", "1.0.1", "REJECTED", "2026-09-02T00:00:00Z")] + self.released
        fake, _c, result = self.run_submit(self.routes(versions, locs=[{"id": "L1"}]))
        self.assertNotIn(("POST", "/v1/appStoreVersions"), fake.writes())
        self.assertIn(("PATCH", "/v1/appStoreVersionLocalizations/L1"), fake.writes())
        self.assertEqual(result["version_id"], "V2")

    def test_editable_version_with_other_string_is_retargeted(self):
        versions = [version("V2", "1.0.0", "PREPARE_FOR_SUBMISSION", "2026-09-02T00:00:00Z")]
        released = self.released + versions
        fake, _c, _r = self.run_submit(self.routes(released))
        patch = [b for m, p, _q, b, _h in fake.calls if (m, p) == ("PATCH", "/v1/appStoreVersions/V2")][0]
        self.assertEqual(patch["data"]["attributes"]["versionString"], "1.0.1")

    def test_reuses_open_review_submission(self):
        fake, _c, result = self.run_submit(self.routes(self.released, open_subs=[{"id": "OPEN"}]))
        self.assertNotIn(("POST", "/v1/reviewSubmissions"), fake.writes())
        self.assertIn(("PATCH", "/v1/reviewSubmissions/OPEN"), fake.writes())
        self.assertEqual(result["submission_id"], "OPEN")

    def test_refuses_when_in_review_and_writes_nothing(self):
        for versions, subs in (([version("V2", "1.0.1", "IN_REVIEW", "9")], None),
                               (self.released, [{"id": "S"}])):
            fake, _c, result = self.run_submit(self.routes(versions, in_review_subs=subs))
            self.assertEqual(result, {"submitted": False, "refused": "in_review"})
            self.assertEqual(fake.writes(), [])

    def test_rejects_invalid_or_missing_build(self):
        for build in (build_doc("B9", "999", "1.0.1", state="PROCESSING"),
                      build_doc("B9", "999", "1.0.1", expired=True), {"data": []}):
            with self.assertRaises(ValueError):
                self.run_submit(self.routes(self.released, build=build))

    def test_first_ever_version_skips_whats_new(self):
        fake, _c, result = self.run_submit(self.routes([]))
        self.assertEqual(result["whats_new"], "skipped_first_version")
        self.assertNotIn(("POST", "/v1/appStoreVersionLocalizations"), fake.writes())

    def test_dry_run_sends_no_writes_and_lists_plan(self):
        fake, client, result = self.run_submit(self.routes(self.released), dry_run=True)
        self.assertEqual(fake.writes(), [])
        self.assertEqual(len(client.planned), 6)
        self.assertFalse(result["submitted"])

    def test_empty_notes_use_default_and_long_notes_are_capped(self):
        fake, _c, _r = self.run_submit(self.routes(self.released), notes="  \n")
        loc = [b for m, p, _q, b, _h in fake.calls if (m, p) == ("POST", "/v1/appStoreVersionLocalizations")][0]
        self.assertEqual(loc["data"]["attributes"]["whatsNew"], fr.DEFAULT_NOTES)
        fake, _c, _r = self.run_submit(self.routes(self.released), notes="x" * 5000)
        loc = [b for m, p, _q, b, _h in fake.calls if (m, p) == ("POST", "/v1/appStoreVersionLocalizations")][0]
        self.assertEqual(len(loc["data"]["attributes"]["whatsNew"]), fr.WHATS_NEW_LIMIT)

    def test_cli_refusal_exit_code_and_notes_stdin(self):
        routes = self.routes([version("V2", "1.0.1", "WAITING_FOR_REVIEW", "9")])
        out = io.StringIO()
        with redirect_stdout(out):
            code = fr.main(["ios", "submit", "--build", "999", "--notes-stdin"], env=self.env(),
                           transport=FakeAsc(routes), stdin=io.StringIO("notes"))
        self.assertEqual(code, 3)
        self.assertEqual(json.loads(out.getvalue())["refused"], "in_review")

    def test_cli_api_error_exit_1(self):
        routes = self.routes(self.released)
        routes[("POST", "/v1/appStoreVersions")] = (409, {"errors": [{"code": "ENTITY_ERROR", "detail": "dup"}]})
        notes = Path(self.tmp) / "notes.txt"
        notes.write_text("hello")
        out = io.StringIO()
        with redirect_stdout(out):
            code = fr.main(["ios", "submit", "--build", "999", "--notes-file", str(notes)], env=self.env(),
                           transport=FakeAsc(routes))
        self.assertEqual(code, 1)
        self.assertIn("ENTITY_ERROR", json.loads(out.getvalue())["error"])

    def test_stale_baseline_refuses_without_writes(self):
        versions = [version("V2", "1.0.0", "READY_FOR_SALE", "2026-09-02T00:00:00Z")]
        fake = FakeAsc(self.routes(versions))
        client = fr.AscClient(self.creds(), transport=fake)
        result = fr.submit(client, "ios", "com.example", "999", "n", "MANUAL", baseline=None)
        self.assertEqual(result["refused"], "stale_whats_new")
        self.assertEqual((result["baseline"], result["current_baseline"]), (None, "1.0.0"))
        self.assertEqual(fake.writes(), [])

    def test_matching_baseline_submits(self):
        fake = FakeAsc(self.routes(self.released))
        client = fr.AscClient(self.creds(), transport=fake)
        result = fr.submit(client, "ios", "com.example", "999", "n", "MANUAL", baseline="1.0.0")
        self.assertTrue(result["submitted"])

    def test_cli_baseline_none(self):
        out = io.StringIO()
        with redirect_stdout(out):
            code = fr.main(["ios", "submit", "--build", "999", "--notes-stdin", "--whats-new-baseline", "none"],
                           env=self.env(), transport=FakeAsc(self.routes(self.released)), stdin=io.StringIO("x"))
        self.assertEqual((code, json.loads(out.getvalue())["refused"]), (3, "stale_whats_new"))


class VersionHistoryTests(unittest.TestCase):
    def test_released_versions_and_baseline(self):
        vs = [version("a", "2610.03", "PREPARE_FOR_SUBMISSION", "4"),
              version("b", "2610.02", "READY_FOR_SALE", "3"),
              version("c", "2610.01", "REPLACED_WITH_NEW_VERSION", "2"),
              version("d", "2610.10", "REJECTED", "5"),
              version("e", "bogus", "READY_FOR_SALE", "1")]
        self.assertEqual(fr.released_versions(vs), ["2610.02", "2610.01"])
        self.assertEqual(fr.released_baseline(vs, "2610.03"), "2610.02")
        self.assertEqual(fr.released_baseline(vs, "2610.02"), "2610.01")
        self.assertIsNone(fr.released_baseline(vs, "2610.01"))
        self.assertIsNone(fr.released_baseline([], "2610.01"))


class BetaNotesTests(TempHome):
    def routes(self, builds, locs):
        seq = list(builds)
        routes = {("GET", "/v1/apps"): {"data": [{"id": "APP1"}]},
                  ("GET", "/v1/builds"): lambda q, _b: seq.pop(0) if len(seq) > 1 else seq[0],
                  ("GET", "/v1/builds/B9/betaBuildLocalizations"): {"data": locs},
                  ("PATCH", "/v1/betaBuildLocalizations/BL1"): {"data": {"id": "BL1"}},
                  ("POST", "/v1/betaBuildLocalizations"): {"data": {"id": "BL2"}}}
        return routes

    def test_waits_for_build_then_creates_localization(self):
        fake = FakeAsc(self.routes([{"data": []}, build_doc("B9", "57", "2610.01", "PROCESSING")], []))
        client = fr.AscClient(self.creds(), transport=fake)
        sleeps = []
        result = fr.beta_notes(client, "ios", "com.example", "57", " What changed \n", wait=100,
                               sleep=sleeps.append, clock=lambda: 0.0)
        self.assertEqual((result["beta_notes"], result["version"], sleeps), ("set", "2610.01", [30]))
        body = [b for m, p, _q, b, _h in fake.calls if m == "POST"][0]["data"]
        self.assertEqual(body["attributes"], {"locale": "en-US", "whatsNew": "What changed"})
        self.assertEqual(body["relationships"]["build"]["data"]["id"], "B9")

    def test_patches_existing_localization(self):
        locs = [{"id": "BL0", "attributes": {"locale": "fr-FR"}}, {"id": "BL1", "attributes": {"locale": "en-US"}}]
        fake = FakeAsc(self.routes([build_doc("B9", "57", "2610.01")], locs))
        fr.beta_notes(fr.AscClient(self.creds(), transport=fake), "ios", "com.example", "57", "x" * 5000)
        self.assertEqual(fake.writes(), [("PATCH", "/v1/betaBuildLocalizations/BL1")])
        body = [b for m, p, _q, b, _h in fake.calls if m == "PATCH"][0]
        self.assertEqual(len(body["data"]["attributes"]["whatsNew"]), fr.BETA_NOTES_LIMIT)

    def test_timeout_and_empty_notes(self):
        ticks = iter([0.0, 50.0, 200.0])
        fake = FakeAsc(self.routes([{"data": []}], []))
        client = fr.AscClient(self.creds(), transport=fake)
        with self.assertRaises(ValueError):
            fr.beta_notes(client, "ios", "com.example", "57", "n", wait=100, sleep=lambda _s: None,
                          clock=lambda: next(ticks))
        with self.assertRaises(ValueError):
            fr.beta_notes(client, "ios", "com.example", "57", "  ")

    def test_cli_beta_notes_and_released_versions(self):
        routes = self.routes([build_doc("B9", "57", "2610.01")], [])
        routes[("GET", "/v1/apps/APP1/appStoreVersions")] = {"data": [
            version("V1", "2610.01", "READY_FOR_SALE", "1")]}
        out = io.StringIO()
        with redirect_stdout(out):
            code = fr.main(["ios", "beta-notes", "--build", "57", "--notes-stdin"], env=self.env(),
                           transport=FakeAsc(routes), stdin=io.StringIO("notes"))
        self.assertEqual((code, json.loads(out.getvalue())["beta_notes"]), (0, "set"))
        out = io.StringIO()
        with redirect_stdout(out):
            code = fr.main(["ios", "released-versions", "--json"], env=self.env(), transport=FakeAsc(routes))
        self.assertEqual((code, json.loads(out.getvalue())), (0, {"released": ["2610.01"]}))


class MarkerTests(unittest.TestCase):
    def zip_with(self, doc):
        import zipfile
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as archive:
            archive.writestr("build.json", json.dumps(doc))
        return buf.getvalue()

    def listing(self, args):
        return json.dumps({"artifacts": [{"id": 7, "name": "fst-ios-build_57",
                                          "workflow_run": {"head_sha": "h" * 40}}]})

    def test_marker_download_prefers_marker_sha(self):
        doc = {"built": True, "build": "57", "sha": "s" * 40, "whats_new_baseline": None}
        fetched = []
        fetch = lambda args: fetched.append(args) or self.zip_with(doc)  # noqa: E731
        marker = fr.artifact_marker("fst-ios-build_57", "o/r", self.listing, fetch)
        self.assertEqual((marker["sha"], marker["run_head_sha"]), ("s" * 40, "h" * 40))
        self.assertEqual(fetched[0], ["api", "repos/o/r/actions/artifacts/7/zip"])
        self.assertEqual(fr.artifact_head_sha("fst-ios-build_57", "o/r", self.listing, fetch), "s" * 40)

    def test_bad_zip_falls_back_to_run_head(self):
        self.assertIsNone(fr.artifact_marker("fst-ios-build_57", "o/r", self.listing, lambda a: b"nope"))
        self.assertEqual(fr.artifact_head_sha("fst-ios-build_57", "o/r", self.listing, lambda a: b"nope"),
                         "h" * 40)


class LedgerTests(TempHome):
    def test_record_build_cli_roundtrip(self):
        env = self.env(FST_RELEASE_LEDGER=os.path.join(self.tmp, "sub", "dir", "builds.json"))
        out = io.StringIO()
        with redirect_stdout(out):
            code = fr.main(["ios", "record-build", "--build", "12", "--version", "1.0.1", "--sha", "abc"], env=env)
            fr.main(["ios", "record-build", "--build", "13", "--version", "1.0.1", "--sha", "def"], env=env)
        self.assertEqual(code, 0)
        ledger = fr.read_ledger(fr.ledger_path(env))
        self.assertEqual(fr.ledger_sha(ledger, "IOS", "12"), "abc")
        self.assertEqual(fr.ledger_sha(ledger, "IOS", "13"), "def")
        self.assertIsNone(fr.ledger_sha(ledger, "IOS", "14"))
        self.assertIsNone(fr.ledger_sha(ledger, "MAC_OS", "12"))

    def test_corrupt_ledger_reads_empty(self):
        path = Path(self.tmp) / "corrupt.json"
        path.write_text("{nope")
        self.assertEqual(fr.read_ledger(path), {})


if __name__ == "__main__":
    unittest.main()


class ErrorDetailTests(unittest.TestCase):
    def test_associated_errors_are_listed(self):
        payload = {"errors": [{"code": "STATE_ERROR", "detail": "cannot be reviewed", "meta": {
            "associatedErrors": {"/v1/appStoreVersions/V": [
                {"code": "ENTITY_ERROR.ATTRIBUTE.REQUIRED", "detail": "copyright is required"}]}}}]}
        self.assertEqual(fr._error_detail(payload),
                         "STATE_ERROR: cannot be reviewed [ENTITY_ERROR.ATTRIBUTE.REQUIRED: copyright is required]")
