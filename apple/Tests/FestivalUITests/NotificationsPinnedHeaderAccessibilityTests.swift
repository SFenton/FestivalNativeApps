#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Notifications pinned header accessibility (issues #322, #469)

/// What assistive technologies get from the Notifications sheet's rows while they scroll
/// under the pinned "New"/"Older" titles (`.agents/patterns/scroll-edge.md` R2, R5, R7;
/// `.agents/controls/notifications/ios.md`).
///
/// Issue #322 made each row hide the system separator and draw its own line, with two
/// zero-size guide markers, inside its masked row background
/// (``View/pinnedHeaderEdgeFadeRow(_:first:background:)``). These tests host the real
/// ``NotificationsSheet`` over a keyless fixture feed and sweep the List through "New" and
/// past the push of "Older", in VoiceOver's reading order (``macListReadingOrder(_:table:)``):
/// - the titles are headings, each read before its own rows;
/// - every row is one enabled, named button with its test ID, read in feed order, at
///   least 44 pt tall, and a row in the fade or cut by the title keeps the frame it has
///   clear of it (the mask is drawing only);
/// - the drawn separator, its guide markers and the mask expose nothing;
/// - no separator line draws under the pinned title, with the fade and with every
///   setting that turns it into a hard edge (R7).
///
/// macOS keeps the font size under `dynamicTypeSize`, so these are not text-scaling
/// evidence: the iPhone journey `NotificationsAccessibilityJourneyTests` runs the same
/// checks at AX5 (`apple-ci`).
@MainActor
struct NotificationsPinnedHeaderAccessibilityTests {
    static let size = CGSize(width: 420, height: 640)
    static let newCount = 8
    static let olderCount = 24
    static let rowPrefix = "fst.notifications.row."
    /// The rows' fade depth under the pinned title (`PinnedHeaderEdgeFade.height`).
    static let fade: CGFloat = 40
    /// Scroll offsets through "New" (its title pinned) and past the push of "Older".
    static let offsets: [Double] = [0] + Array(stride(from: 60.0, through: 720.0, by: 30.0))
        + Array(stride(from: 820.0, through: 1_240.0, by: 30.0))

    /// The hosted sheet, its List and the feed it shows.
    @MainActor
    struct Sheet {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let scroll: NSScrollView
        let table: NSTableView
        /// Feed rows by notification ID, in feed order.
        let notifications: [AppNotification]
        let cleanup: () -> Void

        /// The pinned title's top: the List's scroll-view top below its content inset.
        var pinTop: CGFloat {
            let frame = scroll.convert(scroll.bounds, to: host)
            return (host.isFlipped ? frame.minY : host.bounds.height - frame.maxY) + scroll.contentInsets.top
        }

        /// The pinned title's bottom edge, where the rows' fade starts.
        var pinBottom: CGFloat { pinTop + table.rect(ofRow: 0).height }

        /// Scroll the List to `offset` and wait for `title` to be in the tree.
        func scroll(to offset: Double, showing title: String) async throws -> CGImage {
            let clip = scroll.contentView
            clip.scroll(to: NSPoint(x: 0, y: CGFloat(offset) - scroll.contentInsets.top))
            scroll.reflectScrolledClipView(clip)
            return try await nativeHostedSettle(host, untilText: [title])
        }
    }

    /// The real sheet over a scrolling feed, in `mode`'s accessibility setting, settled.
    private func hostSheet(_ mode: BottomChromeFadeMode) async throws -> Sheet {
        let (session, accountId) = await scrollingNotificationsSession(
            newCount: Self.newCount, olderCount: Self.olderCount
        )
        let (defaults, suite) = mode.storage()
        let host = nativeHostedView(
            AnyView(mode.system(
                NotificationsSheet(session: session)
                    .frame(width: Self.size.width, height: Self.size.height)
                    .preferredColorScheme(.dark)
                    .background(BrandTokens.appBackground)
                    .defaultAppStorage(defaults)
            )),
            size: Self.size, forceGlassFallback: false
        )
        let window = nativeHostedWindow(host, size: Self.size)
        _ = try await nativeHostedSettle(host, untilText: ["New"])
        let scroll = try #require(listScrollView(in: host))
        let table = try #require(scroll.documentView as? NSTableView)
        return Sheet(
            host: host, window: window, scroll: scroll, table: table,
            notifications: session.notificationsCenter.notifications,
            cleanup: {
                window.orderOut(nil)
                forgetScrollingAccount(accountId)
                UserDefaults.standard.removePersistentDomain(forName: suite)
            }
        )
    }

    /// A row's place in the feed and the title it belongs under.
    private func feedIndex(_ node: MacAXNode, in sheet: Sheet) -> Int? {
        guard node.identifier.hasPrefix(Self.rowPrefix) else { return nil }
        let id = String(node.identifier.dropFirst(Self.rowPrefix.count))
        return sheet.notifications.firstIndex { $0.id == id }
    }

    // MARK: Reading order, names, roles and targets

    /// Swept through "New" and past the push of "Older": the List reads only the two
    /// headings and the rows, each row after its own section's heading and in feed order,
    /// named with its spoken label, an enabled button ≥ 44 pt tall; a row in the fade or
    /// cut by the pinned title keeps its clear frame; nothing else is exposed and nothing
    /// is unnamed. The same with the fade and with each hard-edge setting.
    @Test(arguments: [
        BottomChromeFadeMode.standard, .systemReduceTransparency, .lessTransparency, .moreContrast,
    ])
    func rowsUnderThePinnedTitleKeepTheirAccessibility(mode: BottomChromeFadeMode) async throws {
        let sheet = try await hostSheet(mode)
        defer { sheet.cleanup() }
        var clearFrames: [String: CGRect] = [:]
        var faded = Set<String>(), cut = Set<String>()
        for offset in Self.offsets {
            _ = try await sheet.scroll(to: offset, showing: offset < 800 ? "New" : "Older")
            let order = macListReadingOrder(sheet.host, table: sheet.table)
            macAccessibilityDump(order.all, name: "notifications-pinned-\(mode.rawValue)-\(Int(offset))")
            let context = "\(mode.rawValue) at \(Int(offset)) pt: \(order.rows)"
            #expect(macAccessibilityFindings(order.all).isEmpty, "\(context)")

            var heading: String?
            var lastIndex = -1
            for node in order.rows {
                if node.role == "AXHeading" {
                    #expect(["New", "Older"].contains(node.spokenName), "\(context)")
                    heading = node.spokenName
                    continue
                }
                let index = try #require(
                    feedIndex(node, in: sheet), "not a heading or row (separator or marker exposed?): \(node); \(context)"
                )
                let notification = sheet.notifications[index]
                #expect(node.role == "AXButton", "\(node)")
                #expect(node.isEnabled, "\(node)")
                #expect(node.spokenName == NotificationRow.accessibilityLabel(notification), "\(node)")
                #expect(index > lastIndex, "rows out of feed order: \(context)")
                lastIndex = index
                // Every row after the first visible heading reads under its own section.
                if let heading {
                    #expect(heading == (index < Self.newCount ? "New" : "Older"), "\(node) under \(heading)")
                }
                let frame = try #require(nativeHostedAccessibilityFrame(node.identifier, in: sheet.host))
                #expect(frame.height >= 44, "\(node) is \(frame.height) pt tall")
                if frame.minY >= sheet.pinBottom + Self.fade {
                    clearFrames[node.identifier] = clearFrames[node.identifier] ?? frame
                } else if frame.maxY > sheet.pinBottom, let clear = clearFrames[node.identifier] {
                    if frame.minY < sheet.pinBottom { cut.insert(node.identifier) } else { faded.insert(node.identifier) }
                    #expect(abs(frame.height - clear.height) <= 0.5 && abs(frame.width - clear.width) <= 0.5,
                            "the mask changed \(node.identifier)'s frame: \(clear) → \(frame) (\(context))")
                }
            }
            // At rest both visible titles read, "New" first; scrolled, at most one of each.
            let headings = order.rows.filter { $0.role == "AXHeading" }.map(\.spokenName)
            if offset == 0 { #expect(headings.first == "New", "\(context)") }
            #expect(Set(headings).count == headings.count, "a title read twice: \(context)")
        }
        #expect(!faded.isEmpty, "no row was read inside the fade band")
        #expect(!cut.isEmpty, "no row was read while the pinned title cut it")
    }

    // MARK: Separators

    /// Issue #322 in every edge mode: swept through "New" and past the push of "Older", no
    /// separator line (dim ink, unlike the title's bright text) draws in the pinned title's
    /// band, with the fade (R2) and with each hard-edge setting (R7), while separators
    /// lower down still draw.
    @Test(arguments: [
        BottomChromeFadeMode.standard, .systemReduceTransparency, .lessTransparency, .moreContrast,
    ])
    func separatorsNeverDrawUnderThePinnedTitle(mode: BottomChromeFadeMode) async throws {
        let sheet = try await hostSheet(mode)
        defer { sheet.cleanup() }
        // App background mean ≈ 27; a separator ≈ 49 (system separator color over it).
        let separatorInk = 40
        let headerRow = sheet.table.rect(ofRow: 0).height
        var leaks: [Double] = []
        var separatorsBelow = 0
        for offset in Self.offsets.dropFirst() {
            let image = try await sheet.scroll(to: offset, showing: offset < 800 ? "New" : "Older")
            // Right of the title, above the header's own bottom hairline.
            let band = CGRect(x: 90, y: sheet.pinTop + 1, width: Self.size.width - 110, height: headerRow - 5)
            if nativeHostedBrightSamples(in: band, of: image, hostSize: Self.size, threshold: separatorInk) > 0 {
                leaks.append(offset)
                _ = try nativeHostedPNG(
                    image, filename: "notifications-separator-\(mode.rawValue)-\(Int(offset)).png",
                    environment: "FST_HISTORY_RENDER_OUT"
                )
            }
            // A thin strip between the rows' text and their chevrons: only separators draw there.
            let strip = CGRect(x: 340, y: sheet.pinTop + 100, width: 28, height: 300)
            separatorsBelow += nativeHostedBrightSamples(in: strip, of: image, hostSize: Self.size, threshold: separatorInk)
        }
        #expect(leaks.isEmpty, "\(mode.rawValue): separator drawn under the pinned title at offsets \(leaks)")
        #expect(separatorsBelow > 0, "\(mode.rawValue): no separators drew below the title")
    }
}
#endif
