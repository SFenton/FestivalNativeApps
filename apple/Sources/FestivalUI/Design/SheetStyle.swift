import SwiftUI
import FestivalDesign

// MARK: - Sheet style

/// Detent presets shared by every Festival modal.
public enum FestivalSheetSize: Sendable {
    /// Short pickers and confirmations: opens at large (operator, 2026-09-28: sheets
    /// opened only halfway), and can still be dragged down to medium.
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

/// Width sizing for a sheet across size classes (see `.agents/design/apple/duo.md`).
///
/// This is independent of ``FestivalSheetSize``'s *height* detents: sizing picks a system
/// `presentationSizing` (iOS/macOS 18+) so Duo unfolded and iPad don't stretch a short,
/// standalone task edge-to-edge like Mail's compose sheet does on iPad.
public enum FestivalSheetSizing: Sendable {
    /// A fixed, centered "form" card at regular width (Duo unfolded, iPad) — the system's
    /// own compact-width sheet elsewhere. The default for short tasks: pickers, filters,
    /// sort, notifications, search.
    case automatic
    /// Full-bleed "page" sizing at every width, for content that benefits from using all
    /// of it regardless of size class (e.g. the zoomable Paths image/text viewer).
    case page
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
    var sizing: FestivalSheetSizing = .automatic
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.deviceLayout) private var deviceLayout
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    /// Every sheet opens at the large detent.
    @State private var detent: PresentationDetent = .large

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .presentationDetents(size.detents, selection: $detent)
            .presentationDragIndicator(.visible)
            .modifier(SheetBackground(opaque: reduceTransparency || lessTransparency || moreContrast))
            .modifier(FestivalSheetSizingModifier(
                sizing: sizing, regularWidth: deviceLayout.widthClass == .regular
            ))
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
    }

}

/// Applies `presentationSizing(.form)` at regular width (Duo unfolded/iPad) unless the
/// caller asked for full-bleed `.page` sizing everywhere. No-op pre-iOS/macOS 18.
private struct FestivalSheetSizingModifier: ViewModifier {
    let sizing: FestivalSheetSizing
    let regularWidth: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            switch sizing {
            case .page:
                content.presentationSizing(.page)
            case .automatic:
                if regularWidth {
                    content.presentationSizing(.form)
                } else {
                    content
                }
            }
        } else {
            content
        }
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
    /// - Parameters:
    ///   - size: Detent preset; `.large` by default.
    ///   - sizing: Width sizing across size classes; `.automatic` (form at regular width)
    ///     by default. Pass `.page` for content that wants full width everywhere.
    /// - Returns: The sheet content with Festival presentation styling.
    func festivalSheet(
        _ size: FestivalSheetSize = .large, sizing: FestivalSheetSizing = .automatic
    ) -> some View {
        modifier(FestivalSheetModifier(size: size, sizing: sizing))
    }
}

// MARK: - Sheet actions

/// Colours for text actions inside Festival sheets.
public enum FestivalSheetActionColor {
    /// Reset / Clear actions: red, as the operator asked for every filter and sort sheet,
    /// but light enough (#FF6B66) to keep 4.5:1 contrast on the dark sheet surface
    /// (`BrandTokens.statusRed` is a fill colour and fails as text).
    public static let destructive = Color(.sRGB, red: 1.0, green: 107.0 / 255, blue: 102.0 / 255)
}
