# Metadata pills

> **What:** the season chip ("S15") and the percentile chip ("Top 3%") drawn beside scores: one shared component each per platform, one size everywhere, the web colours with the current season inverted, and the spoken labels. Used by Songs rows, Suggestions, Song Detail cards and Score History, song leaderboards, Score History, Statistics percentile tables and Top Songs, and Band Detail. **Read when:** you show a season or a "Top N%" next to a score, or change either chip's size, colours or label.

Status: **current**, 2026-10-12. Provenance: #606 (split from #573).

## Intent

A season or a percentile looks and reads the same wherever a score shows it, so the eye learns it once. The season chip is readable at a glance and the current season stands out (owner, #606: "Season chips in general need some better contrast … Are we using shared Top X%, season chips, etc. between pages? Suggestions page seems to be using slightly smaller ones").

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/songs/metadata/SeasonPill.tsx` (`SeasonPill`) | "S<n>", width `IconSize.xl` (48), padding 2/4, `Radius.xs` (8), 2 px border. Normal: `surfaceSubtle` #162133 fill, `textSecondary` #D7DEE8 text, `borderSubtle` #1E2A3A border. `current`: the fill and text swap (light chip, dark text). |
| `FortniteFestivalWeb/src/components/songs/metadata/PercentilePill.tsx` (`PercentilePill`) | "Top N%" parsed with `^Top\s+([\d.]+)%$`: ≤ 1 `goldOutlineSkew` (italic, skewX −8°, bold, 2 px `goldStroke` #CFA500, `gold` #FFD700 text); ≤ 5 `goldOutline` (upright); otherwise `surfaceWhiteSubtle` (10% white) with `textSecondary`, semibold. Minimum width 5.5 em; inherits the row's font. |

Both are shared by seven web files (song rows, Suggestions, Song Detail, leaderboards, player history, percentile table, top songs).

## Rules

1. **R1. One component each.** Every season chip is the platform's shared season pill and every "Top N%" chip is its shared percentile pill. A page never draws a private copy, a smaller variant or a plain text season. Pages differ only in placement and whether the chip shows (the 520 dp season rule stays with [leaderboard-row](leaderboard-row.md) R1).
2. **R2. Season colours.** Normal: `surfaceSubtle` fill, `textSecondary` text, a 2 dp `borderSubtle` outline (text contrast ≥ 7:1). The catalogue's **current season** inverts: `textSecondary` fill with `surfaceSubtle` text. A page that doesn't know the current season shows every season neutral; it never guesses.
3. **R3. One size.** Both pills use the platform's chip label style (Material 3 Label Large 14 sp; Apple `.body` semibold; Fluent Body), a 24 dp/pt minimum height, an 8 dp corner radius and 6 dp horizontal padding; the season pill is at least 48 dp wide and the percentile pill at least 5.5 em. Both grow with the text size, never clip and never truncate.
4. **R4. Percentile tiers.** Top 1%: the skewed italic gold outline with bold gold text. Top 5% (above 1%): the upright gold outline. Anything else: 10% white fill with `textSecondary` semibold text (bold on the selected player's row where the web uses `bold`). A solid gold fill is not a tier.
5. **R5. Spoken label.** The season pill reads "Season N", or "Current season N" for the current season, so the inversion has a spoken equivalent. The percentile pill reads its text. Inside a row that is one screen-reader stop, the row's label carries the same words; the pills are never separate stops.
6. **R6. Not this pattern.** The accuracy / FC pill ([score accuracy](../controls/score-accuracy/spec.md)), star ratings, difficulty and intensity pills, Item Shop badges ([shop-offer-status](shop-offer-status.md)), and the Leaderboards page's rating values (accent text, not a chip) are separate controls.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Season pill (R2, R3, R5) | `apple/Sources/FestivalUI/Features/SongLeaderboard/ScoreSeasonPill.swift` `ScoreSeasonPill` | `android/app/src/main/java/com/festivalscoretracker/android/ui/design/MetadataPills.kt` `SeasonPill` (current season from `LocalCurrentSeason`; colours `seasonPillColors`) | `windows/Festival.App/Controls/MetadataPills.cs` `MetadataPills.Season` / `ApplySeason` (sizes and roles in `windows/Festival.Core/Domain/MetadataPillStyle.cs`) |
| Percentile pill (R3, R4) | `apple/Sources/FestivalUI/Features/Profile/PlayerPercentileTable.swift` `PercentilePill` | `MetadataPills.kt` `PercentilePill` (gold outlines via `ui/design/AccuracyPill.kt` `goldOutline`) | `MetadataPills.Percentile` / `ApplyPercentile` (XAML templates: `Controls/PercentilePillView`); tiers `MetadataPillStyle.Tier` / `TierOf` |

Android consumers:

- `SeasonPill`: Songs rows (`ui/songs/SongRow.kt` `MetadataPill`, current season from the row projection), Suggestions rows (`SuggestionCardView` `RowMetadata`), Song Detail instrument cards and song leaderboards (`SongDetailScreen` `SeasonCell` / `StackedScoreRow`), the Song Detail Score History card (`SongHistoryCard`), Score History rows (`PlayerHistoryScreen` `HistoryRow`) and the First Run Songs demo (through `MetadataPill`).
- `PercentilePill`: Songs rows, Suggestions rows, the Statistics/Profile percentile table (`ProfileCharts`), Top Songs (`ProfileTopSongs`) and Band Detail (`BandDetailScreen`).
- `LocalCurrentSeason` is provided from the catalogue's `currentSeason` by the Song Detail and song leaderboard routes (`SongDetailViewModel` / `SongLeaderboardViewModel` `currentSeason`) and Score History (`PlayerHistoryUiState.currentSeason`). Suggestions doesn't provide it: its stale categories are never the current season.
- The leaderboard season column (`LeaderboardSectionColumns` `metaWidth`) measures the label plus the pill's padding and never drops below `SEASON_PILL_MIN_WIDTH`, so every row's pill fits the shared column.
- Tests: `MetadataPillsUiTest` (one height, Songs rows draw the same composable, 48 dp / 5.5 em minimums, colours, labels, 200% text), `SongScoreMetadataUiTest` (tiers and season on Songs rows), `ProfileViewModelsTest.historyNamesTheCurrentSeasonOnlyWhenTheCatalogueReportsIt`, and the `SeasonPillAccessibilityJourneyTest` device journey (spoken "Current season" / "Season", reading order, ATF at 100% and 200%).

Windows consumers:

- Season pill: Songs rows (`Controls/SongRowVisuals`, current season from `SongRowProjection`), Suggestions season rows (`Controls/SuggestionSongRow`, never current: stale categories), every `Controls/LeaderboardEntryRow` (Song Detail instrument previews, song and band-song leaderboards, the Song Detail Score History list and selected-bar rows; current season from `App.Session.Catalog?.CurrentSeason`) and the first-run metadata demo (`Controls/FirstRunDemo` `MetadataDemoPill`, never current).
- Percentile pill: Songs rows, Suggestions rows, the Profile percentile table (`Controls/PlayerPercentileRowView`), the first-run Top Songs and metadata demos, and Band Detail's best/worst song rows (`Pages/BandsDetailPage.xaml` through `PercentilePillView`; web `BandSongsSection` → `PlayerSongRow` → `PercentilePill`).
- Each pill is one raw-view `MetadataPill` (no UIA children); the host row's name speaks the value. Rows whose season pill is current say "current season N" (`MetadataPillStyle.WithCurrentSeason`: leaderboard rows and Score History bars).
- **Live contrast switch.** The pill owns its contrast-theme lifecycle. `MetadataPills` hands every look to `MetadataPill.ApplyLook`. The pill keeps that look and re-resolves its fill, stroke and label roles from `ContrastTheme.Brush` on `ContrastTheme.Changed` while it is loaded, and again on `Loaded`, so a recycled or cached row catches up. This is required because the brushes are set in code and the label opts out of the system backplate (`HighContrastAdjustment=None`): without the re-resolve, a page left open across a switch keeps its normal-theme pills. Consumers (Suggestions, Profile, First Run, Band Detail's `PercentilePillView`) never subscribe for their pills. `LeaderboardEntryRow` and Songs rows still re-render on their own handler for their other surfaces. #606 review.
- The leaderboard season column (`LeaderboardColumnLayout`) never drops below `MetadataPillStyle.SeasonMinWidth`, so every row's pill fits the shared column.
- Tests: `MetadataPillStyleTests` (metrics, labels, tiers, colours, spoken current season, Band Detail tier), `MetadataPillContrastMarkupTests` (only the shared pill resolves role brushes, and it listens for contrast changes), `LeaderboardColumnLayoutTests`; UIA `tools/windows/journeys/a11y-song-season.json` (`assertsize ≥ 48×24`, names, keyboard, 225% text), `tools/windows/journeys/a11y-pill-contrast-switch.json` (Suggestions season and percentile, Profile percentile and First Run Top Songs pills, populated and open, switched live to the Desert contrast theme with `contrast:desert`: ButtonFace fill and ButtonText outline, then back to the normal colours), Suggestions `loaded`/`rival-rows` and the first-run Top Songs journey.
- Test IDs (raw view): Suggestions `fst.suggestions.row.<song>[.<instrument>].season` / `.percentile` (the row ID with `|` → `.`), Profile `fst.player.percentile.<instrument>.<tier>.pill`, First Run `fst.first-run.demo.statistics-top-songs.pill.<n>`.

### Agent decision: Material 3 chip size and the web colours (#606)

Agent decision (#606, 2026-10-12, owner may override with `/choose`). Android drew these chips five different ways: Suggestions' percentile at 12 sp (72 dp) and its season at 16 sp, the Song Detail Score History season at 14 sp `textPrimary` on `surfaceMuted` with 6 dp corners, Song Detail cards and song leaderboards as plain `S15` text, and Songs at 14 sp with `surfaceMuted` seasons. Only Songs inverted the current season, and its Top 1% was a solid gold fill where the others drew an outline.

| Option | What you'd see | Guidance (strength) | Web / pattern precedent | Trade-offs |
|---|---|---|---|---|
| A. Keep each page's size, only raise the season contrast | Readable seasons, but three chip sizes. | — | None. | Leaves the owner's "slightly smaller ones" complaint. |
| **B. One shared pill each, Label Large 14 sp, 24 dp, 8 dp corners, web colours (chosen)** | The same chip on every page; the current season a light chip with dark text. | material-3 skill, typography: "Chip label \| Label Large" (**should**); shape scale: "`small` \| 8 \| … chips" (**should**); color roles: "inverse-surface / inverse-on-surface \| Contrasting elements" (**should**) | Web `SeasonPill`/`PercentilePill` (7 consumers); Apple `ScoreSeasonPill` | Suggestions and Song Detail chips grow slightly; Songs' Top 1% becomes the web's skewed outline instead of a gold fill. |
| C. Material `AssistChip` | Tappable-looking chip with a 32 dp container. | Material chips are interactive (**should**) | None. | Implies an action; a 32 dp chip doesn't fit score rows. |

**Chose B.** The web is the product source of truth and already has one component each; the Material type and shape roles for chips give the same 14 sp / 8 dp. Width minimums follow the web (season 48 dp, Apple's 44 pt aside), so pills line up in shared columns.

### Agent decision: Fluent pill sizes and colours (#606)

Agent decision (#606, 2026-10-12, owner may override with `/choose`). Windows drew these chips six ways: Songs rows' 14 epx boxes with `surfaceMuted` seasons, Suggestions' 12 epx percentile and season text, leaderboard and Score History rows' plain "S15" text, the Profile table's own gold/neutral badge, the first-run demo copies, and Band Detail's purple `#7C3AED` badge.

| Option | What you'd see | Guidance (strength) | Web / pattern precedent | Trade-offs |
|---|---|---|---|---|
| A. Raise the season contrast in place | Readable seasons, still several sizes. | — | None. | Leaves "slightly smaller ones". |
| **B. One factory each, Fluent Body 14 epx, 24 epx tall, 4 epx corners, 4 epx padding, web colours (chosen)** | The same pill on every page; the current season a light pill with dark text; Band Detail's purple badge becomes the tiered pill. | winui-code-review: "Corner radius uses `ControlCornerRadius` / `OverlayCornerRadius` — not hardcoded values" (**should**); "Typography uses built-in styles (… `BodyTextBlockStyle` …)" (**should**); winui-design theme-accessibility: "Never set `HighContrastAdjustment="None"` to 'fix' a contrast issue … unless you've supplied correct system-aware brushes everywhere" (**must**) | Web `SeasonPill`/`PercentilePill`; Apple `ScoreSeasonPill` | 4 epx corners and padding deviate from R3's 8/6 (below). |
| C. Fluent `InfoBadge`/`Button`-styled chip | A badge or tappable-looking chip. | `InfoBadge` is for notifications (**should**) | None. | Wrong semantics; badges are not data. |

**Chose B.** Windows-specific values, recorded here instead of R3: a **4 epx corner radius** (the Fluent `ControlCornerRadius` value, matching the accuracy pill beside it in every row) and **4 epx padding** (web `padding.xs` horizontal). The ordinary percentile uses the opaque `surfaceMuted` #223047 (Fluent tokens are opaque; the contrast gate pairs `textSecondary` on it) instead of 10% white, and the current season's outline is `surfaceSubtle` #162133. Under a contrast theme: season and ordinary percentile ButtonFace / ButtonText with a ButtonText outline, current season Highlight / HighlightText, gold tiers Window fill with a WindowText outline and label (Top 1% keeps its skew and italic); the label opts out of the automatic backplate (`HighContrastAdjustment=None`) because every role is already a system colour (the theme-accessibility exception).

## Known debt

None recorded.

## Guards (`tools/pattern_guard.py`)

- `metadata-pills/android-private-pill`: no `fun …SeasonPill(` or `fun …PercentilePill(` outside `ui/design/MetadataPills.kt`.
- `metadata-pills/windows-private-pill`: no pill brush key (`FST(SeasonPill|CurrentSeason|PercentileNeutral|PercentilePill|GoldPillFill)…Brush`) in `windows/Festival.App` outside `Themes/Styles.xaml`; pages build pills through `MetadataPills`.
