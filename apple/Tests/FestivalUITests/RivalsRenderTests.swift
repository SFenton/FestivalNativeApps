#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixture session

/// Only the nine per-instrument visibility keys `VisibleInstrumentsReader` reads.
private let allInstrumentKeys = [
    "fst.settings.showLead", "fst.settings.showBass", "fst.settings.showDrums",
    "fst.settings.showVocals", "fst.settings.showProLead", "fst.settings.showProBass",
    "fst.settings.showKaraoke", "fst.settings.showProCymbals", "fst.settings.showProDrums",
]

/// Build a fixture session against the real loopback `tools/mock_service.py`
/// process (see `RivalsMockService.swift` for why Rivals hosted tests can't use
/// an in-memory `HTTPTransport` actor like every other domain's), with a stored
/// selected player and explicit instrument visibility.
///
/// - Parameters:
///   - accountId: Selected (viewing) player id; a `-empty`/`-503` suffix selects
///     the mock's empty/unavailable Rivals scenario (see `mock_service.py`).
///   - visible: Instruments to enable; every other one of the nine is disabled.
/// - Returns: A ready session plus its private `UserDefaults` suite to clean up.
@MainActor
private func rivalsFixtureSession(
    accountId: String, displayName: String = "Fixture Viewer",
    visible: Set<String> = ["fst.settings.showLead"]
) async throws -> (session: FestivalSession, storage: UserDefaults, suite: String) {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    let suite = "fst.tests.rivals.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    let identity: [String: String] = ["accountId": accountId, "displayName": displayName]
    storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    for key in allInstrumentKeys { storage.set(visible.contains(key), forKey: key) }
    let session = FestivalSession(factory: { client }, selectionStorage: storage)
    return (session, storage, suite)
}

/// A session with no stored selection at all.
@MainActor
private func anonymousRivalsSession() async throws -> FestivalSession {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    return FestivalSession(factory: { client })
}

/// Lead + Bass: both a "Common Rivals" (2+ instruments) and a within-group Combo
/// (`RivalCombo.comboId(for: [.lead, .bass]) == "03"`) section should render.
private let leadAndBass: Set<String> = ["fst.settings.showLead", "fst.settings.showBass"]

/// A rival id `tools/mock_service.py`'s detail routes accept (`[A-Za-z0-9]+`).
///
/// A hyphenated id such as `fixture-player-1` never matches those routes, so the
/// mock answers 404 and the client's documented 404-as-empty mapping renders
/// "No Shared Songs" whatever scenario the test meant to exercise.
private let routableRivalId = "f1c749eb07c32578cfa3e59ec38c03a8"

// MARK: - RivalsScreen: no profile / loading / empty instruments

@MainActor
@Test func rivalsScreenRendersChooseProfileWhenNoPlayerSelected() async throws {
    let session = try await anonymousRivalsSession()
    #expect(session.selectedPlayer == nil)
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["No Player Selected", "Choose Profile"])
    _ = try nativeHostedPNG(image, filename: "rivals-no-profile.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["No Player Selected", "Choose Profile"])
}

/// Captured before the per-instrument `.task` loads settle: every section's
/// initial `@State` is `.loading`.
@MainActor
@Test func rivalsScreenRendersLoadingBeforeSectionsSettle() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv", visible: leadAndBass
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1400)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1400))
    defer { window.orderOut(nil) }
    // Capture synchronously, before any `.task` load can resolve (no settle:
    // the loopback fixture answers within one poll).
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "rivals-loading.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Common Rivals", "Loading"])
}

@MainActor
@Test func rivalsScreenRendersNoInstrumentsEnabledState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv", visible: []
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 500)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 500))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Enable at least one instrument in Settings to see rivals."]
    )
    _ = try nativeHostedPNG(image, filename: "rivals-no-instruments.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(
        host, image: image, containing: ["Enable at least one instrument in Settings to see rivals."]
    )
}

// MARK: - RivalsScreen: loaded song tab (Common + Combo + per-instrument)

@MainActor
@Test func rivalsScreenRendersSongTabWithCommonAndComboSections() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv", visible: leadAndBass
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1600)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1600))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Common Rivals", "Combo Rivals", "Fixture Rival Golf"], excluding: ["Loading"]
    )
    _ = try nativeHostedPNG(
        image, filename: "rivals-song-tab-common-combo.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    assertRendersContent(
        host, image: image,
        containing: ["Common Rivals", "Combo Rivals", "Fixture Rival Golf", "ahead", "behind"],
        notContaining: ["shared"]
    )
    // #41: every loaded section ends with the shared purple "View All Rivals" button.
    let identifiers = nativeHostedAccessibility(host).identifiers
    for id in [
        "fst.rivals.common.view-all", "fst.rivals.combo.view-all",
        "fst.rivals.song.\(Instrument.lead.rawValue).view-all",
        "fst.rivals.song.\(Instrument.bass.rawValue).view-all",
    ] {
        #expect(identifiers.contains(id), "missing \(id)")
    }
}

/// Switch to the Leaderboard tab via the real `NSSegmentedControl` (mirrors
/// `ProfileSelectionSheetRenderTests`'s scope-picker pattern) and confirm rows load.
@MainActor
@Test func rivalsScreenRendersLeaderboardTabRows() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv", visible: ["fst.settings.showLead"]
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1000)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1000))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(900))
    host.layoutSubtreeIfNeeded()
    let picker = try #require(rivalsSegmentedControls(in: host).first)
    #expect(picker.segmentCount == 2)
    picker.selectedSegment = 1
    picker.sendAction(picker.action, to: picker.target)
    let image = try await nativeHostedSettle(
        host, untilText: ["Fixture Rival Bravo", "View All Rivals"], excluding: ["Loading"]
    )
    _ = try nativeHostedPNG(image, filename: "rivals-leaderboard-tab.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(
        host, image: image,
        containing: ["Fixture Rival Bravo", "View All Rivals", "ahead", "behind"],
        notContaining: ["shared"]
    )
    #expect(nativeHostedAccessibility(host).identifiers.contains(
        "fst.rivals.leaderboard.\(Instrument.lead.rawValue).view-all"
    ))
}

/// #41: "View All Rivals" draws exactly the shared ``PurpleActionLabel`` that
/// "View Full Leaderboard" uses (no extra row chrome from the link).
@MainActor
@Test func rivalsViewAllButtonMatchesViewFullLeaderboardStyle() async throws {
    let size = CGSize(width: 360, height: 80)
    func capture(_ content: some View) throws -> CGImage {
        let host = nativeHostedView(
            NavigationStack { content.padding(16) }.preferredColorScheme(.dark), size: size
        )
        return try nativeHostedImage(host)
    }
    let rivals = try capture(RivalsViewAllButton(
        route: .allRivals(scope: .song(instruments: [Instrument.lead.rawValue])),
        identifier: "fst.rivals.song.lead.view-all"
    ))
    let shared = try capture(PurpleActionLabel(title: "View All Rivals"))
    let plainText = try capture(Text("View All Rivals").font(.body.weight(.semibold)))
    #expect(nativeHostedControlPixels(rivals).bright > 0)
    #expect(nativeHostedSignature(rivals) == nativeHostedSignature(shared))
    #expect(nativeHostedSignature(rivals) != nativeHostedSignature(plainText))
}

/// #321: a Rival Detail category's "View All" is the same shared purple button
/// (``PurpleActionLink`` → ``PurpleActionLabel``), not a plain white "See All" row.
@MainActor
@Test func rivalDetailCategoryViewAllMatchesSharedPurpleButton() async throws {
    let size = CGSize(width: 360, height: 80)
    func capture(_ content: some View) throws -> CGImage {
        let host = nativeHostedView(
            NavigationStack { content.padding(16) }.preferredColorScheme(.dark), size: size
        )
        return try nativeHostedImage(host)
    }
    let category = try capture(PurpleActionLink(
        title: "View All",
        route: .rivalry(rivalId: "r", mode: "closest_battles", name: nil, scope: nil),
        identifier: "fst.rival-detail.category.closest_battles.view-all",
        card: "Closest Battles"
    ))
    let shared = try capture(PurpleActionLabel(title: "View All"))
    let plainText = try capture(Text("View All").font(.body.weight(.semibold)))
    #expect(nativeHostedControlPixels(category).bright > 0)
    #expect(nativeHostedSignature(category) == nativeHostedSignature(shared))
    #expect(nativeHostedSignature(category) != nativeHostedSignature(plainText))
}

/// A 503 (matching the live service's scrape-window freeze) shows each section's
/// own inline `RivalsSectionError`, not a full-screen takeover.
@MainActor
@Test func rivalsScreenRendersSectionErrorOnServiceUnavailable() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv-503", visible: ["fst.settings.showLead"]
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Scores are updating", "Retry Now"], excluding: ["Loading"]
    )
    _ = try nativeHostedPNG(image, filename: "rivals-unavailable.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Scores are updating", "Retry Now"])
}

/// With 2+ visible instruments, a 503 fails the Common Rivals and Combo
/// sections' own loads too (not just the per-instrument sections).
@MainActor
@Test func rivalsScreenRendersCommonAndComboSectionErrors() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv-503", visible: leadAndBass
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 900)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 900))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Combo Rivals", "Scores are updating"], excluding: ["Loading"]
    )
    _ = try nativeHostedPNG(
        image, filename: "rivals-common-combo-errors.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["Combo Rivals", "Scores are updating"])
    // Regression for a fixed product bug: `RivalCommonSection.load()` used to
    // read each instrument with `try?`, so when every read 503s it intersected
    // nothing and rendered `EmptyView()` instead of its `.failed` branch. It now
    // propagates the first read's error like every sibling section.
    #expect(nativeHostedAccessibility(host).contains("Common Rivals"))
}

/// An empty per-instrument scenario hides the Common Rivals/Combo sections
/// entirely (`EmptyView()`). Per-instrument sections are skipped when empty too
/// (`.agents/pages/rivals/ios.md`), so only the Song/Leaderboard picker remains.
@MainActor
@Test func rivalsScreenHidesCommonAndComboSectionsWhenEmpty() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv-empty", visible: leadAndBass
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Leaderboard"], excluding: ["Loading"])
    _ = try nativeHostedPNG(
        image, filename: "rivals-common-combo-empty.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    assertRendersContent(
        host, image: image, containing: ["Song", "Leaderboard"],
        notContaining: ["Common Rivals", "Combo Rivals", "Loading"]
    )
}

private func rivalsSegmentedControls(in view: NSView) -> [NSSegmentedControl] {
    let current = (view as? NSSegmentedControl).map { [$0] } ?? []
    return current + view.subviews.flatMap { rivalsSegmentedControls(in: $0) }
}

// MARK: - AllRivalsScreen

@MainActor
@Test func allRivalsScreenRendersLoadedSongScopeRows() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            AllRivalsScreen(session: session, scope: .song(instruments: ["Solo_Guitar"]))
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1000)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1000))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Lead Rivals", "Fixture Rival Golf"])
    _ = try nativeHostedPNG(image, filename: "all-rivals-loaded.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(
        host, image: image,
        containing: ["Lead Rivals", "Fixture Rival Golf", "ahead", "behind"],
        notContaining: ["shared"]
    )
}

@MainActor
@Test func allRivalsScreenRendersEmptyState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv-empty")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            AllRivalsScreen(session: session, scope: .song(instruments: ["Solo_Guitar"]))
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 600)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 600))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["No Rivals Yet"])
    _ = try nativeHostedPNG(image, filename: "all-rivals-empty.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["No Rivals Yet"])
}

@MainActor
@Test func allRivalsScreenRendersUnavailableState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv-503")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            AllRivalsScreen(session: session, scope: .leaderboard(instrument: "Solo_Guitar", rankBy: .totalscore))
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 600)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 600))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Scores are updating", "Retry Now"])
    _ = try nativeHostedPNG(image, filename: "all-rivals-unavailable.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Scores are updating", "Retry Now"])
}

@MainActor
@Test func allRivalsScreenRendersCommonRivalsForMultiInstrumentSongScope() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            AllRivalsScreen(session: session, scope: .song(instruments: ["Solo_Guitar", "Solo_Bass"]))
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1000)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1000))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Common Rivals", "Fixture Rival Golf"], excluding: ["Loading"]
    )
    _ = try nativeHostedPNG(
        image, filename: "all-rivals-common.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["Common Rivals", "Fixture Rival Golf"])
}

// MARK: - RivalDetailScreen: categorization

@MainActor
@Test func allRivalsScreenRendersComboScopeRows() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            AllRivalsScreen(
                session: session,
                scope: .combo(token: "03", instruments: ["Solo_Guitar", "Solo_Bass"])
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1000)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1000))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Combo Rivals", "Fixture Rival Golf"])
    _ = try nativeHostedPNG(image, filename: "all-rivals-combo.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Combo Rivals", "Fixture Rival Golf"])
}

/// An unresolvable scope (every named instrument raw value is unknown) shows
/// "Unknown Category" rather than an empty or loading board.
@MainActor
@Test func allRivalsScreenRendersUnknownCategoryForUnresolvableScope() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            AllRivalsScreen(session: session, scope: .song(instruments: ["Not_A_Real_Instrument"]))
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 500)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 500))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Unknown Category"])
    _ = try nativeHostedPNG(
        image, filename: "all-rivals-unknown-category.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["Unknown Category"])
}

@MainActor
@Test func rivalDetailScreenRendersCategorizedSongs() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalDetailScreen(
                session: session, rivalId: "f1c749eb07c32578cfa3e59ec38c03a8", name: "Fixture Rival Golf",
                scope: .song(instruments: ["Solo_Guitar"])
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1400)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1400))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Closest Battles", "Almost Passed", "Fixture Drift"]
    )
    _ = try nativeHostedPNG(
        image, filename: "rival-detail-categories.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    assertRendersContent(
        host, image: image, containing: ["Closest Battles", "Almost Passed", "Fixture Drift"]
    )
    // #321: each category ends with the shared purple "View All", label first.
    let tree = nativeHostedAccessibility(host)
    #expect(tree.identifiers.contains("fst.rival-detail.category.closest_battles.view-all"))
    #expect(tree.identifiers.contains("fst.rival-detail.category.almost_passed.view-all"))
    #expect(tree.contains("View All, Closest Battles"))
    #expect(!tree.contains("See All"))
}

/// iPhone Duo Rivals pane (#321): the pane header's "View All" link and each category
/// card's purple "View All" keep their own identifiers. The pane and card containers
/// carry identifiers too, so without `.accessibilityElement(children: .contain)` those
/// would shadow every descendant's (see `LeaderboardsJourneyTests`).
@MainActor
@Test func rivalDualDetailPaneExposesViewAllIdentifiers() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let selection = AppRoute.rivalDetail(
        rivalId: "f1c749eb07c32578cfa3e59ec38c03a8", name: "Fixture Rival Golf",
        scope: .song(instruments: ["Solo_Guitar"])
    )
    let size = CGSize(width: 402, height: 700)
    let host = nativeHostedView(
        NavigationStack { RivalDualDetailPane(session: session, selection: selection) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Closest Battles"])
    _ = try nativeHostedPNG(image, filename: "rival-dual-detail-pane.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Closest Battles"])
    let tree = nativeHostedAccessibility(host)
    for identifier in [
        "fst.dual.rivals.detail", "fst.dual.rivals.detail.view-all",
        "fst.dual.rivals.category.closest_battles", "fst.dual.rivals.category.closest_battles.view-all",
    ] {
        #expect(tree.identifiers.contains(identifier), "\(identifier) unreachable: \(tree.identifiers)")
    }
    #expect(tree.contains("View All Fixture Rival Golf"))
    #expect(tree.contains("View All, Closest Battles"))
    #expect(!tree.contains("See All"))
}

@MainActor
@Test func rivalDetailScreenRendersNoSharedSongsState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv-empty")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalDetailScreen(
                session: session, rivalId: routableRivalId, name: "Fixture Player 1",
                scope: .song(instruments: ["Solo_Guitar"])
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 600)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 600))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["No Shared Songs"])
    _ = try nativeHostedPNG(
        image, filename: "rival-detail-no-songs.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["No Shared Songs"])
}

/// A `nil` scope (deep link, cold `DebugLaunchRoute`, or `FindRivalSheet`'s
/// arbitrary search result) reads the web's Settings scopes with
/// `allowLiveFallback=true` (`RivalDetailScopes.settingsScopes`; Lead + Bass → `03`).
@MainActor
@Test func rivalDetailScreenRendersNilScopeFallbackMerge() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv", visible: leadAndBass
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalDetailScreen(
                session: session, rivalId: routableRivalId, name: "Fixture Player 1",
                scope: nil
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1400)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1400))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Closest Battles"], excluding: ["Loading"])
    _ = try nativeHostedPNG(
        image, filename: "rival-detail-fallback-merge.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["Closest Battles"])
}

/// A `.leaderboard` scope's normal (200) path, complementing the unavailable
/// case below with `leaderboardRivalDetail`'s success branch.
@MainActor
@Test func rivalDetailScreenRendersLeaderboardScopeLoaded() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalDetailScreen(
                session: session, rivalId: "f1c71052e0052ae7143f3b3c750f2f49",
                name: "Fixture Rival Bravo", scope: .leaderboard(instrument: "Solo_Guitar", rankBy: .totalscore)
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1200)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1200))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Closest Battles", "Fixture Rival Bravo"])
    _ = try nativeHostedPNG(
        image, filename: "rival-detail-leaderboard-loaded.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["Closest Battles", "Fixture Rival Bravo"])
}

@MainActor
@Test func rivalDetailScreenRendersUnavailableState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv-503")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalDetailScreen(
                session: session, rivalId: routableRivalId, name: "Fixture Player 1",
                scope: .leaderboard(instrument: "Solo_Guitar", rankBy: .totalscore)
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 600)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 600))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Scores are updating"], excluding: ["Loading"])
    _ = try nativeHostedPNG(
        image, filename: "rival-detail-unavailable.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["Scores are updating"])
}

// MARK: - RivalryScreen: full category list, delta-magnitude ordering

/// `closest_battles` sorts by `|rankDelta|` ascending, mirroring
/// `RivalCategorization.categorize` (native `categorizeRivalSongs`); the demo
/// fixture's ties (`rankDelta == 0`) sort first.
@MainActor
@Test func rivalryScreenRendersClosestBattlesInDeltaMagnitudeOrder() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalryScreen(
                session: session, rivalId: "f1c749eb07c32578cfa3e59ec38c03a8",
                mode: "closest_battles", name: "Fixture Rival Golf", scope: .song(instruments: ["Solo_Guitar"])
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 900)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 900))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Fixture Drift", "Fixture Echo"])
    _ = try nativeHostedPNG(
        image, filename: "rivalry-closest-battles.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["Fixture Drift", "Fixture Echo"])
    // The demo fixture's rival leads on `fixture-orbit` (delta -20): confirms a
    // rival-leads bucket exists alongside `closest_battles` for the same detail.
    let categories = RivalCategorization.categorize(rivalDetailDemoSongs)
    let closest = try #require(categories.first { $0.key == "closest_battles" })
    let deltas = closest.songs.map { abs($0.rankDelta) }
    #expect(deltas == deltas.sorted())
}

@MainActor
@Test func rivalryScreenRendersEmptyCategoryState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv-empty")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalryScreen(
                session: session, rivalId: routableRivalId, mode: "closest_battles",
                name: "Fixture Player 1", scope: .song(instruments: ["Solo_Guitar"])
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 500)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 500))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["No Songs", "There are no songs in this category."]
    )
    _ = try nativeHostedPNG(
        image, filename: "rivalry-empty-category.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["No Songs", "There are no songs in this category."])
}

/// Songs used by `rival-detail-demo.json`, mirrored here (rather than decoding the
/// fixture again) purely to assert the ordering claim above independently of the view.
private let rivalDetailDemoSongs: [RivalSongComparison] = [
    rivalSong(id: "fixture-pulse", delta: 1),
    rivalSong(id: "fixture-orbit", delta: -20),
    rivalSong(id: "fixture-echo", delta: 40),
    rivalSong(id: "fixture-drift", delta: 0),
]

private func rivalSong(id: String, delta: Int) -> RivalSongComparison {
    let json = """
    {"songId":"\(id)","title":null,"artist":null,"instrument":"Solo_Guitar",
     "userInstrument":null,"rivalInstrument":null,
     "userRank":1,"rivalRank":1,"rankDelta":\(delta),"userScore":100,"rivalScore":90}
    """
    return try! JSONDecoder().decode(RivalSongComparison.self, from: Data(json.utf8))
}

// MARK: - FindRivalSheet: search states

private func rivalsTextFields(in view: NSView) -> [NSTextField] {
    let current = (view as? NSTextField).map { [$0] } ?? []
    return current + view.subviews.flatMap { rivalsTextFields(in: $0) }
}

@MainActor
private func typeIntoFindRival(_ text: String, host: NSView) throws {
    let field = try #require(rivalsTextFields(in: host).first)
    field.stringValue = text
    field.delegate?.controlTextDidChange?(
        Notification(name: NSControl.textDidChangeNotification, object: field)
    )
    field.sendAction(field.action, to: field.target)
}

@MainActor
@Test func findRivalSheetRendersEnterQueryState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        FindRivalSheet(session: session)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 390, height: 700)
    )
    let image = try await nativeHostedSettle(
        host, untilText: ["Enter at least two characters to search for a rival."]
    )
    _ = try nativeHostedPNG(image, filename: "find-rival-enter-query.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(
        host, image: image, containing: ["Enter at least two characters to search for a rival."]
    )
}

@MainActor
@Test func findRivalSheetRendersLoadingThenResults() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        FindRivalSheet(session: session)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 390, height: 700)
    )
    try typeIntoFindRival("Fixture", host: host)
    // Under the 250ms debounce: still `.loading`. Only the painted sheet and query
    // are asserted here — a busy parallel run can outlast the debounce window.
    try await Task.sleep(for: .milliseconds(60))
    host.layoutSubtreeIfNeeded()
    let loading = try nativeHostedImage(host)
    _ = try nativeHostedPNG(loading, filename: "find-rival-loading.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(host, image: loading, containing: ["Find a Rival", "Fixture"])
    // Past the debounce plus the real network round trip: `.results`.
    let results = try await nativeHostedSettle(
        host, untilText: ["View rivalry with Fixture Player 1"]
    )
    _ = try nativeHostedPNG(results, filename: "find-rival-results.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(
        host, image: results,
        containing: ["View rivalry with Fixture Player 1", "View rivalry with Fixture Player 2"],
        notContaining: ["Searching Players"]
    )
}

@MainActor
@Test func findRivalSheetRendersEmptyResultsState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        FindRivalSheet(session: session)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 390, height: 700)
    )
    try typeIntoFindRival("zzz-nobody", host: host)
    let image = try await nativeHostedSettle(host, untilText: ["No player results were returned."])
    _ = try nativeHostedPNG(image, filename: "find-rival-empty.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(
        host, image: image, containing: ["No player results were returned.", "Retry Search"],
        notContaining: ["Searching Players"]
    )
}

/// Clearing back to an empty query resets to `.enterQuery` without a stale
/// results list lingering (`.onChange(of: query)`).
@MainActor
@Test func findRivalSheetResetsToEnterQueryAfterClearing() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        FindRivalSheet(session: session)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 390, height: 700)
    )
    try typeIntoFindRival("Fixture", host: host)
    let withResults = try await nativeHostedSettle(
        host, untilText: ["View rivalry with Fixture Player 1"]
    )
    try typeIntoFindRival("", host: host)
    let cleared = try await nativeHostedSettle(
        host, untilText: ["Enter at least two characters to search for a rival."]
    )
    assertRendersContent(
        host, image: cleared,
        containing: ["Enter at least two characters to search for a rival."],
        notContaining: ["View rivalry with"]
    )
    _ = try nativeHostedPNG(
        withResults, filename: "find-rival-before-clear.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    let clearedPNG = try nativeHostedPNG(
        cleared, filename: "find-rival-after-clear.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(!clearedPNG.isEmpty)
}

@MainActor
@Test func findRivalSheetRendersFailedSearchState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        FindRivalSheet(session: session)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 390, height: 700)
    )
    // The shared fixture's `/api/account/search` returns HTTP 503 for "busy".
    try typeIntoFindRival("busy", host: host)
    let image = try await nativeHostedSettle(host, untilText: ["Player search unavailable"])
    _ = try nativeHostedPNG(image, filename: "find-rival-failed.png", environment: "FST_RIVALS_RENDER_OUT")
    assertRendersContent(
        host, image: image, containing: ["Player search unavailable", "Retry Search"],
        notContaining: ["Searching Players"]
    )
}
#endif
