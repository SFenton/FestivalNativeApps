#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Profile Bands group cards (owner #596)

/// The owner asked that the profile's Duos, Trios and Quads each be **one card** of band
/// rows ending with the purple View All, "as other cards", with no Duos/Trios/Quads chip
/// on the rows (#596). These hosted checks pin the grouped card (rows inside one card,
/// hairline-adjacent, the View All inside it below the last row) and its accessibility:
/// heading, rows, then View All in reading order; one button named label first and then
/// its group (view-all-cta R4); a full-width target of at least 44 pt (R1, R3); no row
/// repeats its group's name; and all of it at the largest accessibility size. Wide
/// windows put the group cards in the profile's two instrument-tile columns.
///
/// HIG Lists and tables: grouped style, "headers, footers, extra space between groups";
/// HIG Layout: "Group related information/functions using negative space, containers,
/// or separators"; HIG Buttons: "the hit region is at least 44x44 pt".
@MainActor
@Suite(.serialized)
struct ProfileBandsCardAccessibilityTests {
    // MARK: - Fixture

    /// Mock-service player with 18 duos, 8 trios and 4 quads (six shown per group).
    static let accountId = "fixture-player-1"
    static let groups: [PlayerBandGroup] = [.duos, .trios, .quads]
    static let width: CGFloat = 402
    static let viewAllNames: [PlayerBandGroup: String] = [
        .duos: "View All Bands (18), Duos", .trios: "View All Bands (8), Trios",
    ]

    static func card(_ group: PlayerBandGroup) -> String { "fst.player.bands.card.\(group.rawValue)" }
    static func viewAll(_ group: PlayerBandGroup) -> String { "fst.player.bands.view-all.\(group.rawValue)" }
    static func row(_ entry: PlayerBandEntry) -> String { "fst.player-bands.row.\(entry.id)" }

    /// One hosted bands section and the preview it shows.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let preview: PlayerBandsPreview

        func close() { window.orderOut(nil) }
    }

    /// Host the profile bands section on a page of `width`, loaded from the mock service.
    ///
    /// - Parameters:
    ///   - typeSize: Dynamic Type size for the section.
    ///   - width: Page width.
    ///   - layout: Device layout (compact phone unless a test widens it).
    /// - Returns: The settled host and the preview it shows.
    /// - Throws: An unreachable mock service or an unsettled section.
    static func host(
        _ typeSize: DynamicTypeSize, width: CGFloat = width, layout: DeviceLayout = .standardPhone
    ) async throws -> Hosted {
        let baseURL = try await RivalsMockService.shared.baseURL()
        let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
        let session = FestivalSession(factory: { client })
        let preview = try await session.playerBandsPreview(accountId: accountId)
        let size = CGSize(width: width, height: 6000)
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    ScrollView {
                        PlayerBandsPreviewSection(
                            session: session, accountId: accountId, displayName: "Fixture Player 1",
                            routeDisplayName: nil, phase: .loaded(preview)
                        )
                        .padding(16)
                    }
                }
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
                .environment(\.deviceLayout, layout)
                .environment(\.dynamicTypeSize, typeSize)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            groups.allSatisfy { nativeHostedAccessibilityFrame(card($0), in: host) != nil }
                && nativeHostedAccessibilityFrame(viewAll(.trios), in: host) != nil
        }
        return Hosted(host: host, window: window, preview: preview)
    }

    /// The element carrying an identifier in a tree walk.
    static func node(_ id: String, in nodes: [MacAXNode]) throws -> MacAXNode {
        try #require(
            nodes.first { $0.identifier == id && $0.isElement },
            "\(id) in\n\(nodes.map(\.description).joined(separator: "\n"))"
        )
    }

    // MARK: - Expectations

    /// Each group is one card: its rows sit inside it with no gap between them (hairlines,
    /// not separate tiles), and View All ends the card below the last row.
    static func expectOneCardPerGroup(_ hosted: Hosted) throws {
        for group in hosted.preview.groups {
            let card = try #require(nativeHostedAccessibilityFrame(Self.card(group.group), in: hosted.host))
            var rows: [CGRect] = []
            for entry in group.entries {
                rows.append(try #require(nativeHostedAccessibilityFrame(row(entry), in: hosted.host), "\(entry.id)"))
            }
            for frame in rows {
                #expect(card.insetBy(dx: -0.5, dy: -0.5).contains(frame), "\(group.group) row inside its card: \(frame) in \(card)")
                #expect(abs(frame.width - card.width) <= 1, "\(group.group) rows span the card edge to edge: \(frame) vs \(card)")
            }
            for (above, below) in zip(rows, rows.dropFirst()) {
                #expect(abs(below.minY - above.maxY) <= 1.5, "\(group.group) rows share one card, no tile gap: \(above) → \(below)")
            }
            let lastRow = try #require(rows.last)
            let inset = FestivalGlassSection<EmptyView, EmptyView>.actionInset
            if group.hasMore {
                let button = try #require(nativeHostedAccessibilityFrame(viewAll(group.group), in: hosted.host))
                #expect(card.insetBy(dx: -0.5, dy: -0.5).contains(button), "\(group.group) View All inside the card: \(button) in \(card)")
                #expect(button.minY >= lastRow.maxY - 0.5, "\(group.group) View All after the last row")
                #expect(button.height >= 44 - 0.5, "\(group.group) View All is at least 44 pt tall: \(button)")
                #expect(button.width >= card.width - 2 * inset - 1, "\(group.group) View All spans the card: \(button)")
                #expect(abs(card.maxY - button.maxY - inset) <= 1, "\(group.group) View All ends the card")
            } else {
                #expect(nativeHostedAccessibilityFrame(viewAll(group.group), in: hosted.host) == nil)
                #expect(abs(card.maxY - lastRow.maxY) <= 1, "\(group.group) card ends at its last row")
            }
        }
    }

    /// Each View All is one button, named label first and then its group; rows read their
    /// members and count but never their group's name (no Duos/Trios/Quads chip).
    static func expectNamesAndRoles(_ hosted: Hosted) throws {
        let nodes = macAccessibilityTree(hosted.host)
        let elements = nodes.filter(\.isElement)
        for (group, name) in viewAllNames {
            let button = try node(viewAll(group), in: nodes)
            #expect(button.role == "AXButton", "\(button)")
            #expect(button.spokenName == name, "\(button)")
            #expect(elements.filter { $0.spokenName.contains("View All Bands") && $0.spokenName.hasSuffix(group.label) }.count == 1)
        }
        for group in hosted.preview.groups {
            #expect(elements.filter { $0.spokenName == group.group.label }.count == 1, "\(group.group) heading read once")
            for entry in group.entries {
                let row = try node(row(entry), in: nodes)
                #expect(row.spokenName == PlayerBandRow.spokenLabel(entry), "\(row)")
                for label in groups.map(\.label) {
                    #expect(!row.spokenName.contains(label), "\(entry.id) repeats a size chip: \(row)")
                }
            }
        }
        #expect(macAccessibilityFindings(nodes) == [])
    }

    /// Reading order: each group's heading, its rows, then its View All, group by group.
    static func expectReadingOrder(_ hosted: Hosted) throws {
        let order = macAccessibilityTree(hosted.host, navigationOrder: true).filter(\.isElement)
        func index(_ match: (MacAXNode) -> Bool, _ what: String) throws -> Int {
            let found = order.firstIndex(where: match)
            return try #require(found, "\(what) in:\n\(order.map(\.description).joined(separator: "\n"))")
        }
        var sequence: [Int] = []
        for group in hosted.preview.groups {
            sequence.append(try index({ $0.identifier == "fst.player.bands.group.\(group.group.rawValue)" }, "\(group.group) heading"))
            for entry in group.entries {
                sequence.append(try index({ $0.identifier == row(entry) }, entry.id))
            }
            if group.hasMore {
                sequence.append(try index({ $0.identifier == viewAll(group.group) }, "\(group.group) View All"))
            }
        }
        #expect(sequence == sequence.sorted() && Set(sequence).count == sequence.count,
                "heading, rows, then View All, group by group: \(sequence)")
    }

    // MARK: - Tests

    /// iPhone width: each group is one card ending with its View All inside it.
    @Test func eachGroupIsOneCardEndingWithViewAll() async throws {
        let hosted = try await Self.host(.large)
        defer { hosted.close() }
        let image = try nativeHostedImage(hosted.host)
        _ = try nativeHostedPNG(image, filename: "profile-bands-cards.png", environment: "FST_BANDS_RENDER_OUT")
        try Self.expectOneCardPerGroup(hosted)
    }

    /// Names, roles, no group chip on rows, and reading order at the default size.
    @Test func viewAllAndRowsAreNamedAndReadInOrder() async throws {
        let hosted = try await Self.host(.large)
        defer { hosted.close() }
        try Self.expectNamesAndRoles(hosted)
        try Self.expectReadingOrder(hosted)
    }

    /// At the largest accessibility size the cards, names, order and targets hold.
    @Test func groupCardsHoldAtAccessibilitySizes() async throws {
        let hosted = try await Self.host(.accessibility5)
        defer { hosted.close() }
        try Self.expectOneCardPerGroup(hosted)
        try Self.expectNamesAndRoles(hosted)
        try Self.expectReadingOrder(hosted)
    }

    /// A regular-width window puts the group cards in two columns (Duos beside Trios,
    /// Quads below), like the profile's instrument tiles, each still one card.
    @Test func wideWindowPutsGroupCardsInTwoColumns() async throws {
        let width: CGFloat = 1024
        let wide = DeviceLayout.resolve(LayoutSignals(size: CGSize(width: width, height: 1366), widthClass: .regular))
        let hosted = try await Self.host(.large, width: width, layout: wide)
        defer { hosted.close() }
        let duos = try #require(nativeHostedAccessibilityFrame(Self.card(.duos), in: hosted.host))
        let trios = try #require(nativeHostedAccessibilityFrame(Self.card(.trios), in: hosted.host))
        let quads = try #require(nativeHostedAccessibilityFrame(Self.card(.quads), in: hosted.host))
        #expect(trios.minX > duos.maxX, "Trios beside Duos: \(duos) | \(trios)")
        #expect(abs(trios.minY - duos.minY) <= 1, "Duos and Trios start on one line")
        #expect(quads.minY > max(duos.maxY, trios.maxY), "Quads on the next row")
        #expect(abs(quads.minX - duos.minX) <= 1, "Quads under Duos")
        try Self.expectOneCardPerGroup(hosted)
        try Self.expectReadingOrder(hosted)
    }
}
#endif
