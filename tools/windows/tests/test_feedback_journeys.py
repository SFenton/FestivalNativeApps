"""Feedback Form journeys and fixture (``journeys/feedback.py``, ``feedback_fixture.py``; issue #236).

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root.
"""

import importlib.util
import json
import struct
import sys
import tempfile
import threading
import unittest
import zlib
from pathlib import Path

from tools.windows import uiwin as u

_PATH = Path(__file__).resolve().parents[1] / "journeys" / "feedback.py"
_SPEC = importlib.util.spec_from_file_location("fst_feedback_journeys", _PATH)
f = importlib.util.module_from_spec(_SPEC)
sys.modules[_SPEC.name] = f
_SPEC.loader.exec_module(f)

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import feedback_fixture as fx  # noqa: E402  (tools/windows module)

TREE = "\n".join([
    'Window "Report an Issue" id=fst.settings.feedback.bug.dialog class=Popup rect=1,1,800,600',
    '  Button "Image, shot-1.png, 1 KB" id=fst.settings.feedback.attachment class=Button rect=1,2,3,4 [focusable]',
    '  Button "Remove shot-1.png" id=fst.settings.feedback.attachment.remove class=Button rect=1,2,3,4 [focusable]',
    '  Button "Image, shot-2.png, 1 KB" id=fst.settings.feedback.attachment class=Button rect=1,2,3,4 [focusable]',
    '  Text "Add a description." id=fst.settings.feedback.validation class=TextBlock rect=1,2,3,4',
    '  Button "Submit" id=PrimaryButton class=Button rect=1,2,3,4 [disabled,focusable] patterns=Invoke',
])

BODY = (b'--b\r\nContent-Disposition: form-data; name="kind"\r\n\r\nbug\r\n'
        b'--b\r\nContent-Disposition: form-data; name="title"\r\n\r\n[Bug] secret words\r\n'
        b'--b\r\nContent-Disposition: form-data; name="platform"\r\nContent-Type: text/plain\r\n\r\nwindows\r\n'
        b'--b\r\nContent-Disposition: form-data; name="media"; filename="a.png"\r\n\r\nPNG\r\n'
        b'--b\r\nContent-Disposition: form-data; name="media"; filename="b.png"\r\n\r\nPNG\r\n--b--\r\n')


class FeedbackJourneyTests(unittest.TestCase):
    """Journey definitions parse, cover every spec state and the checks report what they should."""

    def test_every_step_parses(self):
        with tempfile.TemporaryDirectory() as folder:
            for journey in f.JOURNEYS:
                self.assertTrue(journey.phases, journey.name)
                for phase in journey.phases:
                    for step in f.expand(phase.steps, Path(folder)):
                        u.parse_step(step)
                    self.assertLessEqual(set(phase.control), {"features", "post", "status", "reset"}, journey.name)

    def test_every_spec_state_is_covered(self):
        spec = (f.REPO / ".agents" / "controls" / "feedback-form" / "spec.md").read_text(encoding="utf-8")
        for state in f.STATES:
            self.assertIn(f"| {state} |", spec)
        covered = {state for journey in f.JOURNEYS for state in journey.states}
        self.assertEqual(covered, set(f.STATES))

    def test_matrix_pages_cover_every_state_and_parse(self):
        pages = json.loads((f.REPO / "tools" / "windows" / "journeys" / "a11y-feedback.json").read_text(encoding="utf-8"))
        self.assertEqual({p["name"].removeprefix("feedback-") for p in pages}, set(f.STATES))
        for page in pages:
            self.assertEqual(page["fixture"][0], "feedback_fixture.py", page["name"])
            self.assertEqual(page["tabs"], 0, page["name"])
            for step in page["ready"] + page["after_ready"]:
                u.parse_step(step.replace("{repo}", str(f.REPO)))

    def test_picker_steps_qualify_the_open_button(self):
        steps = f.expand(f._pick("a.png", "b.png"), Path("C:/media"))
        self.assertIn("invoke:id=1&class=Button", steps)
        setvalue = u.parse_step(next(s for s in steps if s.startswith("setvalue:")))
        self.assertEqual(setvalue["selector"], {"kind": "id", "value": "1148", "class": "Edit"})
        self.assertEqual(setvalue["text"], f'"{Path("C:/media")}\\a.png" "{Path("C:/media")}\\b.png"')

    def test_check_tree_counts(self):
        ok = f.Phase([], expect=[f._named("fst.settings.feedback.validation", "Add a description.")],
                     forbid=[r'"Image, shot-3'], count={f.ATTACHMENT: 2})
        self.assertEqual(f.check_tree(TREE, ok), [])
        bad = f.Phase([], expect=[f._id("fst.settings.feedback.sent")], forbid=[r"\[disabled"], count={f.ATTACHMENT: 4})
        failures = f.check_tree(TREE, bad)
        self.assertEqual(len(failures), 3)
        self.assertIn("saw 2", failures[2])

    def test_check_posted(self):
        phase = f.Phase([], posted={"one": lambda s: s["posts"] == 1, "media": lambda s: s["last"]["media"] == 2})
        self.assertEqual(f.check_posted({"posts": 1, "reads": 0, "last": {"media": 2}}, phase), [])
        self.assertEqual(len(f.check_posted({"posts": 0, "reads": 0, "last": None}, phase)), 2)
        self.assertEqual(f.check_posted(None, phase), ["fixture snapshot unreadable"])
        self.assertEqual(f.check_posted(None, f.Phase([])), [])

    def test_settle_posted_waits_for_a_trailing_read(self):
        # #548: "Filing" shows on the accepted POST, the first status read follows PollInterval later.
        phase = f.Phase([], posted={"status polled": lambda s: s["reads"] >= 1})
        snapshots = iter([{"posts": 1, "reads": 0}, {"posts": 1, "reads": 0}, {"posts": 1, "reads": 1}])
        self.assertEqual(f.settle_posted(lambda: next(snapshots), phase, timeout=5, interval=0), [])

    def test_settle_posted_reports_the_last_failure_after_timeout(self):
        phase = f.Phase([], posted={"status polled": lambda s: s["reads"] >= 1})
        reads = []

        def snapshot():
            reads.append(1)
            return {"posts": 1, "reads": 0}

        failures = f.settle_posted(snapshot, phase, timeout=0.05, interval=0.01)
        self.assertEqual(len(failures), 1)
        self.assertIn("status polled", failures[0])
        self.assertGreater(len(reads), 1)
        self.assertEqual(f.settle_posted(lambda: None, phase, timeout=0, interval=0), ["fixture snapshot unreadable"])

    def test_settle_posted_without_predicates_reads_nothing(self):
        self.assertEqual(f.settle_posted(lambda: self.fail("read"), f.Phase([])), [])

    def test_settle_posted_returns_at_once_when_it_holds(self):
        phase = f.Phase([], posted={"one": lambda s: s["posts"] == 1})
        reads = []
        self.assertEqual(f.settle_posted(lambda: reads.append(1) or {"posts": 1}, phase, timeout=5, interval=5), [])
        self.assertEqual(len(reads), 1)

    def test_png_is_valid(self):
        data = f.png(4, 3, (1, 2, 3))
        self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"))
        width, height = struct.unpack(">II", data[16:24])
        self.assertEqual((width, height), (4, 3))
        idat = data.index(b"IDAT")
        length = struct.unpack(">I", data[idat - 4:idat])[0]
        self.assertEqual(zlib.decompress(data[idat + 4:idat + 4 + length]), (b"\x00" + bytes((1, 2, 3)) * 4) * 3)
        with tempfile.TemporaryDirectory() as folder:
            f.write_media(Path(folder))
            self.assertEqual(sorted(p.name for p in Path(folder).iterdir()), [f"shot-{i}.png" for i in range(1, 6)])

    def test_control_unreachable_returns_none(self):
        self.assertIsNone(f.control("http://127.0.0.1:9/", {}))


class FeedbackFixtureTests(unittest.TestCase):
    """The fixture wrapper's pure parts."""

    def test_summarize_never_echoes_text(self):
        summary = fx.summarize(BODY, {"Content-Type": "multipart/form-data; boundary=b"})
        self.assertEqual(summary, {"fields": ["kind", "title", "platform", "media", "media"], "kind": "bug",
                                   "platform": "windows", "media": 2, "forbidden_header": False})
        self.assertNotIn("secret", json.dumps(summary))
        self.assertTrue(fx.summarize(BODY, {"X-API-Key": "k"})["forbidden_header"])
        self.assertTrue(fx.summarize(BODY, {"X-FST-Selected-Profile": "p"})["forbidden_header"])
        self.assertEqual(fx.summarize(b"", {})["media"], 0)

    def test_bare_token_names_from_dotnet(self):
        body = BODY.replace(b'name="kind"', b"name=kind").replace(b'name="platform"', b"name=platform") \
            .replace(b'name="media"; filename="a.png"', b"name=media; filename=a.png")
        summary = fx.summarize(body, {})
        self.assertEqual(summary["fields"], ["kind", "title", "platform", "media", "media"])
        self.assertEqual((summary["kind"], summary["platform"], summary["media"]), ("bug", "windows", 2))
        self.assertEqual(fx.quote_names(body).replace(b'filename=a.png', b'filename="a.png"'), BODY)
        self.assertEqual(fx.quote_names(BODY), BODY)

    def test_state_modes_hold_and_reset(self):
        state = fx.FeedbackState(post="hold", slow_seconds=1)
        self.assertFalse(state.post_released.is_set())
        self.assertTrue(state.status_released.is_set())
        state.record_post({"media": 1})
        state.record_read()
        snap = state.update({"post": ["ok"], "status": ["hold"], "features": ["off"]})
        self.assertEqual((snap["post"], snap["status"], snap["features"]), ("ok", "hold", "off"))
        self.assertTrue(state.post_released.is_set())
        self.assertFalse(state.status_released.is_set())
        self.assertFalse(state.features_on())
        self.assertEqual((snap["posts"], snap["reads"], snap["last"]), (1, 1, {"media": 1}))
        self.assertEqual(state.update({"reset": ["1"]})["posts"], 0)
        with self.assertRaises(ValueError):
            state.update({"post": ["slow"]})
        with self.assertRaises(ValueError):
            state.update({"bogus": ["1"]})

    def test_held_request_is_released_by_control(self):
        state = fx.FeedbackState(post="hold", slow_seconds=5)
        released = []
        waiter = threading.Thread(target=lambda: released.append(state.post_released.wait(5)))
        waiter.start()
        state.update({"post": ["ok"]})
        waiter.join(5)
        self.assertEqual(released, [True])

    def test_update_holds_status_before_releasing_the_post(self):
        state = fx.FeedbackState(post="hold", slow_seconds=5)
        order = []

        class Recording(threading.Event):
            def __init__(self, name):
                super().__init__()
                self.name = name

            def set(self):
                order.append(("set", self.name))
                super().set()

            def clear(self):
                order.append(("clear", self.name))
                super().clear()

        state.post_released, state.status_released = Recording("post"), Recording("status")
        state.update({"post": ["ok"], "status": ["hold"]})
        self.assertEqual(order, [("clear", "status"), ("set", "post")])

    def test_parse_options_passes_the_rest_through(self):
        options, rest = fx.parse_options(["--port", "0", "--features", "off", "--status", "hold", "--slow-seconds", "9"])
        self.assertEqual((options.features, options.post, options.status, options.slow_seconds), ("off", "ok", "hold", 9.0))
        self.assertEqual(rest, ["--port", "0"])


if __name__ == "__main__":
    unittest.main()
