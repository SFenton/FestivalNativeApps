#!/usr/bin/env python3
"""Check the cross-platform pattern registry and enforce its guard rules.

The registry (`contracts/patterns.json`, prose in `.agents/patterns/<id>.md`) names, per
behavior pattern, the canonical component on each platform and regex guards that keep new
code from growing a parallel implementation outside it.

Commands::

    python3 tools/pattern_guard.py                 # check (default): registry + guards; exit 1 on errors
    python3 tools/pattern_guard.py index           # compact Markdown index (for prompts and agents)
    python3 tools/pattern_guard.py index --json    # the same as JSON
    python3 tools/pattern_guard.py which PATH...   # patterns that own or guard each path
    python3 tools/pattern_guard.py changed --base origin/master [--head HEAD] [--strict]
                                                   # patterns touched by a diff and whether their
                                                   # doc or contract was updated

Standard library only, so it runs in CI and on every agent host.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable

# region Configuration

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "contracts" / "patterns.json"
PRODUCT = ROOT / "contracts" / "product.json"
PLATFORMS = ("apple", "android", "windows")
STATUSES = frozenset({"current", "proposed", "superseded"})
ID = re.compile(r"^[a-z][a-z0-9-]*$")
#: Lines that are only comments are never guard violations (docs may name banned APIs).
COMMENT = re.compile(r"^\s*(//|/\*|\*|#|<!--)")
#: Where the web source of truth may live on an agent host (first existing wins).
WEB_CANDIDATES = (
    "~/fst-agents/repos/FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/src",
    "~/repos/FortniteFestivalLeaderboardScraper/FortniteFestivalWeb/src",
)
SKIP_DIRS = frozenset({".git", "build", ".build", "DerivedData", "node_modules", "bin", "obj", ".gradle"})

# endregion

# region Model


@dataclass
class Report:
    """Findings from one check run."""

    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def load(root: Path = ROOT) -> dict[str, Any]:
    """Read the registry.

    Args:
        root: Repository root.

    Returns:
        The parsed `contracts/patterns.json`.
    """
    return json.loads((root / "contracts" / "patterns.json").read_text(encoding="utf-8"))


@lru_cache(maxsize=None)
def glob_regex(pattern: str) -> re.Pattern[str]:
    """Translate a repo glob (`**`, `*`, `?`) to an anchored regex over `/` paths.

    Args:
        pattern: Glob relative to the repository root.

    Returns:
        Compiled regex matching whole relative paths.
    """
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("**", i):
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile("^" + "".join(out) + "$")


def matches(path: str, patterns: Iterable[str]) -> bool:
    """Whether `path` matches any glob in `patterns`."""
    return any(glob_regex(p).match(path) for p in patterns)


def web_root(explicit: str | None = None) -> Path | None:
    """The web `src` folder on this host, or None when it isn't checked out."""
    for candidate in ([explicit] if explicit else []) + [os.environ.get("FST_WEB_SRC", "")] + list(WEB_CANDIDATES):
        if candidate and (path := Path(candidate).expanduser()).is_dir():
            return path
    return None


def source_files(root: Path, glob: str) -> list[str]:
    """Repo-relative files matching `glob`, skipping build output.

    Args:
        root: Repository root.
        glob: Repo glob, e.g. `apple/Sources/**/*.swift`.

    Returns:
        Sorted relative paths.
    """
    prefix = glob.split("*", 1)[0].rsplit("/", 1)[0] if "*" in glob else glob
    base = root / prefix
    if base.is_file():
        return [prefix] if glob_regex(glob).match(prefix) else []
    found = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            rel = os.path.relpath(os.path.join(dirpath, name), root).replace(os.sep, "/")
            if glob_regex(glob).match(rel):
                found.append(rel)
    return sorted(found)

# endregion

# region Check


def _validate_entry(pattern: dict[str, Any], root: Path, web: Path | None, ids: set[str],
                    product: dict[str, set[str]], report: Report) -> None:
    pid = pattern.get("id", "?")
    where = f"pattern {pid}"
    for key in ("id", "title", "status", "doc", "summary", "canonical"):
        if not pattern.get(key):
            report.errors.append(f"{where}: missing `{key}`")
    if not ID.match(str(pid)):
        report.errors.append(f"{where}: id must be kebab-case")
    if pattern.get("status") not in STATUSES:
        report.errors.append(f"{where}: status must be one of {sorted(STATUSES)}")
    doc = root / str(pattern.get("doc", ""))
    doc_text = doc.read_text(encoding="utf-8") if doc.is_file() else ""
    if not doc_text:
        report.errors.append(f"{where}: doc `{pattern.get('doc')}` does not exist")
    elif not re.search(r"^(?:-|\d+\.) \*\*R1\.", doc_text, re.M):
        report.errors.append(f"{where}: doc needs a numbered Rules block starting with `- **R1.`")
    canonical = pattern.get("canonical") or {}
    for platform in canonical:
        if platform not in PLATFORMS:
            report.errors.append(f"{where}: unknown platform `{platform}` in canonical")
    for platform in PLATFORMS:
        for ref in canonical.get(platform) or []:
            path = root / ref.get("path", "")
            if not path.is_file():
                report.errors.append(f"{where}: canonical {platform} path `{ref.get('path')}` does not exist")
            elif ref.get("symbol") and not re.search(rf"\b{re.escape(ref['symbol'])}\b",
                                                      path.read_text(encoding="utf-8", errors="replace")):
                report.errors.append(f"{where}: symbol `{ref['symbol']}` not found in `{ref['path']}`")
    if web is not None:
        for ref in pattern.get("web") or []:
            path = web / ref.get("path", "")
            if not path.is_file():
                report.errors.append(f"{where}: web path `{ref.get('path')}` does not exist under {web}")
            elif ref.get("symbol") and ref["symbol"] not in path.read_text(encoding="utf-8", errors="replace"):
                report.errors.append(f"{where}: web symbol `{ref['symbol']}` not found in `{ref['path']}`")
    related = pattern.get("related") or {}
    for other in related.get("patterns") or []:
        if other not in ids:
            report.errors.append(f"{where}: related pattern `{other}` is not in the registry")
    for kind in ("pages", "controls"):
        for item in related.get(kind) or []:
            if item not in product[kind]:
                report.errors.append(f"{where}: related {kind[:-1]} `{item}` is not in contracts/product.json")
    for other in (pattern.get("supersedes") or []) + ([pattern["supersededBy"]] if pattern.get("supersededBy") else []):
        if other not in ids:
            report.errors.append(f"{where}: supersession target `{other}` is not in the registry")
    for guard in pattern.get("guards") or []:
        gid = f"{pid}/{guard.get('id', '?')}"
        if doc_text and gid not in doc_text:
            report.errors.append(f"{where}: doc must name guard `{gid}` under Guards")


def run_guards(pattern: dict[str, Any], root: Path, report: Report,
               only: set[str] | None = None) -> list[tuple[str, str, int, str]]:
    """Apply a pattern's guards; violations outside `allow` and `debt` become errors.

    Args:
        pattern: One registry entry.
        root: Repository root.
        report: Findings sink.
        only: When given, scan only these repo-relative paths.

    Returns:
        Every match as (guard id, path, line number, kind) where kind is error/debt.
    """
    hits: list[tuple[str, str, int, str]] = []
    for guard in pattern.get("guards") or []:
        gid = f"{pattern['id']}/{guard.get('id', '?')}"
        try:
            regex = re.compile(guard["regex"])
        except (KeyError, re.error) as exc:
            report.errors.append(f"guard {gid}: invalid regex ({exc})")
            continue
        allow, debt = guard.get("allow") or [], guard.get("debt") or []
        seen_debt: set[str] = set()
        files = source_files(root, guard.get("glob", ""))
        if only is not None:
            files = [f for f in files if f in only]
        for rel in files:
            if matches(rel, allow):
                continue
            try:
                lines = (root / rel).read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError:
                continue
            for number, line in enumerate(lines, 1):
                if COMMENT.match(line) or not regex.search(line):
                    continue
                if rel in debt:
                    seen_debt.add(rel)
                    hits.append((gid, rel, number, "debt"))
                else:
                    hits.append((gid, rel, number, "error"))
                    report.errors.append(f"{rel}:{number}: {gid}: {guard.get('message', 'pattern guard')}")
        if only is None:
            for rel in debt:
                if rel not in seen_debt:
                    report.errors.append(f"guard {gid}: debt entry `{rel}` no longer violates; remove it from "
                                         "`debt` and the doc's Known debt table")
        if seen_debt:
            report.warnings.append(f"guard {gid}: known debt in {len(seen_debt)} file(s)")
    return hits


def check(root: Path = ROOT, web: Path | None = None) -> Report:
    """Validate the registry and run every guard.

    Args:
        root: Repository root.
        web: Web `src` folder, or None to skip web path checks.

    Returns:
        The findings.
    """
    report = Report()
    try:
        data = load(root)
    except (OSError, ValueError) as exc:
        report.errors.append(f"contracts/patterns.json: {exc}")
        return report
    patterns = data.get("patterns") or []
    ids = [p.get("id") for p in patterns]
    for dup in sorted({i for i in ids if ids.count(i) > 1}):
        report.errors.append(f"duplicate pattern id `{dup}`")
    try:
        manifest = json.loads((root / "contracts" / "product.json").read_text(encoding="utf-8"))
        product = {k: {item["id"] for item in manifest.get(k, [])} for k in ("pages", "controls")}
    except (OSError, ValueError, KeyError):
        product = {"pages": set(), "controls": set()}
    readme = root / ".agents" / "patterns" / "README.md"
    router = readme.read_text(encoding="utf-8") if readme.is_file() else ""
    for pattern in patterns:
        _validate_entry(pattern, root, web, set(ids), product, report)
        if router and f"({pattern.get('id')}.md)" not in router:
            report.errors.append(f"pattern {pattern.get('id')}: not listed in .agents/patterns/README.md")
        run_guards(pattern, root, report)
    if web is None:
        report.warnings.append("web source not found (set FST_WEB_SRC); web paths were not checked")
    return report

# endregion

# region Index / which / changed


def index(data: dict[str, Any], as_json: bool = False) -> str:
    """Compact index of current patterns for prompts.

    Args:
        data: Registry.
        as_json: Emit JSON instead of Markdown.

    Returns:
        The index text.
    """
    rows = []
    for p in data.get("patterns") or []:
        if p.get("status") == "superseded":
            continue
        canon = {pl: [r["path"].rsplit("/", 1)[-1] + (f" `{r['symbol']}`" if r.get("symbol") else "")
                      for r in (p.get("canonical") or {}).get(pl) or []] for pl in PLATFORMS}
        rows.append({"id": p["id"], "title": p.get("title", ""), "summary": p.get("summary", ""),
                     "doc": p.get("doc", ""), "keywords": p.get("keywords", []), "canonical": canon})
    if as_json:
        return json.dumps(rows, indent=2)
    out = ["| Pattern | Summary | Apple | Android | Windows |", "|---|---|---|---|---|"]
    for r in rows:
        out.append(f"| [{r['id']}]({r['doc']}) | {r['summary']} | "
                   + " | ".join(", ".join(r["canonical"][pl]) or "—" for pl in PLATFORMS) + " |")
    return "\n".join(out)


def owners(data: dict[str, Any], path: str) -> list[tuple[str, str]]:
    """Patterns that own (canonical) or guard `path`.

    Returns:
        (pattern id, role) pairs, role is `canonical` or `guarded`.
    """
    found = []
    for p in data.get("patterns") or []:
        canon = [r["path"] for pl in PLATFORMS for r in (p.get("canonical") or {}).get(pl) or []]
        if path in canon:
            found.append((p["id"], "canonical"))
        elif any(glob_regex(g.get("glob", "")).match(path) for g in p.get("guards") or []):
            found.append((p["id"], "guarded"))
    return found


def changed_report(data: dict[str, Any], files: list[str]) -> tuple[str, bool]:
    """Which patterns a change touches and whether their doc/contract moved with it.

    Args:
        data: Registry.
        files: Changed repo-relative paths.

    Returns:
        (Markdown summary, True when a canonical file changed without its pattern doc or contract).
    """
    touched: dict[str, list[str]] = {}
    for f in files:
        for pid, role in owners(data, f):
            if role == "canonical":
                touched.setdefault(pid, []).append(f)
    docs_changed = set(files)
    lines, missing = [], False
    for p in data.get("patterns") or []:
        if p["id"] not in touched:
            continue
        updated = p.get("doc") in docs_changed or "contracts/patterns.json" in docs_changed
        missing |= not updated
        lines.append(f"- `{p['id']}` ({p.get('doc')}): canonical files changed: "
                     + ", ".join(f"`{f}`" for f in touched[p["id"]])
                     + ("; pattern doc/contract updated" if updated
                        else "; **pattern doc/contract not updated**: confirm the rules still hold or update them"))
    if not lines:
        return "No canonical pattern components changed.", False
    return "Patterns touched by this change:\n" + "\n".join(lines), missing


def diff_files(base: str, head: str) -> list[str]:
    """Changed paths between `base` and `head` (merge-base diff)."""
    out = subprocess.run(["git", "diff", "--name-only", f"{base}...{head}"], cwd=ROOT, capture_output=True,
                         text=True, check=True)
    return [line.strip() for line in out.stdout.splitlines() if line.strip()]

# endregion

# region CLI


def main(argv: list[str] | None = None) -> int:
    """Command-line entry point."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd")
    p_check = sub.add_parser("check", help="validate the registry and run guards (default)")
    p_check.add_argument("--web", help="web src folder (default: FST_WEB_SRC or the agent clone)")
    p_index = sub.add_parser("index", help="print the pattern index")
    p_index.add_argument("--json", action="store_true")
    p_which = sub.add_parser("which", help="patterns owning or guarding paths")
    p_which.add_argument("paths", nargs="+")
    p_changed = sub.add_parser("changed", help="patterns touched by a diff")
    p_changed.add_argument("--base", default="origin/master")
    p_changed.add_argument("--head", default="HEAD")
    p_changed.add_argument("--files", nargs="*", help="explicit changed paths instead of git diff")
    p_changed.add_argument("--strict", action="store_true", help="exit 1 when a canonical file changed alone")
    args = parser.parse_args(argv)

    if args.cmd in (None, "check"):
        report = check(ROOT, web_root(getattr(args, "web", None)))
        for w in report.warnings:
            print(f"warning: {w}")
        for e in report.errors:
            print(f"error: {e}")
        print(f"pattern_guard: {len(report.errors)} error(s), {len(report.warnings)} warning(s)")
        return 1 if report.errors else 0
    data = load()
    if args.cmd == "index":
        print(index(data, args.json))
        return 0
    if args.cmd == "which":
        for path in args.paths:
            rel = os.path.relpath(Path(path).resolve(), ROOT).replace(os.sep, "/") if Path(path).exists() else path
            found = owners(data, rel)
            print(f"{rel}: " + (", ".join(f"{pid} ({role})" for pid, role in found) or "no pattern"))
        return 0
    files = args.files if args.files is not None else diff_files(args.base, args.head)
    text, missing = changed_report(data, files)
    print(text)
    return 1 if (missing and args.strict) else 0


if __name__ == "__main__":
    sys.exit(main())

# endregion
