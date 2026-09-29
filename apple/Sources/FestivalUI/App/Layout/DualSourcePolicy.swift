import CoreGraphics
import SwiftUI

// MARK: - Dual-source policy

/// Pure rules for splitting a page into two stacked regions on the iPhone Duo inner
/// display in portrait (`.agents/design/apple/duo.md`, "Dual-source half-fold layouts").
///
/// The top (primary) region keeps the page's usual content; the bottom (secondary)
/// region shows a second, related source of information. Partially open, the split
/// sits exactly on the fold (the division reserved region), so nothing interactive lands
/// on the crease. Flat, the same two regions split proportionally, so folding and
/// unfolding only move the divider. Every other pose shows the primary content alone.
///
/// **Shelved** (operator, 2026-09-28: "I'd rather just have portrait layout, even in
/// not-fully-open mode"). ``isEnabled`` is false, so `DeviceLayout` never produces
/// `.dualSource`: every `DualSourceLayout` renders its primary alone, rows push, and
/// the section set and list/detail follow the pre-dual rules. Flip the flag to revisit.
enum DualSourcePolicy {
    /// Single switch for the whole dual-source feature (default off).
    static let isEnabled = false

    /// Where the two regions divide.
    enum Mode: Sendable, Equatable {
        /// One region: the page's primary content only.
        case single
        /// Divide on the horizontal fold (partially open, portrait).
        case atFold(CGRect)
        /// Divide at ``primaryShare`` of the height (flat, portrait).
        case proportional
    }

    /// Heights of the two regions and the gutter between them, top to bottom.
    struct Regions: Sendable, Equatable {
        /// Primary (top) region height.
        let primary: CGFloat
        /// Gutter between the regions: the fold's own height, or ``proportionalGap``.
        let gap: CGFloat
        /// Secondary (bottom) region height.
        let secondary: CGFloat
    }

    /// Share of the container the primary region gets when the display is flat.
    static let primaryShare: CGFloat = 0.58
    /// Gutter between the regions when the display is flat.
    static let proportionalGap: CGFloat = 12
    /// Smallest gutter kept around a fold that reports a zero-height division.
    static let minimumFoldGap: CGFloat = 8
    /// Smallest useful region; a fold that leaves less on either side falls back to
    /// the proportional split inside the container.
    static let minimumRegionHeight: CGFloat = 120

    /// How a window divides pages that have a second source.
    ///
    /// - Parameter layout: Published window layout.
    /// - Returns: The split mode.
    static func mode(_ layout: DeviceLayout) -> Mode {
        guard layout.contentArrangement == .dualSource else { return .single }
        if let fold = layout.foldFrame, fold.width >= fold.height { return .atFold(fold) }
        return .proportional
    }

    /// Whether pages show their second source at all in this window.
    ///
    /// Pages that move part of their own content into the secondary region (Player
    /// profile charts) read this to avoid showing it twice.
    ///
    /// - Parameter layout: Published window layout.
    /// - Returns: True for the inner display in portrait.
    static func isActive(_ layout: DeviceLayout) -> Bool { mode(layout) != .single }

    /// Divide a container into regions.
    ///
    /// - Parameters:
    ///   - mode: Split mode from ``mode(_:)``.
    ///   - container: The layout's frame in window coordinates (the same space as the
    ///     reserved-region fold frame).
    /// - Returns: Region heights, or nil for ``Mode/single`` or a container too small
    ///   to hold two useful regions.
    static func regions(mode: Mode, container: CGRect) -> Regions? {
        let height = container.height
        guard height >= minimumRegionHeight * 2 + proportionalGap else { return nil }
        switch mode {
        case .single:
            return nil
        case let .atFold(fold):
            // Centre the gutter on the fold, widening a hairline division a little.
            let gapHeight = max(fold.height, minimumFoldGap)
            let top = (fold.midY - gapHeight / 2 - container.minY).rounded()
            let bottom = height - top - gapHeight
            if top >= minimumRegionHeight, bottom >= minimumRegionHeight {
                return Regions(primary: top, gap: gapHeight, secondary: bottom)
            }
            return proportional(height: height)
        case .proportional:
            return proportional(height: height)
        }
    }

    /// The flat split: ``primaryShare`` above ``proportionalGap``.
    ///
    /// - Parameter height: Container height.
    /// - Returns: Region heights.
    private static func proportional(height: CGFloat) -> Regions {
        let primary = ((height - proportionalGap) * primaryShare).rounded()
        return Regions(primary: primary, gap: proportionalGap, secondary: height - proportionalGap - primary)
    }
}
