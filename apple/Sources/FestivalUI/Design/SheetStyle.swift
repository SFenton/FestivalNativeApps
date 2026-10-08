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
    @Environment(\.festivalModalCoverage) private var coverage
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false
    /// Every sheet opens at the large detent.
    @State private var detent: PresentationDetent = .large

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .presentationDetents(size.detents, selection: $detent)
            // The system grabber hugs the sheet's top edge and cannot be moved; HIG shows
            // it only on resizable sheets, so large-only sheets drop it (operator batch 7:
            // grabber too close to the top) and keep their top-right Close.
            .presentationDragIndicator(size.detents.count > 1 ? .visible : .hidden)
            .modifier(SheetBackground(opaque: reduceTransparency || lessTransparency || moreContrast))
            .modifier(FestivalSheetSizingModifier(
                sizing: sizing, regularWidth: deviceLayout.windowWidthClass == .regular,
                fitsWindow: coverage == .fullScreen
            ))
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
            .pausesFestivalBackdrop()
    }

}

/// Applies `presentationSizing(.form)` at regular width (Duo unfolded/iPad) unless the
/// caller asked for full-bleed `.page` sizing everywhere. A full-window Mac sheet
/// (`festivalModalPresentation` with `.fullScreen` coverage, issue #368) uses `.fitted`
/// so the window-sized frame of `MacWindowSizedSheet` decides its size; `.page` would
/// cap it near 700 pt. No-op pre-iOS/macOS 18.
private struct FestivalSheetSizingModifier: ViewModifier {
    let sizing: FestivalSheetSizing
    let regularWidth: Bool
    var fitsWindow = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            #if os(macOS)
            if fitsWindow {
                content.presentationSizing(.fitted)
            } else {
                sized(content)
            }
            #else
            sized(content)
            #endif
        } else {
            content
        }
    }

    @available(iOS 18.0, macOS 15.0, *)
    @ViewBuilder
    private func sized(_ content: Content) -> some View {
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
    /// but light enough (#FF8C88) to keep 4.5:1 contrast on the sheet surface in every
    /// mode (`BrandTokens.statusRed` is a fill colour and fails as text). #FF6B66 rendered
    /// 4.33:1 under Increase Contrast, where the button platter is lighter (iPad audit,
    /// Lane A11Y3); #FF8C88 gives about 5.4:1 there.
    public static let destructive = Color(.sRGB, red: 1.0, green: 140.0 / 255, blue: 136.0 / 255)
}

/// The native Close button every Festival modal carries top-right (operator batch 7):
/// the system close glyph (`Button(role: .close)`) on iOS/macOS 26+, a "Close" text
/// button before. Modals get it through ``FestivalModal`` rather than adding it themselves.
public struct FestivalSheetCloseItem: ToolbarContent {
    private let identifier: String
    private let action: () -> Void

    /// Create the close item.
    ///
    /// - Parameters:
    ///   - identifier: Accessibility identifier (existing sheets keep theirs).
    ///   - action: Dismisses the sheet.
    public init(identifier: String, action: @escaping () -> Void) {
        self.identifier = identifier
        self.action = action
    }

    public var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Group {
                if #available(iOS 26.0, macOS 26.0, *) {
                    Button(role: .close, action: action)
                } else {
                    Button("Close", action: action)
                }
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier(identifier)
        }
    }
}
