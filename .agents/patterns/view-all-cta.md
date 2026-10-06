# View all call to action

> **What:** the full-width "View all" button that ends a card of preview rows and opens (or expands) the full list: View Full Leaderboard, View All Rivals, View All (Rival Detail categories), View All Rankings (N), View All Scores. **Read when:** adding a card that previews part of a list, or changing any of these buttons.

Status: **current**, 2026-10-06. Provenance: operator batch 6.29, #41, #68, #207, #264, #268, #321.

## Intent

A card that previews the top of a longer list ends the same way on every page: one wide, brand-purple button below the rows that names where it goes. People learn it once and find it in the same place on Song Details, Rivals, Compete and Leaderboards.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/songinfo/components/ViewFullLeaderboardCta.tsx` (`ViewFullLeaderboardCta`) | Full-width, `entryRowHeight`, centred semibold `textPrimary` label on a frosted card; Song Detail instrument and band cards (`InstrumentCard`, `SongBandLeaderboardPreview`). |
| `FortniteFestivalWeb/src/pages/rivals/useRivalsSharedStyles.ts` (`viewAllButton`) | The same look for View All Rivals on Rivals and Compete (`RivalsPage`, `CompetePage`, `LeaderboardRivalsTab`). |
| `FortniteFestivalWeb/src/pages/leaderboards/components/RankingCard.tsx` (`RankingCard`) | View All Rankings (N) below the ranking rows (also `BandRankingCard`). |
| `FortniteFestivalWeb/src/components/common/GraphCard.tsx` (`viewAllButton`) | View All Scores below Song Detail's score history list. |

The web places the button **after** the rows and only for non-empty, error-free previews (`InstrumentCard.tsx:300-327`).

## Rules

1. **R1. One button, after the rows.** The CTA sits below the card's last row (after the selected player's appended row, when shown), spans the card's width and centres a semibold label. It shows only when the card shows rows: never while loading, for an empty card or on a failed read.
2. **R2. Brand purple, not the web's frosted fill.** Owner decision (operator batch 6.29): the natives fill the CTA with the brand purple (`#7C3AED`) and white text instead of the web's frosted card. It is never the platform accent colour.
3. **R3. Platform minimum target, no per-consumer overrides.** Height is at least the platform target (Apple 44 pt, Android 48 dp, Windows 40 epx `FSTMinTargetSize`). Consumers set no margin, height, colour, corner or font of their own; the canonical component owns them.
4. **R4. Label first, then the card.** Labels are the web copy in Title Case (View Full Leaderboard, View All Rivals, View All Rankings (N), View All Scores, and plain View All where the card title already names the list). The copy is "View All", never "See All" (owner, #321). The accessible name starts with the visible label, then names the card or chart ("View Full Leaderboard, Lead"; WCAG 2.5.3 label in name), the role is Button and each card's CTA has its own test ID.
5. **R5. Contrast and transparency modes keep it readable.** Windows contrast themes draw it HighlightText on Highlight with no automatic text backplate (`HighContrastAdjustment="None"`); Apple uses an opaque purple under Reduce Transparency and the in-app contrast/transparency toggles.
6. **R6. Not this pattern.** A section title's trailing "View All" link ([section-headers](section-headers.md) R8) and Search's "View All Results" are links, not this CTA. A preview card's own bottom "see the whole list" row is this CTA, never a separate in-card text row: Rival Detail's category cards end with it (owner, #321).
7. **R7. Bottom rows become the CTA; title-row links stay links.** **Agent decision (#321, 2026-10-06): option A; owner may override with `/choose`.** The owner asked that Rivals' in-card "See All" use the purple button and that every "See All" read "View All". Bottom-of-card "see the whole list" rows become this CTA (labelled "View All" plus the card in the spoken name). Title-row links keep the section-headers R8 link style with "View All" copy. Rationale: HIG Buttons "Keep to one or two prominent buttons per view" (should), the web's header links on Rival Detail and Profile Bands, and the existing R8 pattern. Option B, every link a purple button, was rejected.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Button look (R1–R3, R5) | `apple/Sources/FestivalUI/Features/Leaderboards/PurpleActionButton.swift` `PurpleActionLabel`; push link `PurpleActionLink` (label, route, test ID, label-first spoken name) | `android/app/src/main/java/com/festivalscoretracker/android/ui/design/ViewFullLeaderboardButton.kt` `ViewFullLeaderboardButton` | `windows/Festival.App/Themes/Styles.xaml` `FSTViewAllButtonStyle` (based on `AccentButtonStyle`) |
| Labels and accessible name (R4) | per consumer | per consumer | `windows/Festival.Core/Domain/ViewAllCta.cs` `ViewAllCta` (`Name(label, card)`; card view models expose `ViewAllText`, `ViewAllName`, `ViewAllAutomationId`) |

Windows consumers (`ViewAllCtaTests` lists them and forbids overrides): Song Detail Score History View All Scores (`SongDetailPage.xaml` `HistoryViewAll`, `fst.history.view-all`), Song Detail instrument cards (`fst.song-detail.view-all.<instrument>`) and band cards (`fst.song-detail.band-view-all.<type>`), Leaderboards instrument and band cards (`fst.leaderboards.card.<instrument>.view-all`, `fst.leaderboards.band-card.<type>.view-all`) and the Rivals hub cards on both tabs (`fst.rivals.section[.leaderboard].<id>.view-all`; `/compete` opens the same page).

Apple consumers: `RivalsViewAllButton` (Rivals, Compete; via `PurpleActionLink`), Rival Detail categories (`RivalDetailScreen`, Duo `RivalDualDetailPane`; `PurpleActionLink` "View All", `fst.rival-detail.category.<key>.view-all` / `fst.dual.rivals.category.<key>.view-all`, spoken "View All, <category>"), `PlayerBandsPreviewSection`, `SongScorePreview`, `SongBandPreviewSection`, `SongScoreHistorySection`, `CompeteScreen`, `LeaderboardsScreen`. Android consumers: `RivalComponents`, `CompeteScreen`, `SongDetailScreen`, `SongHistoryCard`, `LeaderboardsScreen`, `ProfileBands`.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple Song Detail cards label the button "View full leaderboard" (sentence case) and speak "View full `<chart>` leaderboard", which splits the visible label | R4 | Apple check; out of #268's Windows scope |
| Android and Windows Rival Detail category "See All" and other "See All" copy; web `rivals.seeAll`, `compete.seeAll`, `player.seeAll` | R4, R6, R7 | Android, Windows and web checks of #321 |
| TODO(orchestrator): Android accessible names are not audited against R4 | R4 | Android check of #68 adds its findings here |

## Guards (`tools/pattern_guard.py`)

- `view-all-cta/windows-label-copy`
- `view-all-cta/windows-xaml-literal`
- `view-all-cta/windows-parallel-style`
