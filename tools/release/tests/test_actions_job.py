"""Unit tests for ``tools/release/actions_job.py`` and the Actions SHA lookup in ``fst_release.py``."""

import base64
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from tools.release import actions_job as aj
from tools.release import fst_release as fr


class FakeMain:
    """Stands in for ``fst_release.main``: records argv/stdin and prints a canned document."""

    def __init__(self, code=0, doc=None):
        self.code = code
        self.doc = doc if doc is not None else {"ok": True}
        self.calls = []

    def __call__(self, argv, env=None, stdin=None):
        self.calls.append({"argv": argv, "stdin": stdin.read() if stdin else None})
        print(json.dumps(self.doc))
        return self.code


class RunJobTests(unittest.TestCase):
    def test_ios_submit_blocked_unless_review_enabled(self):
        fake = FakeMain()
        result = aj.run_job("ios", "submit", "42", "notes", False, {}, main=fake)
        self.assertEqual((result["exit_code"], result["output"]), (4, {"blocked": "app_store_review_disabled"}))
        self.assertEqual(fake.calls, [])
        result = aj.run_job("ios", "submit", "42", "notes", False, {"FST_APPSTORE_REVIEW_ENABLED": "true"},
                            main=fake, marker_lookup=lambda *_a: None)
        self.assertEqual(result["exit_code"], 0)
        self.assertEqual(fake.calls[0]["argv"], ["ios", "submit", "--build", "42", "--notes-stdin"])
        self.assertEqual(fake.calls[0]["stdin"], "notes")

    def test_ios_submit_uses_marker_notes_and_baseline(self):
        fake = FakeMain()
        marker = {"version": "2610.02", "version_tag": "ios/v2610.02", "sha": "s", "whats_new_baseline": "2610.01",
                  "store_notes": "• Faster songs."}
        result = aj.run_job("ios", "submit", "57", "orchestrator notes", False,
                            {"FST_APPSTORE_REVIEW_ENABLED": "true"}, main=fake,
                            marker_lookup=lambda p, b, e: marker if (p, b) == ("ios", "57") else None)
        self.assertEqual(fake.calls[0]["argv"], ["ios", "submit", "--build", "57", "--notes-stdin",
                                                 "--whats-new-baseline", "2610.01"])
        self.assertEqual(fake.calls[0]["stdin"], "• Faster songs.")
        self.assertEqual(result["marker"]["version_tag"], "ios/v2610.02")
        first = dict(marker, whats_new_baseline=None, store_notes="")
        aj.run_job("ios", "submit", "57", "n", False, {"FST_APPSTORE_REVIEW_ENABLED": "true"}, main=fake,
                   marker_lookup=lambda *_a: first)
        self.assertEqual(fake.calls[1]["argv"][-2:], ["--whats-new-baseline", "none"])
        self.assertEqual(fake.calls[1]["stdin"], "n")

    def test_stale_refusal_dispatches_one_rebuild(self):
        fake = FakeMain(code=3, doc={"refused": "stale_whats_new"})
        marker = {"version_tag": "ios/v2610.02", "whats_new_baseline": None}
        gh_calls = []

        def runner(args):
            gh_calls.append(args)
            return "[]"
        result = aj.run_job("ios", "submit", "57", "n", False, {"FST_APPSTORE_REVIEW_ENABLED": "true"},
                            main=fake, marker_lookup=lambda *_a: marker, runner=runner)
        self.assertEqual(result["rebuild"], {"dispatched": True, "version_tag": "ios/v2610.02"})
        self.assertEqual(gh_calls[-1], ["workflow", "run", "ios-release-build.yml", "--ref", "master",
                                        "-f", "version_tag=ios/v2610.02", "-f", "rebuild_reason=stale_whats_new"])
        busy = aj.dispatch_rebuild("ios", marker, lambda args: '[{"databaseId": 1}]')
        self.assertEqual(busy["reason"], "build_queued")
        self.assertEqual(aj.dispatch_rebuild("ios", {}, runner)["reason"], "no_version_tag")

        def broken(args):
            raise RuntimeError("gh down")
        self.assertEqual(aj.dispatch_rebuild("ios", marker, broken)["reason"], "error")

    def test_windows_submit_and_status_argv(self):
        fake = FakeMain(code=3, doc={"refused": "Certification"})
        result = aj.run_job("windows", "submit", "0.1.9.0", "n", True, {"GITHUB_SHA": "abc"}, main=fake)
        self.assertEqual(fake.calls[0]["argv"],
                         ["windows", "submit", "--build", "0.1.9.0", "--notes-stdin", "--dry-run"])
        self.assertEqual((result["exit_code"], result["output"], result["sha"]), (3, {"refused": "Certification"}, "abc"))
        aj.run_job("windows", "status", None, "", False, {}, main=fake)
        self.assertEqual(fake.calls[1]["argv"], ["windows", "status", "--json"])

    def test_rejects_bad_build_and_notes(self):
        with self.assertRaises(ValueError):
            aj.tool_argv("windows", "submit", "1; rm -rf /", False)
        with self.assertRaises(ValueError):
            aj.tool_argv("windows", "submit", None, False)
        with self.assertRaises(ValueError):
            aj.decode_notes("***")
        self.assertEqual(aj.decode_notes(base64.b64encode("Fixes ✓".encode()).decode()), "Fixes ✓")


class MainTests(unittest.TestCase):
    def run_main(self, argv, env):
        out = io.StringIO()
        with redirect_stdout(out):
            code = aj.main(argv, env=env)
        return code, out.getvalue()

    def test_writes_result_and_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            out, summary = Path(tmp) / "result.json", Path(tmp) / "summary.md"
            env = {"HOME": tmp, "GITHUB_STEP_SUMMARY": str(summary), "GITHUB_SHA": "f" * 40}
            code, _ = self.run_main(["--platform", "windows", "--command", "status", "--out", str(out)], env)
            self.assertEqual(code, 0)  # blocked (no credentials) is a quiet exit
            result = json.loads(out.read_text())
            self.assertEqual(result["exit_code"], 4)
            self.assertEqual(result["output"]["blocked"], "missing_store_credentials")
            self.assertIn("store-release windows status", summary.read_text())

    def test_invalid_input_fails_loudly(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "result.json"
            code, _ = self.run_main(["--platform", "windows", "--command", "submit", "--build", "x",
                                     "--out", str(out)], {"HOME": tmp})
            self.assertEqual(code, 1)
            self.assertIn("numeric", json.loads(out.read_text())["output"]["error"])


class ArtifactShaTests(unittest.TestCase):
    def test_head_sha_from_exact_artifact(self):
        calls = []

        def runner(args):
            calls.append(args)
            return json.dumps({"artifacts": [{"name": "fst-ios-build_42", "workflow_run": {"head_sha": "d" * 40}}]})
        self.assertEqual(fr.artifact_head_sha("fst-ios-build_42", "o/r", runner), "d" * 40)
        self.assertIn("name=fst-ios-build_42", calls[0][1])
        self.assertIsNone(fr.artifact_head_sha("fst-ios-build_43", "o/r", runner))

    def test_lookup_failures_are_none(self):
        def broken(args):
            raise RuntimeError("gh down")
        self.assertIsNone(fr.artifact_head_sha("x", "o/r", broken))


if __name__ == "__main__":
    unittest.main()
