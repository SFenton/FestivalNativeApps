import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - SongsScreen re-render boundary (issue #325)

/// `SongsScreen` compares equal across a parent's re-creation that changes nothing, so a
/// tab-bar minimize mid-scroll skips its body instead of rebuilding the List.
@MainActor
@Suite("SongsScreen re-render boundary")
struct SongsScreenEquatableTests {
    /// A session that never reaches the network.
    private let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })

    /// Build a page with the given value inputs.
    ///
    /// - Parameters:
    ///   - session: The page's session (defaults to the shared one).
    ///   - visibleInstruments: Settings-visible charts.
    ///   - highContrast: Effective contrast override.
    ///   - isVisible: Whether the page is the front page.
    ///   - openShop: The Item Shop action, if any.
    /// - Returns: A Songs page.
    private func page(
        session: FestivalSession? = nil,
        visibleInstruments: Set<Instrument> = Set(Instrument.allCases),
        highContrast: Bool = false, isVisible: Bool = true,
        openShop: (() -> Void)? = {}
    ) -> SongsScreen {
        SongsScreen(
            session: session ?? self.session, visibleInstruments: visibleInstruments,
            highContrast: highContrast, isVisible: isVisible, openShop: openShop
        )
    }

    @Test("A re-created page with a new openShop closure is equal")
    func recreatedClosureIsEqual() {
        #expect(page(openShop: { _ = 1 }) == page(openShop: { _ = 2 }))
    }

    @Test("Visibility, charts, contrast and the shop action's presence still update the page")
    func valueInputsAreCompared() {
        #expect(page(isVisible: true) != page(isVisible: false))
        #expect(page(visibleInstruments: [.lead]) != page(visibleInstruments: [.lead, .bass]))
        #expect(page(highContrast: false) != page(highContrast: true))
        #expect(page(openShop: nil) != page(openShop: {}))
    }

    @Test("A different session is a different page")
    func sessionIdentityIsCompared() {
        let other = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
        #expect(page() != page(session: other))
    }
}
