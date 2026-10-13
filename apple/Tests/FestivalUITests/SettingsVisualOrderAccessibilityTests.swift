#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Settings › Show Instrument Icons and Independent Visual Order accessibility (#494, for #372)
//
// #372 aligned Show Instrument Icons, Enable Independent Song Row Visual Order and the
// drag-to-reorder Song Row Visual Order list with the web, and opened the list on the right
// of the list/detail Settings. These hosted checks (macOS host, `apple-ci`) pin what
// VoiceOver, Voice Control and Switch Control get from that region, since it is the same
// SwiftUI on iPhone, iPad, iPhone Duo and Mac:
// - both switches are switches with the web's labels, their state and a hint, read in the
//   web's App Settings order;
// - pressing the Independent Visual Order switch (AXPress, as Switch Control and Full
//   Keyboard Access do) reveals the list right after it, with or without Reduce Motion;
// - each row is one static-text element named by the web's label, valued "n of N", with
//   no separate grip element (before #494 the Mac tree gave it an unknown role and dropped
//   the position), and its Move Up / Move Down actions reorder and save without a drag;
// - every row keeps a 44 pt target and wraps instead of clipping in a narrow column
//   (macOS hosting doesn't scale Dynamic Type, so iOS AX5 is
//   `SettingsVisualOrderAccessibilityJourneyTests`);
// - in the list/detail Settings the Song Row Visual Order row is a named button listed only
//   while the switch is on, and its page on the right reads the same rows and actions.
//
// HIG Accessibility: "Offer another physical interaction for core functionality"; HIG
// Drag and drop: "Offer alternatives to drag and drop"; HIG VoiceOver: "be sure to keep
// labels current as interface and content change"; HIG Accessibility (Mobility): iOS
// 44×44 pt default control size.

/// Accessibility of Settings' Show Instrument Icons, Independent Visual Order and Song
/// Row Visual Order (#372).
@MainActor
@Suite(.serialized)
struct SettingsVisualOrderAccessibilityTests {
    static let iconsID = "fst.settings.show-instrument-icons"
    static let visualOrderID = "fst.settings.enable-visual-order"
    static let listID = "fst.settings.song-row-order"
    static let pathDefaultID = "fst.settings.path-default-view"
    static let topicRowID = SettingsTopic.songRowOrder.accessibilityIdentifier
    static let orderKey = "fst.settings.songRowVisualOrder"
    static let enabledKey = "fst.settings.enableVisualOrder"

    /// The web's `DEFAULT_METADATA_ORDER` row titles (`METADATA_SORT_DISPLAY`).
    static let defaultLabels = [
        "Score", "Percentage", "Percentile", "Stars", "Season Achieved", "Song Intensity", "Difficulty",
        "Last Played",
    ]

    /// One hosted Settings page in an offscreen window over a private store.
    @MainActor
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }

        /// The settled accessibility tree, in navigation order.
        func tree(_ name: String) -> [MacAXNode] {
            host.layoutSubtreeIfNeeded()
            let nodes = macAccessibilityTree(host, navigationOrder: true)
            macAccessibilityDump(nodes, name: "settings-visual-order-\(name)")
            return nodes
        }

        /// The reorder rows in reading order.
        func rows(_ name: String) -> [MacAXNode] {
            tree(name).filter { $0.isElement && $0.identifier.hasPrefix(SettingsVisualOrderAccessibilityTests.listID + ".") }
        }

        /// The realized element with `identifier`.
        func element(_ identifier: String) throws -> NSObject {
            try #require(nativeHostedAccessibilityElement(identifier, in: host), "\(identifier) is realized")
        }
    }

    /// Host Settings.
    ///
    /// - Parameters:
    ///   - enabled: Seeds Enable Independent Song Row Visual Order.
    ///   - reduceMotion: Settings' in-app Reduce Motion.
    ///   - listDetail: Host the list/detail list (iPad, unfolded Duo landscape).
    ///   - topic: Host one topic's page on the right instead of the whole page.
    ///   - seed: Extra stored values.
    ///   - until: Identifier that must be realized before the test reads the tree.
    /// - Returns: The hosted page.
    static func host(
        enabled: Bool = false, reduceMotion: Bool = true, listDetail: Bool = false,
        topic: SettingsTopic? = nil, seed: [String: Any] = [:], until: String
    ) async throws -> Hosted {
        let suiteName = "fst.tests.settings-visual-order.\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(enabled, forKey: enabledKey)
        storage.set(reduceMotion, forKey: "fst.accessibility.reduceMotion")
        for (key, value) in seed { storage.set(value, forKey: key) }
        let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
        let size = CGSize(width: 402, height: topic == nil ? 2600 : 900)
        let select = ListDetailSelectAction(section: .settings, page: .settings, close: {}) { _ in }
        let page = NavigationStack { SettingsScreen(session: session, topic: topic) }
            .environment(\.listDetailSelect, listDetail ? select : nil)
            .frame(width: size.width, height: size.height)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark)
        let host = nativeHostedView(AnyView(page), size: size)
        let window = nativeHostedWindow(host, size: size)
        let hosted = Hosted(host: host, window: window, storage: storage, suiteName: suiteName)
        do {
            _ = try await nativeHostedSettle(host) { nativeHostedAccessibilityElement(until, in: host) != nil }
        } catch {
            hosted.close()
            throw error
        }
        return hosted
    }

    /// The named custom accessibility actions an element offers.
    static func actions(_ element: NSObject) -> [NSAccessibilityCustomAction] {
        guard element.responds(to: NSSelectorFromString("accessibilityCustomActions")) else { return [] }
        return (element.value(forKey: "accessibilityCustomActions") as? [NSAccessibilityCustomAction]) ?? []
    }

    /// Perform the custom action named `name` on `element`.
    ///
    /// - Returns: Whether the element offered the action.
    @discardableResult
    static func perform(_ name: String, on element: NSObject) -> Bool {
        guard let action = actions(element).first(where: { $0.name == name }) else { return false }
        if let handler = action.handler {
            _ = handler()
        } else if let target = action.target as? NSObject, let selector = action.selector {
            _ = target.perform(selector, with: action)
        } else {
            return false
        }
        return true
    }

    // MARK: - Switches

    /// Both switches are named switches with the web's labels, their default state and a
    /// hint, read Show Instrument Icons → Independent Visual Order → CHOpt default view;
    /// with the switch off no reorder row is reachable.
    @Test func switchesAreNamedWithTheirStateInWebOrder() async throws {
        let hosted = try await Self.host(until: Self.visualOrderID)
        defer { hosted.close() }
        let nodes = hosted.tree("switches-off")
        let icons = try #require(nodes.first { $0.identifier == Self.iconsID })
        #expect(icons.isElement && icons.role == "AXCheckBox", "a switch: \(icons)")
        #expect(icons.spokenName.contains("Show Instrument Icons"), "\(icons)")
        #expect(icons.value == "1", "on by default: \(icons)")
        #expect(icons.help.contains("full combo"), "the hint names what it shows: \(icons)")

        let order = try #require(nodes.first { $0.identifier == Self.visualOrderID })
        #expect(order.isElement && order.role == "AXCheckBox", "a switch: \(order)")
        #expect(order.spokenName.contains("Enable Independent Song Row Visual Order"), "\(order)")
        #expect(order.value == "0", "off by default: \(order)")

        let ids = nodes.filter(\.isElement).map(\.identifier)
        let iconsIndex = try #require(ids.firstIndex(of: Self.iconsID))
        let orderIndex = try #require(ids.firstIndex(of: Self.visualOrderID))
        let pathIndex = try #require(ids.firstIndex { $0.hasPrefix(Self.pathDefaultID) })
        #expect(iconsIndex < orderIndex && orderIndex < pathIndex, "web App Settings order: \(ids)")
        #expect(!ids.contains { $0.hasPrefix(Self.listID + ".") }, "no reorder rows while off: \(ids)")
        #expect(!nodes.contains { $0.isElement && $0.spokenName == "Song Row Visual Order" })

        for id in [Self.iconsID, Self.visualOrderID] {
            let element = try hosted.element(id)
            #expect((element.value(forKey: "isAccessibilityEnabled") as? Bool) == true, "\(id) is enabled")
        }
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")
    }

    /// Pressing Show Instrument Icons (AXPress) turns it off and saves it.
    @Test func pressingShowInstrumentIconsSavesIt() async throws {
        let hosted = try await Self.host(until: Self.iconsID)
        defer { hosted.close() }
        _ = try hosted.element(Self.iconsID).perform(NSSelectorFromString("accessibilityPerformPress"))
        _ = try await nativeHostedSettle(hosted.host) {
            hosted.storage.object(forKey: "fst.settings.showInstrumentIcons") as? Bool == false
        }
        #expect(hosted.storage.object(forKey: "fst.settings.showInstrumentIcons") as? Bool == false)
        _ = try await nativeHostedSettle(hosted.host) {
            hosted.tree("icons-off").first { $0.identifier == Self.iconsID }?.value == "0"
        }
        #expect(hosted.tree("icons-off").first { $0.identifier == Self.iconsID }?.value == "0")
    }

    /// Pressing Independent Visual Order reveals the list right after its switch, its
    /// header first, rows in the web's default order, with and without Reduce Motion.
    @Test(arguments: [true, false])
    func pressingTheSwitchRevealsTheListAfterIt(reduceMotion: Bool) async throws {
        let hosted = try await Self.host(reduceMotion: reduceMotion, until: Self.visualOrderID)
        defer { hosted.close() }
        _ = try hosted.element(Self.visualOrderID).perform(NSSelectorFromString("accessibilityPerformPress"))
        _ = try await nativeHostedSettle(hosted.host) { hosted.rows("reveal").count == Self.defaultLabels.count }
        #expect(hosted.storage.bool(forKey: Self.enabledKey))

        let nodes = hosted.tree("revealed-\(reduceMotion ? "reduce-motion" : "animated")")
        let elements = nodes.filter(\.isElement)
        let order = try #require(elements.firstIndex { $0.identifier == Self.visualOrderID })
        #expect(elements[order].value == "1", "the switch reads on: \(elements[order])")
        let header = try #require(elements.firstIndex { $0.spokenName == "Song Row Visual Order" })
        let rows = elements.indices.filter { elements[$0].identifier.hasPrefix(Self.listID + ".") }
        let path = try #require(elements.firstIndex { $0.identifier.hasPrefix(Self.pathDefaultID) })
        #expect(order < header, "the list's title follows its switch")
        #expect(rows.allSatisfy { header < $0 && $0 < path }, "rows between the title and CHOpt: \(elements.map(\.identifier))")
        #expect(rows.map { elements[$0].label } == Self.defaultLabels)
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")
    }

    // MARK: - Rows

    /// Each row is one element named by its web label, valued by its position, hinted,
    /// with Move Up / Move Down actions and no separate grip element.
    @Test func rowsAreOneNamedElementWithPositionAndMoveActions() async throws {
        let hosted = try await Self.host(enabled: true, until: "\(Self.listID).score")
        defer { hosted.close() }
        let rows = hosted.rows("rows")
        #expect(rows.map(\.label) == Self.defaultLabels)
        let count = Self.defaultLabels.count
        #expect(rows.map(\.value) == (1...count).map { "\($0) of \(count)" })
        #expect(rows.map(\.identifier) == MetadataField.defaultSongRowOrder.map { "\(Self.listID).\($0.rawValue)" })
        for row in rows {
            #expect(row.role == "AXStaticText", "static text, not an unknown role that drops the position: \(row)")
            #expect(row.help == "Drag the handle to reorder, or use the Move actions.", "\(row)")
            let element = try hosted.element(row.identifier)
            #expect(Set(Self.actions(element).map(\.name)) == ["Move Up", "Move Down"], "\(row.label) actions")
        }
        // The grip is decorative: nothing in the list is read except its rows.
        let list = hosted.tree("rows")
        let listIndex = try #require(list.firstIndex { $0.identifier == Self.listID })
        let inside = list[(listIndex + 1)...].prefix { $0.depth > list[listIndex].depth }
        let unexpected = inside.filter { $0.isElement && !$0.identifier.hasPrefix(Self.listID + ".") }
        #expect(unexpected.isEmpty, "only rows are read inside the list: \(unexpected)")
        #expect(!inside.contains { $0.isElement && $0.role == "AXImage" }, "no grip image element")
        #expect(macAccessibilityFindings(list).isEmpty, "\(macAccessibilityFindings(list))")
    }

    /// Move Down and Move Up reorder the rows, update the spoken positions and save the
    /// order; a move past either end does nothing.
    @Test func moveActionsReorderAndSaveWithoutADrag() async throws {
        let hosted = try await Self.host(enabled: true, until: "\(Self.listID).score")
        defer { hosted.close() }
        let score = "\(Self.listID).score"
        #expect(Self.perform("Move Up", on: try hosted.element(score)), "Move Up is offered at the top")
        #expect(hosted.rows("top-move-up").first?.identifier == score, "the first row stays first")

        #expect(Self.perform("Move Down", on: try hosted.element(score)))
        _ = try await nativeHostedSettle(hosted.host) {
            hosted.rows("moved-down").first { $0.identifier == score }?.value == "2 of 8"
        }
        var rows = hosted.rows("moved-down")
        #expect(rows.prefix(2).map(\.label) == ["Percentage", "Score"])
        #expect(rows.first { $0.identifier == score }?.value == "2 of 8")
        #expect(rows.first { $0.label == "Percentage" }?.value == "1 of 8")
        #expect(hosted.storage.string(forKey: Self.orderKey)?.hasPrefix("percentage,score,") == true)

        #expect(Self.perform("Move Up", on: try hosted.element(score)))
        _ = try await nativeHostedSettle(hosted.host) {
            hosted.rows("moved-up").first { $0.identifier == score }?.value == "1 of 8"
        }
        rows = hosted.rows("moved-up")
        #expect(rows.map(\.label) == Self.defaultLabels)
        #expect(hosted.storage.string(forKey: Self.orderKey) == SettingsOrder.encode(MetadataField.defaultSongRowOrder))

        let last = "\(Self.listID).lastPlayed"
        #expect(Self.perform("Move Down", on: try hosted.element(last)))
        #expect(hosted.rows("bottom-move-down").last?.identifier == last, "the last row stays last")
    }

    /// With a metadata field hidden, positions count only the rows read, and a move keeps
    /// the hidden field's saved place.
    @Test func positionsCountOnlyVisibleRows() async throws {
        let hosted = try await Self.host(
            enabled: true, seed: ["fst.settings.metadataPercentage": false], until: "\(Self.listID).score"
        )
        defer { hosted.close() }
        let rows = hosted.rows("hidden-field")
        #expect(!rows.contains { $0.label == "Percentage" })
        #expect(rows.map(\.value) == (1...7).map { "\($0) of 7" })
        #expect(Self.perform("Move Down", on: try hosted.element("\(Self.listID).score")))
        _ = try await nativeHostedSettle(hosted.host) {
            hosted.rows("hidden-field-moved").first { $0.label == "Score" }?.value == "2 of 7"
        }
        #expect(hosted.rows("hidden-field-moved").prefix(2).map(\.label) == ["Percentile", "Score"])
        let saved = MetadataField.savedSongRowOrder(hosted.storage.string(forKey: Self.orderKey) ?? "")
        #expect(saved.count == MetadataField.allCases.count && saved.contains(.percentage))
    }

    // MARK: - Target size and text scaling

    /// Every row is at least 44 pt tall and spans the list, so the whole row is a target
    /// for VoiceOver and Voice Control.
    @Test func rowsKeepA44PointTarget() async throws {
        let hosted = try await Self.host(enabled: true, until: "\(Self.listID).score")
        defer { hosted.close() }
        let list = try #require(nativeHostedAccessibilityFrame(Self.listID, in: hosted.host))
        var previous: CGRect?
        for field in MetadataField.defaultSongRowOrder {
            let frame = try #require(nativeHostedAccessibilityFrame("\(Self.listID).\(field.rawValue)", in: hosted.host))
            #expect(frame.height >= 44 - 0.5, "\(field) row is 44 pt tall: \(frame)")
            #expect(frame.width >= list.width - 2, "\(field) row spans the list: \(frame) vs \(list)")
            if let previous { #expect(frame.minY >= previous.maxY - 0.5, "rows read top to bottom") }
            previous = frame
        }
    }

    /// In a column too narrow for a label (the width effect of large text), rows wrap and
    /// grow instead of clipping, stay one element each and keep their actions.
    @Test func rowsWrapInANarrowColumn() async throws {
        var order: [MetadataField] = MetadataField.defaultSongRowOrder
        func list() -> some View {
            SettingsReorderList(
                items: order, identifier: Self.listID, label: \.reorderLabel, key: \.rawValue
            ) { order = $0 }
        }
        let wide = NSHostingController(rootView: list().preferredColorScheme(.dark))
            .sizeThatFits(in: CGSize(width: 360, height: 10_000))
        let width: CGFloat = 96
        let narrow = NSHostingController(rootView: list().preferredColorScheme(.dark))
            .sizeThatFits(in: CGSize(width: width, height: 10_000))
        #expect(narrow.width <= width + 0.5, "the list fits its column: \(narrow)")
        #expect(narrow.height > wide.height + 20, "long labels wrap: \(narrow) vs \(wide)")

        let size = CGSize(width: width, height: narrow.height + 40)
        let host = nativeHostedView(
            list().frame(width: width, alignment: .top).background(BrandTokens.cardBackground)
                .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        _ = try await nativeHostedSettle(host) {
            nativeHostedAccessibilityElement("\(Self.listID).intensity", in: host) != nil
        }
        let nodes = macAccessibilityTree(host).filter { $0.isElement && $0.identifier.hasPrefix(Self.listID + ".") }
        #expect(nodes.map(\.label) == Self.defaultLabels, "rows keep their full names")
        let intensity = try #require(nativeHostedAccessibilityFrame("\(Self.listID).intensity", in: host))
        let score = try #require(nativeHostedAccessibilityFrame("\(Self.listID).score", in: host))
        #expect(intensity.height > score.height + 10, "Song Intensity wraps onto more lines: \(intensity) vs \(score)")
        #expect(intensity.maxX <= width + 0.5, "the row stays inside its column: \(intensity)")
        let element = try #require(nativeHostedAccessibilityElement("\(Self.listID).intensity", in: host))
        #expect(Set(Self.actions(element).map(\.name)) == ["Move Up", "Move Down"])
    }

    // MARK: - List/detail Settings

    /// In the list/detail list the Song Row Visual Order row is a named button with its
    /// description as the hint, read right after its switch, and listed only while the
    /// switch is on; the inline list is not repeated beside it.
    @Test func listDetailRowIsANamedButtonOnlyWhileTheSwitchIsOn() async throws {
        let hosted = try await Self.host(enabled: true, listDetail: true, until: Self.topicRowID)
        defer { hosted.close() }
        let nodes = hosted.tree("list-detail-on")
        let elements = nodes.filter(\.isElement)
        let row = try #require(elements.first { $0.identifier == Self.topicRowID })
        #expect(row.role == "AXButton", "a button: \(row)")
        #expect(row.label == "Song Row Visual Order")
        #expect(row.help == SettingsTopic.songRowOrder.subtitle)
        let ids = elements.map(\.identifier)
        let switchIndex = try #require(ids.firstIndex(of: Self.visualOrderID))
        let rowIndex = try #require(ids.firstIndex(of: Self.topicRowID))
        #expect(rowIndex == switchIndex + 1, "the row follows its switch: \(ids)")
        #expect(!ids.contains { $0.hasPrefix(Self.listID + ".") }, "the list opens on the right, not inline")
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")

        _ = try hosted.element(Self.visualOrderID).perform(NSSelectorFromString("accessibilityPerformPress"))
        _ = try await nativeHostedSettle(hosted.host) {
            nativeHostedAccessibilityElement(Self.topicRowID, in: hosted.host) == nil
        }
        #expect(!hosted.tree("list-detail-off").contains { $0.identifier == Self.topicRowID })
        #expect(hosted.tree("list-detail-off").first { $0.identifier == Self.visualOrderID }?.value == "0")
    }

    /// The page on the right reads the same rows, positions and Move actions as the inline
    /// list, and Move Down saves the order.
    @Test func rightHandPageReadsTheSameRowsAndActions() async throws {
        let hosted = try await Self.host(enabled: true, topic: .songRowOrder, until: "\(Self.listID).score")
        defer { hosted.close() }
        let rows = hosted.rows("topic-page")
        #expect(rows.map(\.label) == Self.defaultLabels)
        #expect(rows.first?.value == "1 of 8")
        #expect(!hosted.tree("topic-page").contains { $0.identifier == Self.visualOrderID }, "only the list")
        #expect(Self.perform("Move Down", on: try hosted.element("\(Self.listID).score")))
        _ = try await nativeHostedSettle(hosted.host) {
            hosted.storage.string(forKey: Self.orderKey)?.hasPrefix("percentage,score,") == true
        }
        #expect(hosted.storage.string(forKey: Self.orderKey)?.hasPrefix("percentage,score,") == true)
        let tree = hosted.tree("topic-page")
        #expect(macAccessibilityFindings(tree).isEmpty, "\(macAccessibilityFindings(tree))")
    }

    /// A deep link to the page while the switch is off reads one static note naming the
    /// switch, not an empty list.
    @Test func rightHandPageWhileOffReadsTheNote() async throws {
        let id = "\(Self.listID).off"
        let hosted = try await Self.host(enabled: false, topic: .songRowOrder, until: id)
        defer { hosted.close() }
        let nodes = hosted.tree("topic-off")
        let note = try #require(nodes.first { $0.identifier == id })
        #expect(note.isElement && note.role == "AXStaticText", "\(note)")
        #expect(note.spokenName.contains("Enable Independent Song Row Visual Order"))
        #expect(!nodes.contains { $0.identifier.hasPrefix(Self.listID + ".") && $0.identifier != id })
    }
}
#endif
