"""Pure logic of ``tools/android/cdp.py`` (shared installed-PWA lab).

Covers WebSocket framing, key parsing, step parsing/splitting, animation and
motion summaries and video sizing without a browser.
Run: ``python -m unittest discover -s tools/android/tests`` from the repo root.
"""

import struct
import tempfile
import unittest
from pathlib import Path

from tools.android import cdp


class WebSocketTests(unittest.TestCase):
    """RFC 6455 helpers."""

    def test_accept_key_matches_rfc_example(self):
        self.assertEqual(cdp.ws_accept_key("dGhlIHNhbXBsZSBub25jZQ=="),
                         "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

    def test_frames_are_masked_with_length_forms(self):
        mask = b"\x01\x02\x03\x04"
        small = cdp.encode_frame(b"hi", mask=mask)
        self.assertEqual(small[:2], bytes([0x81, 0x80 | 2]))
        self.assertEqual(bytes(b ^ mask[i % 4] for i, b in enumerate(small[6:])), b"hi")
        medium = cdp.encode_frame(b"x" * 300, mask=mask)
        self.assertEqual(medium[1], 0x80 | 126)
        self.assertEqual(struct.unpack(">H", medium[2:4])[0], 300)
        large = cdp.encode_frame(b"x" * 70000, 0x2, mask=mask)
        self.assertEqual((large[0], large[1]), (0x82, 0x80 | 127))
        self.assertEqual(struct.unpack(">Q", large[2:10])[0], 70000)


class StepTests(unittest.TestCase):
    """Step splitting, parsing and placeholders."""

    def test_split_keeps_semicolons_out_of_comments(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "a.steps"
            path.write_text("# note; not a step\nroute:/songs; wait:1  # trailing; comment\n\n",
                            encoding="utf-8")
            self.assertEqual(cdp.split_steps("click:text=A", str(path)),
                             ["click:text=A", "route:/songs", "wait:1"])

    def test_parse_and_optional(self):
        self.assertEqual(cdp.parse_step("?click:testid=fre-close@1"),
                         ("click", "testid=fre-close@1"))
        self.assertTrue(cdp.is_optional("?click:x"))
        self.assertEqual(cdp.parse_step("shot:a.png", {"shot": "path"}), ("shot", "a.png"))
        for bad in ("fly:away", "wait:soon", "scroll:far", "key:hyper", "anims:maybe", "click:"):
            with self.assertRaises(ValueError):
                cdp.parse_step(bad)

    def test_placeholders(self):
        self.assertEqual(cdp.expand_placeholders(["shot:{out}/a.png"], {"out": "C:/x"}),
                         ["shot:C:/x/a.png"])

    def test_keys(self):
        self.assertEqual(cdp.parse_key("alt+left"), (1, "ArrowLeft", "ArrowLeft", 37))
        self.assertEqual(cdp.parse_key("ctrl+shift+a"), (10, "a", "KeyA", 65))
        self.assertEqual(cdp.parse_key("7")[2], "Digit7")
        with self.assertRaises(ValueError):
            cdp.parse_key("hyper+x")


class SummaryTests(unittest.TestCase):
    """Animation, network and motion summaries."""

    def test_animation_summary(self):
        events = [{"method": "Animation.animationStarted", "params": {"animation": {
            "type": "CSSAnimation", "name": "fadeInUp", "source": {
                "duration": 400, "delay": 300.04, "easing": "linear", "iterations": 1,
                "keyframesRule": {"keyframes": [{"offset": "0%"}, {"offset": "100%"}]}}}}},
            {"method": "Page.loadEventFired", "params": {}}]
        rows = cdp.summarize_animations(events)
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0]["name"], rows[0]["duration_ms"], rows[0]["delay_ms"]),
                         ("fadeInUp", 400, 300.0))
        self.assertEqual(rows[0]["keyframes"], ["0%", "100%"])

    def test_blocked_requests(self):
        events = [
            {"method": "Network.requestWillBeSent",
             "params": {"requestId": "1", "request": {"url": "https://x/api/bands/search?q=a"}}},
            {"method": "Network.loadingFailed", "params": {"requestId": "1",
                                                           "blockedReason": "inspector"}},
            {"method": "Network.loadingFailed", "params": {"requestId": "2"}},
        ]
        self.assertEqual(cdp.blocked_requests(events), ["https://x/api/bands/search?q=a"])

    def test_frame_diffs_and_bursts(self):
        text = ("[m] frame:1 pts:1 pts_time:0.1\n[m] lavfi.signalstats.YAVG=0.5\n"
                "[m] frame:2 pts:2 pts_time:0.2\n[m] lavfi.signalstats.YAVG=0.01\n")
        self.assertEqual(cdp.parse_frame_diffs(text), [(0.1, 0.5), (0.2, 0.01)])
        bursts = cdp.motion_bursts([1.0, 1.05, 1.1, 2.0], gap=0.1)
        self.assertEqual([(b["start"], b["end"], b["frames"], b["duration_ms"]) for b in bursts],
                         [(1.0, 1.1, 3, 100), (2.0, 2.0, 1, 0)])

    def test_video_sizes(self):
        self.assertEqual(cdp.scale_540(1080, 2424), (540, 1212))
        self.assertEqual(cdp.scale_540(2160, 1350), (864, 540))
        self.assertEqual(cdp.scale_540(400, 300), (400, 300))
        self.assertEqual(cdp.even(755), 754)


if __name__ == "__main__":
    unittest.main()
