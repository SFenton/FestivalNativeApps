# Song header

> **What:** the song identity block at the top of song pages (art, one-line marquee title, artist · year · length, optional third line), the board line under it on song leaderboards (instrument or band size), the song title pinned in the top bar and the song's static album-art backdrop. **Read when:** adding or changing a song page header, a song title in a page title or bar, the shared marquee text, a song leaderboard's board switcher or a song page's background.

Status: **current**, 2026-10-05. Provenance: #315 (title), #317 (board line, bar title, backdrop).

## Intent

A song page names its song the same way everywhere: the title takes the full width beside the art on one line and scrolls when it doesn't fit, like the web's `SongInfoHeader`. Song titles never wrap into a narrow column or stop early with empty space to their right.

A page about one song also looks like it belongs to that song: it sits over that song's cover, so moving from Song Detail to a leaderboard and back never changes the context. A song leaderboard only changes the line under the header: the instrument on a solo board, the band size (Duos, Trios, Quads) on a band board (owner, #317: "the same header we have for other solo instruments, just saying Duos, Trios, Quads instead of {instrument name}").

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/songs/headers/SongInfoHeader.tsx` (`SongInfoHeader`) | Art, `MarqueeText` title and artist · year · duration, optional `subtitle2` and `onTitleClick`; used by Song Detail, Leaderboard, Song Band Leaderboard and Player History, with a `collapsed` form for the pinned bar. |
| `FortniteFestivalWeb/src/pages/leaderboard/band/SongBandLeaderboardPage.tsx` (`SongBandLeaderboardPage`) | Band board: `SongInfoHeader` with the band label as `subtitle2` (`{type} • N entries` only with entry totals on) over `PageBackground src={song.albumArt}`. |
| `FortniteFestivalWeb/src/pages/Page.tsx` (`PageBackground`) | The static, dimmed album-art background of song pages. |
| `FortniteFestivalWeb/src/components/common/MarqueeText.tsx` (`MarqueeText`) | One line; scrolls only when it overflows (8 s cycle, 28 px gap); static when it fits. |

## Rules

1. **R1. One shared header.** Song pages draw their song identity through the canonical header (title, artist · year · length, optional third line; a leaderboard's board line follows R5), not a page-local title `Text`, link or `TextBlock`. A tappable title opens the song (web `onTitleClick`), and the whole header is one control with the heading role.
2. **R2. Full width, one line, marquee.** The title fills the width beside the art. When it is wider it scrolls through the shared marquee; when it fits it stays still. It never wraps at normal text sizes and never tail-truncates while motion is allowed.
3. **R3. Motion and large text.** With Reduce Motion / Remove animations the title tail-truncates without animation. At accessibility text sizes the in-page title wraps so the whole name is readable (HIG Typography: "Minimize text truncation at large font sizes in scrollable regions"). Assistive technology reads the full title once.
4. **R4. The pinned bar title marquees on one line.** When the header scrolls away and the song title moves into the top bar, it stays on one line at every text size and scrolls when it overflows, like the web's collapsed `SongInfoHeader` (Apple `marqueeWrapsAtAccessibilitySizes = false`). Bar actions that no longer fit still move to the overflow menu.
5. **R5. The board line names the board.** Under the header a song leaderboard shows its board in one place and style: the instrument (icon and name) on a solo board, the band size name (`Duos`, `Trios`, `Quads`) on a band board. Where the platform switches boards from the header, both boards use the same control (Android `SongBoardSwitcher`). An entry count appears only where the solo board shows one. The board line follows the header in reading order.
6. **R6. The bar title follows the header.** A song leaderboard has no bar title while its header is on screen. Once the header scrolls away the bar shows the song (Apple: art, title and board label; Android and Windows: the song title, R4). A `<Board> Leaderboard`/`<Band> Scores` bar title is a violation. In a split layout where the header never scrolls away, the bar stays empty.
7. **R7. Static song backdrop.** Every song page shows that song's static, dimmed cover in the shared artwork background, never the animated carousel. Each page requests the cover itself while it is visible, because navigation disposes the previous page and its request. Reduce Motion and Low Data keep the backdrop still or plain ([artwork-background](../controls/artwork-background/spec.md)).

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Marquee text | `apple/Sources/FestivalUI/Design/MarqueeText.swift` `MarqueeText` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/MarqueeText.kt` `FestivalMarqueeText` | `windows/Festival.App/Controls/MarqueeText.cs` `MarqueeText` |
| In-page song header | `apple/Sources/FestivalUI/Features/SongDetail/SongDetailScreen.swift` `SongDetailScreen` (hero) | `android/app/src/main/java/com/festivalscoretracker/android/ui/songdetail/SongDetailScreen.kt` `SongHeader` | Page XAML (see Known debt) |
| Board line / switcher (R5) | `apple/Sources/FestivalUI/Features/SongLeaderboard/SoloLeaderboardScreen.swift` `scoreHeader` | `android/app/src/main/java/com/festivalscoretracker/android/ui/songdetail/SongLeaderboardScreen.kt` `SongBoardSwitcher` | `windows/Festival.App/Pages/LeaderboardsSongPage.xaml` `HeaderArt` |
| Static song backdrop (R7) | `apple/Sources/FestivalUI/Background/FestivalBackground.swift` `festivalBackground` (`.song(albumArt)`) | `android/app/src/main/java/com/festivalscoretracker/android/ui/background/SongCoverBackdrop.kt` `SongCoverBackdrop` | `windows/Festival.App/MainWindow.xaml.cs` `IBackdropPage` (`BackdropArt`) |
| Pinned bar title | `SongDetailScreen` principal toolbar `MarqueeText` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/FestivalScreen.kt` `marqueeTitle` | `FSTMarqueeTitleStyle` on `SongDetailPage` |

Android consumers of `SongHeader`: Song Detail, Song Leaderboard and Song Band Leaderboard (`artSize = 64.dp`; the band board adds `onTitleClick` → Song Detail, like web, and its band size in `SongBoardSwitcher` below, #317). `SongCoverBackdrop` consumers: Song Detail, Song Leaderboard and Song Band Leaderboard. Player History keeps its compact instrument-icon row and puts the title in `FestivalMarqueeText` (no art; see Known debt). `FestivalScreen(marqueeTitle = true)` is used by Song Detail, Song Leaderboard and Song Band Leaderboard; other pages keep the Material 3 truncating title.

**Agent decision (#315, 2026-10-05; the owner may override):** on Android the song pages' top-app-bar title scrolls instead of ending in "…". Options: (A) keep Material 3's default one-line truncation; (B) wrap in a taller bar; (C) one-line marquee. Chose C. Web (collapsed `SongInfoHeader`), Apple (pinned `MarqueeText`) and Windows (`FSTMarqueeTitleStyle`) already scroll this title. Material 3 keeps a small top app bar to one Title-style line ("Top app bar title | Title Large"; small bar "Start-aligned, 64dp"), which C keeps and B breaks. Remove animations still truncates (R3).

**Agent decision (#317, 2026-10-05; the owner may override):** on Android the band board's band size moved from M3 segmented buttons below the header into the header's board line as the solo board's drop-down (`SongBoardSwitcher`, text only, "Switch band size"), and the `<Size> · N entries` third line went with it (the Android solo header has no entry count). The owner asked for the solo header "just saying Duos/Trios/Quads instead of {instrument name}", and the solo board switches its instrument from that spot. Material 3 skill (Menu): "In Jetpack Compose, prefer current Material3 menu APIs" (the switcher is an M3 `DropdownMenu`); (A11y) "Minimum touch target 48x48dp" (the anchor is 48 dp, `Role.DropdownList`). The title link (#315, web `onTitleClick`) stays.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple `SoloLeaderboardScreen` score header draws a wrapping `Text(song.title)`; Song Leaderboard/Full Rankings bar titles are capped at 240/260 pt | R2, R4 | Apple session for #315 |
| Windows `LeaderboardsSongPage`, `SongDetailPage`, `BandsSongLeaderboardPage` and `PlayerHistoryPage` header titles are wrapping or non-marquee `TextBlock`s | R1, R2 | Windows session for #315 |
| Apple `SongBandLeaderboardScreen`: `<Band> Scores` bar title, no song header, carousel backdrop | R1, R5–R7 | #317 iOS lane |
| Windows `BandsSongLeaderboardPage`: `{Band} Leaderboard` heading with the song as a secondary link | R1, R5, R6 | #317 Windows lane |
| Android Player History shows instrument icon + title without the art and artist line of web `SongInfoHeader`, a "Score History" bar title and no song backdrop | R1, R7 | Follow-up; the title itself complies with R2–R3 |

## Guards (`tools/pattern_guard.py`)

- `song-header/android-cover-push`: only `SongCoverBackdrop` pushes the song cover; a page calls it instead of `BackgroundController.pushFocus` (R7).

No title guard: song titles in list rows legitimately use plain one-line text, so a regex can't separate header titles from row titles. Review against R1–R4.

Regression journeys instead: every `FestivalMarqueeText` publishes what it draws as the semantics property `FestivalMarquee.ModeKey` (`Static`, `Scrolling`, `Truncated`, `Wrapped`; not read by TalkBack). Android `ui/songdetail/SongHeaderTitleUiTest` launches the whole shell on Song Detail, Song Leaderboard, Song Band Leaderboard and Player History with a synthetic overflowing title and asserts R2 (one `Scrolling` line whose box ends at the header's edge), R3 (Reduce Motion `Truncated` with an ellipsis; 200% text `Wrapped` in-page; one heading stop that reads the title once), R4 (after scrolling, the bar title is one `Scrolling` line up to the first action, also at 200%) and that short titles stay `Static`. A plain `Text` title has no mode and fails them. Add a page here when it gains a song header. #317 adds the band board's pinned bar title to `songBandLeaderboardTitleScrollsAcrossTheHeaderAndTheBar`, `BandsUiTest.songBandLeaderboardUsesTheSoloSongHeaderAndScrollAwayTitle` (R5, R6) and the cover tests `BandsUiTest.songBandLeaderboardShowsTheSongsStaticCover`, `LeaderboardsUiTest.songLeaderboardShowsTheSongsStaticCover` and `SongCoverBackdropTest` (R7).
