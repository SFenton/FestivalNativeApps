"""Pure helpers of ``tools/android/talkback_walk.py`` (no device needed).

Run: ``python -m unittest discover -s tools/android/tests`` from the repo root.
"""

import struct
import unittest

from tools.android import talkback_walk as tw

LOG = """\
V/talkback: SpeechControllerImpl(1): Speaking fragment text="Back. Button", utteranceId=talkback_2, TtsSpan=null, locale=null, event=type:EVENT_TYPE_ACCESSIBILITY subtype:TYPE_VIEW_ACCESSIBILITY_FOCUSED displayId:0 time:10
V/talkback: SpeechControllerImpl(1): Speaking fragment text="Double-tap to activate", utteranceId=talkback_3, TtsSpan=null, locale=null, event=null
V/talkback: SpeechControllerImpl(1): Speaking fragment text="Search", utteranceId=talkback_4, TtsSpan=null, locale=null, event=type:EVENT_TYPE_ACCESSIBILITY subtype:TYPE_VIEW_ACCESSIBILITY_FOCUSED displayId:0 time:20
V/talkback: SpeechControllerImpl(1): Speaking fragment text="Button", utteranceId=talkback_5, TtsSpan=null, locale=null, event=type:EVENT_TYPE_ACCESSIBILITY subtype:TYPE_VIEW_ACCESSIBILITY_FOCUSED displayId:0 time:20
V/talkback: SpeechControllerImpl(1): Speaking fragment text="Window title", utteranceId=talkback_6, TtsSpan=null, locale=null, event=type:EVENT_TYPE_ACCESSIBILITY subtype:TYPE_WINDOW_STATE_CHANGED displayId:0 time:30
"""


class TalkBackWalkTests(unittest.TestCase):
    """Log parsing, key chord and report formatting."""

    def test_focus_utterances_join_fragments_and_drop_hints(self):
        self.assertEqual(tw.focus_utterances(LOG), ["Back. Button", "Search Button"])
        self.assertEqual(tw.focus_utterances(""), [])

    def test_next_item_chord_is_meta_right(self):
        chord = tw.next_item_chord()
        self.assertEqual(len(chord), 8 * 24)
        events = [struct.unpack("<qqHHi", chord[i:i + 24])[2:] for i in range(0, len(chord), 24)]
        keys = [e for e in events if e[0] == tw.EV_KEY]
        self.assertEqual(keys, [(1, 125, 1), (1, 106, 1), (1, 106, 0), (1, 125, 0)])

    def test_input_device_by_name(self):
        out = ('add device 1: /dev/input/event13\n  name:     "qwerty2"\n'
               'add device 13: /dev/input/event1\n  name:     "AT Translated Set 2 keyboard"\n')
        self.assertEqual(tw.input_device(out, tw.KEYBOARD), "/dev/input/event1")
        self.assertIsNone(tw.input_device(out, "missing"))

    def test_log_level_preference(self):
        self.assertIn('<string name="pref_log_level">2</string>', tw.with_log_level("<map>\n</map>"))
        replaced = tw.with_log_level('<map><string name="pref_log_level">6</string></map>')
        self.assertEqual(replaced.count("pref_log_level"), 1)
        self.assertIn(">2<", replaced)

    def test_markdown_escapes_pipes(self):
        text = tw.markdown("x", ["A | B", "C"])
        self.assertIn("| 1 | A \\| B |", text)
        self.assertIn("| 2 | C |", text)


if __name__ == "__main__":
    unittest.main()
