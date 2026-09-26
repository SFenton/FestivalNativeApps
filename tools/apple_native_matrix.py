#!/usr/bin/env python3
"""Run serial fixture-backed Apple device tests and gate their real UI line coverage."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import signal
import socket
import subprocess
import sys
import time
from pathlib import Path
from urllib.error import URLError
from urllib.request import urlopen

if __package__:
    from .apple_xccov_gate import device_identity, xcode_json
else:
    from apple_xccov_gate import device_identity, xcode_json

ROOT = Path(__file__).resolve().parents[1]
TEST_SOURCE = ROOT / "apple/Apps/iOSUITests/FestivalMobileUITests.swift"
TEST_NAME = re.compile(r"^\s+func (test[A-Za-z0-9_]+)\(", re.MULTILINE)
IOS_RUNTIME = re.compile(
    r"^com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+)-(\d+)(?:-(\d+))?$"
)
DUO_TEST = "testDuoOuterFourRotations"
SERVICE_PORT = 8765
RECOVERY_PORT = 8769
OFFLINE_PORT = 8771
SCORE_OFFLINE_PORT = 8772
SHOP_OFFLINE_PORT = 8773
ROLLOVER_PORTS = {"iphone": 8767, "ipad": 8768}
DEVICE_FAMILIES = {"iphone": "iPhone", "ipad": "iPad"}
LOCK_FILE = Path("/tmp/festival-native-matrix.lock")
FIXTURE_INPUTS = (
    "tools/mock_service.py",
    "contracts/fixtures/publication.json",
    "contracts/fixtures/songs-empty.json",
    "contracts/fixtures/songs-demo.json",
    "contracts/fixtures/path-demo.json",
    "contracts/fixtures/shop-demo.json",
)
REQUIRED_INPUTS = (
    *FIXTURE_INPUTS,
    "apple/Apps/iOSUITests/FestivalMobileUITests.swift",
    "apple/project.yml",
    "apple/Package.swift",
    "apple/FestivalNativeApple.xcodeproj/project.pbxproj",
    "apple/FestivalNativeApple.xcodeproj/xcshareddata/xcschemes/FestivalMobile.xcscheme",
    "contracts/fluent-tokens.json",
    "contracts/coverage-rules.json",
    "tools/apple_native_matrix.py",
    "tools/apple_xccov_gate.py",
)
INPUT_GLOBS = (
    "apple/Sources/**/*.swift",
    "apple/Apps/iOS/**/*.swift",
    "apple/Apps/iOS/Assets.xcassets/**/*",
    "apple/Tests/FestivalUITests/Fixtures/**/*",
)


class MatrixError(ValueError):
    """A setup or test failure that must not become passing device evidence."""


def acquire_matrix_lock(path: Path = LOCK_FILE) -> int:
    """Prevent two runner instances from switching the same simulator mid-suite.

    Args:
        path: Persistent host-wide lock path; never unlink it between runs.

    Returns:
        Non-inheritable locked descriptor to close only when the matrix exits.

    Raises:
        MatrixError: If the lock is busy, inaccessible or a symlink.
    """
    try:
        descriptor = os.open(
            path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600
        )
    except OSError as error:
        raise MatrixError(f"Cannot open exclusive simulator lock {path}: {error}") from error
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as error:
        os.close(descriptor)
        raise MatrixError(f"Another Apple matrix owns the simulators: {error}") from error
    return descriptor


def file_hashes(root: Path, names: tuple[str, ...]) -> dict[str, str]:
    """Hash exact, in-repository test inputs without exposing their contents.

    Args:
        root: Native repository root.
        names: Relative files, not directories or symlinks.

    Returns:
        Relative source paths to SHA-256 digests.

    Raises:
        MatrixError: If any expected input is absent or points outside the repo.
    """
    hashes: dict[str, str] = {}
    for name in sorted(names):
        path = root / name
        if (
            path.is_symlink()
            or not path.resolve().is_relative_to(root.resolve())
            or not path.is_file()
        ):
            raise MatrixError(f"Native test input is missing or a symlink: {name}")
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def input_hashes(root: Path = ROOT) -> dict[str, str]:
    """Snapshot the app, fixture, Xcode project, test and coverage-rule bytes.

    Args:
        root: Repository containing generated Xcode project and tracked sources.

    Returns:
        Input paths and exact hashes, including generated asset metadata.

    Raises:
        MatrixError: On missing generated project, source or fixture inputs.
    """
    names = set(REQUIRED_INPUTS)
    source_files = list(root.glob("apple/Sources/**/*.swift"))
    if not source_files:
        raise MatrixError("No compiled Apple Swift package sources found")
    for file in source_files:
        names.add(file.relative_to(root).as_posix())
    for pattern in INPUT_GLOBS[1:]:
        names.update(
            file.relative_to(root).as_posix()
            for file in root.glob(pattern) if file.is_file()
        )
    return file_hashes(root, tuple(names))


def require_unchanged(expected: dict[str, str], *, root: Path = ROOT) -> None:
    """Fail the entire run when any compiled or evidence input drifts.

    Args:
        expected: Source snapshot created before the first device test.
        root: Repository whose selected test inputs must remain unchanged.

    Raises:
        MatrixError: For changed, added, missing or replaced inputs.
    """
    current = input_hashes(root)
    if current != expected:
        changed = sorted(
            name for name in current.keys() | expected.keys()
            if current.get(name) != expected.get(name)
        )
        raise MatrixError(
            "Native test or fixture inputs changed during the matrix: "
            + ", ".join(changed[:12])
        )


def selected_tests(source: str, requested: list[str]) -> list[str]:
    """Select real native tests, excluding only the separate unverified Duo pose.

    Args:
        source: Current UI-test Swift source to discover ordinary test functions.
        requested: Optional test-method names for a targeted non-coverage run.

    Returns:
        Exact selected method names in source or caller order.

    Raises:
        MatrixError: If a selector is absent, duplicated or targets the Duo harness.
    """
    discovered = TEST_NAME.findall(source)
    if not discovered or len(set(discovered)) != len(discovered):
        raise MatrixError("Missing or duplicate native UI-test methods")
    allowed = set(discovered) - {DUO_TEST}
    if requested:
        if len(set(requested)) != len(requested) or not set(requested) <= allowed:
            raise MatrixError("Unknown, duplicate or Duo-only UI-test selector")
        return requested
    return [name for name in discovered if name != DUO_TEST]


def booted_targets(report: dict, allowed: set[str]) -> set[str]:
    """Fail without touching simulators owned by another project.

    Args:
        report: `simctl list devices booted --json` output.
        allowed: Exactly the two caller-specified FST iPhone/iPad simulator IDs.

    Returns:
        Booted target IDs, at most one.

    Raises:
        MatrixError: For malformed data, a foreign booted device or concurrent devices.
    """
    runtimes = report.get("devices")
    if not isinstance(runtimes, dict):
        raise MatrixError("simctl did not return a device inventory")
    booted: set[str] = set()
    for devices in runtimes.values():
        if not isinstance(devices, list):
            raise MatrixError("simctl returned an invalid runtime")
        for device in devices:
            if not isinstance(device, dict) or device.get("state") != "Booted":
                continue
            identifier = device.get("udid")
            if not isinstance(identifier, str) or not identifier:
                raise MatrixError("simctl returned a booted device without an ID")
            booted.add(identifier)
    if len(booted) > 1 or not booted <= allowed:
        raise MatrixError(
            "Another simulator is booted; leave unrelated devices untouched: "
            + ", ".join(sorted(booted))
        )
    return booted


def validate_product_devices(
    report: dict, requested: dict[str, str], expected_os: dict[str, str]
) -> dict[str, str]:
    """Reject wrong runtimes or foreign UDIDs before any simulator is modified.

    Args:
        report: Full `simctl list devices --json` inventory.
        requested: iPhone and iPad FST product simulator identifiers.
        expected_os: Exact iOS/iPadOS versions requested for this evidence run.

    Returns:
        Actual OS version of the approved iPhone and iPad simulator.

    Raises:
        MatrixError: If a requested simulator is absent, foreign or on the wrong OS.
    """
    runtimes = report.get("devices")
    if not isinstance(runtimes, dict):
        raise MatrixError("simctl did not return a complete device inventory")
    devices = [
        (runtime, device) for runtime, entries in runtimes.items()
        if isinstance(runtime, str) and isinstance(entries, list)
        for device in entries if isinstance(device, dict)
    ]
    versions: dict[str, str] = {}
    for family, identifier in requested.items():
        matches = [
            (runtime, device) for runtime, device in devices
            if device.get("udid") == identifier
        ]
        if len(matches) != 1:
            raise MatrixError(f"{family}: FST simulator {identifier} was not found exactly once")
        runtime, device = matches[0]
        kind = device.get("deviceTypeIdentifier")
        if (
            not isinstance(device.get("name"), str)
            or not device["name"].startswith("FST ")
            or DEVICE_FAMILIES[family] not in device["name"]
            or not isinstance(kind, str)
            or f"SimDeviceType.{DEVICE_FAMILIES[family]}" not in kind
        ):
            raise MatrixError(f"{identifier}: refusing to use a non-FST {family} simulator")
        version = IOS_RUNTIME.fullmatch(runtime)
        if version is None:
            raise MatrixError(f"{identifier}: unrecognized iOS runtime {runtime}")
        actual_os = ".".join(part for part in version.groups() if part is not None)
        if actual_os != expected_os[family]:
            raise MatrixError(
                f"{family} simulator {identifier} runs iOS {actual_os}, "
                f"expected iOS {expected_os[family]}"
            )
        versions[family] = actual_os
    return versions


def verify_result(summary: dict, *, device: str, identifier: str, expected: int) -> None:
    """Reject a green Xcode exit code with missing, skipped or wrong-device tests.

    Args:
        summary: Native xcresulttool test summary.
        device: Requested family, `iphone` or `ipad`.
        identifier: Expected destination UDID.
        expected: Number of test cases deliberately selected.

    Raises:
        MatrixError: On a partial run, skipped test, wrong device or failed case.
    """
    family, actual = device_identity(summary)
    if (family.lower(), actual) != (device, identifier):
        raise MatrixError(f"Test result came from unexpected device {family} {actual}")
    if (
        summary.get("result") != "Passed"
        or summary.get("totalTestCount") != expected
        or summary.get("passedTests") != expected
        or summary.get("failedTests") != 0
        or summary.get("skippedTests") != 0
    ):
        raise MatrixError(
            f"{device}: expected {expected} passing tests, got "
            f"{summary.get('passedTests')} passed, {summary.get('failedTests')} failed, "
            f"{summary.get('skippedTests')} skipped out of {summary.get('totalTestCount')}"
        )


def verify_test_names(report: dict, expected: list[str]) -> None:
    """Require exactly the planned executable test methods, not just their count.

    Args:
        report: xcresulttool's nested `test-results tests` tree.
        expected: Test methods discovered before the first device was launched.

    Raises:
        MatrixError: If a test was replaced, omitted, duplicated or malformed.
    """
    nodes = report.get("testNodes")
    if not isinstance(nodes, list):
        raise MatrixError("Xcode did not return a test-case tree")
    pending = nodes.copy()
    executed: list[str] = []
    while pending:
        node = pending.pop()
        if not isinstance(node, dict):
            raise MatrixError("Xcode returned a malformed test node")
        if node.get("nodeType") == "Test Case":
            name = node.get("name")
            if not isinstance(name, str) or not name.startswith("test") or not name.endswith("()"):
                raise MatrixError("Xcode returned an unrecognized test case")
            executed.append(name[:-2])
        children = node.get("children", [])
        if not isinstance(children, list):
            raise MatrixError("Xcode returned malformed nested test cases")
        pending.extend(children)
    if len(executed) != len(set(executed)) or set(executed) != set(expected):
        raise MatrixError(
            "Xcode ran the wrong test methods; missing "
            + repr(sorted(set(expected) - set(executed)))
            + ", unexpected " + repr(sorted(set(executed) - set(expected)))
        )


def run_checked(
    command: list[str], *, label: str, env: dict[str, str], timeout: int = 300
) -> str:
    """Run a noninteractive local command and surface its full diagnostic on failure.

    Args:
        command: Executable and discrete arguments, never shell-constructed text.
        label: Operation for actionable diagnostics.
        env: Pinned Xcode developer directory and inherited local environment.
        timeout: Bounded seconds for a simulator operation or coverage report.

    Returns:
        Standard output as text.

    Raises:
        MatrixError: If the command exits unsuccessfully.
    """
    result = subprocess.run(
        command, text=True, capture_output=True, env=env,
        check=False, timeout=timeout,
    )
    if result.returncode:
        raise MatrixError(
            f"{label} exited {result.returncode}: "
            f"{result.stderr.strip() or result.stdout.strip()}"
        )
    return result.stdout


def fixture_json(port: int, endpoint: str) -> dict:
    """Read only the local fixture's own allowlisted health or catalogue endpoint.

    Args:
        port: Dedicated loopback fixture listener.
        endpoint: Exact fixture path, never an external host.

    Returns:
        Valid JSON response object.

    Raises:
        MatrixError: If the fixture sends an unexpected JSON shape.
    """
    with urlopen(f"http://127.0.0.1:{port}{endpoint}", timeout=2) as response:
        value = json.load(response)
    if not isinstance(value, dict):
        raise MatrixError(f"Fixture {port}{endpoint} returned invalid JSON")
    return value


def fixture_options(flags: list[str]) -> dict[str, bool | int | None]:
    """Allow only known mock modes and their immutable launch flags.

    Args:
        flags: CLI switches passed to the local fixture process.

    Returns:
        Exact health flags expected from the new process.

    Raises:
        MatrixError: If a caller tries to start an unknown fixture mode.
    """
    options: dict[str, bool | int | None] = {
        "unpinned": False, "rolloverOnRead": None,
        "failFirstWhiteCatalogue": False,
        "stopAfterFirstSongs": False,
        "stopAfterFirstScore": False,
        "stopAfterFirstShop": False,
    }
    if flags == []:
        return options
    if flags == ["--unpinned", "--rollover-on-read", "2"]:
        return dict(options, unpinned=True, rolloverOnRead=2)
    if flags == ["--fail-first-white-catalogue"]:
        return dict(options, failFirstWhiteCatalogue=True)
    if flags == ["--unpinned", "--stop-after-first-songs"]:
        return dict(options, unpinned=True, stopAfterFirstSongs=True)
    if flags == ["--unpinned", "--stop-after-first-score"]:
        return dict(options, unpinned=True, stopAfterFirstScore=True)
    if flags == ["--unpinned", "--stop-after-first-shop"]:
        return dict(options, unpinned=True, stopAfterFirstShop=True)
    raise MatrixError("Unknown or non-deterministic local fixture flags")


def require_fixture_identity(
    identity: dict, flags: list[str], expected: dict[str, str], port: int
) -> None:
    """Pin reused and newly started listeners to their actual startup bytes.

    Args:
        identity: Local fixture health payload containing immutable source hashes.
        flags: Known CLI flags requested by the matrix.
        expected: Baseline SHA-256 hashes for loaded mock code and three JSON inputs.
        port: Loopback port for a precise error.

    Raises:
        MatrixError: On stale code, old data, unpinned/rollover flags or malformed health.
    """
    if (
        identity.get("ready") is not True
        or identity.get("sourceHashes") != expected
        or identity.get("options") != fixture_options(flags)
    ):
        raise MatrixError(f"Fixture {port} is stale or has incompatible launch flags")


def port_is_free(port: int) -> bool:
    """Detect a live loopback listener without mistaking TIME_WAIT for ownership.

    Args:
        port: Loopback port reserved for one fixture.

    Returns:
        True only when a new loopback connection is refused.

    Raises:
        MatrixError: On a socket failure other than a refused connection.
    """
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.5):
            return False
    except ConnectionRefusedError:
        return True
    except OSError as error:
        raise MatrixError(f"Cannot safely inspect loopback port {port}: {error}") from error


def start_fixture(
    port: int, flags: list[str], evidence: Path, *, label: str = "shared",
    allow_existing: bool = False, expected_hashes: dict[str, str] | None = None
) -> subprocess.Popen | None:
    """Start a private stateful fixture or verify a reusable ordinary listener.

    Args:
        port: Known local fixture port.
        flags: Fixed scenario switches for this listener.
        evidence: Existing result directory for sanitized process logs.
        label: Device name used to keep same-port fixture logs distinct.
        allow_existing: Reuse only a verified ordinary service at port 8765.
        expected_hashes: Pinned mock/JSON inputs captured at matrix start.

    Returns:
        The launched process, or None when reusing a verified ordinary fixture.

    Raises:
        MatrixError: On a busy stateful port, failed startup or wrong ordinary service.
    """
    expected = expected_hashes if expected_hashes is not None else file_hashes(
        ROOT, FIXTURE_INPUTS
    )
    fixture_options(flags)
    if not port_is_free(port):
        if not allow_existing:
            raise MatrixError(f"127.0.0.1:{port} is in use; do not replace its process")
        try:
            health = fixture_json(port, "/__fixture__/health")
            require_fixture_identity(health, flags, expected, port)
            songs = fixture_json(port, "/api/songs?scenario=art-white")
        except (OSError, URLError, ValueError) as error:
            raise MatrixError(f"127.0.0.1:{port} is not the expected FST fixture: {error}") from error
        candidates = songs.get("songs")
        if (
            not isinstance(candidates, list)
            or len(candidates) != 1
            or not isinstance(candidates[0], dict)
            or candidates[0].get("songId") != "fixture-white"
        ):
            raise MatrixError(f"127.0.0.1:{port} is not the expected FST fixture")
        print(f"Reusing verified loopback fixture on {port}")
        return None

    log = evidence / f"fixture-{label}-{port}.log"
    stream = log.open("x", encoding="utf-8")
    try:
        process = subprocess.Popen(
            [sys.executable, "-u", str(ROOT / "tools/mock_service.py"), "--port", str(port), *flags],
            cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
        )
    finally:
        stream.close()
    healthy = False
    try:
        for _ in range(50):
            if process.poll() is not None:
                raise MatrixError(f"Fixture {port} exited early; see {log}")
            try:
                identity = fixture_json(port, "/__fixture__/health")
            except (OSError, URLError):
                time.sleep(0.1)
                continue
            require_fixture_identity(identity, flags, expected, port)
            healthy = True
            return process
        raise MatrixError(f"Fixture {port} did not become healthy; see {log}")
    finally:
        if not healthy:
            stop_fixture(process)


def stop_fixture(process: subprocess.Popen | None) -> None:
    """Stop only a child fixture launched by this runner, never a reused listener.

    Args:
        process: Managed fixture process or None for a separately owned listener.
    """
    if process is None or process.poll() is not None:
        return
    try:
        os.kill(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        if process.poll() is None:
            try:
                os.kill(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        process.wait(timeout=5)


def active_devices(env: dict[str, str], allowed: set[str]) -> set[str]:
    """Read booted device IDs through Xcode's documented JSON simulator output.

    Args:
        env: Pinned Xcode environment.
        allowed: Explicit product simulator UDIDs; no other device is ours to stop.

    Returns:
        The single current product device, or an empty set.
    """
    raw = run_checked(
        ["xcrun", "simctl", "list", "devices", "booted", "--json"],
        label="simctl list", env=env,
    )
    try:
        return booted_targets(json.loads(raw), allowed)
    except json.JSONDecodeError as error:
        raise MatrixError(f"simctl returned invalid JSON: {error}") from error


def boot_device(
    identifier: str, env: dict[str, str], allowed: set[str]
) -> None:
    """Reuse an already-running product simulator; switch only between explicit IDs.

    Args:
        identifier: FST device chosen for this serial suite.
        env: Pinned Xcode environment.
        allowed: Exactly the user-specified iPhone/iPad IDs.
    """
    current = active_devices(env, allowed)
    if current == {identifier}:
        print(f"Reusing booted product simulator {identifier}")
        return
    if current:
        run_checked(
            ["xcrun", "simctl", "shutdown", next(iter(current))],
            label="simctl shutdown", env=env,
        )
    run_checked(["xcrun", "simctl", "boot", identifier], label="simctl boot", env=env)
    run_checked(
        ["xcrun", "simctl", "bootstatus", identifier, "-b"],
        label="simctl bootstatus", env=env,
    )
    if active_devices(env, allowed) != {identifier}:
        raise MatrixError(f"Only {identifier} may be booted during its test suite")


def device_order(
    selection: str, booted: set[str], iphone: str, ipad: str
) -> tuple[str, ...]:
    """Start with the already-running product device to avoid a needless reboot.

    Args:
        selection: Requested `iphone`, `ipad` or `both` matrix.
        booted: At most one previously validated product simulator ID.
        iphone: Selected FST iPhone UDID.
        ipad: Selected FST iPad UDID.

    Returns:
        One requested family or both families in a reuse-first serial order.
    """
    if selection != "both":
        return (selection,)
    if booted == {ipad}:
        return ("ipad", "iphone")
    if not booted or booted == {iphone}:
        return ("iphone", "ipad")
    raise MatrixError("Cannot order an unrecognized booted simulator")


def run_device(
    device: str, identifier: str, evidence: Path,
    *, expected_tests: list[str], baseline: dict[str, str], env: dict[str, str]
) -> Path:
    """Run one full or explicit-targeted native suite with four fresh fixtures.

    Args:
        device: iPhone or iPad role.
        identifier: Product simulator UDID for this role.
        evidence: Unique result directory containing complete logs and .xcresult.
        expected_tests: Frozen selected methods from before the first device.
        baseline: Hashed fixture, app, test and project inputs from matrix start.
        env: Pinned Xcode environment.

    Returns:
        Path to a complete, passing simulator test result.

    Raises:
        MatrixError: If fixtures, build, test discovery or result validation fails.
    """
    rollover = ROLLOVER_PORTS[device]
    managed: list[subprocess.Popen] = []
    try:
        fixture_hashes = {name: baseline[name] for name in FIXTURE_INPUTS}
    except KeyError as error:
        raise MatrixError(f"Missing fixture input snapshot: {error}") from error
    try:
        for port, flags in (
            (rollover, ["--unpinned", "--rollover-on-read", "2"]),
            (RECOVERY_PORT, ["--fail-first-white-catalogue"]),
            (OFFLINE_PORT, ["--unpinned", "--stop-after-first-songs"]),
            (SCORE_OFFLINE_PORT, ["--unpinned", "--stop-after-first-score"]),
            (SHOP_OFFLINE_PORT, ["--unpinned", "--stop-after-first-shop"]),
        ):
            process = start_fixture(
                port, flags, evidence, label=device, expected_hashes=fixture_hashes
            )
            if process is None:
                raise MatrixError(f"Stateful fixture {port} was not freshly started")
            managed.append(process)
        require_unchanged(baseline)
        result = evidence / f"{device}.xcresult"
        command = [
            "xcodebuild", "-quiet", "-project", str(ROOT / "apple/FestivalNativeApple.xcodeproj"),
            "-scheme", "FestivalMobile", "-configuration", "Debug",
            "-destination", f"platform=iOS Simulator,id={identifier}",
            "-derivedDataPath", str(ROOT / f"apple/DerivedData/native-matrix-{device}"),
            "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO",
            "-enableCodeCoverage", "YES",
        ]
        command.extend(
            f"-only-testing:FestivalMobileUITests/FestivalMobileUITests/{name}"
            for name in expected_tests
        )
        command.extend(["test", "CODE_SIGNING_ALLOWED=NO"])
        log = evidence / f"{device}-xcodebuild.log"
        with log.open("x", encoding="utf-8") as output:
            try:
                process = subprocess.run(
                    command, cwd=ROOT, env=env, text=True,
                    stdout=output, stderr=subprocess.STDOUT,
                    check=False, timeout=1200,
                )
            except subprocess.TimeoutExpired as error:
                raise MatrixError(f"{device} xcodebuild timed out; see {log}") from error
        if process.returncode:
            raise MatrixError(
                f"{device} xcodebuild exited {process.returncode}; see {log}\n"
                + log.read_text(encoding="utf-8")[-4000:]
            )
        summary = xcode_json(
            "xcresulttool", ["get", "test-results", "summary", "--path", str(result)]
        )
        verify_result(
            summary, device=device, identifier=identifier, expected=len(expected_tests)
        )
        cases = xcode_json(
            "xcresulttool", ["get", "test-results", "tests", "--path", str(result)]
        )
        verify_test_names(cases, expected_tests)
        require_unchanged(baseline)
        print(f"{device}: {len(expected_tests)}/{len(expected_tests)} passed; {result}")
        return result
    finally:
        for process in reversed(managed):
            stop_fixture(process)


def main(argv: list[str] | None = None) -> int:
    """Require all setup/evidence gates before declaring a serial native run passed.

    Args:
        argv: Optional CLI arguments for deterministic unit tests.

    Returns:
        Zero only if every selected suite and its applicable coverage gate passes.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iphone-udid", required=True)
    parser.add_argument("--ipad-udid", required=True)
    parser.add_argument("--iphone-os", required=True, help="Required iOS version, e.g. 26.5")
    parser.add_argument("--ipad-os", required=True, help="Required iPadOS version, e.g. 26.5")
    parser.add_argument("--device", choices=("iphone", "ipad", "both"), default="both")
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--only-test", action="append", default=[])
    parser.add_argument("--no-coverage-gate", action="store_true")
    args = parser.parse_args(argv)
    if args.iphone_udid == args.ipad_udid:
        parser.error("iPhone and iPad need distinct simulator IDs")
    if not all(re.fullmatch(r"\d+\.\d+(?:\.\d+)?", version)
               for version in (args.iphone_os, args.ipad_os)):
        parser.error("Explicit iPhone and iPad OS versions must be dotted numerals")
    if (args.device != "both" or args.only_test) and not args.no_coverage_gate:
        parser.error("A targeted or single-device run cannot certify the paired UI coverage gate")
    evidence = args.evidence_dir.resolve()
    if evidence == ROOT or ROOT in evidence.parents or evidence.exists():
        parser.error("Use a new evidence directory outside the source repository")
    lock: int | None = None
    try:
        lock = acquire_matrix_lock()
        baseline = input_hashes()
        planned = selected_tests(TEST_SOURCE.read_text(encoding="utf-8"), args.only_test)
        env = os.environ.copy()
        env["DEVELOPER_DIR"] = env.get(
            "DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer"
        )
        os.environ["DEVELOPER_DIR"] = env["DEVELOPER_DIR"]
        allowed = {args.iphone_udid, args.ipad_udid}
        inventory = run_checked(
            ["xcrun", "simctl", "list", "devices", "--json"],
            label="simctl inventory", env=env,
        )
        try:
            versions = validate_product_devices(
                json.loads(inventory),
                {"iphone": args.iphone_udid, "ipad": args.ipad_udid},
                {"iphone": args.iphone_os, "ipad": args.ipad_os},
            )
        except json.JSONDecodeError as error:
            raise MatrixError(f"simctl inventory is not valid JSON: {error}") from error
        print(
            f"Verified simulator runtimes: iPhone iOS {versions['iphone']}, "
            f"iPad iPadOS {versions['ipad']}"
        )
        current = active_devices(env, allowed)
        require_unchanged(baseline)
        evidence.mkdir(parents=True)
        ordinary = start_fixture(
            SERVICE_PORT, [], evidence, allow_existing=True,
            expected_hashes={name: baseline[name] for name in FIXTURE_INPUTS},
        )
        try:
            results: list[Path] = []
            for device in device_order(
                args.device, current, args.iphone_udid, args.ipad_udid
            ):
                identifier = args.iphone_udid if device == "iphone" else args.ipad_udid
                boot_device(identifier, env, allowed)
                results.append(run_device(
                    device, identifier, evidence,
                    expected_tests=planned, baseline=baseline, env=env,
                ))
                require_unchanged(baseline)
            require_unchanged(baseline)
            if not args.no_coverage_gate:
                output = run_checked(
                    [sys.executable, str(ROOT / "tools/apple_xccov_gate.py"),
                     *(argument for result in results for argument in ("--result", str(result)))],
                    label="iOS UI/app line coverage", env=env, timeout=900,
                )
                require_unchanged(baseline)
                print(output.strip())
            else:
                require_unchanged(baseline)
                print("Paired UI/app coverage gate intentionally not run for this run")
        finally:
            stop_fixture(ordinary)
    except (OSError, subprocess.SubprocessError, MatrixError, URLError, ValueError) as error:
        print(f"Apple native matrix failed: {error}", file=sys.stderr)
        return 1
    finally:
        if lock is not None:
            os.close(lock)
    return 0


def exit_on_signal(number: int, _frame: object) -> None:
    """Enter normal Python unwinding so only owned child processes are stopped.

    Args:
        number: SIGTERM or SIGHUP delivered to this runner.
        _frame: Signal-frame metadata, not needed for cleanup.
    """
    raise SystemExit(128 + number)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, exit_on_signal)
    signal.signal(signal.SIGHUP, exit_on_signal)
    raise SystemExit(main())
