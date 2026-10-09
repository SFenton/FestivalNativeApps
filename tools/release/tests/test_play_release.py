"""Tests for tools/release/play_release.py (no network: a fake HTTP transport)."""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from tools.release import play_release as pr

ACCOUNT = {"type": "service_account", "client_email": "ci@fst.iam.gserviceaccount.com",
           "private_key": "-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n"}
PKG = "com.festivalscoretracker.android"


class FakeHttp:
    """Routes ``(method, url-prefix)`` to ``(status, body)`` or a list of them (consumed in order)."""

    def __init__(self, routes):
        self.routes, self.calls = routes, []

    def __call__(self, method, url, headers, body):
        self.calls.append((method, url, headers, body))
        matches = [(len(prefix), key) for key in self.routes for m, prefix in [key]
                   if m == method and url.startswith(prefix)]
        if not matches:
            raise AssertionError(f"unexpected {method} {url}")
        answer = self.routes[max(matches)[1]]
        return answer.pop(0) if isinstance(answer, list) else answer


def routes(extra=None):
    base = {
        ("POST", pr.TOKEN_URL): (200, {"access_token": "tok"}),
        ("POST", f"{pr.API}/{PKG}/edits"): (200, {"id": "e1"}),
        ("DELETE", f"{pr.API}/{PKG}/edits/e1"): (204, {}),
        ("POST", f"{pr.UPLOAD_API}/{PKG}/edits/e1/bundles"): (200, {"versionCode": 261009010}),
        ("PUT", f"{pr.API}/{PKG}/edits/e1/tracks/internal"): (200, {}),
    }
    base.update(extra or {})
    return base


def fake_sign(key, message):
    return b"sig"


class PlayReleaseTests(unittest.TestCase):
    def run_main(self, argv, http, env=None):
        env = {"PLAY_SERVICE_ACCOUNT_JSON": json.dumps(ACCOUNT)} if env is None else env
        from io import StringIO
        import contextlib
        out = StringIO()
        with contextlib.redirect_stdout(out):
            code = pr.main(argv, http=http, env=env, sign=fake_sign)
        return code, json.loads(out.getvalue())

    def test_token_assertion_is_a_signed_jwt_for_the_publisher_scope(self):
        http = FakeHttp(routes())
        token = pr.access_token(ACCOUNT, http, now=lambda: 1000, sign=fake_sign)
        self.assertEqual(token, "tok")
        body = http.calls[0][3].decode()
        self.assertIn("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer", body)
        assertion = dict(p.split("=", 1) for p in body.split("&"))["assertion"]
        header, claims, signature = assertion.split(".")
        pad = lambda s: s + "=" * (-len(s) % 4)
        decoded = json.loads(__import__("base64").urlsafe_b64decode(pad(claims)))
        self.assertEqual((decoded["iss"], decoded["scope"], decoded["exp"]),
                         (ACCOUNT["client_email"], pr.SCOPE, 4600))
        self.assertEqual(signature, "c2ln")

    def test_check_opens_and_discards_an_edit(self):
        http = FakeHttp(routes())
        code, out = self.run_main(["check", "--package", PKG], http)
        self.assertEqual((code, out["status"]), (0, "ready"))
        self.assertIn(("DELETE", f"{pr.API}/{PKG}/edits/e1"), [(m, u) for m, u, _h, _b in http.calls])

    def test_check_reports_an_app_that_play_does_not_know_yet(self):
        http = FakeHttp(routes({("POST", f"{pr.API}/{PKG}/edits"): (404, {"error": {"message": "Package not found"}})}))
        code, out = self.run_main(["check", "--package", PKG], http)
        self.assertEqual((code, out["status"]), (2, "app_not_ready"))

    def test_upload_releases_on_the_track_and_commits(self):
        http = FakeHttp(routes({("POST", f"{pr.API}/{PKG}/edits/e1:commit"): (200, {})}))
        with tempfile.TemporaryDirectory() as tmp:
            aab, notes = Path(tmp, "a.aab"), Path(tmp, "n.txt")
            aab.write_bytes(b"AAB")
            notes.write_text("Fixes things\n")
            code, out = self.run_main(["upload", "--package", PKG, "--aab", str(aab), "--version-name", "2610.09.01",
                                       "--notes-file", str(notes)], http)
        self.assertEqual((code, out["status"], out["version_code"]), (0, "completed", 261009010))
        put = next(b for m, u, _h, b in http.calls if m == "PUT")
        release = json.loads(put)["releases"][0]
        self.assertEqual(release, {"name": "2610.09.01", "versionCodes": ["261009010"], "status": "completed",
                                   "releaseNotes": [{"language": "en-US", "text": "Fixes things"}]})
        upload = next((h, b) for m, u, h, b in http.calls if "bundles" in u)
        self.assertEqual((upload[0]["Content-Type"], upload[1]), ("application/octet-stream", b"AAB"))
        self.assertEqual(http.calls[-1][1], f"{pr.API}/{PKG}/edits/e1:commit")

    def test_a_draft_app_gets_a_draft_release(self):
        draft = (400, {"error": {"message": "Only releases with status draft may be created on draft app."}})
        http = FakeHttp(routes({("PUT", f"{pr.API}/{PKG}/edits/e1/tracks/internal"): [draft, (200, {})],
                                  ("POST", f"{pr.API}/{PKG}/edits/e1:commit"): (200, {})}))
        with tempfile.TemporaryDirectory() as tmp:
            aab = Path(tmp, "a.aab")
            aab.write_bytes(b"AAB")
            code, out = self.run_main(["upload", "--package", PKG, "--aab", str(aab), "--version-name", "1"], http)
        self.assertEqual((code, out["status"]), (0, "draft"))
        puts = [json.loads(b)["releases"][0]["status"] for m, u, _h, b in http.calls if m == "PUT"]
        self.assertEqual(puts, ["completed", "draft"])

    def test_a_failed_commit_discards_the_edit_and_exits_1(self):
        http = FakeHttp(routes({("POST", f"{pr.API}/{PKG}/edits/e1:commit"): (403, {"error": {"message": "denied"}})}))
        with tempfile.TemporaryDirectory() as tmp:
            aab = Path(tmp, "a.aab")
            aab.write_bytes(b"AAB")
            code, out = self.run_main(["upload", "--package", PKG, "--aab", str(aab), "--version-name", "1"], http)
        self.assertEqual((code, out["step"]), (1, "edits.commit"))
        self.assertEqual(http.calls[-1][0], "DELETE")

    def test_missing_or_bad_credentials(self):
        code, out = self.run_main(["check", "--package", PKG], FakeHttp({}), env={})
        self.assertEqual((code, out["status"]), (2, "missing_play_credentials"))
        code, out = self.run_main(["check", "--package", PKG], FakeHttp({}),
                                  env={"PLAY_SERVICE_ACCOUNT_JSON": json.dumps({"type": "user"})})
        self.assertEqual(code, 2)
        self.assertNotIn("abc", json.dumps(out))

    def test_notes_are_clipped_to_play_s_limit(self):
        self.assertEqual(pr.clip_notes(" short \n"), "short")
        long = "\n".join(f"- line {i} " + "x" * 40 for i in range(30))
        clipped = pr.clip_notes(long)
        self.assertLessEqual(len(clipped), pr.NOTES_LIMIT)
        self.assertTrue(clipped.endswith("…"))

    @unittest.skipUnless(shutil.which("openssl"), "openssl not installed")
    def test_openssl_signature_verifies(self):
        with tempfile.TemporaryDirectory() as tmp:
            key, pub = Path(tmp, "k.pem"), Path(tmp, "p.pem")
            subprocess.run(["openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048",
                            "-out", str(key)], check=True, capture_output=True)
            subprocess.run(["openssl", "pkey", "-in", str(key), "-pubout", "-out", str(pub)], check=True,
                           capture_output=True)
            sig = pr.openssl_sign(key.read_text(), b"payload")
            sig_file = Path(tmp, "s.bin")
            sig_file.write_bytes(sig)
            msg = Path(tmp, "m.bin")
            msg.write_bytes(b"payload")
            ok = subprocess.run(["openssl", "dgst", "-sha256", "-verify", str(pub), "-signature", str(sig_file),
                                 str(msg)], capture_output=True)
            self.assertEqual(ok.returncode, 0)


if __name__ == "__main__":
    unittest.main()
