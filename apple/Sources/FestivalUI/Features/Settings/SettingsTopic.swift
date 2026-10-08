import Foundation
import FestivalCore

// MARK: - Settings topics

/// A Settings group with more than one option, a reorder list or its own page, which the
/// list/detail Settings (iPad, unfolded iPhone Duo in landscape; issue #371, owner-approved
/// `split-panes` variant) shows as a chevron row opening on the right
/// (`AppRoute.settingsTopic`). Plain toggles stay in the list and act in place.
///
/// iPhone, portrait and folded layouts keep the single long page, and the Mac keeps its
/// Settings window panes (``SettingsPane``); none of them use these routes. Licenses keeps
/// its own `AppRoute.licenses` page.
enum SettingsTopic: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Song Row Visual Order (drag to reorder); listed while Independent Visual Order is on.
    case songRowOrder
    /// CHOpt Path Default View and the draggable text-path column order.
    case paths
    /// The app's accessibility overrides.
    case accessibility
    /// Hide Item Shop and Highlight Shop Items.
    case itemShop
    /// Which instruments show throughout the app.
    case instruments
    /// Which score fields song rows show.
    case metadata
    /// App, build and service versions, and What's New.
    case version
    /// Live service status and the last publication.
    case serviceInfo
    /// First-run guide replays.
    case firstRun
    /// The privacy policy, inline in the pane (a sheet everywhere else).
    case privacyPolicy

    var id: Self { self }

    /// The chevron row's title: the section title of the single long page.
    var rowTitle: String {
        switch self {
        case .songRowOrder: "Song Row Visual Order"
        case .paths: "CHOpt Paths"
        case .accessibility: "Accessibility"
        case .itemShop: "Item Shop"
        case .instruments: "Show Instruments"
        case .metadata: "Show Instrument Metadata"
        case .version: "Festival Score Tracker Version"
        case .serviceInfo: ServiceInfoText.title
        case .firstRun: "First Run Guides"
        case .privacyPolicy: "Privacy Policy"
        }
    }

    /// The open page's navigation title: the row title, shortened where a half pane's
    /// large title would truncate.
    var pageTitle: String {
        switch self {
        case .version: "Version"
        case .metadata: "Instrument Metadata"
        default: rowTitle
        }
    }

    /// The chevron row's description. The open page shows its section's own description
    /// above the card.
    var subtitle: String {
        switch self {
        case .songRowOrder:
            "When filtering to a single instrument in the song list, extra metadata is "
                + "displayed. Choose the order it appears in on the bottom row."
        case .paths: "How optimal Overdrive paths open on a song's Paths page."
        case .accessibility: "App overrides for motion, artwork, contrast and transparency."
        case .itemShop: "Control how Item Shop availability is displayed."
        case .instruments: "Choose which instruments to display throughout the app."
        case .metadata: "Choose which score fields appear on song rows."
        case .version: "Festival Score Tracker information to help with debugging."
        case .serviceInfo: ServiceInfoText.hint
        case .firstRun: "Re-visit the first run experience for each page."
        case .privacyPolicy: "How Festival Score Tracker handles your information."
        }
    }

    /// The chevron row's accessibility identifier. Privacy Policy keeps the identifier of
    /// its single-page row, which opens the same policy as a sheet.
    var accessibilityIdentifier: String {
        self == .privacyPolicy ? "fst.settings.privacy-policy" : "fst.settings.topic.\(rawValue)"
    }

    /// Whether the row sits inside the App Settings card (beside the toggles it belongs
    /// to) rather than standing alone like the Licenses link.
    var isAppSettingsRow: Bool {
        self == .songRowOrder || self == .paths
    }
}
