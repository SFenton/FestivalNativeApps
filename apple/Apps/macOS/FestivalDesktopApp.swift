import SwiftUI
import FestivalUI

/// Native macOS app: one primary window (sidebar shell), the Settings window and the
/// menu bar commands, all sharing one ``MacAppModel``.
@main
struct FestivalDesktopApp: App {
    @State private var model = MacAppModel()

    init() {
        MacDebugHooks.install()
    }

    var body: some Scene {
        Window("Festival Score Tracker", id: "main") {
            MacRootView(model: model)
        }
        .defaultSize(width: MacWindowMetrics.defaultSize.width, height: MacWindowMetrics.defaultSize.height)
        .windowToolbarStyle(.unified)
        .commands { MacCommands(model: model) }

        Settings {
            MacSettingsView(model: model)
        }
    }
}
