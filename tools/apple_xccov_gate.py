#!/usr/bin/env python3
"""Gate measured iPhone/iPad shared-UI and app lines; Core/Design remain separate."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
TARGET_SOURCES = {
    "FestivalUI": "apple/Sources/FestivalUI/*.swift",
    "FestivalMobile.app": "apple/Apps/iOS/*.swift",
}


def xcode_json(tool: str, arguments: list[str]) -> dict[str, Any]:
    """Run a read-only Xcode report query and reject invalid JSON or failures.

    Args:
        tool: xcrun subcommand, either xcresulttool or xccov.
        arguments: Read-only report/view flags and a result-bundle path.

    Returns:
        Parsed report object.

    Raises:
        ValueError: If Xcode cannot read the result or returns malformed data.
    """
    process = subprocess.run(
        ["xcrun", tool, *arguments], text=True, capture_output=True, check=False
    )
    if process.returncode:
        raise ValueError(f"{tool}: {process.stderr.strip() or process.stdout.strip()}")
    try:
        report = json.loads(process.stdout)
    except json.JSONDecodeError as error:
        raise ValueError(f"{tool}: invalid JSON result: {error}") from error
    if not isinstance(report, dict):
        raise ValueError(f"{tool}: expected a report object")
    return report


def line_hits(
    archive: dict[str, Any], source: Path, covered: int, executable: int
) -> dict[int, bool]:
    """Reject impossible counters while retaining unique archived source lines.

    Args:
        archive: xccov's JSON archive output for one source file.
        source: Absolute source path listed in the coverage report.
        covered: Xcode's covered-line count, including SwiftUI specializations.
        executable: Xcode's executable count, including specialized functions.

    Returns:
        Executable line numbers and whether each ran at least once.

    Raises:
        ValueError: On missing lines or a report smaller than its unique archive.
    """
    lines = archive.get(str(source))
    if not isinstance(lines, list):
        raise ValueError(f"{source}: missing per-line archive")
    hits: dict[int, bool] = {}
    for item in lines:
        if not isinstance(item, dict) or item.get("isExecutable") is not True:
            continue
        number, count = item.get("line"), item.get("executionCount", 0)
        if (
            type(number) is not int or number <= 0
            or type(count) is not int or count < 0
            or number in hits
        ):
            raise ValueError(f"{source}: invalid executable-line counter")
        hits[number] = count > 0
    if len(hits) > executable or sum(hits.values()) > covered:
        raise ValueError(f"{source}: archive counters exceed the Xcode report")
    return hits


def merged_hits(
    reports: list[dict[str, dict[int, bool]]]
) -> dict[str, dict[int, bool]]:
    """Join each source line across devices without losing location context.

    Args:
        reports: A passing device's complete source-to-line map per result.

    Returns:
        Source paths with the union of their measured line counters.

    Raises:
        ValueError: If source or executable-line sets differ across builds.
    """
    if not reports:
        raise ValueError("No device reports to merge")
    expected = reports[0]
    if not expected:
        raise ValueError("No measured production source")
    combined = {name: hits.copy() for name, hits in expected.items()}
    for report in reports[1:]:
        if report.keys() != expected.keys():
            raise ValueError("Xcode results cover different production source files")
        for name, hits in report.items():
            if hits.keys() != expected[name].keys():
                raise ValueError(f"{name}: executable lines differ between Xcode results")
            for line, executed in hits.items():
                combined[name][line] |= executed
    return combined


def union_lines(
    reports: list[dict[str, dict[int, bool]]]
) -> tuple[int, int]:
    """Count combined lines, not a sum or average of device percentages.

    Args:
        reports: One complete, passing device result per entry.

    Returns:
        Combined covered and executable source lines.
    """
    combined = merged_hits(reports)
    return sum(sum(lines.values()) for lines in combined.values()), sum(
        len(lines) for lines in combined.values()
    )


def device_identity(summary: dict[str, Any]) -> tuple[str, str]:
    """Require one real iOS Simulator destination with a known device family.

    Args:
        summary: Completed xcresulttool test-results summary.

    Returns:
        Device family (`iPhone` or `iPad`) and simulator identifier.

    Raises:
        ValueError: If the result lacks an unambiguous supported destination.
    """
    entries = summary.get("devicesAndConfigurations")
    if not isinstance(entries, list) or len(entries) != 1:
        raise ValueError("Expected exactly one device in each Xcode result")
    device = entries[0].get("device", {})
    model, identifier = device.get("modelName"), device.get("deviceId")
    if (
        device.get("platform") != "iOS Simulator"
        or not isinstance(model, str)
        or not isinstance(identifier, str)
        or not identifier
    ):
        raise ValueError("Xcode result is missing an iOS Simulator device identity")
    if model.startswith("iPhone"):
        return "iPhone", identifier
    if model.startswith("iPad"):
        return "iPad", identifier
    raise ValueError(f"Unsupported iOS simulator device family: {model}")


def validate_result_devices(
    results: list[Path], devices: list[tuple[str, str]], scope: str
) -> None:
    """Require distinct passing-result paths and consistent simulator identities.

    Args:
        results: Complete Xcode result-bundle paths submitted to the gate.
        devices: Family and device ID read from each result, in the same order.
        scope: `paired`, `iphone` or `ipad`; never infer a paired pass from one family.

    Raises:
        ValueError: On duplicates, mixed devices within a family or wrong scope.
    """
    if scope not in {"paired", "iphone", "ipad"}:
        raise ValueError(f"Unsupported iOS coverage scope: {scope}")
    minimum = 2 if scope == "paired" else 1
    if len(results) < minimum or len({result.resolve() for result in results}) != len(results):
        raise ValueError(f"Provide at least {minimum} distinct Xcode result bundles")
    if len(devices) != len(results):
        raise ValueError("Xcode result and simulator counts differ")
    by_family: dict[str, str] = {}
    for family, identifier in devices:
        if family not in {"iPhone", "iPad"} or not identifier:
            raise ValueError("Xcode result has an unsupported simulator identity")
        if family in by_family and by_family[family] != identifier:
            raise ValueError(f"{family} result shards must use the same simulator")
        by_family[family] = identifier
    if scope == "paired":
        if set(by_family) != {"iPhone", "iPad"}:
            raise ValueError("Results must include an iPhone and iPad simulator")
        if by_family["iPhone"] == by_family["iPad"]:
            raise ValueError("Results must use distinct iPhone and iPad simulators")
    else:
        expected = "iPhone" if scope == "iphone" else "iPad"
        if set(by_family) != {expected}:
            raise ValueError(f"{scope} coverage requires only {expected} simulator results")


def collect_result(
    result: Path, root: Path
) -> tuple[dict[str, dict[int, bool]], float, tuple[str, str]]:
    """Require one passing iOS result and read all app and shared-UI line hits.

    Args:
        result: Completed Xcode .xcresult with code coverage enabled.
        root: Repository root containing the expected production sources.

    Returns:
        Covered executable lines, the test start epoch and device identity.

    Raises:
        ValueError: On a failed test, omitted target, missing source or malformed archive.
    """
    if not result.is_dir():
        raise ValueError(f"{result}: Xcode result bundle does not exist")
    summary = xcode_json(
        "xcresulttool", ["get", "test-results", "summary", "--path", str(result)]
    )
    if summary.get("result") != "Passed" or summary.get("passedTests", 0) < 1:
        raise ValueError(f"{result}: tests did not pass")
    device = device_identity(summary)
    start = summary.get("startTime")
    if not isinstance(start, (int, float)):
        raise ValueError(f"{result}: missing test start time")
    report = xcode_json("xccov", ["view", "--report", "--json", str(result)])
    targets = {target.get("name"): target for target in report.get("targets", [])}
    measured: dict[str, dict[int, bool]] = {}
    for name, pattern in TARGET_SOURCES.items():
        target = targets.get(name)
        if not isinstance(target, dict) or not isinstance(target.get("files"), list):
            raise ValueError(f"{result}: missing {name} coverage target")
        expected = {source.resolve() for source in root.glob(pattern)}
        if not expected:
            raise ValueError(f"{root}: no production files match {pattern}")
        actual = {Path(item["path"]).resolve() for item in target["files"]}
        if actual != expected:
            raise ValueError(
                f"{result}: {name} source mismatch; missing {sorted(map(str, expected - actual))}, "
                f"unexpected {sorted(map(str, actual - expected))}"
            )
        for item in target["files"]:
            source = Path(item["path"]).resolve()
            archive = xcode_json(
                "xccov", ["view", "--archive", "--file", str(source), "--json", str(result)]
            )
            measured[source.relative_to(root.resolve()).as_posix()] = line_hits(
                archive, source, item["coveredLines"], item["executableLines"]
            )
    return measured, start, device


def main(argv: list[str] | None = None) -> int:
    """Check the iOS UX bar against complete, source-identical device results.

    Args:
        argv: Optional CLI arguments for tests.

    Returns:
        Exit status zero only when the exact combined line bar passes.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--result", type=Path, action="append", required=True)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--scope", choices=("paired", "iphone", "ipad"), default="paired")
    parser.add_argument("--details", action="store_true")
    args = parser.parse_args(argv)
    try:
        minimum = 2 if args.scope == "paired" else 1
        if (
            len(args.result) < minimum
            or len({result.resolve() for result in args.result}) != len(args.result)
        ):
            raise ValueError(f"Provide at least {minimum} distinct Xcode result bundles")
        root = args.root.resolve()
        rules = json.loads((root / "contracts/coverage-rules.json").read_text(encoding="utf-8"))
        threshold = rules["thresholds"]["ux"]
        if type(threshold) is not int or not 0 <= threshold <= 100:
            raise ValueError("Invalid iOS UX coverage threshold")
        reports, starts, devices = zip(
            *(collect_result(result, root) for result in args.result)
        )
        validate_result_devices(args.result, list(devices), args.scope)
        first_start = min(starts)
        for source in reports[0]:
            if (root / source).stat().st_mtime > first_start:
                raise ValueError(f"{source}: edited after the first test began; rerun both devices")
        combined = merged_hits(list(reports))
        if args.details:
            for source, hits in sorted(combined.items()):
                missing = [str(line) for line, ran in sorted(hits.items()) if not ran]
                print(
                    f"{source}: {sum(hits.values())}/{len(hits)} lines; "
                    f"uncovered: {', '.join(missing[:45])}"
                )
        covered, executable = union_lines(list(reports))
        label = (
            "ios.ui-and-app-ux" if args.scope == "paired"
            else f"ios.{args.scope}.ui-and-app-ux"
        )
        print(
            f"{label}: {covered}/{executable} lines "
            f"= {100 * covered / executable:.2f}% "
            f"(need {threshold}%)"
        )
        if covered * 100 < threshold * executable:
            raise ValueError(f"{args.scope} UX coverage is below {threshold}%")
    except (OSError, KeyError, TypeError, ValueError, ZeroDivisionError) as error:
        print(f"iOS Xcode coverage error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
