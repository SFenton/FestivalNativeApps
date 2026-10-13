#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Song Detail band preview columns accessibility (issue #491, for #366)

/// #366 moved Song Detail's Duos, Trios and Quads previews into a second
/// `SongDetailCardGrid` after the instrument cards (pattern `hinge-columns` R9), so on
/// iPad, the Mac and the unfolded iPhone Duo they sit side by side: Duos | Trios, then
/// Quads under Duos. `songDetailBandPreviewsFlowInCardColumnsWhenWide` pins the geometry;
/// these hosted checks (macOS host, `apple-ci`) pin what assistive technologies get from
/// it, on the shared SwiftUI the four Apple surfaces run:
///
/// - each size's title is a heading naming the size, read first in its section, then its
///   band rows, then its View Full Leaderboard button, or its empty-state text; each row
///   and button is one named button (never an identifier) of at least 44×44 pt that lies
///   wholly inside its own column and on the page (HIG Accessibility: iOS, iPadOS default
///   control size 44×44 pt; HIG VoiceOver: "Use accurate section headings");
/// - VoiceOver reads the sections whole, in size order (Duos, Trios, Quads), after every
///   instrument card: the drawn row-major order of the sections, never a line across
///   both columns (HIG VoiceOver: "Specify how elements are grouped, ordered or linked
///   where relationships are only visual, like proximity or alignment");
/// - two columns change nothing VoiceOver reads: the same page at iPhone width (one
///   column) reads the same band elements with the same roles and names in the same order;
/// - in iPhone Duo book pose the columns meet at the fold and no band target crosses it
///   (HIG iPhone Duo: the folding region "divides the inner display into usable regions
///   while excluding the center fold");
/// - all of it at the largest accessibility size too (`.accessibility5`, the eager grid).
///   macOS keeps its font size, so `SongDetailBandColumnsJourneyTests` shows real AX5
///   growth on the iPad and runs the system audit there.
@MainActor
@Suite(.serialized)
struct SongDetailBandColumnsAccessibilityTests {
    // MARK: - Constants

    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    static let minimumTarget: CGFloat = 44
    /// Frame tolerance for whole-pixel snapping on a 1x display.
    static let tolerance: CGFloat = 1.5

    /// The band elements VoiceOver reads, in order, for the fixture (`tools/mock_service.py`):
    /// `fixture-pulse` has two Duos rows and, for `fixture-player-1`, its rank-29 band
    /// appended; Trios and Quads have no scores.
    static let readOrder: [String] = [
        "fst.song-detail.band-header.Band_Duets",
        "fst.song-detail.band-row.Band_Duets.0",
        "fst.song-detail.band-row.Band_Duets.1",
        "fst.song-detail.band-selected.Band_Duets",
        "fst.song-detail.band-leaderboard.Band_Duets",
        "fst.song-detail.band-header.Band_Trios",
        "fst.song-detail.band-empty.Band_Trios",
        "fst.song-detail.band-header.Band_Quad",
        "fst.song-detail.band-empty.Band_Quad",
    ]

    /// The band buttons: Duos' rows, its appended band and its View Full Leaderboard.
    static let buttons = readOrder.filter { !$0.contains(".band-header.") && !$0.contains(".band-empty.") }

    /// Identifier prefixes of the instrument cards, which read before every band section.
    static let instrumentPrefixes = [
        "fst.song-detail.card-header.", "fst.song-detail.preview-row.",
        "fst.song-detail.spotlight.", "fst.song-detail.leaderboard.",
    ]

    /// The iPhone Duo inner display's vertical fold in book pose (window coordinates).
    nonisolated static let bookFold = CGRect(x: 455, y: 0, width: 40, height: 6000)

    /// Where the page is hosted.
    enum Placement: String, CustomTestStringConvertible {
        /// A wide Mac window or iPad landscape: two columns.
        case wide
        /// The iPhone Duo inner display fully open: two columns at the free space's midpoint.
        case duoFlat
        /// The iPhone Duo inner display in book pose: two columns meeting at the fold.
        case duoBook
        /// iPhone width: one column.
        case phone

        var testDescription: String { rawValue }

        var width: CGFloat {
            switch self {
            case .wide: 1000
            case .duoFlat, .duoBook: 951
            case .phone: 402
            }
        }

        /// The injected device layout, for the Duo placements.
        var layout: DeviceLayout? {
            let hinge: HingeState
            switch self {
            case .duoFlat: hinge = .fullyOpen
            case .duoBook: hinge = .partiallyOpen
            case .wide, .phone: return nil
            }
            let fold = SongDetailBandColumnsAccessibilityTests.bookFold
            return DeviceLayout.resolve(LayoutSignals(
                size: CGSize(width: width, height: 669), widthClass: .regular,
                safeAreaInsets: EdgeInsets(), hinge: hinge,
                divisions: hinge == .partiallyOpen ? [fold] : [], hinges: [fold]
            ))
        }
    }

    /// One hosted Song Detail page.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let storage: UserDefaults?
        let suite: String?

        @MainActor
        func close() {
            window.orderOut(nil)
            if let suite { storage?.removePersistentDomain(forName: suite) }
        }
    }

    // MARK: - Hosting

    /// Host `fixture-pulse`'s Song Detail, tall enough to hold every card, with
    /// `fixture-player-1` selected and fades off, until every band element is in the tree.
    ///
    /// - Parameters:
    ///   - placement: Width and device layout.
    ///   - typeSize: Dynamic Type size (the eager grid at every size, #500).
    /// - Returns: The settled page.
    static func host(_ placement: Placement, typeSize: DynamicTypeSize = .large) async throws -> Hosted {
        let (session, storage, suite) = try await bandsFixtureSession(selected: "fixture-player-1")
        let song = try #require(try await session.catalog().catalog.songs.first { $0.songId == "fixture-pulse" })
        let size = CGSize(width: placement.width, height: 6000)
        var page = AnyView(NavigationStack { SongDetailScreen(song: song, session: session) })
        if let layout = placement.layout {
            page = AnyView(page.environment(\.deviceLayout, layout))
        }
        let host = nativeHostedView(
            AnyView(
                page
                    .environment(\.festivalFadeInEnabled, false)
                    .environment(\.dynamicTypeSize, typeSize)
                    .preferredColorScheme(.dark)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        let hosted = Hosted(host: host, window: window, storage: storage, suite: suite)
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            readOrder.allSatisfy { nativeHostedAccessibilityFrame($0, in: host) != nil }
        }
        return hosted
    }

    // MARK: - Tree helpers

    /// The page's elements in VoiceOver's navigation order.
    static func readingOrder(_ host: NSView) -> [MacAXNode] {
        host.layoutSubtreeIfNeeded()
        return macAccessibilityTree(host, navigationOrder: true).filter(\.isElement)
    }

    static func dump(_ nodes: [MacAXNode]) -> String {
        nodes.map(\.description).joined(separator: "\n")
    }

    /// The one element carrying `identifier`.
    static func element(_ identifier: String, in nodes: [MacAXNode], _ context: String) throws -> MacAXNode {
        let matches = nodes.filter { $0.identifier == identifier }
        return try #require(matches.count == 1 ? matches.first : nil,
                            "\(context): one element \(identifier):\n\(dump(nodes))")
    }

    static func frame(_ identifier: String, _ hosted: Hosted, _ context: String) throws -> CGRect {
        try #require(nativeHostedAccessibilityFrame(identifier, in: hosted.host), "\(context): no frame for \(identifier)")
    }

    // MARK: - Expectations

    /// Duos and Trios share a line, Quads starts the next under Duos. A section's
    /// accessibility frame is the union of its children's, and a heading's text is centred
    /// in its 44 pt row, so lines are compared by heading centres, not section tops.
    static func expectTwoColumns(_ hosted: Hosted, _ context: String) throws {
        let duos = try frame("fst.song-detail.band.Band_Duets", hosted, context)
        let trios = try frame("fst.song-detail.band.Band_Trios", hosted, context)
        let quads = try frame("fst.song-detail.band.Band_Quad", hosted, context)
        let duosHeading = try frame("fst.song-detail.band-header.Band_Duets", hosted, context)
        let triosHeading = try frame("fst.song-detail.band-header.Band_Trios", hosted, context)
        #expect(abs(duosHeading.midY - triosHeading.midY) < tolerance && trios.minX > duos.maxX,
                "\(context): Trios beside Duos: \(duos) \(trios)")
        #expect(abs(quads.minX - duos.minX) < tolerance && quads.minY >= max(duos.maxY, trios.maxY) - tolerance,
                "\(context): Quads starts the next line under Duos: \(quads)")
    }

    /// Each heading names its size; each button is named, 44×44 pt or larger, inside its
    /// own section's column and the page; the empty states read their text.
    static func expectNamesRolesAndTargets(_ hosted: Hosted, _ context: String) throws {
        let nodes = macAccessibilityTree(hosted.host)
        let page = hosted.host.bounds.insetBy(dx: -0.5, dy: -0.5)
        for band in BandType.allCases {
            let heading = try element("fst.song-detail.band-header.\(band.rawValue)", in: nodes, context)
            #expect(heading.role == "AXHeading" && heading.spokenName.hasPrefix(band.label),
                    "\(context): \(band.label) title is a heading naming the size: \(heading)")
        }
        for band in [BandType.trios, .quad] {
            let empty = try element("fst.song-detail.band-empty.\(band.rawValue)", in: nodes, context)
            #expect(empty.spokenName.contains("When \(band.label) scores are submitted"),
                    "\(context): \(band.label) reads its empty state: \(empty)")
            #expect(!nodes.contains { $0.identifier == "fst.song-detail.band-leaderboard.\(band.rawValue)" },
                    "\(context): an empty \(band.label) offers no View Full Leaderboard")
        }
        let column = try frame("fst.song-detail.band.Band_Duets", hosted, context).insetBy(dx: -0.5, dy: -0.5)
        let trios = try frame("fst.song-detail.band.Band_Trios", hosted, context)
        for id in buttons {
            let node = try element(id, in: nodes, context)
            #expect(node.role == "AXButton", "\(context): \(id) is a button: \(node)")
            #expect(!node.spokenName.isEmpty && !node.spokenName.contains("fst."),
                    "\(context): \(id) has a spoken name: \(node)")
            let target = try frame(id, hosted, context)
            #expect(target.width >= minimumTarget - 0.5 && target.height >= minimumTarget - 0.5,
                    "\(context): \(id) is a 44×44 pt target: \(target)")
            #expect(column.contains(target), "\(context): \(id) stays in the Duos column: \(target) in \(column)")
            #expect(page.contains(target), "\(context): \(id) lies on the page: \(target)")
            let overlap = target.insetBy(dx: 0.5, dy: 0.5).intersection(trios)
            #expect(overlap.isNull || overlap.isEmpty, "\(context): \(id) reaches into Trios: \(target) \(trios)")
        }
        let top = try element("fst.song-detail.band-row.Band_Duets.0", in: nodes, context)
        #expect(top.spokenName.hasPrefix("Rank 1, "), "\(context): the top band reads its rank first: \(top)")
        let selected = try element("fst.song-detail.band-selected.Band_Duets", in: nodes, context)
        #expect(selected.spokenName.hasPrefix("Your band, Rank 29, "), "\(context): the appended band: \(selected)")
        let viewFull = try element("fst.song-detail.band-leaderboard.Band_Duets", in: nodes, context)
        #expect(viewFull.spokenName == PurpleActionName.spoken("View Full Leaderboard", card: BandType.duets.label),
                "\(context): View Full names its size: \(viewFull)")
    }

    /// VoiceOver reads the band elements in ``readOrder`` (each section whole, in size
    /// order, which is the sections' drawn row-major order) after every instrument card.
    static func expectReadingOrder(_ hosted: Hosted, _ context: String) throws {
        let order = readingOrder(hosted.host)
        let read = order.map(\.identifier).filter(readOrder.contains)
        #expect(read == readOrder, "\(context): band elements read in order:\n\(read.joined(separator: "\n"))")
        let firstBand = try #require(order.firstIndex { $0.identifier.hasPrefix("fst.song-detail.band") },
                                     "\(context): a band element is read:\n\(dump(order))")
        let lastCard = try #require(order.lastIndex { node in instrumentPrefixes.contains { node.identifier.hasPrefix($0) } },
                                    "\(context): an instrument card is read:\n\(dump(order))")
        #expect(lastCard < firstBand, "\(context): every instrument card reads before Duos: \(lastCard) vs \(firstBand)")
        let headings = try BandType.allCases.map { band in
            (band, try frame("fst.song-detail.band-header.\(band.rawValue)", hosted, context))
        }
        let drawn = headings.sorted { lhs, rhs in
            abs(lhs.1.midY - rhs.1.midY) < tolerance ? lhs.1.minX < rhs.1.minX : lhs.1.midY < rhs.1.midY
        }.map(\.0)
        #expect(drawn == BandType.allCases, "\(context): the read order is the drawn order: \(drawn)")
    }

    /// The band elements VoiceOver reads, each with its role and name.
    static func sequence(_ hosted: Hosted) -> [String] {
        readingOrder(hosted.host)
            .filter { $0.identifier.hasPrefix("fst.song-detail.band") }
            .map { "\($0.identifier) \($0.role) '\($0.spokenName)'" }
    }

    // MARK: - Tests

    /// In two columns (a wide Mac window or iPad landscape, and the flat Duo inner
    /// display), at the default and the largest accessibility size, the band previews keep
    /// their headings, named 44 pt buttons inside their own column and size-order reading.
    @Test(arguments: [Placement.wide, .duoFlat], [DynamicTypeSize.large, .accessibility5])
    func bandColumnsKeepHeadingsNamesTargetsAndOrder(placement: Placement, typeSize: DynamicTypeSize) async throws {
        let hosted = try await Self.host(placement, typeSize: typeSize)
        defer { hosted.close() }
        let context = "\(placement) \(typeSize)"
        macAccessibilityDump(Self.readingOrder(hosted.host), name: "song-detail-band-columns-\(placement)-\(typeSize)")
        try Self.expectTwoColumns(hosted, context)
        try Self.expectNamesRolesAndTargets(hosted, context)
        try Self.expectReadingOrder(hosted, context)
    }

    /// Two columns read like one: the same page at iPhone width stacks the sections and
    /// reads the same band elements with the same roles and names in the same order.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func bandColumnsReadTheSameSequenceAsOneColumn(typeSize: DynamicTypeSize) async throws {
        let wide = try await Self.host(.wide, typeSize: typeSize)
        let paired = Self.sequence(wide)
        wide.close()
        let phone = try await Self.host(.phone, typeSize: typeSize)
        defer { phone.close() }
        let duos = try Self.frame("fst.song-detail.band.Band_Duets", phone, "phone")
        let trios = try Self.frame("fst.song-detail.band.Band_Trios", phone, "phone")
        #expect(abs(trios.minX - duos.minX) < Self.tolerance && trios.minY >= duos.maxY - Self.tolerance,
                "\(typeSize): iPhone width is one column: \(duos) \(trios)")
        try Self.expectNamesRolesAndTargets(phone, "phone \(typeSize)")
        try Self.expectReadingOrder(phone, "phone \(typeSize)")
        let single = Self.sequence(phone)
        #expect(!paired.isEmpty && paired == single,
                "\(typeSize): two columns read like one:\n\(paired.joined(separator: "\n"))\nvs\n\(single.joined(separator: "\n"))")
    }

    /// iPhone Duo book pose: Duos ends before the fold and Trios starts after it, no band
    /// button crosses the fold, and the reading order and names are unchanged.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func bookPoseKeepsBandTargetsOffTheFold(typeSize: DynamicTypeSize) async throws {
        let hosted = try await Self.host(.duoBook, typeSize: typeSize)
        defer { hosted.close() }
        let context = "book pose \(typeSize)"
        let fold = Self.bookFold
        _ = try await nativeHostedSettle(hosted.host, timeout: .seconds(20)) {
            guard let duos = nativeHostedAccessibilityFrame("fst.song-detail.band.Band_Duets", in: hosted.host) else {
                return false
            }
            return abs(duos.maxX - fold.minX) < Self.tolerance
        }
        let duos = try Self.frame("fst.song-detail.band.Band_Duets", hosted, context)
        let trios = try Self.frame("fst.song-detail.band.Band_Trios", hosted, context)
        #expect(abs(duos.maxX - fold.minX) < Self.tolerance, "\(context): Duos ends at the fold: \(duos)")
        #expect(abs(trios.minX - fold.maxX) < Self.tolerance, "\(context): Trios starts after the fold: \(trios)")
        let ids = Self.readOrder + BandType.allCases.map { "fst.song-detail.band.\($0.rawValue)" }
        for id in ids {
            let target = try Self.frame(id, hosted, context)
            #expect(target.maxX <= fold.minX + Self.tolerance || target.minX >= fold.maxX - Self.tolerance,
                    "\(context): \(id) crosses the fold: \(target)")
        }
        try Self.expectTwoColumns(hosted, context)
        try Self.expectNamesRolesAndTargets(hosted, context)
        try Self.expectReadingOrder(hosted, context)
    }
}
#endif
