#!/usr/bin/env python3
"""Fail when actual per-language logic/UI line coverage misses its own threshold."""

from __future__ import annotations

import argparse
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
RULES = ROOT / "contracts" / "coverage-rules.json"


def source_files(root: Path, patterns: list[str]) -> set[str]:
    """Find source files subject to coverage, independently of report contents.

    Args:
        root: Repository root.
        patterns: Repository-relative glob patterns for one coverage category.

    Returns:
        All matched repository-relative POSIX file paths.
    """
    return {
        path.relative_to(root).as_posix()
        for pattern in patterns
        for path in root.glob(pattern)
        if path.is_file()
    }


def llvm_file_totals(reports: list[Path], root: Path) -> dict[str, tuple[int, int]]:
    """Extract exact executable and covered line totals from LLVM JSON exports.

    Args:
        reports: One `llvm-cov export --format=text` result per test binary.
        root: Root against which tracked source paths are resolved.

    Returns:
        Mapping from repository-relative path to (covered, executable) lines.

    Raises:
        ValueError: On malformed, missing or duplicated per-file coverage.
    """
    totals: dict[str, tuple[int, int]] = {}
    for report in reports:
        try:
            payload = json.loads(report.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise ValueError(f"{report}: cannot read LLVM coverage JSON: {error}") from error
        if not isinstance(payload, dict) or not isinstance(payload.get("data"), list):
            raise ValueError(f"{report}: missing LLVM data array")
        for group in payload["data"]:
            if not isinstance(group, dict) or not isinstance(group.get("files"), list):
                raise ValueError(f"{report}: missing LLVM files array")
            for item in group["files"]:
                if not isinstance(item, dict) or not isinstance(item.get("filename"), str):
                    raise ValueError(f"{report}: invalid file entry")
                try:
                    name = Path(item["filename"]).resolve().relative_to(root.resolve()).as_posix()
                except ValueError:
                    continue  # Generated compiler or SDK sources are not product code.
                lines: Any = item.get("summary", {}).get("lines")
                if (
                    not isinstance(lines, dict)
                    or type(lines.get("covered")) is not int
                    or type(lines.get("count")) is not int
                    or not 0 <= lines["covered"] <= lines["count"]
                ):
                    raise ValueError(f"{report}: invalid line totals for {name}")
                if name in totals:
                    raise ValueError(f"{name}: duplicated in coverage exports; merge profiles first")
                totals[name] = (lines["covered"], lines["count"])
    return totals


def _resolve_xml_source(name: str, candidates: set[str]) -> str:
    """Resolve report-local file names without silently choosing a duplicate.

    Args:
        name: XML filename, absolute path, or JaCoCo package-relative name.
        candidates: Repository files classified as logic or UX.

    Returns:
        The unique matching repository-relative source path.

    Raises:
        ValueError: If the name does not uniquely identify one source file.
    """
    normalized = name.replace("\\", "/").lstrip("/")
    matches = [
        path for path in candidates
        if path == normalized
        or path.endswith("/" + normalized)
        or normalized.endswith("/" + path)
    ]
    if len(matches) != 1:
        raise ValueError(f"{name}: expected one matching source file, found {matches}")
    return matches[0]


def xml_file_totals(
    reports: list[Path], candidates: set[str]
) -> dict[str, tuple[int, int]]:
    """Merge JaCoCo and Cobertura line hits across host and device test reports.

    Args:
        reports: XML files produced by the actual platform test runners.
        candidates: Files named by the configured logic/UI source patterns.

    Returns:
        Mapping of repository paths to (covered, executable) line counts.

    Raises:
        ValueError: For unsupported, ambiguous or invalid XML coverage.
    """
    lines: dict[str, dict[int, bool]] = {}
    for report in reports:
        try:
            document = ET.parse(report).getroot()
        except (OSError, ET.ParseError) as error:
            raise ValueError(f"{report}: cannot read coverage XML: {error}") from error
        entries: list[tuple[str, list[ET.Element]]] = []
        if document.tag == "report":
            for package in document.findall("package"):
                package_name = package.get("name", "")
                for source in package.findall("sourcefile"):
                    filename = source.get("name")
                    if not filename:
                        raise ValueError(f"{report}: JaCoCo source without a filename")
                    entries.append((f"{package_name}/{filename}", source.findall("line")))
        elif document.tag == "coverage":
            for source in document.findall(".//class"):
                filename = source.get("filename")
                if not filename:
                    raise ValueError(f"{report}: Cobertura class without a filename")
                entries.append((filename, source.findall("./lines/line")))
        else:
            raise ValueError(f"{report}: expected JaCoCo report or Cobertura coverage XML")
        if not entries:
            raise ValueError(f"{report}: no source-file coverage entries")
        for name, elements in entries:
            path = _resolve_xml_source(name, candidates)
            hits = lines.setdefault(path, {})
            for element in elements:
                try:
                    number = int(element.attrib["nr" if document.tag == "report" else "number"])
                    if document.tag == "report":
                        missed, covered = int(element.attrib["mi"]), int(element.attrib["ci"])
                        if missed < 0 or covered < 0:
                            raise ValueError("negative instruction count")
                        if missed + covered == 0:
                            continue
                        executed = covered > 0
                    else:
                        count = int(element.attrib["hits"])
                        if count < 0:
                            raise ValueError("negative hit count")
                        executed = count > 0
                except (KeyError, ValueError) as error:
                    raise ValueError(f"{report}: invalid line metrics for {path}") from error
                if number <= 0:
                    raise ValueError(f"{report}: invalid line number for {path}")
                hits[number] = hits.get(number, False) or executed
    return {
        path: (sum(covered for covered in hit_map.values()), len(hit_map))
        for path, hit_map in lines.items()
    }


def check_coverage(
    totals: dict[str, tuple[int, int]], root: Path, rules: dict[str, Any], language: str
) -> list[str]:
    """Check source-file completeness and separate threshold ratios.

    Args:
        totals: Actual per-file (covered, executable) line counts.
        root: Repository root.
        rules: Versioned coverage classification and numeric thresholds.
        language: Language section to validate.

    Returns:
        Errors for missing files, category overlap and low measured coverage.
    """
    if language not in rules or not isinstance(rules[language], dict):
        return [f"{language}: no configured coverage categories"]
    errors: list[str] = []
    exclude_patterns = rules[language].get("exclude", [])
    if not isinstance(exclude_patterns, list) or not all(
        isinstance(pattern, str) for pattern in exclude_patterns
    ):
        return [f"{language}: invalid coverage exclusion patterns"]
    excluded = source_files(root, exclude_patterns)
    for name in excluded:
        if name in totals and totals[name][1] > 0:
            errors.append(f"{language}: executable source cannot be excluded: {name}")
    classified: set[str] = set()
    for category in ("logic", "ux"):
        patterns = rules[language].get(category)
        threshold = rules.get("thresholds", {}).get(category)
        if (
            not isinstance(patterns, list)
            or not patterns
            or not all(isinstance(pattern, str) for pattern in patterns)
            or type(threshold) is not int
            or not 0 <= threshold <= 100
        ):
            errors.append(f"{language}.{category}: invalid patterns or threshold")
            continue
        files = source_files(root, patterns) - excluded
        if not files:
            errors.append(f"{language}.{category}: no matching source files")
            continue
        overlap = classified & files
        if overlap:
            errors.append(f"{language}.{category}: source classified twice: {sorted(overlap)}")
        classified.update(files)
        missing = files - totals.keys()
        if missing:
            errors.append(f"{language}.{category}: missing coverage for {sorted(missing)}")
            continue
        covered = sum(totals[name][0] for name in files)
        executable = sum(totals[name][1] for name in files)
        if executable == 0:
            errors.append(f"{language}.{category}: report has zero executable lines")
            continue
        percent = covered * 100 / executable
        print(f"{language}.{category}: {covered}/{executable} lines = {percent:.2f}% (need {threshold}%)")
        if covered * 100 < threshold * executable:
            errors.append(f"{language}.{category}: {percent:.2f}% is below {threshold}%")
    source_roots = rules[language].get("sourceRoots")
    if source_roots is not None:
        if (
            not isinstance(source_roots, list)
            or not source_roots
            or not all(isinstance(pattern, str) for pattern in source_roots)
        ):
            errors.append(f"{language}: invalid sourceRoots patterns")
        else:
            production = source_files(root, source_roots)
            if not production:
                errors.append(f"{language}: sourceRoots matched no production files")
            unclassified = production - classified - excluded
            if unclassified:
                errors.append(
                    f"{language}: unclassified production source: {sorted(unclassified)}"
                )
            outside_roots = classified - production
            if outside_roots:
                errors.append(
                    f"{language}: classified source outside sourceRoots: {sorted(outside_roots)}"
                )
    return errors


def main(argv: list[str] | None = None) -> int:
    """Parse LLVM reports and enforce the configured category coverage bars.

    Args:
        argv: Optional command-line arguments.

    Returns:
        Exit status zero only when all measured gates pass.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--language", required=True, choices=("swift", "kotlin", "csharp"))
    parser.add_argument("--report", type=Path, action="append", required=True)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--rules", type=Path, default=RULES)
    args = parser.parse_args(argv)
    try:
        rules = json.loads(args.rules.read_text(encoding="utf-8"))
        if args.language == "swift":
            totals = llvm_file_totals(args.report, args.root)
        else:
            candidates = source_files(
                args.root,
                [pattern for category in ("logic", "ux") for pattern in rules[args.language][category]]
            )
            totals = xml_file_totals(args.report, candidates)
        errors = check_coverage(totals, args.root, rules, args.language)
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"Coverage gate error: {error}", file=sys.stderr)
        return 2
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
