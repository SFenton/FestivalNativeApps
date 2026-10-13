# Metadata pills

> **What:** shared season and Top X% content badges, their contrast, sizing and accessibility. **Read when:** drawing these values on any page or first-run replica.

Status: **current**. Provenance: SFenton/festival-report-tracker#606; extends [surface-materials](surface-materials.md) R6.

## Intent

Season and percentile values have one treatment per platform, independent of their page. The owner asks for "better contrast" and "shared Top X%, season chips".

## Web source

| Source | Behavior |
|---|---|
| `FortniteFestivalWeb/src/components/songs/metadata/SeasonPill.tsx` | Secondary text on the subtle surface with a thick outline; current season inverts the pair. Explicit `current` overrides catalogue detection. |
| `FortniteFestivalWeb/src/components/songs/metadata/PercentilePill.tsx` | Top 1% gold italic/skewed outline, Top 5% upright gold outline, other values neutral; minimum width 5.5 em. |

## Rules

- **R1. Reuse, never redraw.** Every season or Top X% badge uses the canonical component, including Songs, Suggestions, Song Detail previews and history, solo song leaderboards and band-board pinned rows, Profile/Statistics percentiles, Band Detail best/worst songs and first-run replicas. Rankings' blue rating text is a different value role, not a percentile badge.
- **R2. Season contrast is explicit.** Match `ScoreSeasonPill`: `textSecondary` (#D7DEE8) on opaque `surfaceSubtle` (#162133), at least 7:1 text contrast. Invert this pair for the catalogue's current season. Suggestions' stale-score seasons mean *last played* and remain neutral; never infer a current season from a score's maximum season.
- **R3. Size is page-independent.** Windows uses one 14 epx semibold label, 24 epx minimum height, 48 epx minimum season width, 5.5 em minimum percentile width, 2 epx outline and Fluent 4 epx corners. These are minimums, not fixed frames: Windows text scaling grows content. The shared leaderboard fitter reserves the season pill including its padding and stroke, preserves the 520 epx season breakpoint and never drops the tapped history detail row's season.
- **R4. Contrast themes repaint live.** Neutral pills use ButtonFace/ButtonText; current seasons use Highlight/HighlightText; gold outlines use Window/WindowText. Code-built pills own their `ContrastTheme.Changed` subscription, re-resolve role brushes on the UI thread on load and on colour changes, and unsubscribe on unload. No consumer has to remember to repaint a pill.
- **R5. Badges are not actions.** Pills are raw-view, non-focusable Text peers; the surrounding row reads its values exactly once in visual order. A displayed current season is spoken as "current season N"; a hidden season is not read. Preserve existing score-season and Songs metadata test IDs. Keyboard and touch targets belong to the row (40 epx minimum), not to the 24 epx badge.

## Canonical implementation

| Role | Apple | Android | Windows |
|---|---|---|---|
| Season | `Features/SongLeaderboard/ScoreSeasonPill.swift` `ScoreSeasonPill` (contrast precedent) | Private copies; separate platform worker owns consolidation | `Controls/MetadataPills.cs` `MetadataPills.Season`, hosted by `MetadataPill` |
| Percentile | `Features/Profile/PlayerPercentileTable.swift` `PercentilePill` (precedent) | Private copies; separate platform worker owns consolidation | `Controls/MetadataPills.cs` `MetadataPills.Percentile`; `PercentilePillView` is the XAML adapter |
| Geometry | Native scaled metrics | Separate platform worker | `Festival.Core/Domain/MetadataPillMetrics.cs`; `LeaderboardColumnLayout` uses the season width |

## Agent decision

Agent decision (SFenton/festival-report-tracker#606, 2026-10-12; owner may override): choose the shared web/iOS content treatment with native Windows geometry. Supersedes the private 12/13/14 epx pills, outline-only old seasons, bare leaderboard seasons and Band Detail's purple percentile badge.

| Option | Outcome | Trade-off |
|---|---|---|
| Keep the Songs 12 epx/22 epx boxes everywhere | Consistent but small, with outline-only old seasons | Does not satisfy the requested iOS contrast |
| Copy Apple's body font and fixed scaled frame literally | Larger typography and Apple corners | Needlessly copies platform geometry |
| Shared 14 epx/24 epx minimum pills, iOS contrast, Fluent corners | Same size and semantic tiers everywhere, grows with text | Chosen; preserves native row focus and layout |

Guidance: `winui-design/references/theme-accessibility.md` **must**: "Only `SystemColor*Brush` resources are allowed inside an HC dictionary"; `winui-design` **must**: never disable automatic High Contrast adjustment without system-aware brushes throughout. Explicit role pairs and shared live repaint satisfy these requirements. Native chrome is unchanged; these are decorative content badges, not custom segmented controls.

## Guards

- `metadata-pills/windows-season-style`: season brush roles may appear in C# only in the shared factory.
- `metadata-pills/windows-private-percentile-xaml`: pages use the shared adapter instead of the legacy private percentile roles.

## Tests and known debt

- Windows: `MetadataPillTests` covers geometry, the inverted colour pair, measured text contrast, shared consumers and theme lifecycle. `a11y-metadata-pills.json` covers the history detail, current-season row, Songs, Suggestions and Profile/Statistics badges at normal, 225% text and Desert contrast; `a11y-song-season.json` keeps the history keyboard/reading-order contract. The same metadata matrix also runs against the published Native AOT executable.
- Apple and Android consumers are outside this Windows experiment's edit scope; their consolidation or remaining divergences are deferred, not certified here.
