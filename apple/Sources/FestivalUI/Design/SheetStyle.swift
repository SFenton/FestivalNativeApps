import SwiftUI
import FestivalDesign

// MARK: - Sheet style

/// Detent presets shared by every Festival modal.
public enum FestivalSheetSize: Sendable {
    /// Short pickers and confirmations: medium, expandable to large.
    case compact
    /// Search, filters and forms that need the full height.
    case large

    var detents: Set<PresentationDetent> {
        switch self {
        case .compact: [.medium, .large]
        case .large: [.large]
        }
    }
}

/// Dark Liquid Glass modal presentation (see `.agents/design/apple/liquid-glass.md`).
///
/// - iOS/macOS 26+: the system sheet material *is* Liquid Glass (translucent at partial
///   detents, opaque when expanded). We keep it, forced to the dark appearance, because any
///   `presentationBackground` would replace it with a flat fill.
/// - iOS 17–25: a dark `.ultraThinMaterial` plus a brand navy tint (frosted, not glass).
/// - Reduce Transparency (system or in-app) and Increase Contrast: opaque card colour.
struct FestivalSheetModifier: ViewModifier {
    let size: FestivalSheetSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .presentationDetents(size.detents)
            .presentationDragIndicator(.visible)
            .modifier(SheetBackground(opaque: reduceTransparency || lessTransparency || moreContrast))
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
    }

}

/// System glass on 26+, frosted navy before it, opaque navy for accessibility overrides.
private struct SheetBackground: ViewModifier {
    let opaque: Bool

    func body(content: Content) -> some View {
        if opaque {
            content.presentationBackground(BrandTokens.cardBackground)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content
        } else {
            content.presentationBackground {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    BrandTokens.cardBackground.opacity(0.62)
                }
            }
        }
    }
}

public extension View {
    /// Present this view as a dark-glass Festival sheet with native detents.
    ///
    /// Apply to the **root of the sheet content** (inside `.sheet { … }`), not to the
    /// presenting view. Use `FestivalSectionHeader` for section titles inside the sheet
    /// so they render white and Title Case.
    ///
    /// ```swift
    /// .sheet(isPresented: $sortPresented) {
    ///     SongsSortSheet(…).festivalSheet(.compact)
    /// }
    /// ```
    ///
    /// - Parameter size: Detent preset; `.large` by default.
    /// - Returns: The sheet content with Festival presentation styling.
    func festivalSheet(_ size: FestivalSheetSize = .large) -> some View {
        modifier(FestivalSheetModifier(size: size))
    }
}
