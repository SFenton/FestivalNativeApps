# Song header

> **What:** the song identity block at the top of song pages (album art beside a one-line marquee title, artist · year · length, optional third line) and its compact pinned form in the navigation bar. **Read when:** adding or changing a song page header, a song title or artist at the top of a page or in its bar, or the shared marquee text.

Status: **current**, 2026-10-05. Provenance: #315.

## Intent

A song page names its song once, the same way everywhere, at full width, like the web's `SongInfoHeader`. The title and artist each sit on one line that fills the width beside the album art, so a title never wraps early into a narrow column or stops early with empty space to its right. A line that does not fit scrolls (marquee) inside its column; a line that fits stays still. When the header scrolls under the bar, a compact copy (small art and the title) takes the bar's title slot.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/songs/headers/SongInfoHeader.tsx` (`SongInfoHeader`) | One header for Song Details, Song Leaderboard, Band Song Leaderboard and Player History: art, then a text column whose title (`h1`), artist · year · duration line and optional `subtitle2` are each a `MarqueeText`; optional `onTitleClick`; a `collapsed` form for the pinned bar. |
| `FortniteFestivalWeb/src/components/common/MarqueeText.tsx` (`MarqueeText`) | One line; scrolls only when the text is wider than its box (8 s cycle, 28 px gap); static when it fits; ellipsis under `prefers-reduced-motion`. |
| `FortniteFestivalWeb/src/hooks/ui/useMarqueeSync.ts` (`useMarqueeSync`) | The header's overflowing lines scroll the same distance, in lockstep. |

## Rules

1. **R1. One shared header.** Every song page (Song Details, Song Leaderboard, Band Song Leaderboard, Player History) draws its song identity, its leaderboard header row and its bar title through the canonical components below (title, artist · year · length, optional third line such as "Duos · N entries"), never a page-local title `Text`, link, `TextBlock` or copied header row. A tappable title opens the song (web `onTitleClick`), and the whole header is one control with the heading role.
2. **R2. Fill the width, one line, marquee only on overflow.** The header's text column takes all the width beside the art; the title and artist never wrap at standard text sizes and never tail-truncate while motion is allowed. A line wider than its column scrolls with the platform's shared marquee (Apple `MarqueeText`, Android `FestivalMarqueeText`, Windows `MarqueeText`); lines that fit stay still. The header's overflowing lines scroll in lockstep (web `useMarqueeSync`). (#315: the Apple Song Leaderboard wrapped "Through the Fire / and Flames" beside empty space.)
3. **R3. Motion and large text follow the shared marquee.** With Reduce Motion / Remove animations the line tail-truncates without animation (HIG Accessibility: "When Reduce Motion is on, reduce automatic and repetitive animation"). At accessibility text sizes the in-page header wraps onto as many lines as it needs so the whole name is readable (HIG Typography, *should*: "Minimize text truncation at large font sizes in scrollable regions"). Assistive technology reads the full title once.
4. **R4. One pinned bar title, one line.** When the header scrolls away, the compact bar copy (small art where the platform shows it, the title on one marqueeing line, optional caption such as the instrument or band size) takes the bar's title slot. It stays on one line at every text size (Apple `marqueeWrapsAtAccessibilitySizes = false`), uses the bar's available width rather than a fixed cap, is built only while the in-page header is scrolled away (so it is never read twice) and comes from the canonical component, like the web's collapsed `SongInfoHeader`. Bar actions that no longer fit still move to the overflow menu.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Marquee text | `apple/Sources/FestivalUI/Design/MarqueeText.swift` `MarqueeText` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/MarqueeText.kt` `FestivalMarqueeText` | `windows/Festival.App/Controls/MarqueeText.cs` `MarqueeText` |
| In-page title/artist column | `apple/Sources/FestivalUI/Common/SongHeaderText.swift` `SongHeaderText` (`MarqueeText` lines in a `maxWidth: .infinity` column with `marqueeSync`) | `android/app/src/main/java/com/festivalscoretracker/android/ui/songdetail/SongDetailScreen.kt` `SongHeader` (`FestivalMarqueeText` title and subtitle) | Page XAML (see Known debt) |
| Leaderboard header row (art + column, one heading, scrolled-away report) | `apple/Sources/FestivalUI/Common/SongHeaderText.swift` `SongHeaderRow` (80 pt art) | `SongHeader` (`artSize = 64.dp`) | — |
| Pinned bar title | `apple/Sources/FestivalUI/Common/SongHeaderText.swift` `SongBarTitle`, and on the boards `SongBarTitleToolbarItem` (principal item, empty unspoken placeholder until the header scrolls away) | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/FestivalScreen.kt` `marqueeTitle` | `FSTMarqueeTitleStyle` on `SongDetailPage` |

**Apple consumers:** Song Details hero and pinned title (`SongDetailScreen`, its own 96 pt top-aligned row around `SongHeaderText`); Song Leaderboard (`SoloLeaderboardScreen`, caption = instrument) and Band Song Leaderboard (`SongBandLeaderboardScreen`, caption = band size; detail line `SongBandLeaderboardResponse.headerDetail`, web `songBandLeaderboard.subtitle`) through `SongHeaderRow` + `SongBarTitleToolbarItem`; Player History (`PlayerHistoryScreen`) opens Song Details on its Score History section, so it shows the Song Details hero, and in a split Song Details' trailing pane the song page is beside it. All on iPhone, iPad, iPhone Duo and Mac.

**Android consumers** of `SongHeader`: Song Detail, Song Leaderboard and Song Band Leaderboard (`artSize = 64.dp`, `subtitle2` = "Duos · N entries", `onTitleClick` → Song Detail). Player History keeps its compact instrument-icon row and puts the title in `FestivalMarqueeText` (no art; see Known debt). `FestivalScreen(marqueeTitle = true)` is used by Song Detail and Song Leaderboard; other pages keep the Material 3 truncating title.

**Agent decision (2026-10-05, #315; owner may override with `/choose`):** a song page with a song header uses the song's dimmed cover as its backdrop (`festivalBackground(.song(albumArt))`), so the Apple Band Song Leaderboard moved off the carousel backdrop when it gained the header. Precedent: the web page's `PageBackground src={song.albumArt}`, Android and Windows Band Song Leaderboard (both switch to the song cover), Apple Song Leaderboard.

**Agent decision (#315, 2026-10-05; the owner may override):** on Android the song pages' top-app-bar title scrolls instead of ending in "…". Options: (A) keep Material 3's default one-line truncation; (B) wrap in a taller bar; (C) one-line marquee. Chose C. Web (collapsed `SongInfoHeader`), Apple (pinned `MarqueeText`) and Windows (`FSTMarqueeTitleStyle`) already scroll this title. Material 3 keeps a small top app bar to one Title-style line ("Top app bar title | Title Large"; small bar "Start-aligned, 64dp"), which C keeps and B breaks. Remove animations still truncates (R3).

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Windows `LeaderboardsSongPage`, `SongDetailPage`, `BandsSongLeaderboardPage` and `PlayerHistoryPage` header titles are wrapping or non-marquee `TextBlock`s | R1, R2 | Windows session for #315 |
| Android Player History shows instrument icon + title without the art and artist line of web `SongInfoHeader` | R1 | Follow-up; the title itself complies with R2–R3 |

## Guards (`tools/pattern_guard.py`)

- `song-header/apple-wrapping-title`: a page-local `Text(song.title)` in an Apple feature view. Song list rows legitimately use plain one-line text (`SongRowView` is allowed), so the guard can't cover every platform; review other pages against R1–R4.

Regression journeys: Apple `SongHeaderTextTests` lay out the shared column and leaderboard row and assert R2 (a long title stays on one line and the column fills the width beside the art), R3 (in-page wrap at accessibility sizes; one heading that names the song once) and R4's trigger (the row reports when it scrolls away). Every Android `FestivalMarqueeText` publishes what it draws as the semantics property `FestivalMarquee.ModeKey` (`Static`, `Scrolling`, `Truncated`, `Wrapped`; not read by TalkBack). Android `ui/songdetail/SongHeaderTitleUiTest` launches the whole shell on Song Detail, Song Leaderboard, Song Band Leaderboard and Player History with a synthetic overflowing title and asserts R2 (one `Scrolling` line whose box ends at the header's edge), R3 (Reduce Motion `Truncated` with an ellipsis; 200% text `Wrapped` in-page; one heading stop that reads the title once), R4 (after scrolling, the bar title is one `Scrolling` line up to the first action, also at 200%) and that short titles stay `Static`. A plain `Text` title has no mode and fails them. Add a page here when it gains a song header.
