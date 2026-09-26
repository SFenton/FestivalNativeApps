#!/usr/bin/env python3
"""Validate and print the source-linked native migration backlog."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
BACKLOG = ROOT / "contracts/parity-backlog.json"
PRODUCT = ROOT / "contracts/product.json"
IDENTIFIER = re.compile(r"^[a-z][a-z0-9-]*$")
SOURCE_REF = re.compile(
    r"^(?:FortniteFestivalWeb|FSTService|packages/(?:core|theme))"
    r"(?:/[A-Za-z0-9_][A-Za-z0-9_.-]*)+\.(?:tsx|ts|cs):[1-9]\d*$"
)
STATES = {"pending", "in_progress", "blocked", "done"}
APPLE_STATES = {"absent", "placeholder", "partial", "verified"}


def validate(backlog: Any, product: Any) -> list[str]:
    """Reject missing routes, unverifiable work and cyclic dependencies.

    Args:
        backlog: Decoded feature and route work inventory.
        product: Existing cross-platform page contract.

    Returns:
        Actionable errors, or an empty list for a complete, consistent inventory.
    """
    if not isinstance(backlog, dict) or not isinstance(product, dict):
        return ["Both backlog and product must be JSON objects"]
    if backlog.get("schemaVersion") != 1:
        return ["Unsupported parity-backlog schema version"]
    pages = product.get("pages")
    epics = backlog.get("epics")
    routes = backlog.get("routes")
    if not isinstance(pages, list) or not isinstance(epics, list) or not isinstance(routes, list):
        return ["Product pages, backlog epics and routes must be lists"]
    if not epics:
        return ["Backlog must contain actionable epics"]

    errors: list[str] = []
    epic_ids: set[str] = set()
    epic_map: dict[str, dict[str, Any]] = {}
    for index, epic in enumerate(epics):
        if not isinstance(epic, dict):
            errors.append(f"epics[{index}]: expected an object")
            continue
        identifier = epic.get("id")
        if not isinstance(identifier, str) or not IDENTIFIER.fullmatch(identifier):
            errors.append(f"epics[{index}]: invalid id")
            continue
        if identifier in epic_ids:
            errors.append(f"epics[{index}]: duplicate id {identifier}")
        epic_ids.add(identifier)
        epic_map[identifier] = epic
        if type(epic.get("priority")) is not int or epic["priority"] not in (0, 1, 2):
            errors.append(f"{identifier}: priority must be 0, 1 or 2")
        if not isinstance(epic.get("status"), str) or epic["status"] not in STATES:
            errors.append(f"{identifier}: invalid status")
        if epic.get("status") == "blocked" and (
            not isinstance(epic.get("blockedOn"), str) or not epic["blockedOn"].strip()
        ):
            errors.append(f"{identifier}: blocked work needs an explicit blocker")
        references = epic.get("sourceRefs")
        if not isinstance(references, list) or not references or any(
            not isinstance(ref, str) or not SOURCE_REF.fullmatch(ref) for ref in references
        ):
            errors.append(f"{identifier}: cite at least one source file and line")
        acceptance = epic.get("acceptance")
        if not isinstance(acceptance, list) or not acceptance or any(
            not isinstance(item, str) or not item.strip() for item in acceptance
        ):
            errors.append(f"{identifier}: acceptance must contain nonempty checks")
        dependencies = epic.get("dependsOn")
        if not isinstance(dependencies, list) or any(
            not isinstance(dep, str) for dep in dependencies
        ):
            errors.append(f"{identifier}: dependencies must be epic IDs")
        elif len(dependencies) != len(set(dependencies)):
            errors.append(f"{identifier}: duplicate dependencies")

    for identifier, epic in epic_map.items():
        dependencies = epic.get("dependsOn", [])
        if not isinstance(dependencies, list):
            continue
        for dep in dependencies:
            if dep not in epic_ids:
                errors.append(f"{identifier}: unknown dependency {dep}")
            elif dep == identifier:
                errors.append(f"{identifier}: cannot depend on itself")
            elif epic.get("status") == "done" and epic_map[dep].get("status") != "done":
                errors.append(f"{identifier}: marked done before dependency {dep}")

    visited: set[str] = set()
    exploring: set[str] = set()

    def visit(identifier: str) -> None:
        if identifier in exploring:
            errors.append(f"{identifier}: cyclic dependency")
            return
        if identifier in visited:
            return
        exploring.add(identifier)
        for dependency in epic_map[identifier].get("dependsOn", []):
            if isinstance(dependency, str) and dependency in epic_map:
                visit(dependency)
        exploring.remove(identifier)
        visited.add(identifier)

    for identifier in epic_ids:
        visit(identifier)

    expected: set[str] = set()
    for page in pages:
        identifier = page.get("id") if isinstance(page, dict) else None
        if not isinstance(identifier, str):
            errors.append("Product page has an invalid route id")
        else:
            expected.add(identifier)
    route_ids: set[str] = set()
    referenced_epics: set[str] = set()
    for index, route in enumerate(routes):
        if not isinstance(route, dict):
            errors.append(f"routes[{index}]: expected an object")
            continue
        identifier = route.get("id")
        if not isinstance(identifier, str) or not IDENTIFIER.fullmatch(identifier):
            errors.append(f"routes[{index}]: invalid id")
            continue
        if identifier in route_ids:
            errors.append(f"routes[{index}]: duplicate id {identifier}")
        route_ids.add(identifier)
        if not isinstance(route.get("apple"), str) or route["apple"] not in APPLE_STATES:
            errors.append(f"{identifier}: invalid Apple state")
        if not isinstance(route.get("gap"), str) or not route["gap"].strip():
            errors.append(f"{identifier}: missing native-versus-source gap")
        owners = route.get("epics")
        if not isinstance(owners, list) or not owners:
            errors.append(f"{identifier}: route needs migration epics")
            continue
        for owner in owners:
            if not isinstance(owner, str) or owner not in epic_ids:
                errors.append(f"{identifier}: unknown epic {owner}")
            else:
                referenced_epics.add(owner)
    for identifier in sorted(expected - route_ids):
        errors.append(f"Missing product route {identifier}")
    for identifier in sorted(route_ids - expected):
        errors.append(f"Unknown product route {identifier}")
    for identifier in sorted(epic_ids - referenced_epics):
        if epic_map[identifier].get("shared") is not True:
            errors.append(f"{identifier}: orphan epic needs a route or shared=true")
    for page in pages:
        if isinstance(page, dict) and page.get("status") == "implemented":
            route = next((entry for entry in routes if isinstance(entry, dict)
                          and entry.get("id") == page.get("id")), None)
            if route is None or route.get("apple") != "verified":
                errors.append(f"{page.get('id')}: product claims implementation before Apple verification")
    return errors


def ready(backlog: dict[str, Any]) -> list[dict[str, Any]]:
    """Select incomplete epics whose prerequisites have actually been completed.

    Args:
        backlog: Validated backlog with epic status and dependencies.

    Returns:
        Pending epics sorted by priority and source order.
    """
    done = {epic["id"] for epic in backlog["epics"] if epic["status"] == "done"}
    return sorted(
        (epic for epic in backlog["epics"]
         if epic["status"] == "pending" and set(epic["dependsOn"]) <= done),
        key=lambda epic: epic["priority"],
    )


def main(argv: list[str] | None = None) -> int:
    """Check the contract and optionally print the full route/feature to-do list.

    Args:
        argv: Command-line arguments for deterministic tests.

    Returns:
        Zero only for an internally consistent, complete route inventory.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="Print all feature work and route gaps")
    parser.add_argument("--ready", action="store_true", help="Print only unblocked pending epics")
    args = parser.parse_args(argv)
    try:
        backlog = json.loads(BACKLOG.read_text(encoding="utf-8"))
        product = json.loads(PRODUCT.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        print(f"Cannot read parity contract: {error}", file=sys.stderr)
        return 1
    errors = validate(backlog, product)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    verified = sum(route["apple"] == "verified" for route in backlog["routes"])
    print(f"Parity backlog valid: {len(backlog['routes'])} routes, "
          f"{len(backlog['epics'])} feature epics; {verified} Apple routes verified.")
    if args.ready:
        for epic in ready(backlog):
            print(f"P{epic['priority']} {epic['id']}: {epic['acceptance'][0]}")
    elif args.list:
        for epic in sorted(backlog["epics"], key=lambda item: item["priority"]):
            print(f"P{epic['priority']} [{epic['status']}] {epic['id']}: "
                  f"{epic['acceptance'][0]}")
            if epic["status"] == "blocked":
                print(f"  BLOCKED: {epic['blockedOn']}")
        for route in backlog["routes"]:
            print(f"route {route['id']} [{route['apple']}]: {route['gap']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
