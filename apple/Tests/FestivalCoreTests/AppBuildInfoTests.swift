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

    @Test("Version and build fallbacks are unchanged")
    func fallbacks() {
        #expect(AppBuildInfo.versionText(nil) == "—")
        #expect(AppBuildInfo.versionText(["CFBundleShortVersionString": "2.1"]) == "2.1")
        #expect(AppBuildInfo.versionText(["CFBundleVersion": "7"]) == "— (7)")
        #expect(AppBuildInfo.versionText(["CFBundleShortVersionString": "2.1", AppBuildInfo.gitSHAKey: "abcdef0123"])
            == "2.1 · abcdef0")
    }
}
