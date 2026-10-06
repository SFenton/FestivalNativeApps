# Song header title

> **What:** the song identity block at the top of song pages (art, one-line marquee title, artist · year · length, optional third line) and the song title pinned in the top bar. **Read when:** adding or changing a song page header, a song title in a page title or bar, or the shared marquee text.

Status: **current**, 2026-10-05. Provenance: #315.

## Intent

A song page names its song the same way everywhere: the title takes the full width beside the art on one line and scrolls when it doesn't fit, like the web's `SongInfoHeader`. Song titles never wrap into a narrow column or stop early with empty space to their right.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/songs/headers/SongInfoHeader.tsx` (`SongInfoHeader`) | Art, `MarqueeText` title and artist · year · duration, optional `subtitle2` and `onTitleClick`; used by Song Detail, Leaderboard, Song Band Leaderboard and Player History, with a `collapsed` form for the pinned bar. |
| `FortniteFestivalWeb/src/components/common/MarqueeText.tsx` (`MarqueeText`) | One line; scrolls only when it overflows (8 s cycle, 28 px gap); static when it fits. |

## Rules

1. **R1. One shared header.** Song pages draw their song identity through the canonical header (title, artist · year · length, optional third line such as "Duos · N entries"), not a page-local title `Text`, link or `TextBlock`. A tappable title opens the song (web `onTitleClick`), and the whole header is one control with the heading role.
2. **R2. Full width, one line, marquee.** The title fills the width beside the art. When it is wider it scrolls through the shared marquee; when it fits it stays still. It never wraps at normal text sizes and never tail-truncates while motion is allowed.
3. **R3. Motion and large text.** With Reduce Motion / Remove animations the title tail-truncates without animation. At accessibility text sizes the in-page title wraps so the whole name is readable (HIG Typography: "Minimize text truncation at large font sizes in scrollable regions"). Assistive technology reads the full title once.
4. **R4. The pinned bar title marquees on one line.** When the header scrolls away and the song title moves into the top bar, it stays on one line at every text size and scrolls when it overflows, like the web's collapsed `SongInfoHeader` (Apple `marqueeWrapsAtAccessibilitySizes = false`). Bar actions that no longer fit still move to the overflow menu.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Marquee text | `apple/Sources/FestivalUI/Design/MarqueeText.swift` `MarqueeText` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/MarqueeText.kt` `FestivalMarqueeText` | `windows/Festival.App/Controls/MarqueeText.cs` `MarqueeText` |
| In-page song header | `apple/Sources/FestivalUI/Features/SongDetail/SongDetailScreen.swift` `SongDetailScreen` (hero) | `android/app/src/main/java/com/festivalscoretracker/android/ui/songdetail/SongDetailScreen.kt` `SongHeader` | Page XAML (see Known debt) |
| Pinned bar title | `SongDetailScreen` principal toolbar `MarqueeText` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/FestivalScreen.kt` `marqueeTitle` | `FSTMarqueeTitleStyle` on `SongDetailPage` |

Android consumers of `SongHeader`: Song Detail, Song Leaderboard and Song Band Leaderboard (`artSize = 64.dp`, `subtitle2` = "Duos · N entries", `onTitleClick` → Song Detail). Player History keeps its compact instrument-icon row and puts the title in `FestivalMarqueeText` (no art; see Known debt). `FestivalScreen(marqueeTitle = true)` is used by Song Detail and Song Leaderboard; other pages keep the Material 3 truncating title.

**Agent decision (#315, 2026-10-05; the owner may override):** on Android the song pages' top-app-bar title scrolls instead of ending in "…". Options: (A) keep Material 3's default one-line truncation; (B) wrap in a taller bar; (C) one-line marquee. Chose C. Web (collapsed `SongInfoHeader`), Apple (pinned `MarqueeText`) and Windows (`FSTMarqueeTitleStyle`) already scroll this title. Material 3 keeps a small top app bar to one Title-style line ("Top app bar title | Title Large"; small bar "Start-aligned, 64dp"), which C keeps and B breaks. Remove animations still truncates (R3).

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple `SoloLeaderboardScreen` score header draws a wrapping `Text(song.title)`; Song Leaderboard/Full Rankings bar titles are capped at 240/260 pt | R2, R4 | Apple session for #315 |
| Windows `LeaderboardsSongPage`, `SongDetailPage`, `BandsSongLeaderboardPage` and `PlayerHistoryPage` header titles are wrapping or non-marquee `TextBlock`s | R1, R2 | Windows session for #315 |
| Android Player History shows instrument icon + title without the art and artist line of web `SongInfoHeader` | R1 | Follow-up; the title itself complies with R2–R3 |

## Guards (`tools/pattern_guard.py`)

None yet: song titles in list rows legitimately use plain one-line text, so a regex can't separate header titles from row titles. Review against R1–R4.

Regression journeys instead: every `FestivalMarqueeText` publishes what it draws as the semantics property `FestivalMarquee.ModeKey` (`Static`, `Scrolling`, `Truncated`, `Wrapped`; not read by TalkBack). Android `ui/songdetail/SongHeaderTitleUiTest` launches the whole shell on Song Detail, Song Leaderboard, Song Band Leaderboard and Player History with a synthetic overflowing title and asserts R2 (one `Scrolling` line whose box ends at the header's edge), R3 (Reduce Motion `Truncated` with an ellipsis; 200% text `Wrapped` in-page; one heading stop that reads the title once), R4 (after scrolling, the bar title is one `Scrolling` line up to the first action, also at 200%) and that short titles stay `Static`. A plain `Text` title has no mode and fails them. Add a page here when it gains a song header.
