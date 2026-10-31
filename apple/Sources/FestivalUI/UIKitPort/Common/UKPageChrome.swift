#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Page title

extension UIViewController {
    /// Sets the page title the way ``View/festivalNavigationTitle(_:)`` does: the
    /// navigation title plus a title display mode. Automatic follows the system (large
    /// at the top of a scroll view, inline once scrolled); a page with floating page
    /// tools places its title leading and inline (``FestivalTitlePlacement``).
    ///
    /// - Parameters:
    ///   - title: The page title.
    ///   - mode: Requested display mode.
    ///   - outerMode: The enclosing page's mode, inherited by an `automatic` child.
    ///   - floatsPageTools: Whether the page has floating page tools (leading inline title).
    func ukSetPageTitle(
        _ title: String, mode: FestivalTitlePlacement.PageMode = .automatic,
        outerMode: FestivalTitlePlacement.PageMode? = nil, floatsPageTools: Bool = false
    ) {
        self.title = title
        navigationItem.title = title
        let placement = FestivalTitlePlacement.resolve(floatsPageTools: floatsPageTools)
        let effective = FestivalTitlePlacement.effectiveMode(mode, outer: outerMode)
        switch placement.displayMode(for: effective) {
        case .automatic: navigationItem.largeTitleDisplayMode = .automatic
        case .inline: navigationItem.largeTitleDisplayMode = .never
        case .large: navigationItem.largeTitleDisplayMode = .always
        }
        navigationItem.style = placement.usesEditorRole ? .editor : .navigator
    }
}

// MARK: - Instrument page title

/// A page title with instrument artwork (``InstrumentPageTitle``): the `header` style is
/// the large in-page title with the icon(s) beside or above it; `pinned` is the compact
/// bar title with a marquee. One heading element (title and subtitle combined).
final class UKInstrumentPageTitleView: UIView {
    /// ``InstrumentPageTitle/Style``.
    enum Style {
        /// Large in-page title.
        case header
        /// Compact title pinned in the navigation bar.
        case pinned
    }

    private let instruments: [Instrument]
    private let titleText: String
    private let subtitleText: String?
    private let subtitleInstrument: Instrument?
    private let style: Style
    private var content: UIView?

    /// Creates the title.
    ///
    /// - Parameters:
    ///   - instruments: One instrument draws beside the title, several in a row above it.
    ///   - title: Title text.
    ///   - subtitle: Optional supporting line.
    ///   - subtitleInstrument: Icon before the subtitle.
    ///   - style: `header` or `pinned`.
    ///   - identifier: Accessibility identifier.
    init(
        instruments: [Instrument], title: String, subtitle: String? = nil, subtitleInstrument: Instrument? = nil,
        style: Style, identifier: String
    ) {
        self.instruments = instruments
        self.titleText = title
        self.subtitleText = subtitle
        self.subtitleInstrument = subtitleInstrument
        self.style = style
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isAccessibilityElement = true
        accessibilityLabel = [title, subtitle].compactMap { $0 }.joined(separator: ", ")
        accessibilityTraits = .header
        accessibilityIdentifier = identifier
        rebuild()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKInstrumentPageTitleView, _) in self.rebuild() }
    }

    /// Convenience for a single optional instrument.
    convenience init(
        instrument: Instrument?, title: String, subtitle: String? = nil, subtitleInstrument: Instrument? = nil,
        style: Style, identifier: String
    ) {
        self.init(
            instruments: instrument.map { [$0] } ?? [], title: title, subtitle: subtitle,
            subtitleInstrument: subtitleInstrument, style: style, identifier: identifier
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func rebuild() {
        content?.removeFromSuperview()
        let header = style == .header
        let iconSide = UKFont.scaled(header ? 36 : 24, relativeTo: header ? .largeTitle : .headline, traits: traitCollection)
        let subtitleSide = UKFont.scaled(header ? 18 : 14, relativeTo: header ? .subheadline : .caption1, traits: traitCollection)
        let outer = UIStackView()
        outer.axis = .horizontal
        outer.spacing = header ? 10 : 6
        outer.alignment = .center
        if instruments.count == 1, let instrument = instruments.first {
            outer.addArrangedSubview(UKInstrumentIconView(instrument, size: iconSide, hidesFromAccessibility: true))
        }
        let column = UIStackView()
        column.axis = .vertical
        column.spacing = header ? 2 : 0
        column.alignment = header ? .leading : (instruments.count == 1 ? .leading : .center)
        if header {
            if instruments.count > 1 {
                let row = UKInstrumentIconRow(instruments: instruments, side: iconSide, spacing: 8)
                column.addArrangedSubview(row)
                column.setCustomSpacing(6, after: row)
            }
            column.addArrangedSubview(UKLabel(titleText, style: .largeTitle, weight: .bold))
        } else {
            let marquee = UKMarqueeLabel(titleText, font: UKFont.font(.headline))
            marquee.wrapsAtAccessibilitySizes = false
            column.addArrangedSubview(marquee)
        }
        if let subtitleText {
            let line = UIStackView()
            line.axis = .horizontal
            line.spacing = header ? 6 : 4
            line.alignment = .center
            if let subtitleInstrument {
                line.addArrangedSubview(UKInstrumentIconView(subtitleInstrument, size: subtitleSide, hidesFromAccessibility: true))
            }
            line.addArrangedSubview(UKLabel(subtitleText, style: header ? .subheadline : .caption1, lines: header ? 0 : 1))
            column.addArrangedSubview(line)
        }
        outer.addArrangedSubview(column)
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)
        NSLayoutConstraint.activate([
            outer.leadingAnchor.constraint(equalTo: leadingAnchor), outer.topAnchor.constraint(equalTo: topAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(lessThanOrEqualToConstant: header ? 10_000 : 260),
        ])
        content = outer
    }
}

// MARK: - Song header text

/// A song's title and artist as marquees that scroll in step (``SongHeaderText``), with
/// room for details below. Use ``titleView`` to measure the title's bottom edge for the
/// scroll-away bar title (``SongHeaderScrollAway``).
final class UKSongHeaderTextView: UIView {
    /// The title marquee.
    let titleView: UKMarqueeLabel
    /// The artist marquee.
    let artistView: UKMarqueeLabel
    private let syncGroup = UKMarqueeSyncGroup()

    /// Creates the header text.
    ///
    /// - Parameters:
    ///   - title: Song title.
    ///   - artist: Artist name.
    ///   - titleFont: Title font (`.title3.bold()` in the row, `.title2.bold()` in Song Detail).
    ///   - spacing: Vertical spacing.
    ///   - details: Views under the artist.
    init(title: String, artist: String, titleFont: UIFont, spacing: CGFloat, details: [UIView] = []) {
        titleView = UKMarqueeLabel(title, font: titleFont)
        artistView = UKMarqueeLabel(artist, font: UKFont.font(.body))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        titleView.syncGroup = syncGroup
        artistView.syncGroup = syncGroup
        let stack = UIStackView(arrangedSubviews: [titleView, artistView] + details)
        stack.axis = .vertical
        stack.spacing = spacing
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// An instrument-and-text line under a song's artist (``SongBoardLine``): a body-scaled
/// 20 pt icon and a marquee.
final class UKSongBoardLine: UIView {
    /// The text marquee (put it in a ``UKMarqueeSyncGroup`` to scroll with its siblings).
    let marquee: UKMarqueeLabel

    /// Creates the line.
    ///
    /// - Parameters:
    ///   - instrument: Icon, or nil for text only.
    ///   - text: The text.
    init(instrument: Instrument?, text: String) {
        marquee = UKMarqueeLabel(text)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        if let instrument {
            stack.addArrangedSubview(UKInstrumentIconView(instrument, size: UKFont.scaled(20, relativeTo: .body), hidesFromAccessibility: true))
        }
        stack.addArrangedSubview(marquee)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Leaderboard column slot

/// A leaderboard row column that keeps a fixed width across rows
/// (``LeaderboardColumnSlot``): at least as wide as the section's widest `template`
/// string measured in the bold monospaced-digit `font`, so numbers align down the list.
/// Above accessibility text sizes there is no template and the column shrinks to fit.
final class UKLeaderboardColumnSlot: UIView {
    private let content: UIView
    private let template: String?
    private let style: UIFont.TextStyle
    private var widthConstraint: NSLayoutConstraint?

    /// Creates a slot.
    ///
    /// - Parameters:
    ///   - template: The widest string the column shows (``LeaderboardRowColumns``), or nil.
    ///   - style: The column's text style (`.body` by default).
    ///   - content: The cell content.
    init(template: String?, style: UIFont.TextStyle = .body, content: UIView) {
        self.template = template
        self.style = style
        self.content = content
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyTemplate()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKLeaderboardColumnSlot, _) in
            self.applyTemplate()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func applyTemplate() {
        widthConstraint?.isActive = false
        widthConstraint = nil
        guard let template, !template.isEmpty, !UKFont.isAccessibilitySize(traitCollection) else { return }
        let bold = UKFont.font(style, weight: .bold, monospacedDigit: true)
        let width = ceil((template as NSString).size(withAttributes: [.font: bold]).width)
        widthConstraint = widthAnchor.constraint(greaterThanOrEqualToConstant: width)
        widthConstraint?.isActive = true
    }
}

/// The leaderboard row metrics the UIKit rows read (``LeaderboardRowMetrics``).
enum UKLeaderboardRowMetrics {
    /// Minimum height of a leaderboard row.
    static var minHeight: CGFloat { LeaderboardRowMetrics.minHeight }
}

// MARK: - Self sizing

/// Self-sizing collection-view cells, measured at the width the layout proposes (the
/// port's "Layout" rule): the cell fits its content to the proposed width with a required
/// horizontal and a flexible vertical priority, so Dynamic Type up to AX5 wraps and grows
/// the row exactly as the SwiftUI list does.
class UKSelfSizingCell: UICollectionViewCell {
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = super.preferredLayoutAttributesFitting(layoutAttributes)
        attributes.size = CGSize(
            width: layoutAttributes.size.width, height: UKSelfSizing.fittingHeight(of: contentView, width: layoutAttributes.size.width)
        )
        return attributes
    }
}

/// Measurement helpers for self-sizing views.
enum UKSelfSizing {
    /// The height `view` needs at `width`.
    ///
    /// - Parameters:
    ///   - view: The view (its subviews' constraints must be complete).
    ///   - width: The proposed width.
    /// - Returns: The fitted height, rounded up to a whole point.
    @MainActor
    static func fittingHeight(of view: UIView, width: CGFloat) -> CGFloat {
        ceil(view.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        ).height)
    }
}
#endif
