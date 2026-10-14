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
/// board has no instrument, so its title is the band size alone. A combo board (issue
/// #602) draws its instruments' artwork in a row above the heading, as the web
/// `FullRankingsPage` does, and its pinned bar title is the text alone.
///
/// The Rival pages (issue #604) title the page with the rival or the section and put
/// the list it belongs to in the subtitle ("Lead Rivals", led by that chart's icon), so
/// the subtitle can carry its own decorative icon, and their pinned bar copy keeps the
/// subtitle as a caption under the title, like a song page's bar title (#542).
struct InstrumentPageTitle: View {
    /// Where the title is drawn.
    enum Style {
        /// The page's large heading, first in the scrolling content.
        case header
        /// The navigation bar's principal title after the heading scrolls away.
        case pinned
    }

    /// The charts whose artwork leads the title: none draws the title alone, one leads
    /// it, several (a combo) sit in a row above the header.
    let instruments: [Instrument]
    let title: String
    /// A secondary line under the title (a board's entry total, a Rival page's list or
    /// rival). The pinned copy shows it as a caption only when the toolbar item passes it.
    var subtitle: String?
    /// The chart whose artwork leads the subtitle (a single-chart Rival Detail, #604).
    var subtitleInstrument: Instrument?
    let style: Style
    /// Accessibility identifier of the combined title element.
    let identifier: String
    @ScaledMetric(relativeTo: .largeTitle) private var headerIconSide: CGFloat = 36
    @ScaledMetric(relativeTo: .headline) private var pinnedIconSide: CGFloat = 24
    /// The song board line's ratio (20 pt beside 17 pt body, `SongBoardLine`) at the
    /// 15 pt subheadline.
    @ScaledMetric(relativeTo: .subheadline) private var headerSubtitleIconSide: CGFloat = 18
    /// The song bar caption's icon (`SongBarTitle`): no taller than the caption's line.
    @ScaledMetric(relativeTo: .caption) private var pinnedSubtitleIconSide: CGFloat = 14

    /// Create a page title.
    ///
    /// - Parameters:
    ///   - instrument: The chart whose artwork leads the title, or nil (band sizes).
    ///   - title: The page's name, e.g. "Lead Rankings" or "Lead".
    ///   - subtitle: A secondary line under the title, or nil.
    ///   - subtitleInstrument: The chart whose artwork leads the subtitle, or nil.
    ///   - style: The in-page heading or the bar's compact title.
    ///   - identifier: Accessibility identifier of the title.
    init(
        instrument: Instrument?, title: String, subtitle: String? = nil,
        subtitleInstrument: Instrument? = nil, style: Style, identifier: String
    ) {
        self.init(
            instruments: instrument.map { [$0] } ?? [], title: title, subtitle: subtitle,
            subtitleInstrument: subtitleInstrument, style: style, identifier: identifier
        )
    }

    /// Create a page title for a board of one or more charts.
    ///
    /// - Parameters:
    ///   - instruments: The board's charts; several draw a combo's icon row.
    ///   - title: The page's name, e.g. "Lead + Bass Rankings".
    ///   - subtitle: A secondary line under the title, or nil.
    ///   - subtitleInstrument: The chart whose artwork leads the subtitle, or nil.
    ///   - style: The in-page heading or the bar's compact title.
    ///   - identifier: Accessibility identifier of the title.
    init(
        instruments: [Instrument], title: String, subtitle: String? = nil,
        subtitleInstrument: Instrument? = nil, style: Style, identifier: String
    ) {
        self.instruments = instruments
        self.title = title
        self.subtitle = subtitle
        self.subtitleInstrument = subtitleInstrument
        self.style = style
        self.identifier = identifier
    }

    var body: some View {
        HStack(spacing: style == .header ? 10 : 6) {
            if instruments.count == 1, let instrument = instruments.first {
                InstrumentIcon(instrument, size: style == .header ? headerIconSide : pinnedIconSide)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            switch style {
            case .header:
                VStack(alignment: .leading, spacing: 2) {
                    if instruments.count > 1 {
                        InstrumentIconRow(instruments: instruments, side: headerIconSide, spacing: 8)
                            .padding(.bottom, 4)
                    }
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(FestivalText.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        HStack(spacing: 6) {
                            subtitleIcon(side: headerSubtitleIconSide)
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(FestivalText.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .pinned:
                VStack(alignment: instruments.count == 1 ? .leading : .center, spacing: 0) {
                    MarqueeText(title)
                        .font(.headline)
                        .foregroundStyle(FestivalText.primary)
                        .lineLimit(1)
                    if let subtitle {
                        HStack(spacing: 4) {
                            subtitleIcon(side: pinnedSubtitleIconSide)
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(FestivalText.primary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(identifier)
    }

    /// The subtitle's decorative chart icon, when it has one: hidden from VoiceOver,
    /// because the subtitle's text names the instrument.
    @ViewBuilder
    private func subtitleIcon(side: CGFloat) -> some View {
        if let subtitleInstrument {
            InstrumentIcon(subtitleInstrument, size: side)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Combo icon row

/// A combo's instrument artwork in a row (web `CompeteScopeHeader` / `FullRankingsPage`
/// combo title: the icons above the "Lead + Bass" label). Decorative: the label beside
/// it names the instruments, so it is hidden from VoiceOver.
struct InstrumentIconRow: View {
    let instruments: [Instrument]
    /// Side of each icon's square.
    let side: CGFloat
    /// Gap between icons: web `Gap.sm` (4 pt) in Compete's card header, `Gap.md` (8 pt)
    /// in the Full Rankings title.
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(instruments, id: \.self) { instrument in
                InstrumentIcon(instrument, size: side)
                    .fixedSize()
            }
        }
        .accessibilityHidden(true)
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
/// #93). Callers skip it on the iPhone Duo vertical bar, where iOS 27 minimizes the
/// top navigation bar on scroll, so the system title stays (pattern
/// `page-tools-and-nav-chrome` R14; only song pages keep that bar, #363).
struct InstrumentPageTitleToolbarItem: ToolbarContent {
    let instrument: Instrument?
    let title: String
    /// A caption under the pinned title (a Rival page's subtitle, #604), or nil.
    var subtitle: String? = nil
    /// The chart whose artwork leads the caption, or nil.
    var subtitleInstrument: Instrument? = nil
    /// Whether the in-page heading has scrolled under the bar.
    let isShown: Bool
    /// Accessibility identifier of the shown title.
    let identifier: String

    /// Whether a page whose top bar minimizes on scroll (Full Rankings, All Rivals) may
    /// pin its title in this chrome: not on the iPhone Duo vertical bar, where the
    /// system title stays instead (pattern `page-tools-and-nav-chrome` R14). Song
    /// pages keep their top bar (#363) and do not ask.
    ///
    /// - Parameter chrome: The section chrome the page is shown in.
    /// - Returns: False on the vertical bar, true otherwise.
    nonisolated static func pinsTitle(in chrome: DeviceLayout.SectionChrome) -> Bool {
        !chrome.isVerticalBar
    }

    @Environment(\.pageToolsRegistry) private var pageTools

    var body: some ToolbarContent {
        ToolbarItem(placement: FestivalTitlePlacement.resolve(floatsPageTools: pageTools != nil).toolbarPlacement) {
            if isShown {
                InstrumentPageTitle(
                    instrument: instrument, title: title, subtitle: subtitle,
                    subtitleInstrument: subtitleInstrument, style: .pinned, identifier: identifier
                )
                    .frame(maxWidth: 260)
                    // A bar title stays on one line at every text size; UIKit caps the
                    // size of what a bar hosts, so it offers the Large Content Viewer, as
                    // system bar titles and `SongBarTitle` do (`system-bar-title-size`).
                    .environment(\.marqueeWrapsAtAccessibilitySizes, false)
                    .accessibilityShowsLargeContentViewer()
                    .transition(.opacity)
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            }
        }
    }
}
