# Song leaderboard header

> **What:** the song header, bar title and backdrop of a song-scoped leaderboard (one instrument or one band size of one song). **Read when:** adding or changing a song leaderboard, or any page that opens a board for one song.

Status: **current**, 2026-10-05. Provenance: operator batch 7.2, #93, #293, #317.

## Intent

Every leaderboard for one song looks like the same page: the song is named first, by the song header in the page, and the board (an instrument or a band size) is one line under the artist. The bar adds no second title while that header is on screen, and the song's static, dimmed album art is behind the page. Opening Duos from Song Detail should feel the same as opening Lead.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/songs/headers/SongInfoHeader.tsx` (`SongInfoHeader`) | One header for Song Detail, the solo `LeaderboardPage`, `PlayerHistoryPage` and `SongBandLeaderboardPage`: art, title, artist, and `subtitle2` for the board line. Art is `AlbumArtSize.collapsed` 80 px (120 expanded, Song Detail only). |
| `FortniteFestivalWeb/src/pages/leaderboard/band/SongBandLeaderboardPage.tsx` (`SongBandLeaderboardPage`) | Band board: `SongInfoHeader collapsed`, `subtitle2` = the band label, or `songBandLeaderboard.subtitle` ("{type} • {count} entries") when `showLeaderboardEntryTotals`; `background={<PageBackground src={song.albumArt} />}`. |
| `FortniteFestivalWeb/src/pages/leaderboard/global/LeaderboardPage.tsx` (`LeaderboardPage`) | Solo board: the same header with the instrument icon + name; the entry count only when `showLeaderboardEntryTotals && totalEntries > 0`. |

## Rules

1. **R1. Song first.** The page's header is the song (art, title, artist), with the board's name on the line below: the instrument (with its icon) or the band size ("Duos", "Trios", "Quads"; no icon, like the web). Never a "<Board> Scores" or "<Board> Leaderboard" page title. The song title is the page's level-1 accessibility heading.
2. **R2. Entry totals only when asked.** The board line adds the entry count (" · N entries", or Windows' own "N <Board> entries" line) only when the response's `showLeaderboardEntryTotals` is true and the total is above zero; an empty board never says "0 … entries".
3. **R3. Bar title after scroll.** The header scrolls with the rows; the bar's title slot stays empty until the header passes under the bar, then shows small art, the song title (single-line marquee) and the board name. HIG Toolbars (should): "Give each window a useful title… you can omit it when content supplies context." Platforms without a per-page bar title slot (Windows) skip the bar title (Variants).
4. **R4. Song backdrop.** A song-scoped page uses the song's static, dimmed album art (Apple `festivalBackground(.song)`, Android's shared background focused on the song art, Windows `IBackdropPage.BackdropArt`), never the animated carousel, which belongs to pages not tied to one song (Bands, Band Rankings, Band Detail).
5. **R5. One header per platform.** Song leaderboards get the header (and bar title, where there is one) from the canonical component below, not a feature-local copy; changing the board (band size, instrument) keeps the header and backdrop and only updates the board line.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Header, board line, bar title | `apple/Sources/FestivalUI/Features/SongLeaderboard/SoloLeaderboardScreen.swift` `SoloLeaderboardScreen` (`scoreHeader`, `SongDetailPinnedTitlePolicy` decides when the header is under the bar) | `android/app/src/main/java/com/festivalscoretracker/android/ui/songdetail/SongLeaderboardScreen.kt` `SongLeaderboardScreen` (Song Detail's `SongHeader`) | `windows/Festival.App/Controls/SongLeaderboardHeader.xaml.cs` `SongLeaderboardHeader` |
| Song backdrop | `festivalBackground(.song(song.albumArt))` | the song's art pushed to the shared background (`background.pushFocus(song.albumArt)` on the band board) | the page implements `IBackdropPage` (`BackdropArt` = the song cover) and calls `MainWindow.RefreshBackdrop()` once the song resolves |

Consumers: Apple `SoloLeaderboardScreen` and `SongBandLeaderboardScreen`; Android `SongLeaderboardScreen` and `ui/bands/SongBandLeaderboardScreen.kt`; Windows `Pages/LeaderboardsSongPage` and `Pages/BandsSongLeaderboardPage`.

### Windows (`Controls/SongLeaderboardHeader`)

- Layout: static cover tile, 80 epx (web `AlbumArtSize.collapsed`), 56 epx below a 760 epx window (`AdaptiveTrigger`); 8 epx corners, 16 epx gap to the text. Text column: title (`FSTPageTitleStyle`, heading level 1), artist (`FSTMarqueeSecondaryStyle`), both full-width one-line `MarqueeText` per [song-header](song-header.md) R2/R3; then the board line (20 epx `InstrumentIcon` + instrument name, or the band size with no icon); then the optional total line (`FSTSecondaryTextStyle`, wraps).
- States: song resolved (all lines); song missing or failed to resolve (title and art collapse, the board line stays so the page still names the board); total hidden unless R2 holds; cover not loaded under Save Data or `--no-art` (the tile keeps its muted surface; the shell backdrop follows the same switch). The decorative cover and icon are `AccessibilityView="Raw"`; the control itself is not a tab stop.
- Identifiers are set per page: `TitleAutomationId`, `ArtistAutomationId`, `BoardAutomationId`, `TotalAutomationId` → `fst.song-leaderboard.title|artist|instrument|total` and `fst.song-band-leaderboard.title|artist|subtitle|total`.
- Journeys: `song-board-header` (`tools/windows/journeys/boards-ui.json`), `song-band-leaderboard-switch-and-detail`, `song-band-leaderboard-entry-totals`, `song-band-leaderboard-error` (`tools/windows/journeys/bands.json`; `--song-band-totals` fixture switch) assert the song-first order, the board line after every size switch and total visibility.

## Variants

- **Windows has no bar title (R3).** The WinUI title bar carries the back button and app identity, not a per-page title; the solo header scrolls away under it and the page-change announcement names the board (`<Song>, <Board> leaderboard`).
- **Windows band board: fixed header.** Agent decision (#317, 2026-10-05; the owner may override): the band board's header stays fixed above the size `SelectorBar` instead of scrolling away with the rows like the solo board. The band rows' load gate hides the `ListView` (and any `ListView.Header`) while a size swap loads, which would blank the header, and the row UIA from #196 relies on that `ListView`. The web also keeps `SongInfoHeader` `collapsed` above the band rows. The song-title link to Song Detail was dropped to match the solo board (the web header has no title link); Back returns to Song Detail.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple `Features/SongLeaderboard/SongBandLeaderboardScreen.swift` titles the bar "<Band> Scores", has no song header and uses `festivalBackground(.carousel)` | R1, R3, R4 | Apple branch for #317 (`report/317`) |
| Android `ui/bands/SongBandLeaderboardScreen.kt` titles the bar "${type.label} Leaderboard" (its header wraps the shared `SongHeader` since #315) | R1, R3 | Android branch for #317 (`report/317-android`) |

The song title inside the header and the bar title follows [song-header](song-header.md) (full-width one-line marquee, R2–R4).

## Guards (`tools/pattern_guard.py`)

- `song-leaderboard-header/windows-board-title` — Windows song leaderboard view models never build a "{Board} Leaderboard" / "{Board} Scores" title.
- `song-leaderboard-header/windows-page-title` — Windows song pages take their title from `SongLeaderboardHeader`, not a page-local `FSTPageTitleStyle` heading (Songs and Song Detail are allowed).
