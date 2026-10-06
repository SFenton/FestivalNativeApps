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
        monotonic = pages["settings-service-info-monotonic"]
        self.assertEqual(m.page_sizes(monotonic, ["compact", "medium", "wide"], "normal"), ["compact"])
        self.assertEqual(m.mode_pages([monotonic], "text-200"), [])

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


if __name__ == "__main__":
    unittest.main()
