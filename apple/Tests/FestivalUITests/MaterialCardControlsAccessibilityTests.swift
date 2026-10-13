#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Material card controls accessibility (issue #291, backfilled by #454)

// #291 moved every content card and every custom floating control off per-card Liquid
// Glass onto the shared material card (`festivalCard` / `festivalCardCapsule`,
// `FestivalCardModifier`, pattern `surface-materials`). `RowCardSurfaceTests` pins the
// card's opaque fallbacks and a row card's tree; these hosted checks (macOS host,
// `apple-ci`) pin what the moved *controls* expose to VoiceOver and Voice Control on
// iPhone, iPad, iPhone Duo and Mac, which share this SwiftUI: the Full Rankings /
// Song Leaderboard pager (`RankingsPagerView`), the Band Rankings floating pager
// (`RankingsGlassPager`) and its band-size pill (`RankingsSwitcherPillLabel`), and the
// purple call to action (`PurpleActionLabel`) inside and outside a section card.
// Each control keeps its spoken name, button role, edge-disabled state, adjustable
// page value, reading order and a 44 pt target, and AXPress / AXIncrement still act,
// on the material card and on its opaque Reduce Transparency / Increase Contrast card
// alike. macOS keeps the font size; the iPhone XCUITest
// `MaterialCardAccessibilityJourneyTests` proves the same controls at AX5 on device.

// MARK: - Fixture

/// Transparency and contrast settings the card draws differently for.
enum MaterialControlsMode: String, CaseIterable, CustomTestStringConvertible {
    /// The shipping material card.
    case material
    /// System Reduce Transparency: the opaque card.
    case systemReduceTransparency
    /// The app's Reduce Transparency setting: the opaque card.
    case lessTransparency
    /// The app's Increase Contrast setting: the opaque card.
    case moreContrast

    var testDescription: String { rawValue }
}

/// Records what the hosted controls asked for.
@MainActor
final class MaterialControlsLog {
    /// Pages the text pager moved to.
    var textPager: [Int] = []
    /// Pages the floating pager moved to.
    var floatingPager: [Int] = []
    /// Presses of the purple buttons, by identifier suffix.
    var actions: [String] = []
}

/// Every control #291 moved onto the material card, stacked on a phone-width page as on
/// the boards: a section card ending with its in-card purple action, a purple action
/// below separate cards, the text pager on page 1 of 3, and the floating bar's pager on
/// page 2 of 3 beside its band-size pill.
private struct MaterialControlsProbe: View {
    let log: MaterialControlsLog

    var body: some View {
        VStack(spacing: 12) {
            FestivalGlassSection("Lead") {
                Text("Fixture Player 1")
                    .foregroundStyle(FestivalText.primary)
                    .accessibilityIdentifier("fst.test-material.row")
            } action: {
                Button { log.actions.append("in-card") } label: {
                    PurpleActionLabel(title: "View Full Leaderboard")
                }
                .festivalRowButtonStyle()
                .accessibilityLabel(PurpleActionName.spoken("View Full Leaderboard", card: "Lead"))
                .accessibilityIdentifier("fst.test-material.in-card")
            }
            Button { log.actions.append("view-all") } label: {
                PurpleActionLabel(title: "View All")
            }
            .festivalRowButtonStyle()
            .accessibilityLabel(PurpleActionName.spoken("View All", card: "Rivals"))
            .accessibilityIdentifier("fst.test-material.view-all")
            RankingsPagerView(page: 1, totalPages: 3, idPrefix: "fst.test-pager") { log.textPager.append($0) }
            HStack(spacing: 8) {
                RankingsGlassPager(
                    state: RankingsPagerState(page: 2, totalPages: 3), idPrefix: "fst.test-floating"
                ) { log.floatingPager.append($0) }
                Menu {
                    Button("Duos") {}
                    Button("Trios") {}
                } label: {
                    RankingsSwitcherPillLabel(title: "Duos", showsTitle: true) {
                        Image(systemName: "person.3.fill").font(.title3)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("fst.test-material.band-type-menu")
                .accessibilityLabel("Band size")
                .accessibilityValue("Duos")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
    }
}

/// One expected control: its identifier, spoken name, value and whether it acts.
private struct ExpectedControl: CustomStringConvertible {
    let id: String
    let label: String
    var value: String = ""
    var enabled = true
    /// A button (AXButton); false for the adjustable page badge and the pop-up menu.
    var isButton = true

    var description: String { "\(label) #\(id)" }
}

/// The controls in visual (and reading) order.
private let expectedControls: [ExpectedControl] = [
    ExpectedControl(id: "fst.test-material.in-card", label: "View Full Leaderboard, Lead"),
    ExpectedControl(id: "fst.test-material.view-all", label: "View All, Rivals"),
    ExpectedControl(id: "fst.test-pager.page-first", label: "First page", enabled: false),
    ExpectedControl(id: "fst.test-pager.page-previous", label: "Previous page", enabled: false),
    ExpectedControl(id: "fst.test-pager.page-info", label: "Page", value: "1 of 3", isButton: false),
    ExpectedControl(id: "fst.test-pager.page-next", label: "Next page"),
    ExpectedControl(id: "fst.test-pager.page-last", label: "Last page"),
    ExpectedControl(id: "fst.test-floating.page-first", label: "First Page"),
    ExpectedControl(id: "fst.test-floating.page-previous", label: "Previous Page"),
    ExpectedControl(id: "fst.test-floating.page-info", label: "Page", value: "2 of 3", isButton: false),
    ExpectedControl(id: "fst.test-floating.page-next", label: "Next Page"),
    ExpectedControl(id: "fst.test-floating.page-last", label: "Last Page"),
    ExpectedControl(
        id: "fst.test-material.band-type-menu", label: "Band size", value: "Duos", isButton: false
    ),
]

/// A phone-width page tall enough for every control.
private let probeSize = CGSize(width: 402, height: 560)

/// One hosted probe in a window.
@MainActor
private struct HostedMaterialControls {
    let host: NSHostingView<NativeHostedRoot<AnyView>>
    let window: NSWindow
    let log: MaterialControlsLog
    let storage: UserDefaults
    let suiteName: String

    /// Host the probe under one transparency or contrast setting.
    ///
    /// - Parameter mode: The setting under test.
    /// - Returns: The hosted probe; call ``close()`` when done.
    static func host(_ mode: MaterialControlsMode) throws -> HostedMaterialControls {
        let suiteName = "fst.tests.material-controls.\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(mode == .lessTransparency, forKey: "fst.accessibility.lessTransparency")
        storage.set(mode == .moreContrast, forKey: "fst.accessibility.moreContrast")
        let log = MaterialControlsLog()
        let host = nativeHostedView(
            AnyView(
                MaterialControlsProbe(log: log)
                    .environment(\._accessibilityReduceTransparency, mode == .systemReduceTransparency)
                    .defaultAppStorage(storage)
                    .preferredColorScheme(.dark)
            ),
            // The material branch must draw for real; Reduce Transparency is pinned above.
            size: probeSize, forceGlassFallback: false
        )
        let window = nativeHostedWindow(host, size: probeSize)
        return HostedMaterialControls(host: host, window: window, log: log, storage: storage, suiteName: suiteName)
    }

    func close() {
        window.orderOut(nil)
        storage.removePersistentDomain(forName: suiteName)
    }

    /// The tree in VoiceOver's navigation order, after one layout pass.
    func tree() -> [MacAXNode] {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        return macAccessibilityTree(host, navigationOrder: true)
    }

    /// The realized element with `identifier`.
    func element(_ identifier: String) -> NSObject? {
        host.layoutSubtreeIfNeeded()
        return nativeHostedAccessibilityElement(identifier, in: host)
    }

    /// The frame of the element with `identifier`, in the host's top-left points.
    func frame(_ identifier: String) -> CGRect? {
        nativeHostedAccessibilityFrame(identifier, in: host)
    }
}

/// The name a control announces: its label, or for a menu (whose label macOS reports as
/// the title) its title.
private func announcedName(_ node: MacAXNode) -> String {
    node.label.isEmpty ? node.title : node.label
}

/// The value a control announces. An adjustable element on macOS (role AXUnknown)
/// reports its `accessibilityValue` as the value description, which VoiceOver reads.
///
/// - Parameters:
///   - node: The control's node.
///   - hosted: The hosted probe, to read the element's value description.
/// - Returns: The announced value, empty when none.
@MainActor
private func announcedValue(_ node: MacAXNode, in hosted: HostedMaterialControls) -> String {
    guard node.value.isEmpty, let element = hosted.element(node.identifier),
          element.responds(to: NSSelectorFromString("accessibilityValueDescription"))
    else { return node.value }
    return element.value(forKey: "accessibilityValueDescription") as? String ?? ""
}

/// A comparable line per expected control: role, name, value and state.
///
/// - Parameter hosted: The hosted probe.
/// - Returns: One line per control in ``expectedControls`` order.
@MainActor
private func controlSignature(_ hosted: HostedMaterialControls) -> [String] {
    let nodes = hosted.tree()
    return expectedControls.map { control in
        guard let node = nodes.first(where: { $0.identifier == control.id }) else { return "missing \(control.id)" }
        return "\(node.role) '\(announcedName(node))' = '\(announcedValue(node, in: hosted))'"
            + " enabled \(node.isEnabled) #\(node.identifier)"
    }
}

// MARK: - Tests

/// Accessibility of the controls #291 moved onto the material card.
///
/// HIG Accessibility: iOS/iPadOS default control size "44×44pt"; "Label elements
/// correctly for Voice Control and VoiceOver". HIG Materials: "Use standard materials
/// within the content layer"; Reduce Transparency and Increase Contrast change only the
/// look, never what assistive technologies read or reach.
@MainActor
@Suite(.serialized)
struct MaterialCardControlsAccessibilityTests {
    /// HIG Accessibility: iOS/iPadOS default control size.
    static let minimumTarget: CGFloat = 44

    @Test("Each control on the material card is named, has its role, state and value, and reads in visual order",
          arguments: MaterialControlsMode.allCases)
    func controlsAreNamedInOrder(mode: MaterialControlsMode) throws {
        let hosted = try HostedMaterialControls.host(mode)
        defer { hosted.close() }
        let nodes = hosted.tree()
        macAccessibilityDump(nodes, name: "material-controls-\(mode.rawValue)")
        let tree = nodes.map(\.description).joined(separator: "\n")

        for control in expectedControls {
            let node = try #require(nodes.first { $0.identifier == control.id }, "\(control) in tree:\n\(tree)")
            #expect(node.isElement, "\(control) is an accessibility element")
            #expect(announcedName(node) == control.label,
                    "\(control) is named '\(control.label)', not '\(announcedName(node))'")
            let value = announcedValue(node, in: hosted)
            #expect(value == control.value, "\(control) value '\(value)'")
            #expect(node.isEnabled == control.enabled, "\(control) enabled \(node.isEnabled)")
            if control.isButton {
                #expect(node.role == NSAccessibility.Role.button.rawValue, "\(control) is a button, not \(node.role)")
            }
        }
        #expect(nodes.first { $0.identifier == "fst.test-material.band-type-menu" }.map {
            [NSAccessibility.Role.popUpButton.rawValue, NSAccessibility.Role.menuButton.rawValue].contains($0.role)
        } == true, "the band-size pill is a menu control")
        // One menu element for the whole pill: macOS used to expose the icon and the title
        // as two 28 × 14 pt "Band size" menu buttons (#454).
        let bandSize = nodes.filter { $0.isElement && announcedName($0) == "Band size" }
        #expect(bandSize.count == 1, "one band-size control, not \(bandSize)")
        #expect(macAccessibilityFindings(nodes) == [], "unnamed controls or images:\n\(tree)")

        // The row reads before its card's action, and every control in visual order.
        let wanted = ["fst.test-material.row"] + expectedControls.map(\.id)
        let order = nodes.map(\.identifier).filter { wanted.contains($0) }
        #expect(order == wanted, "reading order:\n\(tree)")
        // The card and its rim add no element of their own: nothing unnamed and
        // identifier-less between the controls (the rim is accessibility-hidden).
        // The hosting view itself (depth 0) is the window's group, not a card element.
        let decorative = nodes.filter {
            $0.depth > 0 && $0.isElement && $0.spokenName.isEmpty && $0.identifier.isEmpty
        }
        #expect(decorative.isEmpty, "decorative elements: \(decorative)")
    }

    @Test("Every control on the material card keeps at least a 44 × 44 pt target",
          arguments: MaterialControlsMode.allCases)
    func controlsKeepTheirTargets(mode: MaterialControlsMode) throws {
        let hosted = try HostedMaterialControls.host(mode)
        defer { hosted.close() }
        for control in expectedControls {
            let frame = try #require(hosted.frame(control.id), "\(control) has a frame")
            #expect(frame.width >= Self.minimumTarget - 0.5 && frame.height >= Self.minimumTarget - 0.5,
                    "\(control) target \(frame)")
            #expect(probeSize.width >= frame.maxX && frame.minX >= 0, "\(control) on the page: \(frame)")
        }
    }

    @Test("The opaque Reduce Transparency and Increase Contrast cards expose the same controls as the material card",
          arguments: MaterialControlsMode.allCases.filter { $0 != .material })
    func opaqueCardKeepsTheTree(mode: MaterialControlsMode) throws {
        let material = try HostedMaterialControls.host(.material)
        defer { material.close() }
        let opaque = try HostedMaterialControls.host(mode)
        defer { opaque.close() }
        #expect(controlSignature(opaque) == controlSignature(material))
        // Same place and size; the opaque card's centred stroke may add half a point.
        for control in expectedControls {
            let a = try #require(material.frame(control.id), "\(control) material frame")
            let b = try #require(opaque.frame(control.id), "\(control) opaque frame")
            let drift = [a.minX - b.minX, a.minY - b.minY, a.width - b.width, a.height - b.height].map(abs).max() ?? 0
            #expect(drift <= 1.5, "\(control) moved: \(a) → \(b)")
        }
        let count = { (hosted: HostedMaterialControls) in hosted.tree().filter(\.isElement).count }
        #expect(count(opaque) == count(material), "element count")
    }

    @Test("Pressing and adjusting the controls on the material card still acts",
          arguments: [MaterialControlsMode.material, .lessTransparency])
    func controlsStillAct(mode: MaterialControlsMode) throws {
        let hosted = try HostedMaterialControls.host(mode)
        defer { hosted.close() }
        let press = NSSelectorFromString("accessibilityPerformPress")
        let increment = NSSelectorFromString("accessibilityPerformIncrement")
        let decrement = NSSelectorFromString("accessibilityPerformDecrement")
        func act(_ id: String, _ selector: Selector) throws {
            let element = try #require(hosted.element(id), "\(id) in tree")
            #expect(element.responds(to: selector), "\(id) supports \(selector)")
            _ = element.perform(selector)
        }

        try act("fst.test-material.in-card", press)
        try act("fst.test-material.view-all", press)
        try act("fst.test-pager.page-next", press)
        try act("fst.test-pager.page-last", press)
        try act("fst.test-pager.page-info", increment)
        try act("fst.test-floating.page-first", press)
        try act("fst.test-floating.page-info", decrement)
        try act("fst.test-floating.page-info", increment)
        hosted.host.layoutSubtreeIfNeeded()

        #expect(hosted.log.actions == ["in-card", "view-all"])
        #expect(hosted.log.textPager == [2, 3, 2])
        #expect(hosted.log.floatingPager == [1, 1, 3])
    }
}
#endif
