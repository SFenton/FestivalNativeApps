"""Machine-wide capacity gates (``tools/devcap.py``).

Each test points ``DEVCAP_DIR`` at a temporary directory, so nothing here
touches the real ``~/.devcap`` that running lanes use. Two gates in one
process conflict exactly like two processes (``flock`` locks belong to the
open file), which lets most cases run in-process.
"""

import json
import os
import subprocess
import sys
import threading
import time
import unittest
import unittest.mock
from pathlib import Path
from tempfile import TemporaryDirectory

from tools import devcap
from tools.devcap import Gate, Hold, WaitTimeout, gate_names, parse_ticket, queue_order

TOOL = Path(devcap.__file__)
UDID = "0D77CC23-71D3-46F4-B491-EDAA73B6B65A"

#: Stands in for ``xcrun``: logs its arguments and which simulator slots are
#: still held at that moment (probed with the same OS lock devcap uses).
FAKE_XCRUN = """#!/usr/bin/env python3
import fcntl, os, sys
gate = os.path.join(os.environ["DEVCAP_DIR"], "simulator")
held = []
for name in sorted(os.listdir(gate)):
    if name.endswith(".lock"):
        handle = open(os.path.join(gate, name), "a+b")
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            held.append(name)
        handle.close()
with open(os.environ["FAKE_XCRUN_LOG"], "a") as log:
    log.write(" ".join(sys.argv[1:]) + " held=" + ",".join(held) + "\\n")
"""


class DevcapTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.root = Path(self.tmp.name)
        patcher = unittest.mock.patch.dict(os.environ, {"DEVCAP_DIR": str(self.root)})
        patcher.start()
        self.addCleanup(patcher.stop)
        self.addCleanup(self.tmp.cleanup)
        for key in [k for k in os.environ if k.startswith("DEVCAP_SLOTS_") or k == devcap.HELD_ENV]:
            os.environ.pop(key)

    def gate(self, name="simulator", slots=1):
        return Gate(name, self.root, slots)


class TicketTests(unittest.TestCase):
    def test_parse_ticket(self):
        self.assertEqual(parse_ticket("00000000000000000012-345.ticket"), (12, 345))
        for name in ("x.lock", "12.ticket", "a-1.ticket", "1-b.ticket", "1-2.txt"):
            self.assertIsNone(parse_ticket(name))

    def test_queue_order_is_fifo_and_splits_dead_owners(self):
        names = ["3-30.ticket", "1-10.ticket", "2-20.ticket", "junk"]
        live, stale = queue_order(names, lambda pid: pid != 10)
        self.assertEqual(live, ["2-20.ticket", "3-30.ticket"])
        self.assertEqual(stale, ["1-10.ticket"])


class ConfigTests(DevcapTestCase):
    def test_defaults_scale_with_machine(self):
        self.assertEqual(devcap.default_slots("simulator", memory_gb=8), 1)
        self.assertEqual(devcap.default_slots("simulator", memory_gb=64), 3)
        self.assertEqual(devcap.default_slots("simulator", memory_gb=512), 4)
        self.assertEqual(devcap.default_slots("build", cpus=10), 2)
        self.assertEqual(devcap.default_slots("build", cpus=2), 1)
        self.assertEqual(devcap.default_slots("anything"), 1)

    def test_environment_beats_config_file(self):
        (self.root / "config.json").write_text(json.dumps({"simulator": 5, "build": 3}))
        self.assertEqual(devcap.configured_slots("build", self.root), 3)
        with unittest.mock.patch.dict(os.environ, {"DEVCAP_SLOTS_BUILD": "7"}):
            self.assertEqual(devcap.configured_slots("build", self.root), 7)
        with unittest.mock.patch.dict(os.environ, {"DEVCAP_SLOTS_BUILD": "nonsense"}):
            self.assertEqual(devcap.configured_slots("build", self.root),
                             devcap.default_slots("build"))

    def test_devices_always_have_one_slot(self):
        (self.root / "config.json").write_text(json.dumps({"device-ABC": 4}))
        self.assertEqual(devcap.configured_slots("device-ABC", self.root), 1)

    def test_bad_config_falls_back_to_default(self):
        (self.root / "config.json").write_text("{not json")
        self.assertEqual(devcap.configured_slots("anything", self.root), 1)

    def test_env_key(self):
        self.assertEqual(devcap.env_key("sim-pool.x"), "DEVCAP_SLOTS_SIM_POOL_X")

    def test_gate_names_are_canonical(self):
        names = gate_names(pools=["build"], sims=["bbb-2"], devices=["aaa-1"])
        self.assertEqual(names, ["device-AAA-1", "device-BBB-2", "build", "simulator"])
        self.assertEqual(gate_names(sims=["x", "x"]), ["device-X", "simulator"])
        self.assertEqual(gate_names(devices=["x"]), ["device-X"])

    def test_invalid_gate_name(self):
        with self.assertRaises(ValueError):
            Gate("../escape", self.root, 1)


class GateTests(DevcapTestCase):
    def test_slots_fill_then_wait(self):
        first, second, third = (self.gate(slots=2) for _ in range(3))
        first.acquire("one", wait_seconds=1)
        second.acquire("two", wait_seconds=1)
        self.assertEqual({first._slot, second._slot}, {0, 1})
        messages = []
        with self.assertRaises(WaitTimeout):
            third.acquire("three", wait_seconds=0.3, poll_seconds=0.05, announce=messages.append)
        self.assertIn("2/2 held", messages[0])
        self.assertIn("'one'", messages[0])
        self.assertFalse(list((self.root / "simulator" / "queue").iterdir()), "ticket removed")
        freed = first._slot
        first.release()
        third.acquire("three", wait_seconds=1, poll_seconds=0.05)
        self.assertEqual(third._slot, freed)
        for gate in (second, third):
            gate.release()

    def test_holder_record_and_release(self):
        gate = self.gate()
        gate.acquire("shot iphone", wait_seconds=1)
        observer = self.gate()
        [record] = observer.holders()
        self.assertEqual(record["pid"], os.getpid())
        self.assertEqual(record["purpose"], "shot iphone")
        self.assertEqual(record["slot"], 0)
        gate.release()
        gate.release()  # idempotent
        self.assertEqual(observer.holders(), [])
        self.assertFalse((self.root / "simulator" / "slot-0.json").exists())
        log = (self.root / "devcap.log").read_text()
        self.assertIn("acquire simulator slot 0/1", log)
        self.assertIn("release simulator slot 0", log)

    def test_dead_tickets_do_not_block_the_queue(self):
        queue = self.root / "simulator" / "queue"
        queue.mkdir(parents=True)
        dead = queue / "00000000000000000001-999999999.ticket"
        dead.write_text("ghost")
        gate = self.gate()
        with unittest.mock.patch.object(devcap, "pid_alive", lambda pid: pid == os.getpid()):
            gate.acquire("live", wait_seconds=1, poll_seconds=0.05)
        self.assertFalse(dead.exists())
        gate.release()

    def test_waiters_behind_the_head_do_not_take_slots(self):
        queue = self.root / "simulator" / "queue"
        queue.mkdir(parents=True)
        (queue / "00000000000000000001-1.ticket").write_text("earlier lane")
        gate = self.gate()
        messages = []
        with unittest.mock.patch.object(devcap, "pid_alive", lambda pid: True):
            with self.assertRaises(WaitTimeout):
                gate.acquire("later", wait_seconds=0.3, poll_seconds=0.05, announce=messages.append)
            self.assertEqual(gate.waiting(), [{"pid": 1, "purpose": "earlier lane"}])
        self.assertIn("1 ahead in queue", messages[0])

    def test_lowering_slots_ignores_slots_above_the_limit(self):
        wide = self.gate(slots=3)
        wide.acquire("a", wait_seconds=1)
        narrow = self.gate(slots=1)
        with self.assertRaises(WaitTimeout):
            narrow.acquire("b", wait_seconds=0.2, poll_seconds=0.05, announce=lambda _: None)
        wide.release()

    def test_stale_holder_record_is_ignored(self):
        gate_dir = self.root / "simulator"
        gate_dir.mkdir(parents=True)
        (gate_dir / "slot-0.lock").touch()
        (gate_dir / "slot-0.json").write_text(json.dumps({"pid": 999999999, "purpose": "crashed"}))
        self.assertEqual(self.gate().holders(), [])


class HoldTests(DevcapTestCase):
    def test_hold_takes_device_and_simulator_and_exports_them(self):
        with devcap.hold(sims=["abc"], purpose="journey", hold_seconds=None, root=self.root) as held:
            self.assertEqual([g.name for g in held.gates], ["device-ABC", "simulator"])
            self.assertEqual(os.environ[devcap.HELD_ENV], "device-ABC,simulator")
            with self.assertRaises(WaitTimeout):
                Gate("device-ABC", self.root).acquire("other", 0.2, 0.05, announce=lambda _: None)
        self.assertNotIn(devcap.HELD_ENV, os.environ)
        self.assertEqual(Gate("device-ABC", self.root).holders(), [])

    def test_nested_hold_reuses_inherited_gates(self):
        with devcap.hold(sims=["abc"], hold_seconds=None, root=self.root):
            with devcap.hold(sims=["abc"], pools=["build"], hold_seconds=None, root=self.root) as inner:
                self.assertEqual([g.name for g in inner.gates], ["build"])
            self.assertEqual(os.environ[devcap.HELD_ENV], "device-ABC,simulator")

    def test_failed_acquire_releases_earlier_gates(self):
        os.environ["DEVCAP_SLOTS_SIMULATOR"] = "1"
        blocker = Gate("simulator", self.root)
        blocker.acquire("busy", 1)
        held = Hold(["device-X", "simulator"], "x", wait_seconds=0.2, hold_seconds=None, root=self.root)
        with unittest.mock.patch("sys.stderr"), self.assertRaises(WaitTimeout):
            held.acquire()
        self.assertEqual(held.gates, [])
        self.assertEqual(Gate("device-X", self.root).holders(), [])
        blocker.release()

    def test_concurrent_release_logs_once(self):
        held = Hold(["build"], "x", wait_seconds=1, hold_seconds=None, root=self.root)
        held.acquire()
        threads = [threading.Thread(target=held.release) for _ in range(4)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual((self.root / "devcap.log").read_text().count("release build"), 1)

    def test_watchdog_fires_on_overrun(self):
        fired = []
        held = Hold(["build"], "slow", wait_seconds=1, hold_seconds=0.1, root=self.root,
                    on_overrun=lambda: fired.append(True))
        with unittest.mock.patch.object(devcap.os, "_exit", lambda code: fired.append(code)):
            held.acquire()
            time.sleep(0.5)
        self.assertEqual(fired, [True, devcap.HOLD_TIMEOUT_EXIT])
        self.assertEqual(Gate("build", self.root).holders(), [])


class CliTests(DevcapTestCase):
    def cli(self, *args, **kwargs):
        return subprocess.run([sys.executable, str(TOOL), *args], capture_output=True, text=True,
                              env={**os.environ}, timeout=30, **kwargs)

    def test_run_passes_exit_code_and_held_gates(self):
        result = self.cli("run", "--sim", UDID, "--pool", "build", "--purpose", "t", "--",
                          sys.executable, "-c",
                          "import os, sys; print(os.environ['DEVCAP_HELD']); sys.exit(3)")
        self.assertEqual(result.returncode, 3, result.stderr)
        self.assertEqual(result.stdout.strip(), f"build,device-{UDID},simulator")

    def test_run_requires_a_gate_and_a_command(self):
        self.assertEqual(self.cli("run", "--", "true").returncode, 2)
        self.assertEqual(self.cli("run", "--pool", "build").returncode, 2)

    def test_run_waits_then_times_out_with_tempfail(self):
        with devcap.hold(pools=["build"], purpose="holder", hold_seconds=None, root=self.root):
            os.environ.pop(devcap.HELD_ENV)
            os.environ["DEVCAP_SLOTS_BUILD"] = "1"
            result = self.cli("run", "--pool", "build", "--wait", "0.5", "--", "true")
        self.assertEqual(result.returncode, devcap.WAIT_TIMEOUT_EXIT)
        self.assertIn("'holder'", result.stderr)

    def test_second_process_runs_after_first_releases(self):
        os.environ["DEVCAP_SLOTS_SIMULATOR"] = "1"
        marker = self.root / "order.txt"
        script = ("import sys, time; open(sys.argv[1], 'a').write(sys.argv[2] + ' start\\n'); "
                  "time.sleep(0.6); open(sys.argv[1], 'a').write(sys.argv[2] + ' end\\n')")
        first = subprocess.Popen([sys.executable, str(TOOL), "run", "--pool", "simulator", "--",
                                  sys.executable, "-c", script, str(marker), "A"], env={**os.environ},
                                 stderr=subprocess.PIPE, text=True)
        deadline = time.monotonic() + 30
        while not marker.exists() and time.monotonic() < deadline:  # A holds the slot
            time.sleep(0.05)
        second = self.cli("run", "--pool", "simulator", "--", sys.executable, "-c", script, str(marker), "B")
        first.communicate(timeout=30)
        self.assertEqual(second.returncode, 0)
        self.assertEqual(marker.read_text().split("\n")[:4], ["A start", "A end", "B start", "B end"])
        self.assertIn("waiting for 'simulator'", second.stderr)

    def test_hold_timeout_kills_the_command(self):
        result = self.cli("run", "--pool", "build", "--hold", "0.5", "--",
                          sys.executable, "-c", "import time; time.sleep(30)")
        self.assertEqual(result.returncode, devcap.HOLD_TIMEOUT_EXIT)
        self.assertIn("HOLD TIMEOUT", result.stderr)

    def test_status_reports_holders_and_slots(self):
        with devcap.hold(sims=["abc"], purpose="journey", hold_seconds=None, root=self.root):
            os.environ.pop(devcap.HELD_ENV)
            report = json.loads(self.cli("status", "--json").stdout)
            text = self.cli("status").stdout
        by_gate = {entry["gate"]: entry for entry in report}
        self.assertEqual(by_gate["device-ABC"]["holders"][0]["purpose"], "journey")
        self.assertEqual(len(by_gate["simulator"]["holders"]), 1)
        self.assertIn("build", by_gate)
        self.assertIn("device-ABC: 1/1 held", text)
        self.assertIn("journey", text)

    def test_shutdown_runs_after_the_command_inside_the_hold(self):
        calls = []

        def record(udids):
            calls.append((list(udids), [h["purpose"] for h in Gate("simulator", self.root).holders()]))

        with unittest.mock.patch.object(devcap, "shutdown_sims", record):
            code = devcap.main(["run", "--sim", UDID, "--shutdown", "--purpose", "p", "--",
                                sys.executable, "-c", "pass"])
            devcap.main(["run", "--sim", UDID, "--", sys.executable, "-c", "pass"])
        self.assertEqual(code, 0)
        self.assertEqual(calls, [([UDID], ["p"])])  # once, while the slot was still held

    def test_shutdown_runs_when_the_hold_overruns(self):
        calls = []
        held = Hold(["simulator"], "x", wait_seconds=1, hold_seconds=0.2, root=self.root)
        held.cleanup = lambda: calls.append("shutdown")
        held.acquire()
        with unittest.mock.patch.object(devcap.os, "_exit", lambda code: calls.append(code)):
            code = devcap.run_command(held, [sys.executable, "-c", "import time; time.sleep(30)"])
            deadline = time.monotonic() + 10
            while len(calls) < 2 and time.monotonic() < deadline:  # the watchdog finishes
                time.sleep(0.05)
        self.assertEqual(code, devcap.HOLD_TIMEOUT_EXIT)
        self.assertEqual(calls, ["shutdown", devcap.HOLD_TIMEOUT_EXIT])

    def test_shutdown_sims_survives_missing_xcrun(self):
        with unittest.mock.patch.object(devcap.subprocess, "run", side_effect=FileNotFoundError):
            devcap.shutdown_sims([UDID])

    def test_shutdown_sims_never_passes_a_non_udid(self):
        with unittest.mock.patch.object(devcap.subprocess, "run") as run:
            devcap.shutdown_sims(["all", "booted", "iPhone 17 Pro"])
        run.assert_not_called()

    def test_sim_must_be_a_udid(self):
        for value in ("all", "booted", "abc"):
            result = self.cli("run", "--sim", value, "--shutdown", "--", "true")
            self.assertEqual(result.returncode, 2, value)
            self.assertIn("simulator UDID", result.stderr)

    def fake_xcrun(self):
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        xcrun = bin_dir / "xcrun"
        xcrun.write_text(FAKE_XCRUN.replace("/usr/bin/env python3", sys.executable))
        xcrun.chmod(0o755)
        log = self.root / "xcrun.log"
        os.environ["PATH"] = f"{bin_dir}{os.pathsep}{os.environ['PATH']}"
        os.environ["FAKE_XCRUN_LOG"] = str(log)
        os.environ["DEVCAP_SLOTS_SIMULATOR"] = "1"
        return log

    @unittest.skipIf(os.name == "nt", "simulators are macOS-only")
    def test_cli_shutdown_runs_while_the_slot_is_held(self):
        log = self.fake_xcrun()
        result = self.cli("run", "--sim", UDID, "--shutdown", "--", sys.executable, "-c", "pass")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(log.read_text(), f"simctl shutdown {UDID} held=slot-0.lock\n")

    @unittest.skipIf(os.name == "nt", "simulators are macOS-only")
    def test_cli_shutdown_runs_after_a_hold_timeout_before_the_slot_frees(self):
        log = self.fake_xcrun()
        for _ in range(3):
            log.unlink(missing_ok=True)
            result = self.cli("run", "--sim", UDID, "--shutdown", "--hold", "1", "--",
                              sys.executable, "-c", "import time; time.sleep(30)")
            self.assertEqual(result.returncode, devcap.HOLD_TIMEOUT_EXIT, result.stderr)
            self.assertTrue(log.exists(), "xcrun was never called")
            self.assertEqual(log.read_text(), f"simctl shutdown {UDID} held=slot-0.lock\n")
            self.assertEqual(Gate("simulator", self.root).holders(), [])

    def test_slots_and_version(self):
        os.environ["DEVCAP_SLOTS_SIMULATOR"] = "2"
        self.assertIn("simulator=2", self.cli("slots").stdout)
        self.assertEqual(self.cli("--version").stdout.strip(), devcap.VERSION)


class AgeTests(unittest.TestCase):
    def test_describe_age(self):
        self.assertEqual(devcap.describe_age(5), "5s")
        self.assertEqual(devcap.describe_age(185), "3m")
        self.assertEqual(devcap.describe_age(7500), "2h05m")


if __name__ == "__main__":
    unittest.main()
