#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Quick Links instrument icons (#303, tests backfilled by #460)
//
// #303 drew the Quick Links chooser's instrument artwork at its 144 pt intrinsic size,
// so on Profile the Lead/Bass rows grew far taller than their neighbours and the icon
// covered the row title. `QuickLinkLabel` now pre-sizes the artwork beside the SF
// Symbols. These hosted tests pin that from an assistive technology's side on the
// `apple-ci` macOS host: each instrument row is one button named by its instrument (the
// artwork is not a separate stop and never reads as a file name), keeps the same height
// and title column as the symbol rows, and its title wraps rather than clips in a narrow
// column. Real Dynamic Type, the iPhone sheet and the iPad/Duo menu are on device:
// `QuickLinksIconAccessibilityJourneyTests`.

/// Profile's Quick Links shape: symbol rows around two instrument rows and a nested row.
private let iconSections: [QuickLinkSection] = [
    QuickLinkSection(id: "global", title: "Global Statistics", icon: .system("chart.bar.fill")),
    QuickLinkSection(id: "instrument:Solo_Guitar", title: "Lead", icon: .instrument(.lead)),
    QuickLinkSection(
        id: "rank-history:Solo_Guitar", title: "Rank History", icon: .system("chart.line.uptrend.xyaxis"),
        depth: 1, spokenTitle: "Lead Rank History"
    ),
    QuickLinkSection(id: "instrument:Solo_Bass", title: "Bass", icon: .instrument(.bass)),
    QuickLinkSection(id: "instrument:Solo_PeripheralDrums", title: "Pro Drums", icon: .instrument(.proDrums)),
    QuickLinkSection(id: "bands", title: "Bands", icon: .system("person.3.fill")),
]

private let iconSectionIDs = iconSections.map(\.id)
private let instrumentIDs = ["instrument:Solo_Guitar", "instrument:Solo_Bass", "instrument:Solo_PeripheralDrums"]

/// Host the iPhone accessory sheet (`PageToolInlineMenuSheet`) listing ``iconSections``.
///
/// - Returns: The hosting view and its window, once every row is exposed.
@MainActor
private func hostIconSheet() async throws -> (NSView, NSWindow) {
    let controller = QuickLinksController()
    controller.sections = iconSections
    let menu = PageToolInlineMenu(title: controller.title, choices: QuickLinksMenu(controller: controller).choices())
    let size = CGSize(width: 402, height: 700)
    let host = nativeHostedView(
        PageToolInlineMenuSheet(menu: menu, registry: PageToolsRegistry()).preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    try await nativeHostedSettle(host) {
        iconSectionIDs.allSatisfy { nativeHostedAccessibilityFrame("fst.quick-links.item.\($0)", in: host) != nil }
    }
    return (host, window)
}

// MARK: - Names and roles

/// Each instrument row is one button named by its instrument. The artwork inside it is
/// not a separate VoiceOver stop and never reads as an asset or file name.
@MainActor
@Test func quickLinksInstrumentRowsReadAsOneNamedButton() async throws {
    let (host, window) = try await hostIconSheet()
    defer { window.orderOut(nil) }
    let tree = macAccessibilityTree(host)
    let rows = tree.filter { $0.identifier.hasPrefix("fst.quick-links.item.") && $0.isElement }
    #expect(rows.map(\.identifier) == iconSectionIDs.map { "fst.quick-links.item.\($0)" }, "\(tree)")
    #expect(rows.map(\.spokenName) == iconSections.map(\.accessibilityTitle), "\(rows)")
    #expect(rows.allSatisfy { $0.role == "AXButton" }, "\(rows)")
    let images = tree.filter { $0.role == "AXImage" && $0.isElement }
    #expect(images.isEmpty, "Row icons exposed as separate elements: \(images)")
    let assetNames = Instrument.allCases.flatMap {
        [InstrumentIcon.assetName(for: $0, keyboard: false), InstrumentIcon.assetName(for: $0, keyboard: true)]
    }
    let leaked = tree.filter { node in assetNames.contains { node.spokenName.localizedCaseInsensitiveContains($0) } }
    #expect(leaked.isEmpty, "Artwork name spoken: \(leaked)")
}

// MARK: - Size

/// Instrument rows are as tall as the symbol rows around them: the 144 pt artwork (#303)
/// made them several times taller, with the icon over the title. Every row meets the
/// macOS minimum target height (HIG Accessibility: 20×20 pt minimum on macOS).
@MainActor
@Test func quickLinksInstrumentRowsMatchSymbolRowHeight() async throws {
    let (host, window) = try await hostIconSheet()
    defer { window.orderOut(nil) }
    var frames: [String: CGRect] = [:]
    for id in iconSectionIDs {
        frames[id] = try #require(nativeHostedAccessibilityFrame("fst.quick-links.item.\(id)", in: host))
    }
    let symbolHeight = try #require(frames["global"]).height
    #expect(symbolHeight >= 20, "\(frames)")
    for id in instrumentIDs {
        let height = try #require(frames[id]).height
        #expect(abs(height - symbolHeight) <= 1, "\(id) \(height) pt vs symbol row \(symbolHeight) pt")
    }
}

/// The label lays the icon out in the symbols' column: an instrument label is no taller
/// than a symbol label, and its title starts where a symbol row's title starts, so the
/// icon can neither overlap nor push the title.
@MainActor
@Test(arguments: [DynamicTypeSize.large, .accessibility5])
func quickLinksInstrumentLabelKeepsTheSymbolColumn(_ size: DynamicTypeSize) {
    func fitted(_ section: QuickLinkSection) -> CGSize {
        NSHostingController(
            rootView: QuickLinkLabel(section: section, presentation: .list)
                .environment(\.dynamicTypeSize, size)
                .preferredColorScheme(.dark)
        ).sizeThatFits(in: CGSize(width: 10_000, height: 10_000))
    }
    let symbol = fitted(QuickLinkSection(id: "s", title: "Lead", icon: .system("chart.bar.fill")))
    let instrument = fitted(QuickLinkSection(id: "i", title: "Lead", icon: .instrument(.lead)))
    #expect(instrument.height <= symbol.height + 1, "instrument \(instrument), symbol \(symbol)")
    #expect(abs(instrument.width - symbol.width) <= 4, "instrument \(instrument), symbol \(symbol)")
}

// MARK: - Text scaling

/// An instrument row's title wraps rather than clipping when the column is narrower
/// than one line (macOS has no Dynamic Type, so a narrow column stands in for the
/// iPhone sheet at AX5, as `quickLinksNestedRowLabelWrapsInsteadOfClipping` does).
@MainActor
@Test func quickLinksInstrumentRowTitleWrapsInsteadOfClipping() {
    let section = QuickLinkSection(
        id: "instrument:Solo_PeripheralCymbals", title: "Pro Cymbals Expert Plus", icon: .instrument(.proCymbals)
    )
    let host = NSHostingController(
        rootView: QuickLinkLabel(section: section, presentation: .list).preferredColorScheme(.dark)
    )
    let oneLine = host.sizeThatFits(in: CGSize(width: 10_000, height: 10_000))
    let width = oneLine.width * 0.6
    let narrow = host.sizeThatFits(in: CGSize(width: width, height: 10_000))
    #expect(narrow.width <= width + 0.5)
    #expect(narrow.height > oneLine.height * 1.5, "one line \(oneLine), narrow \(narrow)")
}
#endif
