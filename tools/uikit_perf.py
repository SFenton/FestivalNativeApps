#!/usr/bin/env python3
"""A/B performance of the SwiftUI app and its UIKit port on one simulator.

Measures frame rate, hitches, main-thread cost, CPU, GPU and memory per surface, cold launch to first content, and
navigation (push and pop), the way Fenton-HASS-Native measured its UIKit port. Method and how to read the tables:
``.agents/testing/apple/uikit-perf.md``.

Per surface, per round, per app (the order alternates each round): a fresh install, a launch whose environment opens the
surface and asks the app to measure itself (``FST_PERF_AUTORUN``; ``apple/Sources/FestivalUI/Diagnostics``: 8 s idle and
two 8 s scrolls at 900 pt/s, or push/pop cycles for ``[nav]`` scenarios), and a host sampler (``tools/perf_sampler.py``:
Mac GPU utilisation, the simulator render server's CPU). Both apps are built optimized (``Release`` with the ``DEBUG``
condition, like ``apple_perf.py --probe``) into their own DerivedData, so the debug launch overrides work on optimized code.
Data comes from the loopback fixture service (``tools/mock_service.py``, started here); ``--live`` uses the keyless public
service instead (read-only GETs only, ``.agents/platforms/service-safety.md``).

Examples::

    python3 tools/uikit_perf.py --surfaces tools/uikit-perf-surfaces.txt --family iphone --rounds 3
    python3 tools/uikit_perf.py --family ipad --only "Songs (long list),Settings" --rounds 1 --label smoke
    python3 tools/uikit_perf.py --report apple/build/perf/<label>      # only re-print a finished run's tables
"""
from __future__ import annotations

import argparse
import re
import shlex
import signal
import subprocess
import sys
import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ios_sim  # noqa: E402  (sibling tool: simulator lock, build lock, device aliases)

# region Configuration

REPO_ROOT = Path(__file__).resolve().parent.parent
APPLE_DIR = REPO_ROOT / "apple"
TOOLS_DIR = REPO_ROOT / "tools"
DEFAULT_SURFACES = TOOLS_DIR / "uikit-perf-surfaces.txt"
RESULTS_DIR = APPLE_DIR / "build" / "perf"
#: One DerivedData for both apps' optimized probe builds (never mixed with the Debug ``lane`` build).
DERIVED_DATA = APPLE_DIR / "DerivedData" / "perf-probe"
#: Release optimization with the Debug hooks (``apple_perf.py``'s ``--probe``), so ``FST_DEBUG_*`` and ``FST_PERF_*`` work.
PROBE_SETTINGS = ["SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG"]
#: ``--family`` -> ``ios_sim.DEVICES`` alias.
FAMILIES = {"iphone": "iphone", "ipad": "ipad", "duo": "duo"}
#: Seconds after launch before the app measures (the page loads, art decodes).
DEFAULT_SETTLE = 12.0
#: Slack added to the in-app run's length when waiting for it to finish.
RUN_MARGIN = 40.0
#: Marker the app writes last.
DONE = "FSTPERF_DONE"
#: Env every measured launch gets: no stored profile or song-card filters (nothing is frozen: the real animation cost is
#: the point).
BASE_ENV = {"FST_UI_TEST_CLEAR_PROFILE": "1", "FST_UI_TEST_RESET_SONG_CARDS": "1"}


@dataclass(frozen=True)
class AppUnderTest:
    """One of the two apps being compared.

    Attributes:
        key: ``swiftui`` or ``uikit`` (the label in result file names).
        scheme: Xcode scheme and target.
        executable: Built executable (and ``.app``) name.
        bundle_id: Bundle identifier.
    """

    key: str
    scheme: str
    executable: str
    bundle_id: str


APPS = {
    "swiftui": AppUnderTest("swiftui", "FestivalMobile", "FestivalMobile", ios_sim.BUNDLE_ID),
    "uikit": AppUnderTest("uikit", "FestivalMobileUIKit", "FestivalMobileUIKit", ios_sim.UIKIT_BUNDLE_ID),
}


@dataclass
class Surface:
    """One measured page.

    Attributes:
        name: Display name (row label in the report).
        env: Launch environment that opens it.
        section: ``surfaces`` (launch, idle, scroll) or ``nav`` (launch, push, pop).
    """

    name: str
    env: dict[str, str] = field(default_factory=dict)
    section: str = "surfaces"

# endregion

# region Pure helpers


def parse_surfaces(text: str, only: list[str] | None = None) -> list[Surface]:
    """Parse a surfaces file.

    Args:
        text: File contents: ``[section]`` headers, ``Name|KEY=value KEY=value`` lines, ``#`` comments.
        only: Surface names to keep (exact match); None keeps all.

    Returns:
        Surfaces in file order.

    Raises:
        ValueError: A line without a name, a pair without ``=``, or an unknown section.
    """
    surfaces, section = [], "surfaces"
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            if section not in ("surfaces", "nav"):
                raise ValueError(f"line {number}: unknown section [{section}]")
            continue
        name, _, rest = line.partition("|")
        if not name.strip():
            raise ValueError(f"line {number}: no surface name")
        env = {}
        for pair in shlex.split(rest):
            key, sep, value = pair.partition("=")
            if not sep or not key:
                raise ValueError(f"line {number}: {pair!r} is not KEY=value")
            env[key] = value
        if only is None or name.strip() in only:
            surfaces.append(Surface(name.strip(), env, section))
    return surfaces


def safe_name(name: str) -> str:
    """File-name form of a surface name (``[A-Za-z0-9._-]`` only)."""
    return re.sub(r"[^A-Za-z0-9._-]", "-", name)


def app_order(round_number: int, apps: list[str]) -> list[str]:
    """The apps in the order a round measures them: alternating so neither always runs first.

    Args:
        round_number: 1-based round.
        apps: App keys in the default order.

    Returns:
        ``apps`` on odd rounds, reversed on even rounds.
    """
    return list(apps) if round_number % 2 == 1 else list(reversed(apps))


def run_paths(out: Path, round_number: int, app: str, name: str) -> tuple[Path, Path]:
    """Result and sampler file of one run.

    Args:
        out: Results folder.
        round_number: 1-based round.
        app: App key.
        name: Surface name.

    Returns:
        ``(result tsv, sampler tsv)``, named as ``uikit_perf_report.py`` expects.
    """
    stem = f"r{round_number}-{app}-{safe_name(name)}"
    return out / f"{stem}.tsv", out / f"{stem}.samples.tsv"


def launch_env(surface: Surface, result: Path, settle: float, base_url: str | None, seconds: float = 8.0,
               speed: float = 900.0) -> dict[str, str]:
    """The ``SIMCTL_CHILD_`` environment of one measured launch.

    Args:
        surface: What to open.
        result: File the app writes its ``FSTPERF`` lines to.
        settle: Seconds the app waits before measuring.
        base_url: Fixture service origin, or None for the public service.
        seconds: Length of each idle and scroll run.
        speed: Scroll speed in points per second.

    Returns:
        Environment entries for ``simctl launch``.
    """
    env = dict(BASE_ENV)
    if base_url:
        env["FST_API_BASE_URL"] = base_url
    env.update(surface.env)
    env.update({
        "FST_PERF_AUTORUN": f"{settle:g}", "FST_PERF_FILE": str(result), "FST_PERF_NAME": surface.name,
        "FST_PERF_SECONDS": f"{seconds:g}", "FST_PERF_SPEED": f"{speed:g}",
    })
    return {f"SIMCTL_CHILD_{k}": v for k, v in env.items()}


def run_budget(surface: Surface, settle: float, seconds: float, cycles: int = 6) -> float:
    """Seconds to wait for a run's ``FSTPERF_DONE``.

    Args:
        surface: The surface.
        settle: Settle seconds.
        seconds: Seconds per idle or scroll run.
        cycles: Push/pop cycles of a nav scenario.

    Returns:
        A generous upper bound.
    """
    if surface.section == "nav":
        return settle + cycles * 12 + RUN_MARGIN
    return settle + 3 * (seconds + 1.5) + RUN_MARGIN


def finished(text: str) -> bool:
    """Whether a result file carries the app's final line."""
    return any(line.strip() == DONE for line in text.splitlines())


def build_argv(app: AppUnderTest) -> list[str]:
    """``xcodebuild`` invocation of an app's optimized probe build.

    Args:
        app: The app.

    Returns:
        Argument vector, run from ``apple/``.
    """
    return [
        "xcodebuild", "-project", "FestivalNativeApple.xcodeproj", "-scheme", app.scheme, "-configuration", "Release",
        "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", str(DERIVED_DATA), "build", "-quiet",
        *PROBE_SETTINGS,
    ]


def app_bundle(app: AppUnderTest) -> Path:
    """Path of an app's optimized probe build."""
    return DERIVED_DATA / "Build" / "Products" / "Release-iphonesimulator" / f"{app.executable}.app"


def fixture_args(large: bool = True) -> list[str]:
    """Arguments of the fixture service.

    Args:
        large: Pad the Songs catalogue (108 more songs) and the rankings so the lists are long.

    Returns:
        ``mock_service.py`` arguments (an OS-assigned port).
    """
    return ["--port", "0", *(["--large-catalogue", "--large-rankings"] if large else [])]


def parse_fixture_port(line: str) -> int | None:
    """The port in ``mock_service.py``'s ready line (``Local test fixture service on 127.0.0.1:<port>``)."""
    match = re.search(r"127\.0\.0\.1:(\d+)", line)
    return int(match.group(1)) if match else None

# endregion

# region Running


def log(message: str) -> None:
    """Progress line on stderr."""
    print(message, file=sys.stderr, flush=True)


def build_apps(apps: list[str]) -> int:
    """Build the optimized probe flavour of each app, serialized on the cross-lane build lock.

    Args:
        apps: App keys.

    Returns:
        0, or the first failing build's exit code.
    """
    subprocess.run(["xcodegen", "generate", "-q"], cwd=APPLE_DIR, check=True)
    for key in apps:
        with ios_sim.build_lock():
            log(f"building {key} (Release, -O, DEBUG hooks)")
            result = subprocess.run(build_argv(APPS[key]), cwd=APPLE_DIR, env=ios_sim._env())
        if result.returncode:
            return result.returncode
    return 0


@contextmanager
def fixture_service(enabled: bool):
    """Run the fixture service for a block.

    Args:
        enabled: False yields None (the public service is used).

    Yields:
        The service origin (``http://127.0.0.1:<port>``) or None.
    """
    if not enabled:
        yield None
        return
    process = subprocess.Popen([sys.executable, str(TOOLS_DIR / "mock_service.py"), *fixture_args()],
                               stdout=subprocess.PIPE, text=True)
    try:
        port = parse_fixture_port(process.stdout.readline())
        if port is None:
            raise RuntimeError("the fixture service did not report a port")
        yield f"http://127.0.0.1:{port}"
    finally:
        process.terminate()
        process.wait(timeout=10)


def simctl(*args: str, env: dict[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess:
    """``xcrun simctl`` with Xcode pinned."""
    return subprocess.run(["xcrun", "simctl", *args], env=env or ios_sim._env(), check=check,
                          capture_output=True, text=True)


def run_one(udid: str, app: AppUnderTest, surface: Surface, round_number: int, out: Path, settle: float,
            base_url: str | None, seconds: float) -> bool:
    """One measured run: fresh install, sampler, launch, wait for the app's last line.

    Args:
        udid: Simulator.
        app: App to run.
        surface: Page to open.
        round_number: 1-based round.
        out: Results folder.
        settle: Settle seconds.
        base_url: Fixture origin or None.
        seconds: Seconds per idle or scroll run.

    Returns:
        Whether the app finished its run in time.
    """
    result, samples = run_paths(out, round_number, app.key, surface.name)
    result.unlink(missing_ok=True)
    result.touch()  # the app appends to an existing file
    simctl("terminate", udid, app.bundle_id, check=False)
    simctl("uninstall", udid, app.bundle_id, check=False)
    simctl("install", udid, str(app_bundle(app)))
    sampler = subprocess.Popen([sys.executable, str(TOOLS_DIR / "perf_sampler.py"), "--udid", udid,
                                "--executable", app.executable, "--out", str(samples)])
    ok = False
    try:
        env = {**ios_sim._env(), **launch_env(surface, result, settle, base_url, seconds)}
        simctl("launch", udid, app.bundle_id, env=env)
        deadline = time.time() + run_budget(surface, settle, seconds)
        while time.time() < deadline:
            if finished(result.read_text()):
                ok = True
                break
            time.sleep(1)
    finally:
        sampler.send_signal(signal.SIGTERM)
        sampler.wait(timeout=10)
        simctl("terminate", udid, app.bundle_id, check=False)
    log(f"measured: round {round_number} {app.key} {surface.name}" + ("" if ok else "  (TIMED OUT)"))
    return ok


def run_all(args: argparse.Namespace, surfaces: list[Surface], out: Path) -> int:
    """Every round of every surface and app on one simulator, under the simulator lock.

    Args:
        args: Parsed arguments.
        surfaces: What to measure.
        out: Results folder.

    Returns:
        0 when every run finished, 1 otherwise.
    """
    udid = ios_sim.resolve_device(FAMILIES[args.family])
    apps = [a.strip() for a in args.apps.split(",") if a.strip()]
    failures = 0
    with ios_sim.sim_lock(udid, f"uikit perf {args.family}"), fixture_service(not args.live) as base_url:
        ios_sim.boot_exclusive(udid)
        simctl("bootstatus", udid, "-b")
        for round_number in range(1, args.rounds + 1):
            for surface in surfaces:
                for key in app_order(round_number, apps):
                    if not run_one(udid, APPS[key], surface, round_number, out, args.settle, base_url, args.seconds):
                        failures += 1
    return 1 if failures else 0

# endregion


def main(argv: list[str] | None = None) -> int:
    """Build, measure and print the report.

    Args:
        argv: Arguments (default ``sys.argv[1:]``).

    Returns:
        Exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--surfaces", type=Path, default=DEFAULT_SURFACES, help="surfaces file (default: %(default)s)")
    parser.add_argument("--family", choices=sorted(FAMILIES), default="iphone", help="simulator family")
    parser.add_argument("--rounds", type=int, default=3)
    parser.add_argument("--only", help="comma-separated surface names to run")
    parser.add_argument("--apps", default="swiftui,uikit", help="comma-separated: swiftui, uikit")
    parser.add_argument("--label", default=time.strftime("perf-%Y%m%d-%H%M"),
                        help="results folder name under apple/build/perf")
    parser.add_argument("--settle", type=float, default=DEFAULT_SETTLE, help="seconds before each measurement")
    parser.add_argument("--seconds", type=float, default=8.0, help="seconds per idle and scroll run")
    parser.add_argument("--no-build", action="store_true", help="measure the existing optimized builds")
    parser.add_argument("--live", action="store_true", help="keyless public service instead of the fixture service")
    parser.add_argument("--report", type=Path, help="only print the report of this results folder")
    args = parser.parse_args(argv)
    import uikit_perf_report  # sibling tool

    if args.report:
        return uikit_perf_report.main([str(args.report)])
    only = [n.strip() for n in args.only.split(",")] if args.only else None
    surfaces = parse_surfaces(args.surfaces.read_text(), only)
    if not surfaces:
        parser.error("no surface selected")
    apps = [a.strip() for a in args.apps.split(",") if a.strip()]
    if any(a not in APPS for a in apps):
        parser.error(f"--apps takes {sorted(APPS)}")
    if not args.no_build and (code := build_apps(apps)):
        return code
    out = RESULTS_DIR / args.label
    out.mkdir(parents=True, exist_ok=True)
    status = run_all(args, surfaces, out)
    text, _ = uikit_perf_report.render(uikit_perf_report.collect(out))
    (out / "report.md").write_text(text + "\n")
    print(text)
    log(f"results: {out}")
    return status


if __name__ == "__main__":
    sys.exit(main())
