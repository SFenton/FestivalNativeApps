"""Tests for tools/release/store_secrets.py (no network; gh is faked)."""

from __future__ import annotations

import base64
import io
import json
import shutil
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from tools.release import store_secrets as ss

ISSUER = "69a6de70-03db-47e3-e053-5b8c7c11a4d1"
P8 = "-----BEGIN PRIVATE KEY-----\nMIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg\n-----END PRIVATE KEY-----"


class FakeGh:
    """Records ``gh`` calls; ``secret list`` answers with ``present``."""

    def __init__(self, present=(), fail_set=False):
        self.calls = []
        self.present = list(present)
        self.fail_set = fail_set

    def __call__(self, argv, stdin):
        self.calls.append((list(argv), stdin))
        if argv[:2] == ["secret", "list"]:
            out = json.dumps([{"name": n} for n in self.present]).encode()
            return subprocess.CompletedProcess(argv, 0, out, b"")
        if self.fail_set:
            return subprocess.CompletedProcess(argv, 1, b"", b"HTTP 403")
        return subprocess.CompletedProcess(argv, 0, b"", b"")

    def secrets(self):
        return {argv[2]: stdin.decode() for argv, stdin in self.calls if argv[:2] == ["secret", "set"]}


class StoreSecretsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp)

    def write(self, name, content):
        path = self.tmp / name
        path.write_bytes(content if isinstance(content, bytes) else content.encode())
        return str(path)

    def run_main(self, argv, gh, subjects_fn=lambda data, pw: None):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = ss.main(argv, runner=gh, subjects_fn=subjects_fn)
        return code, out.getvalue(), err.getvalue()

    def test_asc_sets_three_secrets_on_stdin_only(self):
        gh = FakeGh()
        code, out, _ = self.run_main(
            ["asc", "--key-id", "ABC123DEFG", "--issuer-id", ISSUER, "--p8", self.write("k.p8", P8 + "\n")], gh)
        self.assertEqual(code, 0)
        self.assertEqual(gh.secrets(), {"ASC_KEY_ID": "ABC123DEFG", "ASC_ISSUER_ID": ISSUER, "ASC_PRIVATE_KEY": P8})
        for argv, _ in gh.calls:
            self.assertEqual(argv[3:], ["--env", "store-release", "-R", ss.REPO])
            self.assertNotIn(P8, " ".join(argv))
        self.assertNotIn("PRIVATE KEY", out)

    def test_asc_rejects_bad_input_without_calling_gh(self):
        gh = FakeGh()
        code, _, err = self.run_main(
            ["asc", "--key-id", "short", "--issuer-id", ISSUER, "--p8", self.write("k.p8", P8)], gh)
        self.assertEqual(code, 2)
        self.assertEqual(gh.calls, [])
        self.assertIn("key id", err)
        code, _, _ = self.run_main(
            ["asc", "--key-id", "ABC123DEFG", "--issuer-id", ISSUER, "--p8", self.write("bad.p8", "nope")], gh)
        self.assertEqual(code, 2)

    def test_ios_p12_base64_and_subject_check(self):
        gh = FakeGh()
        p12 = self.write("d.p12", b"\x30\x82binary")
        pw = self.write("pw", "s3cret\n")
        code, _, _ = self.run_main(["ios-p12", "--p12", p12, "--password-file", pw], gh,
                                   subjects_fn=lambda d, p: ["CN = Apple Distribution: Example (3Q9X8JX23S)"])
        self.assertEqual(code, 0)
        self.assertEqual(gh.secrets()["IOS_DIST_P12_PASSWORD"], "s3cret")
        self.assertEqual(base64.b64decode(gh.secrets()["IOS_DIST_P12_BASE64"]), b"\x30\x82binary")

        gh = FakeGh()
        code, _, err = self.run_main(["ios-p12", "--p12", p12, "--password-file", pw], gh,
                                     subjects_fn=lambda d, p: ["CN = Apple Development: Example"])
        self.assertEqual(code, 2)
        self.assertEqual(gh.calls, [])
        self.assertIn("Apple Distribution", err)
        with self.assertRaises(ss.InputError):
            ss.validate_p12_subjects(["CN = Apple Distribution: A", "CN = Apple Development: B"])

    @unittest.skipUnless(shutil.which("openssl"), "openssl not installed")
    def test_p12_subjects_reads_real_pkcs12(self):
        key, cert, p12 = (str(self.tmp / n) for n in ("k.pem", "c.pem", "x.p12"))
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                        "-days", "1", "-subj", "/CN=Apple Distribution: Test (3Q9X8JX23S)"],
                       check=True, capture_output=True)
        subprocess.run(["openssl", "pkcs12", "-export", "-inkey", key, "-in", cert, "-out", p12,
                        "-passout", "pass:pw"], check=True, capture_output=True)
        data = Path(p12).read_bytes()
        subjects = ss.p12_subjects(data, "pw")
        self.assertEqual(len(subjects), 1)
        self.assertIn("Apple Distribution: Test", subjects[0])
        with self.assertRaises(ss.InputError):
            ss.p12_subjects(data, "wrong")

    def test_msstore_validation_and_set(self):
        gh = FakeGh()
        secret = self.write("s", "client-secret~value\n")
        base = ["msstore", "--tenant-id", ISSUER, "--client-id", ISSUER, "--client-secret-file", secret,
                "--seller-id", "12345678"]
        code, _, _ = self.run_main(base + ["--app-id", "9NBLGGH4R315"], gh)
        self.assertEqual(code, 0)
        self.assertEqual(gh.secrets()["MSSTORE_CLIENT_SECRET"], "client-secret~value")
        self.assertEqual(len(gh.secrets()), 5)
        code, _, _ = self.run_main(base + ["--app-id", "placeholder"], FakeGh())
        self.assertEqual(code, 2)

    def test_status_reports_missing_names(self):
        gh = FakeGh(present=["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY", "MSSTORE_APP_ID"])
        code, out, _ = self.run_main(["status"], gh)
        self.assertEqual(code, 0)
        groups = json.loads(out)["groups"]
        self.assertTrue(groups["asc"]["configured"])
        self.assertFalse(groups["ios_p12"]["configured"])
        self.assertEqual(groups["msstore"]["missing"],
                         ["MSSTORE_TENANT_ID", "MSSTORE_CLIENT_ID", "MSSTORE_CLIENT_SECRET", "MSSTORE_SELLER_ID"])

    def test_gh_failure_exits_one(self):
        code, _, err = self.run_main(
            ["asc", "--key-id", "ABC123DEFG", "--issuer-id", ISSUER, "--p8", self.write("k.p8", P8)],
            FakeGh(fail_set=True))
        self.assertEqual(code, 1)
        self.assertIn("HTTP 403", err)


if __name__ == "__main__":
    unittest.main()
