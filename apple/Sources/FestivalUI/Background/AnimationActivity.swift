import SwiftUI

// MARK: - Window visibility

extension EnvironmentValues {
    /// Whether the window showing this view can be seen. The Mac shell sets it from
    /// the window's occlusion state (minimized, fully covered, on another Space or a
    /// locked screen); iPhone and iPad leave it true and rely on the scene phase.
    @Entry var festivalWindowVisible = true
}

/// One rule for every continuous decoration (artwork carousel, Shop pulses): it runs
/// only in an active scene whose window is visible, as the Windows app pauses when
/// occluded or minimized.
enum AnimationActivity {
    /// Whether continuous decoration may run.
    ///
    /// - Parameters:
    ///   - phase: The scene phase.
    ///   - windowVisible: ``SwiftUI/EnvironmentValues/festivalWindowVisible``.
    /// - Returns: True only for an active, visible scene.
    static func sceneActive(_ phase: ScenePhase, windowVisible: Bool) -> Bool {
        phase == .active && windowVisible
    }
}
