import SwiftUI
import FestivalUI

/// Native macOS app: one primary window (sidebar shell), the Settings window and the
/// menu bar commands, all sharing one ``MacAppModel``.
@main
struct FestivalDesktopApp: App {
    @State private var model = MacAppModel()

    init() {
        MacDebugHooks.install()
        // Debug `FST_DEBUG_STALL_LOG=<path>`: main-thread stall report (scroll stress).
        MainThreadStallMonitor.startIfRequested()
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
