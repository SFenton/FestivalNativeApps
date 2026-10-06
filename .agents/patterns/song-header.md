# Song header

> **What:** the in-page song header on song pages (album art beside the song title, artist and page details) and its compact pinned form in the navigation bar. **Read when:** changing how a song page shows the song's title, artist or art at the top of the page or in its bar.

Status: **current**, 2026-10-05. Provenance: #315.

## Intent

A song page names its song once, at full width. The title and artist each sit on one line that fills the width beside the album art, so a title never wraps early beside empty space. A line that does not fit scrolls (marquee) inside its column; a line that fits stays still. When the header scrolls under the bar, a compact copy (small art and the title) takes the bar's title slot.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/songs/headers/SongInfoHeader.tsx` (`SongInfoHeader`) | One header for Song Details, Song Leaderboard, Band Song Leaderboard and Player History: art, then a text column whose title (`h1`), artist line and optional `subtitle2` are each a `MarqueeText`. |
| `FortniteFestivalWeb/src/components/common/MarqueeText.tsx` (`MarqueeText`) | One line; scrolls only when the text is wider than its box; ellipsis under `prefers-reduced-motion`. |
| `FortniteFestivalWeb/src/hooks/ui/useMarqueeSync.ts` (`useMarqueeSync`) | The header's overflowing lines scroll the same distance, in lockstep. |

## Rules

1. **R1. Fill the width, one line.** The header's text column takes all the width beside the art; the title and artist never wrap at standard text sizes. (#315: the Apple Song Leaderboard wrapped "Through the Fire / and Flames" beside empty space.)
2. **R2. Marquee only on overflow, with the shared marquee.** A line wider than its column scrolls with the platform's shared marquee (Apple `MarqueeText`, Android `FestivalMarqueeText`, Windows `MarqueeText`); lines that fit stay still. The header's overflowing lines scroll in lockstep (web `useMarqueeSync`).
3. **R3. Motion and text size follow the shared marquee.** Reduce Motion tail-truncates without animation (HIG Accessibility: "When Reduce Motion is on, reduce automatic and repetitive animation"). At accessibility text sizes the in-page header wraps onto as many lines as it needs instead of truncating (HIG Typography, *should*: "Keep text truncation to a minimum as font size increases"). Assistive technology reads the full title once.
4. **R4. One pinned bar title.** The compact bar copy (small art, title on one marqueeing line, optional caption such as the instrument) stays on one line at every text size, is built only while the in-page header is scrolled away (so it is never read twice) and comes from the canonical component.
5. **R5. One header component per platform.** Song pages get the header's text column and bar title from the canonical components below, never a page-local `Text` that wraps.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| In-page title/artist column | `apple/Sources/FestivalUI/Common/SongHeaderText.swift` `SongHeaderText` (`MarqueeText` lines in a `maxWidth: .infinity` column with `marqueeSync`) | `android/app/src/main/java/com/festivalscoretracker/android/ui/songdetail/SongDetailScreen.kt` `SongHeader` (`FestivalMarqueeText` title and subtitle) | `windows/Festival.App/Controls/MarqueeText.cs` `MarqueeText` (the pinned Song Details title) |
| Pinned bar title | `apple/Sources/FestivalUI/Common/SongHeaderText.swift` `SongBarTitle` | — | — |

Apple consumers: Song Details hero and pinned title (`SongDetailScreen`), Song Leaderboard header and pinned title (`SoloLeaderboardScreen`), on iPhone, iPad, iPhone Duo and Mac. Android consumers of `SongHeader`: Song Details and Song Leaderboard.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple Band Song Leaderboard and Player History show no in-page song header (titles "Duos Scores", "Score History"); the web shows `SongInfoHeader` there | R5 (parity) | Web-parity port of those pages; use `SongHeaderText` when added |
| Android Band Song Leaderboard header (`ui/bands/SongBandLeaderboardScreen.kt`, `BandTextLink` title) and Player History subtitle use plain `Text` | R1, R2 | Android check filed from #315 |
| Windows `LeaderboardsSongPage`, `SongDetailPage`, `BandsSongLeaderboardPage` and `PlayerHistoryPage` header titles are wrapping or non-scrolling `TextBlock`s | R1, R2 | Windows check filed from #315 |

## Guards (`tools/pattern_guard.py`)

- `song-header/apple-wrapping-title`
