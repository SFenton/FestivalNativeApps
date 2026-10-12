#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - iPhone Duo bottom Filter Songs field (issue #333, backfilled by #474)

/// Accessibility of the Songs Filter field #333 moved to the bottom of the page on iPhone
/// Duo (`BottomSearchField`, the shared ``GlobalSearchField`` on its floating surface),
/// rendered as `SongsScreen` places it: a bottom safe-area inset under the list, in the
/// Duo layout, on the right page across a book-pose fold.
///
/// - Name, role, state: one text field named "Filter Songs" with the field's identifier;
///   with text, one "Clear Search" button that empties it when pressed (AXPress, the
///   keyboard and switch path), and none while empty.
/// - Reading order: the field reads after the rows drawn above it (visual order, top to
///   bottom), then its Clear button; the decorative magnifying glass is not an element.
/// - Target size: the Clear button is at least 44 × 44 pt (HIG Accessibility: iOS/iPadOS
///   default control size 44×44 pt), on the field's line, inside the page.
///
/// In macOS hosting the field's accessibility frame is its text line, not the capsule;
/// the capsule's tap-to-focus target and text scaling (macOS hosting has no Dynamic
/// Type) are checked on the simulator by the journey.
///
/// Reduce Transparency and Increase Contrast are `BottomSearchFieldSurfaceRenderTests`;
/// the production chrome (folded Duo window, default and AX5, system audit) is the
/// `SongsBottomFilterFieldJourneyTests` simulator journey.
@MainActor
@Suite(.serialized)
struct SongsBottomFilterFieldAccessibilityTests {
    static let fieldID = "fst.songs.filter-field"
    static let clearID = "fst.songs.filter-clear"
    /// iPhone Duo inner display, landscape, beside the vertical bar.
    static let size = CGSize(width: 867, height: 669)
    /// A 24 pt book-pose fold through the middle of the 951 pt window.
    static let fold = CGRect(x: 463.5, y: 0, width: 24, height: 669)

    /// The page: rows above the field, the field in the bottom safe-area inset.
    private struct Page: View {
        @State var text: String
        let hinge: CGRect?

        var body: some View {
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { index in
                    Text("Song \(index + 1)")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 16)
                        .accessibilityIdentifier("row.\(index)")
                }
                Spacer(minLength: 0)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BottomSearchField(
                    text: $text, prompt: "Filter Songs", accessibilityLabel: "Filter Songs",
                    identifier: SongsBottomFilterFieldAccessibilityTests.fieldID,
                    clearIdentifier: SongsBottomFilterFieldAccessibilityTests.clearID,
                    hinge: hinge, space: "page"
                )
            }
            .coordinateSpace(.named("page"))
        }
    }

    /// A hosted page and its window.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
    }

    /// Host the page in the Duo inner landscape layout and wait for the field.
    ///
    /// - Parameters:
    ///   - text: The field's starting text.
    ///   - bookPose: Whether a book-pose fold divides the page.
    ///   - typeSize: The Dynamic Type size.
    /// - Returns: The hosted page, field laid out.
    static func host(text: String, bookPose: Bool = false, typeSize: DynamicTypeSize = .large) async throws -> Hosted {
        let layout = BottomSearchFieldPlacementTests.duo(
            bookPose ? .partiallyOpen : .fullyOpen, size: CGSize(width: 951, height: 669),
            fold: bookPose ? fold : nil
        )
        let view = Page(text: text, hinge: bookPose ? fold : nil)
            .frame(width: size.width, height: size.height)
            .environment(\.deviceLayout, layout)
            .dynamicTypeSize(typeSize)
            .preferredColorScheme(.dark)
        let host = nativeHostedView(AnyView(view), size: size)
        let window = nativeHostedWindow(host, size: size)
        _ = try await nativeHostedSettle(host) {
            guard let field = nativeHostedAccessibilityFrame(fieldID, in: host) else { return false }
            return !bookPose || field.minX > fold.maxX
        }
        return Hosted(host: host, window: window)
    }

    /// The elements VoiceOver reaches, in order, with a printable form for failures.
    static func reachable(_ host: NSView) -> (nodes: [(node: MacAXNode, frame: CGRect?)], dump: String) {
        let nodes = nativeHostedReachableElements(host)
        return (nodes, nodes.map { "\($0.node) \($0.frame.map { "\($0)" } ?? "")" }.joined(separator: "\n"))
    }

    // MARK: Name, role, order, size

    /// Empty: one named text field after the rows, below them, with no Clear button and
    /// no element for the decorative glass.
    @Test(arguments: [false, true])
    func emptyFieldIsANamedTextFieldReadAfterTheRows(bookPose: Bool) async throws {
        let page = try await Self.host(text: "", bookPose: bookPose)
        defer { page.window.orderOut(nil) }
        let (nodes, dump) = Self.reachable(page.host)
        let fields = nodes.indices.filter { nodes[$0].node.identifier == Self.fieldID }
        #expect(fields.count == 1, "Filter Songs fields\n\(dump)")
        let index = try #require(fields.first)
        let field = nodes[index]
        #expect(field.node.role == "AXTextField", "role\n\(dump)")
        #expect(field.node.label == "Filter Songs", "name\n\(dump)")
        #expect(!nodes.contains { $0.node.identifier == Self.clearID }, "Clear shown while empty\n\(dump)")
        #expect(!nodes.contains { $0.node.role == "AXImage" }, "the glass is decorative\n\(dump)")

        // Visual order: every row above the field reads before it.
        let rows = nodes.indices.filter { nodes[$0].node.identifier.hasPrefix("row.") }
        #expect(rows.count == 4, "rows\n\(dump)")
        #expect(rows.allSatisfy { $0 < index }, "the field reads before a row above it\n\(dump)")
        let frame = try #require(field.frame)
        let lastRow = try #require(rows.last.flatMap { nodes[$0].frame })
        #expect(frame.minY >= lastRow.maxY, "the field \(frame) is not below the rows \(lastRow)")

        #expect(frame.height > 0, "field \(frame)")
        #expect(frame.maxY <= Self.size.height + 0.5 && frame.maxX <= Self.size.width + 0.5, "field \(frame)")
        if bookPose {
            #expect(frame.minX >= Self.fold.maxX + 16 - 0.5, "the field is not on the right page: \(frame)")
        }
    }

    /// With text: Clear Search follows the field, is a 44 pt button and empties it.
    @Test(arguments: [false, true])
    func clearButtonIsANamedFullSizeTargetThatEmptiesTheField(bookPose: Bool) async throws {
        let page = try await Self.host(text: "Song", bookPose: bookPose)
        defer { page.window.orderOut(nil) }
        _ = try await nativeHostedSettle(page.host) {
            nativeHostedAccessibilityFrame(Self.clearID, in: page.host) != nil
        }
        let (nodes, dump) = Self.reachable(page.host)
        let field = try #require(nodes.firstIndex { $0.node.identifier == Self.fieldID }, "field\n\(dump)")
        let clears = nodes.indices.filter { nodes[$0].node.identifier == Self.clearID }
        #expect(clears.count == 1, "Clear buttons\n\(dump)")
        let clear = try #require(clears.first)
        #expect(nodes[clear].node.role == "AXButton", "role\n\(dump)")
        #expect(nodes[clear].node.spokenName == "Clear Search", "name\n\(dump)")
        #expect(nodes[field].node.value == "Song", "the field's value\n\(dump)")
        #expect(clear == field + 1, "Clear does not read right after the field\n\(dump)")
        let fieldFrame = try #require(nodes[field].frame)
        let clearFrame = try #require(nodes[clear].frame)
        #expect(clearFrame.width >= 44 - 0.5 && clearFrame.height >= 44 - 0.5,
                "Clear Search is smaller than 44 × 44 pt: \(clearFrame)")
        #expect(clearFrame.minX >= fieldFrame.maxX - 0.5, "Clear \(clearFrame) overlaps the field \(fieldFrame)")
        #expect(abs(clearFrame.midY - fieldFrame.midY) <= 1, "Clear \(clearFrame) is off the field's line \(fieldFrame)")
        #expect(clearFrame.maxY <= Self.size.height + 0.5, "Clear leaves the page: \(clearFrame)")
        if bookPose {
            #expect(clearFrame.maxX <= Self.size.width - 16 + 0.5, "Clear leaves the right page: \(clearFrame)")
        }

        let element = try #require(nativeHostedAccessibilityElement(Self.clearID, in: page.host))
        _ = element.perform(NSSelectorFromString("accessibilityPerformPress"))
        _ = try await nativeHostedSettle(page.host) {
            nativeHostedAccessibilityFrame(Self.clearID, in: page.host) == nil
        }
        let after = Self.reachable(page.host)
        #expect(!after.nodes.contains { $0.node.identifier == Self.clearID }, "Clear stayed\n\(after.dump)")
        let emptied = try #require(after.nodes.first { $0.node.identifier == Self.fieldID })
        #expect(emptied.node.value.isEmpty, "the field kept '\(emptied.node.value)'")
    }
}
#endif
