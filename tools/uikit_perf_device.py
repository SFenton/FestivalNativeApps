#!/usr/bin/env python3
"""Physical iOS A/B trials using isolated signed probes and on-device loopback fixtures."""
from __future__ import annotations

import argparse
import base64
import csv
import json
import plistlib
import re
import subprocess
import sys
import threading
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import parse_qsl, unquote, urlsplit
from urllib.request import urlopen

sys.path.insert(0, str(Path(__file__).resolve().parent))
import devcap
import uikit_perf as perf
import uikit_perf_report as report

IDENTITIES = {
    "swiftui": "com.sfenton.festivalscoretracker.perf.swiftui",
    "uikit": "com.sfenton.festivalscoretracker.perf.uikit",
}
ARCHIVE_NAME = "fst-physical-fixture.json"
ORIGIN = "http://127.0.0.1:18765"


def request_key(target: str) -> str:
    """Canonicalize relative fixture targets without losing duplicate/blank query items."""
    parts = urlsplit(target)
    if not target.startswith("/") or target.startswith("//") or parts.scheme or parts.netloc or parts.fragment:
        raise ValueError("fixture requests must be relative paths, never external origins")
    path = unquote(parts.path)
    pairs = sorted(f"{key}={value}" for key, value in parse_qsl(parts.query, keep_blank_values=True))
    if "\n" in path or any("\n" in pair for pair in pairs):
        raise ValueError("fixture request components cannot contain newlines")
    if path.startswith("/__fixture__/") and path != "/__fixture__/health" and not path.startswith("/__fixture__/art/"):
        raise ValueError("state-changing fixture controls cannot be archived")
    return "\n".join([path, *pairs])


def default_requests() -> list[str]:
    """Finite synthetic reads for landing pages; unrecorded variants remain explicit gaps."""
    paths = [
        "/__fixture__/health", "/api/publication", "/api/features", "/api/version", "/api/service-info",
        "/api/songs", "/api/songs?scenario=demo", "/api/shop",
        *[f"/__fixture__/art/{name}.png" for name in ("pulse", "orbit", "white")],
        "/api/player/fixture-player-1", "/api/player/fixture-player-1/notifications?limit=50",
        "/api/player/fixture-player-1/bands?group=all&page=1&pageSize=25",
        "/api/player/fixture-player-1/history?songId=fixture-pulse&instrument=Solo_Guitar",
        "/api/player/fixture-player-1/rivals/all",
        "/api/player/fixture-player-1/rivals/Solo_Guitar/f1c749eb07c32578cfa3e59ec38c03a8?limit=0&sort=closest",
        "/api/paths/fixture-pulse/Solo_Guitar/expert?generationId=fixture-path-generation",
    ]
    paths += [f"/api/player/fixture-player-1/bands?group={group}&page=1&pageSize=6"
              for group in ("duos", "trios", "quads")]
    for instrument in ("Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals", "Solo_Karaoke",
                       "Solo_PeripheralGuitar", "Solo_PeripheralBass", "Solo_PeripheralVocals",
                       "Solo_PeripheralDrums", "Solo_PeripheralCymbals"):
        for top in (10, 25):
            paths += [
                f"/api/leaderboard/fixture-pulse/{instrument}?top={top}&offset=0",
                f"/api/leaderboard/fixture-pulse/{instrument}?top={top}&offset=0&leeway=1",
            ]
        paths += [
            f"/api/rankings/{instrument}/fixture-player-1",
            f"/api/rankings/{instrument}/fixture-player-1/history?days=30",
            f"/api/player/fixture-player-1/rivals/{instrument}",
            f"/api/player/fixture-player-1/leaderboard-rivals/{instrument}?rankBy=totalscore",
        ]
        paths += [f"/api/rankings/{instrument}?rankBy=totalscore&page=1&pageSize={size}"
                  for size in (5, 10, 25)]
    for combo, size in (("03", 25), ("0f", 5), ("30", 5)):
        paths += [f"/api/rankings/combo?combo={combo}&rankBy=totalscore&page=1&pageSize={size}",
                  f"/api/player/fixture-player-1/rivals/{combo}"]
    paths += ["/api/leaderboard/fixture-pulse/all?top=10",
              "/api/leaderboard/fixture-pulse/bands/all?top=10",
              "/api/leaderboard/fixture-pulse/bands/all?top=10&accountId=fixture-player-1"]
    for band in ("Band_Duets", "Band_Trios", "Band_Quad"):
        paths += [
            f"/api/leaderboard/fixture-pulse/bands/{band}?top=25&offset=0&accountId=fixture-player-1",
        ]
        paths += [f"/api/rankings/bands/{band}?rankBy=totalscore&page=1&pageSize={size}" for size in (10, 25)]
    return paths


def export_archive(destination: Path, extra_requests: list[str]) -> dict:
    """Freeze actual responses from an owned, large, publication-7 loopback mock."""
    sys.path.insert(0, str(perf.REPO_ROOT))
    from tools.mock_service import FixtureHandler, FixtureServer
    targets = sorted(set(default_requests() + extra_requests))
    for target in targets:
        request_key(target)
    server = FixtureServer(("127.0.0.1", 0), FixtureHandler, large_catalogue=True, large_rankings=True, long_titles=True)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    origin = f"http://127.0.0.1:{server.server_port}"
    try:
        identity = perf.fixture_health(origin)
        responses = {}
        for target in targets:
            try:
                response = urlopen(origin + target, timeout=10)
            except HTTPError as error:
                response = error
            with response:
                responses[request_key(target)] = {
                    "status": response.status, "headers": dict(response.headers),
                    "body": base64.b64encode(response.read()).decode("ascii"),
                }
        archive = {"schema": 1, "origin": ORIGIN, "fixture": identity, "requests": targets, "responses": responses}
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(archive, sort_keys=True, separators=(",", ":")) + "\n")
        return archive
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def validate_archive(path: Path) -> dict:
    """Reject wrong fixture generations/options before device mutation."""
    archive = json.loads(path.read_text())
    options = archive.get("fixture", {}).get("health", {}).get("options", {})
    if (archive.get("schema") != 1 or archive.get("origin") != ORIGIN
            or archive.get("fixture", {}).get("publication", {}).get("publicationId") != 7
            or not options.get("largeCatalogue") or not options.get("largeRankings")
            or options.get("unpinned") or options.get("rolloverOnCommand")):
        raise ValueError("a pinned large publication-7 loopback archive is required")
    for target in archive.get("requests", []):
        if request_key(target) not in archive.get("responses", {}):
            raise ValueError(f"archive is missing {target}")
    return archive


def validate_app(spec: str) -> perf.AppUnderTest:
    """Restrict all install/uninstall/reset operations to the two dedicated probe identities."""
    app = perf.parse_app_bundle_spec(spec)
    if IDENTITIES.get(app.key) != app.bundle_id:
        raise ValueError("only dedicated swiftui/uikit benchmark identities may be mutated")
    with (perf.app_bundle(app) / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("CFBundleIdentifier") != app.bundle_id or info.get("CFBundleExecutable") != app.executable:
        raise ValueError("bundle identity/executable does not match the requested arm")
    if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("physical trials require iPhoneOS bundles, not simulator builds")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(perf.app_bundle(app))], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    return app


def device_command(device: str, *args: str, output: Path | None = None, check: bool = True) -> dict:
    """Execute a bounded devicectl operation and retain its raw JSON."""
    command = ["xcrun", "devicectl", "device", *args[:2], "--device", device, "--timeout", "30"]
    if output is not None:
        command += ["--json-output", str(output)]
    command += args[2:]
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=40)
    if check and result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    if result.returncode or output is None:
        return {}
    return json.loads(output.read_text()).get("result", {})


def physical_env(surface: perf.Surface, container: str, result: Path, settle: float, seconds: float) -> dict[str, str]:
    """Reuse canonical launch knobs with a writable on-device Documents result path."""
    if not container.startswith("/private/var/mobile/Containers/Data/Application/"):
        raise ValueError("devicectl did not provide an app data-container path")
    env = {key.removeprefix("SIMCTL_CHILD_"): value
           for key, value in perf.launch_env(surface, result, settle, ORIGIN, seconds).items()}
    env["FST_PERF_FILE"] = f"{container}/Documents/{result.name}"
    env["FST_PERF_FIXTURE_ARCHIVE"] = ARCHIVE_NAME
    env["FST_LIVE_PUBLICATION_UPDATES"] = "0"
    return env


def context_failures(text: str) -> list[str]:
    """Fail closed on missing thermal, power or replay evidence."""
    return report.physical_context_failures(text)


def run_trial(args, app: perf.AppUnderTest, surface: perf.Surface, round_number: int) -> list[str]:
    """Fresh-install one isolated arm, collect its sandbox output, then stop its exact PID."""
    result, _ = perf.run_paths(args.output, round_number, app.key, surface.name)
    stem = result.stem
    pid = None
    if perf.sha256_file(args.archive) != args.archive_digest:
        raise RuntimeError("fixture archive changed during the matched series")
    if perf.sha256_tree(perf.app_bundle(app)) != args.bundle_digests[app.key]:
        raise RuntimeError("signed probe bundle changed during the matched series")
    with devcap.hold(devices=[args.device], purpose=f"FST physical perf {stem}", hold_seconds=300):
        try:
            device_command(args.device, "uninstall", "app", app.bundle_id, check=False)
            device_command(args.device, "install", "app", str(perf.app_bundle(app)),
                           output=args.output / f"{stem}-install.json")
            listing = device_command(args.device, "info", "apps", "--bundle-id", app.bundle_id, "--include-container-paths",
                                     output=args.output / f"{stem}-container.json")
            apps = listing.get("apps", [])
            if len(apps) != 1 or not apps[0].get("containerAccessible"):
                raise RuntimeError("installed benchmark data container is inaccessible")
            env = physical_env(surface, apps[0]["dataContainerPath"], result, args.settle, args.seconds)
            device_command(args.device, "copy", "to", "--source", str(args.archive),
                           "--destination", f"Documents/{ARCHIVE_NAME}", "--domain-type", "appDataContainer",
                           "--domain-identifier", app.bundle_id, output=args.output / f"{stem}-fixture-copy.json")
            launched = device_command(args.device, "process", "launch", "--terminate-existing",
                                      "--environment-variables", json.dumps(env), app.bundle_id,
                                      output=args.output / f"{stem}-launch.json")
            pid = launched.get("process", {}).get("processIdentifier")
            if not isinstance(pid, int):
                raise RuntimeError("launch did not return the owned app PID")
            deadline = time.monotonic() + perf.run_budget(surface, args.settle, args.seconds)
            while time.monotonic() < deadline:
                device_command(args.device, "copy", "from", "--source", f"Documents/{result.name}",
                               "--destination", str(result), "--domain-type", "appDataContainer",
                               "--domain-identifier", app.bundle_id, check=False)
                if result.exists() and perf.finished(result.read_text()):
                    device_command(args.device, "copy", "from", "--source", "Documents/fst-physical-missing-requests.txt",
                                   "--destination", str(args.output / f"{stem}-missing-requests.txt"),
                                   "--domain-type", "appDataContainer", "--domain-identifier", app.bundle_id, check=False)
                    return context_failures(result.read_text())
                time.sleep(3)
            return ["timed out waiting for physical FSTPERF_DONE"]
        finally:
            if pid is not None:
                device_command(args.device, "process", "terminate", "--pid", str(pid),
                               output=args.output / f"{stem}-terminate.json")


def run(args) -> int:
    """Run source-bound alternating trials; no host GPU sampler or production option exists."""
    archive = validate_archive(args.archive)
    if not re.fullmatch(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}", args.device):
        raise ValueError("an exact physical device UDID is required")
    if args.rounds < 1 or args.cooldown < 0 or args.settle <= 0 or args.seconds <= 0:
        raise ValueError("invalid trial count/timing")
    apps = [validate_app(spec) for spec in args.app]
    if sorted(app.key for app in apps) != ["swiftui", "uikit"]:
        raise ValueError("exactly one SwiftUI and one UIKit probe arm are required")
    receipt = json.loads(args.build_receipt.read_text())
    if receipt.get("build_exit") != 0 or receipt.get("configuration") != "Release" or receipt.get("probe") is not True:
        raise ValueError("successful matching Release-probe build receipt is required")
    if (not receipt.get("source_before", {}).get("app_source_digest")
            or receipt["source_before"]["app_source_digest"] != receipt.get("source_after", {}).get("app_source_digest")):
        raise ValueError("build source changed between the two signed arms")
    args.bundle_digests = receipt["bundle_digests"]
    args.archive_digest = perf.sha256_file(args.archive)
    for app in apps:
        if receipt.get("bundle_digests", {}).get(app.key) != perf.sha256_tree(perf.app_bundle(app)):
            raise ValueError(f"{app.key} does not match the signed build receipt")
    only = [name.strip() for name in args.only.split(",")] if args.only else None
    surfaces = perf.parse_surfaces(args.surfaces.read_text(), only)
    if not surfaces or (only and set(only) != {surface.name for surface in surfaces}):
        raise ValueError("unknown/empty surface selection")
    if args.output.exists() and any(args.output.iterdir()):
        raise ValueError("output directory must be new; retained evidence is never overwritten")
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = {
        "platform": "physical-ios", "device_udid": args.device, "rounds": args.rounds,
        "apps": [app.key for app in apps], "build": receipt, "cooldown_seconds": args.cooldown,
        "fixture": archive["fixture"], "archive_digest": args.archive_digest,
        "source": perf.source_identity(args.surfaces),
        "metrics_unavailable": ["device GPU counters", "device render-server CPU"],
        "fixture_cost": "App CPU and footprint include the same process-local synthetic replay server.",
        "surfaces": [vars(surface) for surface in surfaces], "physical_failures": [],
    }
    manifest_path = args.output / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    try:
        for round_number in range(1, args.rounds + 1):
            for surface in surfaces:
                if surface.status != "measure":
                    continue
                for key in perf.app_order(round_number, [app.key for app in apps]):
                    app = next(app for app in apps if app.key == key)
                    print(f"round {round_number} {key}: {surface.name}", flush=True)
                    failures = run_trial(args, app, surface, round_number)
                    manifest["physical_failures"] += [
                        f"round {round_number} {key} {surface.name}: {failure}" for failure in failures]
                    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
                    time.sleep(args.cooldown)
    except KeyboardInterrupt:
        manifest["physical_failures"].append("measurement interrupted; series incomplete")
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        manifest["physical_failures"].append(str(error))
    finally:
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
        collected = report.collect(args.output)
        text, rows = report.render(collected, physical=True)
        text = ("Physical iOS; no Mac GPU/render-server samples. CPU and footprint include the shared local fixture replay.\n\n"
                + text + "\n" + report.qualification_markdown(collected, manifest))
        (args.output / "report.md").write_text(text + "\n")
        with (args.output / "report.csv").open("w") as handle:
            fields = sorted({key for row in rows for key in row})
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
        print(f"results: {args.output}", flush=True)
    return 2 if report.qualify(collected, manifest) else 0


def main(argv: list[str] | None = None) -> int:
    """Export a synthetic archive or execute physical trials."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    export = commands.add_parser("export")
    export.add_argument("--output", type=Path, required=True)
    export.add_argument("--request", action="append", default=[])
    export.add_argument("--requests-file", type=Path)
    trial = commands.add_parser("run")
    trial.add_argument("--device", required=True)
    trial.add_argument("--app", action="append", required=True, metavar="LABEL|APP|BUNDLE_ID|EXECUTABLE")
    trial.add_argument("--archive", type=Path, required=True)
    trial.add_argument("--build-receipt", type=Path, required=True)
    trial.add_argument("--output", type=Path, required=True)
    trial.add_argument("--surfaces", type=Path, default=perf.DEFAULT_SURFACES)
    trial.add_argument("--only")
    trial.add_argument("--rounds", type=int, default=3)
    trial.add_argument("--settle", type=float, default=12)
    trial.add_argument("--seconds", type=float, default=8)
    trial.add_argument("--cooldown", type=float, default=30)
    args = parser.parse_args(argv)
    try:
        if args.command == "export":
            requests = args.request
            if args.requests_file:
                requests += [line.strip() for line in args.requests_file.read_text().splitlines()
                             if line.strip() and not line.startswith("#")]
            archive = export_archive(args.output, requests)
            print(f"archived {len(archive['responses'])} synthetic responses: {args.output}")
            return 0
        return run(args)
    except (ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(2, f"{error}\n")


if __name__ == "__main__":
    sys.exit(main())
