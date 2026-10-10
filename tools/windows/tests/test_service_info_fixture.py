"""Settings Service Info tooling: ``service_info_fixture.py`` and the ``journeys/a11y-settings-service-info.json`` pages.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import json
import sys
import threading
import time
import unittest
import urllib.error
import urllib.request
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import a11y_matrix as m  # noqa: E402  (sibling module)
import mock_service  # noqa: E402
import service_info_fixture as f  # noqa: E402
from tools.windows import uiwin  # noqa: E402

PAGES = Path(__file__).resolve().parents[1] / "journeys" / "a11y-settings-service-info.json"


def attempts(body: dict) -> tuple[int, int]:
    """``(attempted, unavailable)`` of a discovery body."""
    progress = body["currentUpdate"]["attemptProgress"]
    return progress["attemptedThisPass"], progress["retryableUnavailableThisPass"]


class ResponseTests(unittest.TestCase):
    """Each state answers the body the card needs, without touching the shared mock constants."""

    def test_idle_is_the_mock_idle_body(self):
        self.assertEqual(f.response("idle", 0), (200, mock_service.SERVICE_INFO_IDLE))

    def test_loading_holds_only_the_first_read_then_answers_idle(self):
        self.assertEqual([f.response("loading", read) for read in range(3)], [(200, mock_service.SERVICE_INFO_IDLE)] * 3)
        self.assertEqual([f.delay("loading", read) for read in range(3)], [f.LOADING_DELAY_SECONDS, 0.0, 0.0])
        for state in f.STATES:
            if state != "loading":
                self.assertEqual(f.delay(state, 0), 0.0, state)

    def test_discovery_is_the_mock_discovery_body(self):
        status, body = f.response("discovery", 3)
        self.assertEqual((status, body), (200, mock_service.SERVICE_INFO_DISCOVERY))
        body["currentUpdate"]["phasePercent"] = -1
        self.assertEqual(mock_service.SERVICE_INFO_DISCOVERY["currentUpdate"]["phasePercent"], 24.8, "bodies are copies")

    def test_monotonic_steps_down_then_up_and_repeats_the_last(self):
        seen = [attempts(f.response("monotonic", read)[1]) for read in range(6)]
        self.assertEqual(seen, [(1310, 70), (1200, 60), (1200, 60), (1400, 80), (1400, 80), (1400, 80)])
        self.assertLess(seen[1][0], seen[0][0], "the second read is a lower (older) count the card must not show")
        body = f.response("monotonic", 1)[1]["currentUpdate"]
        self.assertEqual((body["phaseId"], body["phaseAttempt"]), ("post.registered_player_band_discovery", 1),
                         "one phase attempt, so the reducer keeps the higher count")

    def test_indeterminate_has_no_total_and_no_attempts(self):
        current = f.response("indeterminate", 0)[1]["currentUpdate"]
        self.assertEqual((current["status"], current["phaseId"]), ("updating", "scrape.leaderboards"))
        self.assertIsNone(current["unitsTotal"])
        self.assertIsNone(current["phasePercent"])
        self.assertNotIn("attemptProgress", current)
        self.assertIn("attemptProgress", mock_service.SERVICE_INFO_DISCOVERY["currentUpdate"])

    def test_switching_goes_unknown_then_exact_then_unknown_with_later_progress(self):
        """Issue #556: each read is newer (the reducer ignores an older read of one operation as stale)."""
        reads = [f.response("switching", read)[1]["currentUpdate"] for read in range(0, 4 * f.SWITCHING_READS, f.SWITCHING_READS)]
        self.assertEqual([(c["phaseId"], c["phasePercent"], c["unitsTotalFinal"]) for c in reads],
                         [("scrape.leaderboards", None, False), ("scrape.leaderboards", 40.0, True),
                          ("post.compute_rankings", None, False), ("post.compute_rankings", None, False)])
        self.assertEqual((reads[1]["unitsCompleted"], reads[1]["unitsTotal"]), (40, 100))
        times = [c["lastProgressAt"] for c in reads[:3]]
        self.assertEqual(times, sorted(set(times)), "strictly later progress times")
        self.assertLess(reads[1]["phaseOrdinal"], reads[2]["phaseOrdinal"], "a forward phase, not a restart")
        self.assertEqual({c["operationId"] for c in reads}, {"fixture-op-2"})
        self.assertTrue(all("attemptProgress" not in c for c in reads))
        for step in range(3):
            first = step * f.SWITCHING_READS
            self.assertEqual(f.response("switching", first), f.response("switching", first + f.SWITCHING_READS - 1), step)

    def test_failed_stopped_unpublished(self):
        self.assertEqual(f.response("failed", 0)[1]["currentUpdate"]["status"], "failed")
        self.assertEqual(f.response("stopped", 0)[1]["workerStatus"]["status"], "offline")
        unpublished = f.response("unpublished", 0)[1]
        self.assertIsNone(unpublished["lastCompletedUpdate"])
        self.assertIsNone(unpublished["publication"]["publishedAt"])
        self.assertIsNotNone(mock_service.SERVICE_INFO_IDLE["lastCompletedUpdate"])

    def test_unavailable_is_a_503(self):
        self.assertEqual(f.response("unavailable", 0)[0], 503)

    def test_unknown_state_raises(self):
        with self.assertRaises(ValueError):
            f.response("nope", 0)
        with self.assertRaises(ValueError):
            f.ServiceInfoState("nope")

    def test_every_state_answers(self):
        for state in f.STATES:
            self.assertIn(f.response(state, 0)[0], (200, 503), state)


class OptionTests(unittest.TestCase):
    """The wrapper's flags are split from the mock's."""

    def test_parse_options(self):
        options, rest = f.parse_options(["--port", "0", "--service-info", "monotonic"])
        self.assertEqual((options.service_info, rest), ("monotonic", ["--port", "0"]))
        options, rest = f.parse_options([])
        self.assertEqual((options.service_info, rest), ("idle", []))


class FixtureServerTests(unittest.TestCase):
    """The patched handler over a real loopback socket."""

    def serve(self, state: f.ServiceInfoState) -> str:
        original = mock_service.FixtureHandler.do_GET
        f.install(state)
        server = mock_service.FixtureServer(("127.0.0.1", 0), mock_service.FixtureHandler)
        threading.Thread(target=server.serve_forever, daemon=True).start()

        def stop():
            server.shutdown()
            server.server_close()
            mock_service.FixtureHandler.do_GET = original

        self.addCleanup(stop)
        return f"http://127.0.0.1:{server.server_port}"

    @staticmethod
    def get(url: str) -> tuple[int, dict]:
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                return response.status, json.loads(response.read())
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read())

    def test_monotonic_sequence_over_http(self):
        base = self.serve(f.ServiceInfoState("monotonic"))
        seen = [attempts(self.get(base + f.ROUTE)[1])[0] for _ in range(4)]
        self.assertEqual(seen, [1310, 1200, 1200, 1400])

    def test_idle_over_http(self):
        status, body = self.get(self.serve(f.ServiceInfoState("idle")) + f.ROUTE)
        self.assertEqual((status, body["currentUpdate"]["status"]), (200, "idle"))

    def test_loading_holds_the_first_read_over_http(self):
        base = self.serve(f.ServiceInfoState("loading"))
        times = []
        with mock.patch.object(f, "LOADING_DELAY_SECONDS", 0.5):
            for _ in range(2):
                start = time.monotonic()
                status, body = self.get(base + f.ROUTE)
                times.append(time.monotonic() - start)
                self.assertEqual((status, body["currentUpdate"]["status"]), (200, "idle"))
        self.assertGreaterEqual(times[0], 0.45)
        self.assertLess(times[1], 0.4)

    def test_unavailable_and_other_routes(self):
        base = self.serve(f.ServiceInfoState("unavailable"))
        self.assertEqual(self.get(base + f.ROUTE)[0], 503)
        status, body = self.get(base + "/api/songs")
        self.assertEqual(status, 200)
        self.assertIn("songs", body)


class PagesTests(unittest.TestCase):
    """Every page step parses, needs no mouse input, and every state has a page."""

    def test_pages_parse(self):
        pages = json.loads(PAGES.read_text(encoding="utf-8"))
        states = {p["fixture"][2] for p in pages if p.get("fixture")}
        self.assertEqual(states, set(f.STATES))
        for page in pages:
            if "fixture" in page:
                self.assertEqual(page["fixture"][:2], ["service_info_fixture.py", "--service-info"], page["name"])
            for step in m.page_steps(page, "medium", Path("out"), "", True, 10):
                parsed = uiwin.parse_step(step)
                self.assertNotIn(parsed["verb"], {"click", "rightclick", "hover", "scroll"}, f"{page['name']}: {step}")

    def test_live_pages_need_no_fixture_state(self):
        pages = json.loads(PAGES.read_text(encoding="utf-8"))
        live = {p["name"] for p in m.live_pages(pages)}
        self.assertEqual(live, {"settings-service-info-live", "settings-service-info-live-film"})

    def test_timed_page_runs_once(self):
        pages = {p["name"]: p for p in json.loads(PAGES.read_text(encoding="utf-8"))}
        for name in ("settings-service-info-monotonic", "settings-service-info-switching"):
            page = pages[name]
            self.assertEqual(m.page_sizes(page, ["compact", "medium", "wide"], "normal"), ["compact"], name)
            self.assertEqual(m.mode_pages([page], "text-200"), [], name)

    def test_unknown_total_pages_assert_the_sweep_by_motion_mode(self):
        """Issue #556: the bar sweeps with motion, holds a still track under reduced motion or a hidden window."""
        pages = {p["name"]: p for p in json.loads(PAGES.read_text(encoding="utf-8"))}
        sweeping, still = pages["settings-service-info-indeterminate"], pages["settings-service-info-indeterminate-still"]
        bar = "assertstatus:raw=fst.settings.service-info.bar|"
        self.assertIn(bar + "sweeping@10", sweeping["after_ready"])
        self.assertIn(bar + "still@10", still["after_ready"])
        for mode in ("no-animations", "app-reduced"):
            self.assertEqual(m.mode_pages([sweeping], mode), [], mode)
            self.assertEqual(m.mode_pages([still], mode), [still], mode)
        self.assertEqual(m.mode_pages([still], "normal"), [])
        self.assertEqual(m.mode_pages([sweeping], "normal"), [sweeping])
        statuses = [s.split("|", 1)[1] for s in pages["settings-service-info-switching"]["after_ready"] if s.startswith(bar)]
        self.assertEqual(statuses, ["sweeping@15", "determinate@15", "sweeping@15", "held not-visible@10", "sweeping@10"])
        for page in (sweeping, still):
            self.assertTrue(any(s.startswith("scan:") for s in page["after_ready"]), page["name"])
            self.assertTrue(any(s.startswith("assertorder:") for s in page["after_ready"]), page["name"])

    def test_monotonic_page_proves_each_accepted_count_is_announced_once(self):
        """Issue #275: listening starts before Settings' first read; kept-back lower reads announce nothing."""
        monotonic = {p["name"]: p for p in json.loads(PAGES.read_text(encoding="utf-8"))}["settings-service-info-monotonic"]
        self.assertEqual(monotonic["tab"], "songs")
        steps = monotonic["after_ready"]
        self.assertEqual(steps[:2], ["listen:announcements", "key:ctrl+comma"])
        announced = [uiwin.parse_step(s)["text"] for s in steps if s.startswith("assertannounced:")]
        self.assertEqual(len(announced), 2)
        self.assertIn("1,310 attempted this pass", announced[0])
        self.assertIn("1,400 attempted this pass", announced[1])
        self.assertEqual(steps[-3:], ["assertannouncedcount:1|~1,310 attempted this pass",
                                      "assertannouncedcount:1|~1,400 attempted this pass",
                                      "assertannouncedcount:0|~1,200 attempted this pass"])

    def test_loading_page_opens_settings_itself_once_per_run(self):
        """Loading only precedes the first read after Settings opens, and the fixture holds only its first read."""
        loading = {p["name"]: p for p in json.loads(PAGES.read_text(encoding="utf-8"))}["settings-service-info-loading"]
        self.assertEqual(loading["tab"], "songs")
        self.assertEqual(m.page_sizes(loading, ["compact", "medium", "wide"], "hc-desert"), ["compact"])
        timeout_ms = int(loading["env"]["FST_DEBUG_SERVICE_INFO_TIMEOUT_MS"])
        self.assertGreaterEqual(timeout_ms, f.LOADING_DELAY_SECONDS * 1000 + 3000,
                                "the lengthened app timeout outlasts the held read with margin")
        self.assertGreater(f.LOADING_DELAY_SECONDS, 3.0, "longer than the default timeout the page lengthens")
        steps = loading["after_ready"]
        self.assertEqual(steps[0], "key:ctrl+comma")
        scan = next(i for i, s in enumerate(steps) if s.startswith("scan:"))
        self.assertIn("assertname:id=fst.settings.service-info.state|Loading", steps[:scan])
        self.assertIn("waitfor:raw=fst.settings.service-info.spinner", steps[:scan])
        self.assertEqual(steps[scan + 1], "assertname:id=fst.settings.service-info.process@0|Loading",
                         "the scan finished while the card was still Loading")

    def test_stacked_page_runs_only_at_large_text(self):
        pages = json.loads(PAGES.read_text(encoding="utf-8"))
        names = {p["name"] for p in m.mode_pages(pages, "normal")}
        self.assertNotIn("settings-service-info-stacked", names)
        self.assertIn("settings-service-info-stacked", {p["name"] for p in m.mode_pages(pages, "text-200")})

    def test_state_row_layout_pages_check_measured_fit_both_ways(self):
        """#539: the state row stacks by measured fit, so a compact window stacks at 225% and a medium one stays inline."""
        pages = {p["name"]: p for p in json.loads(PAGES.read_text(encoding="utf-8"))}
        stacked, inline = pages["settings-service-info-stacked"], pages["settings-service-info-inline-large-text"]
        self.assertEqual((stacked["sizes"], stacked["modes"][0]), (["compact"], "text-225"))
        self.assertEqual((inline["sizes"], inline["modes"][0]), (["medium"], "text-225"))
        self.assertIn("assertbelow:id=fst.settings.service-info.process|id=fst.settings.service-info.state", stacked["after_ready"])
        self.assertIn("assertbelow:id=fst.settings.service-info.state|id=fst.settings.service-info.process", inline["after_ready"])
        for page in (stacked, inline):
            self.assertIn("assertapart:name=Leaderboard Service State&class=TextBlock|id=fst.settings.service-info.process",
                          page["after_ready"])


if __name__ == "__main__":
    unittest.main()
