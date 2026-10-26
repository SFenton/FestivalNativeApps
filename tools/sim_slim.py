"""Slim a held iOS simulator with simslim so more lanes fit in the devcap ``simulator`` slots.

[simslim](https://github.com/MobAI-App/simslim) disables the background daemons a journey
does not need (a stock simulator is ~4 GB and ~258 processes; slimmed, well under 1 GB) with
launchd overrides stored on the device, so a slimmed simulator stays slim across shutdowns.
``ios_sim.boot_exclusive`` calls :func:`ensure_slim` right after every boot, inside the
devcap hold and before the app launches; ``python3 tools/ios_sim.py slim --device <alias>``
does it on its own. Rules: ``.agents/platforms/apple/capacity.md`` (Slim simulators).

- Idempotent: a simulator already on the profile costs one ``simslim verify`` (about 3 s),
  and nothing at all when this process verified it and it has stayed booted since. A stock
  one costs about 90 s the first time.
- ``FST_SIM_SLIM=0`` leaves the simulator stock (A/B and perf runs); ``FST_SIM_SLIM_PROFILE``
  names another profile file. GitHub Actions runners stay stock.
- A missing ``simslim``, a UDID this process does not hold, or a failed ``simslim on`` is a
  warning, never a failure: the run goes ahead on the simulator as it is.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Callable, Mapping

sys.path.insert(0, str(Path(__file__).resolve().parent))
import devcap  # noqa: E402  (the hold that must cover every slim)

# region Configuration

#: Default profile: everything off except what FST journeys and the PWA lab use.
DEFAULT_PROFILE = Path(__file__).resolve().parent / "simslim" / "ui.json"
#: ``0`` skips slimming for this run (the stored overrides of an already slim device stay).
SLIM_ENV = "FST_SIM_SLIM"
#: Path of a profile file to use instead of ``DEFAULT_PROFILE``.
PROFILE_ENV = "FST_SIM_SLIM_PROFILE"
#: ``simslim doctor`` features the profile keeps; checked after each fresh slim.
REQUIRED_FEATURES = ("photos",)

Runner = Callable[..., subprocess.CompletedProcess]

#: ``(udid, profile)`` pairs this process verified; dropped again whenever that device boots.
_verified: set[tuple[str, str]] = set()

# endregion

# region Slimming


def profile_path(env: Mapping[str, str] | None = None) -> Path:
    """Return the profile file to apply.

    Args:
        env: Environment to read ``FST_SIM_SLIM_PROFILE`` from (default ``os.environ``).

    Returns:
        ``FST_SIM_SLIM_PROFILE`` when set, else ``DEFAULT_PROFILE``.
    """
    env = os.environ if env is None else env
    return Path(env[PROFILE_ENV]).expanduser() if env.get(PROFILE_ENV) else DEFAULT_PROFILE


def skip_reason(udid: str, env: Mapping[str, str] | None = None,
                which: Callable[[str], str | None] = shutil.which) -> str | None:
    """Say why ``udid`` must stay as it is, or None when it may be slimmed.

    Args:
        udid: Simulator to slim.
        env: Environment to read (default ``os.environ``; ``devcap.hold`` keeps
            ``DEVCAP_HELD`` there for the block it covers).
        which: ``shutil.which`` (injectable for tests).

    Returns:
        A short reason (opt-out, CI, simslim missing, gate not held), or None.
    """
    env = os.environ if env is None else env
    if env.get(SLIM_ENV) == "0":
        return f"{SLIM_ENV}=0"
    if env.get("GITHUB_ACTIONS") == "true":
        return "GitHub Actions runner (CI simulators stay stock)"
    if which("simslim") is None:
        return "simslim not installed (brew install mobai-app/tap/simslim)"
    held = {name for name in env.get(devcap.HELD_ENV, "").split(",") if name}
    if devcap.device_gate(udid) not in held:
        return f"no devcap hold on {udid} (never slim a simulator you do not hold)"
    return None


def ensure_slim(udid: str, *, booted: bool = True, env: Mapping[str, str] | None = None,
                run: Runner = subprocess.run, which: Callable[[str], str | None] = shutil.which) -> str:
    """Bring a booted, held simulator onto the slim profile.

    Call inside the devcap hold for ``udid``, after the boot finished and before the app
    launches. A fresh slim may reboot the simulator (``simslim on`` without
    ``--no-reboot``), which resets an iPhone Duo to folded; callers that set a pose do so
    after this returns.

    Args:
        udid: Booted simulator to slim.
        booted: True when the device booted since this process last looked at it (forces
            a ``simslim verify`` even when it was verified before).
        env: Environment for the skip checks and subprocesses (default ``os.environ``).
        run: ``subprocess.run`` (injectable for tests).
        which: ``shutil.which`` (injectable for tests).

    Returns:
        ``skipped``, ``cached`` (verified earlier and booted since), ``verified`` (already
        slim), ``slimmed``, ``rebooted`` (slimmed with a reboot) or ``failed`` (left stock).
    """
    env = dict(os.environ if env is None else env)
    if reason := skip_reason(udid, env, which):
        print(f"sim_slim: leaving {udid} as it is: {reason}", file=sys.stderr)
        return "skipped"
    profile = str(profile_path(env))
    key = (udid, profile)
    if booted:
        _verified.discard(key)
    elif key in _verified:
        return "cached"

    def simslim(*args: str) -> bool:
        return run(["simslim", *args], capture_output=True, text=True, check=False, env=env).returncode == 0

    name = Path(profile).name
    if simslim("verify", udid, "--profile", profile):
        _verified.add(key)
        print(f"sim_slim: {udid} already slim ({name})", file=sys.stderr)
        return "verified"
    print(f"sim_slim: slimming {udid} ({name}; about 90 s the first time)", file=sys.stderr)
    # --no-reboot only moves toward more-disabled; a daemon the profile wants back on needs a reboot.
    simslim("on", udid, "--no-reboot", "--profile", profile)
    outcome = "slimmed"
    if not simslim("verify", udid, "--profile", profile):
        if not simslim("on", udid, "--profile", profile):
            print(f"sim_slim: simslim on failed for {udid}; continuing stock", file=sys.stderr)
            return "failed"
        run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture_output=True, check=False, env=env)
        outcome = "rebooted"
    _verified.add(key)
    if not simslim("doctor", udid, "--requires", ",".join(REQUIRED_FEATURES)):
        print(f"sim_slim: simslim doctor reports {', '.join(REQUIRED_FEATURES)} broken on {udid}",
              file=sys.stderr)
    return outcome

# endregion
