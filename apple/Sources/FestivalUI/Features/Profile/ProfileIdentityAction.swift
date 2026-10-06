import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Action

/// The one identity action a player page offers for the account it shows.
///
/// Placement (`.agents/design/apple/nav-accessories.md`): its own header button on
/// iPhone, iPad and Mac; the iPhone Duo rail item otherwise. Paused states (unverified
/// or changed publication) offer no action and stay as footnotes in the page header.
enum ProfileIdentityAction: Hashable {
    /// No profile selected: select this one.
    case select
    /// Another profile is selected: switch to this one (confirmed by the page).
    case switchTo
    /// This is the selected profile: deselect it (confirmed by the page).
    case deselect

    /// Short title for the header button.
    var shortTitle: String {
        switch self {
        case .select: "Select"
        case .switchTo: "Switch"
        case .deselect: "Deselect"
        }
    }

    /// Full title, used for the toolbar item and VoiceOver.
    var title: String {
        switch self {
        case .select: "Select Profile"
        case .switchTo: "Switch To This Profile"
        case .deselect: "Deselect Profile"
        }
    }

    /// Toolbar symbol (the toolbar needs a `Label` so vertical bars can show it).
    var systemImage: String {
        switch self {
        case .select: "person.crop.circle.badge.plus"
        case .switchTo: "arrow.left.arrow.right"
        case .deselect: "person.crop.circle.badge.xmark"
        }
    }

    /// Existing journey-test identifiers, kept from the former in-header buttons.
    var accessibilityIdentifier: String {
        self == .deselect ? "fst.player.deselect" : "fst.player.select"
    }

    /// Identifier of the iPhone Duo rail item (`VerticalBarActionItem`).
    var railAccessibilityIdentifier: String { accessibilityIdentifier + ".rail" }

    /// Select and Switch are the page's primary action; Deselect is secondary.
    var isProminent: Bool { self != .deselect }

    /// Deselect is drawn red, like the web's danger button.
    var isDestructive: Bool { self == .deselect }
}

// MARK: - Header button

/// The player page's Select / Switch / Deselect as its own header button (operator,
/// 2026-09-28). The iPhone Duo rail uses `VerticalBarActionItem` instead.
struct ProfileIdentityToolbarItem: ToolbarContent {
    let action: ProfileIdentityAction
    /// False while the page's read has not proven the action yet (or selection is
    /// paused): the button keeps its place, disabled, so the toolbar never re-lays out.
    var isEnabled = true
    let perform: (ProfileIdentityAction) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .festivalPageAction) {
            button
        }
    }

    /// A short text button: prominent accent blue for Select/Switch, prominent red for
    /// Deselect (web `btnDanger`, `Colors.statusRed`, white text; operator batch 6.18).
    @ViewBuilder private var button: some View {
        let base = Button {
            perform(action)
        } label: {
            Text(action.shortTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(isEnabled ? Color.white : FestivalText.disabled)
        }
        .accessibilityLabel(action.title)
        // A distinct identifier while disabled, so journeys waiting for the action
        // never tap the placeholder.
        .accessibilityIdentifier(isEnabled ? action.accessibilityIdentifier : action.accessibilityIdentifier + ".pending")
        .disabled(!isEnabled)
        base.buttonStyle(.borderedProminent)
            .tint(action.isDestructive ? BrandTokens.statusRed : AccentText.prominentFill)
    }
}
