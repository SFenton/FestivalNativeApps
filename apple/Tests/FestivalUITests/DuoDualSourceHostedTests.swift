#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// iPhone Duo inner display, portrait, partially open (fold across the middle).
private let halfFoldPortrait = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 669, height: 951), widthClass: .regular,
    hinge: .partiallyOpen, divisions: [CGRect(x: 0, y: 463, width: 669, height: 25)]
))

/// iPhone Duo inner display, portrait, flat.
private let unfoldedPortrait = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
))

/// iPhone Duo outer display, portrait.
private let folded = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 466, height: 678), widthClass: .compact,
    safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
    verticalBarEdge: .trailing, hinge: .closed
))

private let innerPortraitSize = CGSize(width: 669, height: 951)

/// A session that never reaches the network.
@MainActor
private func offlineSession() -> FestivalSession {
    FestivalSession(factory: { throw FestivalAPIError.invalidResource })
}

/// Host a view under an injected layout in a dark offscreen window.
@MainActor
private func host<Content: View>(
    _ content: Content, layout: DeviceLayout, size: CGSize, storage: UserDefaults? = nil
) -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow) {
    // Load-in fades never advance in an offscreen host, so render with the app's
    // Reduce Motion on (content then appears without animation).
    let defaults = storage ?? UserDefaults(suiteName: "fst.tests.dual.host")!
    defaults.set(true, forKey: "fst.accessibility.reduceMotion")
    let view = NavigationStack { content }
        .environment(\.deviceLayout, layout)
        .defaultAppStorage(defaults)
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark)
    let hosted = nativeHostedView(view, size: size)
    return (hosted, nativeHostedWindow(hosted, size: size))
}

/// A synthetic two-source page.
private struct FixtureDualPage: View {
    var body: some View {
        DualSourceLayout {
            List { Text("Fixture Primary") }
        } secondary: {
            DualSourcePane("Fixture Source", systemImage: "sparkles", identifier: "fixture") {
                HorizontalCarousel("Fixture Carousel", items: [FixtureCard(id: "a"), FixtureCard(id: "b"), FixtureCard(id: "c")]) { card in
                    Text("Fixture Card \(card.id)").padding(24).festivalGlass(.card)
                }
            }
        }
    }
}

private struct FixtureCard: Identifiable { let id: String }

// MARK: - Layout per pose

/// Partially open and flat portrait both show the second source below the page.
@MainActor
@Test(arguments: [halfFoldPortrait, unfoldedPortrait])
func dualSourceShowsSecondSourceInInnerPortrait(layout: DeviceLayout) async throws {
    let (hosted, window) = host(FixtureDualPage(), layout: layout, size: innerPortraitSize)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(hosted, untilText: ["Fixture Primary", "Fixture Source", "Fixture Card a"])
    _ = try nativeHostedPNG(image, filename: "dual-fixture-\(layout.pose).png", environment: "FST_DUO_RENDER_OUT")
    assertRendersContent(
        hosted, image: image, minimumNonBackgroundFraction: 0.002, minimumInkFraction: 0.0005,
        containing: ["Fixture Primary", "Fixture Source", "Fixture Carousel"]
    )
}

/// Folded (and every other pose) shows the page alone, exactly as without the wrapper.
@MainActor
@Test(arguments: [folded, DeviceLayout.standardPhone])
func dualSourceHidesSecondSourceElsewhere(layout: DeviceLayout) async throws {
    let (hosted, window) = host(FixtureDualPage(), layout: layout, size: CGSize(width: 466, height: 678))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(hosted, untilText: ["Fixture Primary"], excluding: ["Fixture Source"])
    assertRendersContent(
        hosted, image: image, minimumNonBackgroundFraction: 0, minimumInkFraction: 0,
        containing: ["Fixture Primary"], notContaining: ["Fixture Source", "Fixture Card"]
    )
}

// MARK: - Page secondaries (offline / anonymous states)

/// Anonymous, the Songs suggestions region explains itself and offers Choose Profile.
@MainActor
@Test func suggestionsPaneAnonymousOffersChooseProfile() async throws {
    let session = offlineSession()
    let page = DualSourceLayout { Text("Fixture Songs") } secondary: {
        SuggestionsCarouselPane(session: session, source: .all, seeAll: .suggestions)
    }
    let (hosted, window) = host(page, layout: halfFoldPortrait, size: innerPortraitSize)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(hosted, untilText: ["Suggestions", "No Profile Selected", "Choose Profile"])
    _ = try nativeHostedPNG(image, filename: "dual-suggestions-anonymous.png", environment: "FST_DUO_RENDER_OUT")
}

/// With Hide Item Shop on, the Item Shop picks region says so instead of loading.
@MainActor
@Test func shopPicksPaneRespectsHideItemShop() async throws {
    let suite = "fst.tests.dual.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    defer { storage.removePersistentDomain(forName: suite) }
    storage.set(true, forKey: "fst.settings.hideShop")
    let identity: [String: String] = ["accountId": "fixture-dual", "displayName": "Fixture Dual"]
    storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource }, selectionStorage: storage)
    let page = DualSourceLayout { Text("Fixture Suggestions") } secondary: {
        SuggestionsCarouselPane(session: session, source: .itemShop, seeAll: .shop)
    }
    let (hosted, window) = host(page, layout: unfoldedPortrait, size: innerPortraitSize, storage: storage)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(hosted, untilText: ["Item Shop Picks", "Item Shop Hidden"])
}

/// Before any selection, the Rivals region asks for one.
@MainActor
@Test func rivalsPaneAsksForSelection() async throws {
    let page = DualSourceLayout { Text("Fixture Rivals") } secondary: {
        RivalDualDetailPane(session: offlineSession(), selection: nil)
    }
    let (hosted, window) = host(page, layout: halfFoldPortrait, size: innerPortraitSize)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(hosted, untilText: ["Rivalry", "Select a Rival"])
}

/// Rows in a dual page select into the second region instead of pushing.
@MainActor
@Test func dualSelectionRoutesRowsToSecondRegion() async throws {
    let rival = AppRoute.rivalDetail(rivalId: "fixture-rival", name: "Fixture Rival", scope: nil)
    let recorder = SelectionRecorder()
    let page = DualSelectionFixture(route: rival, recorder: recorder)
    let (hosted, window) = host(page, layout: halfFoldPortrait, size: innerPortraitSize)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(hosted, untilText: ["Fixture Row"])
    #expect(recorder.hasSelectAction)
    let stackRecorder = SelectionRecorder()
    let (stackHosted, stackWindow) = host(
        DualSelectionFixture(route: rival, recorder: stackRecorder), layout: folded,
        size: CGSize(width: 466, height: 678)
    )
    defer { stackWindow.orderOut(nil) }
    try await nativeHostedSettle(stackHosted, untilText: ["Fixture Row"])
    #expect(!stackRecorder.hasSelectAction)
}

/// Records whether a row sees a select action (dual) or not (plain link).
@MainActor
private final class SelectionRecorder {
    var hasSelectAction = false
}

private struct DualSelectionFixture: View {
    let route: AppRoute
    let recorder: SelectionRecorder
    @State private var selection: AppRoute?

    var body: some View {
        DualSourceLayout {
            SelectionProbe(recorder: recorder) { Text("Fixture Row") }
                .dualSourceSelection($selection, section: .rivals)
        } secondary: {
            Text(selection == nil ? "Nothing Selected" : "Selected")
        }
    }
}

private struct SelectionProbe<Label: View>: View {
    let recorder: SelectionRecorder
    @ViewBuilder let label: () -> Label
    @Environment(\.listDetailSelect) private var select

    var body: some View {
        label().onAppear { recorder.hasSelectAction = select != nil }
    }
}

// MARK: - Compete (loopback mock service)

/// Compete in inner portrait: leaderboards carousel on top, rivals carousel below,
/// both from the loopback mock (`RivalsMockService`), with the stacked hub's
/// single-column sections gone.
@MainActor
@Test func competeDualShowsLeaderboardsAboveRivals() async throws {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    let suite = "fst.tests.dual.compete.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    defer { storage.removePersistentDomain(forName: suite) }
    let identity: [String: String] = ["accountId": "fixture-riv", "displayName": "Fixture Viewer"]
    storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    for key in [
        "fst.settings.showBass", "fst.settings.showDrums", "fst.settings.showVocals",
        "fst.settings.showProLead", "fst.settings.showProBass", "fst.settings.showKaraoke",
        "fst.settings.showProCymbals", "fst.settings.showProDrums",
    ] { storage.set(false, forKey: key) }
    storage.set(true, forKey: "fst.settings.showLead")
    let session = FestivalSession(factory: { client }, selectionStorage: storage)
    let (hosted, window) = host(CompeteScreen(session: session), layout: halfFoldPortrait, size: innerPortraitSize, storage: storage)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        hosted, untilText: ["Leaderboards", "Rivals", "Leaderboards Overview", "View Full Leaderboard"],
        excluding: ["Loading"]
    )
    _ = try nativeHostedPNG(image, filename: "dual-compete.png", environment: "FST_DUO_RENDER_OUT")
}

/// Anonymous, the Song Detail history and Leaderboards rank-history regions offer
/// Choose Profile instead of loading.
@MainActor
@Test func historyPanesAnonymousOfferChooseProfile() async throws {
    let session = offlineSession()
    let song = try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-song","title":"Fixture Song","artist":"Fixture Artist"}
    """.utf8))
    let songPage = DualSourceLayout { Text("Fixture Song Detail") } secondary: {
        SongHistoryCarouselPane(session: session, song: song)
    }
    let (songHosted, songWindow) = host(songPage, layout: halfFoldPortrait, size: innerPortraitSize)
    defer { songWindow.orderOut(nil) }
    try await nativeHostedSettle(songHosted, untilText: ["Your Score History", "No Profile Selected", "Choose Profile"])

    let boardsPage = DualSourceLayout { Text("Fixture Boards") } secondary: {
        LeaderboardsRankHistoryPane(session: session)
    }
    let (boardsHosted, boardsWindow) = host(boardsPage, layout: unfoldedPortrait, size: innerPortraitSize)
    defer { boardsWindow.orderOut(nil) }
    try await nativeHostedSettle(boardsHosted, untilText: ["Your Rank History", "No Profile Selected"])
}
#endif
