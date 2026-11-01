#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Song header row

/// The in-page song header of the song leaderboards (``SongHeaderRow``): an 80 pt cover, then
/// the title (`title3` bold) and artist marquees scrolling in step, with detail lines below.
/// One combined heading element for VoiceOver (title, artist, then the details).
///
/// Song Detail's own hero is larger (96 pt cover, `title` bold) and is built by that page
/// from ``UKSongHeaderTextView``; this row is shared with Song Leaderboard.
final class UKSongHeaderRowView: UIView {
    /// The text column, whose ``UKSongHeaderTextView/titleView`` bottom edge drives the
    /// scroll-away bar title.
    let text: UKSongHeaderTextView

    /// Creates the header.
    ///
    /// - Parameters:
    ///   - song: The song.
    ///   - session: Owner of the artwork caches.
    ///   - details: Lines under the artist (instrument and entry total); each one's
    ///     accessibility label joins the combined label.
    init(song: Song, session: FestivalSession, details: [UIView] = []) {
        text = UKSongHeaderTextView(
            title: song.title, artist: song.artist, titleFont: UKFont.font(.title3, weight: .bold), spacing: 4, details: details
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let art = UKArtworkTileView(size: 80)
        art.configure(raw: song.albumArt, session: session)
        let row = UIStackView(arrangedSubviews: [art, text])
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 6), row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .header
        accessibilityLabel = ([song.title, song.artist] + details.compactMap { Self.spokenText(of: $0) }).joined(separator: ", ")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The spoken text of a detail line: its own label, else its labels joined.
    private static func spokenText(of view: UIView) -> String? {
        if let label = view.accessibilityLabel, !label.isEmpty { return label }
        if let label = view as? UILabel { return label.text }
        let parts = view.subviews.compactMap { spokenText(of: $0) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// MARK: - Bar title

/// The song identity pinned in the navigation bar once the page's title scrolls away
/// (``SongBarTitle``): a 28 pt cover, the title as a headline marquee (never wrapping) and
/// an optional caption with a small instrument icon. One combined heading element.
final class UKSongBarTitleView: UIView {
    /// Creates the bar title.
    ///
    /// - Parameters:
    ///   - song: The song.
    ///   - session: Owner of the artwork caches.
    ///   - caption: Optional second line (instrument name, entry total).
    ///   - captionInstrument: Icon before the caption.
    ///   - identifier: Accessibility identifier.
    init(song: Song, session: FestivalSession, caption: String? = nil, captionInstrument: Instrument? = nil, identifier: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let art = UKArtworkTileView(size: 28)
        art.configure(raw: song.albumArt, session: session)
        let title = UKMarqueeLabel(song.title, font: UKFont.font(.headline))
        title.wrapsAtAccessibilitySizes = false
        let column = UIStackView(arrangedSubviews: [title])
        column.axis = .vertical
        column.alignment = .fill
        if let caption {
            let line = UIStackView()
            line.spacing = 4
            line.alignment = .center
            if let captionInstrument {
                line.addArrangedSubview(UKInstrumentIconView(captionInstrument, size: UKFont.scaled(14, relativeTo: .caption1), hidesFromAccessibility: true))
            }
            line.addArrangedSubview(UKLabel(caption, style: .caption1, lines: 1))
            column.addArrangedSubview(line)
        }
        let row = UIStackView(arrangedSubviews: [art, column])
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(lessThanOrEqualToConstant: 260),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .header
        accessibilityLabel = [song.title, caption].compactMap { $0 }.joined(separator: ", ")
        accessibilityIdentifier = identifier
        showsLargeContentViewer = true
        largeContentTitle = song.title
        addInteraction(UILargeContentViewerInteraction())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
