# Songs profile panel

> **What:** the wide Songs row that puts the selected profile's score cards on its right half: a player's per-instrument cards, or a band's score card. The song stays on the left; the list stays full width. **Read when:** changing wide Songs rows on iPad, the iPhone Duo inner display or the Mac; adding a selected-profile visual to a Songs row; or porting this to Android/Windows wide layouts.

Status: **current**, 2026-10-07. Provenance: #340 (split from #332; agent decision below), #388 design review.

## Intent

The owner asked that on Duo unfolded, iPad and Mac, with a profile selected, "player/band data should take right side of the screen with nice graphs/chips/cards for each instrument, or just card/chip for band score(s) if band". Wide rows use their spare width for the selected profile's scores. With no profile, or for a song without scores, the row looks exactly as it does today. The panel only *presents* the Songs score index; it never decides availability, publication or load state.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx` (`bandPerformanceToPlayerScore`) | A selected band's `/song-rows` entry is shown as a score row: score, accuracy/FC, percentile, stars, season, end time. |
| `FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx` | The selected player's metadata pills (score, accuracy, percentile, stars …) on each Songs row. |

The web has no wide split row; its desktop row puts the same pills inline. The panel is a native wide-layout addition (HIG Layout) built from the web's pills.

## Rules

1. **R1. Wide shells only.** iPad, the iPhone Duo inner display and the Mac opt in (`songRowsAllowProfilePanel`). iPhone, folded Duo and Item Shop rows never split. A row splits only when its card is at least 600 pt wide (`DeviceLayout.regularColumnWidth`) and R3's fit holds.
2. **R2. Selection, publication and load gates.** A row splits only for a selected player or band whose score index is available and observed in the same publication as the displayed Songs rows (`FestivalSession.hasCurrentPlayerScores(forCatalogue:)`, `hasCurrentBandScores(forCatalogue:)`). Loading, syncing (202), failed, 503-unpublished and publication-paused indexes keep the plain row with its existing loading/paused/unavailable line. Filter Invalid Scores (player only), accessibility text sizes and an invalid accuracy value also keep the plain row. The panel adds no transition of its own ([load-transition](load-transition.md): only the existing Songs reveal).
3. **R3. Compact cards keep one line, or the row stays plain.** "All instruments" and band cards show only Score, Accuracy/FC, Percentile and Stars (where enabled), in the saved Settings order. They use equal columns, take the most columns that fit, and drop Stars only to fit their line or save a line (VoiceOver still hears them). If even a starless compact card can't fit one line in the half (estimated per field, scaled by Dynamic Type), the row stays plain: at default text the 600 pt row's 282 pt half is below a six-digit card's 302 pt, so such rows split from about 640 pt. A single filtered chart's card shows every enabled field, takes the whole half and wraps its pills like the one-chart Songs row.
4. **R4. Player cards.** One card per Settings-visible, charted chart with a positive score, in the status chips' instrument order, with the chart icon. A song with no positive score on the shown charts keeps the plain row.
5. **R5. Band card.** One card for the selected band's song row (score > 0), with the band-size symbol (`BandType.symbolName`, shared with Song Details' band Quick Links). Bands have no chart, so no Intensity or game difficulty. The band index comes only from the mutation-free `GET /api/rankings/bands/{bandType}/{teamKey}/song-rows` ([service safety](../platforms/service-safety.md)), validated for team, combo, count and value ranges. The plain (narrow or gated) band row shows the band's pills like the player's one-chart row.
6. **R6. Grid.** While a profile is selected (and, for a player, Filter Invalid Scores is off), the landscape two-card grid shows one song per row so each row has the width (`SongProfilePanelPolicy.gridColumns`).
7. **R7. Surfaces.** Cards are flat `surfaceMuted` 35 % fills, 8 pt radius, a stroke under Increase Contrast, inside the one row card; no second material ([surface-materials](surface-materials.md) R6).
8. **R8. Accessibility and IDs.** Each card is one VoiceOver element ("Lead: Score 270,007, Full combo, …"; "The Duo, Duos band: Score 1,234,567, …"), read after the song; the row stays one combined link. Test IDs: `fst.songs.profile-panel.<songId>` and `fst.songs.profile-panel.<songId>.<instrument rawValue | band>`.
9. **R9. One component.** Consumers never build their own split: `SongRowView.profilePanel` asks `SongProfilePanelPolicy` (gate, tiles, arrangement) and renders `SongProfilePanel`.

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Gate, fit, tiles, grid (R1–R6) | `apple/Sources/FestivalUI/Features/Songs/SongProfilePanelPolicy.swift` `SongProfilePanelPolicy` (`allows`, `arrangement`, `tiles`, `bandTiles`, `gridColumns`) | not ported | not ported |
| Panel view (R7, R8) | `apple/Sources/FestivalUI/Features/Songs/SongProfilePanel.swift` `SongProfilePanel` | — | — |
| Row integration | `apple/Sources/FestivalUI/Features/Songs/SongRowView.swift` `profilePanel` | — | — |
| Band index (R2, R5) | `apple/Sources/FestivalCore/FestivalAPI+Bands.swift` `bandSongRows`; `apple/Sources/FestivalUI/App/FestivalSession.swift` `refreshSelectedBand` | — | — |

Tests: `SongProfilePanelPolicyTests` (gate, fit including the 600 pt threshold, player and band tiles), `SelectedBandSessionTests` (band index load, publication gate, 503), `SelectedSongRowRenderTests` (`wideSongRowsSplitOnlyForASelectedPlayersScores`, `wideSongRowsAtTheBreakpointKeepCompactCardsOnOneLine`, `wideSongRowsShowTheSelectedBandsScoreCard`), `FestivalAPIBandsTests` (`bandSongRows…`), `OnDemandSplitPolicyTests.songsGridColumnsWithSelectedPlayer`.

## Agent decision (#340, 2026-10-07)

With a profile selected on wide Songs, the right side of **each wide row** holds that profile's score cards (option A). Owner may override with `/choose`.

| Option | What you'd see | Guidance (strength) | Web / pattern precedent |
|---|---|---|---|
| **A. Split each wide row (chosen)** | Every scored song shows its per-instrument (or band) cards on the right half of its row. | HIG Layout: "Larger spaces may show more functionality" (should). HIG Lists and tables: "consider alternatives to over-large rows" (should), met by R3's one-line compact cards. | Operator 2026-10-04 ([split-view](../design/apple/split-view.md)): "screens like Songs should never be split". Reuses the Songs row card, status chips and the [song-score-metadata](../controls/song-score-metadata/spec.md) pills. |
| B. Songs list + selected-song pane | A list/detail split with the tapped song's scores on the right. | HIG Split views (should, regular width) | Contradicts the operator's never-split Songs verdict; Song Details already shows one song's scores. |
| C. No change | Today's chips/one-chart row. | — | Ignores the ask. |

Why A: an explicit owner choice (Songs never splits) outranks the platform's split-view recommendation, and A keeps it while using the width. The precedence tie-break favours the existing row, chips and pills over a new pane.

Fit sub-decision (#388 review): compact cards never wrap (R3) rather than wrapping at the 600 pt breakpoint. Options: (a) let compact cards wrap in a narrow half (rejected: two-line overview cards make rows taller than the plain row, against HIG Lists and tables' "alternatives to over-large rows"); (b) raise the breakpoint to a fixed width (rejected: a band's seven-digit score or larger text would still wrap); (c) measure the one-line fit per row and keep the plain row when it fails (chosen). The single filtered chart's card keeps wrapping because the one-chart Songs row already wraps the same fields (HIG Typography: "consider stacking text above secondary items").

Band sub-decision: the band card ships with this pattern, fed by the read-only `/song-rows` projection the web uses. Selecting a band is one profile at a time (the web's single `selectedProfile`), exclusive with a player, and in memory only.

## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Apple has no user-facing "select band" entry yet; a band is selected only through `FST_DEBUG_BAND` and tests. The web's band selection flow is unported. | Reach of R5 | Port band selection (separate issue); the panel needs no change. |
| On the iPhone Duo inner display the halves meet at the display midpoint, but the system's 40 pt hinge band (455–495 pt) is wider than the 12 pt gap, as in the two-card grid. | R1 on Duo | Duo hinge pass. |
| Android and Windows wide Songs rows have no panel. | Parity | Their own issues. |

## Guards (`tools/pattern_guard.py`)

None yet; the policy and render tests above hold the rules.
