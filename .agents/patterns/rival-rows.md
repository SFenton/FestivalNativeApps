# Rival rows

> **What:** the rows inside Rivals cards: the hub's rival rows (name, "N ahead" / "N behind" pills) and the song comparison rows on Rival Detail, Rivalry and the Duo dual-pane category cards (album art, instrument icon, title, artist, "#rank Name" pills and a rank-delta badge). **Read when:** changing a Rivals row, its status pills or its album art, or adding a new surface that compares the player with a rival.

Status: **current**, 2026-10-10. Provenance: #558 (owner report from iPhone), #603 (one card per list; Windows song rows adopt R3).

## Intent

Every Rivals card says who is ahead the same way: a red or green capsule with text in it. A song comparison row also shows the song's album art, like every other song row in the app, so people recognise songs at a glance.

## Web source (behavior reference)

| Web | Behavior |
|---|---|
| `FortniteFestivalWeb/src/pages/rivals/components/RivalRow.tsx` (`RivalRow`) | Hub rival row: avatar, name, ahead/behind counts. |
| `FortniteFestivalWeb/src/pages/rivals/components/RivalSongRow.tsx` (`RivalSongRow`) | Song comparison row on `RivalDetailPage`, `RivalryPage` and the first-run `RivalsDetailDemo`: 40 px album art (purple placeholder), title/artist, instrument glyph; then "You #rank score" · green/red/neutral rank-delta and score-delta chips · "Them #rank score". |

## Rules

1. **R1. One row component per kind, shared by every surface.** Apple: hub rows are `RivalRowContent`, song rows are `RivalSongRowContent` (Rival Detail, Rivalry, Duo `RivalDualCategoryCard`, so iPhone, iPad, Duo and Mac). Android: `RivalRow` / `RivalSongRow`. Windows: `RivalRowView` / `RivalSongRowView`. A page never draws its own variant.
2. **R2. One status pill.** Standing is drawn as a capsule: the status tint at 16 % fill, a 40 % 1 pt stroke and semibold caption text in the readable tint (red text uses the lighter `RivalStatusText.red`, ≈ 6.5:1 on the dark cards). Apple `RivalStatusPill`, Android `RivalPill`, Windows `FSTRivalPillStyle`. Green is `BrandTokens.statusGreen`, red `BrandTokens.statusRed`, neutral the primary text colour. Every pill carries text, so colour is never the only signal (HIG Color: "Avoid relying solely on color … convey it another way, like text labels", **should**).
3. **R3. Song rows: "#rank Name" pills (agent decision #558; Windows #603).** The bottom line of a song comparison row is two pills, "#12 Player" and "#13 Rival": the leader's green, the trailer's red, both neutral when tied. The trailing ▲/▼ rank-delta badge stays (Windows: the unsigned rank gap under a Segoe Fluent arrow, "=" when tied). Apple since #558 and Windows since #603, on every song-row surface; no score or score-delta chips. [Agent decision below](#agent-decision-apple-song-row-pills-558); [Windows decision](#agent-decision-windows-song-rows-and-one-card-603).
4. **R4. Album art leads every song row.** The row's leading column shows the song's art through the shared bounded-cache `ArtworkTile` at the native song-row size (Apple 44 pt; Android 48 dp; web 40 px), with the standard placeholder when there is none; it is decorative and hidden from accessibility (HIG Images). The instrument icon sits directly below the art; the column is vertically centred in the row, so art alone sits in the middle (owner, #558). The art comes from the catalogue the page already loads (`songsById`); no new reads.
5. **R5. One accessibility element per row, wrapping at large sizes.** A song row reads as one element: "Song, you rank 12, Rival ranks 13, you lead" (or "Rival leads", "tied"), with a 44 pt minimum height. Pills sit on one line when they fit, one per line otherwise, and at accessibility text sizes each pill wraps instead of truncating (HIG Typography: "Keep text truncation to a minimum as font size increases", **should**).

6. **R6. One card per rival list (owner #603).** A list of rival rows or song rows (the hub's section cards, All Rivals, Rival Detail's category cards and the Rivalry sub-page) draws its rows in one card with hairline separators, like iOS's grouped `FestivalGlassSection` and the #543 boards ([leaderboard-row](leaderboard-row.md) R10), never a card per row. Rows keep their own focus/press target and spoken name; View All, sort and selection (All Rivals' wide split) are unchanged. Windows: `ItemsRepeater` cards use `RowSeparators` (a `RowSeparator` hairline in the row template); the virtualized `ListView` lists (All Rivals, Rivalry) draw the card through `GroupedRows.ApplyToContainer` slices and fade in as one card (`FadeIn.Together`, [load-transition](load-transition.md) R11).

## Canonical implementation

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Status pill (R2) | `apple/Sources/FestivalUI/Features/Rivals/RivalsSupport.swift` `RivalStatusPill`, `RivalStatusText` | `android/app/src/main/java/com/festivalscoretracker/android/ui/rivals/RivalComponents.kt` `RivalPill` | `windows/Festival.App/Controls/RivalsResources.xaml` `FSTRivalPillStyle` |
| Hub row (R1) | `RivalsSupport.swift` `RivalRowContent` | `RivalComponents.kt` `RivalRow` | `windows/Festival.App/Controls/RivalRowView.xaml` |
| Song row (R1, R3–R5) | `RivalsSupport.swift` `RivalSongRowContent` (standing `RivalSongStanding`) | `RivalComponents.kt` `RivalSongRow` | `windows/Festival.App/Controls/RivalSongRowView.xaml`; text and standing `windows/Festival.Core/ViewModels/RivalDetailViewModels.cs` `RivalSongItem` (`PlayerPillText`, `RivalOutcome`, `RankGapText`, `AccessibleName`); tints `Controls/RivalsUi.cs` |
| One card per list (R6) | `FestivalGlassSection` rows in `RivalsScreen`, `AllRivalsScreen`, `RivalDetailScreen`, `RivalryScreen` | — | `windows/Festival.App/Controls/RowSeparators.cs` (repeater cards), `Controls/GroupedRows.cs` `ApplyToContainer` (ListViews) |

Apple consumers: `RivalsScreen` sections, `AllRivalsScreen` and the First Run rivals hub demo (hub rows), `RivalDetailScreen.songRow`, `RivalryScreen.songRow`, `RivalsDualSource.swift` `RivalDualCategoryCard` (song rows). Not a consumer: the First Run rivals demo card (`FirstRunRivalsDetailCard`), a static illustration with its own art and rank labels.

Windows consumers: `Pages/RivalsPage.xaml` section cards (hub rows, R6 hairlines; also Compete's rivals beside Compete), `Pages/AllRivalsPage.xaml` (hub rows in one grouped `ListView` card), `Pages/RivalDetailPage.xaml` category cards and `Pages/RivalryPage.xaml` (song rows; one card each). Guards: `RivalsViewModelTests` (pill text, standing, rank gap, spoken name), `RivalsCardMarkupTests` (one card, hairlines, one song-row layout), journey `tools/windows/journeys/a11y-rivals-cards.json` (`ui_ci.py` `rivals-cards`, normal and text-225).

### Agent decision: Apple song row pills (#558)

Agent decision (#558, 2026-10-09, owner may override with `/choose`). The owner asked: "Bottom row should be the red and green pills from other rivals cards. Album art should appear in these cards too- vertically centered if the only thing, above instrument icon if both present."

| Option | What you'd see | Guidance (strength) | Web / pattern precedent | Trade-offs |
|---|---|---|---|---|
| **A. "#rank Name" pills (chosen)** | "#12 You" and "#13 Rival" as hub-style capsules, the leader green, the trailer red, neutral when tied; ▲/▼ badge kept. | HIG Color "Avoid relying solely on color" (**should**): text in every pill plus the arrow badge and a spoken leader. | The hub rows' pills (R2), the exact pills the owner points at. | Least churn; keeps the wide iPad/Mac layout. |
| B. Web/Android/Windows delta chips | "You #rank" · rank-delta and score-delta chips · "Rival #rank", no trailing badge. | Same guidance. | Web `RivalSongRow`, Android `RivalSongRow`. | Not the "pills from other rivals cards"; rebuilds the row and adds scores. |

**Chose A.** No platform **must** applies; the owner's explicit words outrank web parity in the precedence table, and A reuses the one shared pill (R2) rather than adding chips. `RivalSongRowTests` pins the tints, art placement, spoken label and AX stacking.

### Agent decision: Windows song rows and one card (#603)

Agent decision (#603, 2026-10-10, owner may override with `/choose`). The owner (Android report, Windows checked as the same feature): "Compete: Rivals cards need consolidation into a single card like iOS / Rival page: Cards have web-style which is good start but I think they should align to the iOS design / Sub-page also needs consolidation to one card." Windows had the same gaps: All Rivals and Rivalry drew a card per row, the hub and Rival Detail cards had no separators, and song rows were web-style (compact "#you you · #them rival" text plus one pill; Rivalry added score and score-delta chips).

| Option | What you'd see | Guidance (strength) | Web / pattern precedent | Trade-offs |
|---|---|---|---|---|
| **A. iOS row everywhere, one card per list (chosen)** | Every song row: art over the instrument icon, title, artist, "#12 You" / "#13 Rival" pills, ▲/▼ rank gap; each list one card with hairlines. | Fluent/WinUI: "Vertical list → `ListView`" and `DividerStrokeColorDefaultBrush` for "separator lines" (winui-design); keep the platform collection and virtualisation. | iOS `RivalSongRowContent` (R3), #543 grouped boards (`GroupedRows`). | Rivalry loses the score columns; its sorts are rank-based, so nothing it sorts by disappears. |
| B. One card, keep the web full row on Rivalry | Cards consolidated; Rivalry keeps "You #rank score" · chips · "Rival #rank score". | Same. | Web `RivalSongRow`. | Two song-row layouts (breaks R1) and not "align to the iOS design". |

**Chose A.** No platform **must** applies; the owner's explicit words ("align to the iOS design", "consolidation to one card") outrank web parity, and A keeps one row component (R1) and reuses the #543 grouping rather than adding a card style.
## Known debt

| Debt | Breaks | Plan |
|---|---|---|
| Android rival lists still draw a card per row and web-style song rows | R3, R6 on Android | #603's Android branch |

## Guards (`tools/pattern_guard.py`)

None yet.
