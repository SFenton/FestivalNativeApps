#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Filtered player profile (#619, pattern `invalid-scores` R9)

// With Settings › Filter Invalid Scores on, the player page aggregates any player's
// effective scores (web `PlayerContent` `effectiveScores`), whether or not that player is
// selected. These hosted checks (macOS host, `apple-ci`) read the real
// `PlayerProfileContent` tree, which is the same SwiftUI on iPhone, iPad, iPhone Duo and
// Mac: Best Rank speaks the filtered rank, a chart left with no valid score reads its
// empty state, and the setting and the leeway re-aggregate the open page in place.

/// The shared loopback fixture service with `fixture-player-2`'s scores made invalid at
/// a 1% leeway: Lead `fixture-pulse` (raw #2) is valid only as a 95,000 variant ranked
/// #5, Lead `fixture-orbit` ranks #6, and Drums `fixture-pulse` (raw #1) is invalid
/// below 3% with no fallback. Counts that player's profile reads.
private actor InvalidProfileTransport: HTTPTransport {
    let base = URLSessionHTTPTransport()
    private(set) var profileReads = 0

    /// Forward a public GET, rewriting only `/api/player/fixture-player-2`'s scores.
    ///
    /// - Parameter request: A keyless public read.
    /// - Returns: The fixture response, with the edited scores for the viewed player.
    /// - Throws: Transport errors, or an unexpected fixture shape.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        let result = try await base.send(request)
        guard request.url?.path == "/api/player/fixture-player-2", result.status == 200 else { return result }
        profileReads += 1
        var profile = try #require(try JSONSerialization.jsonObject(with: result.data) as? [String: Any])
        var scores = try #require(profile["scores"] as? [[String: Any]])
        for index in scores.indices {
            switch (scores[index]["si"] as? String, scores[index]["ins"] as? String) {
            case ("fixture-pulse", "01"):
                scores[index]["ml"] = 2.0
                scores[index]["vs"] = [[
                    "sc": 95_000, "acc": 950, "fc": false, "st": 5, "ml": 0.5, "rt": [["l": 0.5, "r": 5]],
                ]]
            case ("fixture-orbit", "01"):
                scores[index]["ml"] = 0.0
                scores[index]["rk"] = 6
            case ("fixture-pulse", "04"):
                scores[index]["ml"] = 3.0
            default:
                break
            }
        }
        profile["scores"] = scores
        var headers: [String: String] = [:]
        for name in ["Content-Type", "ETag", "X-FST-Publication-Id"] {
            if let value = result.header(name) { headers[name] = value }
        }
        return HTTPResult(
            status: result.status, data: try JSONSerialization.data(withJSONObject: profile), headers: headers
        )
    }
}

/// A session over ``InvalidProfileTransport`` with `selected` stored as the selected
/// player.
@MainActor
private func invalidProfileSession(
    selected: String, transport: InvalidProfileTransport
) async throws -> FestivalSession {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: transport)
    let defaults = try #require(UserDefaults(suiteName: "fst.tests.profile-invalid.\(UUID().uuidString)"))
    defaults.set(
        Data(#"{"accountId":"\#(selected)","displayName":"Fixture Player"}"#.utf8),
        forKey: SelectedPlayerIdentity.storageKey
    )
    return FestivalSession(factory: { client }, selectionStorage: defaults)
}

/// Each identified element's spoken value. A static SwiftUI element on macOS exposes
/// `accessibilityValue(_:)` as its value description (VoiceOver speaks it after the label),
/// which ``MacAXNode`` does not read.
@MainActor
private func spokenValues(_ root: NSView) -> [String: String] {
    var values: [String: String] = [:]
    var seen = Set<ObjectIdentifier>()
    func string(_ object: NSObject, _ key: String) -> String? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) as? String : nil
    }
    func walk(_ node: Any, depth: Int) {
        guard depth < 90, let object = node as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return }
        if let id = string(object, "accessibilityIdentifier"), !id.isEmpty,
           let value = string(object, "accessibilityValueDescription") ?? string(object, "accessibilityValue") {
            values[id] = value
        }
        let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
            ? object.value(forKey: "accessibilityChildren") as? [Any] : nil
        for child in children ?? [] { walk(child, depth: depth + 1) }
        if let view = object as? NSView { for subview in view.subviews { walk(subview, depth: depth + 1) } }
    }
    walk(root, depth: 0)
    return values
}

/// Best Rank tile identifiers: Global Statistics, then the Lead section.
private let overviewBestRank = "fst.player.stat.overview.best-rank"
private let leadBestRank = "fst.player.stat.\(Instrument.lead.rawValue).best-rank"
private let drumsEmpty = "fst.player.instrument-empty.\(Instrument.drums.rawValue)"

/// Wait until both Best Rank tiles speak the expected values, and return the tree and
/// the spoken values.
@MainActor
private func settleBestRanks(
    _ host: NSHostingView<some View>, overview: String, lead: String
) async throws -> (nodes: [MacAXNode], values: [String: String]) {
    var values: [String: String] = [:]
    _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
        values = spokenValues(host)
        return values[overviewBestRank] == overview && values[leadBestRank] == lead
    }
    #expect(values[overviewBestRank] == overview && values[leadBestRank] == lead, "\(values)")
    let nodes = macAccessibilityTree(host)
    macAccessibilityDump(nodes, name: "profile-invalid-\(overview)-\(lead)")
    return (nodes, values)
}

/// Accessibility of the filtered player profile (HIG Design principles: "Keep visual and
/// interaction behavior consistent so people learn quickly and can predict new
/// interactions": the same scores show the same filtered ranks on every page).
@MainActor
@Suite(.serialized)
struct PlayerProfileInvalidScoresTests {
    /// A viewed, non-selected player's Best Rank tiles speak the filtered rank (#5 from
    /// the valid variant, not the raw #2 or the dropped Drums #1), Drums reads its empty
    /// state, the content has no accessibility findings, and raising the leeway or
    /// turning the setting off restores the raw ranks in place without re-reading the
    /// profile. Statistics (the same player selected) shows the same filtered ranks.
    @Test func viewedProfileShowsFilteredRanksAndUpdatesInPlace() async throws {
        for selected in ["fixture-player-1", "fixture-player-2"] {
            let transport = InvalidProfileTransport()
            let session = try await invalidProfileSession(selected: selected, transport: transport)
            let suite = "fst.tests.profile-invalid-settings.\(UUID().uuidString)"
            let storage = try #require(UserDefaults(suiteName: suite))
            defer { storage.removePersistentDomain(forName: suite) }
            storage.set(true, forKey: "fst.settings.filterInvalidScores")
            storage.set(1.0, forKey: "fst.settings.leeway")
            let size = CGSize(width: 402, height: 2400)
            let host = nativeHostedView(
                NavigationStack {
                    PlayerProfileContent(session: session, accountId: "fixture-player-2", routeDisplayName: nil)
                }
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark),
                size: size
            )
            let window = nativeHostedWindow(host, size: size)
            defer { window.orderOut(nil) }

            let (filtered, values) = try await settleBestRanks(host, overview: "#5", lead: "#5")
            let best = try #require(filtered.first { $0.isElement && $0.identifier == overviewBestRank })
            #expect(best.label == "Best Rank", "\(best)")
            #expect(filtered.contains { $0.identifier == drumsEmpty }, "Drums has no valid score at 1%")
            #expect(values["fst.player.stat.\(Instrument.lead.rawValue).songs-played"] == "2", "\(values)")
            #expect(macAccessibilityFindings(filtered) == [], "selected: \(selected)")
            let reads = await transport.profileReads

            storage.set(3.0, forKey: "fst.settings.leeway")
            let wide = try await settleBestRanks(host, overview: "#1", lead: "#2").nodes
            #expect(!wide.contains { $0.identifier == drumsEmpty }, "every score is valid at 3%")

            storage.set(1.0, forKey: "fst.settings.leeway")
            _ = try await settleBestRanks(host, overview: "#5", lead: "#5")
            storage.set(false, forKey: "fst.settings.filterInvalidScores")
            let raw = try await settleBestRanks(host, overview: "#1", lead: "#2").nodes
            #expect(!raw.contains { $0.identifier == drumsEmpty })
            #expect(await transport.profileReads == reads, "the open page re-aggregates without a re-read")
        }
    }
}
#endif
