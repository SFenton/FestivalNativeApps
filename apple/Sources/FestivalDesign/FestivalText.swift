import SwiftUI

// MARK: - Text colour rule

/// The app's text colour rule (operator, 2026-09-28): **text is white everywhere**.
///
/// Use `primary` for every readable string: titles, values, labels (including stat
/// tile captions), row subtitles such as artist names, descriptions, empty-state and
/// status messages. Reach for `deemphasized` only where Apple's HIG clearly wants a
/// quieter tone, and `disabled` only for inactive controls. Features should use these
/// tokens instead of `.secondary`, `.tertiary`, `.gray` or raw `BrandTokens.text*`
/// colours so the rule stays in one place (`.agents/platforms/apple/architecture.md`).
public enum FestivalText {
    /// White. The default for all readable text.
    public static let primary = BrandTokens.textPrimary

    /// Muted blue-grey for HIG de-emphasis only, inside opaque cards, sheets or lists
    /// (it fails contrast over bright artwork): timestamps and dates,
    /// chart axis labels, text-field placeholders, and decorative glyphs (disclosure chevrons, search magnifier,
    /// clear buttons). Never for content a reader needs to compare or act on.
    public static let deemphasized = BrandTokens.textMuted

    /// Inactive controls and unavailable options.
    public static let disabled = BrandTokens.textDisabled
}
