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

/// Initial and stored-selection states paint the same readable finder at two widths.
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
        // No selected-profile ("Public Profile") container: the web's modal has none,
        // so a stored selection paints the same finder as the anonymous state.
        #expect(chosenPixels.bright == anonymousPixels.bright)
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
        #expect(first == second)
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

/// Locate the actual native All/Players/Bands scope rather than simulating view state.
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
    /// - Parameter outcome: Fixture results, validated empty or HTTP 403 (players only;
    ///   bands then answer empty).
    init(outcome: HostedSearchOutcome) { self.outcome = outcome }

    /// Reject every request except the unprivileged, bounded synthetic player and band
    /// search GETs the Profiles sheet sends together (issue #600).
    ///
    /// - Parameter request: Operational public name search from the native form.
    /// - Returns: One fixture-shaped player or band, an empty envelope, or HTTP 403.
    /// - Throws: A write, selected header, key, wrong term, route, page or limit.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        if let path = request.url?.path { paths.append(path) }
        guard let url = request.url, request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil,
              request.allHTTPHeaderFields?.keys.contains(where: {
                  $0.lowercased().hasPrefix("x-fst-selected-")
              }) != true,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.first(where: { $0.name == "q" })?.value == "Fixture" else {
            throw FestivalAPIError.invalidResource
        }
        let value = { (name: String) in items.first(where: { $0.name == name })?.value }
        switch url.path {
        case "/api/account/search" where value("limit") == "10":
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
        case "/api/bands/search" where value("page") == "1" && value("pageSize") == "10":
            terms.append("Fixture")
            let band = """
            {"bandId":"fixture-band-1","teamKey":"fixture-player-1:fixture-player-2",\
            "bandType":"Band_Duets","appearanceCount":12,"members":[\
            {"accountId":"fixture-player-1","displayName":"Fixture Player 1","instruments":["Solo_Guitar"]},\
            {"accountId":"fixture-player-2","displayName":"Fixture Player 2","instruments":["Solo_Bass"]}]}
            """
            let results = outcome == .results ? band : ""
            return HTTPResult(status: 200, data: Data("""
            {"query":"Fixture","normalizedQuery":"fixture","rankBy":"adjusted","page":1,\
            "pageSize":10,"totalCount":\(results.isEmpty ? 0 : 1),"isAmbiguous":false,\
            "needsDisambiguation":false,"interpretations":[],"results":[\(results)]}
            """.utf8))
        default:
            throw FestivalAPIError.invalidResource
        }
    }

    /// Validated synthetic query terms actually requested, one per player or band read.
    ///
    /// - Returns: The terms, in arrival order.
    func recordedTerms() -> [String] { terms }

    /// Disallow even a rejected stats, sync-status or selected-header GET.
    ///
    /// - Returns: Every route sent to the strict local transport, sorted.
    func recordedPaths() -> [String] { paths.sorted() }
}

/// Type `text` into the hosted sheet's native field and wait for both searches.
///
/// - Parameters:
///   - text: Query to enter.
///   - host: AppKit-hosted profile sheet.
///   - transport: The strict transport recording the reads.
/// - Throws: A missing field.
@MainActor
private func enterProfileQuery(
    _ text: String, in host: NSView, transport: HostedAccountSearchTransport
) async throws {
    let field = try #require(profileTextFields(in: host).first)
    field.stringValue = text
    field.delegate?.controlTextDidChange?(
        Notification(name: NSControl.textDidChangeNotification, object: field)
    )
    field.sendAction(field.action, to: field.target)
    for _ in 0..<40 {
        if (await transport.recordedTerms()).count >= 2 { break }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }
}

/// Both public profile searches, players and bands (issue #600).
private let profileSearchPaths = ["/api/account/search", "/api/bands/search"]

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
    // A never-shown window realizes the results List's rows (AppKit table cells).
    let window = nativeHostedWindow(host, size: CGSize(width: 390, height: 844))
    defer { withExtendedLifetime(window) {} }
    let initial = try nativeHostedImage(host)
    let field = try #require(profileTextFields(in: host).first)
    #expect(field.stringValue.isEmpty)
    #expect(field.placeholderString == "Search players or bands")
    try await enterProfileQuery("Fixture", in: host, transport: transport)
    #expect(await transport.recordedTerms() == ["Fixture", "Fixture"])
    try await Task.sleep(for: .milliseconds(50))
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
    #expect(await transport.recordedPaths() == profileSearchPaths)
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
        let window = nativeHostedWindow(host, size: CGSize(width: 390, height: 844))
        defer { withExtendedLifetime(window) {} }
        try await enterProfileQuery("Fixture", in: host, transport: transport)
        #expect(await transport.recordedTerms() == ["Fixture", "Fixture"])
        // Results fade in (web stagger), so poll until the settled frame paints.
        var image = try nativeHostedImage(host)
        for _ in 0..<30 where outcome == .denied && nativeHostedStatusPixels(image).gold <= 10 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            image = try nativeHostedImage(host)
        }
        if outcome == .empty { try await Task.sleep(for: .milliseconds(300)) }
        let gold = nativeHostedStatusPixels(image).gold
        let ids = nativeHostedAccessibility(host).identifiers
        if outcome == .denied {
            #expect(gold > 10)
            #expect(ids.contains("fst.profile.players-error"))
            #expect(!ids.contains("fst.profile.hint"))
        } else {
            #expect(gold == 0)
            #expect(ids.contains("fst.profile.hint"))
            #expect(!ids.contains("fst.profile.players-error"))
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

/// Issue #600: a native All · Players · Bands scope bar starts on All with players and
/// bands searched together; Players and Bands only narrow what shows, without another
/// read, and the Bands scope shows band results rather than a gate.
@MainActor
@Test func profileScopeBarStartsOnAllAndNarrowsWithoutRefetching() async throws {
    let transport = HostedAccountSearchTransport(outcome: .results)
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let host = nativeHostedView(
        ProfileSelectionSheet(session: session)
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue),
        size: CGSize(width: 390, height: 844)
    )
    // A never-shown window realizes the results List's rows (AppKit table cells).
    let window = nativeHostedWindow(host, size: CGSize(width: 390, height: 844))
    defer { withExtendedLifetime(window) {} }
    let picker = try #require(profileScopePickers(in: host).first)
    #expect(picker.segmentCount == 3)
    #expect((0..<3).map { picker.label(forSegment: $0) } == ["All", "Players", "Bands"])
    #expect(picker.selectedSegment == 0)
    #expect(try #require(profileTextFields(in: host).first).isEnabled)
    try await enterProfileQuery("Fixture", in: host, transport: transport)
    #expect(await transport.recordedPaths() == profileSearchPaths)
    try await Task.sleep(for: .milliseconds(100))
    let found = nativeHostedAccessibility(host).identifiers
    #expect(found.contains("fst.profile.result.fixture-player-1"))
    #expect(found.contains("fst.profile.result.band"))
    #expect(found.contains("fst.profile.section.players"))
    #expect(found.contains("fst.profile.section.bands"))
    #expect(!found.contains("fst.profile.bands-unavailable"))
    let all = try nativeHostedPNG(
        nativeHostedImage(host), filename: "profile-all-scope.png",
        environment: "FST_PROFILE_RENDER_OUT"
    )
    var images = [all]
    for (segment, name, prompt) in [
        (2, "bands", "Search bands"), (1, "players", "Search players"),
    ] {
        picker.selectedSegment = segment
        picker.sendAction(picker.action, to: picker.target)
        for _ in 0..<20 {
            if profileTextFields(in: host).first?.placeholderString == prompt { break }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(profileTextFields(in: host).first?.placeholderString == prompt)
        #expect(try #require(profileTextFields(in: host).first).isEnabled)
        try await Task.sleep(for: .milliseconds(100))
        let ids = nativeHostedAccessibility(host).identifiers
        #expect(ids.contains("fst.profile.result.band") == (name == "bands"))
        #expect(ids.contains("fst.profile.result.fixture-player-1") == (name == "players"))
        #expect(!ids.contains(where: { $0.hasPrefix("fst.profile.section.") }))
        let image = try nativeHostedImage(host)
        #expect(nativeHostedStatusPixels(image).gold == 0)
        images.append(try nativeHostedPNG(
            image, filename: "profile-\(name)-scope.png",
            environment: "FST_PROFILE_RENDER_OUT"
        ))
    }
    #expect(Set(images).count == 3, "All, Bands and Players painted the same results")
    #expect(await transport.recordedPaths() == profileSearchPaths)
    #expect(session.selectedPlayer == nil)
}
#endif
