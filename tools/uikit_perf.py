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
import hashlib
import json
import re
import shlex
import signal
import subprocess
import sys
import time
import urllib.request
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
    bundle_path: Path | None = None
    source_label: str = ""


APPS = {
    "swiftui": AppUnderTest("swiftui", "FestivalMobile", "FestivalMobile", ios_sim.BUNDLE_ID,
                            source_label="current-worktree"),
    "uikit": AppUnderTest("uikit", "FestivalMobileUIKit", "FestivalMobileUIKit", ios_sim.UIKIT_BUNDLE_ID,
                          source_label="current-worktree"),
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
    case_id: str = ""
    mode: str = "scroll"
    min_runs: int = 3
    expect_content: bool = True
    status: str = "measure"
    status_reason: str = ""

    def __post_init__(self):
        if not self.case_id:
            self.case_id = safe_name(self.name)

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
    sections = {
        "surfaces": "scroll", "nav": "nav", "modal": "modal",
        "component": "component", "components": "component",
    }
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            if section not in sections:
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
        clean_name = name.strip()
        mode = env.get("FST_PERF_MODE", sections[section])
        try:
            min_runs = max(1, int(env.get("FST_PERF_MIN_RUNS", "3")))
        except ValueError as exc:
            raise ValueError(f"line {number}: FST_PERF_MIN_RUNS is not an integer") from exc
        case_id = env.get("FST_PERF_CASE_ID", safe_name(clean_name))
        expect_content = env.get("FST_PERF_EXPECT_CONTENT", "1").lower() not in ("0", "false", "no")
        status = env.get("FST_PERF_STATUS", "measure")
        status_reason = env.get("FST_PERF_REASON", "")
        if only is None or clean_name in only or case_id in only:
            surfaces.append(Surface(clean_name, env, section, case_id, mode, min_runs, expect_content, status, status_reason))
    ids = [surface.case_id for surface in surfaces]
    if len(ids) != len(set(ids)):
        raise ValueError("duplicate FST_PERF_CASE_ID in surfaces manifest")
    return surfaces


def safe_name(name: str) -> str:
    """File-name form of a surface name (``[A-Za-z0-9._-]`` only)."""
    return re.sub(r"[^A-Za-z0-9._-]", "-", name)


def app_order(round_number: int, apps: list[str]) -> list[str]:
    """The apps in the order a round measures them, rotating the first arm each round.

    Args:
        round_number: 1-based round.
        apps: App keys in the default order.

    Returns:
        A left rotation of ``apps`` by the 0-based round number.
    """
    if not apps:
        return []
    shift = (round_number - 1) % len(apps)
    return list(apps[shift:] + apps[:shift])


def parse_app_bundle_spec(spec: str) -> AppUnderTest:
    """Parse ``LABEL|ABSOLUTE_APP_PATH|BUNDLE_ID|EXECUTABLE`` for an isolated arm."""
    parts = spec.split("|")
    if len(parts) != 4 or any(not part for part in parts):
        raise ValueError("app bundle must be LABEL|ABSOLUTE_APP_PATH|BUNDLE_ID|EXECUTABLE")
    label, path, bundle_id, executable = parts
    if safe_name(label) != label:
        raise ValueError(f"app arm label must contain only safe filename characters: {label!r}")
    bundle = Path(path).expanduser()
    if not bundle.is_absolute():
        raise ValueError("app bundle path must be absolute")
    if bundle.suffix != ".app":
        raise ValueError("app bundle path must end in .app")
    return AppUnderTest(label, "", executable, bundle_id, bundle, source_label=label)


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
        "FST_PERF_CASE_ID": surface.case_id, "FST_PERF_MODE": surface.mode,
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
    if surface.mode in ("nav", "modal", "component"):
        return settle + cycles * 12 + RUN_MARGIN
    if surface.mode == "latency":
        return settle + seconds + RUN_MARGIN
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
    if app.bundle_path is not None:
        return app.bundle_path
    return DERIVED_DATA / "Build" / "Products" / "Release-iphonesimulator" / f"{app.executable}.app"


def fixture_args(large: bool = True, long_titles: bool = False) -> list[str]:
    """Arguments of the fixture service.

    Args:
        large: Pad the Songs catalogue (108 more songs) and the rankings so the lists are long.

    Returns:
        ``mock_service.py`` arguments (an OS-assigned port).
    """
    return [
        "--port", "0",
        *(["--large-catalogue", "--large-rankings"] if large else []),
        *(["--long-titles"] if long_titles else []),
    ]


def parse_fixture_port(line: str) -> int | None:
    """The port in ``mock_service.py``'s ready line (``Local test fixture service on 127.0.0.1:<port>``)."""
    match = re.search(r"127\.0\.0\.1:(\d+)", line)
    return int(match.group(1)) if match else None


def fixture_health(base_url: str) -> dict:
    """Verify that the selected loopback listener is the requested large fixture.

    The guard prevents an old listener or another lane's service from silently
    becoming the source of a performance run.
    """
    with urllib.request.urlopen(f"{base_url}/__fixture__/health", timeout=5) as response:
        health = json.load(response)
    options = health.get("options", {})
    if health.get("ready") is not True or not options.get("largeCatalogue") or not options.get("largeRankings"):
        raise RuntimeError(f"fixture readiness/wrong-source guard failed: {health!r}")
    with urllib.request.urlopen(f"{base_url}/api/publication", timeout=5) as response:
        publication = json.load(response)
    if publication.get("publicationId") != 7:
        raise RuntimeError(f"fixture publication guard failed: {publication!r}")
    with urllib.request.urlopen(f"{base_url}/api/songs?scenario=demo", timeout=5) as response:
        songs = json.load(response)
    if not any(song.get("songId") == "fixture-pulse" for song in songs.get("songs", [])):
        raise RuntimeError("fixture song guard failed: fixture-pulse is missing")
    return {
        "health": health,
        "publication": publication,
        "songs_count": songs.get("count"),
    }


def sha256_file(path: Path) -> str:
    """Return a content digest for a raw artifact or source file."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_tree(*roots: Path) -> str:
    """Hash source paths in deterministic order for A/B matching."""
    digest = hashlib.sha256()
    files = sorted(path for root in roots for path in (root.rglob("*") if root.is_dir() else [root]) if path.is_file())
    for path in files:
        try:
            relative = path.relative_to(REPO_ROOT).as_posix()
        except ValueError:
            relative = str(path)
        digest.update(relative.encode("utf-8"))
        digest.update(sha256_file(path).encode("ascii"))
    return digest.hexdigest()


def source_identity(surface_path: Path = DEFAULT_SURFACES) -> dict:
    """Capture the exact worktree identity used for the app and tooling."""
    def git(*args: str) -> str:
        return subprocess.run(["git", *args], cwd=REPO_ROOT, capture_output=True, text=True, check=True).stdout.strip()

    status = git("status", "--porcelain")
    changed = [line[3:] for line in status.splitlines() if len(line) > 3]
    app_prefixes = ("apple/Sources/", "apple/Apps/", "apple/Package.swift", "apple/project.yml")
    instrumentation_prefix = "apple/Sources/FestivalUI/Diagnostics/"
    return {
        "commit": git("rev-parse", "HEAD"),
        "dirty": any(path.startswith(app_prefixes) and not path.startswith(instrumentation_prefix) for path in changed),
        "tooling_dirty": any(
            not path.startswith(app_prefixes) or path.startswith(instrumentation_prefix)
            for path in changed
        ),
        "tool_digests": {
            path.relative_to(REPO_ROOT).as_posix(): sha256_file(path)
            for path in (Path(__file__), TOOLS_DIR / "uikit_perf_report.py", TOOLS_DIR / "perf_sampler.py",
                         surface_path)
        },
        "app_source_digest": sha256_tree(
            APPLE_DIR / "Sources", APPLE_DIR / "Apps", APPLE_DIR / "Package.swift", APPLE_DIR / "project.yml"
        ),
    }


def capacity_identity() -> dict:
    """Capture shared admission state without stopping or inspecting other apps."""
    try:
        output = subprocess.run(
            [sys.executable, str(TOOLS_DIR / "devcap.py"), "status"],
            cwd=REPO_ROOT, capture_output=True, text=True, check=True,
        ).stdout
    except (OSError, subprocess.CalledProcessError):
        return {"available": False}
    match = re.search(r"simulator:\s+(\d+)/(\d+)\s+held", output)
    held, slots = (int(match.group(1)), int(match.group(2))) if match else (None, None)
    return {
        "available": True,
        "simulator_slots_held_before_run": held,
        "simulator_slots": slots,
        "other_simulator_workload_present": bool(held),
    }

# endregion

# region Running


def log(message: str) -> None:
    """Progress line on stderr."""
    print(message, file=sys.stderr, flush=True)


def build_apps(apps: list[str], app_map: dict[str, AppUnderTest]) -> int:
    """Build the optimized probe flavour of each app, serialized on the cross-lane build lock.

    Args:
        apps: App keys.

    Returns:
        0, or the first failing build's exit code.
    """
    if any(app_map[key].bundle_path is not None for key in apps):
        raise ValueError("explicit app bundles require --no-build")
    subprocess.run(["xcodegen", "generate", "-q"], cwd=APPLE_DIR, check=True)
    for key in apps:
        with ios_sim.build_lock():
            log(f"building {key} (Release, -O, DEBUG hooks)")
            result = subprocess.run(build_argv(app_map[key]), cwd=APPLE_DIR, env=ios_sim._env())
        if result.returncode:
            return result.returncode
    return 0


@contextmanager
def fixture_service(enabled: bool, long_titles: bool = False):
    """Run the fixture service for a block.

    Args:
        enabled: False yields None (the public service is used).

    Yields:
        ``(origin, health)`` or ``(None, None)`` for live mode.
    """
    if not enabled:
        yield None, None
        return
    process = subprocess.Popen([sys.executable, str(TOOLS_DIR / "mock_service.py"), *fixture_args(long_titles=long_titles)],
                               stdout=subprocess.PIPE, text=True)
    try:
        port = parse_fixture_port(process.stdout.readline())
        if port is None:
            raise RuntimeError("the fixture service did not report a port")
        origin = f"http://127.0.0.1:{port}"
        yield origin, fixture_health(origin)
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
        try:
            sampler.wait(timeout=10)
        except subprocess.TimeoutExpired:
            sampler.kill()
            sampler.wait(timeout=5)
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
    udid = args.udid or ios_sim.resolve_device(FAMILIES[args.family])
    apps = [a.strip() for a in args.apps.split(",") if a.strip()]
    app_map: dict[str, AppUnderTest] = args.app_map
    failures = 0
    with ios_sim.sim_lock(udid, f"uikit perf {args.family}"), fixture_service(
        not args.live, args.long_titles
    ) as fixture:
        base_url, fixture_info = fixture
        manifest = {
            "schema": 2,
            "family": args.family,
            "udid": udid,
            "apps": apps,
            "arms": [
                {"label": app.key, "bundle": str(app_bundle(app)), "bundle_id": app.bundle_id,
                 "executable": app.executable, "source_label": app.source_label,
                 "bundle_digest": sha256_tree(app_bundle(app))}
                for app in (app_map[key] for key in apps)
            ],
            "rounds": args.rounds,
            "settle_seconds": args.settle,
            "measurement_seconds": args.seconds,
            "fixture": {
                "mode": "live" if args.live else "loopback", "base_url": base_url,
                "long_titles": args.long_titles, "health": fixture_info,
            },
            "source": source_identity(args.surfaces),
            "capacity": capacity_identity(),
            "surfaces": [
                {"name": s.name, "case_id": s.case_id, "section": s.section, "mode": s.mode,
                 "min_runs": s.min_runs, "expect_content": s.expect_content,
                 "status": s.status, "status_reason": s.status_reason, "env": s.env}
                for s in surfaces
            ],
        }
        (out / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        # Boot only the explicitly leased FST simulator. Never shut down another
        # project's device or use the legacy boot_exclusive helper.
        simctl("boot", udid, check=False)
        try:
            simctl("bootstatus", udid, "-b")
            for round_number in range(1, args.rounds + 1):
                for surface in surfaces:
                    for key in app_order(round_number, apps):
                        if not run_one(udid, app_map[key], surface, round_number, out, args.settle, base_url, args.seconds):
                            failures += 1
        finally:
            simctl("shutdown", udid, check=False)
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
    parser.add_argument(
        "--app-bundle", action="append", default=[],
        metavar="LABEL|APP|BUNDLE_ID|EXECUTABLE",
        help="isolated prebuilt Release arm; repeat for before/after/reference (requires --no-build)",
    )
    parser.add_argument("--label", default=time.strftime("perf-%Y%m%d-%H%M"),
                        help="results folder name under apple/build/perf")
    parser.add_argument("--settle", type=float, default=DEFAULT_SETTLE, help="seconds before each measurement")
    parser.add_argument("--seconds", type=float, default=8.0, help="seconds per idle and scroll run")
    parser.add_argument("--no-build", action="store_true", help="measure the existing optimized builds")
    parser.add_argument("--live", action="store_true", help="keyless public service instead of the fixture service")
    parser.add_argument("--long-titles", action="store_true", help="fixture variant for real overflowing marquee probes")
    parser.add_argument("--udid", help="explicit owned simulator UDID (overrides --family alias)")
    parser.add_argument("--allow-incomplete", action="store_true", help="keep a smoke run non-zero only for execution failures")
    parser.add_argument("--report", type=Path, help="only print the report of this results folder")
    args = parser.parse_args(argv)
    import uikit_perf_report  # sibling tool

    if args.report:
        return uikit_perf_report.main([str(args.report)])
    only = [n.strip() for n in args.only.split(",")] if args.only else None
    surfaces = parse_surfaces(args.surfaces.read_text(), only)
    if not surfaces:
        parser.error("no surface selected")
    app_map = dict(APPS)
    try:
        for spec in args.app_bundle:
            app = parse_app_bundle_spec(spec)
            if app.key in app_map:
                parser.error(f"duplicate app arm label: {app.key}")
            if not app_bundle(app).exists():
                parser.error(f"app bundle does not exist: {app.bundle_path}")
            app_map[app.key] = app
    except ValueError as exc:
        parser.error(str(exc))
    apps = [a.strip() for a in args.apps.split(",") if a.strip()]
    if any(a not in app_map for a in apps):
        parser.error(f"--apps takes {sorted(app_map)}")
    if args.app_bundle and not args.no_build:
        parser.error("--app-bundle requires --no-build")
    args.app_map = app_map
    if not args.no_build and (code := build_apps(apps, app_map)):
        return code
    out = RESULTS_DIR / args.label
    out.mkdir(parents=True, exist_ok=True)
    status = run_all(args, surfaces, out)
    collected = uikit_perf_report.collect(out)
    manifest = uikit_perf_report.load_manifest(out)
    text, _ = uikit_perf_report.render(collected)
    qualification = uikit_perf_report.qualification_markdown(collected, manifest)
    text = text + ("\n" if text and qualification else "") + qualification
    (out / "report.md").write_text(text + "\n")
    print(text)
    log(f"results: {out}")
    gate = bool(uikit_perf_report.qualify(collected, manifest))
    return status if args.allow_incomplete else max(status, 2 if gate else 0)


if __name__ == "__main__":
    sys.exit(main())
