import Foundation
import Testing
@testable import FestivalCore

// MARK: - AppBuildInfo

@Suite("AppBuildInfo")
struct AppBuildInfoTests {
    private let base: [String: Any] = ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "42"]

    private func info(sha: String?) -> [String: Any] {
        var info = base
        info[AppBuildInfo.gitSHAKey] = sha
        return info
    }

    @Test("A stamped commit appends its first seven characters")
    func stampedCommit() {
        let text = AppBuildInfo.versionText(info(sha: "42edc57a1b2c3d4e5f60718293a4b5c6d7e8f901"))
        #expect(text == "0.1.0 (42) · 42edc57")
    }

    @Test("Missing, dev and empty commits show only version and build")
    func noCommitSuffix() {
        #expect(AppBuildInfo.versionText(base) == "0.1.0 (42)")
        #expect(AppBuildInfo.versionText(info(sha: "dev")) == "0.1.0 (42)")
        #expect(AppBuildInfo.versionText(info(sha: "")) == "0.1.0 (42)")
        #expect(AppBuildInfo.versionText(info(sha: "  ")) == "0.1.0 (42)")
    }

    @Test("Non-hex values such as an unexpanded build setting are ignored")
    func rejectsNonHex() {
        #expect(AppBuildInfo.shortCommit("$(FST_GIT_SHA)") == nil)
        #expect(AppBuildInfo.shortCommit("DEV") == nil)
        #expect(AppBuildInfo.shortCommit("main") == nil)
    }

    @Test("Short and upper-case SHAs are normalised")
    func normalises() {
        #expect(AppBuildInfo.shortCommit("ABC12") == "abc12")
        #expect(AppBuildInfo.shortCommit(" 42EDC57FF\n") == "42edc57")
    }

    @Test("A release version tag reads as version, build and commit")
    func releaseTagVersion() {
        let stamped: [String: Any] = [
            "CFBundleShortVersionString": "2610.02.17",
            "CFBundleVersion": "57",
            AppBuildInfo.gitSHAKey: "42edc57a1b2c3d4e5f60718293a4b5c6d7e8f901",
        ]
        #expect(AppBuildInfo.versionText(stamped) == "2610.02.17 (57) · 42edc57")
    }

    @Test("Version and build fallbacks are unchanged")
    func fallbacks() {
        #expect(AppBuildInfo.versionText(nil) == "—")
        #expect(AppBuildInfo.versionText(["CFBundleShortVersionString": "2.1"]) == "2.1")
        #expect(AppBuildInfo.versionText(["CFBundleVersion": "7"]) == "— (7)")
        #expect(AppBuildInfo.versionText(["CFBundleShortVersionString": "2.1", AppBuildInfo.gitSHAKey: "abcdef0123"])
            == "2.1 · abcdef0")
    }
}

// MARK: - Release stamping

/// Guards the path from a `version-bump` tag to Settings → App Version: release builds pass
/// `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` and `FST_GIT_SHA` on the `xcodebuild` command
/// line, so each Apple app's Info.plist must read those settings rather than fixed values.
@Suite("Release version stamping")
struct ReleaseVersionStampingTests {
    /// The `apple/project.yml` block for one target (its lines up to the next target).
    private func targetBlock(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("project.yml")
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        guard let start = lines.firstIndex(of: "  \(name):") else { return "" }
        let rest = lines[(start + 1)...]
        let end = rest.firstIndex { line in
            line.hasPrefix("  ") && !line.hasPrefix("   ") && !line.trimmingCharacters(in: .whitespaces).isEmpty
                || (!line.hasPrefix(" ") && !line.isEmpty)
        } ?? lines.endIndex
        return lines[start..<end].joined(separator: "\n")
    }

    @Test("iPhone and Mac apps take version, build and commit from release build settings",
          arguments: ["FestivalMobile", "FestivalDesktop"])
    func infoPlistReadsBuildSettings(target: String) throws {
        let block = try targetBlock(target)
        #expect(!block.isEmpty, "target \(target) not found in apple/project.yml")
        #expect(block.contains("CFBundleShortVersionString: $(MARKETING_VERSION)"))
        #expect(block.contains("CFBundleVersion: $(CURRENT_PROJECT_VERSION)"))
        #expect(block.contains("\(AppBuildInfo.gitSHAKey): $(FST_GIT_SHA)"))
        #expect(block.contains("FST_GIT_SHA: dev"), "local builds must keep the dev default (no commit shown)")
    }
}
