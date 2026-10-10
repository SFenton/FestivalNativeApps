"""Unit tests for ``tools/release/versioning.py`` against throwaway git repositories."""

import datetime as dt
import io
import json
import re
import subprocess
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from tools.release import versioning as v

OCT = dt.datetime(2026, 10, 1, 12, tzinfo=dt.timezone.utc)
NOV = dt.datetime(2026, 11, 2, 12, tzinfo=dt.timezone.utc)


class Repo:
    """A scratch git repository with helpers for commits, merges and tags."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.run("init", "-q", "-b", "master")
        self.run("config", "user.email", "t@example.com")
        self.run("config", "user.name", "T")
        self.run("config", "commit.gpgsign", "false")
        self.run("config", "tag.gpgsign", "false")
        self.git = v.Git(root)

    def run(self, *args: str) -> str:
        return subprocess.run(["git", "-C", str(self.root)] + list(args), check=True,
                              capture_output=True, text=True).stdout

    def commit(self, message: str, *paths: str) -> str:
        for path in paths:
            target = self.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text((target.read_text() if target.exists() else "") + message + "\n")
            self.run("add", path)
        self.run("commit", "-q", "--allow-empty", "-m", message)
        return self.run("rev-parse", "HEAD").strip()

    def tag(self, name: str, ref: str = "HEAD") -> None:
        self.run("tag", "-a", name, ref, "-m", name)


class VersionTests(unittest.TestCase):
    def test_parse_and_format(self):
        self.assertEqual(v.parse_version("2610.01.01"), (2610, 1, 1))
        self.assertEqual(v.parse_version("2610.31.99"), (2610, 31, 99))
        for bad in ("2610.01", "2610.1.01", "2610.01.1", "2610.01.100", "1.0", "2613.01.01", "2600.01.01",
                    "2610.00.01", "2610.32.01", "2610.01.00", "abc", ""):
            self.assertFalse(v.is_version(bad), bad)
        self.assertEqual(v.format_version(2610, 1, 7), "2610.01.07")
        with self.assertRaises(ValueError):
            v.format_version(2610, 1, 100)

    def test_next_version_resets_daily_and_never_goes_back(self):
        self.assertEqual(v.next_version(None, OCT), "2610.01.01")
        self.assertEqual(v.next_version("2610.01.01", OCT), "2610.01.02")
        self.assertEqual(v.next_version("2610.01.07", NOV), "2611.02.01")
        self.assertEqual(v.next_version("2610.01.07", OCT + dt.timedelta(days=1)), "2610.02.01")
        self.assertEqual(v.next_version("2611.02.03", OCT), "2611.02.04")
        with self.assertRaises(ValueError):
            v.next_version("2610.01.99", OCT)
        pdt = dt.datetime(2026, 9, 30, 20, tzinfo=dt.timezone(dt.timedelta(hours=-7)))
        self.assertEqual(v.next_version(None, pdt), "2610.01.01")  # UTC date

    def test_ordering_is_numeric(self):
        ordered = sorted(["2610.10.01", "2610.02.11", "2611.01.01", "2610.02.02", "2609.30.50"],
                         key=v.parse_version)
        self.assertEqual(ordered, ["2609.30.50", "2610.02.02", "2610.02.11", "2610.10.01", "2611.01.01"])

    def test_tags_and_store_mappings(self):
        self.assertEqual(v.tag_for("ios", "2610.01.01"), "ios/v2610.01.01")
        self.assertEqual(v.parse_tag("refs/tags/windows/v2610.12.03"), ("windows", "2610.12.03"))
        for bad in ("ios/released/2610.01.01", "tvos/v2610.01.01", "ios/v2610.01"):
            with self.assertRaises(ValueError):
                v.parse_tag(bad)
        self.assertEqual(v.android_version_code("2610.01.01"), 261001010)
        self.assertEqual(v.android_version_code("2610.12.34", 3), 261012343)
        self.assertLess(v.android_version_code("2610.01.99", 9), v.android_version_code("2610.02.01"))
        self.assertLess(v.android_version_code("2610.31.99", 9), v.android_version_code("2611.01.01"))
        self.assertLess(v.android_version_code("9912.31.99", 9), 2100000000)
        with self.assertRaises(ValueError):
            v.android_version_code("2610.01.01", 10)
        self.assertEqual(v.msix_version("2610.01.01", 57), "2610.101.57.0")
        self.assertEqual(v.msix_version("2610.31.99", 65535), "2610.3199.65535.0")
        with self.assertRaises(ValueError):
            v.msix_version("2610.01.01", 70000)


class PathAndTrailerTests(unittest.TestCase):
    def test_platform_paths(self):
        self.assertTrue(v.matches("ios", "apple/Sources/FestivalUI/Songs.swift"))
        self.assertTrue(v.matches("ios", "apple/Apps/iOS/Info.plist"))
        self.assertFalse(v.matches("ios", "apple/Apps/macOS/App.swift"))
        self.assertFalse(v.matches("ios", "apple/Tests/FestivalCoreTests/X.swift"))
        self.assertFalse(v.matches("ios", "apple/Apps/iOSUITests/X.swift"))
        self.assertFalse(v.matches("ios", "apple/Sources/README.md"))
        self.assertFalse(v.matches("ios", "apple/Apps/iOS/WhatsNew.json"))
        self.assertFalse(v.matches("android", "android/app/src/main/assets/WhatsNew.json"))
        self.assertTrue(v.matches("macos", "apple/Apps/macOS/App.swift"))
        self.assertTrue(v.matches("android", "android/app/src/main/java/A.kt"))
        self.assertFalse(v.matches("android", "android/app/src/test/java/A.kt"))
        self.assertFalse(v.matches("android", "android/app/src/androidTest/java/A.kt"))
        self.assertTrue(v.matches("windows", "windows/Festival.Core/Domain/Changelog.cs"))
        self.assertFalse(v.matches("windows", "windows/Festival.Core.Tests/WhatsNewTests.cs"))
        self.assertFalse(v.matches("ios", "tools/release/fst_release.py"))

    def test_trailers(self):
        message = ("Fix rows\n\nBody text.\n\nRelease-Note: Rows load faster.\n"
                   "release-note-ios: iPhone rows load faster.\nRelease-Note-Android: none\n"
                   "Release-Note-tvOS: ignored\nRelease-note:\n")
        self.assertEqual(v.parse_trailers(message), {
            "*": ["Rows load faster."], "ios": ["iPhone rows load faster."], "android": []})

    def test_merge_subject_uses_pr_title(self):
        self.assertEqual(v.subject("Merge pull request #4 from a/b\n\nFix the Songs tab\n"), "Fix the Songs tab")
        self.assertEqual(v.subject("Plain subject\n\nbody"), "Plain subject")

    def test_bullets_respect_limit(self):
        self.assertEqual(v.bullets(["a", "b"], 100), "• a\n• b")
        self.assertEqual(v.bullets(["a" * 10, "b"], 13), "• aaaaaaaaaa")
        self.assertEqual(v.bullets(["a" * 20], 6), "• aaa…")


class GitFlowTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Repo(Path(self.tmp.name))
        self.repo.commit("Initial app", "apple/Sources/FestivalCore/A.swift", "windows/Festival.Core/A.cs")

    def tearDown(self):
        self.tmp.cleanup()

    def test_plan_bump_first_then_only_on_app_changes(self):
        git = self.repo.git
        plan = v.plan_bump(git, "ios", "HEAD", OCT)
        self.assertEqual((plan["bump"], plan["reason"], plan["version"]), (True, "first_version", "2610.01.01"))
        self.repo.tag("ios/v2610.01.01")
        self.assertEqual(v.plan_bump(git, "ios", "HEAD", OCT)["reason"], "already_tagged")
        self.repo.commit("Docs only", "docs/x.md", "apple/Tests/FestivalCoreTests/T.swift")
        self.assertEqual(v.plan_bump(git, "ios", "HEAD", OCT)["reason"], "no_app_changes")
        forced = v.plan_bump(git, "ios", "HEAD", OCT, force=True)
        self.assertEqual((forced["reason"], forced["version"]), ("forced", "2610.01.02"))
        self.repo.commit("Change", "apple/Sources/FestivalUI/B.swift")
        plan = v.plan_bump(git, "ios", "HEAD", NOV)
        self.assertEqual((plan["reason"], plan["version"], plan["previous"]), ("app_changed", "2611.02.01", "2610.01.01"))

    def test_bump_tags_pushes_and_dispatches(self):
        calls = []
        result = v.bump(self.repo.git, ["ios", "windows", "android"], "HEAD", OCT, dispatch=True,
                        gh_runner=lambda a: calls.append(list(a)) or "")
        self.assertEqual([b["tag"] for b in result["bumped"]], ["ios/v2610.01.01", "windows/v2610.01.01"])
        self.assertEqual(result["skipped"][0]["reason"], "no_app_files")
        self.assertEqual(calls[0], ["workflow", "run", "ios-release-build.yml", "--ref", "master",
                                    "-f", "version_tag=ios/v2610.01.01"])
        self.assertEqual(self.repo.git.version_tags("ios"), [("2610.01.01", "ios/v2610.01.01")])
        again = v.bump(self.repo.git, ["ios"], "HEAD", OCT)
        self.assertEqual(again["bumped"], [])

    def test_late_run_for_older_commit_does_not_bump(self):
        old = self.repo.git.rev("HEAD")
        self.repo.commit("Change", "apple/Sources/FestivalUI/B.swift")
        self.repo.tag("ios/v2610.01.01")
        self.assertEqual(v.plan_bump(self.repo.git, "ios", old, OCT)["reason"], "behind_previous_tag")

    def test_release_branch_cut_from_master_is_versioned_although_it_diverged(self):
        base = self.repo.git.rev("HEAD")
        # Last week's release branch: a cherry-picked fix on top of the cut, tagged there.
        self.repo.git("checkout", "-q", "-b", "releases/2610.05")
        self.repo.commit("Cherry-picked fix", "apple/Sources/FestivalUI/Fix.swift")
        self.repo.tag("ios/v2610.08.01")
        old_release_head = self.repo.git.rev("HEAD")
        # Master moved on (not containing the cherry-pick copy); this week's branch is cut from it.
        self.repo.git("checkout", "-q", base)
        self.repo.commit("Feature", "apple/Sources/FestivalUI/New.swift")
        head = self.repo.git.rev("HEAD")
        self.assertEqual(v.plan_bump(self.repo.git, "ios", head, OCT)["reason"], "behind_previous_tag")
        plan = v.plan_bump(self.repo.git, "ios", head, NOV, release=True)
        self.assertEqual((plan["bump"], plan["reason"]), (True, "release_branch"))
        # An older commit of the tagged branch itself is still skipped in release mode.
        self.assertEqual(v.plan_bump(self.repo.git, "ios", base, NOV, release=True)["reason"], "behind_previous_tag")
        self.assertNotEqual(old_release_head, head)

    def test_failed_dispatch_drops_the_tag(self):
        def broken(_args):
            raise RuntimeError("gh down")
        with self.assertRaises(RuntimeError):
            v.bump(self.repo.git, ["ios"], "HEAD", OCT, dispatch=True, gh_runner=broken)
        self.assertEqual(self.repo.git.version_tags("ios"), [])
        self.assertEqual(v.plan_bump(self.repo.git, "ios", "HEAD", OCT)["reason"], "first_version")

    def _history(self):
        """2610.01.01 (released) → 2610.01.02 (not released) → 2610.01.03 (released) → 2610.01.04 (building)."""
        r = self.repo
        r.tag("ios/v2610.01.01")
        r.commit("Speed up songs\n\nRelease-Note: Songs load faster.", "apple/Sources/FestivalUI/S.swift")
        r.commit("Windows only\n\nRelease-Note: Windows thing.", "windows/Festival.App/W.cs")
        r.tag("ios/v2610.01.02")
        r.run("checkout", "-q", "-b", "feature")
        r.commit("Shop badge\n\nRelease-Note-iOS: The Item Shop badge is back.\nRelease-Note: generic",
                 "apple/Sources/FestivalUI/Shop.swift")
        r.run("checkout", "-q", "master")
        r.run("merge", "-q", "--no-ff", "feature", "-m", "Merge pull request #7 from x/feature\n\nShop badge fix")
        r.tag("ios/v2610.01.03")
        r.commit("Tests only\n\nRelease-Note: should not appear", "apple/Tests/FestivalUITests/T.swift")
        r.commit("Rivals\n\nRelease-Note: Rivals refresh correctly.", "apple/Sources/FestivalUI/R.swift")
        r.tag("ios/v2610.01.04")

    def test_whats_new_sections_per_released_version(self):
        self._history()
        doc = v.whats_new(self.repo.git, "ios", "2610.01.04", ["2610.01.01", "2610.01.03", "1.0", "2611.02.01"])
        self.assertEqual(doc["baseline"], "2610.01.03")
        self.assertEqual([e["version"] for e in doc["entries"]], ["2610.01.04", "2610.01.03", "2610.01.01"])
        self.assertEqual([e["released"] for e in doc["entries"]], [False, True, True])
        self.assertEqual(doc["entries"][0]["items"], ["Rivals refresh correctly."])
        # 2610.01.02 was never released, so its notes fold into 2610.01.03; the iOS-specific note wins.
        self.assertEqual(doc["entries"][1]["items"], ["Songs load faster.", "The Item Shop badge is back."])
        self.assertEqual(doc["entries"][2]["items"], [v.PLATFORMS["ios"]["initial_note"]])
        self.assertEqual(v.store_notes(doc), "• Rivals refresh correctly.")

    def test_whats_new_first_release_and_released_current(self):
        self._history()
        first = v.whats_new(self.repo.git, "ios", "2610.01.02", [])
        self.assertIsNone(first["baseline"])
        self.assertEqual(first["entries"], [{"version": "2610.01.02", "released": False,
                                             "items": [v.PLATFORMS["ios"]["initial_note"]],
                                             "groups": v.groups_json([v.PLATFORMS["ios"]["initial_note"]]),
                                             "testflight": {"since": "2610.01.01", "new": ["Songs load faster."],
                                                            "release": None, "vs_release": ["Songs load faster."],
                                                            "groups": [{"category": "Songs",
                                                                        "items": ["Songs load faster."]}]}}])
        shipped = v.whats_new(self.repo.git, "ios", "2610.01.03", ["2610.01.01", "2610.01.03"])
        self.assertEqual([e["version"] for e in shipped["entries"]], ["2610.01.03", "2610.01.01"])
        self.assertEqual(shipped["baseline"], "2610.01.01")
        with self.assertRaises(ValueError):
            v.whats_new(self.repo.git, "ios", "2610.01.09", [])

    def test_whats_new_defaults_without_trailers_and_caps_history(self):
        r = self.repo
        released = []
        for n in range(1, 14):
            self.merge_pr(n, "[Bug] change %d (#%d)" % (n, n), "apple/Sources/FestivalCore/A%d.swift" % n)
            r.tag("ios/v2610.01.%02d" % n)
            released.append("2610.01.%02d" % n)
        doc = v.whats_new(r.git, "ios", "2610.01.13", released)
        self.assertEqual(len(doc["entries"]), v.HISTORY_LIMIT)
        # A merged PR without a trailer contributes its cleaned title, never a generic line.
        self.assertEqual(doc["entries"][0]["items"], ["Change 13"])

    def merge_pr(self, number, title, path, trailer=""):
        """Merge a one-commit branch the way GitHub does (PR title on the merge commit's second line)."""
        r = self.repo
        r.run("checkout", "-q", "-b", "pr%d" % number)
        r.commit("wip %d" % number, path)
        r.run("checkout", "-q", "master")
        message = "Merge pull request #%d from x/pr%d\n\n%s%s" % (number, number, title, trailer)
        r.run("merge", "-q", "--no-ff", "pr%d" % number, "-m", message)

    def test_nothing_user_facing_skips_the_section_and_store_text(self):
        r = self.repo
        r.tag("ios/v2610.01.01")
        r.commit("Internal\n\nRelease-Note: none", "apple/Sources/FestivalCore/A.swift")
        r.tag("ios/v2610.01.02")
        doc = v.whats_new(r.git, "ios", "2610.01.02", ["2610.01.01"])
        self.assertEqual([e["version"] for e in doc["entries"]], ["2610.01.01"])
        self.assertEqual(v.store_notes(doc), "")
        self.assertEqual(v.clean_title("[Bug] quick Links order (#6)"), "Quick Links order")

    def test_testflight_notes(self):
        self._history()
        git = self.repo.git
        head = "Festival Score Tracker iOS 2610.01.04"
        text = v.testflight_notes(git, "ios", "2610.01.04", "41", released=["2610.01.01", "2610.01.03"])
        self.assertEqual(text, head + "\n\n• Rivals refresh correctly.")
        # Unreleased 2610.01.02 and 2610.01.03 fold into "Other Changes" (vs. the 2610.01.01 release).
        older = v.testflight_notes(git, "ios", "2610.01.04", "41", released=["2610.01.01"])
        self.assertEqual(older, head + "\n\n• Rivals refresh correctly.\n\nOther Changes:\n\nSongs\n\n"
                                       "• Songs load faster.\n\nItem Shop\n\n• The Item Shop badge is back.")
        self.assertNotIn("(build", older)
        # Commit subjects, PR titles and other platforms' notes never appear.
        for absent in ("Shop badge fix", "Merge pull request", "Windows thing", "should not appear", "generic"):
            self.assertNotIn(absent, older)
        unreleased = v.testflight_notes(git, "ios", "2610.01.03", "40")
        self.assertEqual(unreleased, "Festival Score Tracker iOS 2610.01.03\n\n• The Item Shop badge is back.\n\n"
                                     "Other Changes:\n\nSongs\n\n• Songs load faster.")
        # Commits pushed without a trailer (the fixture's "Initial app") never become bullets.
        self.assertNotIn("Initial app", unreleased)
        rebuild = v.testflight_notes(git, "ios", "2610.01.04", "44", rebuild_reason="stale_whats_new",
                                     released=["2610.01.03"])
        self.assertEqual(rebuild, head + "\n\n• Rebuild with no iOS app changes; only the build number changed "
                                         "(stale_whats_new).\n\nOther Changes:\n\nRivals\n\n• Rivals refresh correctly.")
        self.repo.commit("Docs", "docs/a.md")
        self.repo.tag("ios/v2610.01.05")
        # A version with nothing new still lists everything since the release.
        quiet = v.testflight_notes(git, "ios", "2610.01.05", "45", released=["2610.01.03"])
        self.assertEqual(quiet, "Festival Score Tracker iOS 2610.01.05\n\n• No iOS app changes; only the version "
                                "and build number changed.\n\nOther Changes:\n\nRivals\n\n• Rivals refresh correctly.")

    def test_testflight_notes_untrailered_changes_and_limit(self):
        r = self.repo
        r.tag("ios/v2610.01.01")
        r.commit("Refactor the cache", "apple/Sources/FestivalCore/A.swift")
        self.merge_pr(5, "[Feature] iOS: rows show ranks (#5)", "apple/Sources/FestivalUI/Rows.swift")
        r.tag("ios/v2610.01.02")
        text = v.testflight_notes(r.git, "ios", "2610.01.02", "2", released=["2610.01.01"])
        # One bullet per check-in: the untrailered PR by its title, never the direct code commit.
        self.assertEqual(text, "Festival Score Tracker iOS 2610.01.02\n\n• iOS: rows show ranks")
        self.assertNotIn("Bug fixes and improvements", text)
        r.commit("Internal\n\nRelease-Note: none", "apple/Sources/FestivalCore/B.swift")
        r.tag("ios/v2610.01.04")
        quiet = v.testflight_notes(r.git, "ios", "2610.01.04", "4", released=["2610.01.01"])
        self.assertEqual(quiet, "Festival Score Tracker iOS 2610.01.04\n\n• No user-facing changes.\n\n"
                                "Other Changes:\n\n• iOS: rows show ranks")
        for n in range(90):
            r.commit("c\n\nRelease-Note: Songs: Note number %d with a reasonably long sentence about it." % n,
                     "apple/Sources/FestivalCore/A.swift")
        r.tag("ios/v2610.01.05")
        long = v.testflight_notes(r.git, "ios", "2610.01.05", "5")
        self.assertLessEqual(len(long), v.TESTFLIGHT_LIMIT)
        self.assertIn("2610.01.05\n\n• Songs: Note number 0 ", long)
        self.assertRegex(long, r"\n• …and \d+ more\.\n\nOther Changes:\n\n• iOS: rows show ranks$")

    def test_notes_are_the_net_difference_replaces_tester_and_reverts(self):
        r = self.repo
        r.tag("ios/v2610.01.01")
        r.commit("a\n\nRelease-Note: Songs: Rows fade in slowly.", "apple/Sources/FestivalUI/S1.swift")
        r.commit("b\n\nRelease-Note: Songs: Rows fade in quickly.\nRelease-Note-Replaces: Rows fade in slowly.",
                 "apple/Sources/FestivalUI/S2.swift")
        r.commit("c\n\nRelease-Note: Settings: Reset asks first.", "apple/Sources/FestivalUI/S3.swift")
        reverted = r.git("rev-parse", "HEAD").strip()
        r.commit('Revert "c"\n\nThis reverts commit %s.' % reverted, "apple/Sources/FestivalUI/S3.swift")
        r.commit("d\n\nRelease-Note-Tester-iOS: Fixed a crash in the new row fade.",
                 "apple/Sources/FestivalUI/S4.swift")
        r.tag("ios/v2610.01.02")
        self.assertEqual(v.user_notes(r.git, "ios", "ios/v2610.01.01", "ios/v2610.01.02"),
                         ["Songs: Rows fade in quickly."])
        self.assertEqual(v.user_notes(r.git, "ios", "ios/v2610.01.01", "ios/v2610.01.02", tester=True),
                         ["Songs: Rows fade in quickly.", "Fixed a crash in the new row fade."])
        self.assertEqual(v.testflight_notes(r.git, "ios", "2610.01.02", "2", released=["2610.01.01"]),
                         "Festival Score Tracker iOS 2610.01.02\n\n• Songs: Rows fade in quickly.\n"
                         "• Fixed a crash in the new row fade.")
        doc = v.whats_new(r.git, "ios", "2610.01.02", ["2610.01.01"])
        self.assertEqual(doc["entries"][0]["items"], ["Songs: Rows fade in quickly."])
        # A notes-only commit (no app files) can undo an unreleased note; released notes are untouched.
        r.commit("Notes\n\nRelease-Note-Replaces: Songs: Rows fade in quickly.", "docs/notes.md")
        r.tag("ios/v2610.01.03")
        self.assertEqual(v.user_notes(r.git, "ios", "ios/v2610.01.01", "ios/v2610.01.03"), [])
        self.assertEqual(v.user_notes(r.git, "ios", "ios/v2610.01.02", "ios/v2610.01.03"), [])
        entries = v.whats_new(r.git, "ios", "2610.01.03", ["2610.01.01", "2610.01.02"])["entries"]
        self.assertEqual([e["items"] for e in entries if e["version"] == "2610.01.02"],
                         [["Songs: Rows fade in quickly."]])
        self.assertEqual(v.parse_revisions("Release-Note-Replaces: A note.\nRelease-Note-Tester-Android: T.\n"
                                           "Release-Note-Tester: none"),
                         ({"*": ["A note."]}, {"android": ["T."]}))

    def test_commits_reverted_inside_a_merge_leave_no_notes(self):
        r = self.repo
        r.tag("ios/v2610.01.01")
        r.run("checkout", "-q", "-b", "report")
        r.commit("Android\n\nRelease-Note-iOS: Songs: Wrong platform.\nRelease-Note-Replaces: Songs: Keep me.",
                 "apple/Sources/FestivalUI/A.swift")
        bad = r.git("rev-parse", "HEAD").strip()
        r.commit('Revert "Android"\n\nThis reverts commit %s.' % bad, "apple/Sources/FestivalUI/A.swift")
        r.commit("iOS\n\nRelease-Note: Songs: Tools sit next to search.", "apple/Sources/FestivalUI/B.swift")
        r.run("checkout", "-q", "master")
        r.commit("Earlier\n\nRelease-Note: Songs: Keep me.", "apple/Sources/FestivalUI/C.swift")
        r.run("merge", "-q", "--no-ff", "report", "-m", "Merge pull request #9 from x/report\n\nTools")
        r.tag("ios/v2610.01.02")
        self.assertEqual(v.user_notes(r.git, "ios", "ios/v2610.01.01", "ios/v2610.01.02"),
                         ["Songs: Keep me.", "Songs: Tools sit next to search."])

    def test_pending_notes_cli(self):
        self._history()
        self.repo.commit("x\n\nRelease-Note-Tester: Fixed the new Rivals refresh.", "apple/Sources/FestivalUI/R2.swift")
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = v.main(["--repo", str(self.repo.root), "pending-notes", "--platform", "ios",
                           "--released", "2610.01.03"])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(buf.getvalue()), {
            "platform": "ios", "release": "2610.01.03", "notes": ["Rivals refresh correctly."],
            "tester": ["Fixed the new Rivals refresh."]})
        self.assertIsNone(v.pending_notes(self.repo.git, "ios")["release"])

    def test_category_bullets(self):
        notes = ["Spinners fade in.", "Songs: Rows fade in.", "Settings: CHOpt inline.", "Songs: Index rail.",
                 "General: Faster launch."]
        self.assertEqual(v.category_bullets(notes, 4000),
                         "Songs\n\n• Rows fade in.\n• Index rail.\n\nSettings\n\n• CHOpt inline.\n\nGeneral\n\n"
                         "• Faster launch.\n• Spinners fade in.")
        self.assertEqual(v.category_bullets(["A.", "B."], 4000), "• A.\n• B.")
        self.assertEqual(v.category_bullets(notes, 60), "Songs\n\n• Rows fade in.\n• Index rail.\n• …and 3 more.")
        self.assertEqual(v.category_bullets(notes, 20), "• …and 5 more.")
        self.assertEqual(v.strip_category("Item Shop: Badges."), "Badges.")
        self.assertEqual(v.strip_category("Note: not a category."), "Note: not a category.")

    def test_infer_category_prefers_the_opening_words(self):
        cases = {
            "Item Shop rows now match the Songs list.": "Item Shop",
            "Compete no longer shows a separate Leaderboards Overview button.": "Compete",
            "Leaderboard rows now keep ranks lined up.": "Leaderboards",
            "CHOpt Path Default View in Settings now expands inline.": "Settings",
            "Song pages now show band leaderboard previews.": "Song Details",
            "Tapping a letter in the Songs A–Z index lands on it.": "Songs",
            "First-run guides now show the page title, which VoiceOver reads first.": "First Run",
            "Fixed a crash when opening the app.": "Performance",
            "Spinners now fade the results in.": None,
        }
        for note, category in cases.items():
            self.assertEqual(v.infer_category(note), category, note)
        self.assertEqual(v.category_of("Settings: Item Shop badges."), "Settings")
        self.assertEqual(v.groups_json(["Fixed a crash.", "Spinners."]),
                         [{"category": "Performance", "items": ["Fixed a crash."]},
                          {"category": None, "items": ["Spinners."]}])

    def test_whats_new_tester_block_only_on_unreleased_build(self):
        self._history()
        doc = v.whats_new(self.repo.git, "ios", "2610.01.04", ["2610.01.01"])
        self.assertEqual(doc["entries"][0]["testflight"], {
            "since": "2610.01.03", "new": ["Rivals refresh correctly."], "release": "2610.01.01",
            "vs_release": ["Songs load faster.", "Rivals refresh correctly.", "The Item Shop badge is back."],
            "groups": [{"category": "Songs", "items": ["Songs load faster."]},
                       {"category": "Rivals", "items": ["Rivals refresh correctly."]},
                       {"category": "Item Shop", "items": ["The Item Shop badge is back."]}]})
        self.assertTrue(all("testflight" not in e for e in doc["entries"][1:]))
        shipped = v.whats_new(self.repo.git, "ios", "2610.01.03", ["2610.01.01", "2610.01.03"])
        self.assertTrue(all("testflight" not in e for e in shipped["entries"]))

    def test_cli_testflight_notes_reads_released(self):
        self._history()
        root = self.repo.root
        self.repo.tag("ios/released/2610.01.03")
        out = root / "tf.txt"
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = v.main(["--repo", str(root), "testflight-notes", "--tag", "ios/v2610.01.04", "--build", "7",
                           "--released", "2610.01.01", "--released-from-tags", "--out", str(out)])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(buf.getvalue())["build"], "7")
        self.assertEqual(out.read_text().splitlines()[0], "Festival Score Tracker iOS 2610.01.04")

    def test_release_tools_always_name_utf8(self):
        # Windows runners default to cp1252: "•" in notes became "\ufffd" in Store text (2026-10-01).
        pattern = re.compile(r"\.(write_text|read_text)\(((?:[^()]|\([^()]*\))*)\)")
        for path in sorted(Path(v.__file__).parent.glob("*.py")):
            for match in pattern.finditer(path.read_text(encoding="utf-8")):
                self.assertIn("encoding", match.group(2), "%s: %s" % (path.name, match.group(0)))

    def test_cli_writes_utf8_notes(self):
        self._history()
        root = self.repo.root
        with redirect_stdout(io.StringIO()):
            v.main(["--repo", str(root), "whats-new", "--tag", "ios/v2610.01.04", "--released", "2610.01.01",
                    "--out", str(root / "wn.json"), "--store-notes-out", str(root / "notes.txt")])
        self.assertTrue((root / "notes.txt").read_bytes().startswith("•".encode("utf-8")))

    def test_check_notes_requires_a_trailer_for_app_changes(self):
        r = self.repo
        base = r.git.rev("HEAD")
        r.commit("Docs", "docs/a.md")
        self.assertEqual(v.notes_check(r.git, base, "HEAD"), {"platforms": [], "has_release_note": False, "ok": True})
        r.commit("Tweak rows", "apple/Sources/FestivalUI/Row.swift", "windows/Festival.App/Row.cs")
        missing = v.notes_check(r.git, base, "HEAD")
        self.assertEqual((missing["platforms"], missing["ok"]), (["ios", "macos", "windows"], False))
        self.assertTrue(v.notes_check(r.git, base, "HEAD", "Fix\n\nRelease-Note: none")["ok"])
        r.commit("More\n\nRelease-Note-iOS: Rows are taller.", "apple/Sources/FestivalUI/Row2.swift")
        self.assertTrue(v.notes_check(r.git, base, "HEAD")["ok"])
        body = r.root / "body.md"
        body.write_text("no trailer", encoding="utf-8")
        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(v.main(["--repo", str(r.root), "check-notes", "--base", base, "--head", "HEAD~1",
                                     "--body-file", str(body)]), 1)
            self.assertEqual(v.main(["--repo", str(r.root), "check-notes", "--base", base, "--head", "HEAD"]), 0)

    def test_notes_are_grouped_by_category(self):
        notes = ["Settings: CHOpt view is inline.", "Fixed a crash.", "Songs: Rows fade in once.",
                 "item shop: Rows reuse the song row.", "Songs: Index rail lands on the right letter.",
                 "Note: not a category."]
        self.assertEqual(v.by_category(notes), [
            "Songs: Rows fade in once.", "Songs: Index rail lands on the right letter.",
            "item shop: Rows reuse the song row.", "Settings: CHOpt view is inline.",
            "Fixed a crash.", "Note: not a category."])
        self.assertEqual(v.note_category("Song Details: Bands show."), "Song Details")
        self.assertIsNone(v.note_category("Songs:no space"))
        r = self.repo
        r.tag("ios/v2610.01.01")
        r.commit("a\n\nRelease-Note: Settings: Reset asks first.", "apple/Sources/FestivalUI/A.swift")
        r.commit("b\n\nRelease-Note: Songs: Faster rows.", "apple/Sources/FestivalUI/B.swift")
        r.tag("ios/v2610.01.02")
        text = v.testflight_notes(r.git, "ios", "2610.01.02", "2", released=["2610.01.01"])
        self.assertEqual(text, "Festival Score Tracker iOS 2610.01.02\n\n• Songs: Faster rows.\n• Settings: Reset asks first.")
        doc = v.whats_new(r.git, "ios", "2610.01.02", ["2610.01.01"])
        self.assertEqual(doc["entries"][0]["items"], ["Songs: Faster rows.", "Settings: Reset asks first."])

    def test_released_from_tags(self):
        self.repo.tag("windows/v2610.01.01")
        self.repo.tag("windows/released/2610.01.01")
        self.repo.tag("windows/released/junk")
        self.assertEqual(self.repo.git.released_from_tags("windows"), ["2610.01.01"])

    def test_cli_round_trip(self):
        self._history()
        root = self.repo.root
        out = root / "wn.json"
        notes = root / "notes.txt"
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = v.main(["--repo", str(root), "whats-new", "--tag", "ios/v2610.01.04",
                           "--released", "2610.01.01,2610.01.03", "--out", str(out), "--store-notes-out", str(notes)])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(out.read_text())["version"], "2610.01.04")
        self.assertEqual(notes.read_text(), "• Rivals refresh correctly.\n")
        buf = io.StringIO()
        with redirect_stdout(buf):
            v.main(["--repo", str(root), "describe", "--tag", "ios/v2610.01.04", "--build", "50"])
        described = json.loads(buf.getvalue())
        self.assertEqual((described["previous"], described["msix_version"]), ("2610.01.03", "2610.104.50.0"))
        buf = io.StringIO()
        with redirect_stdout(buf):
            self.assertEqual(v.main(["--repo", str(root), "latest-tag", "--platform", "ios"]), 0)
        self.assertEqual(json.loads(buf.getvalue())["tag"], "ios/v2610.01.04")
        buf = io.StringIO()
        with redirect_stdout(buf):
            self.assertEqual(v.main(["--repo", str(root), "describe", "--tag", "nope"]), 1)
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = v.main(["--repo", str(root), "bump", "--enabled", "ios", "--now", "2026-11-01T00:00:00Z"])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(buf.getvalue())["skipped"][0]["reason"], "already_tagged")

    def test_enabled_platforms(self):
        self.assertEqual(v.enabled_platforms({}), ["ios", "windows"])
        self.assertEqual(v.enabled_platforms({"FST_RELEASE_ANDROID_ENABLED": "true"}), ["ios", "android", "windows"])


if __name__ == "__main__":
    unittest.main()
