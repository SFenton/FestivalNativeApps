# Song header title

> **What:** how the song title and its artist line read in every song header: one line across the text column, scrolling when it overflows. **Read when:** adding or changing a song header (Song Detail hero or pinned bar, Song Leaderboard, Band Song Leaderboard, Player History) or any header that names the song.

Status: **current**, 2026-10-05. Provenance: #315.

## Intent

A song header names its song on one line that uses all the width beside the album art. A title that still doesn't fit scrolls inside its column; it never wraps early, leaves empty space beside it or clips.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/songs/headers/SongInfoHeader.tsx` (`SongInfoHeader`) | Shared header of Song Detail, Song Leaderboard, Song Band Leaderboard and Player History: title (`h1`) and `artist · year · duration` in a `flex: 1; minWidth: 0` column, each a `MarqueeText`. |
| `FortniteFestivalWeb/src/components/common/MarqueeText.tsx` (`MarqueeText`) | One line; scrolls only when it overflows, otherwise static. |

## Rules

- **R1. One line, full width.** The song title and its artist line in every song header fill the text column beside the art on one line each, drawn by the platform's shared marquee (R4). Short text stays static. A wrapping or clipping text view for a song header title is a regression.
- **R2. Overflow scrolls, motion off truncates.** Overflowing text scrolls inside its column with the shared marquee's timing. Reduce Motion (or the system's animation setting) and inactive views show the tail-truncated text with no animation. Accessibility text sizes follow the shared marquee's own rule (Apple wraps in-page headers and keeps bar titles on one line). HIG Motion (should): "reduce automatic and repetitive animation" when Reduce Motion is on.
- **R3. Read the full title once.** Assistive technology gets the full title once. When the title is the page's heading it keeps heading level 1; when it is a link (Windows Band Song Leaderboard), the link is named by the title and its inner marquee is hidden from the tree.
- **R4. One marquee per platform.** Song headers reuse the canonical marquee below; no feature-local marquee, fade or wrapping fallback.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Single-line marquee title | `apple/Sources/FestivalUI/Design/MarqueeText.swift` `MarqueeText` | `android/app/src/main/java/com/festivalscoretracker/android/ui/common/MarqueeText.kt` `FestivalMarqueeText` | `windows/Festival.App/Controls/MarqueeText.cs` `MarqueeText` |

Windows consumers (#315): `Pages/SongDetailPage.xaml` hero (title `TitleLargeTextBlockStyle`, artist `FSTMarqueeSongHeaderArtistStyle`) and pinned bar; `Pages/LeaderboardsSongPage.xaml` (title `FSTPageTitleStyle`, artist `FSTMarqueeSecondaryStyle`); `Pages/BandsSongLeaderboardPage.xaml` (song link `FSTMarqueeTitleStyle` inside the `HyperlinkButton`, artist line); `Pages/PlayerHistoryPage.xaml` (`Song · Lead` subtitle under the "Score History" heading). Each keeps its own type size; only the line behavior is shared. `SongHeaderMarkupTests` guards them.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple `Features/SongLeaderboard/SoloLeaderboardScreen.swift` `scoreHeader` draws a wrapping `Text(song.title)`; Band Song Leaderboard, Player History and the pinned bar titles (`maxWidth` 240/260) are unchecked. | R1 | Apple lane of #315. |
| Android `ui/bands/SongBandLeaderboardScreen.kt` (song link) and `ui/profile/PlayerHistoryScreen.kt` (subtitle) use plain `Text`. | R1 | Android lane of #315. |

## Guards (`tools/pattern_guard.py`)

- `song-header-title/windows-no-textblock-title`: a Windows page binds the song title (`Song.Title`, `SongTitle`) to a plain `TextBlock`.
