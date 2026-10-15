import SwiftUI
import FestivalCore

// MARK: - Page tools in the menu bar

/// The focused page's menu-bar values (HIG Toolbars › macOS: "Every toolbar item must
/// also be a menu-bar command"; The menu bar › iPadOS), read by ``MacCommands`` and the
/// iPadOS ``FestivalCommands`` from `@FocusedValue` and handed to the shared page-tool
/// menu items, so both menu bars list, enable and invoke the same commands
/// (page-tools-and-nav-chrome R28).
struct PageToolMenuState {
    /// Sort, Filter, Find Rival and List/Grid of the front page.
    var page: MacPageCommands?
    /// The front rankings page's Rank By.
    var rankBy: MacRankByCommands?
    /// The front rankings page's instrument.
    var instrument: MacInstrumentCommands?
    /// The front band board's band size.
    var bandSize: MacBandSizeCommands?
    /// The front player or rival page's Profile-menu actions.
    var profile: MacProfilePageCommands?
    /// Settings › Experimental Ranks (View › Rank By lists Total Score alone while off).
    var experimentalRanks = ExperimentalRanks.defaultValue
    /// Whether a sheet covers the window, or no window is focused (commands that
    /// present must not stack another sheet).
    var blocked = false
}

/// View-menu page tools, in toolbar order: Sort…, Filter…, Rank By ▸, Instrument ▸,
/// Band Size ▸, then as List / as Grid. Unavailable items are disabled, never hidden
/// (HIG The menu bar: "Disable, don't hide, unavailable items"), and each submenu keeps
/// its items (HIG Menus: "Make sure a submenu remains available even when its items
/// are unavailable"). The choices carry a checkmark on the one in effect (HIG Menus:
/// "Consider a checkmark to show an attribute is in effect").
struct PageToolViewMenuItems: View {
    let state: PageToolMenuState

    var body: some View {
        Button("Sort…") { state.page?.sort?() }
            .disabled(state.page?.sort == nil || state.blocked)
        Button("Filter…") { state.page?.filter?() }
            .disabled(state.page?.filter == nil || state.blocked)
        Menu("Rank By") { PageToolChoiceItems.rankBy(state) }
        Menu("Instrument") { PageToolChoiceItems.instrument(state) }
        Menu("Band Size") { PageToolChoiceItems.bandSize(state) }
        Divider()
        PageToolLayoutItems(state: state)
    }
}

/// One View-menu submenu's choices as checkmarked toggles; every choice stays listed
/// but disabled while no page offers the submenu.
struct PageToolChoiceItems: View {
    /// One choice.
    struct Choice: Identifiable, Equatable {
        let id: String
        let label: String
    }

    let choices: [Choice]
    /// The choice in effect, if a page offers the submenu.
    let selected: String?
    /// Applies a choice, or nil while no page offers the submenu.
    let select: (@MainActor (String) -> Void)?

    var body: some View {
        ForEach(choices) { choice in
            Toggle(choice.label, isOn: Binding(
                get: { selected == choice.id },
                set: { isOn in if isOn { select?(choice.id) } }
            ))
            .disabled(select == nil)
        }
    }

    /// View › Rank By: the front rankings page's metrics, else the account metrics.
    ///
    /// - Parameter state: The focused page values.
    /// - Returns: The submenu's choices.
    static func rankBy(_ state: PageToolMenuState) -> Self {
        let rankBy = state.rankBy
        let options = rankBy?.options ?? MacRankByCommands.accountOptions(experimentalRanks: state.experimentalRanks)
        return Self(
            choices: options.map { Choice(id: $0.id, label: $0.label) },
            selected: rankBy?.selected, select: rankBy?.select
        )
    }

    /// View › Instrument: the front rankings page's charts (issue #294), else every chart.
    ///
    /// - Parameter state: The focused page values.
    /// - Returns: The submenu's choices.
    static func instrument(_ state: PageToolMenuState) -> Self {
        let instrument = state.instrument
        let options = instrument?.options ?? MacInstrumentCommands.allOptions
        return Self(
            choices: options.map { Choice(id: $0.id, label: $0.label) },
            selected: instrument?.selected, select: instrument?.select
        )
    }

    /// View › Band Size: every band size, checked on the front band board's (issue #633).
    ///
    /// - Parameter state: The focused page values.
    /// - Returns: The submenu's choices.
    static func bandSize(_ state: PageToolMenuState) -> Self {
        let bandSize = state.bandSize
        var select: (@MainActor (String) -> Void)?
        if let bandSize {
            select = { id in
                if let size = BandType(rawValue: id) { bandSize.select(size) }
            }
        }
        return Self(
            choices: BandType.allCases.map { Choice(id: $0.rawValue, label: $0.label) },
            selected: bandSize?.selected.rawValue, select: select
        )
    }
}

/// View › as List / as Grid: the front page's List/Grid toolbar toggle (Item Shop,
/// issue #633) as Finder-style checkmarked items; disabled where no page offers it.
struct PageToolLayoutItems: View {
    let state: PageToolMenuState

    var body: some View {
        let layout = state.page?.layout
        Toggle("as List", isOn: Binding(
            get: { layout?.isGrid == false },
            set: { isOn in if isOn { layout?.select(false) } }
        ))
        .disabled(layout == nil || state.blocked)
        Toggle("as Grid", isOn: Binding(
            get: { layout?.isGrid == true },
            set: { isOn in if isOn { layout?.select(true) } }
        ))
        .disabled(layout == nil || state.blocked)
    }
}

/// Profile-menu page tools: the player page's Select / Switch to This Profile, the
/// rival pages' View Rival's Profile (issue #633) and Rivals' Find Rival…, each
/// disabled where the front page does not offer it.
struct PageToolProfileMenuItems: View {
    let state: PageToolMenuState

    var body: some View {
        Button(MacProfilePageCommands.identityMenuTitle(for: state.profile?.identity)) {
            state.profile?.performIdentity?()
        }
        .disabled(state.profile?.performIdentity == nil || state.blocked)
        Button("View Rival's Profile") { state.profile?.viewRivalProfile?() }
            .disabled(state.profile?.viewRivalProfile == nil || state.blocked)
        Button("Find Rival…") { state.page?.findRival?() }
            .disabled(state.page?.findRival == nil || state.blocked)
    }
}

// MARK: - Menu-bar mirror (tests)

/// The menu bars' page-tool items over the focused page's values, laid out as ordinary
/// controls with the band sizes listed inline. Neither menu bar can be driven by tests:
/// a macOS menu bar is not hostable, and the iPadOS 26 menu bar is not in the XCUITest
/// tree (no gesture, pointer hover or key hold exposes it, issue #633). So the hosted
/// macOS tests (`PageToolMenuBarAccessibilityTests`) and the iPad journey
/// (`IPadMenuBarJourneyTests`, Debug `FST_DEBUG_MENU_BAR=1`) drive this mirror, which
/// reads the same `@FocusedValue` keys as ``MacCommands`` and ``FestivalCommands`` and
/// lays out the same shared items they do.
struct PageToolMenuBarMirror: View {
    /// The mirror's accessibility identifier.
    nonisolated static let identifier = "fst.menu-bar-mirror"

    @FocusedValue(\.macPageCommands) private var page
    @FocusedValue(\.macRankBy) private var rankBy
    @FocusedValue(\.macInstrument) private var instrument
    @FocusedValue(\.macBandSize) private var bandSize
    @FocusedValue(\.macProfilePageCommands) private var profile
    /// Whether a sheet covers the window, or no window is focused.
    var blocked: Bool
    /// Settings › Experimental Ranks.
    var experimentalRanks = ExperimentalRanks.defaultValue

    var body: some View {
        let state = PageToolMenuState(
            page: page, rankBy: rankBy, instrument: instrument, bandSize: bandSize,
            profile: profile, experimentalRanks: experimentalRanks, blocked: blocked
        )
        VStack(alignment: .leading, spacing: 4) {
            PageToolViewMenuItems(state: state)
            Divider()
            PageToolChoiceItems.bandSize(state)
            Divider()
            PageToolProfileMenuItems(state: state)
        }
        .padding(8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.identifier)
    }
}
