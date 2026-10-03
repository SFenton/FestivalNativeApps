import Testing
@testable import FestivalUI

// MARK: - Search tab transitions (issue #92)

/// Pins the Search tab's transient behaviour: it opens over the current section and
/// leaving it returns there with the stack intact (HIG Search fields: "returns to the
/// previous tab on exit").
@Suite("Root tab transitions")
struct RootTabTransitionTests {
    @Test("Choosing Search opens it over the current section")
    func searchOpens() {
        #expect(RootTabTransition.choose(.search, selected: .songs, searchActive: false) == .openSearch)
    }

    @Test("Re-choosing Search while it shows does nothing")
    func searchReselected() {
        #expect(RootTabTransition.choose(.search, selected: .songs, searchActive: true) == RootTabTransition.none)
    }

    @Test("Choosing the previous tab closes Search and keeps that tab's stack")
    func previousTabCloses() {
        #expect(RootTabTransition.choose(.section(.songs), selected: .songs, searchActive: true) == .closeSearch)
    }

    @Test("Choosing another tab from Search selects it")
    func otherTabSelects() {
        #expect(RootTabTransition.choose(.section(.settings), selected: .songs, searchActive: true) == .select(.settings))
    }

    @Test("Outside Search, tabs keep their usual semantics")
    func normalTabs() {
        #expect(RootTabTransition.choose(.section(.songs), selected: .songs, searchActive: false) == .select(.songs))
        #expect(RootTabTransition.choose(.section(.settings), selected: .songs, searchActive: false) == .select(.settings))
    }

    @Test("Dismissing the field leaves Search only while it shows")
    func dismiss() {
        #expect(RootTabTransition.dismissSearch(searchActive: true) == .closeSearch)
        #expect(RootTabTransition.dismissSearch(searchActive: false) == RootTabTransition.none)
    }

    @Test("A result opens on the previous tab")
    func resultPushes() {
        #expect(RootTabTransition.openResult(.statistics) == .push(.statistics))
    }
}
