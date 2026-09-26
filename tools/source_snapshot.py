#!/usr/bin/env python3
"""Pin reviewed website files by commit, worktree status and content hash."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "contracts/source-snapshot.json"
BACKLOG = ROOT / "contracts/parity-backlog.json"
SOURCE_PATH = (
    r"(?:FortniteFestivalWeb|FSTService|packages/(?:core|theme))"
    r"(?:/[A-Za-z0-9_][A-Za-z0-9_.-]*)+\.(?:tsx|ts|cs)"
)
SOURCE_REF = re.compile(rf"^{SOURCE_PATH}:[1-9]\d*$")
MARKDOWN_SOURCE_REF = re.compile(
    rf"(?P<path>{SOURCE_PATH}):"
    r"(?P<ranges>[1-9]\d*(?:-[1-9]\d*)?(?:,\s*[1-9]\d*(?:-[1-9]\d*)?)*)"
)
SOURCES = (
    "FSTService/Api/ApiPublicationClassification.cs",
    "FSTService/Api/LeaderboardEndpoints.cs",
    "FSTService/Api/SongsCacheService.cs",
    "packages/core/src/api/serverTypes.ts",
    "packages/theme/src/colors.ts",
    "FortniteFestivalWeb/src/App.tsx",
    "FortniteFestivalWeb/src/api/client.ts",
    "FortniteFestivalWeb/src/api/publication.ts",
    "FortniteFestivalWeb/src/api/songsCache.ts",
    "FortniteFestivalWeb/src/components/shell/AnimatedBackground.tsx",
    "FortniteFestivalWeb/src/components/shell/mobile/BottomNav.tsx",
    "FortniteFestivalWeb/src/components/songs/metadata/DifficultyBars.tsx",
    "FortniteFestivalWeb/src/contexts/SettingsContext.tsx",
    "FortniteFestivalWeb/src/hooks/data/useFilteredSongs.ts",
    "FortniteFestivalWeb/src/hooks/ui/useProbableDuoDisplayMode.ts",
    "FortniteFestivalWeb/src/pages/leaderboard/global/LeaderboardPage.tsx",
    "FortniteFestivalWeb/src/pages/settings/SettingsPage.tsx",
    "FortniteFestivalWeb/src/pages/songinfo/SongDetailPage.tsx",
    "FortniteFestivalWeb/src/pages/songinfo/components/path/PathsModal.tsx",
    "FortniteFestivalWeb/src/pages/songs/SongsPage.tsx",
    "FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx",
    "FortniteFestivalWeb/src/pages/songs/modals/FilterModal.tsx",
    "FortniteFestivalWeb/src/pages/songs/modals/SortModal.tsx",
    "FortniteFestivalWeb/src/pages/songs/songQuickLinks.ts",
    "FortniteFestivalWeb/src/utils/probableDuoDisplay.ts",
    "FortniteFestivalWeb/src/utils/songSearch.ts",
    "FortniteFestivalWeb/src/utils/songSort.ts",
)

def markdown_source_citations(markdown_root: Path) -> list[tuple[str, str, int, int]]:
    """Extract every fully qualified source range from agent guidance.

    Args:
        markdown_root: Existing directory containing agent specifications.

    Returns:
        Cited location, relative source path and each inclusive line range.

    Raises:
        ValueError: If guidance is missing or a Markdown file is a symlink.
    """
    if not markdown_root.is_dir():
        raise ValueError(f"Agent guidance directory is missing: {markdown_root}")
    citations = []
    for doc in sorted(markdown_root.rglob("*.md")):
        if doc.is_symlink() or not doc.is_file():
            raise ValueError(f"Agent guidance file is unavailable or a symlink: {doc}")
        for match in MARKDOWN_SOURCE_REF.finditer(doc.read_text(encoding="utf-8")):
            for line_range in match.group("ranges").split(","):
                bounds = line_range.strip().split("-", 1)
                citations.append((
                    f"{doc.relative_to(markdown_root)}: {match.group('path')}:{line_range.strip()}",
                    match.group("path"), int(bounds[0]), int(bounds[-1]),
                ))
    return citations


def tracked_source_paths(
    backlog: dict, base: tuple[str, ...] = SOURCES, markdown_root: Path | None = None
) -> tuple[str, ...]:
    """Pin existing inputs and cited React/service/shared-package sources.

    Args:
        backlog: Validated versioned parity plan with sourceRefs on every epic.
        base: Previously pinned source files to retain across plan revisions.
        markdown_root: Optional agent specifications with additional source citations.

    Returns:
        Sorted, de-duplicated source file paths without embedded code.

    Raises:
        ValueError: If a feature citation cannot identify a source file and line.
    """
    epics = backlog.get("epics")
    if not isinstance(epics, list) or not epics:
        raise ValueError("Parity backlog needs cited feature epics")
    paths = set(base)
    for epic in epics:
        refs = epic.get("sourceRefs") if isinstance(epic, dict) else None
        if not isinstance(refs, list) or not refs:
            raise ValueError("Parity epic has no source references")
        for ref in refs:
            if not isinstance(ref, str) or not SOURCE_REF.fullmatch(ref):
                raise ValueError(f"Invalid parity source reference: {ref!r}")
            paths.add(ref.rsplit(":", 1)[0])
    if markdown_root is not None:
        paths.update(path for _, path, _, _ in markdown_source_citations(markdown_root))
    return tuple(sorted(paths))


def validate_citation_lines(source: Path, backlog: dict, markdown_root: Path) -> None:
    """Reject out-of-bounds source references in the backlog and agent guidance.

    Args:
        source: Read-only local checkout for source line counts.
        backlog: Source-backed feature epics with explicit path:line citations.
        markdown_root: Existing directory of agent specs to check for full-path ranges.

    Raises:
        ValueError: For a missing file, reversed range or nonexistent cited line.
    """
    citations: list[tuple[str, str, int, int]] = []
    for epic in backlog["epics"]:
        for ref in epic["sourceRefs"]:
            path, line = ref.rsplit(":", 1)
            citations.append((ref, path, int(line), int(line)))
    citations.extend(markdown_source_citations(markdown_root))
    line_counts: dict[str, int] = {}
    source_root = source.resolve()
    for citation, path, first, last in citations:
        if last < first:
            raise ValueError(f"{citation}: source range ends before it starts")
        if path not in line_counts:
            content = source / path
            if not content.is_file() or not content.resolve().is_relative_to(source_root):
                raise ValueError(f"{citation}: cited source missing or outside checkout")
            line_counts[path] = len(content.read_bytes().splitlines())
        if last > line_counts[path]:
            raise ValueError(
                f"{citation}: source line out of range (1..{line_counts[path]})"
            )


def _git(source: Path, *args: str) -> subprocess.CompletedProcess[str]:
    """Run a read-only git query scoped to the existing source checkout.

    Args:
        source: Website repository root.
        args: Exact git subcommand and options, never shell-expanded.

    Returns:
        Completed process with stdout and stderr captured.
    """
    return subprocess.run(
        ["git", "-C", str(source), *args],
        check=False, capture_output=True, text=True,
    )


def source_status(source: Path, path: str) -> str:
    """Record whether reviewed bytes came from HEAD or an uncommitted change.

    Args:
        source: Existing source repository root.
        path: Relative file name within that repository.

    Returns:
        `committed`, `modified`, or `untracked`; no silent unknown fallback.

    Raises:
        ValueError: When a git query fails outside its expected status range.
    """
    tracked = _git(source, "ls-files", "--error-unmatch", "--", path)
    if tracked.returncode == 1:
        return "untracked"
    if tracked.returncode != 0:
        raise ValueError(f"{path}: cannot check git tracking: {tracked.stderr.strip()}")
    for args in (("diff", "--quiet", "--", path), ("diff", "--cached", "--quiet", "--", path)):
        difference = _git(source, *args)
        if difference.returncode == 1:
            return "modified"
        if difference.returncode != 0:
            raise ValueError(f"{path}: cannot check git diff: {difference.stderr.strip()}")
    return "committed"


def create_snapshot(source: Path, paths: tuple[str, ...] | None = None) -> dict:
    """Hash every known parity input and attach its true source provenance.

    Args:
        source: Source repository with the reviewed, possibly dirty worktree.
        paths: Explicit files to pin, or baseline plus every parity-epic citation.

    Returns:
        Machine-checkable metadata; never copies source code or credentials.

    Raises:
        ValueError: If the repo or any referenced source is unavailable.
    """
    revision = _git(source, "rev-parse", "HEAD")
    if revision.returncode != 0 or len(revision.stdout.strip()) != 40:
        raise ValueError(f"{source}: cannot read source HEAD")
    if paths is None:
        backlog = json.loads(BACKLOG.read_text(encoding="utf-8"))
        paths = tracked_source_paths(backlog, markdown_root=ROOT / ".agents")
        validate_citation_lines(source, backlog, ROOT / ".agents")
    files = {}
    for path in paths:
        content = source / path
        if not content.is_file() or not content.resolve().is_relative_to(source.resolve()):
            raise ValueError(f"{path}: reviewed source file missing or outside checkout")
        files[path] = {
            "sha256": hashlib.sha256(content.read_bytes()).hexdigest(),
            "status": source_status(source, path),
        }
    return {
        "repository": "SFenton/FortniteFestivalLeaderboardScraper",
        "baseCommit": revision.stdout.strip(),
        "files": files,
    }


def main(argv: list[str] | None = None) -> int:
    """Write a scoped snapshot or verify existing evidence has not drifted.

    Args:
        argv: CLI options including an explicitly supplied local source checkout.

    Returns:
        Zero for a matching snapshot; nonzero for missing/drifting evidence.
    """
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--write", action="store_true", help="Refresh pinned evidence")
    args = parser.parse_args(argv)
    try:
        snapshot = create_snapshot(args.source)
        serialized = json.dumps(snapshot, indent=2, sort_keys=True) + "\n"
        if args.write:
            OUTPUT.write_text(serialized, encoding="utf-8")
        elif not OUTPUT.is_file() or OUTPUT.read_text(encoding="utf-8") != serialized:
            raise ValueError("source changed since review; refresh specs before updating snapshot")
        dirty = [path for path, entry in snapshot["files"].items()
                 if entry["status"] != "committed"]
        print(f"Pinned {len(snapshot['files'])} sources ({len(dirty)} uncommitted).")
    except (OSError, ValueError) as error:
        print(f"Source snapshot error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
