"""Pure logic of ``tools/android/pwa.py`` (installed-PWA lab on the FST AVDs)."""

import unittest

from tools.android import pwa


class AndroidPwaTests(unittest.TestCase):
    """Chrome first-run geometry, activity parsing, steps and recording size."""

    def test_manage_link_point(self):
        self.assertEqual(pwa.manage_link_point("[63,2207][1017,2298]"), (952, 2273))

    def test_row_switch_matches_overlapping_row(self):
        xml = ('<node text="Allow Chrome sign-in" bounds="[1050,392][1935,456]" />'
               '<node resource-id="com.android.chrome:id/switchWidget" checked="true" '
               'bounds="[1980,389][2089,515]" />'
               '<node text="Help improve Chrome’s features" bounds="[1050,602][1935,719]" />'
               '<node resource-id="com.android.chrome:id/switchWidget" checked="true" '
               'bounds="[1980,649][2089,775]" />')
        self.assertEqual(pwa.row_switch(xml, "Help improve Chrome"), (True, (2034, 712)))
        self.assertIsNone(pwa.row_switch(xml, "Missing row"))

    def test_top_activity(self):
        dump = ("  topResumedActivity=ActivityRecord{92628745 u0 "
                "com.android.chrome/org.chromium.chrome.browser.webapps.WebappActivity t23}\n")
        self.assertIn(pwa.WEBAPP_ACTIVITY, pwa.parse_top_activity(dump))
        self.assertEqual(pwa.parse_top_activity("nothing"), "")

    def test_screenrecord_size(self):
        self.assertEqual(pwa.screenrecord_size(1080, 2424), "854x1920")
        self.assertEqual(pwa.screenrecord_size(1080, 1920), "1080x1920")

    def test_drive_steps(self):
        steps = pwa.parse_drive_steps("posture:half; ?shot:{out}/a.png; back; record:start:x.mp4",
                                      None, {"out": "o"})
        self.assertEqual(steps, [("posture", "half", False), ("shot", "o/a.png", True),
                                 ("back", "", False), ("record", "start:x.mp4", False)])
        with self.assertRaises(ValueError):
            pwa.parse_drive_steps("record:pause", None)


if __name__ == "__main__":
    unittest.main()
