#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Song header seam

/// The song header of a song board and its pinned bar title, built from the shared
/// ``UKSongHeaderRowView`` and ``UKSongBarTitleView`` (Common). Kept as a seam so the
/// boards' pages stay free of the construction details.
@MainActor
enum UKSongBoardSeam {
    /// Builds the in-page header: art beside the title, artist and a board line.
    ///
    /// Parameters: song, session, the board line's instrument (nil for a band size), the
    /// board line's text, the accessibility identifier.
    static var makeHeader: (Song, FestivalSession, Instrument?, String, String) -> UIView = { song, session, instrument, text, identifier in
        let line = UKSongBoardLine(instrument: instrument, text: text)
        let header = UKSongHeaderRowView(song: song, session: session, details: [line])
        header.accessibilityIdentifier = identifier
        return header
    }

    /// Builds the compact bar title: 28 pt art, the title and an optional caption.
    ///
    /// Parameters: song, session, caption, the caption's instrument, the identifier.
    static var makePinnedTitle: (Song, FestivalSession, String?, Instrument?, String) -> UIView = { song, session, caption, instrument, identifier in
        UKSongBarTitleView(song: song, session: session, caption: caption, captionInstrument: instrument, identifier: identifier)
    }
}

#endif
