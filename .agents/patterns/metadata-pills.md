# Metadata pills

> **What:** the small season chip ("S9") and percentile chip ("Top 3%") that sit on Songs rows, Suggestions rows, Song Detail score and leaderboard rows, Score History, Player History, song and band leaderboards, the Profile percentile table and the first-run demos. **Read when:** drawing a season or "Top N%" chip anywhere, changing their colours, size or spoken name, or adding a surface that shows a score's season or percentile.

Status: **current**, 2026-10-10. Provenance: #606 (split from #573, owner report: "Season chips in general need some better contrast … Are we using shared Top X%, season chips, etc. between pages? Suggestions page seems to be using slightly smaller ones").

## Intent

A season or percentile chip looks and reads the same on every page: same size, same colours, same highlight for the current season. People compare chips across Songs, Suggestions and leaderboards, so a smaller or dimmer copy on one page reads as a different thing.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/songs/metadata/SeasonPill.tsx` (`SeasonPill`) | "S9" in `textSecondary` semibold on `surfaceSubtle` with a 2 px `borderSubtle` outline, 48 px wide, radius 8; the current season (from `FestivalContext`) inverts fill and text. Shared by Songs rows, Suggestions, Song Detail, history and leaderboards. |
| `FortniteFestivalWeb/src/components/songs/metadata/PercentilePill.tsx` (`PercentilePill`) | "Top N%": `goldOutlineSkew` (gold text, `#CFA500` outline, italic, skewed −8°) at Top 1%, `goldOutline` at Top 5%, otherwise `textSecondary` on `surfaceWhiteSubtle`; min width 5.5 em. |

## Rules

1. **R1. One season pill and one percentile pill per platform.** Every page draws its season and "Top N%" chips with the platform's canonical component (table below), never a private copy, so size, padding, radius and stroke are identical on every page (owner, #606).
2. **R2. Season pill contrast and current-season highlight.** The season pill is secondary text (`#D7DEE8`) on the subtle surface (`#162133`) with a 2 pt/dp/epx subtle border; the catalogue's current season inverts fill and text (web `SeasonPill`, Apple `ScoreSeasonPill`). The current season comes from the loaded catalogue, never a hard-coded number. Text on the pill keeps at least 4.5:1 in both states.
3. **R3. Percentile tiers.** The percentile pill's tier comes from the percentage with the web thresholds: Top 1% and better is gold, bold, italic and skewed −8° with a `#CFA500` outline and no fill; Top 5% is the gold outline; anything else is secondary text on the translucent white surface. A label that is not "Top N%" is the neutral tier.
4. **R4. Spoken as words, not glyphs.** A season pill is announced "Season 9", or "Current season 9" for the highlighted one, so the highlight is not conveyed by colour alone; a percentile pill is announced with its text. Rows that read as one element (leaderboard rows, Suggestions rows) fold the pill into the row name.
5. **R5. Text scaling and contrast themes.** Pills grow with text scaling and never truncate their text; under a contrast theme (Windows) or Increase Contrast (Apple) the pill uses system colours with a visible border and keeps the current-season inversion with system Highlight colours.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Season pill (R1, R2, R4) | `apple/Sources/FestivalUI/Features/SongLeaderboard/ScoreSeasonPill.swift` `ScoreSeasonPill` | `android/app/src/main/java/com/festivalscoretracker/android/ui/songs/SongRow.kt` `MetadataPill` (Songs rows and first-run; other Android pages are debt) | `windows/Festival.App/Controls/MetadataPills.cs` `MetadataPills.Season` |
| Percentile pill (R1, R3) | `apple/Sources/FestivalUI/Features/Profile/PlayerPercentileTable.swift` `PercentilePill` | `SongRow.kt` `MetadataPill` | `MetadataPills.Percentile` |
| Geometry, tiers, roles, spoken text | in the views above | `core/songs/SongRowProjection.kt` `SongMetadataPill` | `windows/Festival.Core/Domain/MetadataPillStyle.cs` `MetadataPillStyle`, brushes `FSTSeasonPill*`, `FSTCurrentSeason*`, `FSTTopOne*`, `FSTMetadataPill*` in `Themes/Styles.xaml` |

Windows consumers (#606): `SongRowVisuals` (Songs rows and the first-run Songs demos), `SuggestionSongRow` (Suggestions), `LeaderboardEntryRow` (Song Detail top scores, song and band leaderboards, Score History, Player History), `PlayerPercentileRowView` (Profile percentile table), `FirstRunDemo` (Statistics top-songs demo). Not a consumer: Band Detail's purple "Top N%" badge (`BandsDetailPage.xaml`, `FSTPercentilePill*`), which ports the web band page's own badge rather than `PercentilePill`.

### Agent decision: Windows pill size (#606)

Agent decision (#606, 2026-10-10, owner may override with `/choose`). The owner asked for one shared chip, the same size everywhere, with the iOS contrast.

| Option | What you'd see | Guidance (strength) | Web / pattern precedent | Trade-offs |
|---|---|---|---|---|
| **A. Fluent Caption pill (chosen)** | 12 epx semibold text, 22 epx tall, radius 4, at least 36 epx wide (season) / 66 epx (percentile), on every page. | Fluent type ramp: Caption 12 for metadata; `ControlCornerRadius` 4 (**should**). | Web proportions (season pill 3 em wide, percentile 5.5 em) scaled to 12 epx; same size as the Windows accuracy badge beside it. | Smaller than the web's 16 px pill, but it fits the dense Windows rows without wrapping the score columns. |
| B. Web size | 16 epx text, 48 epx wide, radius 8. | Same. | Web `SeasonPill`. | Larger than every other chip in the Windows rows; leaderboard columns would need re-planning on compact windows. |

**Chose A.** No platform **must** applies; the owner's ask is one size and contrast, not the web's pixel size, and Fluent Caption keeps the pill in step with the neighbouring Windows accuracy and score chips. `MetadataPillStyleTests` pins the geometry, tiers and roles; `a11y-metadata-pills.json` pins size, paint and names.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android `ui/suggestions/SuggestionCardView.kt` private `SeasonPill`/`PercentilePill` and `ui/songdetail/SongHistoryCard.kt` private `SeasonPill` | R1, R2 | Android session for #606 |
| Apple Songs rows and Suggestions draw season and percentile chips with `Features/Songs/SongProfileMetadataPills.swift` `SongMetadataFieldView`, while score, history and leaderboard rows use `ScoreSeasonPill` | R1 (two season views) | Not swept in #606 (an Android/Windows issue); Apple check |

## Guards (`tools/pattern_guard.py`)

- `metadata-pills/windows-season-brushes` (C#) and `metadata-pills/windows-season-brushes-xaml` (XAML): the season and Top 1% role brushes (`FSTSeasonPill*`, `FSTCurrentSeason*`, `FSTTopOne*`) appear only in `Styles.xaml` and `MetadataPillStyle.cs`; any other Windows file draws through `MetadataPills`.
