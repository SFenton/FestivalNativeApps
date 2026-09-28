#!/usr/bin/env python3
"""Generate the Windows Licenses manifest from the app's restored NuGet graph.

Reads ``windows/Festival.App/obj/project.assets.json`` (run ``tools/windows/build.ps1`` first), keeps every
package that ships in the self-contained app plus the .NET runtime pack and the C#/WinRT Windows SDK projection,
reads each package's nuspec and license file from the NuGet cache, de-duplicates identical license bodies and
writes ``windows/Festival.App/Assets/licenses.json`` (loaded by the Licenses page; no network).

Usage::

    python tools/windows/licenses.py            # regenerate
    python tools/windows/licenses.py --check    # exit 1 when the committed manifest is stale
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "windows" / "Festival.App" / "obj" / "project.assets.json"
OUTPUT = ROOT / "windows" / "Festival.App" / "Assets" / "licenses.json"

# Build-time only: never copied into the app.
BUILD_ONLY = {"microsoft.windows.sdk.buildtools", "microsoft.windows.sdk.buildtools.msix"}
# Runtime packs that the self-contained build actually uses (the others in downloadDependencies are unused).
RUNTIME_PACKS = {"microsoft.netcore.app.runtime.win-x64", "microsoft.windows.sdk.net.ref"}
DISPLAY_NAMES = {
    "microsoft.netcore.app.runtime.win-x64": ".NET Runtime",
    "microsoft.windows.sdk.net.ref": "C#/WinRT Windows SDK Projection",
}
LICENSE_FILES = ("license.txt", "LICENSE.txt", "LICENSE.TXT", "License.md", "LICENSE.md", "LICENSE")
MIT_TEMPLATE = """MIT License

{copyright}

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""


def nuget_root() -> Path:
    """Return the global packages folder."""
    return Path(os.environ.get("NUGET_PACKAGES") or Path.home() / ".nuget" / "packages")


def read_nuspec(folder: Path) -> dict[str, str]:
    """Return license, copyright and project URL fields from a package's nuspec."""
    nuspec = next(folder.glob("*.nuspec"))
    meta = ET.parse(nuspec).getroot().find("{*}metadata")
    fields: dict[str, str] = {}
    for child in meta if meta is not None else []:
        tag = child.tag.split("}")[-1]
        if tag == "license":
            fields["licenseType"] = child.get("type", "")
        if tag in {"license", "licenseUrl", "copyright", "projectUrl", "id"}:
            fields[tag] = (child.text or "").strip()
    return fields


def license_text(folder: Path, fields: dict[str, str]) -> tuple[str, str]:
    """Return (SPDX-like label, full text) for a package."""
    if fields.get("licenseType") == "file":
        text = (folder / fields["license"]).read_text(encoding="utf-8-sig", errors="replace")
        label = "BSD-3-Clause" if "Redistribution and use in source and binary forms" in text else "Microsoft Software License"
        return label, text
    expression = fields.get("license", "")
    for name in LICENSE_FILES:
        candidate = folder / name
        if candidate.exists():
            return expression or "See license", candidate.read_text(encoding="utf-8-sig", errors="replace")
    if expression == "MIT":
        return "MIT", MIT_TEMPLATE.format(copyright=fields.get("copyright") or "Copyright (c) Microsoft Corporation.")
    if not expression and (url := fields.get("licenseUrl")):
        # Older packages (the Windows SDK projection) only link their terms.
        return "Microsoft Windows SDK License", (
            f"{fields.get('copyright', '')}\n\nThis package is licensed under the Microsoft Windows SDK license terms, "
            f"published at {url}. The terms are not included in the package.")
    return expression or "Unknown", f"License: {expression or 'not declared'}"


def normalize(text: str) -> str:
    """Normalize line endings and trailing whitespace so identical bodies de-duplicate."""
    lines = [line.rstrip() for line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n")]
    return "\n".join(lines).strip() + "\n"


def build_manifest() -> dict:
    """Build the manifest dictionary from the assets file."""
    assets = json.loads(ASSETS.read_text(encoding="utf-8"))
    wanted: list[tuple[str, str]] = []
    for key, library in assets["libraries"].items():
        if library.get("type") != "package":
            continue
        name, version = key.split("/")
        if name.lower() not in BUILD_ONLY:
            wanted.append((name, version))
    for framework in assets["project"]["frameworks"].values():
        for dependency in framework.get("downloadDependencies", []):
            if dependency["name"].lower() in RUNTIME_PACKS:
                wanted.append((dependency["name"], re.sub(r"[\[\]\s]", "", dependency["version"]).split(",")[0]))

    packages, texts = [], {}
    root = nuget_root()
    for name, version in sorted(set(wanted), key=lambda item: item[0].lower()):
        folder = root / name.lower() / version
        fields = read_nuspec(folder)
        label, text = license_text(folder, fields)
        body = normalize(text)
        text_id = hashlib.sha256(body.encode("utf-8")).hexdigest()[:12]
        texts[text_id] = body
        packages.append({
            "id": name,
            "name": DISPLAY_NAMES.get(name.lower(), name),
            "version": version,
            "ecosystem": "NuGet",
            "license": label,
            "url": fields.get("projectUrl") or None,
            "textId": text_id,
        })
    return {"schemaVersion": 1, "packages": packages, "texts": dict(sorted(texts.items()))}


def main() -> int:
    """Write or check the manifest."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail when the committed manifest is stale")
    args = parser.parse_args()
    if not ASSETS.exists():
        print(f"missing {ASSETS}; run tools/windows/build.ps1 first", file=sys.stderr)
        return 2
    rendered = json.dumps(build_manifest(), indent=2, ensure_ascii=False) + "\n"
    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != rendered:
            print(f"{OUTPUT.relative_to(ROOT)} is stale; run python tools/windows/licenses.py", file=sys.stderr)
            return 1
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(rendered, encoding="utf-8", newline="\n")
    manifest = json.loads(rendered)
    print(f"wrote {len(manifest['packages'])} packages, {len(manifest['texts'])} license texts, {len(rendered)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
