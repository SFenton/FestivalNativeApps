#!/usr/bin/env python3
"""App versions, version tags, build notes and generated What's New for every native platform.

Version scheme (operator, 2026-10-01): ``YYMM.NN`` per platform, e.g. ``2610.01``. ``YYMM`` is the UTC
month of the bump and ``NN`` a per-platform counter that restarts at ``01`` each month (two digits at
least; ``2610.100`` follows ``2610.99``). Versions live only in annotated git tags ``<platform>/v<version>``
on the bumped master commit, so bumping never commits to master. Store mappings:

- iOS/macOS: ``CFBundleShortVersionString`` = version, ``CFBundleVersion`` = Actions run number.
- Android: ``versionName`` = version, ``versionCode`` = ``YYMM*100000 + NN*100 + rebuild``.
- Windows MSIX: ``YYMM.NN.<run number>.0``; the displayed version is still ``YYMM.NN``.

Only ``version-bump.yml`` (push to master) creates tags, and only for platforms whose app paths changed
since the platform's previous tag; it then dispatches that platform's build workflow with the tag. Build
workflows have no push trigger, so a version bump is the only thing that starts a build and release.

Notes come from commit trailers on the first-parent history between two tags::

    Release-Note: Song rows load faster.          (any platform whose app paths the commit touched)
    Release-Note-iOS: Fixed the iPhone Songs tab. (that platform only, wins over the generic note)
    Release-Note-Android: none                    (explicitly nothing for that platform)

The in-app What's New lists one section per released version (newest first, at most ``HISTORY_LIMIT``)
plus the section of the version being built when it is not released yet. A version's items are the user
notes between the previously released version's tag and its own tag, so intermediate unreleased versions
and TestFlight builds fold into the next release. A platform's first release says ``initial_note``.
TestFlight "What to Test" instead lists every app commit since the previous version tag.

Commands (JSON on stdout, standard library only, Python 3.9+)::

    versioning.py bump [--platform ios] [--force] [--push] [--dispatch] [--enabled ios,windows]
    versioning.py describe --tag ios/v2610.01 [--build 57] [--rebuild 0]
    versioning.py latest-tag --platform ios
    versioning.py whats-new --tag ios/v2610.03 --released 2610.01,2610.02 --out WhatsNew.json
                            [--store-notes-out notes.txt]
    versioning.py testflight-notes --tag ios/v2610.03 --build 57 [--rebuild-reason r] --out notes.txt

Documentation: .agents/workflow/release-machine.md ("Versions, notes and What's New").
"""

from __future__ import annotations

import argparse
import datetime as _dt
import fnmatch
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Callable, Dict, Iterable, List, Optional, Sequence, Tuple

# region Configuration

REPO_ROOT = Path(__file__).resolve().parents[2]
SCHEMA = 1
HISTORY_LIMIT = 10
DEFAULT_NOTE = "Bug fixes and improvements."
TESTFLIGHT_LIMIT = 4000
STORE_NOTES_LIMIT = 4000
VERSION_RE = re.compile(r"^(\d{4})\.(\d{2,})$")
TRAILER_RE = re.compile(r"^\s*Release[- ]Notes?(?:-([A-Za-z]+))?\s*:\s*(.*?)\s*$", re.IGNORECASE)
NONE_NOTES = frozenset({"", "none", "n/a", "na", "-", "skip", "no", "internal"})
MERGE_SUBJECT_RE = re.compile(r"^Merge (pull request|branch|remote-tracking branch) ")

#: Per platform: app paths (fnmatch, ``*`` crosses ``/``), excluded paths (``WhatsNew.json`` is the
#: build-generated changelog; its checked-in copy is a placeholder), build workflow, the repository
#: variable that must be ``true`` for bumps (``None`` = always), display name and first-release note.
PLATFORMS: Dict[str, Dict[str, object]] = {
    "ios": {
        "include": ("apple/Sources/*", "apple/Package.swift", "apple/Package.resolved",
                    "apple/project.yml", "apple/Apps/iOS/*"),
        "exclude": ("*.md", "*/WhatsNew.json"),
        "workflow": "ios-release-build.yml",
        "enabled_var": None,
        "display": "iOS",
        "initial_note": "The first release of Festival Score Tracker for iPhone.",
    },
    "macos": {
        "include": ("apple/Sources/*", "apple/Package.swift", "apple/Package.resolved",
                    "apple/project.yml", "apple/Apps/macOS/*"),
        "exclude": ("*.md", "*/WhatsNew.json"),
        "workflow": "macos-release.yml",
        "enabled_var": "FST_RELEASE_MACOS_ENABLED",
        "display": "macOS",
        "initial_note": "The first release of Festival Score Tracker for Mac.",
    },
    "android": {
        "include": ("android/*",),
        "exclude": ("*.md", "*/WhatsNew.json", "android/*/src/test/*", "android/*/src/androidTest/*",
                    "android/reports/*"),
        "workflow": "android-release.yml",
        "enabled_var": "FST_RELEASE_ANDROID_ENABLED",
        "display": "Android",
        "initial_note": "The first release of Festival Score Tracker for Android.",
    },
    "windows": {
        "include": ("windows/*",),
        "exclude": ("*.md", "*/WhatsNew.json", "windows/*.Tests/*", "windows/Bench/*", "windows/reports/*",
                    "windows/coverage.runsettings"),
        "workflow": "windows-release-build.yml",
        "enabled_var": None,
        "display": "Windows",
        "initial_note": "The first release of Festival Score Tracker for Windows.",
    },
}

#: Trailer suffix (lower case) -> platform.
TRAILER_PLATFORMS = {
    "ios": "ios", "iphone": "ios", "macos": "macos", "mac": "macos",
    "android": "android", "windows": "windows", "win": "windows",
}

# endregion

# region Versions


def parse_version(text: str) -> Tuple[int, int]:
    """Parse ``YYMM.NN`` into ``(yymm, nn)``.

    Args:
        text: Version string such as ``2610.01``.

    Returns:
        The comparable ``(yymm, nn)`` pair.

    Raises:
        ValueError: ``text`` is not a ``YYMM.NN`` version.
    """
    found = VERSION_RE.match(text or "")
    if not found or not 1 <= int(found.group(1)[2:]) <= 12 or int(found.group(2)) < 1:
        raise ValueError("not a YYMM.NN version: %r" % text)
    return int(found.group(1)), int(found.group(2))


def is_version(text: str) -> bool:
    """Return whether ``text`` is a ``YYMM.NN`` version."""
    try:
        parse_version(text)
    except ValueError:
        return False
    return True


def format_version(yymm: int, nn: int) -> str:
    """Format ``(yymm, nn)`` as ``YYMM.NN`` (``NN`` zero-padded to two digits)."""
    return "%04d.%02d" % (yymm, nn)


def next_version(last: Optional[str], now: _dt.datetime) -> str:
    """Return the version after ``last`` for a bump at ``now``.

    Args:
        last: The platform's newest version, or ``None`` for its first.
        now: Bump time (converted to UTC).

    Returns:
        ``YYMM.01`` in a new month, otherwise ``last`` with ``NN`` + 1. A clock behind ``last``'s month
        keeps counting in ``last``'s month so versions never go backwards.
    """
    utc = now.astimezone(_dt.timezone.utc) if now.tzinfo else now
    month = int(utc.strftime("%y%m"))
    if last is None:
        return format_version(month, 1)
    last_month, last_nn = parse_version(last)
    if last_month >= month:
        return format_version(last_month, last_nn + 1)
    return format_version(month, 1)


def tag_for(platform: str, version: str) -> str:
    """Return the version tag name, e.g. ``ios/v2610.01``."""
    return "%s/v%s" % (platform, version)


def parse_tag(tag: str) -> Tuple[str, str]:
    """Split ``<platform>/v<version>`` (``refs/tags/`` optional) into ``(platform, version)``.

    Raises:
        ValueError: Unknown platform or malformed version.
    """
    name = tag[len("refs/tags/"):] if tag.startswith("refs/tags/") else tag
    platform, _, rest = name.partition("/v")
    if platform not in PLATFORMS or not is_version(rest):
        raise ValueError("not a version tag: %r" % tag)
    return platform, rest


def android_version_code(version: str, rebuild: int = 0) -> int:
    """Return the Play ``versionCode``: ``YYMM*100000 + NN*100 + rebuild`` (monotonic for NN < 1000)."""
    yymm, nn = parse_version(version)
    if not 0 <= rebuild < 100 or nn >= 1000:
        raise ValueError("versionCode needs NN < 1000 and rebuild < 100")
    return yymm * 100000 + nn * 100 + rebuild


def msix_version(version: str, build: int) -> str:
    """Return the four-part Store MSIX version ``YYMM.NN.<build>.0`` (each field at most 65535)."""
    yymm, nn = parse_version(version)
    if not 0 <= build <= 65535 or nn > 65535:
        raise ValueError("MSIX fields must be at most 65535")
    return "%d.%d.%d.0" % (yymm, nn, build)


# endregion

# region Git

Runner = Callable[[Sequence[str]], str]


class Git:
    """Thin ``git`` wrapper bound to one repository (injectable for tests)."""

    def __init__(self, root: Path = REPO_ROOT, runner: Optional[Runner] = None) -> None:
        self.root = Path(root)
        self._runner = runner

    def __call__(self, *args: str) -> str:
        """Run ``git <args>`` and return stdout (raises ``RuntimeError`` on failure)."""
        if self._runner is not None:
            return self._runner(list(args))
        proc = subprocess.run(["git", "-C", str(self.root)] + list(args), capture_output=True, text=True)
        if proc.returncode != 0:
            raise RuntimeError("git %s failed: %s" % (" ".join(args[:3]), (proc.stderr or "").strip()[-300:]))
        return proc.stdout

    def rev(self, ref: str) -> str:
        """Resolve ``ref`` to a commit SHA."""
        return self("rev-parse", "%s^{commit}" % ref).strip()

    def is_ancestor(self, ancestor: str, descendant: str) -> bool:
        """True when ``ancestor`` is reachable from ``descendant``."""
        try:
            self("merge-base", "--is-ancestor", ancestor, descendant)
        except RuntimeError:
            return False
        return True

    def version_tags(self, platform: str) -> List[Tuple[str, str]]:
        """Return ``[(version, tag)]`` for ``platform``, newest version first."""
        found = []
        for line in self("tag", "--list", "%s/v*" % platform).splitlines():
            try:
                _, version = parse_tag(line.strip())
            except ValueError:
                continue
            found.append((version, line.strip()))
        found.sort(key=lambda item: parse_version(item[0]), reverse=True)
        return found

    def released_from_tags(self, platform: str) -> List[str]:
        """Versions recorded by ``<platform>/released/<version>`` tags (stores without a history API)."""
        out = []
        for line in self("tag", "--list", "%s/released/*" % platform).splitlines():
            version = line.strip().rsplit("/", 1)[-1]
            if is_version(version):
                out.append(version)
        return sorted(set(out), key=parse_version, reverse=True)

    def first_parent(self, base: Optional[str], head: str) -> List[str]:
        """First-parent commits in ``(base, head]``, newest first."""
        spec = "%s..%s" % (base, head) if base else head
        return [line for line in self("rev-list", "--first-parent", spec).split() if line]

    def parents(self, sha: str) -> List[str]:
        """Parent SHAs of ``sha``."""
        return self("rev-list", "--parents", "-n", "1", sha).split()[1:]

    def changed_files(self, sha: str) -> List[str]:
        """Files ``sha`` changed relative to its first parent (all files for a root commit)."""
        parents = self.parents(sha)
        if parents:
            out = self("diff", "--name-only", "--no-renames", parents[0], sha)
        else:
            out = self("show", "--name-only", "--no-renames", "--format=", sha)
        return [line for line in out.splitlines() if line]

    def tree_files(self, ref: str) -> List[str]:
        """Every file path in ``ref``'s tree."""
        return [line for line in self("ls-tree", "-r", "--name-only", ref).splitlines() if line]

    def diff_files(self, base: str, head: str) -> List[str]:
        """Files changed between ``base`` and ``head``."""
        return [line for line in self("diff", "--name-only", "--no-renames", base, head).splitlines() if line]

    def message(self, sha: str) -> str:
        """Full commit message of ``sha``."""
        return self("log", "-1", "--format=%B", sha)

    def side_messages(self, merge: str) -> List[str]:
        """Messages of the commits a merge brought in (``merge^1..merge`` minus first-parent)."""
        parents = self.parents(merge)
        if len(parents) < 2:
            return []
        shas = [s for s in self("rev-list", "%s..%s" % (parents[0], merge)).split() if s and s != merge]
        return [self.message(s) for s in shas]


# endregion

# region Commits and notes


def matches(platform: str, path: str) -> bool:
    """Return whether ``path`` belongs to ``platform``'s shipped app."""
    spec = PLATFORMS[platform]
    if not any(fnmatch.fnmatchcase(path, pat) for pat in spec["include"]):  # type: ignore[union-attr]
        return False
    return not any(fnmatch.fnmatchcase(path, pat) for pat in spec["exclude"])  # type: ignore[union-attr]


def relevant(platform: str, files: Iterable[str]) -> bool:
    """Return whether any of ``files`` belongs to ``platform``'s app."""
    return any(matches(platform, f) for f in files)


def parse_trailers(message: str) -> Dict[str, List[str]]:
    """Return release-note trailers by key: ``"*"`` for generic, else the platform id.

    A value such as ``none`` is kept as an empty list so it suppresses the generic note.
    """
    found: Dict[str, List[str]] = {}
    for line in message.splitlines():
        hit = TRAILER_RE.match(line)
        if not hit:
            continue
        suffix = (hit.group(1) or "").lower()
        key = "*" if not suffix else TRAILER_PLATFORMS.get(suffix)
        if key is None:
            continue
        value = " ".join(hit.group(2).split())
        bucket = found.setdefault(key, [])
        if value.lower() not in NONE_NOTES:
            bucket.append(value)
    return found


def subject(message: str) -> str:
    """Commit subject; for ``Merge pull request`` commits the PR title from the body."""
    lines = [line.strip() for line in message.splitlines()]
    first = lines[0] if lines else ""
    if MERGE_SUBJECT_RE.match(first):
        body = next((line for line in lines[1:] if line and not TRAILER_RE.match(line)), "")
        return body or first
    return first


class Change:
    """One first-parent commit with what it means for a platform."""

    def __init__(self, sha: str, subject_line: str, app: bool, notes: List[str]) -> None:
        self.sha = sha
        self.subject = subject_line
        self.app = app
        self.notes = notes


def changes(git: Git, platform: str, base: Optional[str], head: str) -> List[Change]:
    """Collect ``platform`` changes in ``(base, head]`` (newest first).

    ``app`` is True when the commit (a merge: the whole merged branch) touched the platform's app paths.
    ``notes`` are the platform-specific trailers when present, else the generic trailers for app commits.
    Trailers on a merge's side commits count for the merge.
    """
    out = []
    for sha in git.first_parent(base, head):
        message = git.message(sha)
        trailers = parse_trailers(message)
        for side in git.side_messages(sha):
            for key, values in parse_trailers(side).items():
                trailers.setdefault(key, []).extend(values)
        app = relevant(platform, git.changed_files(sha))
        if platform in trailers:
            notes = trailers[platform]
        elif app:
            notes = trailers.get("*", [])
        else:
            notes = []
        if app or notes:
            out.append(Change(sha, subject(message), app, notes))
    return out


def user_notes(git: Git, platform: str, base: Optional[str], head: str) -> List[str]:
    """User-facing notes in ``(base, head]``, oldest first, de-duplicated case-insensitively."""
    seen = set()
    out = []
    for change in reversed(changes(git, platform, base, head)):
        for note in change.notes:
            if note.lower() not in seen:
                seen.add(note.lower())
                out.append(note)
    return out


def bullets(items: Iterable[str], limit: int) -> str:
    """Join ``items`` as ``• `` lines without exceeding ``limit`` characters."""
    lines: List[str] = []
    size = 0
    for item in items:
        line = "• " + item
        extra = len(line) + (1 if lines else 0)
        if size + extra > limit:
            if not lines:
                lines.append(line[:limit - 1] + "…")
            break
        lines.append(line)
        size += extra
    return "\n".join(lines)


# endregion

# region What's New and TestFlight notes


def whats_new(git: Git, platform: str, version: str, released: Iterable[str]) -> Dict[str, object]:
    """Build the What's New document for ``platform`` at ``version``.

    Args:
        git: Repository holding the version tags.
        platform: Platform id.
        version: Version being built (its tag must exist).
        released: Versions the store has released (any order; unknown/untagged ones are ignored).

    Returns:
        ``{schema, platform, version, baseline, entries: [{version, released, items}]}``; ``baseline`` is
        the newest released version older than ``version`` (``None`` before the first release) and
        ``entries`` are newest first.
    """
    tags = dict(git.version_tags(platform))
    if version not in tags:
        raise ValueError("no tag %s" % tag_for(platform, version))
    key = parse_version(version)
    shipped = sorted({v for v in released if is_version(v) and v in tags and parse_version(v) <= key},
                     key=parse_version)
    sections: List[str] = shipped[-HISTORY_LIMIT:]
    if version not in shipped:
        sections = (sections + [version])[-HISTORY_LIMIT:]
    entries = []
    initial = str(PLATFORMS[platform]["initial_note"])
    for item in sections:
        older = [v for v in shipped if parse_version(v) < parse_version(item)]
        if older:
            items = user_notes(git, platform, tags[older[-1]], tags[item]) or [DEFAULT_NOTE]
        else:
            items = [initial]
        entries.append({"version": item, "released": item in shipped, "items": items})
    entries.reverse()
    older_than = [v for v in shipped if parse_version(v) < key]
    return {"schema": SCHEMA, "platform": platform, "version": version,
            "baseline": older_than[-1] if older_than else None, "entries": entries}


def store_notes(document: Dict[str, object]) -> str:
    """App Store / Store listing "What's New": the built version's items as bullets."""
    entries = document.get("entries") or []
    first = entries[0] if entries else None  # type: ignore[index]
    if not isinstance(first, dict) or first.get("version") != document.get("version"):
        return DEFAULT_NOTE
    return bullets(first.get("items") or [DEFAULT_NOTE], STORE_NOTES_LIMIT)


def testflight_notes(git: Git, platform: str, version: str, build: str,
                     rebuild_reason: Optional[str] = None) -> str:
    """TestFlight "What to Test" for one build (platform-specific, at most 4000 characters).

    A fresh version lists the app commits and user notes since the previous version tag; a rebuild of an
    already-built version says it carries no app changes.
    """
    display = str(PLATFORMS[platform]["display"])
    head = "Festival Score Tracker %s %s (build %s)" % (display, version, build)
    if rebuild_reason:
        return "%s\nRebuild of %s with no %s app changes; only the build number changed (%s)." % (
            head, version, display, rebuild_reason)
    tags = git.version_tags(platform)
    older = [(v, t) for v, t in tags if parse_version(v) < parse_version(version)]
    current = dict(tags).get(version)
    if current is None:
        raise ValueError("no tag %s" % tag_for(platform, version))
    if not older:
        return "%s\nFirst build numbered %s; later builds list the %s app changes since the previous version." % (
            head, version, display)
    prev_version, prev_tag = older[0]
    found = [c for c in changes(git, platform, prev_tag, current) if c.app]
    if not found:
        return "%s\nNo %s app changes since %s; only the version and build number changed." % (
            head, display, prev_version)
    lines = [c.subject for c in found]
    notes = user_notes(git, platform, prev_tag, current)
    text = "%s\nChanges since %s:\n%s" % (head, prev_version, bullets(lines, TESTFLIGHT_LIMIT))
    if notes:
        text += "\n\nRelease notes:\n" + bullets(notes, TESTFLIGHT_LIMIT)
    return text[:TESTFLIGHT_LIMIT]


# endregion

# region Bump


def enabled_platforms(env: Dict[str, str]) -> List[str]:
    """Platforms that bump: always-on ones plus those whose repository variable is ``true``."""
    return [p for p, spec in PLATFORMS.items()
            if spec["enabled_var"] is None or env.get(str(spec["enabled_var"])) == "true"]


def plan_bump(git: Git, platform: str, head: str, now: _dt.datetime, force: bool = False) -> Dict[str, object]:
    """Decide whether ``platform`` needs a new version at ``head``.

    Returns:
        ``{platform, bump, reason, version?, tag?, previous?}``; ``bump`` is False when ``head`` already
        carries a version tag or no app path changed since the previous tag (unless ``force``).
    """
    tags = git.version_tags(platform)
    previous = tags[0] if tags else None
    result: Dict[str, object] = {"platform": platform, "previous": previous[0] if previous else None}
    head_sha = git.rev(head)
    if previous and git.rev(previous[1]) == head_sha:
        return dict(result, bump=False, reason="already_tagged")
    if previous and not git.is_ancestor(previous[1], head_sha):
        # A late run for an older push: the newer tag already covers this commit.
        return dict(result, bump=False, reason="behind_previous_tag")
    if previous is None:
        if not relevant(platform, git.tree_files(head_sha)):
            return dict(result, bump=False, reason="no_app_files")
        reason = "first_version"
    elif relevant(platform, git.diff_files(previous[1], head_sha)):
        reason = "app_changed"
    elif force:
        reason = "forced"
    else:
        return dict(result, bump=False, reason="no_app_changes")
    version = next_version(previous[0] if previous else None, now)
    return dict(result, bump=True, reason=reason, version=version, tag=tag_for(platform, version), sha=head_sha)


def gh(args: Sequence[str]) -> str:
    """Run ``gh`` and return stdout (raises ``RuntimeError``)."""
    proc = subprocess.run(["gh"] + list(args), capture_output=True, text=True, timeout=120)
    if proc.returncode != 0:
        raise RuntimeError("gh %s failed: %s" % (" ".join(args[:2]), (proc.stderr or "").strip()[-300:]))
    return proc.stdout


def bump(git: Git, platforms: Iterable[str], head: str, now: _dt.datetime, force: bool = False,
         push: bool = False, dispatch: bool = False, gh_runner: Callable[[Sequence[str]], str] = gh,
         ref: str = "master") -> Dict[str, object]:
    """Tag every platform that needs a version at ``head``; optionally push and dispatch its build.

    Returns:
        ``{bumped: [plan + dispatched], skipped: [plan]}``.
    """
    bumped, skipped = [], []
    for platform in platforms:
        plan = plan_bump(git, platform, head, now, force)
        if not plan["bump"]:
            skipped.append(plan)
            continue
        tag = str(plan["tag"])
        git("tag", "-a", tag, str(plan["sha"]), "-m",
            "%s %s (%s)" % (PLATFORMS[platform]["display"], plan["version"], plan["reason"]))
        if push:
            git("push", "origin", "refs/tags/%s" % tag)
        plan["dispatched"] = False
        if dispatch:
            try:
                gh_runner(["workflow", "run", str(PLATFORMS[platform]["workflow"]), "--ref", ref,
                           "-f", "version_tag=%s" % tag])
            except (RuntimeError, OSError):
                # Without a build the tag would read as already built: drop it so a re-run bumps again.
                if push:
                    git("push", "origin", ":refs/tags/%s" % tag)
                git("tag", "-d", tag)
                raise
            plan["dispatched"] = True
        bumped.append(plan)
    return {"bumped": bumped, "skipped": skipped}


# endregion

# region CLI


def describe(git: Git, tag: str, build: Optional[int] = None, rebuild: int = 0) -> Dict[str, object]:
    """Return the facts a build needs about ``tag`` (version, SHA, previous version, store mappings)."""
    platform, version = parse_tag(tag)
    tags = git.version_tags(platform)
    older = [v for v, _ in tags if parse_version(v) < parse_version(version)]
    out: Dict[str, object] = {"platform": platform, "version": version, "tag": tag, "sha": git.rev(tag),
                              "previous": older[0] if older else None,
                              "android_version_code": android_version_code(version, rebuild)}
    if build is not None:
        out["build"] = str(build)
        out["msix_version"] = msix_version(version, build)
    return out


def build_parser() -> argparse.ArgumentParser:
    """Create the command-line parser."""
    parser = argparse.ArgumentParser(prog="versioning.py", description=__doc__.split("\n")[0])
    parser.add_argument("--repo", default=str(REPO_ROOT))
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("bump")
    p.add_argument("--platform", action="append", choices=sorted(PLATFORMS))
    p.add_argument("--enabled", help="comma-separated platforms (default: enabled_platforms())")
    p.add_argument("--head", default="HEAD")
    p.add_argument("--now", help="ISO time (default: now, UTC)")
    p.add_argument("--force", action="store_true")
    p.add_argument("--push", action="store_true")
    p.add_argument("--dispatch", action="store_true")
    p.add_argument("--ref", default="master")
    p = sub.add_parser("describe")
    p.add_argument("--tag", required=True)
    p.add_argument("--build", type=int)
    p.add_argument("--rebuild", type=int, default=0)
    p = sub.add_parser("latest-tag")
    p.add_argument("--platform", required=True, choices=sorted(PLATFORMS))
    p = sub.add_parser("whats-new")
    p.add_argument("--tag", required=True)
    p.add_argument("--released", default="", help="comma-separated released versions")
    p.add_argument("--released-from-tags", action="store_true")
    p.add_argument("--out", required=True)
    p.add_argument("--store-notes-out")
    p = sub.add_parser("testflight-notes")
    p.add_argument("--tag", required=True)
    p.add_argument("--build", required=True)
    p.add_argument("--rebuild-reason")
    p.add_argument("--out", required=True)
    return parser


def main(argv: Optional[List[str]] = None, env: Optional[Dict[str, str]] = None,
         gh_runner: Callable[[Sequence[str]], str] = gh) -> int:
    """Run the CLI; returns the exit code (0 ok, 1 failure)."""
    args = build_parser().parse_args(argv)
    env = dict(os.environ) if env is None else env
    git = Git(Path(args.repo))
    try:
        if args.command == "bump":
            now = (_dt.datetime.fromisoformat(args.now.replace("Z", "+00:00")) if args.now
                   else _dt.datetime.now(_dt.timezone.utc))
            if args.platform:
                platforms = args.platform
            elif args.enabled:
                platforms = [p for p in args.enabled.split(",") if p]
            else:
                platforms = enabled_platforms(env)
            doc: object = bump(git, platforms, args.head, now, args.force, args.push, args.dispatch,
                               gh_runner, args.ref)
        elif args.command == "describe":
            doc = describe(git, args.tag, args.build, args.rebuild)
        elif args.command == "latest-tag":
            tags = git.version_tags(args.platform)
            doc = {"platform": args.platform, "tag": tags[0][1] if tags else None,
                   "version": tags[0][0] if tags else None}
        elif args.command == "whats-new":
            platform, version = parse_tag(args.tag)
            released = [v for v in args.released.split(",") if v.strip()]
            if args.released_from_tags:
                released += git.released_from_tags(platform)
            doc = whats_new(git, platform, version, [v.strip() for v in released])
            Path(args.out).write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n")
            if args.store_notes_out:
                Path(args.store_notes_out).write_text(store_notes(doc) + "\n")
        else:
            platform, version = parse_tag(args.tag)
            text = testflight_notes(git, platform, version, args.build, args.rebuild_reason)
            Path(args.out).write_text(text + "\n")
            doc = {"platform": platform, "version": version, "build": args.build, "chars": len(text)}
    except (ValueError, RuntimeError, OSError) as err:
        print(json.dumps({"error": str(err)}))
        return 1
    print(json.dumps(doc))
    return 0


# endregion

if __name__ == "__main__":
    sys.exit(main())
