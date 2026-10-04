#!/usr/bin/env python3
"""Generate the Android Licenses manifest from the app's real dependency graph.

Runs ``:app:dependencies --configuration releaseRuntimeClasspath`` (or reads a
saved tree with ``--deps-file``), keeps every resolved runtime module, reads
each module's POM (following ``<parent>`` POMs) from the Gradle cache for its
name, project URL and licenses, maps them to SPDX IDs, and writes
``android/app/src/main/assets/licenses.json`` with one full license text per
SPDX ID (from ``tools/android/license-texts/<SPDX>.txt``).

Usage (repo root)::

    python tools/android/licenses.py            # regenerate
    python tools/android/licenses.py --check    # fail when the committed manifest is stale

Run it in the same commit as any dependency change.
"""

from __future__ import annotations

import argparse
import http.client
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

# region Paths

ROOT = Path(__file__).resolve().parents[2]
ANDROID = ROOT / "android"
OUTPUT = ANDROID / "app" / "src" / "main" / "assets" / "licenses.json"
TEXTS = Path(__file__).resolve().parent / "license-texts"
CACHE = Path(os.environ.get("GRADLE_USER_HOME", Path.home() / ".gradle")) / "caches" / "modules-2" / "files-2.1"

# endregion

# region Dependency tree

LINE = re.compile(r"[+\\]--- (?P<group>[^\s:]+):(?P<artifact>[^\s:]+)(?::(?P<version>[^\s]+))?(?: -> (?P<resolved>[^\s]+))?(?P<rest>.*)$")


def gradle_tree() -> str:
    """Run Gradle and return the release runtime dependency tree.

    Returns:
        The ``dependencies`` task output.
    """
    # gradlew is committed without the executable bit (Windows hosts), so run it through bash.
    wrapper = [str(ANDROID / "gradlew.bat")] if os.name == "nt" else ["bash", str(ANDROID / "gradlew")]
    result = subprocess.run(
        [*wrapper, "-p", str(ANDROID), "--no-daemon", "-q", ":app:dependencies", "--configuration", "releaseRuntimeClasspath"],
        check=True, capture_output=True, text=True,
    )
    return result.stdout


def parse_tree(text: str) -> list[tuple[str, str, str]]:
    """Resolved runtime modules from a ``dependencies`` tree.

    Constraint-only ``(c)`` and unresolved ``(n)`` entries are skipped, BOMs
    are dropped, and a Kotlin Multiplatform root module is dropped when its
    ``-android``/``-jvm`` variant (the artifact that ships) is present.

    Args:
        text: Tree output.

    Returns:
        Sorted unique ``(group, artifact, version)`` tuples.
    """
    coords: set[tuple[str, str, str]] = set()
    for line in text.splitlines():
        match = LINE.search(line)
        if not match:
            continue
        rest = match["rest"]
        if "(c)" in rest or "(n)" in rest:
            continue
        version = match["resolved"] or match["version"]
        if not version or match["artifact"].endswith("-bom"):
            continue
        coords.add((match["group"], match["artifact"], version))
    names = {(g, a) for g, a, _ in coords}
    kept = {
        (g, a, v) for g, a, v in coords
        if not any((g, a + suffix) in names for suffix in ("-android", "-jvm", "-androidx"))
    }
    return sorted(kept)

# endregion

# region POMs

NS = re.compile(r"\{.*?\}")


POM_CACHE = ANDROID / "build" / "license-poms"
REPOSITORIES = ("https://dl.google.com/dl/android/maven2", "https://repo1.maven.org/maven2")


def find_pom(group: str, artifact: str, version: str) -> Path | None:
    """Locate a POM: the Gradle module cache, else a local download cache,
    else a public read-only download from Google Maven / Maven Central (Gradle
    keeps resolved POMs only in its binary metadata store).

    Args:
        group: Group ID.
        artifact: Artifact ID.
        version: Version.

    Returns:
        POM path, or None when unavailable.
    """
    folder = CACHE / group / artifact / version
    if folder.is_dir():
        for pom in folder.glob(f"*/{artifact}-{version}.pom"):
            return pom
    local = POM_CACHE / group / f"{artifact}-{version}.pom"
    if local.exists():
        return local
    relative = f"{group.replace('.', '/')}/{artifact}/{version}/{artifact}-{version}.pom"
    for repository in REPOSITORIES:
        body = download(f"{repository}/{relative}")
        if body is None:
            continue
        local.parent.mkdir(parents=True, exist_ok=True)
        local.write_bytes(body)
        return local
    return None


def download(url: str, attempts: int = 4) -> bytes | None:
    """Fetch a public POM, retrying transient network failures (CI runners
    occasionally drop a request, which used to fail the manifest check).

    Args:
        url: POM URL.
        attempts: Maximum tries for transient failures.

    Returns:
        A parseable body, or None when the repository lacks it or every attempt failed.
    """
    for attempt in range(attempts):
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                body = response.read()
            ET.fromstring(body)
            return body
        except urllib.error.HTTPError as error:
            if error.code in (403, 404, 410):
                return None
        except (urllib.error.URLError, OSError, ET.ParseError, http.client.HTTPException):
            pass
        if attempt + 1 < attempts:
            time.sleep(2 ** attempt)
    return None


def read_pom(path: Path) -> dict:
    """Extract name, URL, licenses and parent from a POM.

    Args:
        path: POM file.

    Returns:
        Dict with ``name``, ``url``, ``licenses`` [(name, url)], ``parent`` (g, a, v) or None.
    """
    root = ET.parse(path).getroot()
    for element in root.iter():
        element.tag = NS.sub("", element.tag)

    def text(node, tag):
        child = node.find(tag) if node is not None else None
        return child.text.strip() if child is not None and child.text else None

    licenses = [(text(lic, "name") or "", text(lic, "url") or "") for lic in root.findall("licenses/license")]
    parent = root.find("parent")
    parent_coords = (text(parent, "groupId"), text(parent, "artifactId"), text(parent, "version")) if parent is not None else None
    return {"name": text(root, "name"), "url": text(root, "url"), "licenses": licenses, "parent": parent_coords}


def module_info(group: str, artifact: str, version: str) -> dict:
    """POM info with licenses/URL inherited from parent POMs when missing.

    Args:
        group: Group ID.
        artifact: Artifact ID.
        version: Version.

    Returns:
        Dict with ``name``, ``url``, ``licenses``.
    """
    info = {"name": None, "url": None, "licenses": []}
    coords = (group, artifact, version)
    for _ in range(6):
        pom = find_pom(*coords) if coords and all(coords) else None
        if pom is None:
            break
        data = read_pom(pom)
        info["name"] = info["name"] or data["name"]
        info["url"] = info["url"] or data["url"]
        if not info["licenses"]:
            info["licenses"] = data["licenses"]
        if info["licenses"] and info["url"]:
            break
        coords = data["parent"]
    return info

# endregion

# region SPDX

SPDX_RULES = [
    (re.compile(r"apache.*2|apache-2\.0|licenses/license-2\.0", re.I), "Apache-2.0"),
    (re.compile(r"\bmit\b|opensource\.org/licenses/mit", re.I), "MIT"),
    (re.compile(r"bsd.*3|3-clause|new bsd|bsd-3", re.I), "BSD-3-Clause"),
    (re.compile(r"bsd.*2|2-clause|simplified bsd", re.I), "BSD-2-Clause"),
    (re.compile(r"eclipse public license.*2|epl-2", re.I), "EPL-2.0"),
    (re.compile(r"gnu general public license.*classpath|gpl.*classpath", re.I), "GPL-2.0-with-classpath-exception"),
]


def spdx(name: str, url: str) -> str | None:
    """Map a POM license to an SPDX ID.

    Args:
        name: License name.
        url: License URL.

    Returns:
        SPDX ID, or None when unrecognized.
    """
    for pattern, identifier in SPDX_RULES:
        if pattern.search(name) or pattern.search(url):
            return identifier
    return None

# endregion

# region Manifest


def build_manifest(coords: list[tuple[str, str, str]]) -> dict:
    """Build the manifest document.

    Args:
        coords: Resolved modules.

    Returns:
        Manifest dict (``packages`` sorted by group/artifact, ``texts`` by SPDX ID).

    Raises:
        SystemExit: When a module has no recognizable license or text.
    """
    packages = []
    used: set[str] = set()
    problems = []
    for group, artifact, version in coords:
        info = module_info(group, artifact, version)
        ids = sorted({i for i in (spdx(n, u) for n, u in info["licenses"]) if i})
        if not ids:
            problems.append(f"{group}:{artifact}:{version} licenses={info['licenses']}")
            continue
        used.update(ids)
        url = info["url"] if info["url"] and info["url"].startswith("https://") else None
        packages.append({
            "group": group, "artifact": artifact, "version": version,
            "name": info["name"] or artifact, "licenses": ids, "url": url,
        })
    texts = {}
    for identifier in sorted(used):
        path = TEXTS / f"{identifier}.txt"
        if not path.exists():
            problems.append(f"missing license text {path}")
            continue
        texts[identifier] = path.read_text(encoding="utf-8").replace("\r\n", "\n")
    if problems:
        sys.exit("licenses.py: unresolved licenses:\n  " + "\n  ".join(problems))
    return {"version": 1, "source": "releaseRuntimeClasspath", "packages": packages, "texts": texts}


def serialize(manifest: dict) -> str:
    """Stable JSON text.

    Args:
        manifest: Manifest.

    Returns:
        JSON with sorted keys and a trailing newline.
    """
    return json.dumps(manifest, indent=1, sort_keys=True, ensure_ascii=False) + "\n"


def main(argv: list[str] | None = None) -> int:
    """Entry point.

    Args:
        argv: Arguments.

    Returns:
        Exit code.
    """
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="fail when the committed manifest is stale")
    parser.add_argument("--deps-file", type=Path, help="read a saved dependencies tree instead of running Gradle")
    args = parser.parse_args(argv)
    tree = args.deps_file.read_text(encoding="utf-8") if args.deps_file else gradle_tree()
    text = serialize(build_manifest(parse_tree(tree)))
    if args.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != text:
            print(f"{OUTPUT.relative_to(ROOT)} is stale: run python tools/android/licenses.py", file=sys.stderr)
            return 1
        print("licenses.json is current")
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(text, encoding="utf-8", newline="\n")
    manifest = json.loads(text)
    print(f"wrote {OUTPUT.relative_to(ROOT)}: {len(manifest['packages'])} packages, licenses {sorted(manifest['texts'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# endregion
