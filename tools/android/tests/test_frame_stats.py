"""Pure helpers of ``tools/android/frame_stats.py`` (no device needed).

Run: ``python -m unittest discover -s tools/android/tests`` from the repo root.
"""

import unittest

from tools.android import frame_stats as fs

HEADER = "Flags,IntendedVsync,Vsync,HandleInputStart,SyncQueued,SyncStart,FrameCompleted,"


def row(flags: int, intended: int, ui_ms: float, total_ms: float) -> str:
    """One framestats CSV line (ns) with the given UI-thread and total times."""
    vsync = intended + 1_000
    return (f"{flags},{intended},{vsync},{vsync},{vsync + int(ui_ms * 1e6)},"
            f"{vsync + int(ui_ms * 1e6) + 10},{intended + int(total_ms * 1e6)},")


DUMP = "\n".join([
    "Graphics info for pid 123 [com.festivalscoretracker.android]:",
    "Total frames rendered: 42",
    "Janky frames: 3 (7.14%)",
    "50th percentile: 9ms",
    "90th percentile: 21ms",
    "95th percentile: 30ms",
    "99th percentile: 57ms",
    "---PROFILEDATA---",
    HEADER,
    row(0, 1_000_000_000, 4.0, 12.0),
    row(0, 1_016_000_000, 12.0, 20.0),
    row(1, 1_032_000_000, 50.0, 60.0),
    "---PROFILEDATA---",
    "Total frames rendered: 99",
])


class FrameStatsTests(unittest.TestCase):
    """Parsing and metrics."""

    def test_summary_takes_first_block(self):
        summary = fs.parse_summary(DUMP)
        self.assertEqual(summary["frames"], 42)
        self.assertEqual(summary["janky"], 3)
        self.assertEqual(summary["p99_ms"], 57)

    def test_framestats_skips_flagged_frames(self):
        rows = fs.parse_framestats(DUMP)
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["IntendedVsync"], 1_000_000_000)

    def test_metrics_and_budgets(self):
        metrics = fs.frame_metrics(fs.parse_framestats(DUMP))
        self.assertEqual(metrics["frames"], 2)
        self.assertEqual(metrics["ui_p50_ms"], 4.0)
        self.assertEqual(metrics["ui_max_ms"], 12.0)
        self.assertEqual(metrics["ui_over_8.33ms"], 1)
        self.assertEqual(metrics["total_over_16.67ms"], 1)
        self.assertIn("| x | 2 |", fs.summary_line("x", metrics))

    def test_merge_and_percentile(self):
        seen = {}
        rows = fs.parse_framestats(DUMP)
        fs.merge_frames(seen, rows)
        fs.merge_frames(seen, rows)
        self.assertEqual(len(seen), 2)
        self.assertEqual(fs.percentile([], 0.5), 0.0)
        self.assertEqual(fs.percentile([1, 2, 3, 4], 0.5), 2)
        self.assertEqual(fs.percentile([1, 2, 3, 4], 0.99), 4)


if __name__ == "__main__":
    unittest.main()
