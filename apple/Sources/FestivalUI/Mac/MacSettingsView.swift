#if os(macOS)
import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Settings window

/// Content of the app's Settings window (App menu › Settings…, ⌘,).
///
/// HIG Settings › macOS puts settings in the App menu and a separate window rather than
/// the main window's navigation, so the web's Settings page is not a sidebar row here.
/// The window reuses the shared Settings page (one long page, like the web) in its own
/// stack so Licenses can open inside it.
public struct MacSettingsView: View {
    let model: MacAppModel
    @State private var path: [AppRoute] = []
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    @Environment(\.colorSchemeContrast) private var systemContrast

    /// Create the Settings window content.
    ///
    /// - Parameter model: The app model shared with the main window.
    public init(model: MacAppModel) {
        self.model = model
    }

    public var body: some View {
        MacStack(
            session: model.session, visibleInstruments: Set(Instrument.allCases),
            stackPath: $path, fullPath: $path, isVisible: true
        ) {
            SettingsScreen(session: model.session, isVisible: true)
        }
        .background(BrandTokens.appBackground)
        .frame(minWidth: 560, idealWidth: 640, minHeight: 520, idealHeight: 760)
        .tint(moreContrast || systemContrast == .increased ? BrandTokens.textPrimary : BrandTokens.accentBlue)
        .preferredColorScheme(.dark)
        .environment(\.festivalSession, model.session)
        .environment(\.shellOwnsGlobalToolbar, true)
    }
}
#endif
