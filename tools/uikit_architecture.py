#!/usr/bin/env python3
"""Guard complete UIKit source ownership separately from cross-platform parity."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path("apple/Sources/FestivalUI/UIKitPort")
CONTRACT = Path("contracts/uikit-architecture.json")
CLASS = re.compile(r"\bclass\s+([A-Za-z_]\w*)(?:\s*<[^{}\n]+>)?\s*:\s*(\w+)")
MOTION = re.compile(
    r"\b(?:UIView\.(?:animate|animateKeyframes|transition)|UIViewPropertyAnimator"
    r"|CABasicAnimation|CAKeyframeAnimation|CADisplayLink|addSymbolEffect)\s*\("
)
NATIVE_CONTAINERS = {
    "UKRootViewController": "window shell owns native tab/navigation containers",
    "UKSectionStack": "navigation container moves persistent route controllers",
    "UKSheetNavigationController": "native UINavigationController for one modal task",
}
UIKIT_CONTROLLER_BASES = {
    "UIViewController", "UINavigationController", "UITabBarController",
    "UISplitViewController", "UIPageViewController", "UITableViewController",
    "UICollectionViewController", "UISearchController", "UIAlertController",
    "UIActivityViewController", "UIDocumentPickerViewController", "UIImagePickerController",
}
DISPOSITIONS = {"pending", "shared-component", "feature-composition", "native-container", "debug-only"}


def discover(root: Path) -> dict[str, dict[str, Any]]:
    """Find every production UIKit file and its declared controller ancestry.

    Args:
        root: Repository root containing the UIKit frontend.

    Returns:
        Source records keyed by repository-relative path, including content digests.
    """
    records = {}
    for path in sorted((root / SOURCE).rglob("*.swift")):
        source = path.read_text(encoding="utf-8")
        name = path.relative_to(root).as_posix()
        records[name] = {
            "path": name,
            "sourceHash": hashlib.sha256(source.encode()).hexdigest(),
            "classes": [{"name": match[0], "base": match[1]} for match in CLASS.findall(source)],
            "motionSites": [
                {"line": source.count("\n", 0, match.start()) + 1, "api": match.group().split("(")[0].strip()}
                for match in MOTION.finditer(source)
            ],
        }
    return records


def refresh(root: Path, previous: dict[str, Any]) -> dict[str, Any]:
    """Refresh discovery while invalidating reviews of changed source.

    Args:
        root: Repository root.
        previous: Existing ownership contract, if any.

    Returns:
        A new contract preserving only reviews bound to identical source.
    """
    old = {item["path"]: item for item in previous.get("files", [])}
    files = []
    for name, found in discover(root).items():
        prior = old.get(name, {})
        same = prior.get("sourceHash") == found["sourceHash"]
        files.append({
            **found,
            "disposition": prior.get("disposition", "pending") if same else "pending",
            "owner": prior.get("owner", ""),
            "verification": prior.get("verification", []) if same else [],
            "note": prior.get("note", "") if same else "",
        })
    return {
        "schemaVersion": 1,
        "scope": ["ios", "ipados", "iphone-duo"],
        "beforeRevision": previous.get("beforeRevision", "412e0370d8b3eba79ffaee445b205c9b8203b9b1"),
        "description": "Complete source-ownership review; not runtime, coverage or performance certification.",
        "files": files,
    }


def validate(contract: Any, *, root: Path, strict: bool = False) -> list[str]:
    """Reject missing source, stale reviews and bypasses of shared lifecycle.

    Args:
        contract: Parsed ownership contract.
        root: Native app repository root.
        strict: Require every file's review and existing verification references.

    Returns:
        Actionable errors. Empty means this gate only, not product certification, passed.
    """
    if not isinstance(contract, dict) or contract.get("schemaVersion") != 1:
        return ["UIKit architecture contract requires schemaVersion 1"]
    actual = discover(root)
    if not actual:
        return ["UIKit architecture discovery found no source files"]
    records = contract.get("files")
    if not isinstance(records, list):
        return ["UIKit architecture contract requires files"]
    errors = []
    registered = {}
    for record in records:
        if not isinstance(record, dict) or not isinstance(record.get("path"), str):
            errors.append("invalid UIKit file record")
            continue
        name = record["path"]
        if name in registered:
            errors.append(f"{name}: duplicate ownership record")
        registered[name] = record
    for name in sorted(set(actual) - set(registered)):
        errors.append(f"{name}: unreviewed new UIKit source")
    for name in sorted(set(registered) - set(actual)):
        errors.append(f"{name}: ownership record refers to missing source")
    classes = {
        item["name"]: item["base"]
        for record in actual.values()
        for item in record["classes"]
    }

    def owns_lifecycle(name: str) -> bool:
        seen = set()
        while name not in seen:
            if name == "UKScreenViewController":
                return True
            seen.add(name)
            name = classes.get(name, "")
            if not name:
                return False
        return False

    def is_controller(name: str) -> bool:
        seen = set()
        while name not in seen:
            if name in UIKIT_CONTROLLER_BASES:
                return True
            seen.add(name)
            name = classes.get(name, "")
            if not name:
                return False
        return False

    for name, found in actual.items():
        record = registered.get(name)
        if record is None:
            continue
        source = (root / name).read_text(encoding="utf-8")
        if record.get("sourceHash") != found["sourceHash"]:
            errors.append(f"{name}: source changed since its ownership review")
        if record.get("classes") != found["classes"]:
            errors.append(f"{name}: declared ancestry differs from discovery")
        if record.get("motionSites") != found["motionSites"]:
            errors.append(f"{name}: native animation sites differ from discovery")
        if record.get("disposition") not in DISPOSITIONS:
            errors.append(f"{name}: unknown architecture disposition")
        if not source.lstrip().startswith("#if os(iOS)"):
            errors.append(f"{name}: UIKit frontend must remain iOS-conditional")
        if re.search(r"\bimport\s+SwiftUI\b|UIHostingController|UIHostingConfiguration", source):
            errors.append(f"{name}: SwiftUI rendering bypasses the UIKit frontend")
        if "method_exchangeImplementations" in source:
            errors.append(f"{name}: global method swizzling bypasses explicit lifecycle")
        if re.search(r"(?:(?<![\w.])|self\.)present\(\s*(?:alert|sheet|picker|controller|preview)\b", source):
            errors.append(f"{name}: direct native presentation bypasses the window coordinator")
        for item in found["classes"]:
            controller = item["name"]
            if controller == "UKScreenViewController" or controller in NATIVE_CONTAINERS:
                continue
            if is_controller(controller) and not owns_lifecycle(controller):
                errors.append(f"{name}: {controller} bypasses UKScreenViewController lifecycle")
        if strict:
            if record.get("disposition") == "pending":
                errors.append(f"{name}: architecture review is pending")
            if not record.get("owner") or not record.get("note"):
                errors.append(f"{name}: review needs its canonical owner and rationale")
            references = record.get("verification")
            if not isinstance(references, list) or not references:
                errors.append(f"{name}: review needs verification references")
            else:
                for reference in references:
                    target = root / str(reference)
                    if not target.is_file() or not target.resolve().is_relative_to(root.resolve()):
                        errors.append(f"{name}: invalid verification reference {reference}")
    return errors


def main(argv: list[str] | None = None) -> int:
    """Refresh or check the complete UIKit ownership inventory.

    Args:
        argv: Optional command-line arguments for focused tests.

    Returns:
        Zero when the selected operation succeeds, otherwise one.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--refresh", action="store_true")
    parser.add_argument("--strict", action="store_true")
    parser.add_argument("--review", action="append", default=[], metavar="PATH",
                        help="record an explicit source-ownership review for this exact path")
    parser.add_argument("--owner")
    parser.add_argument("--disposition", choices=sorted(DISPOSITIONS - {"pending"}))
    parser.add_argument("--note")
    parser.add_argument("--verification", action="append", default=[])
    args = parser.parse_args(argv)
    path = args.root / CONTRACT
    contract = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
    if args.refresh:
        contract = refresh(args.root, contract)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(contract, indent=2) + "\n", encoding="utf-8")
        print(f"Refreshed {len(contract['files'])} UIKit ownership records; changed source requires review")
        return 0
    if args.review:
        if not (args.owner and args.disposition and args.note and args.verification):
            parser.error("--review requires owner, disposition, note and verification")
        errors = validate(contract, root=args.root)
        if errors:
            parser.error("refresh the source inventory before recording reviews: " + "; ".join(errors))
        records = {record["path"]: record for record in contract["files"]}
        for name in args.review:
            if name not in records:
                parser.error(f"not an exact UIKit source path: {name}")
        for reference in args.verification:
            target = args.root / reference
            if not target.is_file() or not target.resolve().is_relative_to(args.root.resolve()):
                parser.error(f"invalid verification reference: {reference}")
        for name in args.review:
            records[name].update(
                owner=args.owner, disposition=args.disposition, note=args.note, verification=args.verification
            )
        path.write_text(json.dumps(contract, indent=2) + "\n", encoding="utf-8")
        print(f"Recorded {len(args.review)} source-ownership reviews; runtime gates remain independent")
        return 0
    errors = validate(contract, root=args.root, strict=args.strict)
    for error in errors:
        print(f"ERROR: {error}")
    if not errors:
        print(f"UIKit ownership valid: {len(contract['files'])} source files; runtime gates remain independent")
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
