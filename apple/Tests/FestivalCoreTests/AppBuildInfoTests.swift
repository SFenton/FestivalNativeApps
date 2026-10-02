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
    /// The `apple/project.yml` target blocks, keyed by target name (each block runs from its
    /// `  Name:` line up to the next two-space-indented key or top-level key).
    private func targetBlocks() throws -> [String: String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("project.yml")
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        guard let targets = lines.firstIndex(of: "targets:") else { return [:] }
        var blocks: [String: String] = [:]
        var name: String?
        var body: [String] = []
        func flush() {
            if let name { blocks[name] = body.joined(separator: "\n") }
        }
        for line in lines[(targets + 1)...] {
            if !line.hasPrefix(" "), !line.isEmpty { break }
            let isTargetKey = line.hasPrefix("  ") && !line.hasPrefix("   ") && line.hasSuffix(":")
                && !line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
            if isTargetKey {
                flush()
                name = String(line.dropFirst(2).dropLast())
                body = [line]
            } else {
                body.append(line)
            }
        }
        flush()
        return blocks
    }

    /// Names of every app (`type: application`) target: iPhone, iPad and Mac.
    private func applicationTargets() throws -> [String: String] {
        try targetBlocks().filter { $0.value.contains("type: application") }
    }

    @Test("The iPhone and Mac apps are found in apple/project.yml")
    func knownAppsPresent() throws {
        let apps = try applicationTargets()
        #expect(apps["FestivalMobile"] != nil)
        #expect(apps["FestivalDesktop"] != nil)
    }

    @Test("Every Apple app takes version, build and commit from release build settings")
    func infoPlistReadsBuildSettings() throws {
        let apps = try applicationTargets()
        #expect(!apps.isEmpty, "no application targets found in apple/project.yml")
        for (target, block) in apps.sorted(by: { $0.key < $1.key }) {
            #expect(block.contains("CFBundleShortVersionString: $(MARKETING_VERSION)"), "\(target)")
            #expect(block.contains("CFBundleVersion: $(CURRENT_PROJECT_VERSION)"), "\(target)")
            #expect(block.contains("\(AppBuildInfo.gitSHAKey): $(FST_GIT_SHA)"), "\(target)")
            #expect(block.contains("FST_GIT_SHA: dev"), "\(target): local builds must keep the dev default (no commit shown)")
        }
    }
}
