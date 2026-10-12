#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Feedback attachment strip accessibility (issue #356, backfilled by #486)

/// The Report an Issue / Request a Feature form shows attached media in a horizontal strip
/// that hides its scroll indicator (`scroll-indicators` R3, #356). These hosted checks pin
/// what that strip exposes on every Apple platform (the same SwiftUI runs on iPhone, iPad,
/// iPhone Duo and Mac): a named button per thumbnail and per remove action, read tile by
/// tile in visual order; every tile reachable with no visible indicator, including one
/// scrolled out of view; full 44 pt targets kept inside the clipping strip at the default
/// and largest text sizes; Remove through the accessibility press; and the disabled state
/// while the form sends.
///
/// The first run found each remove target starting 6 pt above the strip (clipped to 38 pt)
/// and the first tile reading Remove before its thumbnail (#486).
///
/// HIG Accessibility: "Strive for the platform's recommended minimum control size",
/// iOS/iPadOS default 44×44 pt; "Test support for VoiceOver … and verify labels." HIG Scroll
/// views: "Make scrollable content apparent, since indicators aren't always visible."
@MainActor
@Suite(.serialized)
struct FeedbackAttachmentStripAccessibilityTests {
    // MARK: - Fixture

    static let stripID = "fst.settings.feedback.attachments"
    /// About an iPhone Form row's content width: four tiles overflow it.
    static let size = CGSize(width: 330, height: 160)
    static let pointTolerance: CGFloat = 0.5

    /// Attachments the strip asked to remove.
    @MainActor final class RemovalRecorder {
        var removed: [UUID] = []
    }

    /// One hosted strip over private fixture files.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let attachments: [FeedbackAttachment]
        let recorder: RemovalRecorder
        let directory: URL

        func close() {
            window.orderOut(nil)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Host the strip with the form's limit of attachments: three photos and a video.
    ///
    /// - Parameters:
    ///   - typeSize: Dynamic Type size for the strip.
    ///   - disabled: Whether the form is sending (the sheet disables the strip).
    /// - Returns: The settled host and its fixture.
    /// - Throws: A fixture file that cannot be written or a capture failure.
    static func hostStrip(typeSize: DynamicTypeSize = .large, disabled: Bool = false) async throws -> Hosted {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fst-feedback-strip-a11y-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let names = ["screenshot-1.png", "screenshot-2.png", "screenshot-3.png", "recording.mov"]
        let attachments = try names.enumerated().map { index, name in
            let url = directory.appendingPathComponent(name)
            try Data().write(to: url)
            return FeedbackAttachment(
                fileURL: url, filename: name, mimeType: index == 3 ? "video/quicktime" : "image/png",
                byteCount: 2_048 * Int64(index + 1), isVideo: index == 3
            )
        }
        #expect(attachments.count == FeedbackLimits.attachments, "the strip at the form's attachment limit")
        let recorder = RemovalRecorder()
        let host = nativeHostedView(
            AnyView(
                FeedbackAttachmentStrip(attachments: attachments) { recorder.removed.append($0.id) }
                    .disabled(disabled)
                    .frame(width: size.width)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .preferredColorScheme(.dark)
                    .environment(\.dynamicTypeSize, typeSize)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        try await nativeHostedSettle(host) {
            nativeHostedAccessibilityFrame(openID(attachments.count), in: host) != nil
        }
        return Hosted(host: host, window: window, attachments: attachments, recorder: recorder, directory: directory)
    }

    static func openID(_ position: Int) -> String { "fst.settings.feedback.attachment.\(position)" }
    static func removeID(_ position: Int) -> String { "fst.settings.feedback.attachment.\(position).remove" }

    /// What VoiceOver reads, in navigation order: the elements inside the strip and each
    /// tile's container, without the containers themselves or the system scroll bar's parts.
    static func readable(_ host: NSView) -> [MacAXNode] {
        let containers: Set<String> = ["AXScrollArea", "AXGroup", "AXScrollBar", "AXValueIndicator"]
        let scrollerParts: Set<String> = ["AXIncrementArrow", "AXDecrementArrow", "AXIncrementPage", "AXDecrementPage"]
        return macAccessibilityTree(host, navigationOrder: true).filter {
            $0.isElement && !containers.contains($0.role) && !scrollerParts.contains($0.subrole)
        }
    }

    /// Each tile's container, in navigation order, with the elements it holds.
    static func tileGroups(_ host: NSView) -> [[MacAXNode]] {
        let tree = macAccessibilityTree(host, navigationOrder: true)
        return tree.indices.filter { tree[$0].role == "AXGroup" && tree[$0].subrole != "AXHostingView" }.map { start in
            tree[(start + 1)...].prefix { $0.depth > tree[start].depth }.filter(\.isElement)
        }
    }

    /// The strip's AppKit scroll view.
    static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap(scrollView(in:)).first
    }

    /// Frame of an element that must exist.
    static func frame(_ identifier: String, in host: NSView) throws -> CGRect {
        try #require(nativeHostedAccessibilityFrame(identifier, in: host), "\(identifier) frame")
    }

    // MARK: - Names, roles and reading order

    /// Each tile reads its thumbnail (kind, position, name, size, with the open hint) and
    /// then its remove button, tile by tile from the leading edge. The thumbnail's
    /// placeholder symbol, the video's play badge and the remove glyph stay out of the tree.
    @Test func tilesAreNamedButtonsReadThumbnailThenRemove() async throws {
        let hosted = try await Self.hostStrip()
        defer { hosted.close() }
        let nodes = Self.readable(hosted.host)
        macAccessibilityDump(macAccessibilityTree(hosted.host, navigationOrder: true), name: "feedback-attachment-strip")
        let dump = nodes.map(\.description).joined(separator: "\n")

        let expectedIDs = (1...hosted.attachments.count).flatMap { [Self.openID($0), Self.removeID($0)] }
        #expect(nodes.map(\.identifier) == expectedIDs, "thumbnail then remove, tile by tile:\n\(dump)")
        #expect(nodes.allSatisfy { $0.role == "AXButton" }, "every control is a button:\n\(dump)")
        // One container per tile, so the pair reads together and in this order on every
        // platform, whatever the remove button's frame (it sits above the thumbnail's top).
        let groups = Self.tileGroups(hosted.host).map { $0.map(\.identifier) }
        #expect(groups == (1...hosted.attachments.count).map { [Self.openID($0), Self.removeID($0)] },
                "one container per tile:\n\(dump)")
        for (index, attachment) in hosted.attachments.enumerated() {
            let position = index + 1
            let open = try #require(nodes.first { $0.identifier == Self.openID(position) })
            let remove = try #require(nodes.first { $0.identifier == Self.removeID(position) })
            #expect(open.spokenName == attachment.accessibilityLabel(position: position))
            #expect(open.spokenName.hasPrefix(position == 4 ? "Video 4, recording.mov, " : "Photo \(position), "))
            #expect(open.help == "Opens in the default app", "open hint: \(open)")
            #expect(remove.spokenName == "Remove \(attachment.filename)")
            #expect(open.isEnabled && remove.isEnabled)
        }
        // Visual order matches reading order: each tile starts after the previous one.
        let starts = try (1...hosted.attachments.count).map { try Self.frame(Self.openID($0), in: hosted.host).minX }
        #expect(starts == starts.sorted() && Set(starts).count == starts.count, "tiles lie leading to trailing: \(starts)")
        #expect(macAccessibilityFindings(macAccessibilityTree(hosted.host)) == [])
    }

    // MARK: - Hidden indicator

    /// The four tiles overflow the strip and its indicator is hidden on iOS/iPadOS, yet every
    /// tile, including one wholly past the trailing edge, is in the accessibility tree, so
    /// VoiceOver swipes reach it (and scroll it into view). On the Mac `.hidden` yields to
    /// System Settings' "Always" / mouse scroll bars, which show a horizontal bar; the strip
    /// never shows a vertical one (`scroll-indicators` R3).
    @Test func everyTileStaysReachableWithTheIndicatorHidden() async throws {
        let hosted = try await Self.hostStrip()
        defer { hosted.close() }
        let host = hosted.host
        let strip = try Self.frame(Self.stripID, in: host)
        let scroll = try #require(Self.scrollView(in: host), "the strip's scroll view")
        let content = try #require(scroll.documentView?.frame)
        #expect(content.width > strip.width + 44, "four tiles overflow the strip: \(content.width) in \(strip.width)")

        let last = try Self.frame(Self.openID(hosted.attachments.count), in: host)
        #expect(last.minX >= strip.maxX - Self.pointTolerance, "the last tile starts past the trailing edge: \(last)")
        let nodes = Self.readable(host)
        for position in 1...hosted.attachments.count {
            #expect(nodes.contains { $0.identifier == Self.openID(position) }, "tile \(position) reachable")
            #expect(nodes.contains { $0.identifier == Self.removeID(position) }, "remove \(position) reachable")
        }
        let stripNode = try #require(macAccessibilityTree(host).first { $0.identifier == Self.stripID })
        #expect(stripNode.role == "AXScrollArea", "the strip is a scroll area: \(stripNode)")

        #expect(!scroll.hasVerticalScroller || scroll.verticalScroller?.isHidden == true, "no vertical bar")
        if scroll.scrollerStyle == .legacy {
            #expect(scroll.hasHorizontalScroller && scroll.horizontalScroller?.isHidden == false,
                    "`.hidden` yields to always-visible Mac scroll bars (`.never` would not)")
        }
    }

    // MARK: - Target size and text scaling

    /// Every thumbnail and remove button is at least 44 pt and lies wholly inside the strip,
    /// which clips; a remove button never overlaps the next thumbnail. The layout and labels
    /// hold at the largest accessibility text size (thumbnails and targets are fixed size).
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func targetsAreFullSizeAndInsideTheStrip(typeSize: DynamicTypeSize) async throws {
        let hosted = try await Self.hostStrip(typeSize: typeSize)
        defer { hosted.close() }
        let host = hosted.host
        let scroll = try #require(Self.scrollView(in: host))
        // Scroll positions are in content coordinates: compare against the content's bounds,
        // with the strip's height, so a target clipped at the top or bottom fails.
        let strip = try Self.frame(Self.stripID, in: host)
        let content = CGRect(x: 0, y: strip.minY, width: try #require(scroll.documentView?.frame.width),
                             height: scroll.contentView.frame.height)
        let tolerance = Self.pointTolerance
        for position in 1...hosted.attachments.count {
            let open = try Self.frame(Self.openID(position), in: host)
            let remove = try Self.frame(Self.removeID(position), in: host)
            for (name, frame) in [("thumbnail \(position)", open), ("remove \(position)", remove)] {
                #expect(frame.width >= 44 - tolerance && frame.height >= 44 - tolerance, "\(name) is 44 pt: \(frame)")
                #expect(frame.minY >= content.minY - tolerance && frame.maxY <= content.maxY + tolerance,
                        "\(name) \(frame) is clipped by the strip \(content)")
                #expect(frame.minX >= content.minX - tolerance && frame.maxX <= content.maxX + tolerance,
                        "\(name) \(frame) lies inside the strip's content \(content)")
            }
            if position < hosted.attachments.count {
                let next = try Self.frame(Self.openID(position + 1), in: host)
                #expect(remove.maxX <= next.minX + tolerance, "remove \(position) \(remove) clear of thumbnail \(next)")
            }
        }
        let labels = Self.readable(host).map(\.spokenName)
        #expect(labels.count == 2 * hosted.attachments.count && labels.allSatisfy { !$0.isEmpty },
                "every control keeps its name at \(typeSize): \(labels)")
    }

    // MARK: - Activation and state

    /// Remove works through AXPress (VoiceOver VO-Space, Voice Control, Switch Control) and
    /// removes only that attachment.
    @Test func removeActivatesThroughAccessibilityPress() async throws {
        let hosted = try await Self.hostStrip()
        defer { hosted.close() }
        let remove = try #require(nativeHostedAccessibilityElement(Self.removeID(2), in: hosted.host))
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(remove.responds(to: press), "remove offers a press action")
        _ = remove.perform(press)
        try await nativeHostedSettle(hosted.host) { !hosted.recorder.removed.isEmpty }
        #expect(hosted.recorder.removed == [hosted.attachments[1].id])
    }

    /// While the form sends, the sheet disables the strip: every control reads as dimmed.
    @Test func sendingDisablesEveryControl() async throws {
        let hosted = try await Self.hostStrip(disabled: true)
        defer { hosted.close() }
        let nodes = Self.readable(hosted.host)
        let dump = nodes.map(\.description).joined(separator: "\n")
        #expect(nodes.count == 2 * hosted.attachments.count, "\(dump)")
        #expect(nodes.allSatisfy { !$0.isEnabled }, "every control reads as disabled:\n\(dump)")
    }
}
#endif
