#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Song header seam

/// The song header of a song board (``SongHeaderRow``) and its pinned bar title
/// (``SongBarTitle``) behind a seam.
///
/// The Song Detail lane ports the shared `SongHeaderRow` / `SongBarTitle`; until that lands
/// the song boards draw these lane-local versions (the same art, marquees and spoken
/// text). When the shared ones exist, assign `makeHeader` and `makePinnedTitle` once at
/// launch (or replace the default bodies) and delete the lane-local views: no second shared
/// copy is meant to live here.
@MainActor
enum UKSongBoardSeam {
    /// Builds the in-page header: art beside the title, artist and a board line.
    ///
    /// Parameters: song, session, the board line's instrument (nil for a band size), the
    /// board line's text, the accessibility identifier.
    static var makeHeader: (Song, FestivalSession, Instrument?, String, String) -> UIView = { song, session, instrument, text, identifier in
        UKLocalSongHeaderView(song: song, session: session, instrument: instrument, text: text, identifier: identifier)
    }

    /// Builds the compact bar title: 28 pt art, the title and an optional caption.
    ///
    /// Parameters: song, session, caption, the caption's instrument, the identifier.
    static var makePinnedTitle: (Song, FestivalSession, String?, Instrument?, String) -> UIView = { song, session, caption, instrument, identifier in
        UKLocalSongBarTitleView(song: song, session: session, caption: caption, captionInstrument: instrument, identifier: identifier)
    }
}

/// Lane-local stand-in for ``SongHeaderRow``: 80 pt art beside the title and artist
/// marquees and the board line; one heading element for VoiceOver.
final class UKLocalSongHeaderView: UIView {
    init(song: Song, session: FestivalSession, instrument: Instrument?, text: String, identifier: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let art = UKArtworkTileView(size: 80)
        art.configure(raw: song.albumArt, session: session)
        art.isAccessibilityElement = false
        let line = UKSongBoardLine(instrument: instrument, text: text)
        let details = UKSongHeaderTextView(
            title: song.title, artist: song.artist, titleFont: UKFont.font(.title3, weight: .bold), spacing: 4, details: [line]
        )
        line.marquee.syncGroup = nil
        let stack = UIStackView(arrangedSubviews: [art, details])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .header
        accessibilityLabel = [song.title, song.artist, text].joined(separator: ", ")
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Lane-local stand-in for ``SongBarTitle``.
final class UKLocalSongBarTitleView: UIView {
    init(song: Song, session: FestivalSession, caption: String?, captionInstrument: Instrument?, identifier: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let art = UKArtworkTileView(size: 28)
        art.configure(raw: song.albumArt, session: session)
        let title = UKMarqueeLabel(song.title, font: UKFont.font(.headline))
        title.wrapsAtAccessibilitySizes = false
        let column = UIStackView(arrangedSubviews: [title])
        column.axis = .vertical
        if let caption {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 4
            row.alignment = .center
            if let captionInstrument {
                row.addArrangedSubview(UKInstrumentIconView(captionInstrument, size: UKFont.scaled(14, relativeTo: .caption1), hidesFromAccessibility: true))
            }
            row.addArrangedSubview(UKLabel(caption, style: .caption1, lines: 1))
            column.addArrangedSubview(row)
        }
        let stack = UIStackView(arrangedSubviews: [art, column])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(lessThanOrEqualToConstant: 260),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .header
        accessibilityLabel = [song.title, caption].compactMap { $0 }.joined(separator: ", ")
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
