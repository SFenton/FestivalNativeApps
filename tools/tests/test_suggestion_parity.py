"""Exercise the Suggestions parity checks (rule R1, #656) without compiling Swift."""

import contextlib
import copy
import importlib.util
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "run_parity", ROOT / "tools" / "windows" / "suggestion_parity" / "run_parity.py")
run_parity = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(run_parity)


def output(*categories: dict) -> dict:
    """Wrap categories as one single-page scenario output."""
    return {"scenarios": [{"name": "s", "pages": [list(categories)], "resetPages": []}]}


def card(key: str, title: str, *rivals: tuple[str, str]) -> dict:
    """A category whose rows carry the given (account, name) rival annotations."""
    return {"key": key, "title": title,
            "songs": [{"id": f"r{n}", "rivalAccountId": a, "rivalName": name} for n, (a, name) in enumerate(rivals)]}


def quietly(function, *args):
    """Call ``function`` with stdout captured; return (result, printed text)."""
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        result = function(*args)
    return result, buffer.getvalue()


class NamedRivalRuleTests(unittest.TestCase):
    """Rule R1: a card that names one rival lists only that rival."""

    def test_single_rival_climb_past_passes(self):
        """Every row on the named rival's account, title naming it."""
        produced = output(card("song_rival_pct_push", "Climb Past Alpha", ("a", "Alpha"), ("a", "Alpha")))
        problems, counts, names, largest = run_parity.named_rival_violations(produced)
        self.assertEqual(problems, [])
        self.assertEqual((counts, names, largest), ({"song_rival_pct_push": 1}, {"Alpha"}, 2))

    def test_climb_past_listing_another_rival_fails(self):
        """The reported bug: "Climb Past Alpha" with a Beta row."""
        produced = output(card("song_rival_pct_push", "Climb Past Alpha", ("a", "Alpha"), ("b", "Beta")))
        self.assertEqual(len(run_parity.named_rival_violations(produced)[0]), 1)

    def test_title_must_name_the_rows_rival(self):
        """Rows all about Beta under an Alpha title also break the rule, for each named family."""
        for key, template in run_parity.NAMED_RIVAL_TITLES.items():
            with self.subTest(key=key):
                produced = output(card(key, template.format("Alpha"), ("b", "Beta")))
                self.assertEqual(len(run_parity.named_rival_violations(produced)[0]), 1)

    def test_mixed_cards_without_a_named_rival_are_ignored(self):
        """Battleground and Stale Songs stay mixed by design."""
        produced = output(card("song_rival_stale", "Stale Songs Your Rivals Are Beating You On",
                               ("a", "Alpha"), ("b", "Beta")))
        self.assertEqual(run_parity.named_rival_violations(produced), ([], {}, set(), 0))

    def test_committed_named_rival_expected_output_is_discriminating(self):
        """The two-rival fixture's Apple output covers every family, both rivals and multi-row cards."""
        produced = json.loads(run_parity.NAMED_EXPECTED.read_text(encoding="utf-8"))
        problems, counts, names, largest = run_parity.named_rival_violations(produced)
        self.assertEqual(problems, [])
        self.assertEqual(set(counts), set(run_parity.NAMED_RIVAL_TITLES))
        self.assertEqual(names, {"Alpha Rival", "Beta Rival"})
        self.assertGreaterEqual(largest, 2)
        _, printed = quietly(run_parity.check_named_rival, produced, produced)
        self.assertNotIn("FAIL", printed)


class SharedBaselineTests(unittest.TestCase):
    """The shared Windows/Android baseline and the pinned pending port."""

    def setUp(self):
        """Point the checker at a temporary baseline and pending record."""
        holder = tempfile.TemporaryDirectory()
        self.addCleanup(holder.cleanup)
        self.tmp = Path(holder.name)
        self.baseline = output(card("song_rival_pct_push", "Climb Past Alpha", ("a", "Alpha"), ("b", "Beta")))
        self.apple = output(card("song_rival_pct_push", "Climb Past Alpha", ("a", "Alpha")))
        (self.tmp / "expected.json").write_text(run_parity.canonical(self.baseline), encoding="utf-8")
        self.patches = [mock.patch.object(run_parity, "SHARED_EXPECTED", self.tmp / "expected.json"),
                        mock.patch.object(run_parity, "PENDING", self.tmp / "pending-ports.json")]
        for patch in self.patches:
            patch.start()

    def tearDown(self):
        """Undo the path patches."""
        for patch in self.patches:
            patch.stop()

    def pin(self, produced: dict):
        """Write a pending record pinning ``produced``."""
        record = {"rule": "R1", "awaiting": ["windows"], "appleOutputSha256": run_parity.sha256(produced)}
        run_parity.PENDING.write_text(json.dumps(record), encoding="utf-8")

    def test_mismatch_without_pending_record_fails(self):
        """No pending port: any difference is a failure."""
        self.assertFalse(quietly(run_parity.check_shared_baseline, self.apple, False)[0])

    def test_pinned_pending_port_passes_and_reports_old_violations(self):
        """The pinned Apple output passes; the report counts the baseline's mixed cards."""
        self.pin(self.apple)
        ok, printed = quietly(run_parity.check_shared_baseline, self.apple, False)
        self.assertTrue(ok)
        self.assertIn("PENDING PORT", printed)
        self.assertIn("(1 named-rival cards there list another rival)", printed)

    def test_other_apple_drift_fails_despite_pending_record(self):
        """An Apple change beyond the pinned output is caught."""
        self.pin(self.apple)
        drifted = copy.deepcopy(self.apple)
        drifted["scenarios"][0]["pages"][0][0]["title"] = "Climb Past Alpha!"
        self.assertFalse(quietly(run_parity.check_shared_baseline, drifted, False)[0])

    def test_strict_ignores_the_pending_record(self):
        """--strict requires the baseline itself to match."""
        self.pin(self.apple)
        self.assertFalse(quietly(run_parity.check_shared_baseline, self.apple, True)[0])

    def test_regenerated_baseline_passes_and_flags_a_stale_record(self):
        """After the port regenerates the baseline, a leftover record is reported."""
        self.pin(self.apple)
        ok, printed = quietly(run_parity.check_shared_baseline, self.baseline, False)
        self.assertTrue(ok)
        self.assertIn("stale", printed)

    def test_committed_pending_record_pins_a_named_rival_rule(self):
        """The committed record (deleted once the ports regenerate the baseline) is well formed."""
        path = ROOT / "tools/windows/suggestion_parity/pending-ports.json"
        if not path.exists():
            self.skipTest("no pending port")
        record = json.loads(path.read_text(encoding="utf-8"))
        self.assertTrue(record["rule"] and record["awaiting"])
        self.assertEqual(record["baseline"], "windows/Festival.Core.Tests/Fixtures/suggestions-parity.expected.json")
        self.assertRegex(record["appleOutputSha256"], r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
