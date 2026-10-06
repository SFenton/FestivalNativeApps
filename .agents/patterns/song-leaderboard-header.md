# Song leaderboard header

> **What:** the song header, bar title and backdrop of a song-scoped leaderboard (one instrument or one band size of one song). **Read when:** adding or changing a song leaderboard, or any page that opens a board for one song.

Status: **current**, 2026-10-06. Provenance: operator batch 7.2, #93, #293, #315, #316, #317.

## Intent

Every leaderboard for one song looks like the same page: the song is named first, by the song header in the page, and the board (an instrument or a band size) is one line under the artist. The bar adds no second title while that header is on screen, and the song's static, dimmed album art is behind the page. Opening Duos from Song Detail should feel the same as opening Lead.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/songs/headers/SongInfoHeader.tsx` (`SongInfoHeader`) | One header for Song Detail, the solo `LeaderboardPage`, `PlayerHistoryPage` and `SongBandLeaderboardPage`: art, title, artist, and `subtitle2` for the board line. |
| `FortniteFestivalWeb/src/pages/leaderboard/band/SongBandLeaderboardPage.tsx` (`SongBandLeaderboardPage`) | Band board: `subtitle2` = the band label, or `songBandLeaderboard.subtitle` ("{type} • {count} entries") when `showLeaderboardEntryTotals`; `background={<PageBackground src={song.albumArt} />}`. |

## Rules

1. **R1. Song first.** The page's header is the song (art, title, artist), with the board's name on the line below: the instrument (with its icon) or the band size ("Duos", "Trios", "Quads"; no icon, like the web). Never a "<Board> Scores" or "<Board> Leaderboard" page title.
2. **R2. Entry totals only when asked.** The board line adds " · N entries" only when the response's `showLeaderboardEntryTotals` is true.
3. **R3. Bar title after scroll.** The header scrolls with the rows; the bar's title slot stays empty until the header passes under the bar, then shows small art, the song title (single-line marquee) and the board name. HIG Toolbars (should): "Give each window a useful title… you can omit it when content supplies context." A page change keeps that state: under the bar, the new page starts at its first row with the header still under it and the bar title kept, never flashing the header back while the rows reload; otherwise the page returns to the top. A new board (band size, player) starts at the top with its header in view. Web: `goToPage('paginate')` scrolls to the top but pins the collapsed header (`headerPinned`) until the reader scrolls; natively the header is in the scroll content, so keeping it collapsed means keeping it scrolled away (agent decision, #316 review; the owner may override). Apple: `LeaderboardPaging.reloadScroll(headerUnderBar:boardChanged:)`.
4. **R4. Song backdrop.** A song-scoped page uses the song's static, dimmed album art (Apple `festivalBackground(.song)`), never the animated carousel, which belongs to pages not tied to one song (Bands, Band Rankings, Band Detail).
5. **R5. One header per platform, kept through reloads.** Song leaderboards get the header and bar title from the canonical component below, not a feature-local copy. The header sits above the reload gate (web: `SongInfoHeader` in `Page`'s `before` slot, outside its `LoadGate`), so changing the board (band size, instrument), page or selected player keeps the header and backdrop while only the rows reload. The board line names the chosen board at once and adds its total only after that board's response arrives; it never shows another board's total.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Header, board line, bar title | `apple/Sources/FestivalUI/Common/SongHeaderText.swift` `SongHeaderRow`, `SongBarTitleToolbarItem` and `songHeaderScrollAway` ([song-header](song-header.md)), with `apple/Sources/FestivalUI/Features/SongLeaderboard/SongLeaderboardHeader.swift` `SongLeaderboardBoardLine` | `android/app/src/main/java/com/festivalscoretracker/android/ui/songdetail/SongLeaderboardScreen.kt` `SongLeaderboardScreen` (Song Detail's `SongHeader`) with `SongBoardSwitcher` for the board line | `windows/Festival.App/Pages/LeaderboardsSongPage.xaml.cs` `LeaderboardsSongPage` |
| Song backdrop (R4) | `apple/Sources/FestivalUI/Background/FestivalBackground.swift` `festivalBackground` (`.song(albumArt)`) | `android/app/src/main/java/com/festivalscoretracker/android/ui/background/SongCoverBackdrop.kt` `SongCoverBackdrop` | `windows/Festival.App/MainWindow.xaml.cs` `IBackdropPage` (`BackdropArt`) |

Apple consumers: `SoloLeaderboardScreen` (instrument + icon) and `SongBandLeaderboardScreen` (band size), on iPhone, iPad, iPhone Duo and Mac. `SongBandLeaderboardContent` puts the header first in its `ScrollView` with the `FestivalReloadGate` below it, sized to the rest of the visible page so the spinner centres under the header (#317 review). `SoloLeaderboardScreen` keeps the header as the first row of the rows' `List` (it scrolls with them) and holds it through page changes with `FestivalReloadGate`'s retained-frame form: the header and banner render from the last loaded page while only the rows swap (#316; see [load-transition](load-transition.md) R4). While a page loads or after it failed, one result row as tall as the visible list stands in for the rows (empty under the spinner, or the `ServiceStatusView` with Retry), so the header stays and the List cannot clamp a collapsed header back into view. `SongBandLeaderboardContent` grows its gate to the whole visible page for the same case (`rowsAtTop`) until the new rows are revealed. Both use `LeaderboardPaging.reloadScroll` (R3). Both boards decide that the header is under the bar from their scroll view's offset alone (`songHeaderScrollAway(headerBottom:)`: offset ≥ space above the header + its height), never from the header's own geometry: a fling recycles a `List` header row before its geometry reports the hidden position, and a `List`'s `.scrollView` space starts at its frame under the bar, so the Solo bar stayed empty with the header gone (#315, #316 reviews). The bar title is iOS/iPadOS only and uses the bar's full title width ([song-header](song-header.md) R4); the Mac keeps the window title. Identifiers: `<page>.header` and `<page>.pinned-title` with `fst.song-leaderboard` / `fst.song-band-leaderboard`.

Android consumers (#317): `SongLeaderboardScreen` (instrument) and `ui/bands/SongBandLeaderboardScreen.kt` (band size) share Song Detail's `SongHeader` (64 dp art; the band board adds `onTitleClick` → Song Detail, like the web). The board line is `SongBoardSwitcher` on both: the solo board's instrument drop-down, and on the band board the band size as text only ("Trios ▾"), no entry count because the Android solo header shows none (R2 is met by never showing one). The top bar stays empty until `firstVisibleItemIndex > 0`, then shows the song title through `FestivalScreen(scrolled, marqueeTitle = true)` (R3; [song-header](song-header.md) R4); in a hinge split the header stays in the leading pane, so the bar stays empty. Both, and Song Detail, call `SongCoverBackdrop` (R4): NavHost disposes the previous destination and pops its cover, so a page that relied on Song Detail's push fell back to the carousel.

**Agent decision (#317, 2026-10-05; the owner may override):** on Android the band board's band size moved from M3 segmented buttons below the header into the header's board line as the solo board's drop-down (`SongBoardSwitcher`, "Switch band size"), and the `<Size> · N entries` third line went with it. The owner asked for the solo header "just saying Duos/Trios/Quads instead of {instrument name}", and the solo board switches its instrument from that spot. Material 3 skill (Menu): "In Jetpack Compose, prefer current Material3 menu APIs" (the switcher is an M3 `DropdownMenu`); (A11y) "Minimum touch target 48x48dp" (the anchor is 48 dp, `Role.DropdownList`).

Android tests: `BandsUiTest.songBandLeaderboardUsesTheSoloSongHeaderAndScrollAwayTitle` (R1, R3), `SongHeaderTitleUiTest.songBandLeaderboardTitleScrollsAcrossTheHeaderAndTheBar`, and the cover tests `BandsUiTest.songBandLeaderboardShowsTheSongsStaticCover`, `LeaderboardsUiTest.songLeaderboardShowsTheSongsStaticCover` and `SongCoverBackdropTest` (R4).

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Windows `Pages/BandsSongLeaderboardPage.xaml` heads the page "{Band} Leaderboard" with the song as a secondary link | R1 | Windows check filed from #317 |

The song title inside the header and the bar title follows [song-header](song-header.md) (full-width one-line marquee, R2–R4).

## Guards (`tools/pattern_guard.py`)

- `song-leaderboard-header/apple-song-backdrop`
- `song-leaderboard-header/apple-principal-title`
- `song-leaderboard-header/android-cover-push`: only `SongCoverBackdrop` pushes the song cover; a page calls it instead of `BackgroundController.pushFocus` (R4).
