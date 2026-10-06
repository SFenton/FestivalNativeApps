"""``fade_trace.py``: fade-line parsing, the phase checks and the page wiring tripwire (issue #260).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root (CI: ``native.yml``).
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import fade_trace as f  # noqa: E402  (sibling module)

LOAD = ["startup=10.0", "fade-arm list=CardList start=0", "fade-play list=CardList index=0 delay=125 motion=1",
        "fade-play list=CardList index=1 delay=250 motion=1", "ui-frames count=3 max=4",
        "fade-play list=CardList index=2 delay=375 motion=0"]


def events(*lines: str) -> list[f.FadeEvent]:
    return f.parse(list(lines))


class ParseTests(unittest.TestCase):
    def test_reads_only_fade_lines(self):
        parsed = f.parse(LOAD)
        self.assertEqual(["arm", "play", "play", "play"], [e.kind for e in parsed])
        self.assertEqual({"index": 1, "delay": 250, "motion": 1}, parsed[2].values)
        self.assertEqual([0, 1, 2], f.plays(parsed, "CardList"))
        self.assertEqual([0], f.arms(parsed, "CardList"))
        self.assertEqual([], f.plays(parsed, "SongsList"))

    def test_ignores_malformed_lines(self):
        self.assertEqual([], f.parse(["fade-play", "fade-play list=", "fade-other list=A index=1", "fade-arm list=A start=x"]))


class CheckTests(unittest.TestCase):
    def test_load_passes_contiguous_stagger(self):
        self.assertEqual([], f.check_load(f.parse(LOAD), "CardList"))

    def test_load_fails_without_fades_or_with_gaps(self):
        self.assertIn("no row faded", f.check_load(events("fade-arm list=A start=0"), "A")[0])
        self.assertIn("expected each", f.check_load(events("fade-play list=A index=0", "fade-play list=A index=2"), "A")[0])
        self.assertTrue(f.check_load(events("fade-play list=A index=0", "fade-play list=A index=0"), "A"))

    def test_batch_passes_when_only_new_rows_fade(self):
        found = f.check_batch(events("fade-arm list=A start=16", "fade-play list=A index=16",
                                     "fade-arm list=A start=16", "fade-play list=A index=17"), "A")
        self.assertEqual([], found)

    def test_batch_catches_each_regression(self):
        # Restagger call deleted: no re-arm.
        self.assertIn("no re-arm", f.check_batch([], "A")[0])
        # Re-armed from 0 instead of the batch start.
        self.assertIn("no re-arm", f.check_batch(events("fade-arm list=A start=0", "fade-play list=A index=1"), "A")[0])
        # Re-armed but nothing of the batch faded.
        self.assertIn("no row of the batch", f.check_batch(events("fade-arm list=A start=16"), "A")[0])
        # Old rows fade again, or a row twice.
        self.assertIn("faded again", f.check_batch(events("fade-arm list=A start=16", "fade-play list=A index=16",
                                                          "fade-play list=A index=3"), "A")[0])
        self.assertIn("twice", f.check_batch(events("fade-arm list=A start=16", "fade-play list=A index=16",
                                                    "fade-play list=A index=16"), "A")[0])

    def test_only_new_allows_a_fresh_batch_but_no_replays(self):
        self.assertEqual([], f.check_only_new([], "A"))
        self.assertEqual([], f.check_only_new(events("fade-arm list=A start=16", "fade-play list=A index=16"), "A"))
        self.assertTrue(f.check_only_new(events("fade-play list=A index=3"), "A"))
        self.assertTrue(f.check_only_new(events("fade-arm list=A start=16", "fade-play list=A index=4"), "A"))
        self.assertEqual([], f.check_only_new(events("fade-play list=B index=3"), "A"))

    def test_none(self):
        self.assertEqual([], f.check_none(events("fade-arm list=A start=0")))
        self.assertTrue(f.check_none(events("fade-play list=A index=0")))


class RunPhasesTests(unittest.TestCase):
    def test_each_phase_sees_only_its_own_lines(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / "perf.log"
            writes = iter([LOAD, ["fade-arm list=CardList start=10", "fade-play list=CardList index=10"], []])
            driven = []

            def drive(steps):
                driven.append(steps)
                with log.open("a", encoding="utf-8") as handle:
                    handle.writelines(line + "\n" for line in next(writes))

            failures = f.run_phases(drive, log, [
                f.Phase("load", ["a"], lambda e: f.check_load(e, "CardList")),
                f.Phase("more", ["b"], lambda e: f.check_batch(e, "CardList")),
                f.Phase("idle", ["c"], f.check_none),
            ])
        self.assertEqual([], failures)
        self.assertEqual([["a", f.SETTLE_STEP], ["b", f.SETTLE_STEP], ["c", f.SETTLE_STEP]], driven)

    def test_failures_name_their_phase(self):
        with tempfile.TemporaryDirectory() as folder:
            failures = f.run_phases(lambda steps: None, Path(folder) / "missing.log",
                                    [f.Phase("load", [], lambda e: f.check_load(e, "CardList"))])
        self.assertEqual(["load: CardList: no row faded in at load"], failures)


class WiringTests(unittest.TestCase):
    """CI cannot run WinUI journeys: fail when a page drops the call a fade journey exercises."""

    def test_page_wiring_is_in_place(self):
        self.assertEqual([], f.wiring_problems())

    def test_a_deleted_or_commented_call_is_reported(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for rel, _, _ in f.WIRING:
                source = (f.ROOT / rel).read_text(encoding="utf-8")
                (root / rel).parent.mkdir(parents=True, exist_ok=True)
                (root / rel).write_text(source, encoding="utf-8")
            suggestions = root / f.WIRING[0][0]
            text = suggestions.read_text(encoding="utf-8")
            suggestions.write_text(text.replace("ViewModel.CardsAdded +=", "// ViewModel.CardsAdded +="), encoding="utf-8")
            search = root / f.WIRING[2][0]
            text = search.read_text(encoding="utf-8")
            search.write_text(text.replace("FadeIn.Restagger(section", "Noop(section"), encoding="utf-8")
            problems = f.wiring_problems(root)
        self.assertEqual(2, len(problems))
        self.assertIn("SuggestionsPage", problems[0])
        self.assertIn("SearchPage", problems[1])


if __name__ == "__main__":
    unittest.main()
