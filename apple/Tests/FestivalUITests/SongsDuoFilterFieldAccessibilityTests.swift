#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - iPhone Duo Filter Songs field in every pose (issue #334, backfilled by #475)

/// #334 made the iPhone Duo bottom "Filter Songs" field (``BottomSearchField``) span its
/// page in every pose except a book-pose fold, where it lies on the trailing page. The
/// placement tests pin its geometry; these hosted checks pin what it exposes to
/// VoiceOver, Voice Control and Dynamic Type in each pose the change touched (folded,
/// flat landscape, book landscape, flat portrait, book portrait):
///
/// - one text field named "Filter Songs" (its identifier, an empty value, then the
///   typed text), with "Clear Search" a named button only while there is text;
/// - read after the page's rows (it is the page's bottom chrome), then Clear Search;
/// - its hit region spans the column it is drawn in (the full width, or the right page
///   clear of the fold) and meets the macOS 20 pt minimum; Clear Search is a 44 × 44 pt
///   target (``GlobalSearchField/clearTarget``, the iOS minimum) inside the column;
/// - at the largest accessibility size the field keeps its column, named, with nothing
///   clipped below the window.
///
/// The same SwiftUI renders on iPhone Duo. AppKit text fields do not take Dynamic Type,
/// so text growth, UIKit touch targets and `performAccessibilityAudit` are pinned on the
/// iPhone Duo simulation by
/// `DuoFilterFieldAccessibilityJourneyTests/testFilterFieldKeepsItsColumnAtAX5DuoUnfolded`.
///
/// HIG Accessibility: "Provide VoiceOver descriptions for all interface elements"; iOS
/// default control size 44×44 pt, macOS minimum 20×20 pt. HIG Searching: "Display
/// placeholder text that describes the type of information people can search for".
@MainActor
@Suite(.serialized)
struct SongsDuoFilterFieldAccessibilityTests {
    // MARK: - Fixture

    /// One iPhone Duo pose #334 distinguishes.
    enum Pose: String, CaseIterable, CustomTestStringConvertible {
        case folded
        case flatLandscape
        case bookLandscape
        case flatPortrait
        case bookPortrait

        var testDescription: String { rawValue }

        /// Whether the field lies on the right page, clear of the fold.
        var rightPage: Bool { self == .bookLandscape }

        /// The window layout, as `DeviceLayoutPublisher` resolves it.
        var layout: DeviceLayout {
            typealias Duo = BottomSearchFieldPlacementTests
            let landscape = CGSize(width: 951, height: 669)
            let portrait = CGSize(width: 669, height: 951)
            return switch self {
            case .folded: Duo.duo(.closed, size: CGSize(width: 382, height: 678))
            case .flatLandscape: Duo.duo(.fullyOpen, size: landscape, hinges: [Duo.verticalHinge])
            case .bookLandscape: Duo.duo(.partiallyOpen, size: landscape, fold: Duo.verticalHinge)
            case .flatPortrait: Duo.duo(.fullyOpen, size: portrait, hinges: [Duo.horizontalHinge])
            case .bookPortrait: Duo.duo(.partiallyOpen, size: portrait, fold: Duo.horizontalHinge)
            }
        }
    }

    /// The field's text and pose, changed while one host stays up.
    @MainActor @Observable
    final class Driver {
        var text = ""
        var pose: Pose

        init(_ pose: Pose) { self.pose = pose }
    }

    /// A Songs-like page: rows, with the bottom field in the bottom safe area, laid out
    /// at the pose's window size from the host's top-left.
    struct Page: View {
        let driver: Driver

        var body: some View {
            let layout = driver.pose.layout
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { index in
                        Text("Song \(index + 1)")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 16)
                            .accessibilityIdentifier("fst.test.row.\(index + 1)")
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BottomSearchField(
                    text: Binding(get: { driver.text }, set: { driver.text = $0 }),
                    prompt: "Filter Songs", accessibilityLabel: "Filter Songs",
                    identifier: "fst.songs.filter-field", clearIdentifier: "fst.songs.filter-clear",
                    hinge: BottomSearchFieldPlacement.pageHinge(for: layout), space: "page"
                )
            }
            .coordinateSpace(.named("page"))
            .environment(\.deviceLayout, layout)
            .frame(width: layout.size.width, height: layout.size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// A hosted page and its window.
    struct Hosted {
        let driver: Driver
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow

        @MainActor func close() { window.orderOut(nil) }
    }

    /// HIG Accessibility: the macOS minimum control size.
    static let macMinimumTarget: CGFloat = 20

    /// The host's window: large enough for every pose.
    static let window = CGSize(width: 951, height: 951)

    /// Host the page at a Dynamic Type size, starting in `pose`.
    static func host(_ pose: Pose, typeSize: DynamicTypeSize = .large) -> Hosted {
        let driver = Driver(pose)
        let host = nativeHostedView(
            AnyView(Page(driver: driver).environment(\.dynamicTypeSize, typeSize).preferredColorScheme(.dark)),
            size: window
        )
        return Hosted(driver: driver, host: host, window: nativeHostedWindow(host, size: window))
    }

    /// The column the field is drawn in: 16 pt margins, past the fold in book landscape.
    static func column(_ pose: Pose) -> (minX: CGFloat, maxX: CGFloat) {
        let margin = BottomSearchFieldPlacement.margin
        let fold = BottomSearchFieldPlacement.pageHinge(for: pose.layout)
        return (pose.rightPage ? (fold?.maxX ?? 0) + margin : margin, pose.layout.size.width - margin)
    }

    /// Wait for the field to settle in the pose's column.
    static func settle(_ hosted: Hosted, _ pose: Pose) async throws {
        let column = column(pose)
        _ = try await nativeHostedSettle(hosted.host) {
            guard let field = nativeHostedAccessibilityFrame("fst.songs.filter-field", in: hosted.host) else {
                return false
            }
            return field.minX >= column.minX && field.minX <= column.minX + 60
                && field.maxX <= column.maxX && field.maxX >= column.maxX - 14
        }
    }

    /// Elements VoiceOver lands on, in navigation order (containers and the scroll bar
    /// left out).
    static func readingOrder(_ host: NSView) -> [MacAXNode] {
        let structural: Set<String> = ["AXGroup", "AXScrollArea", "AXScrollBar"]
        return macAccessibilityTree(host, navigationOrder: true).filter {
            $0.isElement && !structural.contains($0.role) && $0.subrole != "AXHostingView"
                && !$0.spokenName.isEmpty
        }
    }

    // MARK: - Name, role, value and reading order

    /// In every pose the field is one text field named "Filter Songs", read after the
    /// page's rows, with no Clear Search while empty; typed text becomes its value and
    /// adds a named Clear Search button right after it.
    @Test(arguments: Pose.allCases)
    func fieldIsNamedAndReadAfterThePageInEveryPose(_ pose: Pose) async throws {
        let hosted = Self.host(pose)
        defer { hosted.close() }
        try await Self.settle(hosted, pose)

        var order = Self.readingOrder(hosted.host)
        macAccessibilityDump(macAccessibilityTree(hosted.host, navigationOrder: true), name: "songs-duo-filter-\(pose)")
        var read = order.map(\.description)
        let fields = order.filter { $0.identifier == "fst.songs.filter-field" }
        #expect(fields.count == 1, "\(pose): one Filter Songs field: \(read)")
        let field = try #require(fields.first)
        #expect(["AXTextField", "AXSearchField"].contains(field.role), "\(pose): field role \(field)")
        #expect(field.label == "Filter Songs", "\(pose): field name \(field)")
        #expect(field.value.isEmpty, "\(pose): empty field value \(field)")
        #expect(!order.contains { $0.identifier == "fst.songs.filter-clear" }, "\(pose): no Clear Search while empty: \(read)")
        let rows = order.indices.filter { order[$0].identifier.hasPrefix("fst.test.row.") }
        let fieldIndex = try #require(order.firstIndex { $0.identifier == "fst.songs.filter-field" })
        #expect(!rows.isEmpty && rows.allSatisfy { $0 < fieldIndex }, "\(pose): rows read before the field: \(read)")
        #expect(macAccessibilityFindings(order) == [], "\(pose)")

        hosted.driver.text = "pulse"
        _ = try await nativeHostedSettle(hosted.host) {
            nativeHostedAccessibilityFrame("fst.songs.filter-clear", in: hosted.host) != nil
        }
        order = Self.readingOrder(hosted.host)
        read = order.map(\.description)
        let typed = try #require(order.firstIndex { $0.identifier == "fst.songs.filter-field" }, "\(pose): \(read)")
        #expect(order[typed].value == "pulse", "\(pose): typed value \(order[typed])")
        let clear = try #require(order.firstIndex { $0.identifier == "fst.songs.filter-clear" }, "\(pose): \(read)")
        #expect(order[clear].role == "AXButton" && order[clear].spokenName == "Clear Search", "\(pose): \(order[clear])")
        #expect(clear == typed + 1, "\(pose): Clear Search reads right after the field: \(read)")
        #expect(macAccessibilityFindings(order) == [], "\(pose)")
    }

    // MARK: - Target size

    /// In every pose the field's hit region spans the column it is drawn in (the full
    /// width, or the right page clear of a book-pose fold) and meets the macOS 20 pt
    /// minimum; Clear Search is a 44 × 44 pt target inside the column.
    @Test(arguments: Pose.allCases)
    func fieldSpansItsColumnWithAFullTarget(_ pose: Pose) async throws {
        let hosted = Self.host(pose)
        defer { hosted.close() }
        try await Self.settle(hosted, pose)
        let column = Self.column(pose)

        let field = try #require(nativeHostedAccessibilityFrame("fst.songs.filter-field", in: hosted.host))
        #expect(field.height >= Self.macMinimumTarget, "\(pose): field target \(field)")
        // The text field starts after the magnifier and ends at the capsule's padding.
        #expect(field.minX >= column.minX && field.minX <= column.minX + 40, "\(pose): field \(field) in \(column)")
        #expect(field.maxX <= column.maxX && field.maxX >= column.maxX - 14, "\(pose): field \(field) in \(column)")
        if let fold = BottomSearchFieldPlacement.pageHinge(for: pose.layout), pose.rightPage {
            #expect(!field.intersects(fold), "\(pose): field \(field) crosses the fold \(fold)")
        }

        hosted.driver.text = "pulse"
        _ = try await nativeHostedSettle(hosted.host) {
            nativeHostedAccessibilityFrame("fst.songs.filter-clear", in: hosted.host) != nil
        }
        let typed = try #require(nativeHostedAccessibilityFrame("fst.songs.filter-field", in: hosted.host))
        let clear = try #require(nativeHostedAccessibilityFrame("fst.songs.filter-clear", in: hosted.host))
        #expect(clear.width >= GlobalSearchField.clearTarget && clear.height >= GlobalSearchField.clearTarget,
                "\(pose): Clear Search target \(clear)")
        #expect(clear.minX >= typed.maxX - 0.5 && clear.maxX <= column.maxX, "\(pose): Clear Search \(clear) in \(column)")
        #expect(abs(clear.midY - typed.midY) <= 1, "\(pose): Clear Search centred on the field: \(clear) vs \(typed)")
    }

    // MARK: - Text scaling

    /// At the largest accessibility size the field keeps its column in every pose, named
    /// and inside the window, with a full-size Clear Search still inside the column.
    /// (Text growth is the iOS journey's: AppKit text fields do not take Dynamic Type.)
    @Test(arguments: Pose.allCases)
    func fieldKeepsItsColumnAtAccessibilitySizes(_ pose: Pose) async throws {
        let hosted = Self.host(pose, typeSize: .accessibility5)
        defer { hosted.close() }
        try await Self.settle(hosted, pose)
        let column = Self.column(pose)
        let field = try #require(nativeHostedAccessibilityFrame("fst.songs.filter-field", in: hosted.host))
        #expect(field.minX >= column.minX && field.maxX <= column.maxX, "\(pose): AX5 field \(field) in \(column)")
        #expect(field.maxY <= pose.layout.size.height, "\(pose): AX5 field \(field) clipped by the window")

        hosted.driver.text = "pulse"
        _ = try await nativeHostedSettle(hosted.host) {
            nativeHostedAccessibilityFrame("fst.songs.filter-clear", in: hosted.host) != nil
        }
        let clear = try #require(nativeHostedAccessibilityFrame("fst.songs.filter-clear", in: hosted.host))
        #expect(clear.maxX <= column.maxX && clear.maxY <= pose.layout.size.height, "\(pose): AX5 Clear Search \(clear)")
        #expect(clear.width >= GlobalSearchField.clearTarget && clear.height >= GlobalSearchField.clearTarget,
                "\(pose): AX5 Clear Search target \(clear)")
        let order = Self.readingOrder(hosted.host)
        #expect(order.filter { $0.identifier == "fst.songs.filter-field" }.map(\.label) == ["Filter Songs"])
        #expect(macAccessibilityFindings(order) == [], "\(pose)")
    }
}
#endif
