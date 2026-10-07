import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Page title

/// A page title with the instrument artwork to its left: the large heading at the top
/// of the list, and the compact copy the bar shows once that heading has scrolled under
/// it. Full Rankings (issue #294) and a song board opened beside Song Detail in a split
/// (issue #342, where the song header would repeat the song beside it) use it.
///
/// The artwork is decorative (the title already names the instrument), so it is hidden
/// from VoiceOver, and it scales with the title's text style so it keeps matching the
/// text at every Dynamic Type size (HIG Icons: "Match icon weight to adjacent text").
/// The artwork's visible disc fills about 84% of its square, so a square slightly
/// taller than the font's point size reads as the same height as the capitals. A band
/// board has no instrument, so its title is the band size alone.
struct InstrumentPageTitle: View {
    /// Where the title is drawn.
    enum Style {
        /// The page's large heading, first in the scrolling content.
        case header
        /// The navigation bar's principal title after the heading scrolls away.
        case pinned
    }

    /// The chart whose artwork leads the title; nil draws the title alone.
    let instrument: Instrument?
    let title: String
    /// A secondary line under a header title (a board's entry total); ignored when pinned.
    var subtitle: String?
    let style: Style
    /// Accessibility identifier of the combined title element.
    let identifier: String
    @ScaledMetric(relativeTo: .largeTitle) private var headerIconSide: CGFloat = 36
    @ScaledMetric(relativeTo: .headline) private var pinnedIconSide: CGFloat = 24

    /// Create a page title.
    ///
    /// - Parameters:
    ///   - instrument: The chart whose artwork leads the title, or nil (band sizes).
    ///   - title: The page's name, e.g. "Lead Rankings" or "Lead".
    ///   - subtitle: A secondary line under the header title, or nil.
    ///   - style: The in-page heading or the bar's compact title.
    ///   - identifier: Accessibility identifier of the title.
    init(
        instrument: Instrument?, title: String, subtitle: String? = nil, style: Style,
        identifier: String
    ) {
        self.instrument = instrument
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.identifier = identifier
    }

    var body: some View {
        HStack(spacing: style == .header ? 10 : 6) {
            if let instrument {
                InstrumentIcon(instrument, size: style == .header ? headerIconSide : pinnedIconSide)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            switch style {
            case .header:
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(FestivalText.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(FestivalText.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .pinned:
                MarqueeText(title)
                    .font(.headline)
                    .foregroundStyle(FestivalText.primary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Pinned bar title

/// The bar's principal item on a page with an ``InstrumentPageTitle`` heading: the
/// pinned title while the heading is scrolled away, otherwise an empty, unspoken
/// placeholder.
///
/// Built only while shown: a hidden (opacity 0) copy was still audited, and its icon
/// failed Dynamic Type on Song Leaderboard. Until then the placeholder holds the slot,
/// so the bar does not fall back to `navigationTitle` above the in-list title (issue
/// #93). Callers skip it on the iPhone Duo vertical bar, whose rail never draws a
/// custom title view (`/duo` D4).
struct InstrumentPageTitleToolbarItem: ToolbarContent {
    let instrument: Instrument?
    let title: String
    /// Whether the in-page heading has scrolled under the bar.
    let isShown: Bool
    /// Accessibility identifier of the shown title.
    let identifier: String

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if isShown {
                InstrumentPageTitle(instrument: instrument, title: title, style: .pinned, identifier: identifier)
                    .frame(maxWidth: 260)
                    // A bar title stays on one line at every text size.
                    .environment(\.marqueeWrapsAtAccessibilitySizes, false)
                    .transition(.opacity)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
        }
    }
}
