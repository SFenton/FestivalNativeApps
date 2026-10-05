#!/usr/bin/env python3
"""Check (and optionally repair) the `.agents` documentation architecture.

Rules enforced (see `.agents/workflow/docs-conventions.md`):

1. Every folder under `.agents` has a `README.md` router, and that router links
   every sibling Markdown file and subfolder. Topic folders directly under
   `pages/` and `controls/` are exempt: their parent README routes to them.
2. Every relative Markdown link in `.agents`, `AGENTS.md` and `README.md`
   resolves to an existing file or folder.
3. Every page in `contracts/product.json` / `contracts/parity-backlog.json` has
   `pages/<id>/spec.md`; every control has `controls/<id>/spec.md`; every
   `spec` path declared in `product.json` exists.
4. No file mixes platforms in its headings: `spec.md` headings name no
   platform; per-platform files (`ios.md`, `ipados.md`, `duo.md`, `macos.md`,
   `android.md`, `windows.md`, or files under a platform folder) name only
   their own platform; any other file names at most one platform family.
5. Every Markdown file starts with `# Title` followed by a `> ` "what / when to
   read" header line.
6. The generated tables in `pages/README.md` and `controls/README.md` match
   the contracts and the files on disk.

Usage::

    python3 .agents/_tools/check_docs.py          # check only; exit 1 on errors
    python3 .agents/_tools/check_docs.py --fix    # regenerate indexes, scaffold
                                                  # missing spec stubs, then check

Standard library only, so it runs in CI without dependencies.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# region Configuration

ROOT = Path(__file__).resolve().parents[2]
AGENTS = ROOT / ".agents"
PRODUCT = ROOT / "contracts/product.json"
BACKLOG = ROOT / "contracts/parity-backlog.json"

#: Parent folders whose child topic folders are routed by the parent README.
TOPIC_PARENTS = ("pages", "controls")
#: Parent folders whose child folders are Copilot/agent skills (`<name>/SKILL.md`, YAML frontmatter).
SKILL_PARENTS = ("skills",)
FRONTMATTER = re.compile(r"\A---\n(.*?)\n---\n", re.S)
#: Per-platform file stems allowed inside a topic folder, in display order.
PLATFORM_STEMS = ("ios", "ipados", "duo", "macos", "android", "windows")
#: Folders never checked for routing.
IGNORED_DIRS = {"__pycache__"}
#: Soft size budget; larger files produce a warning so they get split.
MAX_LINES = 200

#: Platform families detected in headings. "iPhone Duo" is matched first so it
#: counts only as Duo.
FAMILIES: dict[str, re.Pattern[str]] = {
    "duo": re.compile(r"\b(?:iPhone\s+)?Duo\b"),
    "iphone": re.compile(r"\biPhone\b|\biOS\b"),
    "ipad": re.compile(r"\biPad(?:OS)?\b"),
    "mac": re.compile(r"\bmacOS\b|\bAppKit\b"),
    "android": re.compile(r"\bAndroid\b|\bJetpack\b"),
    "windows": re.compile(r"\bWindows\b|\bWinUI\b"),
}
APPLE = frozenset({"iphone", "ipad", "mac", "duo"})
#: File stem -> families it may name in headings.
STEM_SCOPE: dict[str, frozenset[str]] = {
    "ios": frozenset({"iphone"}),
    "iphone": frozenset({"iphone"}),
    "ipados": frozenset({"ipad"}),
    "duo": frozenset({"duo"}),
    "macos": frozenset({"mac"}),
    "android": frozenset({"android"}),
    "windows": frozenset({"windows"}),
}
#: Folder name -> families files inside it may name in headings.
FOLDER_SCOPE: dict[str, frozenset[str]] = {
    "apple": APPLE,
    "android": frozenset({"android"}),
    "windows": frozenset({"windows"}),
}

LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
HEADING = re.compile(r"^#{1,6}\s+(.*)$")
FENCE = re.compile(r"^\s*(```|~~~)")
BEGIN = "<!-- BEGIN GENERATED: check_docs.py --fix -->"
END = "<!-- END GENERATED -->"

# endregion

# region Model


@dataclass
class Report:
    """Collected findings for one run."""

    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    def error(self, path: Path, message: str) -> None:
        """Record a failing finding.

        Args:
            path: File or folder the finding concerns.
            message: Human-readable explanation.
        """
        self.errors.append(f"{_rel(path)}: {message}")

    def warn(self, path: Path, message: str) -> None:
        """Record a non-failing finding.

        Args:
            path: File or folder the finding concerns.
            message: Human-readable explanation.
        """
        self.warnings.append(f"{_rel(path)}: {message}")


def _rel(path: Path) -> str:
    """Return a repository-relative display path.

    Args:
        path: Absolute path inside the repository.

    Returns:
        POSIX path relative to the repository root, or the input as text.
    """
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def load_contracts() -> tuple[list[dict], list[dict], dict[str, dict]]:
    """Read pages, controls and backlog routes from the contracts.

    Returns:
        Product pages, product controls and backlog routes keyed by ID. Pages
        present only in the backlog are appended with minimal fields.
    """
    product = json.loads(PRODUCT.read_text(encoding="utf-8"))
    backlog = json.loads(BACKLOG.read_text(encoding="utf-8"))
    routes = {route["id"]: route for route in backlog.get("routes", [])}
    pages = list(product.get("pages", []))
    known = {page["id"] for page in pages}
    pages += [{"id": rid} for rid in routes if rid not in known]
    return pages, list(product.get("controls", [])), routes


# endregion

# region Markdown helpers


def markdown_files() -> list[Path]:
    """List every Markdown file under `.agents`.

    Returns:
        Sorted Markdown paths, excluding ignored folders.
    """
    return sorted(
        path for path in AGENTS.rglob("*.md")
        if not IGNORED_DIRS.intersection(path.relative_to(AGENTS).parts)
    )


def headings(text: str) -> list[str]:
    """Extract heading text outside fenced code blocks.

    Args:
        text: Markdown source.

    Returns:
        Heading titles without leading hashes.
    """
    found, fenced = [], False
    for line in text.splitlines():
        if FENCE.match(line):
            fenced = not fenced
            continue
        if not fenced and (match := HEADING.match(line)):
            found.append(match.group(1))
    return found


def families_in(line: str) -> set[str]:
    """Detect platform families named in one heading.

    Args:
        line: Heading text.

    Returns:
        Family names; "iPhone Duo" counts only as `duo`.
    """
    found: set[str] = set()
    remaining = line
    for name, pattern in FAMILIES.items():
        if pattern.search(remaining):
            found.add(name)
            remaining = pattern.sub(" ", remaining)
    return found


def scope_for(path: Path) -> frozenset[str] | None:
    """Return the platform families a file may name in headings.

    Args:
        path: Markdown file under `.agents`.

    Returns:
        Allowed families, an empty set for platform-neutral specs, or None for
        a generic file (which may name at most one family).
    """
    if path.name == "spec.md":
        return frozenset()
    if path.stem in STEM_SCOPE:
        return STEM_SCOPE[path.stem]
    for part in reversed(path.relative_to(AGENTS).parts[:-1]):
        if part in FOLDER_SCOPE:
            return FOLDER_SCOPE[part]
    return None


# endregion

# region Checks


def check_headers(report: Report) -> None:
    """Require `# Title` then a `> ` what/when line in every file.

    Args:
        report: Findings sink.
    """
    for path in markdown_files():
        text = path.read_text(encoding="utf-8")
        if path.name == "SKILL.md":
            text = FRONTMATTER.sub("", text, count=1)
        lines = [line for line in text.splitlines() if line.strip()]
        if not lines or not lines[0].startswith("# "):
            report.error(path, "first line must be a `# Title` heading")
        elif len(lines) < 2 or not lines[1].startswith("> "):
            report.error(path, "second non-empty line must be a `> ` what/when-to-read header")
        if len(lines) > MAX_LINES:
            report.warn(path, f"{len(lines)} non-empty lines; consider splitting (budget {MAX_LINES})")


def check_links(report: Report) -> None:
    """Resolve every relative Markdown link.

    Args:
        report: Findings sink.
    """
    for path in [*markdown_files(), ROOT / "AGENTS.md", ROOT / "README.md"]:
        if not path.is_file():
            continue
        fenced = False
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if FENCE.match(line):
                fenced = not fenced
            if fenced:
                continue
            for target in LINK.findall(line):
                if re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("#"):
                    continue
                resolved = (path.parent / target.split("#", 1)[0]).resolve()
                if not resolved.exists():
                    report.error(path, f"line {number}: broken link `{target}`")


def check_platform_mixing(report: Report) -> None:
    """Flag files whose headings name platforms outside their scope.

    Args:
        report: Findings sink.
    """
    for path in markdown_files():
        if path.name == "README.md":
            continue
        scope = scope_for(path)
        named: set[str] = set()
        for title in headings(path.read_text(encoding="utf-8")):
            named |= families_in(title)
        if scope is None:
            if len(named) > 1:
                report.error(path, f"headings mix platforms {sorted(named)}; split per platform")
        elif extra := named - scope:
            kind = "platform-neutral spec" if not scope else f"scoped to {sorted(scope)}"
            report.error(path, f"{kind} but headings name {sorted(extra)}; move to a platform file")


def _linked_targets(readme: Path) -> set[Path]:
    """Return resolved local link targets in a router README.

    Args:
        readme: Router file.

    Returns:
        Resolved paths, with folder links also recorded as their README.
    """
    targets: set[Path] = set()
    for target in LINK.findall(readme.read_text(encoding="utf-8")):
        if re.match(r"^[a-z][a-z0-9+.-]*:", target) or target.startswith("#"):
            continue
        resolved = (readme.parent / target.split("#", 1)[0]).resolve()
        targets.add(resolved)
        if resolved.is_dir():
            targets.add(resolved / "README.md")
    return targets


def check_routers(report: Report) -> None:
    """Require a README router per folder that links all its children.

    Args:
        report: Findings sink.
    """
    folders = [AGENTS, *sorted(p for p in AGENTS.rglob("*") if p.is_dir())]
    for folder in folders:
        rel = folder.relative_to(AGENTS).parts
        if IGNORED_DIRS.intersection(rel):
            continue
        if len(rel) == 2 and rel[0] in TOPIC_PARENTS + SKILL_PARENTS:
            continue
        readme = folder / "README.md"
        if not readme.is_file():
            report.error(folder, "folder needs a README.md router")
            continue
        linked = _linked_targets(readme)
        for child in sorted(folder.iterdir()):
            if child.name in IGNORED_DIRS or child == readme:
                continue
            if child.is_dir() and len(rel) == 1 and rel[0] in TOPIC_PARENTS:
                wanted = child / "spec.md"
            elif child.is_dir() and len(rel) == 1 and rel[0] in SKILL_PARENTS:
                wanted = child / "SKILL.md"
            elif child.is_dir():
                wanted = child / "README.md"
            elif child.suffix == ".md":
                wanted = child
            else:
                continue
            if wanted.resolve() not in linked and child.resolve() not in linked:
                report.error(readme, f"router does not link `{child.name}`")


def check_skills(report: Report) -> None:
    """Require `skills/<name>/SKILL.md` with `name` (= folder) and `description` frontmatter.

    Args:
        report: Findings sink.
    """
    for parent in SKILL_PARENTS:
        base = AGENTS / parent
        if not base.is_dir():
            continue
        for folder in sorted(p for p in base.iterdir() if p.is_dir() and p.name not in IGNORED_DIRS):
            skill = folder / "SKILL.md"
            if not skill.is_file():
                report.error(folder, "skill folder needs a SKILL.md")
                continue
            match = FRONTMATTER.match(skill.read_text(encoding="utf-8"))
            meta = dict(line.split(":", 1) for line in (match.group(1).splitlines() if match else [])
                        if ":" in line)
            if meta.get("name", "").strip() != folder.name:
                report.error(skill, f"frontmatter `name` must be `{folder.name}`")
            if not meta.get("description", "").strip():
                report.error(skill, "frontmatter needs a `description` (when to use the skill)")
        for stray in sorted(base.glob("*.md")):
            if stray.name != "README.md":
                report.error(stray, "skills live in `<name>/SKILL.md` folders so agents load them")


def check_contracts(report: Report) -> None:
    """Require specs for every contract page/control and valid `spec` paths.

    Args:
        report: Findings sink.
    """
    pages, controls, _ = load_contracts()
    for kind, items in (("pages", pages), ("controls", controls)):
        ids = {item["id"] for item in items}
        for item in items:
            spec = AGENTS / kind / item["id"] / "spec.md"
            if not spec.is_file():
                report.error(spec, f"missing spec for {kind[:-1]} `{item['id']}` (run --fix to scaffold)")
            declared = item.get("spec")
            if declared and not (ROOT / declared).is_file():
                report.error(PRODUCT, f"{item['id']}: declared spec `{declared}` does not exist")
        for folder in sorted(p for p in (AGENTS / kind).iterdir() if p.is_dir()):
            if folder.name not in ids:
                report.warn(folder, f"topic is not in contracts; add it to product.json or rename")
            for doc in folder.glob("*.md"):
                if doc.stem != "spec" and doc.stem not in PLATFORM_STEMS:
                    report.warn(doc, f"unexpected file name; use spec.md or one of {PLATFORM_STEMS}")


# endregion

# region Generation


def _platform_links(folder: Path) -> str:
    """Render links to the per-platform files present in a topic folder.

    Args:
        folder: `pages/<id>` or `controls/<id>`.

    Returns:
        Middle-dot separated links, or an em dash when there are none.
    """
    links = [f"[{stem}]({folder.name}/{stem}.md)" for stem in PLATFORM_STEMS
             if (folder / f"{stem}.md").is_file()]
    return " · ".join(links) or "—"


def render_pages_index() -> str:
    """Build the generated pages table.

    Returns:
        Markdown table rows, one per contract page plus any extra topic folders.
    """
    pages, _, routes = load_contracts()
    rows = ["| Page | Route | Guard | Apple (backlog) | Spec | Platform files |",
            "|---|---|---|---|---|---|"]
    seen = set()
    for page in pages:
        pid = page["id"]
        seen.add(pid)
        folder = AGENTS / "pages" / pid
        stub = " (stub)" if _is_stub(folder / "spec.md") else ""
        rows.append(
            f"| {pid} | `{page.get('path', '?')}` | {page.get('guard', '?')} | "
            f"{routes.get(pid, {}).get('apple', '?')} | [spec{stub}]({pid}/spec.md) | "
            f"{_platform_links(folder)} |"
        )
    for folder in sorted(p for p in (AGENTS / "pages").iterdir() if p.is_dir() and p.name not in seen):
        rows.append(f"| {folder.name} | ? | ? | ? | [spec]({folder.name}/spec.md) | {_platform_links(folder)} |")
    return "\n".join(rows)


def render_controls_index() -> str:
    """Build the generated controls table.

    Returns:
        Markdown table rows, one per contract control plus any extra topic folders.
    """
    _, controls, _ = load_contracts()
    rows = ["| Control | Test ID | States | Status | Spec | Platform files |",
            "|---|---|---|---|---|---|"]
    seen = set()
    for control in controls:
        cid = control["id"]
        seen.add(cid)
        folder = AGENTS / "controls" / cid
        rows.append(
            f"| {cid} | `{control.get('testId', '?')}` | {len(control.get('states', []))} | "
            f"{control.get('status', '?')} | [spec]({cid}/spec.md) | {_platform_links(folder)} |"
        )
    for folder in sorted(p for p in (AGENTS / "controls").iterdir() if p.is_dir() and p.name not in seen):
        rows.append(f"| {folder.name} | ? | ? | not in contract | [spec]({folder.name}/spec.md) | "
                    f"{_platform_links(folder)} |")
    return "\n".join(rows)


def _is_stub(spec: Path) -> bool:
    """Report whether a spec is still a generated placeholder.

    Args:
        spec: Candidate spec path.

    Returns:
        True when the file carries the scaffold marker.
    """
    return spec.is_file() and "<!-- stub -->" in spec.read_text(encoding="utf-8")


def _replace_block(path: Path, body: str) -> str | None:
    """Return file text with its generated block replaced.

    Args:
        path: README that contains the BEGIN/END markers.
        body: New generated content.

    Returns:
        Updated text, or None if the markers are missing.
    """
    text = path.read_text(encoding="utf-8")
    if BEGIN not in text or END not in text:
        return None
    head, rest = text.split(BEGIN, 1)
    _, tail = rest.split(END, 1)
    return f"{head}{BEGIN}\n{body}\n{END}{tail}"


def check_indexes(report: Report, fix: bool) -> None:
    """Verify (or rewrite) the generated router tables.

    Args:
        report: Findings sink.
        fix: Rewrite stale blocks instead of reporting them.
    """
    for path, body in ((AGENTS / "pages/README.md", render_pages_index()),
                       (AGENTS / "controls/README.md", render_controls_index())):
        if not path.is_file():
            continue
        updated = _replace_block(path, body)
        if updated is None:
            report.error(path, "missing generated-table markers")
        elif updated != path.read_text(encoding="utf-8"):
            if fix:
                path.write_text(updated, encoding="utf-8")
            else:
                report.error(path, "generated table is stale (run --fix)")


def scaffold_specs() -> list[Path]:
    """Create placeholder specs for contract pages/controls that lack one.

    Returns:
        Paths that were created.
    """
    pages, controls, routes = load_contracts()
    created = []
    for page in pages:
        spec = AGENTS / "pages" / page["id"] / "spec.md"
        if spec.exists():
            continue
        route = routes.get(page["id"], {})
        source = f"`{page['source']}` (route declaration)" if page.get("source") else "TODO"
        spec.parent.mkdir(parents=True, exist_ok=True)
        spec.write_text(
            f"# {page['id']} (`{page.get('path', '?')}`) — spec stub\n\n"
            f"> **What:** generated placeholder; this page has not been investigated. "
            f"**Read when:** starting work on it — replace this stub with real web behavior first "
            f"([port-page skill](../../skills/port-page/SKILL.md)).\n\n<!-- stub -->\n\n"
            f"- Guard: `{page.get('guard', '?')}` · Web source: {source}\n"
            f"- Backlog: route `{page['id']}` — Apple `{route.get('apple', '?')}`, epics "
            f"{', '.join(f'`{e}`' for e in route.get('epics', [])) or '—'}; gap text via "
            f"`python3 tools/parity_backlog.py --list`\n",
            encoding="utf-8",
        )
        created.append(spec)
    for control in controls:
        spec = AGENTS / "controls" / control["id"] / "spec.md"
        if spec.exists():
            continue
        spec.parent.mkdir(parents=True, exist_ok=True)
        spec.write_text(
            f"# {control['id']} (`{control.get('testId', '?')}`) — spec stub\n\n"
            f"> **What:** generated placeholder. **Read when:** starting work on this control.\n\n"
            f"<!-- stub -->\n\n- Web source: `{control.get('source', 'TODO')}`\n"
            f"- States: {', '.join(control.get('states', []))}\n",
            encoding="utf-8",
        )
        created.append(spec)
    return created


# endregion

# region CLI


def run(fix: bool = False) -> Report:
    """Run every check, optionally repairing generated content first.

    Args:
        fix: Scaffold missing specs and rewrite generated tables.

    Returns:
        The collected report.
    """
    report = Report()
    if fix:
        for path in scaffold_specs():
            print(f"scaffolded {_rel(path)}")
    check_indexes(report, fix)
    check_headers(report)
    check_links(report)
    check_platform_mixing(report)
    check_routers(report)
    check_skills(report)
    check_contracts(report)
    return report


def main(argv: list[str] | None = None) -> int:
    """Command-line entry point.

    Args:
        argv: Arguments excluding the program name.

    Returns:
        Zero when there are no errors.
    """
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--fix", action="store_true", help="scaffold specs and regenerate indexes")
    parser.add_argument("--quiet", action="store_true", help="hide warnings")
    args = parser.parse_args(argv)
    report = run(fix=args.fix)
    if not args.quiet:
        for line in report.warnings:
            print(f"warning: {line}")
    for line in report.errors:
        print(f"error: {line}")
    files = len(markdown_files())
    print(f"check_docs: {files} files, {len(report.errors)} errors, {len(report.warnings)} warnings")
    return 1 if report.errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

# endregion
