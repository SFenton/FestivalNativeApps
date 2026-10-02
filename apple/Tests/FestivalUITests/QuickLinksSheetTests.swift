import Testing
import FestivalCore
@testable import FestivalUI

// MARK: - Quick Links sheet (issue #42)

/// The tab-bar accessory opens Quick Links as a sheet: it opens only when the page offers
/// sections, and choosing a row closes it and jumps.
@MainActor
struct QuickLinksSheetTests {
    private let sections = [
        QuickLinkSection(id: "a", title: "Alpha"),
        QuickLinkSection(id: "b", title: "Beta"),
    ]

    @Test func opensOnlyWithSectionsToOffer() {
        let controller = QuickLinksController()
        controller.presentSheet()
        #expect(!controller.sheetPresented, "No sections: nothing to jump to")
        controller.configure(title: "Quick Links", explicit: [sections[0]])
        controller.presentSheet()
        #expect(!controller.sheetPresented, "One section hides Quick Links")
        controller.configure(title: "Quick Links", explicit: sections)
        controller.presentSheet()
        #expect(controller.sheetPresented)
    }

    @Test func choosingARowClosesAndJumps() {
        let controller = QuickLinksController()
        controller.configure(title: "Quick Links", explicit: sections)
        controller.presentSheet()
        let serial = controller.jumpSerial
        controller.choose("b")
        #expect(!controller.sheetPresented)
        #expect(controller.jumpTarget == "b")
        #expect(controller.jumpSerial == serial + 1)
        #expect(controller.activeID == "b")
    }

    @Test func choosingAnUnknownRowOnlyCloses() {
        let controller = QuickLinksController()
        controller.configure(title: "Quick Links", explicit: sections)
        controller.presentSheet()
        let serial = controller.jumpSerial
        controller.choose("gone")
        #expect(!controller.sheetPresented)
        #expect(controller.jumpSerial == serial)
    }
}
