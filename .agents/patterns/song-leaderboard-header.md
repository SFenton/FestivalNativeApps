# Song leaderboard header

> **What:** the song header, bar title and backdrop of a song-scoped leaderboard (one instrument or one band size of one song). **Read when:** adding or changing a song leaderboard, or any page that opens a board for one song.

Status: **current**, 2026-10-05. Provenance: operator batch 7.2, #93, #293, #317.

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
3. **R3. Bar title after scroll.** The header scrolls with the rows; the bar's title slot stays empty until the header passes under the bar, then shows small art, the song title (single-line marquee) and the board name. HIG Toolbars (should): "Give each window a useful title… you can omit it when content supplies context."
4. **R4. Song backdrop.** A song-scoped page uses the song's static, dimmed album art (Apple `festivalBackground(.song)`), never the animated carousel, which belongs to pages not tied to one song (Bands, Band Rankings, Band Detail).
5. **R5. One header per platform.** Song leaderboards get the header and bar title from the canonical component below, not a feature-local copy; changing the board (band size, instrument) keeps the header and backdrop and only updates the board line.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Header, board line, bar title | `apple/Sources/FestivalUI/Features/SongLeaderboard/SongLeaderboardHeader.swift` `SongLeaderboardHeader`, `SongLeaderboardBoardLine`, `SongLeaderboardPinnedTitle` (`SongDetailPinnedTitlePolicy` decides when the header is under the bar) | `android/app/src/main/java/com/festivalscoretracker/android/ui/songdetail/SongLeaderboardScreen.kt` `SongLeaderboardScreen` (Song Detail's `SongHeader`) | `windows/Festival.App/Pages/LeaderboardsSongPage.xaml.cs` `LeaderboardsSongPage` |

Apple consumers: `SoloLeaderboardScreen` (instrument + icon) and `SongBandLeaderboardScreen` (band size), on iPhone, iPad, iPhone Duo and Mac. Identifiers: `<page>.header` and `<page>.pinned-title` with `fst.song-leaderboard` / `fst.song-band-leaderboard`.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android `ui/bands/SongBandLeaderboardScreen.kt` titles the bar "${type.label} Leaderboard" (its header wraps the shared `SongHeader` since #315) | R1, R3 | Android check filed from #317 |
| Windows `Pages/BandsSongLeaderboardPage.xaml` heads the page "{Band} Leaderboard" with the song as a secondary link | R1 | Windows check filed from #317 |

The song title inside the header and the bar title follows [song-header](song-header.md) (full-width one-line marquee, R2–R4).

## Guards (`tools/pattern_guard.py`)

- `song-leaderboard-header/apple-song-backdrop`
- `song-leaderboard-header/apple-principal-title`
