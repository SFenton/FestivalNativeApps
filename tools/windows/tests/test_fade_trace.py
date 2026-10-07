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

    def test_only_new_ignores_close_and_skip_lines(self):
        self.assertEqual([], f.check_only_new(events("fade-close list=A start=0 since=300", "fade-skip list=A index=6"), "A"))


SCROLLED = ["fade-arm list=A start=0", "fade-play list=A index=0", "fade-play list=A index=1",
            "fade-close list=A start=0 since=420", "fade-skip list=A index=5", "fade-skip list=A index=6"]


class LoadThenScrollTests(unittest.TestCase):
    def test_parses_close_and_skip(self):
        parsed = f.parse(SCROLLED)
        self.assertEqual(["arm", "play", "play", "close", "skip", "skip"], [e.kind for e in parsed])
        self.assertEqual({"start": 0, "since": 420}, parsed[3].values)

    def test_passes_when_the_scroll_closes_the_window_and_old_rows_just_appear(self):
        self.assertEqual([], f.check_load_then_scroll(events(*SCROLLED), "A"))
        # A batch appended by the scroll may fade its own rows.
        self.assertEqual([], f.check_load_then_scroll(events(*SCROLLED, "fade-arm list=A start=10",
                                                             "fade-play list=A index=10"), "A"))

    def test_catches_the_r5_regression(self):
        # Old rows realized by the early scroll faded (the defect #274's review found).
        found = f.check_load_then_scroll(events(*SCROLLED, "fade-play list=A index=3"), "A")
        self.assertIn("old rows realized by the scroll faded in: [3]", found[0])
        # Old rows faded after a later batch re-armed: only the batch may fade.
        found = f.check_load_then_scroll(events(*SCROLLED, "fade-arm list=A start=10", "fade-play list=A index=7"), "A")
        self.assertIn("[7]", found[0])
        # A reload arm from 0 after the close does not license old rows either.
        self.assertTrue(f.check_load_then_scroll(events(*SCROLLED, "fade-arm list=A start=0",
                                                        "fade-play list=A index=0"), "A"))

    def test_fails_when_nothing_was_proven(self):
        self.assertIn("fade-close missing", f.check_load_then_scroll(events(*SCROLLED[:3]), "A")[0])
        late = [line.replace("since=420", "since=1500") for line in SCROLLED]
        self.assertIn("outside the 1000 ms window", f.check_load_then_scroll(events(*late), "A")[0])
        # A journey that lengthens the app's window measures the close against that window.
        self.assertEqual([], f.check_load_then_scroll(events(*late), "A", 4000))
        self.assertIn("no fade-skip", f.check_load_then_scroll(events(*SCROLLED[:4]), "A")[0])
        # Skips of a kept batch's rows are not old rows of the closed load window.
        self.assertIn("no fade-skip", f.check_load_then_scroll(
            events(*SCROLLED[:4], "fade-arm list=A start=10", "fade-skip list=A index=12"), "A")[0])
        # The load itself must still have faded its first screen.
        self.assertIn("no row faded", f.check_load_then_scroll(events(*SCROLLED[3:]), "A")[0])

    def test_a_batch_kept_by_the_close_may_fade_only_its_own_rows(self):
        kept = ["fade-arm list=A start=0", "fade-play list=A index=0", "fade-arm list=A start=0",
                "fade-close list=A start=10 since=300", "fade-skip list=A index=6"]
        self.assertEqual([], f.check_load_then_scroll(events(*kept, "fade-play list=A index=10"), "A"))
        self.assertIn("[4]", f.check_load_then_scroll(events(*kept, "fade-play list=A index=4"), "A")[0])


class RevealTests(unittest.TestCase):
    """Issue #307: the selected row is revealed after its own entrance, and the jump rushes the waiting fades."""

    STAGGER = ["fade-arm list=Rows start=0"] + [
        f"fade-play list=Rows index={i} delay={125 * (i + 1)} motion=1" for i in range(10)]

    def reveal(self, after=905, rushed=(7, 8, 9), **extra):
        values = {"index": 3, "faded": 1, "delay": 500, "after": after, "scrolled": 0, "rushed": len(rushed),
                  "motion": 1, **extra}
        line = "fade-reveal list=Rows " + " ".join(f"{k}={v}" for k, v in values.items())
        return [line] + [f"fade-rush list=Rows index={i} delay={125 * (i + 1)}" for i in rushed]

    def test_parses_reveal_and_rush_lines(self):
        parsed = events(*self.reveal())
        self.assertEqual(["reveal", "rush", "rush", "rush"], [e.kind for e in parsed])
        self.assertEqual(905, parsed[0].values["after"])

    def test_passes_after_the_entrance_with_the_rest_rushed(self):
        self.assertEqual([], f.check_reveal(events(*self.STAGGER, *self.reveal()), "Rows", 3, require_rush=True))

    def test_catches_a_reveal_before_the_rows_entrance(self):
        # The #307 review's regression: the jump runs while the row is still inside its stagger delay.
        found = f.check_reveal(events(*self.STAGGER, *self.reveal(after=40, rushed=range(10))), "Rows", 3)
        self.assertTrue(any("before its 500 ms delay" in x for x in found), found)
        # The jump scheduled ahead of the stagger: no play before the reveal, nothing waited for.
        found = f.check_reveal(events(*self.reveal(faded=0, delay=0, after=0, rushed=()), *self.STAGGER), "Rows", 3)
        self.assertTrue(any("never faded before" in x for x in found), found)
        self.assertTrue(any("faded=0" in x for x in found), found)

    def test_catches_rows_left_to_fade_after_the_jump(self):
        found = f.check_reveal(events(*self.STAGGER, *self.reveal(rushed=(8, 9))), "Rows", 3)
        self.assertIn("rows [7] kept their stagger delay", found[0])
        self.assertIn("rushed no fade", f.check_reveal(events(*self.STAGGER, *self.reveal(after=1300, rushed=())),
                                                       "Rows", 3, require_rush=True)[0])

    def test_catches_rushing_a_running_fade(self):
        found = f.check_reveal(events(*self.STAGGER, *self.reveal(rushed=(5, 7, 8, 9))), "Rows", 3)
        self.assertIn("[5] whose fades had already started", found[0])

    def test_catches_missing_double_scrolled_and_mismatched_reveals(self):
        self.assertIn("never revealed", f.check_reveal(events(*self.STAGGER), "Rows", 3)[0])
        self.assertIn("never revealed", f.check_reveal(events(*self.reveal(cancelled=1)), "Rows", 3)[0])
        twice = f.check_reveal(events(*self.STAGGER, *self.reveal(), *self.reveal(after=950, rushed=())), "Rows", 3)
        self.assertIn("revealed 2 times", twice[0])
        self.assertIn("scrolled=1", f.check_reveal(events(*self.STAGGER, *self.reveal(scrolled=1, rushed=())), "Rows", 3)[-1])
        lost = events(*self.STAGGER, *self.reveal()[:2])
        self.assertTrue(any("logged 1 rushes" in x for x in f.check_reveal(lost, "Rows", 3)))

    def test_reduce_motion_reveals_at_once_without_rushing(self):
        still = ["fade-arm list=Rows start=0", "fade-play list=Rows index=3 delay=500 motion=0"]
        immediate = self.reveal(faded=0, delay=0, after=0, rushed=(), motion=0)
        self.assertEqual([], f.check_reveal(events(*still, *immediate), "Rows", 3, motion=False))
        found = f.check_reveal(events(*still, *self.reveal()), "Rows", 3, motion=False)
        self.assertTrue(any("motion=1" in x for x in found), found)
        self.assertTrue(any("waited or rushed" in x for x in found), found)


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
