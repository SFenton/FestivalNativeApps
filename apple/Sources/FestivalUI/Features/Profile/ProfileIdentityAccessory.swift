import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Action

/// The one identity action a player page offers for the account it shows.
///
/// Placement (`.agents/design/apple/nav-accessories.md`): the tab-bar bottom accessory
/// on iOS 26.1+ iPhone, otherwise a labelled toolbar item (so the iPhone Duo puts it
/// in its vertical bar). Paused states (unverified or changed publication) offer no
/// action and stay as footnotes in the page header.
enum ProfileIdentityAction: Hashable {
    /// No profile selected: select this one.
    case select
    /// Another profile is selected: switch to this one (confirmed by the page).
    case switchTo
    /// This is the selected profile: deselect it (confirmed by the page).
    case deselect

    /// Short title for the accessory's button.
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
}

// MARK: - Accessory

/// Mini-player-style bar: avatar, name and relationship, and the action button.
struct ProfileIdentityAccessory: View {
    let name: String
    let action: ProfileIdentityAction
    let perform: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProfileAvatar(name: name, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandTokens.textPrimary)
                    .lineLimit(1)
                Text(action == .deselect ? "Selected Profile" : "Public Profile")
                    .font(.caption)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            button
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
    }

    /// Flat (non-glass) button inside the system's glass accessory: no glass on glass.
    @ViewBuilder private var button: some View {
        let base = Button(action: perform) {
            Text(action.shortTitle)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 4)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .accessibilityLabel(action.title)
        .accessibilityIdentifier(action.accessibilityIdentifier)
        if action.isProminent {
            base.buttonStyle(.borderedProminent).tint(BrandTokens.accentBlue)
        } else {
            base.buttonStyle(.bordered).tint(BrandTokens.textPrimary)
        }
    }
}

// MARK: - Toolbar fallback

/// The same action as a labelled toolbar item where neither the tab accessory nor the
/// Duo rail (`VerticalBarActionItem`) applies: iOS 17–26.0 and iPad.
struct ProfileIdentityToolbarItem: ToolbarContent {
    let action: ProfileIdentityAction
    /// True on a tab root, where page actions must precede the bell and avatar.
    let onTabRoot: Bool
    let perform: (ProfileIdentityAction) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) {
            Button {
                perform(action)
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
            .tint(action.isProminent ? BrandTokens.accentBlue : BrandTokens.textPrimary)
            .accessibilityIdentifier(action.accessibilityIdentifier)
        }
    }

    private var placement: ToolbarItemPlacement {
        #if os(iOS)
        onTabRoot ? .topBarTrailing : .primaryAction
        #else
        .primaryAction
        #endif
    }
}
