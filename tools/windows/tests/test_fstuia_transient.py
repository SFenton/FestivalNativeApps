"""``FstUia``'s transient-UIA classifier (``IsTransientUia``) through the offline ``transient`` command (issue #622).

``releases/2610.12``'s ``bp-navigation`` (compact, 225% text) died on one ``scrollinto`` right after Back: FlaUI's
``FindAll`` let the provider's ``UIA_E_TIMEOUT`` (0x80131505) through as a raw ``COMException`` instead of a
``TimeoutException``, so the step's transient-error retry (#552, #574, #618) never ran. Every retry loop (``Find``,
``scrollinto``, ``waitgone``, the launch window poll) shares ``IsTransientUia``, so pinning it covers them all.

``releases/2610.19``'s ``history-anonymous`` (#674) died the same way on ``E_UNEXPECTED`` (0x8000FFFF, "Catastrophic
failure") from ``FindFirst`` right after invoking the History header's song: WinUI's UIA window provider returns it
while it is not initialized, a passing state during the page swap (the app's own peers don't throw there). It is
retried within the step's timeout like ``UIA_E_TIMEOUT``; every other ``COMException`` still fails the step at once.

Run: ``python -m unittest discover -s tools/windows/tests`` from the repo root. Builds ``FstUia`` once (``dotnet``).
"""

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from tools.windows import uiwin as u

UIA_E_TIMEOUT = 0x80131505
E_UNEXPECTED = 0x8000FFFF
E_FAIL = 0x80004005
E_INVALIDARG = 0x80070057
RPC_E_DISCONNECTED = 0x80010108
UIA_E_ELEMENTNOTAVAILABLE = 0x80040201


@unittest.skipUnless(sys.platform == "win32" and shutil.which("dotnet"), "FstUia needs Windows and dotnet")
class TransientUiaTests(unittest.TestCase):
    """Replays ``IsTransientUia`` on synthetic errors."""

    exe: Path

    @classmethod
    def setUpClass(cls):
        cls.exe = u.driver_exe()

    def transient(self, kind: str, hresult: int | None = None) -> bool:
        request: dict = {"command": "transient", "kind": kind}
        if hresult is not None:
            request["hresult"] = hresult
        with tempfile.TemporaryDirectory() as tmp:
            req, resp = Path(tmp) / "req.json", Path(tmp) / "resp.json"
            req.write_text(json.dumps(request), encoding="utf-8")
            subprocess.run([str(self.exe), "--request", str(req), "--response", str(resp)], timeout=60, check=False)
            data = json.loads(resp.read_text(encoding="utf-8"))
        self.assertTrue(data["ok"], data.get("error"))
        return data["result"]["transient"]

    def test_raw_com_timeout_is_transient(self):
        # #622: the form FindAll threw in PageDown after Back to Song Detail.
        self.assertTrue(self.transient("com", UIA_E_TIMEOUT))

    def test_raw_com_unexpected_is_transient(self):
        # #674: FindFirst right after invoking fst.history.song on the anonymous History page.
        self.assertTrue(self.transient("com", E_UNEXPECTED))

    def test_mapped_timeout_and_vanished_element_stay_transient(self):
        self.assertTrue(self.transient("timeout"))
        self.assertTrue(self.transient("element-not-available"))

    def test_other_com_errors_are_not_swallowed(self):
        for hresult in (E_FAIL, E_INVALIDARG, RPC_E_DISCONNECTED, UIA_E_ELEMENTNOTAVAILABLE):
            with self.subTest(hresult=hex(hresult)):
                self.assertFalse(self.transient("com", hresult))

    def test_other_errors_are_not_transient(self):
        self.assertFalse(self.transient("invalid-operation"))


class TransientUiaRetrySourceTests(unittest.TestCase):
    """Every UIA poll that retries a transient error goes through ``IsTransientUia`` and still bounds the retry."""

    def test_retry_loops_share_the_classifier(self):
        source = (u.DRIVER_DIR / "Program.cs").read_text(encoding="utf-8")
        for start, end in (("private Window? WaitForWindow(", "private Window? TopWindow("),
                           ("private void WaitGone(", "private void ScrollInto("),
                           ("private void ScrollInto(", "private void PageDown("),
                           ("internal AutomationElement Find(", "internal const int UiaTimeoutHResult")):
            with self.subTest(loop=start):
                body = source.split(start, 1)[1].split(end, 1)[0]
                self.assertRegex(body, r"catch \(Exception error\) when \(IsTransientUia\(error\) && \(!retried \|\| "
                                       r"DateTime\.UtcNow <=? until\)\)")
                self.assertIn("retried = true;", body)
        classifier = source.split("internal static bool IsTransientUia(", 1)[1].split(";", 1)[0]
        self.assertIn("COMException { HResult: UiaTimeoutHResult or UiaUnexpectedHResult }", classifier)
        self.assertIn("unchecked((int)0x80131505)", source.split("internal const int UiaTimeoutHResult", 1)[1][:60])
        self.assertIn("unchecked((int)0x8000FFFF)", source.split("internal const int UiaUnexpectedHResult", 1)[1][:60])


if __name__ == "__main__":
    unittest.main()
