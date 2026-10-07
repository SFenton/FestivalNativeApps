#if os(macOS)
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Settings window

/// Content of the app's Settings window (App menu › Settings…, ⌘,): a toolbar of
/// panes (General, Songs, Paths, Guides, Service, About) that restores the last pane.
///
/// HIG Settings › macOS: "Choosing Settings from the App menu opens a window,
/// typically a toolbar of related panes … title the window for its pane … restore the
/// last pane." Each pane is a subset of the shared Settings page
/// (``SettingsScreen/pane``) with the same settings and identifiers, in its own stack
/// so Licenses opens inside About.
public struct MacSettingsView: View {
    let model: MacAppModel
    @AppStorage(SettingsPane.storageKey) private var storedPane = SettingsPane.general.rawValue
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @Environment(\.colorSchemeContrast) private var systemContrast

    /// Settings window content size (points): wide enough for two ~400 pt columns of
    /// sections (pattern `wide-columns` R7, #355; a one-section pane keeps one readable
    /// column), tall enough for most panes without scrolling.
    static let size = CGSize(width: 860, height: 620)

    /// Create the Settings window content.
    ///
    /// - Parameter model: The app model shared with the main window.
    public init(model: MacAppModel) {
        self.model = model
    }

    private var selection: Binding<SettingsPane> {
        Binding {
            SettingsPane.restored(from: storedPane)
        } set: { storedPane = $0.rawValue }
    }

    public var body: some View {
        TabView(selection: selection) {
            ForEach(SettingsPane.allCases) { pane in
                MacSettingsPaneView(session: model.session, pane: pane)
                    .tabItem { Label(pane.title, systemImage: pane.symbol) }
                    .tag(pane)
                    .accessibilityIdentifier(pane.accessibilityIdentifier)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .tint(moreContrast || systemContrast == .increased ? BrandTokens.textPrimary : BrandTokens.accentBlue)
        .preferredColorScheme(.dark)
        .environment(\.festivalSession, model.session)
        .environment(\.shellOwnsGlobalToolbar, true)
        .environment(\.settingsChoicesUsePopUpButtons, true)
    }
}

/// One Settings pane in its own stack (Licenses pushes inside About).
struct MacSettingsPaneView: View {
    let session: FestivalSession
    let pane: SettingsPane
    @State private var path: [AppRoute] = []

    var body: some View {
        MacStack(
            session: session, visibleInstruments: Set(Instrument.allCases),
            stackPath: $path, fullPath: $path, isVisible: true
        ) {
            SettingsScreen(session: session, isVisible: true, pane: pane)
        }
        .background(BrandTokens.appBackground)
    }
}
#endif
