#!/usr/bin/env python3
"""Gate measured iPhone/iPad shared-UI and app lines; Core/Design remain separate."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
TARGET_SOURCES_BY_FAMILY = {
    "swiftui": {
        "FestivalUI": "apple/Sources/FestivalUI/**/*.swift",
        "FestivalMobile.app": "apple/Apps/iOS/**/*.swift",
    },
    "uikit": {
        "FestivalUI": "apple/Sources/FestivalUI/**/*.swift",
        "FestivalMobileUIKit.app": "apple/Apps/iOSUIKit/**/*.swift",
    },
}
# Backwards-compatible alias for callers that gate the established SwiftUI app.
TARGET_SOURCES = TARGET_SOURCES_BY_FAMILY["swiftui"]
LLVM_UI_SCHEMA = 2


def file_sha256(path: Path) -> str:
    """Return the SHA-256 digest of one retained coverage artifact."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def llvm_identity(binary: Path, profile: Path) -> dict[str, str]:
    """Read architecture/UUID identity from the frozen binary and profile."""
    commands = {
        "architectures": ["xcrun", "lipo", "-archs", str(binary)],
        "uuids": ["xcrun", "dwarfdump", "--uuid", str(binary)],
        "profileBinaryIds": ["xcrun", "llvm-profdata", "show", "--binary-ids", str(profile)],
    }
    identity: dict[str, str] = {}
    for key, command in commands.items():
        process = subprocess.run(command, text=True, capture_output=True, check=False)
        if process.returncode or process.stderr.strip() or not process.stdout.strip():
            raise ValueError(f"LLVM identity query failed: {key}")
        identity[key] = process.stdout.strip()
    if "arm64" not in identity["architectures"].split():
        raise ValueError("LLVM binary does not contain arm64")
    uuids = {
        token.replace("-", "").lower()
        for token in re.findall(
            r"\b[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\b",
            identity["uuids"],
        )
    }
    profile_ids = {
        token.lower()
        for token in re.findall(r"\b[0-9A-Fa-f]{16,}\b", identity["profileBinaryIds"])
    }
    if uuids and profile_ids and not any(
        uuid in profile_id or profile_id in uuid
        for uuid in uuids for profile_id in profile_ids
    ):
        raise ValueError("LLVM profile binary IDs do not match the dylib UUID")
    return identity


def source_manifest(root: Path) -> dict[str, str]:
    """Return content digests for every source/configuration file in scope."""
    roots = (
        root / "apple/Sources",
        root / "apple/Apps/iOS",
        root / "apple/Apps/iOSUIKit",
        root / "apple/Apps/iOSUITests",
        root / "apple/Apps/iPadOSUITests",
        root / "apple/project.yml",
    )
    manifest: dict[str, str] = {}
    for base in roots:
        files = [base] if base.is_file() else sorted(base.rglob("*"))
        for path in files:
            if not path.is_file():
                continue
            manifest[path.relative_to(root.resolve()).as_posix()] = file_sha256(path)
    return manifest


def source_digest(root: Path) -> str:
    """Hash the content-bound source manifest used by coverage provenance."""
    digest = hashlib.sha256()
    for path, content in sorted(source_manifest(root).items()):
        digest.update(path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(content.encode("ascii"))
        digest.update(b"\n")
    return digest.hexdigest()


def source_omission_reason(path: Path, root: Path) -> str | None:
    """Prove an LLVM-omitted source is macOS-only or declaration-only."""
    relative = path.relative_to(root.resolve()).as_posix()
    text = path.read_text(encoding="utf-8")
    code = strip_swift_comments(text)
    first = next((line.strip() for line in code.splitlines() if line.strip()), "")
    if "/Mac/" in f"/{relative}" and is_macos_only(code, first):
        return "macOS-only compilation guard"
    if (
        re.search(r"\b(func|init|subscript|get|set|if|for|switch|guard|while|repeat|defer|catch)\b", code)
        or re.search(r"\b(var|let)\b[^{=\n]*\{", code)
        or re.search(r"=\s*[^;\n]*[\({]", code)
    ):
        return None
    return "declaration-only source"


def strip_swift_comments(text: str) -> str:
    """Remove Swift comments without treating URL markers inside strings as comments."""
    out: list[str] = []
    index = 0
    block = 0
    quoted = False
    escaped = False
    while index < len(text):
        pair = text[index:index + 2]
        char = text[index]
        if quoted:
            out.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
            index += 1
        elif block:
            if pair == "/*":
                block += 1
                index += 2
            elif pair == "*/":
                block -= 1
                index += 2
            else:
                out.append("\n" if char == "\n" else " ")
                index += 1
        elif pair == "//":
            while index < len(text) and text[index] != "\n":
                index += 1
        elif pair == "/*":
            block = 1
            index += 2
        else:
            out.append(char)
            quoted = char == '"'
            index += 1
    return "".join(out)


def is_macos_only(code: str, first: str) -> bool:
    """Require the whole file to be enclosed by one macOS-only conditional."""
    if first != "#if os(macOS)":
        return False
    depth = 0
    closed = False
    for line in code.splitlines():
        directive = line.strip()
        if directive.startswith("#if "):
            depth += 1
        elif directive == "#endif":
            depth -= 1
            if depth == 0:
                closed = True
        elif depth == 1 and (directive == "#else" or directive.startswith("#elseif")):
            return False
        elif closed and directive:
            return False
    return closed and depth == 0


def llvm_line_map(
    export: dict[str, Any], line_map: str, root: Path,
    provenance: dict[str, Any],
) -> dict[str, dict[int, bool]]:
    """Validate the runner-generated LCOV line map against LLVM's raw export.

    The runner derives this map from ``llvm-cov export --format=lcov`` using the
    same frozen binary/profile as the retained JSON export.  No caller-supplied
    line numbers or zero-executable exclusions are accepted.
    """
    data = export.get("data")
    if not isinstance(data, list):
        raise ValueError("LLVM export must contain a data array")
    raw: dict[str, dict[str, Any]] = {}
    for group in data:
        if not isinstance(group, dict) or not isinstance(group.get("files"), list):
            raise ValueError("LLVM export has an invalid files array")
        for item in group["files"]:
            name = item.get("filename") if isinstance(item, dict) else None
            if not isinstance(name, str):
                raise ValueError("LLVM export has an invalid filename")
            path = Path(name).resolve()
            try:
                relative = path.relative_to(root.resolve()).as_posix()
            except ValueError:
                continue
            if relative.startswith("apple/Sources/FestivalUI/"):
                if relative in raw:
                    raise ValueError(f"{relative}: duplicated in LLVM export")
                raw[relative] = item
    expected = {
        path.relative_to(root.resolve()).as_posix()
        for path in root.glob(TARGET_SOURCES_BY_FAMILY["uikit"]["FestivalUI"])
    }
    files: dict[str, dict[str, list[int]]] = {}
    current: dict[str, list[int]] | None = None
    for raw_line in line_map.splitlines():
        if raw_line.startswith("SF:"):
            path = Path(raw_line[3:]).resolve()
            try:
                relative = path.relative_to(root.resolve()).as_posix()
            except ValueError:
                current = None
                continue
            current = None
            if relative.startswith("apple/Sources/FestivalUI/"):
                if relative in files:
                    raise ValueError(f"{relative}: duplicated in LLVM LCOV")
                current = {"executable": [], "covered": []}
                files[relative] = current
        elif raw_line.startswith("DA:") and current is not None:
            fields = raw_line[3:].split(",")
            if len(fields) < 2:
                raise ValueError(f"invalid LLVM LCOV line record: {raw_line}")
            try:
                line, count = int(fields[0]), int(fields[1])
            except ValueError as error:
                raise ValueError(f"invalid LLVM LCOV line record: {raw_line}") from error
            if line <= 0 or count < 0 or line in current["executable"]:
                raise ValueError(f"invalid LLVM LCOV line record: {raw_line}")
            current["executable"].append(line)
            if count > 0:
                current["covered"].append(line)
        elif raw_line == "end_of_record":
            current = None
    compiled = set(files)
    if not compiled:
        raise ValueError("LLVM LCOV export contains no FestivalUI sources")
    if not compiled <= expected or set(raw) != compiled:
        raise ValueError("LLVM export contains an unexpected FestivalUI source")
    omissions = {}
    for name in sorted(expected - compiled):
        reason = source_omission_reason(root / name, root)
        if reason is None:
            raise ValueError(f"{name}: LLVM omitted an executable owned source")
        omissions[name] = reason
    if provenance.get("omittedSources") != omissions:
        raise ValueError("LLVM omitted-source proof does not match the frozen source tree")
    measured: dict[str, dict[int, bool]] = {}
    for name in sorted(compiled):
        item = raw.get(name)
        entry = files.get(name)
        if not isinstance(item, dict) or not isinstance(entry, dict):
            raise ValueError(f"{name}: missing raw LLVM export or line-map entry")
        executable = entry.get("executable")
        covered = entry.get("covered")
        if (
            not isinstance(executable, list)
            or not isinstance(covered, list)
            or any(type(line) is not int or line <= 0 for line in executable + covered)
            or len(set(executable)) != len(executable)
            or len(set(covered)) != len(covered)
            or not set(covered) <= set(executable)
        ):
            raise ValueError(f"{name}: invalid LLVM executable-line map")
        source = root / name
        line_count = len(source.read_text(encoding="utf-8").splitlines())
        if any(line > line_count for line in executable):
            raise ValueError(f"{name}: executable line is outside the source")
        # This compiler's JSON ``summary.lines`` aggregate differs from its
        # emitted LCOV DA map. Use the exact regenerated LCOV executable-line
        # records; validate_llvm_provenance still rejects any artifact mismatch.
        measured[name] = {line: line in set(covered) for line in executable}
    return measured


def validate_llvm_provenance(
    provenance_path: Path, provenance: dict[str, Any], result: Path,
    export_path: Path, line_map_path: Path,         root: Path, start: float, finish: float, device: tuple[str, str],
) -> None:
    """Require binary/profile/export/source identity for LLVM fallback evidence."""
    if provenance.get("schemaVersion") != LLVM_UI_SCHEMA:
        raise ValueError("unsupported LLVM provenance schema")
    if provenance.get("appFamily") != "uikit" or provenance.get("architecture") != "arm64":
        raise ValueError("LLVM provenance is not for the UIKit arm64 collector")
    manifest = provenance.get("sourceManifest")
    if manifest != source_manifest(root) or provenance.get("sourceDigest") != source_digest(root):
        raise ValueError("LLVM source digest does not match the frozen source/configuration")
    result_info = provenance.get("result")
    if not isinstance(result_info, dict) or Path(result_info.get("path", "")).resolve() != result.resolve():
        raise ValueError("LLVM provenance result path mismatch")
    if abs(float(result_info.get("startTime", -1)) - start) > 0.01:
        raise ValueError("LLVM provenance result start mismatch")
    provenance_finish = float(result_info.get("finishTime", -1))
    if finish < start or provenance_finish != finish:
        raise ValueError("LLVM provenance result finish mismatch")
    if tuple(provenance.get("device", ())) != device:
        raise ValueError("LLVM provenance device mismatch")
    for key, path in (("binary", provenance.get("binary")), ("profile", provenance.get("profile")),
                      ("export", provenance.get("export")), ("lineMap", provenance.get("lineMap"))):
        if not isinstance(path, dict) or not isinstance(path.get("path"), str):
            raise ValueError(f"LLVM provenance missing {key} artifact")
        artifact = Path(path["path"]).resolve()
        expected = {
            "export": export_path,
            "lineMap": line_map_path,
        }.get(key)
        if expected is not None and artifact != expected.resolve():
            raise ValueError(f"LLVM provenance {key} path mismatch")
        if not artifact.is_file() or path.get("sha256") != file_sha256(artifact):
            raise ValueError(f"LLVM provenance {key} digest mismatch")
    if provenance["binary"].get("architecture") != "arm64":
        raise ValueError("LLVM binary architecture does not match the collector")
    identity = llvm_identity(
        Path(provenance["binary"]["path"]), Path(provenance["profile"]["path"])
    )
    if provenance.get("llvmIdentity") != identity:
        raise ValueError("LLVM binary/profile identity mismatch")
    lcov = line_map_path.read_text(encoding="utf-8")
    process = subprocess.run(
        [
            "xcrun", "llvm-cov", "export", str(provenance["binary"]["path"]),
            "--instr-profile", str(provenance["profile"]["path"]),
            "--format=lcov", "--arch=arm64",
        ],
        text=True, capture_output=True, check=False,
    )
    if process.returncode or process.stderr.strip() or process.stdout != lcov:
        raise ValueError("LLVM LCOV does not match the frozen binary/profile")
    profile_mtime = float(provenance["profile"].get("mtime", -1))
    export_mtime = float(provenance["export"].get("mtime", -1))
    grace = float(provenance.get("profileFlushGraceSeconds", 0))
    if grace < 0 or grace > 10:
        raise ValueError("LLVM profile flush grace is invalid")
    if (
        abs(Path(provenance["profile"]["path"]).stat().st_mtime - profile_mtime) > 1
        or abs(Path(provenance["export"]["path"]).stat().st_mtime - export_mtime) > 1
        or not start <= profile_mtime <= finish + grace
        or export_mtime < profile_mtime
    ):
        raise ValueError("LLVM artifacts do not belong to the result collection interval")


def target_sources(app_family: str) -> dict[str, str]:
    """Return the exact executable-source mapping for one iOS app family."""
    try:
        return TARGET_SOURCES_BY_FAMILY[app_family]
    except KeyError as error:
        raise ValueError(f"Unsupported iOS app family: {app_family}") from error


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
    result: Path, root: Path, app_family: str = "swiftui",
    llvm_export: Path | None = None, llvm_line_map_path: Path | None = None,
    llvm_provenance_path: Path | None = None,
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
    finish = summary.get("finishTime")
    if not isinstance(start, (int, float)):
        raise ValueError(f"{result}: missing test start time")
    if not isinstance(finish, (int, float)):
        finish = start
    report = xcode_json("xccov", ["view", "--report", "--json", str(result)])
    targets = {target.get("name"): target for target in report.get("targets", [])}
    measured: dict[str, dict[int, bool]] = {}
    expected_targets = target_sources(app_family)
    foreign_apps = (
        {"FestivalMobile.app", "FestivalMobileUIKit.app"} - set(expected_targets)
    ) & set(targets)
    if foreign_apps:
        raise ValueError(
            f"{result}: foreign app coverage target(s): {sorted(foreign_apps)}"
        )
    if llvm_export or llvm_line_map_path or llvm_provenance_path:
        if app_family != "uikit" or not all((llvm_export, llvm_line_map_path, llvm_provenance_path)):
            raise ValueError("LLVM fallback requires all three UIKit artifacts")
        if not isinstance(summary.get("finishTime"), (int, float)):
            raise ValueError(f"{result}: LLVM evidence requires the actual result finish time")
        export = json.loads(llvm_export.read_text(encoding="utf-8"))
        line_map_payload = llvm_line_map_path.read_text(encoding="utf-8")
        provenance = json.loads(llvm_provenance_path.read_text(encoding="utf-8"))
        validate_llvm_provenance(
            llvm_provenance_path, provenance, result, llvm_export,
            llvm_line_map_path, root, start, finish, device,
        )
        measured.update(llvm_line_map(export, line_map_payload, root, provenance))
    for name, pattern in expected_targets.items():
        if name == "FestivalUI" and llvm_export:
            continue
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
    parser.add_argument("--app-family", choices=tuple(TARGET_SOURCES_BY_FAMILY), default="swiftui")
    parser.add_argument("--llvm-export", type=Path, action="append")
    parser.add_argument("--llvm-line-map", type=Path, action="append")
    parser.add_argument("--llvm-provenance", type=Path, action="append")
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
        llvm_args = (args.llvm_export, args.llvm_line_map, args.llvm_provenance)
        if any(llvm_args) and any(len(values or []) != len(args.result) for values in llvm_args):
            raise ValueError("Provide one LLVM export, line map and provenance artifact per result")
        reports, starts, devices = zip(*(
            collect_result(
                result, root, args.app_family,
                *(values[index] if values else None for values in llvm_args),
            )
            for index, result in enumerate(args.result)
        ))
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
