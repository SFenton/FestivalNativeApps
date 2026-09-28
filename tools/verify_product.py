#!/usr/bin/env python3
"""Validate the cross-platform page and control inventory without third-party packages."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "contracts" / "product.json"
PLATFORMS = ("ios", "macos", "android", "windows")
GUARDS = frozenset({"none", "player", "selection", "feature"})
SLUG = re.compile(r"^[a-z][a-z0-9-]*$")
TEST_ID = re.compile(r"^fst\.[a-z][a-z0-9.-]*(?:\.\*)?$")
SOURCE_TEST_ID = re.compile(
    r'(?:\.accessibilityIdentifier\s*\(|\btestTag\s*\('
    r'|\bAutomationProperties\.SetAutomationId\s*\([^,]+,'
    r'|\bAutomationProperties\.AutomationId\s*=)\s*"(?P<id>fst\.[^"]+)"'
)
SOURCE_REF = re.compile(r"^[^:\n]+:\d+$")
NATIVE_SOURCE = (
    "apple/Sources/**/*.swift", "apple/Apps/**/*.swift",
    "android/**/*.kt", "windows/**/*.cs", "windows/**/*.xaml",
)


def unregistered_native_ids(root: Path, registry: dict[str, str]) -> list[str]:
    """Compare literal native accessibility/test IDs with the central registry.

    Args:
        root: Native product repository containing platform source code.
        registry: Declared static IDs or dynamic-family IDs ending in `.*`.

    Returns:
        File/line diagnostics for any ID that is not registered.
    """
    errors: list[str] = []
    for pattern in NATIVE_SOURCE:
        for path in root.glob(pattern):
            if not path.is_file():
                continue
            source = path.read_text(encoding="utf-8")
            for match in SOURCE_TEST_ID.finditer(source):
                token = match.group("id")
                for interpolation in ("\\(", "${", "{"):
                    if interpolation in token:
                        token = token.split(interpolation, 1)[0] + "*"
                        break
                if token not in registry and not any(
                    family.endswith(".*")
                    and token.startswith(family[:-1])
                    and len(token) > len(family) - 1
                    for family in registry
                ):
                    line = source.count("\n", 0, match.start("id")) + 1
                    errors.append(
                        f"{path.relative_to(root)}:{line}: unregistered native test ID {token}"
                    )
    return errors


def _is_nonempty_text(value: Any) -> bool:
    """Return whether a value is a non-blank string.

    Args:
        value: Manifest field to inspect.

    Returns:
        True only for a non-blank string.
    """
    return isinstance(value, str) and bool(value.strip())


def _check_evidence(
    item: dict[str, Any], *, root: Path, prefix: str, states: list[str] | None
) -> list[str]:
    """Check four-platform test evidence for an implemented surface.

    Args:
        item: Implemented page or control from the manifest.
        root: Root against which local spec and test paths are resolved.
        prefix: Human-readable path to the item for errors.
        states: Required control states, or None for a page.

    Returns:
        Explanations for incomplete or invalid evidence.
    """
    errors: list[str] = []
    spec = item.get("spec")
    if not _is_nonempty_text(spec) or not (root / str(spec)).is_file():
        errors.append(f"{prefix}: implemented surface needs an existing spec file")
    evidence = item.get("evidence")
    if not isinstance(evidence, dict):
        return errors + [f"{prefix}: implemented surface needs per-platform evidence"]
    if set(evidence) != set(PLATFORMS):
        errors.append(f"{prefix}: evidence platforms must be {', '.join(PLATFORMS)}")
    for platform in PLATFORMS:
        record = evidence.get(platform)
        if not isinstance(record, dict):
            errors.append(f"{prefix}.{platform}: missing test evidence")
            continue
        required = ("tests", "visual", "accessibility")
        for field in required:
            paths = record.get(field)
            if not isinstance(paths, list) or not paths or not all(
                _is_nonempty_text(path) and (root / path).is_file()
                for path in paths
            ):
                errors.append(f"{prefix}.{platform}: {field} needs existing file paths")
        if states is not None:
            covered = record.get("states")
            if not isinstance(covered, list) or set(covered) != set(states):
                errors.append(f"{prefix}.{platform}: states must cover {', '.join(states)}")
    return errors


def validate_product(manifest: Any, *, root: Path, strict: bool = False) -> list[str]:
    """Validate IDs, source links, states, evidence and parity status.

    Args:
        manifest: Parsed JSON document, including page, control and test ID registries.
        root: Repository root containing local specs and test evidence.
        strict: Require all surfaces to be implemented on all platforms.

    Returns:
        A list of actionable validation errors; empty means the selected gate passed.
    """
    if not isinstance(manifest, dict):
        return ["product manifest must be a JSON object"]
    errors: list[str] = []
    if manifest.get("schemaVersion") != 1:
        errors.append("schemaVersion must be 1")
    source = manifest.get("source")
    if not isinstance(source, dict) or not re.fullmatch(
        r"[0-9a-f]{40}", str(source.get("revision", ""))
    ):
        errors.append("source.revision must pin a 40-character git commit")
    if manifest.get("platforms") != list(PLATFORMS):
        errors.append("platforms must list ios, macos, android, windows in that order")
    pages = manifest.get("pages")
    controls = manifest.get("controls")
    ids = manifest.get("testIds")
    if not isinstance(pages, list) or not pages:
        return errors + ["pages must be a nonempty list"]
    if not isinstance(controls, list):
        return errors + ["controls must be a list"]
    if not isinstance(ids, dict):
        return errors + ["testIds must map semantic IDs to page/control IDs"]

    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    for index, page in enumerate(pages):
        prefix = f"pages[{index}]"
        if not isinstance(page, dict):
            errors.append(f"{prefix}: must be an object")
            continue
        identifier = page.get("id")
        path = page.get("path")
        if not isinstance(identifier, str) or not SLUG.fullmatch(identifier):
            errors.append(f"{prefix}: invalid id")
        elif identifier in seen_ids:
            errors.append(f"{prefix}: duplicate id {identifier}")
        else:
            seen_ids.add(identifier)
        if not isinstance(path, str) or not path.startswith("/") or "//" in path:
            errors.append(f"{prefix}: path must be an absolute route pattern")
        elif path in seen_paths:
            errors.append(f"{prefix}: duplicate route {path}")
        else:
            seen_paths.add(path)
        if page.get("guard") not in GUARDS:
            errors.append(f"{prefix}: unknown route guard")
        if not isinstance(page.get("source"), str) or not SOURCE_REF.fullmatch(page["source"]):
            errors.append(f"{prefix}: source must contain file:line")
        status = page.get("status")
        if status not in ("pending", "implemented"):
            errors.append(f"{prefix}: status must be pending or implemented")
        if strict and status != "implemented":
            errors.append(f"{prefix}: pending page {identifier}")
        if status == "implemented":
            errors.extend(_check_evidence(page, root=root, prefix=prefix, states=None))

    for index, control in enumerate(controls):
        prefix = f"controls[{index}]"
        if not isinstance(control, dict):
            errors.append(f"{prefix}: must be an object")
            continue
        identifier = control.get("id")
        if not isinstance(identifier, str) or not SLUG.fullmatch(identifier):
            errors.append(f"{prefix}: invalid id")
        elif identifier in seen_ids:
            errors.append(f"{prefix}: duplicate id {identifier}")
        else:
            seen_ids.add(identifier)
        states = control.get("states")
        if (
            not isinstance(states, list)
            or not states
            or any(not isinstance(state, str) or not SLUG.fullmatch(state) for state in states)
            or len(states) != len(set(states))
        ):
            errors.append(f"{prefix}: states must be distinct nonempty slugs")
            states = []
        if not isinstance(control.get("source"), str) or not SOURCE_REF.fullmatch(
            control["source"]
        ):
            errors.append(f"{prefix}: source must contain file:line")
        test_id = control.get("testId")
        if not isinstance(test_id, str) or not TEST_ID.fullmatch(test_id):
            errors.append(f"{prefix}: invalid testId")
        elif ids.get(test_id) != identifier:
            errors.append(f"{prefix}: testId is absent or mismatched in registry")
        status = control.get("status")
        if status not in ("pending", "implemented"):
            errors.append(f"{prefix}: status must be pending or implemented")
        if strict and status != "implemented":
            errors.append(f"{prefix}: pending control {identifier}")
        if status == "implemented":
            errors.extend(_check_evidence(control, root=root, prefix=prefix, states=states))

    for test_id, owner in ids.items():
        if not isinstance(test_id, str) or not TEST_ID.fullmatch(test_id):
            errors.append(f"testIds: invalid ID {test_id}")
        if not isinstance(owner, str) or owner not in seen_ids:
            errors.append(f"testIds: unknown owner {owner}")
    # Every declared page/control implicitly owns the `fst.<id>.*` family, so lanes
    # can add controls under their own page prefix without editing the registry.
    implicit = {f"fst.{item['id']}.*": item["id"]
                for item in [*pages, *controls]
                if isinstance(item, dict) and isinstance(item.get("id"), str)}
    errors.extend(unregistered_native_ids(root, {**implicit, **ids}))
    return errors


def main(argv: list[str] | None = None) -> int:
    """Run inventory checks and print an accurate parity status.

    Args:
        argv: Command-line arguments; None uses the process arguments.

    Returns:
        Zero for a passing gate, nonzero for missing evidence or invalid input.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    parser.add_argument("--strict", action="store_true", help="Fail on pending surfaces")
    args = parser.parse_args(argv)
    try:
        manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"Cannot read product manifest: {error}", file=sys.stderr)
        return 2
    errors = validate_product(manifest, root=ROOT, strict=args.strict)
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    if errors:
        return 1
    pending_pages = sum(page["status"] == "pending" for page in manifest["pages"])
    pending_controls = sum(control["status"] == "pending" for control in manifest["controls"])
    print(
        f"Inventory valid: {len(manifest['pages'])} routes, "
        f"{len(manifest['controls'])} registered controls; "
        f"{pending_pages} pages and {pending_controls} controls not yet certified."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
