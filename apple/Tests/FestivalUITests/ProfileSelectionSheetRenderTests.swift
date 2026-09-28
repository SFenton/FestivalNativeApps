#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

/// Paint the actual native profile sheet without issuing a public account request.
///
/// - Parameters:
///   - session: Anonymous or identity-only synthetic app session.
///   - size: Phone-like or wide native content dimensions.
///   - typeSize: Native text scaling used by the sheet and Close action.
/// - Returns: AppKit-hosted pixels, including real Form and segmented controls.
/// - Throws: A missing hosted rendering.
@MainActor
private func profileSheetImage(
    session: FestivalSession, size: CGSize,
    typeSize: DynamicTypeSize = .large
) throws -> CGImage {
    let host = nativeHostedView(
        ProfileSelectionSheet(session: session)
            .environment(\.dynamicTypeSize, typeSize)
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue),
        size: size
    )
    return try nativeHostedImage(host)
}

/// Initial and stored-selection states paint distinct, readable sheets at two widths.
@MainActor
@Test func profileSheetPaintsAnonymousAndSelectedIdentityWithoutAService() throws {
    let suiteName = "fst-profile-render-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    let viewed = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
    {"accountId":"fixture-player-1","displayName":"Fixture Player 1"}
    """.utf8))
    let identity = try SelectedPlayerIdentity(searchResult: viewed)
    storage.set(try JSONEncoder().encode(identity), forKey: SelectedPlayerIdentity.storageKey)
    let anonymous = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let selected = FestivalSession(
        factory: { throw FestivalAPIError.invalidResource },
        selectionStorage: storage
    )
    #expect(selected.selectedPlayer?.accountId == viewed.accountId)
    #expect(selected.selectedPlayerScores.isEmpty)

    for size in [CGSize(width: 390, height: 844), CGSize(width: 820, height: 1180)] {
        let initial = try profileSheetImage(session: anonymous, size: size)
        let chosen = try profileSheetImage(session: selected, size: size)
        let scale = CGFloat(initial.width) / size.width
        #expect((1...3).contains(scale))
        #expect(abs(CGFloat(initial.height) / size.height - scale) < 0.02)
        #expect(chosen.width == initial.width && chosen.height == initial.height)
        let anonymousPixels = nativeHostedControlPixels(initial)
        let chosenPixels = nativeHostedControlPixels(chosen)
        #expect(anonymousPixels.bright > 20 && anonymousPixels.selected > 40)
        #expect(chosenPixels.bright > anonymousPixels.bright)
        #expect(chosenPixels.selected > 40)
        #expect(anonymousPixels.placeholder == 0 && chosenPixels.placeholder == 0)
        let first = try nativeHostedPNG(
            initial, filename: "profile-anonymous-\(Int(size.width)).png",
            environment: "FST_PROFILE_RENDER_OUT"
        )
        let second = try nativeHostedPNG(
            chosen, filename: "profile-selected-\(Int(size.width)).png",
            environment: "FST_PROFILE_RENDER_OUT"
        )
        #expect(first != second)
    }

    let largeText = try profileSheetImage(
        session: selected, size: CGSize(width: 390, height: 844),
        typeSize: .accessibility5
    )
    #expect(abs(CGFloat(largeText.width) / 390
        - CGFloat(largeText.height) / 844) < 0.02)
    let largePixels = nativeHostedControlPixels(largeText)
    #expect(largePixels.bright > 20 && largePixels.selected > 40)
    #expect(largePixels.placeholder == 0)
    _ = try nativeHostedPNG(
        largeText, filename: "profile-selected-ax5.png",
        environment: "FST_PROFILE_RENDER_OUT"
    )
}

/// The same root profile action paints a real selected name rather than a generic icon.
@MainActor
@Test func profileActionPaintsDistinctSelectedAndAnonymousLabels() throws {
    let suiteName = "fst-profile-action-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    let result = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
    {"accountId":"fixture-player-2","displayName":"Fixture Player 2"}
    """.utf8))
    storage.set(
        try JSONEncoder().encode(SelectedPlayerIdentity(searchResult: result)),
        forKey: SelectedPlayerIdentity.storageKey
    )
    let anonymous = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let selected = FestivalSession(
        factory: { throw FestivalAPIError.invalidResource }, selectionStorage: storage
    )
    func image(for session: FestivalSession) throws -> CGImage {
        let renderer = ImageRenderer(content:
            ProfileActionButton(session: session, onPress: {})
                .preferredColorScheme(.dark)
                .tint(BrandTokens.accentBlue)
                .frame(width: 260, height: 64)
                .background(BrandTokens.cardBackground)
        )
        renderer.scale = 1
        return try #require(renderer.cgImage)
    }
    let initial = try image(for: anonymous)
    let chosen = try image(for: selected)
    #expect(initial.width == 260 && chosen.width == 260)
    #expect(paintedPixels(near: (45, 130, 230), in: chosen, sampleStep: 1) > 20)
    let first = try #require(
        NSBitmapImageRep(cgImage: initial).representation(using: .png, properties: [:])
    )
    let second = try #require(
        NSBitmapImageRep(cgImage: chosen).representation(using: .png, properties: [:])
    )
    #expect(first != second)
}

/// Traverse only real AppKit controls, never SwiftUI's rendered placeholder pixels.
///
/// - Parameter view: Offscreen native profile Form subtree.
/// - Returns: Native text fields exposed by the hosted view hierarchy.
@MainActor
private func profileTextFields(in view: NSView) -> [NSTextField] {
    let current = (view as? NSTextField).map { [$0] } ?? []
    return current + view.subviews.flatMap { profileTextFields(in: $0) }
}

/// Locate the actual native Players/Bands scope rather than simulating view state.
///
/// - Parameter view: AppKit-hosted search sheet.
/// - Returns: Native segmented pickers whose real actions can be sent.
@MainActor
private func profileScopePickers(in view: NSView) -> [NSSegmentedControl] {
    let current = (view as? NSSegmentedControl).map { [$0] } ?? []
    return current + view.subviews.flatMap { profileScopePickers(in: $0) }
}

private enum HostedSearchOutcome: Sendable {
    case results
    case empty
    case denied
}

private actor HostedAccountSearchTransport: HTTPTransport {
    let outcome: HostedSearchOutcome
    private var terms: [String] = []
    private var paths: [String] = []

    /// Distinguish a real empty envelope from a blocked public search.
    ///
    /// - Parameter outcome: Fixture results, validated empty or HTTP 403.
    init(outcome: HostedSearchOutcome) { self.outcome = outcome }

    /// Reject every request except one unprivileged, bounded synthetic search GET.
    ///
    /// - Parameter request: Operational public name search from the native form.
    /// - Returns: One original fixture-shaped, merely viewed player identity.
    /// - Throws: A write, selected header, key, wrong term, route or limit.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        if let path = request.url?.path { paths.append(path) }
        guard let url = request.url, request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil,
              request.allHTTPHeaderFields?.keys.contains(where: {
                  $0.lowercased().hasPrefix("x-fst-selected-")
              }) != true, url.path == "/api/account/search",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "q" })?.value == "Fixture",
              items.first(where: { $0.name == "limit" })?.value == "10" else {
            throw FestivalAPIError.invalidResource
        }
        terms.append("Fixture")
        switch outcome {
        case .results:
            return HTTPResult(status: 200, data: Data("""
            {"results":[{"accountId":"fixture-player-1","displayName":"Fixture Player 1"}]}
            """.utf8))
        case .empty:
            return HTTPResult(status: 200, data: Data(#"{"results":[]}"#.utf8))
        case .denied:
            return HTTPResult(status: 403, data: Data(#"{"status":"denied"}"#.utf8))
        }
    }

    /// Require the real search task to issue exactly one matching public GET.
    ///
    /// - Returns: Validated synthetic query terms actually requested.
    func recordedTerms() -> [String] { terms }

    /// Disallow even a rejected band, stats or selected-header GET.
    ///
    /// - Returns: Every route sent to the strict local transport.
    func recordedPaths() -> [String] { paths }
}

/// Change the actual AppKit search field and require a source-debounced result.
@MainActor
@Test func profileSheetExposesNativeSearchField() async throws {
    let transport = HostedAccountSearchTransport(outcome: .results)
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let host = nativeHostedView(
        ProfileSelectionSheet(session: session)
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue),
        size: CGSize(width: 390, height: 844)
    )
    let initial = try nativeHostedImage(host)
    let field = try #require(profileTextFields(in: host).first)
    #expect(field.stringValue.isEmpty)
    field.stringValue = "Fixture"
    field.delegate?.controlTextDidChange?(
        Notification(name: NSControl.textDidChangeNotification, object: field)
    )
    field.sendAction(field.action, to: field.target)
    for _ in 0..<30 {
        if !(await transport.recordedTerms()).isEmpty { break }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(await transport.recordedTerms() == ["Fixture"])
    let result = try nativeHostedImage(host)
    let before = try nativeHostedPNG(
        initial, filename: "profile-before-search.png",
        environment: "FST_PROFILE_RENDER_OUT"
    )
    let found = try nativeHostedPNG(
        result, filename: "profile-after-search.png",
        environment: "FST_PROFILE_RENDER_OUT"
    )
    #expect(before != found)
    #expect(session.selectedPlayer == nil)
    let clear = try #require(profileTextFields(in: host).first)
    clear.stringValue = ""
    clear.delegate?.controlTextDidChange?(
        Notification(name: NSControl.textDidChangeNotification, object: clear)
    )
    clear.sendAction(clear.action, to: clear.target)
    try await Task.sleep(for: .milliseconds(300))
    #expect(await transport.recordedPaths() == ["/api/account/search"])
    let reset = try nativeHostedPNG(
        nativeHostedImage(host), filename: "profile-cleared-search.png",
        environment: "FST_PROFILE_RENDER_OUT"
    )
    #expect(reset != found)
    #expect(session.selectedPlayer == nil)
}

/// Same query must show distinct source-like empty and actual HTTP 403 responses.
@MainActor
@Test func profileSheetPaintsEmptySearchSeparatelyFromAccessDenied() async throws {
    var images: [Data] = []
    for outcome: HostedSearchOutcome in [.empty, .denied] {
        let transport = HostedAccountSearchTransport(outcome: outcome)
        let client = try FestivalAPI(transport: transport)
        let session = FestivalSession(factory: { client })
        let host = nativeHostedView(
            ProfileSelectionSheet(session: session)
                .preferredColorScheme(.dark)
                .tint(BrandTokens.accentBlue),
            size: CGSize(width: 390, height: 844)
        )
        let field = try #require(profileTextFields(in: host).first)
        field.stringValue = "Fixture"
        field.delegate?.controlTextDidChange?(
            Notification(name: NSControl.textDidChangeNotification, object: field)
        )
        field.sendAction(field.action, to: field.target)
        for _ in 0..<30 {
            if !(await transport.recordedTerms()).isEmpty { break }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(await transport.recordedTerms() == ["Fixture"])
        try await Task.sleep(for: .milliseconds(50))
        let image = try nativeHostedImage(host)
        let gold = nativeHostedStatusPixels(image).gold
        if outcome == .denied {
            #expect(gold > 10)
        } else {
            #expect(gold == 0)
        }
        #expect(session.selectedPlayer == nil)
        let name = outcome == .denied ? "denied" : "empty"
        images.append(try nativeHostedPNG(
            image, filename: "profile-search-\(name).png",
            environment: "FST_PROFILE_RENDER_OUT"
        ))
    }
    #expect(images[0] != images[1])
}

/// Switching to Bands cannot make the native client issue its write-capable GET.
///
/// The search field itself now stays visible in Bands scope (its prompt switches to
/// "Find Band", matching the Players/Bands scope-aware search pill requirement) but
/// is disabled, with an honest gating explanation below it — it no longer disappears
/// outright the way the old Bands `Text` placeholder implied.
@MainActor
@Test func profileBandScopeKeepsUnsafeSearchBlocked() async throws {
    let transport = HostedAccountSearchTransport(outcome: .results)
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let host = nativeHostedView(
        ProfileSelectionSheet(session: session)
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue),
        size: CGSize(width: 390, height: 844)
    )
    let before = try nativeHostedPNG(
        nativeHostedImage(host), filename: "profile-players-scope.png",
        environment: "FST_PROFILE_RENDER_OUT"
    )
    let playersField = try #require(profileTextFields(in: host).first)
    #expect(playersField.isEnabled)
    let picker = try #require(profileScopePickers(in: host).first)
    #expect(picker.segmentCount == 2)
    picker.selectedSegment = 1
    picker.sendAction(picker.action, to: picker.target)
    for _ in 0..<20 {
        if profileTextFields(in: host).first?.isEnabled == false { break }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }
    let bandsField = try #require(profileTextFields(in: host).first)
    #expect(!bandsField.isEnabled)
    #expect((await transport.recordedPaths()).isEmpty)
    let image = try nativeHostedImage(host)
    #expect(nativeHostedStatusPixels(image).gold == 0)
    let after = try nativeHostedPNG(
        image, filename: "profile-bands-blocked.png",
        environment: "FST_PROFILE_RENDER_OUT"
    )
    #expect(before != after)
    picker.selectedSegment = 0
    picker.sendAction(picker.action, to: picker.target)
    for _ in 0..<20 {
        if profileTextFields(in: host).first?.isEnabled == true { break }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(try #require(profileTextFields(in: host).first).isEnabled)
    #expect((await transport.recordedPaths()).isEmpty)
    let restored = try nativeHostedPNG(
        nativeHostedImage(host), filename: "profile-players-restored.png",
        environment: "FST_PROFILE_RENDER_OUT"
    )
    #expect(restored != after)
}
#endif
