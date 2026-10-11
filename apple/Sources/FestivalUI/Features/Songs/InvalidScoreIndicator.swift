import FestivalCore
import FestivalDesign
import SwiftUI

// MARK: - Glyph

/// The Songs row's invalid-score glyph (web `InvalidScoreIcon`): a red alert circle when
/// Filter Invalid Scores replaced or dropped a score, a gold warning when every described
/// score is kept above the CHOpt maximum by an Over CHOpt Threshold filter. It pulses
/// like the web's `choptIconPulse` (an SF Symbols pulse, HIG Motion: "Consider animated
/// SF Symbols"), held still by Reduce Motion, an inactive scene or the UI-test still
/// override.
///
/// It is drawn inside the row and hidden from accessibility; its button is placed over
/// it outside the row's link (``SwiftUI/View/songInvalidScoreIndicator(songId:)``).
struct InvalidScoreGlyph: View {
    let warning: InvalidScoreWarning
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("fst.accessibility.reduceMotion") private var appReduceMotion = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.festivalWindowVisible) private var windowVisible
    /// The web draws a 34 pt icon whose circle is about 28 pt; scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 28

    /// SF Symbol for a warning's tone.
    ///
    /// - Parameter warning: The row's warning.
    /// - Returns: `exclamationmark.triangle.fill` (web `IoWarning`) or
    ///   `exclamationmark.circle` (web `IoAlertCircleOutline`).
    static func symbol(for warning: InvalidScoreWarning) -> String {
        warning.isOverThreshold ? "exclamationmark.triangle.fill" : "exclamationmark.circle"
    }

    /// Glyph colour (web `Colors.gold` / `Colors.statusRed`).
    ///
    /// - Parameter warning: The row's warning.
    /// - Returns: Gold or red.
    static func color(for warning: InvalidScoreWarning) -> Color {
        warning.isOverThreshold ? BrandTokens.gold : BrandTokens.statusRed
    }

    var body: some View {
        let running = ShopStatusBreathe.animates(
            reduceMotion: systemReduceMotion || appReduceMotion,
            sceneActive: AnimationActivity.sceneActive(scenePhase, windowVisible: windowVisible),
            still: DebugAnimationOverride.stillBackground
        )
        Image(systemName: Self.symbol(for: warning))
            .resizable()
            .scaledToFit()
            .frame(width: side, height: side)
            .foregroundStyle(Self.color(for: warning))
            .symbolEffect(.pulse, options: .repeating, isActive: running)
            .accessibilityHidden(true)
            .anchorPreference(key: InvalidScoreIndicatorKey.self, value: .bounds) {
                InvalidScoreIndicatorStop(warning: warning, bounds: $0)
            }
    }
}

// MARK: - Button

/// The drawn glyph's warning and bounds, for its button outside the link.
struct InvalidScoreIndicatorStop {
    let warning: InvalidScoreWarning
    let bounds: Anchor<CGRect>
}

/// One Songs row's invalid-score glyph, if it drew one.
struct InvalidScoreIndicatorKey: PreferenceKey {
    static let defaultValue: InvalidScoreIndicatorStop? = nil

    static func reduce(value: inout InvalidScoreIndicatorStop?, nextValue: () -> InvalidScoreIndicatorStop?) {
        value = value ?? nextValue()
    }
}

/// The indicator's button and its "Filtered Score" alert (web `InvalidScoreIcon`'s
/// `ConfirmAlert`: OK, and Settings to change Filter Invalid Scores). An informational
/// alert, so OK is its acceptance button (HIG Alerts: "you can use OK for acceptance").
struct InvalidScoreIndicatorButton: View {
    let warning: InvalidScoreWarning
    let songId: String
    @Environment(\.openAppSettings) private var openAppSettings
    @State private var presented = false

    /// Minimum hit region (HIG Buttons: "the hit region is at least 44x44 pt").
    static let minimumTarget: CGFloat = 44

    var body: some View {
        Button {
            presented = true
        } label: {
            Color.clear
                .frame(minWidth: Self.minimumTarget, minHeight: Self.minimumTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(InvalidScoreWarning.accessibilityLabel)
        .accessibilityHint("Explains the filtered score")
        .accessibilityIdentifier("fst.songs.invalid-score.\(songId)")
        .alert(InvalidScoreWarning.title, isPresented: $presented) {
            Button("OK", role: .cancel) {}
                .accessibilityIdentifier("fst.songs.invalid-score.ok")
            if let openAppSettings {
                Button(InvalidScoreWarning.settingsAction) { openAppSettings() }
                    .accessibilityIdentifier("fst.songs.invalid-score.settings")
            }
        } message: {
            Text(warning.message)
        }
    }
}

extension View {
    /// Put a Songs row's invalid-score button over its drawn glyph, outside the row's
    /// link so a tap opens the explanation rather than the song, and after the song in
    /// VoiceOver order. Apply it before ``songProfilePanelAccessibility(songId:)`` so the
    /// profile-panel cards follow it. Rows without a glyph add nothing.
    ///
    /// - Parameter songId: The row's song.
    /// - Returns: The row with its indicator button.
    func songInvalidScoreIndicator(songId: String) -> some View {
        // SwiftUI lists an overlay's elements before its content's; the song reads first.
        accessibilitySortPriority(2)
        .overlayPreferenceValue(InvalidScoreIndicatorKey.self) { stop in
            if let stop {
                GeometryReader { proxy in
                    let frame = proxy[stop.bounds]
                    InvalidScoreIndicatorButton(warning: stop.warning, songId: songId)
                        .frame(
                            width: max(frame.width, InvalidScoreIndicatorButton.minimumTarget),
                            height: max(frame.height, InvalidScoreIndicatorButton.minimumTarget)
                        )
                        .position(x: frame.midX, y: frame.midY)
                }
                .accessibilitySortPriority(1)
            }
        }
    }
}
