"""Windows UI CI manifest and runner: ``tools/windows/ci_ui.py`` and ``journeys/ci-ui.json`` (issue #415).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from tools.windows import ci_ui


class ManifestTests(unittest.TestCase):
    """The committed manifest resolves, and bad entries are rejected before CI launches anything."""

    def test_committed_manifest_loads(self):
        entries = ci_ui.load()
        self.assertTrue(entries)
        for entry in entries:
            self.assertIsInstance(entry["issue"], int)

    def _write(self, entries: list[dict]) -> Path:
        folder = Path(tempfile.mkdtemp())
        (folder / "pages.json").write_text(json.dumps([{"name": "a"}, {"name": "b"}]), encoding="utf-8")
        manifest = folder / "ci-ui.json"
        manifest.write_text(json.dumps(entries), encoding="utf-8")
        return manifest

    def _entry(self, **changes) -> dict:
        return {"name": "x", "issue": 1, "pages": "pages.json", "only": ["a"], "sizes": ["compact"],
                "modes": ["normal"], **changes}

    def test_valid_entry_loads(self):
        self.assertEqual(ci_ui.load(self._write([self._entry()]))[0]["name"], "x")

    def test_rejects_bad_entries(self):
        for bad in (self._entry(pages="missing.json"), self._entry(only=["c"]), self._entry(sizes=["huge"]),
                    self._entry(modes=["text-300"]), self._entry(only=[]), {"name": "x"}):
            with self.assertRaises(ValueError, msg=bad):
                ci_ui.load(self._write([bad]))

    def test_rejects_duplicate_names(self):
        with self.assertRaises(ValueError):
            ci_ui.load(self._write([self._entry(), self._entry()]))

    def test_matrix_args(self):
        out, exe = Path("C:/out"), Path("C:/app.exe")
        args = ci_ui.matrix_args(self._entry(only=["a", "b"], sizes=["compact", "wide"]), "text-225", out, exe)
        self.assertEqual(args[args.index("--only") + 1], "a,b")
        self.assertEqual(args[args.index("--sizes") + 1], "compact,wide")
        self.assertEqual(args[args.index("--mode") + 1], "text-225")
        self.assertEqual(Path(args[args.index("--out") + 1]), out / "x")
        self.assertIn("--scan", args)
        self.assertNotIn("--live", args)
        self.assertNotIn("--scan", ci_ui.matrix_args(self._entry(scan=False), "normal", out, exe))


class RunnerTests(unittest.TestCase):
    """``main`` runs each entry once per mode and fails when any run fails."""

    def test_runs_every_mode_and_reports_failure(self):
        manifest = ManifestTests()._write([ManifestTests()._entry(modes=["normal", "text-225"])])
        calls: list[str] = []

        def fake(args):
            mode = args[args.index("--mode") + 1]
            calls.append(mode)
            return 1 if mode == "text-225" else 0

        with mock.patch.object(ci_ui.a11y_matrix, "main", side_effect=fake):
            code = ci_ui.main(["--out", tempfile.mkdtemp(), "--manifest", str(manifest)])
        self.assertEqual((calls, code), (["normal", "text-225"], 1))

    def test_modes_filter(self):
        manifest = ManifestTests()._write([ManifestTests()._entry(modes=["normal", "text-225"])])
        with mock.patch.object(ci_ui.a11y_matrix, "main", return_value=0) as run:
            code = ci_ui.main(["--out", tempfile.mkdtemp(), "--manifest", str(manifest), "--modes", "text-225"])
        self.assertEqual((run.call_count, code), (1, 0))


if __name__ == "__main__":
    unittest.main()
