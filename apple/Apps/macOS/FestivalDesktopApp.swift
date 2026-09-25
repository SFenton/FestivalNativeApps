import SwiftUI
import FestivalUI

/// Native macOS window lifecycle shared with the Swift feature package.
@main
struct FestivalDesktopApp: App {
    var body: some Scene {
        WindowGroup {
            FestivalRootView()
                .frame(minWidth: 620, minHeight: 460)
        }
    }
}
