# Song leaderboard header

> **What:** the song header, bar title and backdrop of a song-scoped leaderboard (one instrument or one band size of one song). **Read when:** adding or changing a song leaderboard, or any page that opens a board for one song.

Status: **current**, 2026-10-06. Provenance: operator batch 7.2, #93, #293, #315, #316, #317.

## Intent

Every leaderboard for one song looks like the same page: the song is named first, by the song header in the page, and the board (an instrument or a band size) is one line under the artist. The bar adds no second title while that header is on screen, and the song's static, dimmed album art is behind the page. Opening Duos from Song Detail should feel the same as opening Lead.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/songs/headers/SongInfoHeader.tsx` (`SongInfoHeader`) | One header for Song Detail, the solo `LeaderboardPage`, `PlayerHistoryPage` and `SongBandLeaderboardPage`: art, title, artist, and `subtitle2` for the board line. Art is `AlbumArtSize.collapsed` 80 px (120 expanded, Song Detail only). With `onTitleClick` the whole title area (art, title, artist, `subtitle2`) is one pressable `role="link"`. |
| `FortniteFestivalWeb/src/pages/leaderboard/band/SongBandLeaderboardPage.tsx` (`SongBandLeaderboardPage`) | Band board: `subtitle2` = the band label, or `songBandLeaderboard.subtitle` ("{type} • {count} entries") when `showLeaderboardEntryTotals`; `onTitleClick={goToSongDetail}`; `background={<PageBackground src={song.albumArt} />}`. |
| `FortniteFestivalWeb/src/pages/leaderboard/global/LeaderboardPage.tsx` (`LeaderboardPage`) | Solo board: the same header with `onTitleClick={goToSongDetail}`; the entry count only when `showLeaderboardEntryTotals && totalEntries > 0`. |

## Rules

1. **R1. Song first.** The page's header is the song (art, title, artist), with the board's name on the line below: the instrument (with its icon) or the band size ("Duos", "Trios", "Quads"; no icon, like the web). Never a "<Board> Scores" or "<Board> Leaderboard" page title. The song title is the page's level-1 accessibility heading, and invoking the header opens Song Detail (web `onTitleClick`; [song-header](song-header.md) R1).
2. **R2. Entry totals only when asked.** The board line adds " · N entries" (Windows: its own "N <Board> entries" line) only when the response's `showLeaderboardEntryTotals` is true and the total is above zero; an empty board never says "0 … entries".
3. **R3. Bar title after scroll.** The header scrolls with the rows; the bar's title slot stays empty until the header passes under the bar, then shows small art, the song title (single-line marquee) and the board name. HIG Toolbars (should): "Give each window a useful title… you can omit it when content supplies context." A page change keeps that state: under the bar, the new page starts at its first row with the header still under it and the bar title kept, never flashing the header back while the rows reload; otherwise the page returns to the top. A new board (band size, player) starts at the top with its header in view. Web: `goToPage('paginate')` scrolls to the top but pins the collapsed header (`headerPinned`) until the reader scrolls; natively the header is in the scroll content, so keeping it collapsed means keeping it scrolled away (agent decision, #316 review; the owner may override). Apple: `LeaderboardPaging.reloadScroll(headerUnderBar:boardChanged:)`. Platforms without a per-page bar title slot (Windows) skip the bar title (Variants).
4. **R4. Song backdrop.** A song-scoped page uses the song's static, dimmed album art (Apple `festivalBackground(.song)`, Android's shared background focused on the song art, Windows `IBackdropPage.BackdropArt`), never the animated carousel, which belongs to pages not tied to one song (Bands, Band Rankings, Band Detail).
5. **R5. One header per platform, kept through reloads.** Song leaderboards get the header and bar title from the canonical component below, not a feature-local copy. The header sits above the reload gate (web: `SongInfoHeader` in `Page`'s `before` slot, outside its `LoadGate`), so changing the board (band size, instrument), page or selected player keeps the header and backdrop while only the rows reload. The board line names the chosen board at once and adds its total only after that board's response arrives; it never shows another board's total.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Header, board line, bar title | `apple/Sources/FestivalUI/Common/SongHeaderText.swift` `SongHeaderRow`, `SongBarTitleToolbarItem` and `songHeaderScrollAway` ([song-header](song-header.md)), with `apple/Sources/FestivalUI/Features/SongLeaderboard/SongLeaderboardHeader.swift` `SongLeaderboardBoardLine` | `android/app/src/main/java/com/festivalscoretracker/android/ui/songdetail/SongLeaderboardScreen.kt` `SongLeaderboardScreen` (Song Detail's `SongHeader`) | `windows/Festival.App/Controls/SongLeaderboardHeader.xaml.cs` `SongLeaderboardHeader` (no bar title; Variants) |
| Song backdrop | `festivalBackground(.song(song.albumArt))` | the song's art pushed to the shared background (`background.pushFocus(song.albumArt)` on the band board) | the page implements `IBackdropPage` (`BackdropArt` = the song cover) and calls `MainWindow.RefreshBackdrop()` once the song resolves |

Apple consumers: `SoloLeaderboardScreen` (instrument + icon) and `SongBandLeaderboardScreen` (band size), on iPhone, iPad, iPhone Duo and Mac. `SongBandLeaderboardContent` puts the header first in its `ScrollView` with the `FestivalReloadGate` below it, sized to the rest of the visible page so the spinner centres under the header (#317 review). `SoloLeaderboardScreen` keeps the header as the first row of the rows' `List` (it scrolls with them) and holds it through page changes with `FestivalReloadGate`'s retained-frame form: the header and banner render from the last loaded page while only the rows swap (#316; see [load-transition](load-transition.md) R4). While a page loads or after it failed, one result row as tall as the visible list stands in for the rows (empty under the spinner, or the `ServiceStatusView` with Retry), so the header stays and the List cannot clamp a collapsed header back into view. `SongBandLeaderboardContent` grows its gate to the whole visible page for the same case (`rowsAtTop`) until the new rows are revealed. Both use `LeaderboardPaging.reloadScroll` (R3). Both boards decide that the header is under the bar from their scroll view's offset alone (`songHeaderScrollAway(headerBottom:)`: offset ≥ space above the header + its height), never from the header's own geometry: a fling recycles a `List` header row before its geometry reports the hidden position, and a `List`'s `.scrollView` space starts at its frame under the bar, so the Solo bar stayed empty with the header gone (#315, #316 reviews). The bar title is iOS/iPadOS only and uses the bar's full title width ([song-header](song-header.md) R4); the Mac keeps the window title. Identifiers: `<page>.header` and `<page>.pinned-title` with `fst.song-leaderboard` / `fst.song-band-leaderboard`.

Windows consumers: `Pages/LeaderboardsSongPage` (instrument + icon) and `Pages/BandsSongLeaderboardPage` (band size).

### Windows (`Controls/SongLeaderboardHeader`)

- Layout: static cover tile, 80 epx (web `AlbumArtSize.collapsed`), 56 epx below a 760 epx window (`AdaptiveTrigger`); 8 epx corners, 16 epx gap to the text. Text column: title (`FSTPageTitleStyle`, heading level 1), artist (`FSTMarqueeSecondaryStyle`), both full-width one-line `MarqueeText` per [song-header](song-header.md) R2/R3; then the board line (20 epx `InstrumentIcon` + instrument name, or the band size with no icon); then the optional total line (`FSTSecondaryTextStyle`, wraps).
- Title invocation (web `onTitleClick`, the whole title area pressable): art and text sit in one flat `Button` (transparent, no border, 8 epx corners; Fluent's subtle hover/press fill) that raises `TitleInvoked`; both pages open Song Detail (`AppRoute.SongDetail(songId)`). The button is named by the song title with help text "Opens Song Details"; the title inside stays the level-1 heading. Without a resolved song it is not hit-testable, not a tab stop and `AccessibilityView.Raw`, so the board line still reads but nothing opens.
- States: song resolved (all lines, invokable); song missing or failed to resolve (title and art collapse, the board line stays so the page still names the board); total hidden unless R2 holds, and cleared the moment the board changes (band size), so it never shows the previous board's total while the new one loads or after it fails (R5); cover not loaded under Save Data or `--no-art` (the tile keeps its muted surface; the shell backdrop follows the same switch). The decorative cover and icon are `AccessibilityView="Raw"`; the `UserControl` itself is not a tab stop.
- Identifiers are set per page: `TitleAutomationId`, `ArtistAutomationId`, `BoardAutomationId`, `TotalAutomationId`, `SongAutomationId` → `fst.song-leaderboard.title|artist|instrument|total|song` and `fst.song-band-leaderboard.title|artist|subtitle|total|song`.
- Tests: `SongBandLeaderboardViewModelTests.SizeSwitchDropsTheOldTotalUntilTheNewSizeCommits` (a held Quads read after Duos totals: empty total until Quads commits, and after a failed Quads read). Journeys: `song-board-header` (`tools/windows/journeys/boards-ui.json`; header order, then invoking the header opens Song Detail), `song-band-leaderboard-switch-and-detail` (board line after every size switch, then the header opens Song Detail), `song-band-leaderboard-entry-totals`, `song-band-leaderboard-slow-switch-total` (`--song-band-slow Band_Quad` holds Quads 5 s: the Duos total is gone at once and stays gone through the load gate) and `song-band-leaderboard-error` (`tools/windows/journeys/bands.json`; `--song-band-totals` fixture switch).

## Variants

- **Windows has no bar title (R3).** The WinUI title bar carries the back button and app identity, not a per-page title; the solo header scrolls away under it and the page-change announcement names the board (`<Song>, <Board> leaderboard`).
- **Windows band board: fixed header.** Agent decision (#317, 2026-10-05; the owner may override): the band board's header stays fixed above the size `SelectorBar` instead of scrolling away with the rows like the solo board. The band rows' load gate hides the `ListView` (and any `ListView.Header`) while a size swap loads, which would blank the header, and the row UIA from #196 relies on that `ListView`. The web also keeps `SongInfoHeader` `collapsed` above the band rows, outside its `LoadGate` (R5).
- **Windows title invocation.** Agent decision (#317 review, 2026-10-06; the owner may override): the whole header is the Song Detail link, as the web's title area is, instead of the band board's former separate `HyperlinkButton` under a "{Band} Leaderboard" heading. A separate link would repeat the song title (R1, [song-header](song-header.md) R1: "the whole header is one control"); a `HyperlinkButton` would recolour the inherited board line with the accent brush. A flat `Button` keeps the text colours and gives Fluent's hover/press fill and focus rectangle.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android `ui/bands/SongBandLeaderboardScreen.kt` titles the bar "${type.label} Leaderboard" (its header wraps the shared `SongHeader` since #315) | R1, R3 | Android check filed from #317 |

The song title inside the header and the bar title follows [song-header](song-header.md) (full-width one-line marquee, R2–R4).

## Guards (`tools/pattern_guard.py`)

- `song-leaderboard-header/apple-song-backdrop`
- `song-leaderboard-header/apple-principal-title`
- `song-leaderboard-header/windows-board-title` — Windows song leaderboard view models never build a "{Board} Leaderboard" / "{Board} Scores" title.
- `song-leaderboard-header/windows-page-title` — Windows song pages take their title from `SongLeaderboardHeader`, not a page-local `FSTPageTitleStyle` heading (Songs and Song Detail are allowed).
