#!/usr/bin/env python3
"""App versions, version tags, build notes and generated What's New for every native platform.

Version scheme (operator, 2026-10-01): ``YYMM.DD.NN`` per platform, e.g. ``2610.01.01``. ``YYMM.DD`` is
the UTC date of the bump and ``NN`` a per-platform counter that restarts at ``01`` each day (two digits;
at most 99 a day). Versions live only in annotated git tags ``<platform>/v<version>`` on the bumped master
commit, so bumping never commits to master. Store mappings:

- iOS/macOS: ``CFBundleShortVersionString`` = version (three integers), ``CFBundleVersion`` = run number.
- Android: ``versionName`` = version, ``versionCode`` = ``YYMM*100000 + DD*1000 + NN*10 + rebuild``.
- Windows MSIX: ``YYMM.<DD*100+NN>.<run number>.0`` (16-bit fields); the displayed version is
  still ``YYMM.DD.NN``.

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
The unreleased built version's entry also carries ``testflight: {since, new, release, vs_release}`` for
beta builds: notes new since the previous version, and every note since the latest release. TestFlight
"What to Test" uses the same two sections ("New since …", "In this build vs. release …").

Commands (JSON on stdout, standard library only, Python 3.9+)::

    versioning.py bump [--platform ios] [--force] [--push] [--dispatch] [--enabled ios,windows]
    versioning.py describe --tag ios/v2610.01.01 [--build 57] [--rebuild 0]
    versioning.py latest-tag --platform ios
    versioning.py whats-new --tag ios/v2610.03.01 --released 2610.01.01,2610.02.01 --out WhatsNew.json
                            [--store-notes-out notes.txt]
    versioning.py testflight-notes --tag ios/v2610.03.01 --build 57 [--rebuild-reason r]
                                   [--released 2610.01.01] --out notes.txt

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
VERSION_RE = re.compile(r"^(\d{4})\.(\d{2})\.(\d{2})$")
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


def parse_version(text: str) -> Tuple[int, int, int]:
    """Parse ``YYMM.DD.NN`` into ``(yymm, dd, nn)``.

    Args:
        text: Version string such as ``2610.01.01``.

    Returns:
        The comparable ``(yymm, dd, nn)`` triple.

    Raises:
        ValueError: ``text`` is not a ``YYMM.DD.NN`` version.
    """
    found = VERSION_RE.match(text or "")
    if not found or not 1 <= int(found.group(1)[2:]) <= 12 or not 1 <= int(found.group(2)) <= 31 \
            or int(found.group(3)) < 1:
        raise ValueError("not a YYMM.DD.NN version: %r" % text)
    return int(found.group(1)), int(found.group(2)), int(found.group(3))


def is_version(text: str) -> bool:
    """Return whether ``text`` is a ``YYMM.DD.NN`` version."""
    try:
        parse_version(text)
    except ValueError:
        return False
    return True


def format_version(yymm: int, dd: int, nn: int) -> str:
    """Format ``(yymm, dd, nn)`` as ``YYMM.DD.NN`` (``DD`` and ``NN`` zero-padded to two digits).

    Raises:
        ValueError: ``nn`` exceeds the 99 versions a platform may cut per day.
    """
    if not 1 <= nn <= 99:
        raise ValueError("at most 99 versions a day (NN=%d)" % nn)
    return "%04d.%02d.%02d" % (yymm, dd, nn)


def next_version(last: Optional[str], now: _dt.datetime) -> str:
    """Return the version after ``last`` for a bump at ``now``.

    Args:
        last: The platform's newest version, or ``None`` for its first.
        now: Bump time (converted to UTC).

    Returns:
        ``YYMM.DD.01`` on a new day, otherwise ``last`` with ``NN`` + 1. A clock behind ``last``'s day
        keeps counting on ``last``'s day so versions never go backwards.
    """
    utc = now.astimezone(_dt.timezone.utc) if now.tzinfo else now
    today = (int(utc.strftime("%y%m")), utc.day)
    if last is None:
        return format_version(today[0], today[1], 1)
    yymm, dd, nn = parse_version(last)
    if (yymm, dd) >= today:
        return format_version(yymm, dd, nn + 1)
    return format_version(today[0], today[1], 1)


def tag_for(platform: str, version: str) -> str:
    """Return the version tag name, e.g. ``ios/v2610.01.01``."""
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
    """Return the Play ``versionCode``: ``YYMM*100000 + DD*1000 + NN*10 + rebuild``.

    Monotonic in the version (``NN`` < 100) and below Play's 2100000000 limit; ``2610.01.01`` is
    ``261001010``.

    Raises:
        ValueError: ``rebuild`` is outside 0-9.
    """
    yymm, dd, nn = parse_version(version)
    if not 0 <= rebuild < 10 or nn >= 100:
        raise ValueError("versionCode needs NN < 100 and rebuild < 10")
    return yymm * 100000 + dd * 1000 + nn * 10 + rebuild


def msix_version(version: str, build: int) -> str:
    """Return the four-part Store MSIX version ``YYMM.<DD*100+NN>.<build>.0`` (each field at most 65535)."""
    yymm, dd, nn = parse_version(version)
    if not 0 <= build <= 65535 or nn >= 100:
        raise ValueError("MSIX fields must be at most 65535 and NN below 100")
    return "%d.%d.%d.0" % (yymm, dd * 100 + nn, build)


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

    def __init__(self, sha: str, subject_line: str, app: bool, notes: List[str], opted_out: bool = False) -> None:
        self.sha = sha
        self.subject = subject_line
        self.app = app
        self.notes = notes
        #: The commit's applicable trailer was explicitly ``none`` (nothing user-facing).
        self.opted_out = opted_out


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
            notes, opted_out = trailers[platform], not trailers[platform]
        elif app:
            notes, opted_out = trailers.get("*", []), "*" in trailers and not trailers["*"]
        else:
            notes, opted_out = [], False
        if app or notes:
            out.append(Change(sha, subject(message), app, notes, opted_out))
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
        entry: Dict[str, object] = {"version": item, "released": item in shipped, "items": items}
        if item == version and item not in shipped:
            entry["testflight"] = tester_notes(git, platform, version, shipped)
        entries.append(entry)
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


def tester_notes(git: Git, platform: str, version: str, released: Iterable[str],
                 rebuild_reason: Optional[str] = None) -> Dict[str, object]:
    """User-facing notes for testers of ``version``: what is new since the previous build and what differs
    from the store's latest release.

    Args:
        git: Repository holding the version tags.
        platform: Platform id.
        version: Version being built (its tag must exist).
        released: Versions the store has released (unknown/untagged and newer ones are ignored).
        rebuild_reason: Set when this build re-uses ``version`` with no app changes.

    Returns:
        ``{since, new, release, vs_release}``. ``since`` is the previous version (``None`` for the first
        build or a rebuild); ``release`` is the newest released version older than ``version`` (``None``
        before the first release). Both lists hold user notes only, never commit subjects.
    """
    display = str(PLATFORMS[platform]["display"])
    tags = dict(git.version_tags(platform))
    current = tags.get(version)
    if current is None:
        raise ValueError("no tag %s" % tag_for(platform, version))
    key = parse_version(version)
    older = sorted((v for v in tags if parse_version(v) < key), key=parse_version)
    shipped = sorted({v for v in released if is_version(v) and v in tags and parse_version(v) < key},
                     key=parse_version)

    def notes_between(base: Optional[str], empty: str) -> List[str]:
        found = [c for c in changes(git, platform, base, current) if c.app or c.notes]
        notes = user_notes(git, platform, base, current)
        if notes:
            return notes
        if any(c.app and not c.opted_out for c in found):
            return [DEFAULT_NOTE]
        return ["No user-facing changes."] if found else [empty]

    if rebuild_reason:
        since, new = None, ["Rebuild with no %s app changes; only the build number changed (%s)." % (
            display, rebuild_reason)]
    elif older:
        since = older[-1]
        new = notes_between(tags[since], "No %s app changes; only the version and build number changed." % display)
    else:
        since, new = None, []
    release = shipped[-1] if shipped else None
    vs_release = notes_between(tags[release] if release else None,
                               "No %s app changes since %s." % (display, release or "the first build"))
    return {"since": since, "new": new, "release": release, "vs_release": vs_release}


def tester_headings(notes: Dict[str, object]) -> Tuple[Optional[str], str]:
    """Headings for :func:`tester_notes`: ``("New since …", "In this build vs. release …")``.

    The first is ``None`` when there is no previous build to compare with.
    """
    if notes.get("new"):
        first: Optional[str] = ("New since %s" % notes["since"]) if notes.get("since") else "New since the last build"
    else:
        first = None
    release = notes.get("release")
    second = ("In this build vs. release %s" % release) if release else "In this build vs. release (no release yet)"
    return first, second


def testflight_notes(git: Git, platform: str, version: str, build: str,
                     rebuild_reason: Optional[str] = None, released: Iterable[str] = ()) -> str:
    """TestFlight "What to Test" for one build (platform-specific, at most 4000 characters).

    Two sections of user-facing notes (``Release-Note`` trailers, never PR titles): what is new since the
    previous version, and everything in this build that differs from the store's latest release (all notes
    before the first release). See :func:`tester_notes`.
    """
    display = str(PLATFORMS[platform]["display"])
    notes = tester_notes(git, platform, version, released, rebuild_reason)
    first, second = tester_headings(notes)
    text = "Festival Score Tracker %s %s (build %s)" % (display, version, build)
    if first:
        text += "\n\n%s:\n%s" % (first, bullets(notes["new"], TESTFLIGHT_LIMIT // 2))  # type: ignore[arg-type]
    budget = TESTFLIGHT_LIMIT - len(text) - len(second) - 4
    if budget > 20:
        text += "\n\n%s:\n%s" % (second, bullets(notes["vs_release"], budget))  # type: ignore[arg-type]
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
    p.add_argument("--released", default="", help="comma-separated released versions")
    p.add_argument("--released-from-tags", action="store_true")
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
            Path(args.out).write_text(json.dumps(doc, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            if args.store_notes_out:
                Path(args.store_notes_out).write_text(store_notes(doc) + "\n", encoding="utf-8")
        else:
            platform, version = parse_tag(args.tag)
            released = [v.strip() for v in args.released.split(",") if v.strip()]
            if args.released_from_tags:
                released += git.released_from_tags(platform)
            text = testflight_notes(git, platform, version, args.build, args.rebuild_reason, released)
            Path(args.out).write_text(text + "\n", encoding="utf-8")
            doc = {"platform": platform, "version": version, "build": args.build, "chars": len(text)}
    except (ValueError, RuntimeError, OSError) as err:
        print(json.dumps({"error": str(err)}))
        return 1
    print(json.dumps(doc))
    return 0


# endregion

if __name__ == "__main__":
    sys.exit(main())
