"""The simslim step every FST simulator boot runs (``tools/sim_slim.py``).

Fakes ``simslim`` and ``simctl`` with a recording runner, so no simulator, simslim
install or devcap hold is needed.
"""

import sys as _sys
import unittest as _unittest

if _sys.platform == "win32":  # Apple tooling imports the POSIX-only fcntl module.
    raise _unittest.SkipTest("Apple simulator tooling runs only on macOS")

import json
import subprocess
import unittest
import unittest.mock
from pathlib import Path

from tools import devcap, ios_sim, sim_slim

UDID = "4E9F2A49-127D-40BC-A909-08AF3D4BE6A5"
HELD = {devcap.HELD_ENV: f"{devcap.device_gate(UDID)},simulator"}


def which(_name):
    return "/opt/homebrew/bin/simslim"


def missing(_name):
    return None


class FakeRunner:
    """Answer ``simslim`` subcommands from a script and record every call.

    Args:
        verify: Exit codes for successive ``simslim verify`` calls (the last repeats).
        on: Exit codes for successive ``simslim on`` calls (the last repeats).
    """

    def __init__(self, verify=(0,), on=(0,)):
        self.calls = []
        self.verify = list(verify)
        self.on = list(on)

    def __call__(self, cmd, **_kwargs):
        self.calls.append(cmd)
        code = 0
        if cmd[:2] == ["simslim", "verify"]:
            code = self.verify.pop(0) if len(self.verify) > 1 else self.verify[0]
        elif cmd[:2] == ["simslim", "on"]:
            code = self.on.pop(0) if len(self.on) > 1 else self.on[0]
        return subprocess.CompletedProcess(cmd, code, stdout="", stderr="")

    def verbs(self):
        """Each call as ``simslim <verb>`` or ``simctl <verb>`` (``on`` keeps ``--no-reboot``)."""
        verbs = []
        for cmd in self.calls:
            if cmd[0] == "simslim":
                verbs.append(" ".join(["simslim", cmd[1], *(["--no-reboot"] if "--no-reboot" in cmd else [])]))
            else:
                verbs.append(f"simctl {cmd[2]}")
        return verbs


class SimSlimTestCase(unittest.TestCase):
    def setUp(self):
        sim_slim._verified.clear()

    def slim(self, runner, env=None, booted=True, which_fn=which):
        with unittest.mock.patch("sys.stderr"):
            return sim_slim.ensure_slim(UDID, booted=booted, env=HELD if env is None else env,
                                        run=runner, which=which_fn)


class SkipTests(SimSlimTestCase):
    """Anything that rules slimming out leaves the simulator as it is and runs nothing."""

    def test_missing_simslim_is_a_skip_not_a_failure(self):
        runner = FakeRunner()
        self.assertEqual(self.slim(runner, which_fn=missing), "skipped")
        self.assertEqual(runner.calls, [])

    def test_opt_out_env(self):
        runner = FakeRunner()
        self.assertEqual(self.slim(runner, env={**HELD, sim_slim.SLIM_ENV: "0"}), "skipped")
        self.assertEqual(runner.calls, [])

    def test_ci_runner_stays_stock(self):
        runner = FakeRunner()
        self.assertEqual(self.slim(runner, env={**HELD, "GITHUB_ACTIONS": "true"}), "skipped")
        self.assertEqual(runner.calls, [])

    def test_never_slims_a_device_without_its_hold(self):
        runner = FakeRunner()
        self.assertEqual(self.slim(runner, env={devcap.HELD_ENV: "simulator"}), "skipped")
        self.assertEqual(self.slim(runner, env={}), "skipped")
        self.assertEqual(runner.calls, [])

    def test_slim_env_other_than_zero_slims(self):
        runner = FakeRunner()
        self.assertEqual(self.slim(runner, env={**HELD, sim_slim.SLIM_ENV: "1"}), "verified")


class IdempotenceTests(SimSlimTestCase):
    """A slim simulator costs one verify, and none while it stays booted in this process."""

    def test_already_slim_costs_one_verify(self):
        runner = FakeRunner(verify=(0,))
        self.assertEqual(self.slim(runner), "verified")
        self.assertEqual(runner.verbs(), ["simslim verify"])

    def test_second_call_while_still_booted_runs_nothing(self):
        runner = FakeRunner(verify=(0,))
        self.slim(runner)
        self.assertEqual(self.slim(runner, booted=False), "cached")
        self.assertEqual(runner.verbs(), ["simslim verify"])

    def test_a_fresh_boot_verifies_again(self):
        runner = FakeRunner(verify=(0,))
        self.slim(runner)
        self.assertEqual(self.slim(runner, booted=True), "verified")
        self.assertEqual(runner.verbs(), ["simslim verify", "simslim verify"])

    def test_not_yet_verified_device_is_verified_even_when_warm(self):
        runner = FakeRunner(verify=(0,))
        self.assertEqual(self.slim(runner, booted=False), "verified")

    def test_another_profile_is_not_covered_by_the_cache(self):
        runner = FakeRunner(verify=(0,))
        self.slim(runner)
        other = {**HELD, sim_slim.PROFILE_ENV: "/tmp/other.json"}
        self.assertEqual(self.slim(runner, env=other, booted=False), "verified")


class SlimTests(SimSlimTestCase):
    """A stock simulator is slimmed live first, with a reboot only when that is not enough."""

    def test_stock_device_is_slimmed_without_a_reboot(self):
        runner = FakeRunner(verify=(1, 0))
        self.assertEqual(self.slim(runner), "slimmed")
        self.assertEqual(runner.verbs(),
                         ["simslim verify", "simslim on --no-reboot", "simslim verify", "simslim doctor"])
        doctor = runner.calls[-1]
        self.assertEqual(doctor[doctor.index("--requires") + 1], "photos")

    def test_falls_back_to_a_rebooting_slim_and_waits_for_the_boot(self):
        runner = FakeRunner(verify=(1, 1))
        self.assertEqual(self.slim(runner), "rebooted")
        self.assertEqual(runner.verbs(), ["simslim verify", "simslim on --no-reboot", "simslim verify",
                                          "simslim on", "simctl bootstatus", "simslim doctor"])

    def test_failed_slim_continues_stock(self):
        runner = FakeRunner(verify=(1,), on=(1,))
        self.assertEqual(self.slim(runner), "failed")
        self.assertNotIn("simslim doctor", runner.verbs())
        # Not cached: the next boot tries again.
        self.assertEqual(self.slim(runner, booted=False), "failed")

    def test_slimmed_device_is_then_cached(self):
        runner = FakeRunner(verify=(1, 0))
        self.slim(runner)
        self.assertEqual(self.slim(runner, booted=False), "cached")

    def test_uses_the_committed_profile(self):
        runner = FakeRunner()
        self.slim(runner)
        cmd = runner.calls[0]
        self.assertEqual(Path(cmd[cmd.index("--profile") + 1]), sim_slim.DEFAULT_PROFILE)

    def test_profile_env_override(self):
        runner = FakeRunner()
        self.slim(runner, env={**HELD, sim_slim.PROFILE_ENV: "/tmp/lean.json"})
        cmd = runner.calls[0]
        self.assertEqual(cmd[cmd.index("--profile") + 1], "/tmp/lean.json")


class ProfileTests(unittest.TestCase):
    """The committed profile keeps exactly what the Festival app and its tools use."""

    def test_default_profile(self):
        profile = json.loads(sim_slim.DEFAULT_PROFILE.read_text())
        self.assertEqual(profile["except"], ["photos"])
        # Safari web clips (pwa_ios.py install and launch) work without webbookmarksd.
        self.assertEqual(profile["keep"], [])


class BootExclusiveTests(unittest.TestCase):
    """``ios_sim.boot_exclusive`` waits for the boot, slims, and reports a fresh device."""

    def boot(self, boot_code, outcome):
        def run(cmd, **_kwargs):
            code = boot_code if cmd[:3] == ["xcrun", "simctl", "boot"] else 0
            return subprocess.CompletedProcess(cmd, code, stdout="", stderr="")
        with unittest.mock.patch.object(ios_sim, "_run", side_effect=run) as fake, \
                unittest.mock.patch.object(ios_sim.sim_slim, "ensure_slim", return_value=outcome) as slim:
            fresh = ios_sim.boot_exclusive(UDID)
        verbs = [c.args[0][2] for c in fake.call_args_list if c.args[0][:2] == ["xcrun", "simctl"]
                 and c.args[0][2] in ("boot", "bootstatus")]
        return fresh, slim.call_args, verbs

    def test_fresh_boot_slims_after_bootstatus(self):
        fresh, call, verbs = self.boot(0, "verified")
        self.assertTrue(fresh)
        self.assertEqual(verbs, ["boot", "bootstatus"])
        self.assertEqual(call.args, (UDID,))
        self.assertTrue(call.kwargs["booted"])
        self.assertEqual(call.kwargs["env"]["DEVELOPER_DIR"], ios_sim.DEVELOPER_DIR)

    def test_warm_device_is_not_fresh(self):
        fresh, call, _ = self.boot(149, "cached")
        self.assertFalse(fresh)
        self.assertFalse(call.kwargs["booted"])

    def test_a_rebooting_slim_makes_a_warm_device_fresh(self):
        fresh, _, _ = self.boot(149, "rebooted")
        self.assertTrue(fresh)


if __name__ == "__main__":
    unittest.main()
